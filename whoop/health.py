"""Local sleep, strain and recovery estimates.

These are NOT WHOOP's scores. WHOOP's recovery, strain and sleep staging are
proprietary cloud algorithms that are not published and cannot be reproduced
from the strap alone. What is here instead:

  * Sleep - a transparent actigraphy + heart-rate-drop detector. It reports
    duration and continuity only. Sleep STAGING (light/deep/REM) is deliberately
    not implemented: it needs validated HRV features and a trained model, and
    guessing it would fabricate medical-looking output. The band's own
    sleep_state byte is a wake/sleep envelope whose value mapping is unverified,
    so it is reported but never used to decide sleep.
  * Strain - Banister TRIMP (see metrics.trimp) mapped through a documented
    saturating curve onto a local 0-21 scale.
  * Recovery - a baseline-relative composite of lnRMSSD, resting HR and sleep
    duration. It returns no score at all until a personal baseline exists,
    because a recovery number without a baseline is meaningless.
  * Stress - how far current lnRMSSD sits below the personal awake-quiet norm,
    in standard deviations, clipped to 0-3. Acute stress withdraws vagal tone,
    which lowers RMSSD. It is scored against an AWAKE baseline, never the sleep
    one: lnRMSSD is systematically higher in sleep, so comparing a daytime
    window against a sleep norm would read as stressed every waking hour.
  * Sleep coach - a bedtime worked back from your wake time and tonight's sleep
    need. Need = stated base need + accumulated sleep debt (the running
    shortfall against your need, as in Kitamura et al. 2016, Scientific Reports,
    which estimates individual optimal sleep and cumulative debt from
    actigraphy) + a coaching allowance for tomorrow's plan. The debt addition
    is capped so one bad week cannot demand an impossible night.
"""

import math
import statistics
from dataclasses import dataclass

from .records import V18Sample

QUIET_ACCEL_G = 0.08
MIN_SLEEP_S = 1800
SLEEP_GAP_TOLERANCE_S = 300
HR_DROP_BPM = 5.0

# TRIMP at which the local strain curve reaches 21*(1-1/e) = 13.3.
STRAIN_SCALE_TRIMP = 150.0
STRAIN_MAX = 21.0

MIN_BASELINE_DAYS = 7
RECOVERY_WEIGHTS = {"hrv": 0.5, "rhr": 0.2, "sleep": 0.3}

STRESS_MAX = 3.0
STRESS_ELEVATED_SD = 1.0
STRESS_HIGH_SD = 2.0

# Sleep coach defaults. The debt window and cap are coaching choices, not
# measurements; 7-9 h is the adult range (Hirshkowitz et al. 2015, Sleep Health).
SLEEP_DEBT_WINDOW_NIGHTS = 14
SLEEP_DEBT_CAP_H = 2.0
SLEEP_LATENCY_H = 0.25
SLEEP_EFFICIENCY = 0.90
TOMORROW_EXTRA_H = {"hard": 0.5, "easy": 0.0, "rest": 0.25}


@dataclass
class SleepPeriod:
    start_unix: int
    end_unix: int
    quiet_fraction: float
    mean_hr: float | None

    @property
    def duration_s(self) -> int:
        return self.end_unix - self.start_unix + 1

    @property
    def hours(self) -> float:
        return self.duration_s / 3600.0


def _close_gaps(samples: list[V18Sample], quiet: list[bool], max_gap_s: int) -> list[bool]:
    """Fill brief movement inside otherwise-quiet stretches.

    Real sleep contains turning and brief awakenings; without closing, one
    restless minute fragments a whole night into unusable pieces.
    """
    filled = list(quiet)
    i = 0
    n = len(samples)
    while i < n:
        if filled[i]:
            i += 1
            continue
        start = i
        while i < n and not filled[i]:
            i += 1
        end = i
        bounded = start > 0 and end < n and filled[start - 1] and filled[end]
        span = samples[end - 1].unix - samples[start].unix + 1
        if bounded and span <= max_gap_s:
            for j in range(start, end):
                filled[j] = True
    return filled


def detect_sleep(
    samples: list[V18Sample],
    quiet_accel_g: float = QUIET_ACCEL_G,
    min_sleep_s: int = MIN_SLEEP_S,
    gap_tolerance_s: int = SLEEP_GAP_TOLERANCE_S,
    hr_drop_bpm: float = HR_DROP_BPM,
) -> list[SleepPeriod]:
    """Sustained-quiet periods confirmed by a heart-rate drop.

    Motion alone is not enough - sitting still at a desk is not sleep - so a
    candidate period must also show HR below the session's active median by
    `hr_drop_bpm`. With no active seconds to compare against, the period is
    rejected rather than assumed.
    """
    ordered = sorted(samples, key=lambda s: s.unix)
    if not ordered:
        return []

    quiet = [
        s.dynamic_accel_g is not None and s.dynamic_accel_g <= quiet_accel_g
        for s in ordered
    ]
    active_hrs = [
        float(s.heart_rate) for s, q in zip(ordered, quiet) if not q and s.wearing
    ]
    if not active_hrs:
        return []
    active_median = statistics.median(active_hrs)

    closed = _close_gaps(ordered, quiet, gap_tolerance_s)

    periods: list[SleepPeriod] = []
    i = 0
    n = len(ordered)
    while i < n:
        if not closed[i]:
            i += 1
            continue
        start = i
        while i < n and closed[i]:
            i += 1
        end = i
        run = ordered[start:end]
        duration = run[-1].unix - run[0].unix + 1
        if duration < min_sleep_s:
            continue
        run_hrs = [float(s.heart_rate) for s in run if s.wearing]
        if not run_hrs or statistics.median(run_hrs) > active_median - hr_drop_bpm:
            continue
        periods.append(
            SleepPeriod(
                start_unix=run[0].unix,
                end_unix=run[-1].unix,
                quiet_fraction=sum(quiet[start:end]) / len(run),
                mean_hr=statistics.mean(run_hrs),
            )
        )
    return periods


def total_sleep_hours(periods: list[SleepPeriod]) -> float:
    return sum(p.hours for p in periods)


def strain_score(trimp_value: float | None) -> float | None:
    """Map TRIMP onto a local 0-21 scale.

    The TRIMP input is Banister's published formula; this 0-21 mapping is our
    own saturating curve, chosen so a hard session approaches but never exceeds
    21. It is not WHOOP's proprietary strain and the numbers are not comparable.
    """
    if trimp_value is None:
        return None
    if trimp_value < 0:
        raise ValueError("TRIMP cannot be negative")
    return STRAIN_MAX * (1.0 - math.exp(-trimp_value / STRAIN_SCALE_TRIMP))


def strain_label(score: float | None) -> str:
    if score is None:
        return "unknown"
    if score < 10:
        return "light"
    if score < 14:
        return "moderate"
    if score < 18:
        return "high"
    return "all-out"


@dataclass
class Baseline:
    """Personal norms. A recovery score is only meaningful relative to these."""

    ln_rmssd_mean: float
    ln_rmssd_sd: float
    rhr_mean: float
    rhr_sd: float
    days: int

    @classmethod
    def from_daily(cls, ln_rmssd: list[float], rhr: list[float]) -> "Baseline | None":
        if len(ln_rmssd) < 2 or len(rhr) < 2:
            return None
        return cls(
            ln_rmssd_mean=statistics.mean(ln_rmssd),
            ln_rmssd_sd=statistics.stdev(ln_rmssd),
            rhr_mean=statistics.mean(rhr),
            rhr_sd=statistics.stdev(rhr),
            days=min(len(ln_rmssd), len(rhr)),
        )


@dataclass
class RecoveryResult:
    score: float | None
    reason: str | None
    hrv_component: float | None = None
    rhr_component: float | None = None
    sleep_component: float | None = None

    @property
    def band(self) -> str:
        if self.score is None:
            return "unavailable"
        if self.score >= 67:
            return "green"
        if self.score >= 34:
            return "yellow"
        return "red"


def _logistic(z: float) -> float:
    return 100.0 / (1.0 + math.exp(-z))


def recovery_score(
    ln_rmssd: float | None,
    rhr: float | None,
    sleep_hours: float | None,
    sleep_need_hours: float | None,
    baseline: Baseline | None,
) -> RecoveryResult:
    """Baseline-relative 0-100 recovery estimate. Not WHOOP's recovery.

    Higher HRV than your own norm and lower resting HR than your own norm both
    push the score up; sleep is scored against your stated need. Components are
    renormalised over whatever is actually available, and a missing baseline
    produces no score rather than a fabricated one.
    """
    if baseline is None or baseline.days < MIN_BASELINE_DAYS:
        return RecoveryResult(None, f"needs at least {MIN_BASELINE_DAYS} days of baseline")
    if ln_rmssd is None or rhr is None:
        return RecoveryResult(None, "needs HRV and resting HR from a rest/sleep window")

    hrv_z = (
        (ln_rmssd - baseline.ln_rmssd_mean) / baseline.ln_rmssd_sd
        if baseline.ln_rmssd_sd > 0
        else 0.0
    )
    rhr_z = (
        -(rhr - baseline.rhr_mean) / baseline.rhr_sd if baseline.rhr_sd > 0 else 0.0
    )
    components = {"hrv": _logistic(hrv_z), "rhr": _logistic(rhr_z)}

    if sleep_hours is not None and sleep_need_hours and sleep_need_hours > 0:
        components["sleep"] = 100.0 * min(sleep_hours / sleep_need_hours, 1.0)

    total_weight = sum(RECOVERY_WEIGHTS[k] for k in components)
    score = sum(components[k] * RECOVERY_WEIGHTS[k] for k in components) / total_weight
    return RecoveryResult(
        score=round(score, 1),
        reason=None,
        hrv_component=round(components["hrv"], 1),
        rhr_component=round(components["rhr"], 1),
        sleep_component=round(components["sleep"], 1) if "sleep" in components else None,
    )


@dataclass
class StressResult:
    index: float | None
    reason: str | None

    @property
    def band(self) -> str:
        if self.index is None:
            return "unavailable"
        if self.index < STRESS_ELEVATED_SD:
            return "low"
        if self.index < STRESS_HIGH_SD:
            return "elevated"
        return "high"


def stress_score(ln_rmssd: float | None, baseline: Baseline | None) -> StressResult:
    """Standard deviations of lnRMSSD below the personal norm, clipped to 0-3.

    Vagal withdrawal is the published acute-stress marker, so a window sitting
    below its own awake-quiet norm scores higher. At or above the norm the index
    is 0 - HRV above your normal is not "negative stress".

    `baseline` MUST be built from awake-quiet windows. Exercise also collapses
    RMSSD, for metabolic rather than psychological reasons, so the caller must
    only pass HRV from a verified-quiet run (see metrics.resting_hrv).
    """
    if baseline is None or baseline.days < MIN_BASELINE_DAYS:
        return StressResult(None, f"needs at least {MIN_BASELINE_DAYS} days of awake-quiet baseline")
    if ln_rmssd is None:
        return StressResult(None, "needs HRV from a verified-quiet window")
    if baseline.ln_rmssd_sd <= 0:
        return StressResult(None, "baseline has no HRV variation to scale against")

    deviation = (baseline.ln_rmssd_mean - ln_rmssd) / baseline.ln_rmssd_sd
    return StressResult(index=round(max(0.0, min(STRESS_MAX, deviation)), 2), reason=None)


@dataclass
class SleepCoach:
    nights: int
    debt_h: float | None
    need_h: float
    time_in_bed_h: float
    wake_min: int | None
    bedtime_min: int | None

    @property
    def reason(self) -> str | None:
        if self.wake_min is None:
            return "set a wake time to get a suggested bedtime"
        return None


def sleep_debt(night_sleep_h: list[float], base_need_h: float) -> float:
    """Running shortfall against need over the recent nights, floored at zero.

    A night longer than need repays debt; the floor stops surplus sleep from
    banking credit against future short nights.
    """
    debt = 0.0
    for actual in night_sleep_h[-SLEEP_DEBT_WINDOW_NIGHTS:]:
        debt = max(0.0, debt + base_need_h - actual)
    return debt


def sleep_coach(
    night_sleep_h: list[float],
    wake_min: int | None,
    base_need_h: float = 8.0,
    tomorrow: str = "easy",
    efficiency: float = SLEEP_EFFICIENCY,
) -> SleepCoach:
    """Suggested bedtime from wake time, sleep debt and tomorrow's plan.

    Time in bed exceeds sleep need by assumed latency and efficiency, because
    time in bed is not time asleep. Both are stated assumptions (90% efficiency,
    15 min latency), not measurements - this strap cannot observe either.
    `bedtime_min` may be negative: it then means the previous evening.
    """
    if tomorrow not in TOMORROW_EXTRA_H:
        raise ValueError(f"tomorrow must be one of {sorted(TOMORROW_EXTRA_H)}")
    if base_need_h <= 0:
        raise ValueError("base_need_h must be positive")
    if not 0.0 < efficiency <= 1.0:
        raise ValueError("efficiency must be in (0, 1]")
    recent = night_sleep_h[-SLEEP_DEBT_WINDOW_NIGHTS:]
    debt = sleep_debt(recent, base_need_h) if recent else None
    need = base_need_h + TOMORROW_EXTRA_H[tomorrow] + (
        min(debt, SLEEP_DEBT_CAP_H) if debt is not None else 0.0
    )
    in_bed = need / efficiency + SLEEP_LATENCY_H
    bedtime = None if wake_min is None else round(wake_min - in_bed * 60.0)
    return SleepCoach(
        nights=len(recent),
        debt_h=round(debt, 2) if debt is not None else None,
        need_h=round(need, 2),
        time_in_bed_h=round(in_bed, 2),
        wake_min=wake_min,
        bedtime_min=bedtime,
    )


def clock_label(minutes: int) -> str:
    """24-hour clock label; negative minutes wrap to the previous day."""
    hours, mins = divmod(minutes % 1440, 60)
    return f"{hours:02d}:{mins:02d}"
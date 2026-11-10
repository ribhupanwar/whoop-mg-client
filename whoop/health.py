"""Local sleep, strain and recovery estimates.

These are NOT WHOOP's scores. WHOOP's recovery, strain and sleep staging are
proprietary cloud algorithms that are not published and cannot be reproduced
from the strap alone. What is here instead:

  * Sleep - a transparent actigraphy + heart-rate-drop detector. It reports
    duration and continuity, and hands the window to `sleep_stage.py` for a
    four-class estimate (awake/light/deep/REM) from HR, its variability, wrist
    movement and R-R breathing regularity. That hypnogram is an approximation,
    never PSG-validated, and refuses below 50 % HR coverage instead of
    collapsing to all-light. The band's own sleep_state byte is a wake/sleep
    envelope whose value mapping is unverified, so it is reported but never
    used to decide sleep or a stage.
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
  * Respiratory rate - an RSA estimate from R-R timing, because the gen5 v18
    wire carries no respiration ADC. It is a local estimate, not a chest-band
    measurement.
  * SpO2 - only the band's own tri-mode candidate byte, surfaced as a
    candidate. Cross-device validation is split, so it is never a clinical
    percentage and never feeds a score.
"""

import math
import statistics
from dataclasses import dataclass

from .records import (
    MAX_RR_MS,
    MIN_RR_MS,
    SPO2_CANDIDATE_MAX,
    SPO2_CANDIDATE_MIN,
    V18Sample,
)

QUIET_ACCEL_G = 0.08
MIN_SLEEP_S = 1800
SLEEP_GAP_TOLERANCE_S = 300
HR_DROP_BPM = 5.0

# Respiratory rate from R-R via respiratory sinus arrhythmia. WHOOP5 v18 has
# no respiration ADC: the only signal is how beat-to-beat timing modulates with
# breathing. These are estimator constants, not measurements.
RSA_RESAMPLE_HZ = 4.0
RSA_DETREND_WINDOW_S = 8.0
RSA_MIN_PEAK_DISTANCE_S = 2.5
RSA_WINDOW_S = 300.0
RSA_GAP_TOLERANCE_S = 3.0
RSA_MIN_BREATH_INTERVAL_S = 2.5  # 24 breaths/min
RSA_MAX_BREATH_INTERVAL_S = 10.0  # 6 breaths/min
RSA_INTERVAL_BAND = 0.4
RESP_PLAUSIBLE_MIN_BPM = 8.0
RESP_PLAUSIBLE_MAX_BPM = 25.0
MIN_RSA_BEATS = 30

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
    # Movement bursts closed inside the period: actigraphy wake events, not
    # verified awakenings. Every raw-movement run inside a closed period was
    # gap-filled, so counting its rising edges counts the bursts.
    wake_events: int = 0

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
                wake_events=sum(
                    1 for j in range(start + 1, end) if not quiet[j] and quiet[j - 1]
                ),
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
class RespRate:
    breaths_per_min: float | None
    reason: str | None
    beats: int
    windows: int

    @property
    def available(self) -> bool:
        return self.breaths_per_min is not None


def _rr_segments(samples: list[V18Sample]) -> list[list[tuple[int, int]]]:
    """Split the beat stream wherever R-R is missing or the record clock jumps.

    Cumulative beat time cannot represent a dropout: stitching the two sides
    would put a step into the tachogram that the peak picker reads as a breath.
    Short gaps are tolerated because a single missed beat does not move the
    estimate, but a multi-second gap starts a new segment.
    """
    ordered = sorted(samples, key=lambda s: s.unix)
    segments: list[list[tuple[int, int]]] = []
    current: list[tuple[int, int]] = []
    last_unix: int | None = None
    last_span_s = 0.0
    for sample in ordered:
        rr = [v for v in sample.rr_intervals_ms if MIN_RR_MS <= v <= MAX_RR_MS]
        if not rr:
            continue
        # On a real capture the wall-clock step exceeds the previous record's
        # R-R span by ~0.16 s. A multi-second excess is a dropout, not timing
        # noise, and stitching across it would fabricate a breath.
        if (
            last_unix is not None
            and sample.unix - last_unix - last_span_s > RSA_GAP_TOLERANCE_S
        ):
            if current:
                segments.append(current)
            current = []
        current.extend((sample.unix, value) for value in rr)
        last_unix = sample.unix
        last_span_s = sum(rr) / 1000.0
    if current:
        segments.append(current)
    return segments


def _resample_beat_times(times: list[float], values: list[int]) -> list[float]:
    dt = 1.0 / RSA_RESAMPLE_HZ
    count = int(times[-1] / dt) + 1
    grid: list[float] = []
    seg = 0
    for i in range(count):
        t = i * dt
        while seg < len(times) - 2 and times[seg + 1] < t:
            seg += 1
        t0, t1 = times[seg], times[seg + 1]
        v0, v1 = values[seg], values[seg + 1]
        if t1 <= t0:
            grid.append(float(v0))
        else:
            fraction = min(max((t - t0) / (t1 - t0), 0.0), 1.0)
            grid.append(v0 + fraction * (v1 - v0))
    return grid


def _detrend(values: list[float]) -> list[float]:
    half = max(1, round(RSA_DETREND_WINDOW_S * RSA_RESAMPLE_HZ / 2.0))
    out: list[float] = []
    for i in range(len(values)):
        lo = max(0, i - half)
        hi = min(len(values) - 1, i + half)
        window = values[lo : hi + 1]
        out.append(values[i] - sum(window) / len(window))
    return out


def _find_peaks(values: list[float], min_distance: int) -> list[int]:
    """Local maxima above zero, thinned greedily by height like scipy's picker."""
    candidates = [
        i
        for i in range(1, len(values) - 1)
        if values[i] > 0 and values[i] > values[i - 1] and values[i] >= values[i + 1]
    ]
    if not candidates:
        return []
    ordered = sorted(candidates, key=lambda i: (-values[i], i))
    kept: list[int] = []
    for i in ordered:
        if all(abs(i - j) >= min_distance for j in kept):
            kept.append(i)
    return sorted(kept)


def _window_rates(detrended: list[float]) -> list[float]:
    min_distance = max(2, round(RSA_MIN_PEAK_DISTANCE_S * RSA_RESAMPLE_HZ))
    window_samples = max(
        min_distance * 3, round(RSA_WINDOW_S * RSA_RESAMPLE_HZ)
    )
    dt = 1.0 / RSA_RESAMPLE_HZ
    rates: list[float] = []
    for start in range(0, len(detrended), window_samples):
        window = detrended[start : start + window_samples]
        if len(window) < min_distance * 3:
            continue
        peaks = _find_peaks(window, min_distance)
        if len(peaks) < 3:
            continue
        intervals = [
            (peaks[i] - peaks[i - 1]) * dt
            for i in range(1, len(peaks))
        ]
        intervals = [
            iv
            for iv in intervals
            if RSA_MIN_BREATH_INTERVAL_S <= iv <= RSA_MAX_BREATH_INTERVAL_S
        ]
        if len(intervals) < 2:
            continue
        median = statistics.median(intervals)
        if median <= 0:
            continue
        anchored = [iv for iv in intervals if abs(iv - median) <= RSA_INTERVAL_BAND * median]
        mean_interval = statistics.mean(anchored) if anchored else median
        if mean_interval > 0:
            rates.append(60.0 / mean_interval)
    return rates


def resp_rate_from_rr(samples: list[V18Sample]) -> RespRate:
    """Estimate sleeping respiratory rate from R-R via RSA.

    This recovers the breathing modulation of beat-to-beat timing, which tracks
    but does not equal a chest-band or capnography rate. It is an on-device
    estimate: the v18 wire carries no respiration ADC. Requires a still or
    sleep window with a continuous R-R train; otherwise returns no value.
    """
    segments = _rr_segments(samples)
    total_beats = sum(len(segment) for segment in segments)
    if total_beats < MIN_RSA_BEATS:
        return RespRate(
            None,
            f"needs at least {MIN_RSA_BEATS} R-R beats from a still or sleep window",
            total_beats,
            0,
        )

    rates: list[float] = []
    for segment in segments:
        if len(segment) < MIN_RSA_BEATS:
            continue
        times: list[float] = []
        acc = 0.0
        for _, rr in segment:
            acc += rr / 1000.0
            times.append(acc)
        if times[-1] < RSA_WINDOW_S / 2.0:
            continue
        grid = _resample_beat_times(times, [rr for _, rr in segment])
        if len(grid) < 8:
            continue
        detrended = _detrend(grid)
        if statistics.pstdev(detrended) <= 1e-9:
            continue
        rates.extend(_window_rates(detrended))

    if not rates:
        return RespRate(
            None,
            "no usable RSA peak train - needs a continuous still or sleep R-R window",
            total_beats,
            0,
        )
    median = statistics.median(rates)
    if not (RESP_PLAUSIBLE_MIN_BPM <= median <= RESP_PLAUSIBLE_MAX_BPM):
        return RespRate(
            None,
            f"RSA estimate {median:.1f}/min fell outside the plausible"
            f" {RESP_PLAUSIBLE_MIN_BPM:.0f}-{RESP_PLAUSIBLE_MAX_BPM:.0f} band",
            total_beats,
            len(rates),
        )
    return RespRate(round(median, 1), None, total_beats, len(rates))


@dataclass
class Spo2Candidate:
    pct: float | None
    readings: int
    saturated: int
    diagnostic: int
    reason: str | None

    @property
    def available(self) -> bool:
        return self.pct is not None


def spo2_candidate_summary(samples: list[V18Sample]) -> Spo2Candidate:
    """Mean of the band's in-band SpO2 candidates, or no value at all.

    This is NOT a validated SpO2. The band banks one candidate byte per second
    only while it records sleep; the percentage range is 70-100, bit-7 values
    are saturation sentinels and other nonzero values are diagnostic codes.
    Cross-device validation is split, so the value is presented as a candidate
    and never feeds a score.
    """
    in_band = [
        s.spo2_candidate_pct
        for s in samples
        if s.spo2_candidate_pct is not None
        and SPO2_CANDIDATE_MIN <= s.spo2_candidate_pct <= SPO2_CANDIDATE_MAX
    ]
    saturated = sum(1 for s in samples if s.spo2_candidate_status == "saturated")
    diagnostic = sum(1 for s in samples if s.spo2_candidate_status == "diagnostic")
    if not in_band:
        return Spo2Candidate(
            None,
            0,
            saturated,
            diagnostic,
            "the strap banked no in-band (70-100) candidate - no SpO2 % is produced",
        )
    return Spo2Candidate(
        round(statistics.mean(in_band), 1),
        len(in_band),
        saturated,
        diagnostic,
        None,
    )


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
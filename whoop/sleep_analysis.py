"""Sleep analysis: a local performance composite from actigraphy and HRV.

NOT WHOOP's Sleep Performance or sleep staging. Every component is a
transparent local rule:

  * Hours vs. needed - sleep hours over the coach's need (base + sleep debt
    + tomorrow's allowance), capped at 100%.
  * Efficiency - duration-weighted quiet fraction of the detected periods.
    Actigraphy: sustained quiet is scored as asleep, movement as awake.
  * Wake events - movement bursts closed inside a period (see
    SleepPeriod.wake_events). These are actigraphy events, not verified
    awakenings.
  * Consistency - share of recorded nights whose bedtime AND wake time sit
    within +/-60 min of the personal medians. A local regularity rule, not
    WHOOP's consistency score and not the Phillips 2017 Sleep Regularity
    Index (which needs full-day epoch data we do not capture).
  * Sleep stress - lnRMSSD per 5-minute window scored against the SLEEP
    baseline (never the awake one: sleep lnRMSSD runs systematically higher).
    High >= 2 SD below the norm, medium >= 1 SD, matching health.stress_score.
    Unavailable until 7 sleep nights exist.
  * Performance - equal-weight mean of whichever components are available.
    WHOOP's weighting is proprietary; this is our own composite.

Light/deep/REM staging is deliberately absent: it needs validated HRV
features and a trained model, and guessing it would fabricate medical-looking
output.
"""

import statistics
from dataclasses import dataclass

from .health import (
    MIN_BASELINE_DAYS,
    STRESS_ELEVATED_SD,
    STRESS_HIGH_SD,
    Baseline,
    SleepPeriod,
    stress_score,
    total_sleep_hours,
)
from .metrics import hrv_from_rr
from .records import V18Sample

CONSISTENCY_TOLERANCE_MIN = 60
MIN_CONSISTENCY_NIGHTS = 2
STRESS_WINDOW_S = 300


def _minutes_of_day(unix: int) -> int:
    # UTC clock minutes. A fixed zone offset shifts every night equally, so
    # deviations from the median are timezone-independent.
    return (unix // 60) % 1440


def _circular_dev(a: int, b: int) -> int:
    d = abs(a - b) % 1440
    return min(d, 1440 - d)


def _circular_median(values: list[int]) -> int:
    return min(values, key=lambda c: sum(_circular_dev(c, v) for v in values))


def sleep_consistency(nights: list[tuple[int, int]]) -> tuple[float | None, int]:
    """(percent of nights within +/-60 min of median bed AND wake, nights used)."""
    usable = [(s, e) for s, e in nights if e > s]
    if len(usable) < MIN_CONSISTENCY_NIGHTS:
        return None, len(usable)
    beds = [_minutes_of_day(s) for s, _ in usable]
    wakes = [_minutes_of_day(e) for _, e in usable]
    bed_med = _circular_median(beds)
    wake_med = _circular_median(wakes)
    consistent = sum(
        1
        for b, w in zip(beds, wakes)
        if _circular_dev(b, bed_med) <= CONSISTENCY_TOLERANCE_MIN
        and _circular_dev(w, wake_med) <= CONSISTENCY_TOLERANCE_MIN
    )
    return round(100.0 * consistent / len(usable), 1), len(usable)


@dataclass
class SleepStressSplit:
    high_pct: float | None
    medium_pct: float | None
    low_pct: float | None
    windows: int
    reason: str | None


def sleep_stress_split(
    samples: list[V18Sample],
    periods: list[SleepPeriod],
    baseline: Baseline | None,
) -> SleepStressSplit:
    """Share of 5-minute sleep windows in each stress band, vs the sleep norm."""
    if baseline is None or baseline.days < MIN_BASELINE_DAYS:
        return SleepStressSplit(
            None, None, None, 0,
            f"needs at least {MIN_BASELINE_DAYS} sleep nights of baseline",
        )
    buckets: dict[tuple[int, int], list[float]] = {}
    for s in samples:
        if not s.wearing or not s.rr_intervals_ms:
            continue
        for pi, p in enumerate(periods):
            if p.start_unix <= s.unix <= p.end_unix:
                key = (pi, (s.unix - p.start_unix) // STRESS_WINDOW_S)
                buckets.setdefault(key, []).extend(float(rr) for rr in s.rr_intervals_ms)
                break
    bands = {"high": 0, "medium": 0, "low": 0}
    scored = 0
    for rr in buckets.values():
        result = stress_score(hrv_from_rr(rr).ln_rmssd, baseline)
        if result.index is None:
            continue
        scored += 1
        if result.index >= STRESS_HIGH_SD:
            bands["high"] += 1
        elif result.index >= STRESS_ELEVATED_SD:
            bands["medium"] += 1
        else:
            bands["low"] += 1
    if not scored:
        return SleepStressSplit(None, None, None, 0, "no R-R beats in the sleep windows")
    return SleepStressSplit(
        high_pct=round(100.0 * bands["high"] / scored, 1),
        medium_pct=round(100.0 * bands["medium"] / scored, 1),
        low_pct=round(100.0 * bands["low"] / scored, 1),
        windows=scored,
        reason=None,
    )


@dataclass
class SleepAnalysis:
    hours: float
    need_h: float
    hours_vs_needed_pct: float
    efficiency_pct: float
    wake_events: int
    consistency_pct: float | None
    consistency_nights: int
    stress: SleepStressSplit
    performance_pct: float | None


def analyze_sleep(
    samples: list[V18Sample],
    periods: list[SleepPeriod],
    need_h: float,
    nights: list[tuple[int, int]],
    sleep_baseline: Baseline | None,
) -> SleepAnalysis:
    """Composite for one capture's sleep. Caller passes only detected periods."""
    if not periods:
        raise ValueError("analyze_sleep needs at least one detected period")
    if need_h <= 0:
        raise ValueError("sleep need must be positive")
    hours = total_sleep_hours(periods)
    total_s = sum(p.duration_s for p in periods)
    efficiency = 100.0 * sum(
        p.quiet_fraction * p.duration_s for p in periods
    ) / total_s
    consistency_pct, consistency_nights = sleep_consistency(nights)
    stress = sleep_stress_split(samples, periods, sleep_baseline)

    components = [min(100.0, 100.0 * hours / need_h), efficiency]
    if consistency_pct is not None:
        components.append(consistency_pct)
    if stress.high_pct is not None:
        components.append(100.0 - stress.high_pct)
    return SleepAnalysis(
        hours=hours,
        need_h=need_h,
        hours_vs_needed_pct=round(components[0], 1),
        efficiency_pct=round(efficiency, 1),
        wake_events=sum(p.wake_events for p in periods),
        consistency_pct=consistency_pct,
        consistency_nights=consistency_nights,
        stress=stress,
        performance_pct=round(statistics.mean(components), 1),
    )
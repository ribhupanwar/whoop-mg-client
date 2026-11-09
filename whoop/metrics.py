"""Published physiological metrics computed locally from gen5 samples.

Standard, citable definitions - not WHOOP's proprietary scores. Every function
here is pure: samples in, numbers out, no I/O and no device dependency.

Provenance:
  * NN filtering - Malik et al. (1996), Heart rate variability standards of
    measurement, Circulation 93(5):1043-1065.
  * RMSSD / SDNN / pNN50 - the same Task Force standards.
  * TRIMP - Banister's training impulse, with the sex-specific exponential
    coefficients from Morton et al. (1990).
  * HR reserve - Karvonen (1957).
  * Age-predicted max HR - Tanaka et al. (2001), 208 - 0.7*age, which is more
    accurate than the older 220-age.
"""

import math
import statistics
from dataclasses import dataclass

from .records import MAX_RR_MS, MIN_RR_MS, V18Sample

# An interval this far from the local median is an ectopic beat or artefact.
NN_MAX_DEVIATION = 0.20
NN_REFERENCE_BEATS = 5

TRIMP_COEFFICIENTS = {"male": (0.64, 1.92), "female": (0.86, 1.67)}


def nn_intervals(
    rr_ms: list[float],
    max_deviation: float = NN_MAX_DEVIATION,
    reference_beats: int = NN_REFERENCE_BEATS,
) -> list[float]:
    """Normal-to-normal intervals, with ectopic beats and artefacts removed.

    The reference is a rolling median of recently accepted beats rather than
    the single preceding interval: an ectopic beat produces a short-then-long
    pair, and comparing against the preceding raw interval would also reject
    the normal recovery beat that follows it.

    The reference is seeded only once two consecutive beats agree, and is
    abandoned after a full window of consecutive rejections. Without both, a
    lone artefact becomes the permanent reference: rejected beats never enter
    the median, so every normal beat that follows is rejected too.
    """
    accepted: list[float] = []
    recent: list[float] = []
    candidate: float | None = None
    rejected_run = 0
    for value in rr_ms:
        if not (MIN_RR_MS <= value <= MAX_RR_MS):
            recent.clear()
            rejected_run = 0
            continue
        if not recent:
            if candidate is None:
                candidate = value
                continue
            midpoint = statistics.median([candidate, value])
            if abs(value - candidate) > max_deviation * midpoint:
                candidate = value
                continue
            accepted.append(candidate)
            recent.append(candidate)
            candidate = None
        else:
            reference = statistics.median(recent)
            if abs(value - reference) > max_deviation * reference:
                rejected_run += 1
                if rejected_run >= reference_beats:
                    recent.clear()
                    rejected_run = 0
                continue
        accepted.append(value)
        recent.append(value)
        rejected_run = 0
        if len(recent) > reference_beats:
            recent.pop(0)
    return accepted


def rmssd(nn_ms: list[float]) -> float | None:
    """Root mean square of successive differences, in ms."""
    if len(nn_ms) < 2:
        return None
    diffs = [b - a for a, b in zip(nn_ms, nn_ms[1:])]
    return math.sqrt(sum(d * d for d in diffs) / len(diffs))


def sdnn(nn_ms: list[float]) -> float | None:
    """Sample standard deviation of NN intervals, in ms."""
    if len(nn_ms) < 2:
        return None
    return statistics.stdev(nn_ms)


def pnn50(nn_ms: list[float]) -> float | None:
    """Percentage of successive differences exceeding 50 ms."""
    if len(nn_ms) < 2:
        return None
    diffs = [abs(b - a) for a, b in zip(nn_ms, nn_ms[1:])]
    return 100.0 * sum(1 for d in diffs if d > 50) / len(diffs)


@dataclass
class HrvResult:
    beats: int
    nn_beats: int
    rmssd_ms: float | None
    sdnn_ms: float | None
    pnn50_pct: float | None
    ln_rmssd: float | None
    mean_rr_ms: float | None

    @property
    def rejected_beats(self) -> int:
        return self.beats - self.nn_beats


def hrv_from_rr(rr_ms: list[float]) -> HrvResult:
    nn = nn_intervals(rr_ms)
    value = rmssd(nn)
    return HrvResult(
        beats=len(rr_ms),
        nn_beats=len(nn),
        rmssd_ms=value,
        sdnn_ms=sdnn(nn),
        pnn50_pct=pnn50(nn),
        # lnRMSSD is the baseline-relative form: RMSSD is right-skewed, so
        # comparing raw values across days overstates high readings.
        ln_rmssd=math.log(value) if value is not None and value > 0 else None,
        mean_rr_ms=statistics.mean(nn) if nn else None,
    )


def hrv(samples: list[V18Sample]) -> HrvResult:
    return hrv_from_rr([float(rr) for s in samples for rr in s.rr_intervals_ms])


def resting_hrv(
    samples: list[V18Sample],
    quiet_accel_g: float = 0.10,
    min_window_s: int = 60,
) -> tuple[HrvResult, int]:
    """HRV from the longest verified-quiet contiguous run, and its length.

    RMSSD is only interpretable at rest. Pooling a whole capture lets motion
    artefacts that happen to fall in a plausible R-R range inflate it, and the
    NN filter cannot catch those because they look like normal intervals. A
    run is never joined across a gap: beats either side of a gap are not
    successive, so the difference between them is not a heartbeat variation.
    """
    eligible = sorted(
        (
            s
            for s in samples
            if s.wearing
            and s.dynamic_accel_g is not None
            and s.dynamic_accel_g <= quiet_accel_g
        ),
        key=lambda s: s.unix,
    )
    runs = [r for r in _contiguous_runs(eligible) if len(r) >= min_window_s]
    if not runs:
        return hrv_from_rr([]), 0
    longest = max(runs, key=len)
    return hrv(longest), len(longest)


def age_predicted_max_hr(age: int) -> float:
    """Tanaka (2001): 208 - 0.7*age. A population estimate, not a measurement."""
    if age <= 0:
        raise ValueError("age must be positive")
    return 208.0 - 0.7 * age


def _contiguous_runs(samples: list[V18Sample]) -> list[list[V18Sample]]:
    runs: list[list[V18Sample]] = []
    current: list[V18Sample] = []
    for sample in samples:
        if current and sample.unix != current[-1].unix + 1:
            runs.append(current)
            current = []
        current.append(sample)
    if current:
        runs.append(current)
    return runs


def _min_rolling_mean(values: list[float], window: int) -> float | None:
    if len(values) < window or window <= 0:
        return None
    total = sum(values[:window])
    best = total
    for i in range(window, len(values)):
        total += values[i] - values[i - window]
        best = min(best, total)
    return best / window


def resting_heart_rate(
    samples: list[V18Sample],
    window_s: int = 60,
    quiet_accel_g: float = 0.10,
) -> float | None:
    """Lowest sustained heart rate across a quiet window, in bpm.

    Resting HR is the lowest sustained rate during sleep or sustained quiet,
    not the single lowest instantaneous reading - one artefact beat must not
    set the value. Seconds must be contiguous so a gap cannot masquerade as a
    sustained window, and motion must be measured, not assumed: a sample with
    no accelerometer reading is excluded rather than treated as quiet.
    """
    eligible = [
        s
        for s in samples
        if s.wearing
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
    ]
    eligible.sort(key=lambda s: s.unix)
    best: float | None = None
    for run in _contiguous_runs(eligible):
        value = _min_rolling_mean([float(s.heart_rate) for s in run], window_s)
        if value is not None and (best is None or value < best):
            best = value
    return best


def hr_reserve_ratio(hr: float, resting_hr: float, max_hr: float) -> float:
    """Karvonen HR reserve fraction, clipped to [0, 1]."""
    if max_hr <= resting_hr:
        raise ValueError("max_hr must exceed resting_hr")
    return max(0.0, min(1.0, (hr - resting_hr) / (max_hr - resting_hr)))


def trimp(
    samples: list[V18Sample],
    max_hr: float,
    resting_hr: float,
    sex: str = "male",
) -> float | None:
    """Banister's training impulse, integrated over observed seconds.

    TRIMP = duration_minutes * HRR * k1 * exp(k2 * HRR). Each sample stands for
    one second, so only observed seconds contribute - a capture with gaps
    yields a lower bound, not an estimate of the missing time.
    """
    if sex not in TRIMP_COEFFICIENTS:
        raise ValueError(f"sex must be one of {sorted(TRIMP_COEFFICIENTS)}")
    if max_hr <= resting_hr:
        raise ValueError("max_hr must exceed resting_hr")
    k1, k2 = TRIMP_COEFFICIENTS[sex]
    wearing = [s for s in samples if s.wearing]
    if not wearing:
        return None
    total = 0.0
    for sample in wearing:
        ratio = hr_reserve_ratio(float(sample.heart_rate), resting_hr, max_hr)
        total += (1.0 / 60.0) * ratio * k1 * math.exp(k2 * ratio)
    return total
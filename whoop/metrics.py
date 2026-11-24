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


def prefer_retransmitted_rr(
    candidate: list[int | float], over: list[int | float]
) -> bool:
    """Return True if candidate RR list should replace existing one during deduplication.

    Prefers the list with more plausible valid intervals (200..3000 ms).
    If valid counts are equal, prefers the list with fewer out-of-range words.
    """
    cand_valid = sum(1 for v in candidate if MIN_RR_MS <= v <= MAX_RR_MS)
    over_valid = sum(1 for v in over if MIN_RR_MS <= v <= MAX_RR_MS)
    if cand_valid != over_valid:
        return cand_valid > over_valid
    cand_bad = sum(1 for v in candidate if not (MIN_RR_MS <= v <= MAX_RR_MS))
    over_bad = sum(1 for v in over if not (MIN_RR_MS <= v <= MAX_RR_MS))
    return cand_bad < over_bad


def hrv(samples: list[V18Sample]) -> HrvResult:
    """Cardiovascular HRV (RMSSD) from a list of records.

    Offload can re-stream a second after reconnect. Deduplicate by second,
    keeping the record with the most valid intervals, before pulling the R-Rs.
    """
    unique_by_second: dict[int, V18Sample] = {}
    for s in samples:
        if s.unix in unique_by_second:
            if not prefer_retransmitted_rr(
                s.rr_intervals_ms, unique_by_second[s.unix].rr_intervals_ms
            ):
                continue
        unique_by_second[s.unix] = s
    ordered = sorted(unique_by_second.values(), key=lambda s: s.unix)
    return hrv_from_rr([float(rr) for s in ordered for rr in s.rr_intervals_ms])


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


def hrv_detailed_diagnostics(
    samples: list[V18Sample],
    sws_epochs: list[tuple[int, int]] | None = None,
) -> dict:
    """Detailed HRV diagnostics for provenance and audit trail."""
    unique_by_second: dict[int, V18Sample] = {}
    for s in samples:
        if s.unix in unique_by_second:
            if not prefer_retransmitted_rr(
                s.rr_intervals_ms, unique_by_second[s.unix].rr_intervals_ms
            ):
                continue
        unique_by_second[s.unix] = s
    ordered = sorted(unique_by_second.values(), key=lambda s: s.unix)

    sws_samples = ordered
    window_type = "ALL_VALID_SLEEP"
    if sws_epochs:
        filtered = [
            s for s in ordered
            if any(start <= s.unix <= end for start, end in sws_epochs)
        ]
        if filtered:
            sws_samples = filtered
            window_type = "SWS_DEEP_SLEEP"

    timestamp_gaps = 0
    if len(ordered) > 1:
        for i in range(1, len(ordered)):
            if ordered[i].unix > ordered[i - 1].unix + 1:
                timestamp_gaps += 1

    raw_beats = 0
    rejection_reasons = {
        "outOfPlausibleRange": 0,
        "ectopicDeviation": 0,
        "seedMismatch": 0,
    }

    runs = _contiguous_runs(sws_samples)
    all_nn: list[float] = []
    squared_diffs = 0.0
    pairs = 0

    for run in runs:
        previous: float | None = None
        recent: list[float] = []
        seed_candidate: float | None = None
        for s in run:
            rr = [float(val) for val in s.rr_intervals_ms]
            raw_beats += len(rr)
            if not rr:
                previous = None
                recent.clear()
                seed_candidate = None
                continue
            for val in rr:
                if not (MIN_RR_MS <= val <= MAX_RR_MS):
                    rejection_reasons["outOfPlausibleRange"] += 1
                    previous = None
                    recent.clear()
                    seed_candidate = None
                    continue
                if not recent:
                    if seed_candidate is None:
                        seed_candidate = val
                        continue
                    midpoint = statistics.median([seed_candidate, val])
                    if abs(val - seed_candidate) > NN_MAX_DEVIATION * midpoint:
                        rejection_reasons["seedMismatch"] += 1
                        seed_candidate = val
                        continue
                    all_nn.append(seed_candidate)
                    recent.append(seed_candidate)
                    previous = seed_candidate
                    seed_candidate = None
                else:
                    reference = statistics.median(recent)
                    if abs(val - reference) > NN_MAX_DEVIATION * reference:
                        rejection_reasons["ectopicDeviation"] += 1
                        previous = None
                        recent.clear()
                        seed_candidate = None
                        continue
                if previous is not None:
                    delta = val - previous
                    squared_diffs += delta * delta
                    pairs += 1
                all_nn.append(val)
                recent.append(val)
                if len(recent) > NN_REFERENCE_BEATS:
                    recent.pop(0)
                previous = val

    accepted_nn = len(all_nn)
    coverage_pct = (accepted_nn / raw_beats * 100.0) if raw_beats > 0 else 0.0
    final_rmssd = math.sqrt(squared_diffs / pairs) if (accepted_nn >= 20 and pairs > 0) else None
    final_ln = math.log(final_rmssd) if final_rmssd is not None and final_rmssd > 0 else None

    return {
        "raw_rr_count": raw_beats,
        "accepted_nn_count": accepted_nn,
        "rejected_beats_by_reason": rejection_reasons,
        "coverage_percentage": round(coverage_pct, 2),
        "timestamp_gaps": timestamp_gaps,
        "selected_calculation_window": window_type,
        "final_rmssd": round(final_rmssd, 2) if final_rmssd is not None else None,
        "final_ln_rmssd": round(final_ln, 2) if final_ln is not None else None,
    }


def sws_resting_hrv(
    samples: list[V18Sample],
    deep_epochs: list[tuple[int, int]] | None = None,
    quiet_accel_g: float = 0.10,
    min_window_s: int = 60,
) -> tuple[HrvResult, int, bool]:
    """HRV during Slow Wave Sleep (SWS / deep sleep) epochs.

    When deep sleep epochs contain at least min_window_s and valid RMSSD, returns
    SWS RMSSD. Otherwise safely falls back to the longest quiet-window resting HRV.
    """
    if deep_epochs:
        deep_samples = [
            s
            for s in samples
            if any(start <= s.unix <= end for start, end in deep_epochs)
        ]
        deep_res, deep_len = resting_hrv(
            deep_samples, quiet_accel_g=quiet_accel_g, min_window_s=min_window_s
        )
        if deep_res.rmssd_ms is not None and deep_res.nn_beats >= 20:
            return deep_res, deep_len, True
    fallback_res, fallback_len = resting_hrv(
        samples, quiet_accel_g=quiet_accel_g, min_window_s=min_window_s
    )
    return fallback_res, fallback_len, False


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


def _median_rolling_mean(values: list[float], window: int) -> float | None:
    """Median of rolling window means (matches Swift Hrv.restingHeartRate)."""
    if len(values) < window or window <= 0:
        return None
    total = sum(values[:window])
    window_means = [total / window]
    for i in range(window, len(values)):
        total += values[i] - values[i - window]
        window_means.append(total / window)
    window_means.sort()
    n = len(window_means)
    if n % 2 == 1:
        return window_means[n // 2]
    return (window_means[n // 2 - 1] + window_means[n // 2]) / 2


def resting_heart_rate(
    samples: list[V18Sample],
    window_s: int = 60,
    quiet_accel_g: float = 0.10,
) -> float | None:
    """Median of rolling window means during quiet periods (matches Swift Hrv.restingHeartRate).

    Resting HR is the median sustained rate during sleep or sustained quiet,
    not the single lowest instantaneous reading - one artefact beat must not
    set the value. Seconds must be contiguous so a gap cannot masquerade as a
    sustained window, and motion must be measured, not assumed: a sample with
    no accelerometer reading is excluded rather than treated as quiet.

    This matches the Swift implementation which reduced MAE vs WHOOP export
    from 8.1 bpm (minimum) to 1.5 bpm (median) over 5 paired nights.
    """
    eligible = [
        s
        for s in samples
        if s.wearing
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
    ]
    eligible.sort(key=lambda s: s.unix)
    window_means: list[float] = []
    for run in _contiguous_runs(eligible):
        if len(run) >= window_s:
            values = [float(s.heart_rate) for s in run]
            total = sum(values[:window_s])
            window_means.append(total / window_s)
            for i in range(window_s, len(values)):
                total += values[i] - values[i - window_s]
                window_means.append(total / window_s)
    if not window_means:
        return None
    window_means.sort()
    n = len(window_means)
    if n % 2 == 1:
        return window_means[n // 2]
    return (window_means[n // 2 - 1] + window_means[n // 2]) / 2


def hr_reserve_ratio(hr: float, resting_hr: float, max_hr: float) -> float:
    """Karvonen HR reserve fraction, clipped to [0, 1]."""
    if max_hr <= resting_hr:
        raise ValueError("max_hr must exceed resting_hr")
    return max(0.0, min(1.0, (hr - resting_hr) / (max_hr - resting_hr)))


def get_reserve_with_heart_rate(
    heart_rate: float,
    resting_heart_rate: float,
    maximum_heart_rate: float,
) -> float:
    """WHOOP 5.80.2 parity (0x109a85a8c): getReserveWithHeartRate:restingHeartRate:maximumHeartRate:"""
    return hr_reserve_ratio(heart_rate, resting_heart_rate, maximum_heart_rate)


def get_heart_rate_for_reserve(
    reserve: float,
    resting_heart_rate: float,
    maximum_heart_rate: float,
) -> float:
    """WHOOP 5.80.2 parity (0x109a85158): getHeartRateForReserve:restingHeartRate:maximumHeartRate:"""
    if maximum_heart_rate <= resting_heart_rate:
        raise ValueError("maximum_heart_rate must exceed resting_heart_rate")
    clipped_reserve = max(0.0, min(1.0, reserve))
    return resting_heart_rate + clipped_reserve * (maximum_heart_rate - resting_heart_rate)


def effective_baselines(
    configured_max_hr: float | None = None,
    measured_resting_hr: float | None = None,
    age: int | None = None,
) -> tuple[float, float]:
    """Safe fallback calibration preventing strain withholding on uncalibrated profile."""
    max_hr = (
        configured_max_hr
        if configured_max_hr is not None and configured_max_hr > 60
        else (age_predicted_max_hr(age) if age is not None and age > 0 else 190.0)
    )
    rhr = (
        measured_resting_hr
        if measured_resting_hr is not None and measured_resting_hr > 30
        else 60.0
    )
    return rhr, max_hr


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


def whoop_strain_intensity(hr: float, resting_hr: float, max_hr: float) -> float:
    """Non-linear strain intensity weighting from WHOOP 5.80.2 (0x1001eee6c)."""
    if max_hr <= resting_hr or resting_hr <= 0:
        return 0.0
    reserve = max(0.0, min(1.0, (hr - resting_hr) / (max_hr + 3.0 - resting_hr)))
    if reserve <= 0.30:
        return 0.0
    return 16.0 / (1.0 + math.exp((1.0 - reserve) / 0.15))


def accumulate_live_strain_step(
    current_raw: float, hr: float, delta_s: float, resting_hr: float, max_hr: float
) -> float:
    """Incremental live strain accumulation step with 3-second gap capping (WHOOP 5.80.2)."""
    weight = whoop_strain_intensity(hr, resting_hr, max_hr)
    dt = min(3.0, max(0.0, delta_s))
    return current_raw + weight * dt / 691200.0

"""Four-stage sleep stager over a sleep window the detector already found.

This is an APPROXIMATION, not PSG-validated staging. It exists because the
band's v18 stream carries the channels a transparent rule stager needs — 1 Hz
HR, beat-to-beat R-R, and a gravity vector — and because silence is not more
honest than a labelled estimate. Every stage figure the app shows is marked as
an estimate.

The recipe is the published sleeplab-style approach NOOP's SleepStagerV2
documents (a 30 s-epoch HMM over cardiorespiratory features), reimplemented
here from its description rather than copied:

  1. per-night z-scores of HR, 5-minute HR variability, movement fraction and
     R-R RSA regularity;
  2. a deep gate on the night's own 11-minute HR-flatness percentile;
  3. a soft sleep-cycle prior (deep early, REM rising, plus REM/deep latency
     guards measured from the first sustained sleep run);
  4. a wake gate on peak jerk relative to the night's own quiescent floor;
  5. Viterbi smoothing with a sticky transition matrix.

Two departures from that recipe, both deliberate:

  * Staging refuses below 50 % HR coverage. A night with no cardiac data would
    otherwise collapse to "all light" — a fabricated stage, not a measurement.
  * Deep/REM latency guards use absolute minutes from the run's onset, so a
    long window cannot stretch the first-REM guard.

Reported four-class agreement for this family of rules on wrist data is low
(kappa ~0.1-0.4 against PSG); treat the hypnogram as a plausible shape, never
as a clinical reading.
"""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass, field
import math
from statistics import median

from .health import SleepPeriod
from .records import V18Sample

EPOCH_S = 30
MIN_HR_COVERAGE = 0.5
MIN_BEATS_PER_EPOCH = 12
STAGE_NAMES = ("deep", "rem", "light", "awake")

# Fixed a priori from sleep physiology and population base rates; not fit to
# any labels. Adult TST is roughly 50 % light, 22 % REM, 15 % deep, 10 % wake.
BASE_LOG_PRIOR = {
    "light": math.log(0.50),
    "deep": math.log(0.15),
    "rem": math.log(0.22),
    "awake": math.log(0.10),
}

# Deep is eligible only in the night's lowest ~25 % HR-flatness epochs.
DEEP_GATE_THRESHOLD = 0.25
DEEP_GATE_SLOPE = 5.0

# Motion thresholds are relative to the night's own quiescent jerk floor, so
# the rule self-calibrates to the band's gravity scale and the wearer's fit.
JERK_FLOOR_MOVE_MULT = 38.0
JERK_FLOOR_GATE_MULT = 55.0
MOTION_GATE_BOOST = 2.0
RESP_WEIGHT = 0.6

TRANSITION = {
    "deep": {"deep": 0.86, "rem": 0.007, "light": 0.126, "awake": 0.007},
    "rem": {"deep": 0.005, "rem": 0.88, "light": 0.10, "awake": 0.015},
    "light": {"deep": 0.06, "rem": 0.06, "light": 0.85, "awake": 0.03},
    "awake": {"deep": 0.0, "rem": 0.0, "light": 0.10, "awake": 0.90},
}

REM_LATENCY_PENALTY = 3.0
REM_LATENCY_MINUTES = 60.0
DEEP_LATENCY_PENALTY = 3.0
DEEP_LATENCY_MINUTES = 20.0
ONSET_SUSTAINED_EPOCHS = 10

RR_MIN_MS = 300.0
RR_MAX_MS = 2000.0
RR_RESAMPLE_HZ = 4.0
RSA_BAND_HZ = (0.15, 0.40)


@dataclass
class StageSegment:
    """Half-open [start_unix, end_unix) span carrying one stage label."""

    start_unix: int
    end_unix: int
    stage: str  # "wake" | "light" | "deep" | "rem"

    @property
    def duration_s(self) -> int:
        return self.end_unix - self.start_unix

    @property
    def minutes(self) -> float:
        return self.duration_s / 60.0


@dataclass
class SleepStaging:
    segments: list[StageSegment] = field(default_factory=list)
    deep_min: float = 0.0
    light_min: float = 0.0
    rem_min: float = 0.0
    wake_min: float = 0.0
    epochs: int = 0
    hr_coverage: float = 0.0
    reason: str | None = None

    @property
    def asleep_min(self) -> float:
        return self.deep_min + self.light_min + self.rem_min

    @property
    def restorative_min(self) -> float:
        return self.deep_min + self.rem_min

    @property
    def total_min(self) -> float:
        return self.asleep_min + self.wake_min

    def stage_minutes(self, stage: str) -> float:
        return {
            "deep": self.deep_min,
            "light": self.light_min,
            "rem": self.rem_min,
            "wake": self.wake_min,
        }.get(stage, 0.0)


@dataclass
class _Epoch:
    start: int
    hr: float | None
    hr_var: float | None
    hr_flat11: float | None
    move_frac: float
    jerk_max: float
    resp_reg: float | None
    clock: float
    jerk_scale: float
    minutes: float


def _zfun(values: list[float | None]):
    present = [v for v in values if v is not None]
    if not present:
        return lambda _value: 0.0
    mean = sum(present) / len(present)
    variance = sum((v - mean) ** 2 for v in present) / len(present)
    sd = math.sqrt(variance) if variance > 0 else 1.0
    return lambda value: 0.0 if value is None else (value - mean) / sd


def _percentile_rank(sorted_values: list[float], value: float | None) -> float:
    if value is None or not sorted_values:
        return 0.5
    return bisect_right(sorted_values, value) / len(sorted_values)


def _resp_regularity(beats: list[tuple[int, float]]) -> float | None:
    """Peakedness of RSA power in 0.15-0.40 Hz over a 4 Hz resampled beat train."""
    if len(beats) < MIN_BEATS_PER_EPOCH:
        return None
    beats = sorted(beats, key=lambda b: (b[0], b[1]))
    t0 = beats[0][0]
    t1 = beats[-1][0]
    if t1 <= t0:
        return None
    step = 1.0 / RR_RESAMPLE_HZ
    count = math.ceil((t1 - t0) / step - 1e-9)
    if count < 16:
        return None

    grid: list[float] = []
    seg = 0
    for index in range(count):
        t = t0 + step * index
        while seg < len(beats) - 2 and beats[seg + 1][0] < t:
            seg += 1
        ta, va = beats[seg]
        tb, vb = beats[seg + 1]
        if tb <= ta:
            grid.append(va)
        else:
            fraction = min(max((t - ta) / (tb - ta), 0.0), 1.0)
            grid.append(va + fraction * (vb - va))

    mean = sum(grid) / len(grid)
    grid = [value - mean for value in grid]

    lo = math.ceil(RSA_BAND_HZ[0] * step * count)
    hi = math.floor(RSA_BAND_HZ[1] * step * count)
    if hi < lo or lo < 0:
        return None
    max_power = 0.0
    sum_power = 0.0
    for k in range(lo, hi + 1):
        omega = 2.0 * math.pi * k / count
        re = 0.0
        im = 0.0
        for j, value in enumerate(grid):
            angle = omega * j
            re += value * math.cos(angle)
            im -= value * math.sin(angle)
        power = re * re + im * im
        sum_power += power
        if power > max_power:
            max_power = power
    if sum_power == 0.0:
        return None
    return max_power / sum_power


def _features(
    start: int,
    end: int,
    sec_hr: dict[int, float],
    sec_gravity: dict[int, tuple[float, float, float]],
    rr_by_sec: dict[int, list[float]],
) -> list[_Epoch]:
    span = max(1, end - start)
    first = ((start + EPOCH_S - 1) // EPOCH_S) * EPOCH_S

    raw: list[tuple[int, float | None, float | None, float | None, list[float], int, float, float | None, float, float]] = []
    all_jerks: list[float] = []

    epoch_start = first
    while epoch_start < end:
        hrs: list[float] = []
        gravity: list[tuple[float, float, float]] = []
        for second in range(epoch_start, epoch_start + EPOCH_S):
            value = sec_hr.get(second)
            if value is not None:
                hrs.append(value)
            point = sec_gravity.get(second)
            if point is not None:
                gravity.append(point)
        if not hrs and not gravity:
            epoch_start += EPOCH_S
            continue

        jerks: list[float] = []
        for index in range(1, len(gravity)):
            ax, ay, az = gravity[index - 1]
            bx, by, bz = gravity[index]
            jerks.append(math.sqrt((ax - bx) ** 2 + (ay - by) ** 2 + (az - bz) ** 2))
        all_jerks.extend(jerks)
        jerk_max = max(jerks) if jerks else 0.0

        five_lo = epoch_start - 150
        five_hi = epoch_start + EPOCH_S + 150
        eleven_lo = epoch_start - 330
        eleven_hi = epoch_start + EPOCH_S + 360

        def window_std(lo: int, hi: int) -> float | None:
            values = [sec_hr[s] for s in range(lo, hi) if s in sec_hr]
            if len(values) < 2:
                return None
            mean = sum(values) / len(values)
            variance = sum((v - mean) ** 2 for v in values) / len(values)
            return math.sqrt(max(0.0, variance))

        beats: list[tuple[int, float]] = []
        for second in range(epoch_start - 90, epoch_start + 120):
            for value in rr_by_sec.get(second, []):
                beats.append((second, min(max(value, RR_MIN_MS), RR_MAX_MS)))

        raw.append(
            (
                epoch_start,
                sum(hrs) / len(hrs) if hrs else None,
                window_std(five_lo, five_hi),
                window_std(eleven_lo, eleven_hi),
                jerks,
                max(1, len(gravity) - 1),
                jerk_max,
                _resp_regularity(beats),
                (epoch_start + 15 - start) / span,
                (epoch_start + 15 - start) / 60.0,
            )
        )
        epoch_start += EPOCH_S

    if not all_jerks:
        jerk_scale = 1e-6
    else:
        jerk_scale = median(all_jerks)
        if jerk_scale <= 0:
            jerk_scale = 1e-6
    move_threshold = jerk_scale * JERK_FLOOR_MOVE_MULT

    feats: list[_Epoch] = []
    for start_e, hr, hr_var, flat, jerks, gaps, jerk_max, resp, clock, minutes in raw:
        moves = sum(1 for jerk in jerks if jerk > move_threshold)
        feats.append(
            _Epoch(
                start=start_e,
                hr=hr,
                hr_var=hr_var,
                hr_flat11=flat,
                move_frac=moves / gaps,
                jerk_max=jerk_max,
                resp_reg=resp,
                clock=clock,
                jerk_scale=jerk_scale,
                minutes=minutes,
            )
        )
    return feats


def _motion_quiescent(epoch: _Epoch) -> bool:
    return epoch.move_frac <= 0.0 and epoch.jerk_max <= epoch.jerk_scale * JERK_FLOOR_GATE_MULT


def _rem_latency_guard(minutes_since_onset: float) -> float:
    return REM_LATENCY_PENALTY * min(1.0, max(0.0, 1.0 - minutes_since_onset / REM_LATENCY_MINUTES))


def _deep_latency_guard(minutes_since_onset: float) -> float:
    return DEEP_LATENCY_PENALTY * min(1.0, max(0.0, 1.0 - minutes_since_onset / DEEP_LATENCY_MINUTES))


def _cycle_prior(clock: float, minutes_since_onset: float) -> dict[str, float]:
    return {
        "deep": 1.2 * max(0.0, 1.0 - clock / 0.55),
        "rem": 1.0 * clock - _rem_latency_guard(minutes_since_onset),
        "light": 0.0,
        "awake": 0.0,
    }


def _viterbi(emissions: list[dict[str, float]]) -> list[str]:
    if not emissions:
        return []
    log_transition = {
        source: {target: math.log(max(value, 1e-9)) for target, value in row.items()}
        for source, row in TRANSITION.items()
    }
    scores = dict(emissions[0])
    back: list[dict[str, str]] = []
    for index in range(1, len(emissions)):
        new_scores: dict[str, float] = {}
        pointers: dict[str, str] = {}
        for stage in STAGE_NAMES:
            best_prev = STAGE_NAMES[0]
            best = scores[best_prev] + log_transition[best_prev][stage]
            for previous in STAGE_NAMES[1:]:
                value = scores[previous] + log_transition[previous][stage]
                if value > best:
                    best = value
                    best_prev = previous
            new_scores[stage] = best + emissions[index][stage]
            pointers[stage] = best_prev
        scores = new_scores
        back.append(pointers)

    last = STAGE_NAMES[0]
    for stage in STAGE_NAMES[1:]:
        if scores[stage] > scores[last]:
            last = stage
    path = [last]
    for pointers in reversed(back):
        last = pointers[last]
        path.append(last)
    path.reverse()
    return path


def _sustained_sleep_onset(labels: list[str]) -> int | None:
    run = 0
    for index, label in enumerate(labels):
        if label == "awake":
            run = 0
            continue
        run += 1
        if run >= ONSET_SUSTAINED_EPOCHS:
            return index - ONSET_SUSTAINED_EPOCHS + 1
    return None


def _stage_epochs(feats: list[_Epoch]) -> list[str]:
    if not feats:
        return []
    z_hr = _zfun([f.hr for f in feats])
    z_var = _zfun([f.hr_var for f in feats])
    z_move = _zfun([f.move_frac for f in feats])
    z_resp = _zfun([f.resp_reg for f in feats])
    flat_sorted = sorted(v for v in (f.hr_flat11 for f in feats) if v is not None)

    emissions: list[dict[str, float]] = []
    for f in feats:
        gate = DEEP_GATE_SLOPE * max(0.0, _percentile_rank(flat_sorted, f.hr_flat11) - DEEP_GATE_THRESHOLD)
        awake_cardiac = 0.8 * z_var(f.hr_var) + 0.4 * z_hr(f.hr)
        if _motion_quiescent(f):
            awake_cardiac = min(0.0, awake_cardiac)
        emission = {
            "deep": -1.1 * z_var(f.hr_var) - 0.5 * z_move(f.move_frac) - gate + BASE_LOG_PRIOR["deep"],
            "rem": 0.6 * z_var(f.hr_var) - 0.6 * z_move(f.move_frac) + 0.4 * z_hr(f.hr) + BASE_LOG_PRIOR["rem"],
            "light": BASE_LOG_PRIOR["light"],
            "awake": 1.0 * z_move(f.move_frac) + awake_cardiac + BASE_LOG_PRIOR["awake"],
        }
        # Pass 1 keeps the REM guard disabled; pass 2 re-adds it from the
        # onset this first pass finds.
        prior = _cycle_prior(f.clock, math.inf)
        for stage in STAGE_NAMES:
            emission[stage] += prior[stage]
        if f.jerk_max > f.jerk_scale * JERK_FLOOR_GATE_MULT:
            emission["awake"] += MOTION_GATE_BOOST
        if f.resp_reg is not None:
            value = z_resp(f.resp_reg)
            emission["deep"] += RESP_WEIGHT * value
            emission["rem"] -= RESP_WEIGHT * value
        emissions.append(emission)

    provisional = _viterbi(emissions)
    onset_index = _sustained_sleep_onset(provisional)
    origin = feats[onset_index].minutes if onset_index is not None else 0.0

    for index, f in enumerate(feats):
        since_onset = f.minutes - origin
        emissions[index]["rem"] -= _rem_latency_guard(since_onset)
        emissions[index]["deep"] -= _deep_latency_guard(since_onset)
    return _viterbi(emissions)


def stage_sleep(samples: list[V18Sample], period: SleepPeriod) -> SleepStaging:
    """Stage one detected sleep window. Never invents stages without HR."""
    start = period.start_unix
    end = period.end_unix + 1  # SleepPeriod's end is inclusive
    if end <= start:
        return SleepStaging(reason="empty sleep window")

    first_epoch = ((start + EPOCH_S - 1) // EPOCH_S) * EPOCH_S
    grid_epochs = max(0, (end - first_epoch + EPOCH_S - 1) // EPOCH_S)
    if grid_epochs == 0:
        return SleepStaging(reason=f"sleep window shorter than one {EPOCH_S} s epoch")

    ordered = sorted(samples, key=lambda s: s.unix)
    pad_lo = start - 360
    pad_hi = end + 420

    hr_sum: dict[int, float] = {}
    hr_count: dict[int, int] = {}
    gravity_sum: dict[int, list[float]] = {}
    rr_by_sec: dict[int, list[float]] = {}
    for sample in ordered:
        second = sample.unix
        if second < pad_lo or second >= pad_hi:
            continue
        if sample.heart_rate > 0:
            hr_sum[second] = hr_sum.get(second, 0.0) + sample.heart_rate
            hr_count[second] = hr_count.get(second, 0) + 1
        if sample.gravity_g is not None:
            current = gravity_sum.get(second)
            if current is None:
                gravity_sum[second] = [sample.gravity_g[0], sample.gravity_g[1], sample.gravity_g[2], 1.0]
            else:
                current[0] += sample.gravity_g[0]
                current[1] += sample.gravity_g[1]
                current[2] += sample.gravity_g[2]
                current[3] += 1.0
        for rr in sample.rr_intervals_ms:
            if RR_MIN_MS <= rr <= RR_MAX_MS:
                rr_by_sec.setdefault(second, []).append(float(rr))

    sec_hr = {second: total / hr_count[second] for second, total in hr_sum.items()}
    sec_gravity = {
        second: (values[0] / values[3], values[1] / values[3], values[2] / values[3])
        for second, values in gravity_sum.items()
    }

    feats = _features(start, end, sec_hr, sec_gravity, rr_by_sec)
    hr_epochs = sum(1 for f in feats if f.hr is not None)
    coverage = hr_epochs / grid_epochs
    if coverage < MIN_HR_COVERAGE:
        return SleepStaging(
            epochs=len(feats),
            hr_coverage=coverage,
            reason=(
                f"heart rate covers {coverage * 100:.0f}% of the sleep window; "
                f"staging needs at least {MIN_HR_COVERAGE * 100:.0f}%"
            ),
        )

    labels = _stage_epochs(feats)
    if len(labels) != len(feats):
        return SleepStaging(epochs=len(feats), hr_coverage=coverage, reason="staging produced no labels")

    segments: list[StageSegment] = []
    for index, (epoch, label) in enumerate(zip(feats, labels)):
        stage = "wake" if label == "awake" else label
        seg_start = start if index == 0 else epoch.start
        seg_end = end if index == len(feats) - 1 else feats[index + 1].start
        if segments and segments[-1].stage == stage:
            segments[-1].end_unix = seg_end
        else:
            segments.append(StageSegment(seg_start, seg_end, stage))

    result = SleepStaging(segments=segments, epochs=len(feats), hr_coverage=coverage)
    for segment in segments:
        minutes = segment.minutes
        if segment.stage == "deep":
            result.deep_min += minutes
        elif segment.stage == "light":
            result.light_min += minutes
        elif segment.stage == "rem":
            result.rem_min += minutes
        elif segment.stage == "wake":
            result.wake_min += minutes
    return result

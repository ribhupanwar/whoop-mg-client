"""Automatic session detection from the 1 Hz stream.

Provenance:
  * Session start/stop - the HR-only detector in the user's own dsta repo:
    baseline = median HR 5-15 min old, start at max(100, baseline+20) bpm
    sustained 4 min, session at least 5 min so a real workout is not missed.
  * Gait class - the band's per-second activity_class byte reads 0 still /
    1 walk / 2 run (noop's Interpreter.swift read of the wire, issue #316).
    Our own captures corroborate it: class-1 seconds carry the motion bursts
    while class-0 seconds stay near quiet. It is a gait readout, not a motion
    flag: arm movement while standing still stays class 0, which is exactly
    what a strength session looks like. The enum is not vendor-verified, so a
    session label always combines gait, steps and HR rather than trusting it.
  * Steps/min - the step counter, never the cadence byte: cadence reads
    97-108 even while sitting still in our rest capture. >=100 steps/min is
    the published moderate-intensity walking cadence (Tudor-Locke et al.
    2011, Int J Behav Nutr Phys Act); >=140 separates running as a coaching
    heuristic, not a validated cut-point.
  * Walking safeguard - walking needs sustained cardiovascular evidence;
    steps alone remain daily movement. Default 10-minute floor prevents
    domestic strolls from becoming workouts.
"""

import math
import statistics
from dataclasses import dataclass

from .records import V18Sample
from .steps import MAX_STEPS_PER_SECOND, step_delta, step_rate, step_total

BASELINE_MIN_AGE_S = 300
BASELINE_MAX_AGE_S = 900
BASELINE_MIN_SAMPLES = 5
HR_START_ABS = 100.0
HR_START_DELTA = 20.0
START_SUSTAIN_S = 240
MIN_SESSION_S = 300
COMPARISON_MIN_SESSION_S = 600
WALK_WORKOUT_MIN_SESSION_S = 600
GAP_TOLERANCE_S = 180
STEP_WINDOW_S = 60
WALK_SPM = 100.0
RUN_SPM = 140.0

GAIT_STILL = 0
GAIT_WALK = 1
GAIT_RUN = 2


@dataclass
class ActivitySession:
    start_unix: int
    end_unix: int
    kind: str
    steps: int
    mean_hr: float | None
    walk_ticks: int
    run_ticks: int

    @property
    def duration_s(self) -> int:
        return self.end_unix - self.start_unix + 1

    @property
    def minutes(self) -> float:
        return self.duration_s / 60.0


@dataclass
class ActivityCandidate:
    session: ActivitySession
    confidence: str  # "confirmed", "uncertain", "daily_movement"
    reason: str


def _step_rate(samples: list[V18Sample], i: int) -> float | None:
    """Steps per minute over the trailing minute, via the shared accumulator.

    Leaps above the sprint ceiling are dropped rather than smeared across the
    window as a fake minute of walking; see `whoop/steps.py`.
    """
    return step_rate(samples, i, window_s=STEP_WINDOW_S, continuous_only=True)


def _baseline_hrs(samples: list[V18Sample]) -> list[float | None]:
    """Median HR of the 5-15 min old window, one value per sample."""
    baselines: list[float | None] = []
    lo = hi = 0
    for i, sample in enumerate(samples):
        while lo < i and samples[lo].unix < sample.unix - BASELINE_MAX_AGE_S:
            lo += 1
        while hi < i and samples[hi].unix <= sample.unix - BASELINE_MIN_AGE_S:
            hi += 1
        window = [float(s.heart_rate) for s in samples[lo:hi]]
        baselines.append(
            statistics.median(window) if len(window) >= BASELINE_MIN_SAMPLES else None
        )
    return baselines


def _close_gaps(flags: list[bool], samples: list[V18Sample]) -> list[bool]:
    filled = list(flags)
    i = 0
    n = len(flags)
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
        if bounded and span <= GAP_TOLERANCE_S:
            for j in range(start, end):
                filled[j] = True
    return filled


def _has_measured_acceleration(sample: V18Sample) -> bool:
    acceleration = sample.dynamic_accel_g
    return acceleration is not None and math.isfinite(acceleration) and acceleration >= 0.03


def _sustained_evidence(flags: list[bool], samples: list[V18Sample]) -> list[bool]:
    """Mirror STRAP's dense, wall-clock confirmation before closing pauses."""
    supported = [False] * len(flags)
    left = count = 0
    covered_through = -1
    for right, flag in enumerate(flags):
        count += flag
        while samples[right].unix - samples[left].unix >= MIN_SESSION_S:
            count -= flags[left]
            left += 1
        if count >= START_SUSTAIN_S:
            for index in range(max(left, covered_through + 1), right + 1):
                supported[index] = flags[index]
            covered_through = right
    return supported


def _kind(spm: list[float], has_steps: bool) -> str:
    if spm:
        median = statistics.median(spm)
        if median >= RUN_SPM:
            return "run"
        if median >= WALK_SPM:
            return "walk"
    return "workout" if has_steps else "cardio"


def detect_activities(
    samples: list[V18Sample], sleep_periods=(), minimum_duration_s: int = MIN_SESSION_S
) -> list[ActivitySession]:
    """Sustained sessions of run, walk or workout, detected without a start tap."""
    if minimum_duration_s <= 0:
        return []

    # Choose one record per timestamp (deduplicate)
    by_second: dict[int, V18Sample] = {}
    for sample in samples:
        if not sample.wearing or not (35 <= sample.heart_rate <= 220):
            continue
        if any(p.start_unix <= sample.unix <= p.end_unix for p in sleep_periods):
            continue
        old = by_second.get(sample.unix)
        if old is not None:
            old_quality = (
                (0 if old.step_motion_counter is None else 2)
                + (0 if old.dynamic_accel_g is None else 1)
                + len(old.rr_intervals_ms)
            )
            new_quality = (
                (0 if sample.step_motion_counter is None else 2)
                + (0 if sample.dynamic_accel_g is None else 1)
                + len(sample.rr_intervals_ms)
            )
            if new_quality <= old_quality:
                continue
        by_second[sample.unix] = sample

    ordered = sorted(by_second.values(), key=lambda s: s.unix)
    if not ordered:
        return []

    rates = [_step_rate(ordered, i) for i in range(len(ordered))]
    baselines = _baseline_hrs(ordered)

    flags = []
    measured_motion = []
    latched_baseline = None
    baseline_frozen = False
    last_evidence_unix = None

    for i, sample in enumerate(ordered):
        if last_evidence_unix is not None and sample.unix - last_evidence_unix > GAP_TOLERANCE_S:
            latched_baseline = None
            baseline_frozen = False
        computed_baseline = baselines[i]
        baseline = latched_baseline if baseline_frozen else computed_baseline

        rate = rates[i] or 0
        recent_steps = rate >= WALK_SPM
        if i > 0 and sample.step_motion_counter is not None:
            previous = ordered[i - 1]
            if previous.step_motion_counter is not None:
                elapsed = sample.unix - previous.unix
                delta = step_delta(previous.step_motion_counter, sample.step_motion_counter,
                                   count_after_reset=False)
                recent_steps = (
                    0 < elapsed <= 5 and 0 < delta <= MAX_STEPS_PER_SECOND * elapsed
                    and rate >= WALK_SPM
                )

        moving = _has_measured_acceleration(sample)
        elevated = (
            sample.heart_rate >= max(HR_START_ABS, baseline + HR_START_DELTA)
            if baseline is not None
            else sample.step_motion_counter is None and sample.heart_rate >= HR_START_ABS
        )
        measured_motion.append(recent_steps)
        is_active = recent_steps or (elevated and moving)
        flags.append(is_active)

        if is_active:
            if not baseline_frozen:
                latched_baseline = baselines[max(0, i - 1)]
                if latched_baseline is None:
                    latched_baseline = computed_baseline
                baseline_frozen = True
            last_evidence_unix = sample.unix

    supported = _sustained_evidence(flags, ordered)
    closed = _close_gaps(supported, ordered)

    sessions: list[ActivitySession] = []
    i = 0
    n = len(ordered)
    while i < n:
        if not closed[i]:
            i += 1
            continue
        start = i
        while i < n and closed[i]:
            if i > start and ordered[i].unix - ordered[i - 1].unix - 1 > GAP_TOLERANCE_S:
                break
            i += 1
        end = i

        # HR remains elevated after a measured walk/run stops. Exclude trailing HR-only cooldown.
        motion_indices = [idx for idx in range(start, end) if supported[idx] and measured_motion[idx]]
        motion_end = (motion_indices[-1] + 1) if len(motion_indices) >= START_SUSTAIN_S else end
        run = ordered[start:motion_end]

        duration = run[-1].unix - run[0].unix + 1
        if duration < minimum_duration_s:
            continue
        if sum(supported[start:motion_end]) < START_SUSTAIN_S:
            continue

        walk_ticks = sum(1 for s in run if s.activity_class == GAIT_WALK)
        run_ticks = sum(1 for s in run if s.activity_class == GAIT_RUN)
        spm = [r for r in rates[start:motion_end] if r is not None and r > 0]
        steps = step_total(run, continuous_only=True) or 0
        has_steps = any(s.step_motion_counter is not None for s in run)

        detected_kind = _kind(spm, has_steps)
        baseline = baselines[start]
        hr_floor = max(HR_START_ABS, baseline + HR_START_DELTA) if baseline is not None else HR_START_ABS
        if detected_kind == "walk":
            # Walking safeguard: require at least 10 minutes and sustained cardiovascular evidence
            if duration < max(minimum_duration_s, WALK_WORKOUT_MIN_SESSION_S):
                continue
            elevated_seconds = sum(
                1
                for idx in range(start, motion_end)
                if supported[idx] and measured_motion[idx] and ordered[idx].heart_rate >= hr_floor
            )
            if elevated_seconds < START_SUSTAIN_S:
                continue
        elif detected_kind in ("workout", "cardio"):
            concurrent_seconds = sum(
                1
                for idx in range(start, motion_end)
                if supported[idx] and ordered[idx].heart_rate >= hr_floor
                and _has_measured_acceleration(ordered[idx])
            )
            required_seconds = START_SUSTAIN_S
            if detected_kind == "workout":
                if duration < WALK_WORKOUT_MIN_SESSION_S:
                    continue
                if baseline is None:
                    required_seconds *= 2
            if concurrent_seconds < required_seconds:
                continue

        sessions.append(
            ActivitySession(
                start_unix=run[0].unix,
                end_unix=run[-1].unix,
                kind=detected_kind,
                steps=steps,
                mean_hr=statistics.mean([float(s.heart_rate) for s in run]),
                walk_ticks=walk_ticks,
                run_ticks=run_ticks,
            )
        )
    return suppress_duplicates(sessions)


def suppress_duplicates(sessions: list[ActivitySession]) -> list[ActivitySession]:
    """Suppress auto-detected sessions that overlap by >= 50% with an earlier accepted session."""
    accepted: list[ActivitySession] = []
    for candidate in sorted(sessions, key=lambda s: s.start_unix):
        cand_duration = max(1, candidate.duration_s)
        is_dup = False
        for other in accepted:
            overlap_start = max(candidate.start_unix, other.start_unix)
            overlap_end = min(candidate.end_unix, other.end_unix)
            if overlap_end >= overlap_start:
                overlap = overlap_end - overlap_start + 1
                if (overlap / cand_duration) >= 0.50:
                    is_dup = True
                    break
        if not is_dup:
            accepted.append(candidate)
    return accepted


def evaluate_candidates(
    samples: list[V18Sample], sleep_periods=(), minimum_duration_s: int = MIN_SESSION_S
) -> list[ActivityCandidate]:
    detected = detect_activities(samples, sleep_periods=sleep_periods, minimum_duration_s=minimum_duration_s)
    return [ActivityCandidate(session=s, confidence="confirmed", reason=s.kind) for s in detected]

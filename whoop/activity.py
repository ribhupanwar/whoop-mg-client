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
WALK_SPM = 60.0
BRISK_WALK_SPM = 100.0
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
    return step_rate(samples, i, window_s=STEP_WINDOW_S)


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


def _kind(run_ticks: int, walk_ticks: int, spm: list[float], has_steps: bool) -> str:
    if run_ticks or walk_ticks:
        return "run" if run_ticks > walk_ticks else "walk"
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
            )
            new_quality = (
                (0 if sample.step_motion_counter is None else 2)
                + (0 if sample.dynamic_accel_g is None else 1)
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
    inactive_count = 0

    for i, sample in enumerate(ordered):
        gait = sample.activity_class
        computed_baseline = baselines[i]
        baseline = latched_baseline or computed_baseline

        # Prefer recent counter delta so trailing 60s window doesn't smear into cooldown
        if (
            i > 0
            and sample.step_motion_counter is not None
            and ordered[i - 1].step_motion_counter is not None
        ):
            elapsed = sample.unix - ordered[i - 1].unix
            delta = step_delta(ordered[i - 1].step_motion_counter, sample.step_motion_counter) if elapsed > 0 else 0
            recent_steps = (
                elapsed > 0
                and elapsed <= 5
                and delta > 0
                and (delta * 60.0 / elapsed) >= WALK_SPM
                and delta <= MAX_STEPS_PER_SECOND * elapsed
            )
        else:
            recent_steps = (rates[i] or 0) >= WALK_SPM

        # Never classify running from an unverified gait byte alone:
        # running gait requires either measured steps or elevated heart rate.
        if gait == GAIT_RUN and (sample.heart_rate >= HR_START_ABS or recent_steps):
            locomotion = True
        else:
            locomotion = recent_steps

        elevated = (
            (baseline is not None and sample.heart_rate >= max(HR_START_ABS, baseline + HR_START_DELTA))
            or (baseline is None and sample.heart_rate >= 115.0)
        )
        measured_motion.append(locomotion)
        is_active = locomotion or elevated
        flags.append(is_active)

        if is_active:
            if latched_baseline is None:
                prev_index = max(0, i - 1)
                latched_baseline = baselines[prev_index] or computed_baseline
            inactive_count = 0
        else:
            inactive_count += 1
            if inactive_count > GAP_TOLERANCE_S:
                latched_baseline = None

    closed = _close_gaps(flags, ordered)

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
        motion_indices = [idx for idx in range(start, end) if measured_motion[idx]]
        motion_end = (motion_indices[-1] + 1) if len(motion_indices) >= START_SUSTAIN_S else end
        run = ordered[start:motion_end]

        duration = run[-1].unix - run[0].unix + 1
        if duration < minimum_duration_s:
            continue
        if sum(flags[start:motion_end]) < START_SUSTAIN_S:
            continue

        walk_ticks = sum(1 for s in run if s.activity_class == GAIT_WALK)
        run_ticks = sum(1 for s in run if s.activity_class == GAIT_RUN)
        spm = [r for r in rates[start:motion_end] if r is not None and r > 0]
        steps = step_total(run) or 0
        has_steps = any(s.step_motion_counter is not None for s in run)

        detected_kind = _kind(run_ticks, walk_ticks, spm, has_steps)
        if detected_kind == "walk":
            # Walking safeguard: require at least 10 minutes and sustained cardiovascular evidence
            if duration < max(minimum_duration_s, WALK_WORKOUT_MIN_SESSION_S):
                continue
            elevated_seconds = sum(
                1
                for idx in range(start, motion_end)
                if measured_motion[idx]
                and ordered[idx].heart_rate >= max(HR_START_ABS, (latched_baseline or baselines[idx] or 70.0) + HR_START_DELTA)
            )
            if elevated_seconds < START_SUSTAIN_S:
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
    return sessions


def evaluate_candidates(
    samples: list[V18Sample], sleep_periods=(), minimum_duration_s: int = MIN_SESSION_S
) -> list[ActivityCandidate]:
    detected = detect_activities(samples, sleep_periods=sleep_periods, minimum_duration_s=minimum_duration_s)
    return [ActivityCandidate(session=s, confidence="confirmed", reason=s.kind) for s in detected]

"""Automatic session detection from the 1 Hz stream.

Provenance:
  * Session start/stop - the HR-only detector in the user's own dsta repo:
    baseline = median HR 5-15 min old, start at max(100, baseline+20) bpm
    sustained 5 min, stop at baseline+10 for 8 min, session at least 10 min.
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
"""

import statistics
from dataclasses import dataclass

from .records import V18Sample

BASELINE_MIN_AGE_S = 300
BASELINE_MAX_AGE_S = 900
BASELINE_MIN_SAMPLES = 5
HR_START_ABS = 100.0
HR_START_DELTA = 20.0
START_SUSTAIN_S = 300
MIN_SESSION_S = 600
GAP_TOLERANCE_S = 180
STEP_WINDOW_S = 60
WALK_SPM = 60.0
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


def _step_rate(samples: list[V18Sample], i: int) -> float | None:
    """Steps per minute over the trailing minute, from counter deltas.

    A single-second delta above 5 steps is impossible even at sprint cadence
    (~250 steps/min), so it is a counter jump or reset artefact and is dropped
    rather than smeared across the whole window as a fake minute of walking.
    """
    if samples[i].step_motion_counter is None:
        return None
    window = [
        s
        for s in samples[max(0, i - STEP_WINDOW_S - 1):i + 1]
        if s.step_motion_counter is not None
        and samples[i].unix - s.unix <= STEP_WINDOW_S
    ]
    if len(window) < 2:
        return None
    total = 0
    for a, b in zip(window, window[1:]):
        delta = (b.step_motion_counter - a.step_motion_counter) & 0xFFFF
        if delta <= 5:
            total += delta
    span = samples[i].unix - window[0].unix
    if span <= 0:
        return None
    return total * 60.0 / span


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


def detect_activities(samples: list[V18Sample]) -> list[ActivitySession]:
    """Sustained sessions of run, walk or workout, detected without a start tap.

    A second is a candidate when the band reports a walking/running gait, the
    step counter shows sustained stepping, or HR clears the dsta start
    threshold. Brief stops (traffic light, racking a weight) are closed inside
    a session; anything shorter than ten minutes is not a session.
    """
    ordered = sorted((s for s in samples if s.wearing), key=lambda s: s.unix)
    if not ordered:
        return []
    rates = [_step_rate(ordered, i) for i in range(len(ordered))]
    baselines = _baseline_hrs(ordered)
    flags = []
    for i, sample in enumerate(ordered):
        gait = sample.activity_class
        if gait in (GAIT_WALK, GAIT_RUN):
            locomotion = True
        elif gait in (None, 0xFF):
            # No gait readout: fall back to the step counter. A trailing-minute
            # rate lags a real stop by up to a minute, so it is only used when
            # the band gives no per-tick answer of its own.
            locomotion = rates[i] is not None and rates[i] >= WALK_SPM
        else:
            locomotion = False
        baseline = baselines[i]
        elevated = baseline is not None and sample.heart_rate >= max(
            HR_START_ABS, baseline + HR_START_DELTA
        )
        flags.append(locomotion or elevated)
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
            i += 1
        run = ordered[start:i]
        if run[-1].unix - run[0].unix + 1 < MIN_SESSION_S:
            continue
        if sum(flags[start:i]) < START_SUSTAIN_S:
            continue
        walk_ticks = sum(1 for s in run if s.activity_class == GAIT_WALK)
        run_ticks = sum(1 for s in run if s.activity_class == GAIT_RUN)
        spm = [r for r in rates[start:i] if r is not None and r > 0]
        has_steps = any(s.step_motion_counter is not None for s in run)
        first, last = run[0].step_motion_counter, run[-1].step_motion_counter
        steps = (
            (last - first) & 0xFFFF
            if first is not None and last is not None and last >= first
            else 0
        )
        sessions.append(
            ActivitySession(
                start_unix=run[0].unix,
                end_unix=run[-1].unix,
                kind=_kind(run_ticks, walk_ticks, spm, has_steps),
                steps=steps,
                mean_hr=statistics.mean([float(s.heart_rate) for s in run]),
                walk_ticks=walk_ticks,
                run_ticks=run_ticks,
            )
        )
    return sessions
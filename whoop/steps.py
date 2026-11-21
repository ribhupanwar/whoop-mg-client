"""Step-counter accumulation for the v18 record.

The counter (u16 at inner[49]) climbs by 0-4 per second while the gait byte
reads walk/run and sits still otherwise, so a window total is the sum of its
deltas, not the difference between its last and first reading. It restarts
from 0 when the band reboots or is re-synced mid-capture, and only a fall from
the top of the 16-bit range is a genuine wrap. It occasionally catches up in
one leap once its internal gait counter flushes; those leaps are real steps,
so the total keeps them, while the per-minute *rate* ignores them because a
leap smeared over a minute would invent sustained walking.
"""

MODULUS = 0x10000
MAX_STEPS_PER_SECOND = 6
WRAP_FLOOR = 0xF000
WRAP_CEILING = 0x0FFF


def step_delta(before: int, after: int, *, count_after_reset: bool = True) -> int:
    """Steps between two counter readings (wrap unwrapped, restart counted)."""
    if after >= before:
        return after - before
    if before >= WRAP_FLOOR and after <= WRAP_CEILING:
        return MODULUS - before + after
    return after if count_after_reset else 0


def step_total(samples, *, continuous_only: bool = False) -> int | None:
    """Steps across a window; None when no record carried a counter."""
    seen = False
    total = 0
    previous: tuple[int, int] | None = None
    for sample in sorted(samples, key=lambda s: s.unix):
        if sample.step_motion_counter is None:
            continue
        seen = True
        if previous is not None:
            gap = sample.unix - previous[0]
            if continuous_only and gap <= 0:
                continue
            change = step_delta(previous[1], sample.step_motion_counter,
                                count_after_reset=not continuous_only)
            if not continuous_only or (gap <= 10 and change <= MAX_STEPS_PER_SECOND * gap):
                total += change
        previous = (sample.unix, sample.step_motion_counter)
    return total if seen else None


def step_rate(samples, i: int, window_s: int = 60, *, continuous_only: bool = False) -> float | None:
    """Trailing-window steps per minute, from counter deltas."""
    if not 0 <= i < len(samples) or samples[i].step_motion_counter is None:
        return None
    end = samples[i]
    window = [
        s
        for s in samples[max(0, i - window_s - 1):i + 1]
        if s.step_motion_counter is not None and end.unix - s.unix <= window_s
    ]
    if len(window) < 2:
        return None
    total = 0
    for a, b in zip(window, window[1:]):
        gap = b.unix - a.unix
        if continuous_only and not 0 < gap <= 10:
            continue
        gap = max(gap, 1)
        steps = step_delta(a.step_motion_counter, b.step_motion_counter,
                           count_after_reset=not continuous_only)
        if steps <= MAX_STEPS_PER_SECOND * gap:
            total += steps
    span = window[-1].unix - window[0].unix
    if span <= 0:
        return None
    return total * 60.0 / span

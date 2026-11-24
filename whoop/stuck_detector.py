"""Stuck strap detection logic for WHOOP offload monitoring.

Detects when the band reports records newer than the local persistent database
by more than `behind_gap_seconds` (default 300s / 5min) AND the local frontier
has not advanced for at least `stuck_after_seconds`.
"""

from __future__ import annotations

from typing import Optional


class StuckStrapDetector:
    def __init__(self, stuck_after_seconds: float = 60.0, behind_gap_seconds: int = 300) -> None:
        self.stuck_after_seconds = stuck_after_seconds
        self.behind_gap_seconds = behind_gap_seconds
        self.last_frontier_ts: Optional[int] = None
        self.last_advance_wall: Optional[float] = None

    def observe(
        self,
        strap_newest_ts: Optional[int],
        our_frontier_ts: Optional[int],
        now: float,
    ) -> bool:
        """Observe strap newest record timestamp vs local database frontier timestamp.

        Returns True if the strap is detected to be stuck.
        """
        if strap_newest_ts is None or our_frontier_ts is None:
            return False

        if self.last_frontier_ts is None:
            self.last_frontier_ts = our_frontier_ts
            self.last_advance_wall = now
            return False

        if our_frontier_ts > self.last_frontier_ts:
            # Local frontier is advancing normally
            self.last_frontier_ts = our_frontier_ts
            self.last_advance_wall = now
            return False

        behind = (strap_newest_ts - our_frontier_ts) > self.behind_gap_seconds
        if not behind:
            # Caught up or strap is not ahead of us (off-wrist or idle)
            self.last_advance_wall = now
            return False

        # Behind AND local frontier has not moved
        elapsed = now - (self.last_advance_wall or now)
        return elapsed >= self.stuck_after_seconds

    def reset(self) -> None:
        self.last_frontier_ts = None
        self.last_advance_wall = None

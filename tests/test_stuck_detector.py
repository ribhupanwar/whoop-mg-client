import unittest

from whoop.stuck_detector import StuckStrapDetector


class TestStuckStrapDetector(unittest.TestCase):
    def test_advancing_frontier_is_never_stuck(self):
        detector = StuckStrapDetector(stuck_after_seconds=60.0, behind_gap_seconds=300)
        # Seed
        self.assertFalse(detector.observe(strap_newest_ts=1786001000, our_frontier_ts=1786000000, now=100.0))
        # Advance frontier at t=130s
        self.assertFalse(detector.observe(strap_newest_ts=1786001000, our_frontier_ts=1786000500, now=130.0))
        # Advance frontier again at t=170s
        self.assertFalse(detector.observe(strap_newest_ts=1786001000, our_frontier_ts=1786000900, now=170.0))

    def test_caught_up_is_never_stuck(self):
        detector = StuckStrapDetector(stuck_after_seconds=60.0, behind_gap_seconds=300)
        # Gap is only 50s (<= 300s)
        self.assertFalse(detector.observe(strap_newest_ts=1786000050, our_frontier_ts=1786000000, now=100.0))
        # 100s later, still only 50s gap (off-wrist or caught up)
        self.assertFalse(detector.observe(strap_newest_ts=1786000050, our_frontier_ts=1786000000, now=200.0))

    def test_stuck_detected_when_behind_and_frozen(self):
        detector = StuckStrapDetector(stuck_after_seconds=60.0, behind_gap_seconds=300)
        # Strap is 2000s ahead (> 300s)
        # Initial seed at t=100s
        self.assertFalse(detector.observe(strap_newest_ts=1786002000, our_frontier_ts=1786000000, now=100.0))
        # At t=130s (30s elapsed < 60s)
        self.assertFalse(detector.observe(strap_newest_ts=1786002000, our_frontier_ts=1786000000, now=130.0))
        # At t=161s (61s elapsed >= 60s) -> STUCK!
        self.assertTrue(detector.observe(strap_newest_ts=1786002000, our_frontier_ts=1786000000, now=161.0))

    def test_recovering_from_stuck(self):
        detector = StuckStrapDetector(stuck_after_seconds=60.0, behind_gap_seconds=300)
        # Seed & become stuck
        detector.observe(strap_newest_ts=1786002000, our_frontier_ts=1786000000, now=100.0)
        self.assertTrue(detector.observe(strap_newest_ts=1786002000, our_frontier_ts=1786000000, now=165.0))
        # Frontier unblocks and advances at t=170s
        self.assertFalse(detector.observe(strap_newest_ts=1786002000, our_frontier_ts=1786000500, now=170.0))

    def test_missing_timestamps_do_not_trigger_stuck(self):
        detector = StuckStrapDetector(stuck_after_seconds=60.0, behind_gap_seconds=300)
        self.assertFalse(detector.observe(strap_newest_ts=None, our_frontier_ts=1786000000, now=100.0))
        self.assertFalse(detector.observe(strap_newest_ts=1786002000, our_frontier_ts=None, now=100.0))


if __name__ == "__main__":
    unittest.main()

import math
import unittest

from whoop.health import SleepPeriod
from whoop.records import RecordHeader, V18Sample
from whoop.sleep_stage import stage_sleep

BASE = 1_720_000_000


def make_night(minutes=90, hr=53.0, bursts=(), breathing=True, heart_rate_override=None):
    samples = []
    for second in range(minutes * 60):
        rate = hr + 1.5 * math.sin(2 * math.pi * second / 2400.0)
        gravity = (0.0, 0.0, 1.0)
        for start_min, end_min in bursts:
            if start_min * 60 <= second < end_min * 60:
                gravity = (
                    0.6 * math.sin(second * 7.1),
                    0.6 * math.cos(second * 5.3),
                    1.0 + 0.4 * math.sin(second * 3.7),
                )
                rate = 88.0
        rr = [int(1000 + 45 * math.sin(2 * math.pi * second / 4.0))] if breathing else []
        samples.append(
            V18Sample(
                header=RecordHeader(
                    version=18, flags=0, record_index=second, unix=BASE + second, subsec_q15=0
                ),
                heart_rate=heart_rate_override if heart_rate_override is not None else int(round(rate)),
                rr_intervals_ms=rr,
                gravity_g=gravity,
            )
        )
    period = SleepPeriod(
        start_unix=BASE, end_unix=BASE + minutes * 60 - 1, quiet_fraction=0.95, mean_hr=hr
    )
    return samples, period


class SleepStageTests(unittest.TestCase):
    def test_quiet_night_tiles_the_whole_window(self):
        samples, period = make_night()
        result = stage_sleep(samples, period)
        self.assertIsNone(result.reason)
        self.assertEqual(result.segments[0].start_unix, period.start_unix)
        self.assertEqual(result.segments[-1].end_unix, period.end_unix + 1)
        for left, right in zip(result.segments, result.segments[1:]):
            self.assertEqual(left.end_unix, right.start_unix)
        self.assertEqual(
            [s.stage for s in result.segments if s.stage not in {"deep", "light", "rem", "wake"}],
            [],
        )

    def test_quiet_night_is_mostly_light_with_no_wake(self):
        samples, period = make_night()
        result = stage_sleep(samples, period)
        self.assertEqual(result.wake_min, 0.0)
        self.assertGreater(result.light_min, result.deep_min)
        self.assertGreater(result.deep_min + result.rem_min, 0.0)
        self.assertAlmostEqual(result.total_min, 90.0, places=6)

    def test_totals_match_the_segments(self):
        samples, period = make_night(minutes=60, bursts=((20, 23),))
        result = stage_sleep(samples, period)
        for stage in ("deep", "light", "rem", "wake"):
            expected = sum(s.minutes for s in result.segments if s.stage == stage)
            self.assertAlmostEqual(result.stage_minutes(stage), expected, places=6)
        self.assertAlmostEqual(result.asleep_min + result.wake_min, result.total_min, places=6)

    def test_motion_bursts_are_staged_as_wake(self):
        samples, period = make_night(minutes=60, bursts=((20, 24),))
        result = stage_sleep(samples, period)
        self.assertIsNone(result.reason)
        self.assertGreater(result.wake_min, 0.0)
        self.assertIn("wake", [s.stage for s in result.segments])

    def test_missing_heart_rate_refuses_to_invent_stages(self):
        samples, period = make_night(minutes=60, heart_rate_override=0)
        result = stage_sleep(samples, period)
        self.assertEqual(result.segments, [])
        self.assertEqual(result.total_min, 0.0)
        self.assertIsNotNone(result.reason)
        self.assertIn("heart rate covers 0%", result.reason or "")

    def test_short_window_refuses(self):
        period = SleepPeriod(start_unix=100, end_unix=110, quiet_fraction=1.0, mean_hr=50)
        result = stage_sleep([], period)
        self.assertIn("shorter than one", result.reason or "")
        self.assertEqual(result.segments, [])


if __name__ == "__main__":
    unittest.main()

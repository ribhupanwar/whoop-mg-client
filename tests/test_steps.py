"""Tests for the step-counter accumulator."""

import unittest

from whoop.records import RecordHeader, V18Sample
from whoop.steps import step_delta, step_rate, step_total


def sample(unix, steps):
    return V18Sample(
        header=RecordHeader(
            version=18, flags=0x80, record_index=unix, unix=unix, subsec_q15=0
        ),
        heart_rate=70,
        step_motion_counter=steps,
    )


class TestStepTotal(unittest.TestCase):
    def test_sums_deltas_and_counts_a_restart_as_a_new_epoch(self):
        rows = [sample(0, 100), sample(1, 130), sample(2, 0), sample(3, 20)]
        self.assertEqual(step_total(rows), 50)

    def test_unwraps_the_sixteen_bit_range(self):
        rows = [sample(0, 65530), sample(1, 65535), sample(2, 3)]
        self.assertEqual(step_total(rows), 9)

    def test_no_counter_is_none(self):
        self.assertIsNone(step_total([sample(0, None), sample(1, None)]))
        self.assertIsNone(step_total([]))

    def test_missing_readings_are_skipped(self):
        rows = [sample(0, 10), sample(1, None), sample(2, 14)]
        self.assertEqual(step_total(rows), 4)

    def test_delta_handles_a_restart(self):
        self.assertEqual(step_delta(60_000, 0), 0)
        self.assertEqual(step_delta(60_000, 5), 5)


class TestStepRate(unittest.TestCase):
    def test_sustained_stepping(self):
        rows = [sample(i, i * 2) for i in range(61)]
        self.assertAlmostEqual(step_rate(rows, 60), 120.0, places=6)

    def test_catch_up_leap_is_not_a_minute_of_walking(self):
        rows = [sample(i, 0) for i in range(60)] + [sample(60, 12)]
        self.assertAlmostEqual(step_rate(rows, 60), 0.0, places=6)


if __name__ == "__main__":
    unittest.main()

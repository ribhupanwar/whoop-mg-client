"""Tests for the local sleep-analysis composite."""

import unittest

from whoop.health import Baseline, SleepPeriod, detect_sleep
from whoop.records import RecordHeader, V18Sample
from whoop.sleep_analysis import (
    analyze_sleep,
    sleep_consistency,
    sleep_stress_split,
)


def sample(unix, hr, accel=0.0, rr=()) -> V18Sample:
    return V18Sample(
        header=RecordHeader(
            version=18, flags=0x80, record_index=unix, unix=unix, subsec_q15=0
        ),
        heart_rate=hr,
        rr_intervals_ms=list(rr),
        dynamic_accel_g=accel,
    )


def stretch(start, seconds, hr, accel, rr=()):
    return [sample(start + i, hr, accel, rr) for i in range(seconds)]


def night_with_turns():
    """Quiet night with two brief movement bursts the gap-closer absorbs."""
    return (
        stretch(0, 300, 100, 0.5)
        + stretch(300, 1500, 60, 0.02)
        + stretch(1800, 60, 65, 0.6)
        + stretch(1860, 1500, 60, 0.02)
        + stretch(3360, 120, 65, 0.6)
        + stretch(3480, 1320, 60, 0.02)
        + stretch(4800, 300, 100, 0.5)
    )


def period(start, end, quiet=1.0):
    return SleepPeriod(start, end, quiet, 60.0)


class TestWakeEvents(unittest.TestCase):
    def test_movement_bursts_inside_a_period_are_counted(self):
        periods = detect_sleep(night_with_turns())
        self.assertEqual(len(periods), 1)
        self.assertEqual(periods[0].wake_events, 2)
        self.assertLess(periods[0].quiet_fraction, 1.0)

    def test_still_night_has_no_wake_events(self):
        rows = stretch(0, 300, 100, 0.5) + stretch(300, 3600, 60, 0.02)
        rows += stretch(3900, 300, 100, 0.5)
        periods = detect_sleep(rows)
        self.assertEqual(periods[0].wake_events, 0)
        self.assertAlmostEqual(periods[0].quiet_fraction, 1.0, places=6)


class TestConsistency(unittest.TestCase):
    def test_one_night_is_not_a_pattern(self):
        pct, nights = sleep_consistency([(0, 28800)])
        self.assertIsNone(pct)
        self.assertEqual(nights, 1)

    def test_regular_nights_score_full(self):
        # Bed 22:30 UTC, wake 06:30, three nights running.
        base = 22 * 3600 + 30 * 60
        nights = [(base + d * 86400, base + d * 86400 + 8 * 3600) for d in range(3)]
        pct, nights_used = sleep_consistency(nights)
        self.assertEqual(pct, 100.0)
        self.assertEqual(nights_used, 3)

    def test_one_late_night_breaks_the_pattern(self):
        base = 22 * 3600 + 30 * 60
        nights = [(base + d * 86400, base + d * 86400 + 8 * 3600) for d in range(2)]
        nights.append((base + 2 * 86400 + 3 * 3600, base + 2 * 86400 + 11 * 3600))
        pct, _ = sleep_consistency(nights)
        self.assertAlmostEqual(pct, 66.7, places=1)

    def test_midnight_wrap_is_not_a_deviation(self):
        # 23:30 and 00:30 bedtimes are 60 min apart, not 23 hours.
        day = 86400
        nights = [
            (23 * 3600 + 30 * 60, 23 * 3600 + 30 * 60 + 8 * 3600),
            (day + 30 * 60, day + 30 * 60 + 8 * 3600),
        ]
        pct, _ = sleep_consistency(nights)
        self.assertEqual(pct, 100.0)

    def test_zero_length_nights_are_dropped(self):
        pct, nights = sleep_consistency([(100, 100), (200, 100)])
        self.assertIsNone(pct)
        self.assertEqual(nights, 0)


class TestSleepStressSplit(unittest.TestCase):
    def norm(self, days=7):
        return Baseline(4.0, 0.3, 55.0, 3.0, days=days)

    def rr_stretch(self, start, seconds, rr):
        return stretch(start, seconds, 60, 0.02, rr=rr)

    def test_without_a_sleep_baseline_it_is_unavailable(self):
        rows = self.rr_stretch(0, 600, (800, 810))
        split = sleep_stress_split(rows, [period(0, 599)], None)
        self.assertIsNone(split.high_pct)
        self.assertIn("7 sleep nights", split.reason)

    def test_six_days_is_not_enough(self):
        rows = self.rr_stretch(0, 600, (800, 810))
        split = sleep_stress_split(rows, [period(0, 599)], self.norm(days=6))
        self.assertIsNone(split.high_pct)

    def test_calm_night_scores_low(self):
        # RMSSD 80 ms -> ln 4.38, above the 4.0 norm -> index 0 -> low.
        rows = self.rr_stretch(0, 600, (760, 840))
        split = sleep_stress_split(rows, [period(0, 599)], self.norm())
        self.assertEqual(split.low_pct, 100.0)
        self.assertEqual(split.high_pct, 0.0)
        self.assertEqual(split.windows, 2)

    def test_middling_night_scores_medium(self):
        # RMSSD 40 ms -> ln 3.69 -> ~1 SD below the norm -> medium.
        rows = self.rr_stretch(0, 600, (780, 820))
        split = sleep_stress_split(rows, [period(0, 599)], self.norm())
        self.assertEqual(split.medium_pct, 100.0)
        self.assertEqual(split.high_pct, 0.0)
        self.assertEqual(split.low_pct, 0.0)

    def test_suppressed_night_scores_high(self):
        # RMSSD ~10 ms -> ln ~2.3, far below the norm -> clipped 3 -> high.
        rows = self.rr_stretch(0, 600, (800, 810, 800, 790))
        split = sleep_stress_split(rows, [period(0, 599)], self.norm())
        self.assertEqual(split.high_pct, 100.0)
        self.assertEqual(split.low_pct, 0.0)

    def test_windows_split_by_band(self):
        rows = self.rr_stretch(0, 300, (760, 840))
        rows += self.rr_stretch(300, 300, (800, 810, 800, 790))
        split = sleep_stress_split(rows, [period(0, 599)], self.norm())
        self.assertEqual(split.low_pct, 50.0)
        self.assertEqual(split.high_pct, 50.0)
        self.assertEqual(split.medium_pct, 0.0)

    def test_no_rr_leaves_it_unavailable(self):
        rows = stretch(0, 600, 60, 0.02)
        split = sleep_stress_split(rows, [period(0, 599)], self.norm())
        self.assertIsNone(split.high_pct)
        self.assertIn("R-R", split.reason)


class TestAnalyzeSleep(unittest.TestCase):
    def test_full_night_scores_full_on_available_components(self):
        rows = stretch(0, 8 * 3600, 60, 0.02)
        analysis = analyze_sleep(rows, [period(0, 8 * 3600 - 1)], 8.0, [], None)
        self.assertEqual(analysis.hours_vs_needed_pct, 100.0)
        self.assertEqual(analysis.efficiency_pct, 100.0)
        self.assertIsNone(analysis.consistency_pct)
        self.assertEqual(analysis.performance_pct, 100.0)

    def test_hours_are_capped_at_need(self):
        rows = stretch(0, 10 * 3600, 60, 0.02)
        analysis = analyze_sleep(rows, [period(0, 10 * 3600 - 1)], 8.0, [], None)
        self.assertEqual(analysis.hours_vs_needed_pct, 100.0)

    def test_short_night_lowers_the_composite(self):
        rows = stretch(0, 4 * 3600, 60, 0.02)
        analysis = analyze_sleep(rows, [period(0, 4 * 3600 - 1)], 8.0, [], None)
        self.assertEqual(analysis.hours_vs_needed_pct, 50.0)
        self.assertEqual(analysis.performance_pct, 75.0)

    def test_efficiency_is_duration_weighted(self):
        rows = stretch(0, 7200, 60, 0.02)
        periods = [period(0, 5399, quiet=1.0), period(5400, 7199, quiet=0.5)]
        analysis = analyze_sleep(rows, periods, 8.0, [], None)
        # 1.5 h at 100% + 0.5 h at 50% -> 87.5%
        self.assertEqual(analysis.efficiency_pct, 87.5)

    def test_consistency_joins_the_composite_when_available(self):
        rows = stretch(0, 8 * 3600, 60, 0.02)
        base = 22 * 3600 + 30 * 60
        nights = [(base + d * 86400, base + d * 86400 + 8 * 3600) for d in range(2)]
        nights.append((base + 2 * 86400 + 3 * 3600, base + 2 * 86400 + 11 * 3600))
        analysis = analyze_sleep(rows, [period(0, 8 * 3600 - 1)], 8.0, nights, None)
        self.assertAlmostEqual(analysis.consistency_pct, 66.7, places=1)
        self.assertAlmostEqual(analysis.performance_pct, 88.9, places=1)

    def test_no_periods_is_an_error(self):
        with self.assertRaises(ValueError):
            analyze_sleep([], [], 8.0, [], None)

    def test_zero_need_is_an_error(self):
        with self.assertRaises(ValueError):
            analyze_sleep([], [period(0, 100)], 0.0, [], None)


if __name__ == "__main__":
    unittest.main()
"""Tests for the local sleep, strain and recovery estimates."""

import math
import unittest

from whoop.health import (
    Baseline,
    RecoveryResult,
    SLEEP_DEBT_CAP_H,
    SLEEP_DEBT_WINDOW_NIGHTS,
    STRESS_MAX,
    clock_label,
    detect_sleep,
    recovery_score,
    sleep_coach,
    sleep_debt,
    strain_label,
    strain_score,
    stress_score,
    total_sleep_hours,
)
from whoop.records import RecordHeader, V18Sample


def sample(unix, hr, accel=0.0) -> V18Sample:
    return V18Sample(
        header=RecordHeader(
            version=18, flags=0x80, record_index=unix, unix=unix, subsec_q15=0
        ),
        heart_rate=hr,
        dynamic_accel_g=accel,
    )


def stretch(start, seconds, hr, accel):
    return [sample(start + i, hr, accel) for i in range(seconds)]


def baseline(days=14):
    return Baseline(
        ln_rmssd_mean=4.0, ln_rmssd_sd=0.3, rhr_mean=55.0, rhr_sd=3.0, days=days
    )


class TestSleepDetection(unittest.TestCase):
    def test_quiet_period_with_hr_drop_is_sleep(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 3600, 60, 0.02)
        rows += stretch(4200, 600, 100, 0.5)
        periods = detect_sleep(rows)
        self.assertEqual(len(periods), 1)
        self.assertEqual(periods[0].start_unix, 600)
        self.assertEqual(periods[0].duration_s, 3600)
        self.assertAlmostEqual(periods[0].hours, 1.0, places=6)
        self.assertAlmostEqual(periods[0].mean_hr, 60.0, places=6)

    def test_sitting_still_without_hr_drop_is_not_sleep(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 3600, 100, 0.02)
        rows += stretch(4200, 600, 100, 0.5)
        self.assertEqual(detect_sleep(rows), [])

    def test_short_quiet_period_is_not_sleep(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 1200, 60, 0.02)
        rows += stretch(1800, 600, 100, 0.5)
        self.assertEqual(detect_sleep(rows), [])

    def test_brief_movement_is_closed_into_one_period(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 1200, 60, 0.02)
        rows += stretch(1800, 120, 70, 0.5)
        rows += stretch(1920, 1200, 60, 0.02)
        rows += stretch(3120, 600, 100, 0.5)
        periods = detect_sleep(rows)
        self.assertEqual(len(periods), 1)
        self.assertEqual(periods[0].duration_s, 2520)
        self.assertAlmostEqual(periods[0].quiet_fraction, 2400.0 / 2520.0, places=6)

    def test_long_movement_splits_and_fragments_are_too_short(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 1200, 60, 0.02)
        rows += stretch(1800, 400, 80, 0.5)
        rows += stretch(2200, 1200, 60, 0.02)
        rows += stretch(3400, 600, 100, 0.5)
        self.assertEqual(detect_sleep(rows), [])

    def test_no_active_seconds_means_no_reference(self):
        rows = stretch(0, 3600, 60, 0.02)
        self.assertEqual(detect_sleep(rows), [])

    def test_missing_accel_is_not_quiet(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 3600, 60, None)
        rows += stretch(4200, 600, 100, 0.5)
        self.assertEqual(detect_sleep(rows), [])

    def test_empty(self):
        self.assertEqual(detect_sleep([]), [])

    def test_total_sleep_sums_periods(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 3600, 60, 0.02)
        rows += stretch(4200, 1800, 100, 0.5)
        rows += stretch(6000, 3600, 60, 0.02)
        rows += stretch(9600, 600, 100, 0.5)
        self.assertAlmostEqual(total_sleep_hours(detect_sleep(rows)), 2.0, places=6)


class TestStrain(unittest.TestCase):
    def test_zero_trimp_is_zero(self):
        self.assertEqual(strain_score(0.0), 0.0)

    def test_scale_constant(self):
        self.assertAlmostEqual(strain_score(150.0), 21.0 * (1 - 1 / math.e), places=6)

    def test_monotonic_and_bounded(self):
        values = [strain_score(t) for t in (0, 10, 50, 150, 300, 1000, 10000)]
        self.assertEqual(values, sorted(values))
        self.assertTrue(all(0 <= v <= 21.0 for v in values))
        self.assertGreater(values[-1], 20.9)

    def test_none_is_absent(self):
        self.assertIsNone(strain_score(None))

    def test_negative_rejected(self):
        with self.assertRaises(ValueError):
            strain_score(-1.0)

    def test_labels(self):
        self.assertEqual(strain_label(None), "unknown")
        self.assertEqual(strain_label(5), "light")
        self.assertEqual(strain_label(12), "moderate")
        self.assertEqual(strain_label(16), "high")
        self.assertEqual(strain_label(20), "all-out")


class TestBaseline(unittest.TestCase):
    def test_from_daily(self):
        result = Baseline.from_daily([4.0, 4.2, 3.8], [55, 57, 53])
        self.assertIsNotNone(result)
        self.assertEqual(result.days, 3)
        self.assertAlmostEqual(result.ln_rmssd_mean, 4.0, places=6)
        self.assertAlmostEqual(result.rhr_mean, 55.0, places=6)

    def test_too_few_days(self):
        self.assertIsNone(Baseline.from_daily([4.0], [55]))
        self.assertIsNone(Baseline.from_daily([], []))


class TestRecovery(unittest.TestCase):
    def test_no_baseline_gives_no_score(self):
        result = recovery_score(4.0, 55.0, 8.0, 8.0, None)
        self.assertIsNone(result.score)
        self.assertIn("baseline", result.reason)
        self.assertEqual(result.band, "unavailable")

    def test_short_baseline_gives_no_score(self):
        result = recovery_score(4.0, 55.0, 8.0, 8.0, baseline(days=3))
        self.assertIsNone(result.score)

    def test_missing_hrv_or_rhr_gives_no_score(self):
        self.assertIsNone(recovery_score(None, 55.0, 8.0, 8.0, baseline()).score)
        self.assertIsNone(recovery_score(4.0, None, 8.0, 8.0, baseline()).score)

    def test_at_baseline_with_full_sleep(self):
        # z=0 -> logistic 50 for both HRV and RHR; sleep 8/8 -> 100.
        # (50*.5 + 50*.2 + 100*.3) / 1.0 = 65
        result = recovery_score(4.0, 55.0, 8.0, 8.0, baseline())
        self.assertAlmostEqual(result.score, 65.0, places=6)
        self.assertEqual(result.band, "yellow")

    def test_missing_sleep_renormalises(self):
        # (50*.5 + 50*.2) / 0.7 = 50
        result = recovery_score(4.0, 55.0, None, None, baseline())
        self.assertAlmostEqual(result.score, 50.0, places=6)
        self.assertIsNone(result.sleep_component)

    def test_high_hrv_low_rhr_scores_higher(self):
        good = recovery_score(4.6, 50.0, 8.0, 8.0, baseline())
        poor = recovery_score(3.4, 62.0, 4.0, 8.0, baseline())
        self.assertGreater(good.score, poor.score)
        self.assertEqual(good.band, "green")
        self.assertEqual(poor.band, "red")

    def test_sleep_is_capped_at_need(self):
        at_need = recovery_score(4.0, 55.0, 8.0, 8.0, baseline())
        overslept = recovery_score(4.0, 55.0, 12.0, 8.0, baseline())
        self.assertEqual(at_need.score, overslept.score)

    def test_zero_sd_is_neutral_not_a_crash(self):
        flat = Baseline(4.0, 0.0, 55.0, 0.0, days=14)
        result = recovery_score(4.0, 55.0, 8.0, 8.0, flat)
        self.assertAlmostEqual(result.score, 65.0, places=6)

    def test_score_stays_in_range(self):
        for ln in (2.0, 4.0, 6.0):
            for rhr in (40.0, 55.0, 75.0):
                result = recovery_score(ln, rhr, 8.0, 8.0, baseline())
                self.assertTrue(0.0 <= result.score <= 100.0)


class TestStress(unittest.TestCase):
    def test_no_baseline_gives_no_index(self):
        result = stress_score(3.4, None)
        self.assertIsNone(result.index)
        self.assertIn("baseline", result.reason)
        self.assertEqual(result.band, "unavailable")

    def test_short_baseline_gives_no_index(self):
        self.assertIsNone(stress_score(3.4, baseline(days=6)).index)

    def test_seven_days_is_enough(self):
        self.assertIsNotNone(stress_score(3.4, baseline(days=7)).index)

    def test_missing_hrv_gives_no_index(self):
        result = stress_score(None, baseline())
        self.assertIsNone(result.index)
        self.assertEqual(result.band, "unavailable")

    def test_zero_sd_gives_no_index_rather_than_dividing_by_zero(self):
        flat = Baseline(4.0, 0.0, 55.0, 3.0, days=14)
        self.assertIsNone(stress_score(3.4, flat).index)

    def test_at_the_norm_is_zero(self):
        result = stress_score(4.0, baseline())
        self.assertEqual(result.index, 0.0)
        self.assertEqual(result.band, "low")

    def test_above_the_norm_is_not_negative_stress(self):
        result = stress_score(4.9, baseline())
        self.assertEqual(result.index, 0.0)
        self.assertEqual(result.band, "low")

    def test_index_counts_standard_deviations_below_the_norm(self):
        # mean 4.0, sd 0.3: each 0.3 of lnRMSSD below the norm is one point.
        for ln, expected in ((3.7, 1.0), (3.4, 2.0), (3.1, 3.0)):
            with self.subTest(ln=ln):
                self.assertAlmostEqual(stress_score(ln, baseline()).index, expected, places=6)

    def test_band_boundaries(self):
        for ln, band in (
            (4.0, "low"), (3.71, "low"), (3.7, "elevated"),
            (3.41, "elevated"), (3.4, "high"), (2.0, "high"),
        ):
            with self.subTest(ln=ln):
                self.assertEqual(stress_score(ln, baseline()).band, band)

    def test_far_below_the_norm_is_clipped(self):
        result = stress_score(1.0, baseline())
        self.assertEqual(result.index, STRESS_MAX)
        self.assertEqual(result.band, "high")

    def test_monotonic_as_hrv_falls(self):
        indices = [stress_score(4.6 - 0.05 * i, baseline()).index for i in range(60)]
        self.assertEqual(indices, sorted(indices))
        self.assertEqual(indices[0], 0.0)
        self.assertEqual(indices[-1], STRESS_MAX)

    def test_index_stays_in_range(self):
        for ln in (0.0, 2.0, 4.0, 6.0, 20.0):
            with self.subTest(ln=ln):
                index = stress_score(ln, baseline()).index
                self.assertTrue(0.0 <= index <= STRESS_MAX)


class TestSleepCoach(unittest.TestCase):
    def test_debt_accumulates_short_nights(self):
        self.assertAlmostEqual(sleep_debt([6.0, 6.0], 8.0), 4.0)

    def test_long_night_repays_debt(self):
        self.assertAlmostEqual(sleep_debt([6.0, 10.0], 8.0), 0.0)

    def test_surplus_sleep_banks_no_credit(self):
        self.assertAlmostEqual(sleep_debt([10.0, 10.0, 6.0], 8.0), 2.0)

    def test_debt_only_looks_at_recent_window(self):
        nights = [6.0] * (SLEEP_DEBT_WINDOW_NIGHTS + 5)
        self.assertAlmostEqual(
            sleep_debt(nights, 8.0), 2.0 * SLEEP_DEBT_WINDOW_NIGHTS
        )

    def test_no_nights_means_unknown_debt_not_zero(self):
        coach = sleep_coach([], 390)
        self.assertIsNone(coach.debt_h)
        self.assertEqual(coach.nights, 0)
        self.assertEqual(coach.need_h, 8.0)

    def test_debt_addition_is_capped(self):
        coach = sleep_coach([6.0, 6.0, 6.0], 390)
        self.assertEqual(coach.debt_h, 6.0)
        self.assertEqual(coach.need_h, 8.0 + SLEEP_DEBT_CAP_H)

    def test_bedtime_is_wake_minus_time_in_bed(self):
        coach = sleep_coach([], 390)
        in_bed_min = round(coach.time_in_bed_h * 60)
        self.assertEqual(coach.bedtime_min, 390 - in_bed_min)
        self.assertLess(coach.bedtime_min, 0)  # previous evening
        self.assertEqual(clock_label(coach.bedtime_min), "21:22")

    def test_tomorrow_hard_adds_allowance(self):
        easy = sleep_coach([], 390, tomorrow="easy")
        hard = sleep_coach([], 390, tomorrow="hard")
        self.assertAlmostEqual(hard.need_h - easy.need_h, 0.5)
        self.assertLess(hard.bedtime_min, easy.bedtime_min)

    def test_no_wake_time_gives_no_bedtime(self):
        coach = sleep_coach([7.0], None)
        self.assertIsNone(coach.bedtime_min)
        self.assertIn("wake time", coach.reason)

    def test_wake_time_gives_no_reason(self):
        self.assertIsNone(sleep_coach([7.0], 390).reason)

    def test_invalid_inputs_raise(self):
        with self.assertRaises(ValueError):
            sleep_coach([], 390, tomorrow="party")
        with self.assertRaises(ValueError):
            sleep_coach([], 390, base_need_h=0)
        with self.assertRaises(ValueError):
            sleep_coach([], 390, efficiency=0.0)
        with self.assertRaises(ValueError):
            sleep_coach([], 390, efficiency=1.2)

    def test_clock_label_wraps_both_ways(self):
        self.assertEqual(clock_label(390), "06:30")
        self.assertEqual(clock_label(-182), "20:58")
        self.assertEqual(clock_label(1440), "00:00")


if __name__ == "__main__":
    unittest.main()
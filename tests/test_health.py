"""Tests for the local sleep, strain and recovery estimates."""

import math
import unittest

from whoop.health import (
    Baseline,
    RecoveryLevel,
    RecoveryResult,
    SLEEP_DEBT_CAP_H,
    VO2MaxSource,
    SLEEP_DEBT_WINDOW_NIGHTS,
    STRESS_MAX,
    clock_label,
    detect_sleep,
    merge_nocturnal_periods,
    recovery_score,
    sleep_coach,
    sleep_debt,
    spo2_candidate_summary,
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
    def test_hr_surge_preserves_corroborated_quiet_sleep(self):
        from whoop.health import _split_run_at_hr_transitions

        start = 1_795_000_000
        surge_start = start + 3600
        surge_end = surge_start + 300
        end = surge_end + 4200
        first = stretch(start, 3600, 80, 0.01)
        last = stretch(surge_end, 4200, 80, 0.01)
        for state, motion, expected in [(2, 0.01, 1), (3, 0.01, 2),
                                         (2, 0.05, 2), (2, None, 2)]:
            surge = stretch(surge_start, 300, 97, motion)
            for row in first + surge + last:
                row.sleep_state = 2
            for row in surge:
                row.sleep_state = state
            result = _split_run_at_hr_transitions(first + surge + last, 100, 5, 3600)
            self.assertEqual(len(result), expected)
            if expected == 1:
                self.assertEqual(len(result[0]), end - start)
            else:
                self.assertEqual([part[0].unix for part in result], [start, surge_end])
                self.assertEqual([part[-1].unix for part in result], [surge_start - 1, end - 1])

    def test_long_corroborated_hr_rise_retains_qualifying_sleep(self):
        from datetime import datetime, timezone
        from whoop.health import _split_run_at_hr_transitions

        start = int(datetime(2025, 2, 10, tzinfo=timezone.utc).timestamp())
        rise = start + 3600
        resumed = rise + 3 * 3600
        end = resumed + 70 * 60
        run = (stretch(start, 3600, 80, 0.01)
               + stretch(rise, 3 * 3600, 97, 0.01)
               + stretch(resumed, 70 * 60, 80, 0.01))
        for row in run:
            row.sleep_state = 2
        expected = _split_run_at_hr_transitions(
            run, 100, 5, 3600, protect_corroborated_sleep=False)
        actual = _split_run_at_hr_transitions(run, 100, 5, 3600)
        self.assertEqual([part[0].unix for part in expected], [start, resumed])
        self.assertEqual([part[0].unix for part in actual], [start, resumed])
        self.assertEqual([part[-1].unix for part in actual], [rise - 1, end - 1])
        periods = detect_sleep(stretch(start - 900, 900, 100, 0.3)
                               + run + stretch(end, 900, 100, 0.3), min_sleep_s=3600)
        self.assertEqual([part.start_unix for part in periods], [start, resumed])
        self.assertEqual([part.end_unix for part in periods], [rise - 1, end - 1])

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

    def test_deep_stillness_without_hr_drop_is_not_sleep(self):
        # Stable wrist posture is possible during quiet wakefulness.
        # No declared sleep state and no reduction from the active HR reference.
        rows = stretch(0, 600, 70, 0.3)
        quiet = stretch(600, 7200, 75, 0.005)
        for row in quiet:
            row.gravity_g = (0.0, 0.0, 1.0)
        rows += quiet + stretch(7800, 600, 70, 0.3)
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

    # --- NOOP Parity Regression Tests ---
    
    def test_awake_in_bed_60_min_without_hr_drop_is_not_sleep(self):
        """Awake in bed for 60 min WITHOUT HR drop should NOT be sleep."""
        rows = stretch(0, 600, 90, 0.3)
        rows += stretch(600, 3600, 88, 0.02)  # 60 min awake, no HR drop (only 2 BPM)
        rows += stretch(4201, 400, 90, 0.5)  # 6+ min movement gap (> gap_tolerance_s=300)
        rows += stretch(4601, 7200, 55, 0.01)  # 2 hours confirmed sleep
        rows += stretch(11801, 600, 90, 0.3)
        periods = detect_sleep(rows)
        # Should detect sleep from 4601 onwards, not from 600
        self.assertEqual(len(periods), 1)
        self.assertEqual(periods[0].start_unix, 4601)

    def test_bathroom_break_2_min_merges(self):
        """2-minute bathroom break should merge into single sleep session."""
        rows = stretch(0, 600, 90, 0.3)
        rows += stretch(600, 3600, 55, 0.01)  # 1 hour sleep
        rows += stretch(4200, 120, 85, 0.15)  # 2 min bathroom break
        rows += stretch(4320, 3600, 55, 0.01)  # 1 hour sleep
        rows += stretch(7920, 600, 90, 0.3)
        periods = detect_sleep(rows)
        merged = merge_nocturnal_periods(periods, rows)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].duration_s, 7320)  # 2h + 2min merged

    def test_bathroom_break_5_min_merges(self):
        """5-minute bathroom break should merge into single sleep session."""
        rows = stretch(0, 600, 90, 0.3)
        rows += stretch(600, 3600, 55, 0.01)
        rows += stretch(4200, 300, 85, 0.15)  # 5 min bathroom break
        rows += stretch(4500, 3600, 55, 0.01)
        rows += stretch(8100, 600, 90, 0.3)
        periods = detect_sleep(rows)
        merged = merge_nocturnal_periods(periods, rows)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].duration_s, 7500)

    def test_bathroom_break_10_min_merges(self):
        """10-minute bathroom break should merge into single sleep session."""
        rows = stretch(0, 600, 90, 0.3)
        rows += stretch(600, 3600, 55, 0.01)
        rows += stretch(4200, 600, 85, 0.15)  # 10 min bathroom break
        rows += stretch(4800, 3600, 55, 0.01)
        rows += stretch(8400, 600, 90, 0.3)
        periods = detect_sleep(rows)
        merged = merge_nocturnal_periods(periods, rows)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].duration_s, 7800)

    def test_bathroom_break_30_min_splits(self):
        """30-minute bathroom break should NOT merge (exceeds 30 min threshold)."""
        rows = stretch(0, 600, 90, 0.3)
        rows += stretch(600, 3600, 55, 0.01)
        rows += stretch(4200, 1800, 85, 0.15)  # 30 min awake - should split
        rows += stretch(6000, 3600, 55, 0.01)
        rows += stretch(9600, 600, 90, 0.3)
        periods = detect_sleep(rows)
        self.assertEqual(len(periods), 2)
        self.assertEqual(periods[0].duration_s, 3600)
        self.assertEqual(periods[1].duration_s, 3600)

    def test_rtc_corruption_25_hour_timestamps_isolated(self):
        """RTC corruption with 25-hour jump should be isolated, not bridge HRV."""
        base = 1000
        rows = stretch(0, 600, 90, 0.3)
        # Gap before first sleep
        rows += stretch(600, 600, 90, 0.3)
        # Normal sleep
        normal_sleep = stretch(1200, 3600, 55, 0.01)
        # RTC jump: next record shows +25 hours (90000 seconds) but record_index is sequential
        rtc_jump = stretch(91200, 3600, 55, 0.01)
        rows += normal_sleep + rtc_jump + stretch(94800, 600, 90, 0.3)
        periods = detect_sleep(rows)
        # Should detect two separate sleep periods, not one 25-hour session
        self.assertEqual(len(periods), 2)
        self.assertEqual(periods[0].duration_s, 3600)
        self.assertEqual(periods[1].duration_s, 3600)

    def test_manual_sleep_correction_recalculates_downstream(self):
        """Manual sleep correction should trigger downstream metric recalculation."""
        from whoop.health import SleepPeriod
        base = 1000
        rows = stretch(0, 600, 90, 0.3)
        rows += stretch(600, 7200, 55, 0.01)  # 2 hours detected sleep
        rows += stretch(7800, 600, 90, 0.3)
        periods = detect_sleep(rows)
        self.assertEqual(len(periods), 1)
        original_start = periods[0].start_unix
        original_end = periods[0].end_unix
        
        # Simulate manual correction: user edits wake time 30 min earlier
        corrected_end = original_end - 1800
        # The corrected period should have shorter duration
        corrected_duration = corrected_end - original_start + 1
        self.assertEqual(corrected_duration, periods[0].duration_s - 1800)
        
        # Downstream metrics (mean HR, quiet fraction) should be recomputed
        # based on the corrected window
        corrected_period = SleepPeriod(
            start_unix=original_start,
            end_unix=corrected_end,
            quiet_fraction=periods[0].quiet_fraction,
            mean_hr=periods[0].mean_hr,
            wake_events=periods[0].wake_events
        )
        self.assertLess(corrected_period.duration_s, periods[0].duration_s)

    def test_sustained_three_minute_hr_elevation_trims_awake_in_bed_prefix_and_ignores_one_minute_surge(self):
        # 600s active (85 bpm), 2700s quiet awake-in-bed laptop prefix (83 bpm),
        # 5400s sleep (60 bpm) with a 1-minute 85 bpm REM surge at 4800s (must NOT split).
        rows = stretch(0, 600, 85, 0.3)
        rows += stretch(600, 2700, 83, 0.01)
        rows += stretch(3300, 1500, 60, 0.01)
        rows += stretch(4800, 60, 85, 0.01)  # 1-min surge only
        rows += stretch(4860, 3840, 60, 0.01)
        rows += stretch(8700, 600, 85, 0.3)
        periods = detect_sleep(rows)
        self.assertEqual(len(periods), 1)
        self.assertGreaterEqual(periods[0].start_unix, 3300)
        self.assertEqual(periods[0].end_unix, 8699)


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

    def test_recovery_level_canonical_boundaries(self):
        # 5-case enum matching 0x10a0f2874 and raw float boundaries 0x100041d3c
        self.assertEqual(RecoveryResult(None, "needs baseline").level, RecoveryLevel.CALIBRATING)
        self.assertEqual(RecoveryResult(None, "needs HRV").level, RecoveryLevel.DEAD_END)
        self.assertEqual(RecoveryResult(33.0, None).level, RecoveryLevel.LOW_RECOVERY)
        self.assertEqual(RecoveryResult(33.0001, None).level, RecoveryLevel.MEDIUM_RECOVERY)
        self.assertEqual(RecoveryResult(66.0, None).level, RecoveryLevel.MEDIUM_RECOVERY)
        self.assertEqual(RecoveryResult(66.0001, None).level, RecoveryLevel.HIGH_RECOVERY)
        self.assertEqual(RecoveryResult(100.0, None).level, RecoveryLevel.HIGH_RECOVERY)

    def test_respiratory_rate_illness_penalty(self):
        # Normal respiration (+0.3 rpm above baseline) applies no penalty
        normal = recovery_score(4.0, 55.0, 8.0, 8.0, baseline(),
                                respiratory_rate=14.3, respiratory_rate_baseline=14.0)
        unpenalized = recovery_score(4.0, 55.0, 8.0, 8.0, baseline())
        self.assertEqual(normal.score, unpenalized.score)

        # Elevated respiration (+2.0 rpm above baseline, illness indicator >= 1.2 rpm)
        sick = recovery_score(4.0, 55.0, 8.0, 8.0, baseline(),
                              respiratory_rate=16.0, respiratory_rate_baseline=14.0)
        self.assertLess(sick.score, unpenalized.score)
        # Expected: 65.0 * (1 - 0.10) = 58.5
        self.assertEqual(sick.score, 58.5)

    def test_sleep_performance_incorporating_sleep_debt(self):
        # When sleep performance (e.g. 75% after sleep debt) is provided,
        # it drives the sleep component directly.
        base = baseline()
        res_with_perf = recovery_score(4.0, 55.0, sleep_hours=8.0, sleep_need_hours=8.0,
                                       baseline=base, sleep_performance=75.0)
        self.assertEqual(res_with_perf.sleep_component, 75.0)

    def test_vo2max_source_enumeration(self):
        # 4 source strings matching 0x109748af0-0x109748b50
        self.assertEqual(VO2MaxSource.INTERNAL_ESTIMATE.value, "INTERNAL_ESTIMATE")
        self.assertEqual(VO2MaxSource.MANUAL_LAB_TEST.value, "MANUAL_LAB_TEST")
        self.assertEqual(VO2MaxSource.MANUAL_WEARABLE.value, "MANUAL_WEARABLE")
        self.assertEqual(VO2MaxSource.MANUAL_OTHER.value, "MANUAL_OTHER")


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


class TestSpo2CandidateSummary(unittest.TestCase):
    def candidate(self, unix, pct=None, status="absent"):
        row = sample(unix, 60)
        row.spo2_candidate_pct = pct
        row.spo2_candidate_status = status
        return row

    def test_mean_of_in_band_candidates(self):
        rows = [
            self.candidate(0, 96, "pct"),
            self.candidate(1, 97, "pct"),
            self.candidate(2, 0, "absent"),
            self.candidate(3, None, "saturated"),
            self.candidate(4, None, "diagnostic"),
        ]
        summary = spo2_candidate_summary(rows)
        self.assertAlmostEqual(summary.pct, 96.5)
        self.assertEqual(summary.readings, 2)
        self.assertEqual(summary.saturated, 1)
        self.assertEqual(summary.diagnostic, 1)
        self.assertIsNone(summary.reason)

    def test_no_in_band_candidate_produces_no_value(self):
        rows = [
            self.candidate(0, 0, "absent"),
            self.candidate(1, None, "saturated"),
            self.candidate(2, None, "diagnostic"),
        ]
        summary = spo2_candidate_summary(rows)
        self.assertIsNone(summary.pct)
        self.assertEqual(summary.readings, 0)
        self.assertIn("no in-band", summary.reason)


if __name__ == "__main__":
    unittest.main()

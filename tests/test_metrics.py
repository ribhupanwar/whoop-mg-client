"""Known-value tests for the published metric definitions."""

import math
import unittest

from whoop.metrics import (
    ACF1_FLOOR,
    ACF1_MIN_PAIRS,
    RR_COVERAGE_CEILING,
    RR_COVERAGE_MIN_SPAN_S,
    age_predicted_max_hr,
    hrv,
    hrv_extended_diagnostics,
    hrv_from_rr,
    hr_reserve_ratio,
    median_of_windowed_rmssd,
    nn_diff_acf1,
    nn_intervals,
    pnn50,
    resting_heart_rate,
    resting_hrv,
    rmssd,
    rr_coverage,
    sdnn,
    sws_resting_hrv,
    trimp,
)
from whoop.records import RecordHeader, V18Sample


def sample(unix, hr, accel=0.0, rr=()) -> V18Sample:
    return V18Sample(
        header=RecordHeader(
            version=18, flags=0x80, record_index=unix, unix=unix, subsec_q15=0
        ),
        heart_rate=hr,
        rr_intervals_ms=list(rr),
        dynamic_accel_g=accel,
    )


class TestNnFiltering(unittest.TestCase):
    def test_clean_series_passes_through(self):
        series = [800.0, 810.0, 795.0, 805.0, 800.0]
        self.assertEqual(nn_intervals(series), series)

    def test_ectopic_pair_rejected_but_recovery_beat_kept(self):
        # A premature beat shortens one interval and lengthens the next. Both
        # are artefacts; the normal beat after them must survive.
        series = [800.0, 800.0, 400.0, 1200.0, 805.0, 800.0]
        self.assertEqual(nn_intervals(series), [800.0, 800.0, 805.0, 800.0])

    def test_out_of_range_rejected(self):
        self.assertEqual(nn_intervals([50.0, 800.0, 5000.0, 810.0]), [800.0, 810.0])

    def test_empty(self):
        self.assertEqual(nn_intervals([]), [])

    def test_leading_artefact_must_not_become_the_reference(self):
        # Opening of the real 856 s quiet run in rest1.jsonl. The first interval
        # is an artefact; seeding the median from it used to reject all 1066
        # normal beats that followed, because rejects never enter the median.
        series = [449.0, 840.0, 838.0, 744.0, 794.0, 849.0, 837.0, 859.0]
        series += [800.0] * 40
        kept = nn_intervals(series)
        self.assertNotIn(449.0, kept)
        self.assertGreater(len(kept), 40)
        self.assertEqual(kept[:6], [840.0, 838.0, 744.0, 794.0, 849.0, 837.0])

    def test_reference_recovers_after_a_long_artefact_burst(self):
        series = [800.0, 805.0] + [1500.0, 350.0] * 6 + [790.0, 800.0, 810.0]
        kept = nn_intervals(series)
        self.assertEqual(kept, [800.0, 805.0, 790.0, 800.0, 810.0])

    def test_two_beats_are_needed_to_seed(self):
        self.assertEqual(nn_intervals([800.0]), [])

    def test_seed_candidate_survives_a_sensor_dropout(self):
        # An out-of-range value carries no interval information, so it must not
        # discard a pending seed that the next real beat can corroborate.
        self.assertEqual(nn_intervals([800.0, 5000.0, 810.0]), [800.0, 810.0])


class TestObservationOnlyDiagnostics(unittest.TestCase):
    """Tests for observation-only diagnostics: ACF1 jitter gate and RR coverage."""

    def test_nn_diff_acf1_constant_series_returns_none(self):
        # Constant series has zero variance -> returns None
        self.assertIsNone(nn_diff_acf1([800.0, 800.0, 800.0, 800.0]))

    def test_nn_diff_acf1_insufficient_pairs_returns_none(self):
        # Fewer than ACF1_MIN_PAIRS (30) pairs returns None
        self.assertIsNone(nn_diff_acf1([800.0, 810.0] * 10))  # 19 pairs < 30

    def test_nn_diff_acf1_smooth_tachogram_positive_acf1(self):
        # Smooth tachogram with RSA-like pattern: successive differences
        # are positively correlated -> ACF1 > 0
        nn = []
        base = 800.0
        for i in range(100):
            nn.append(base + 20 * math.sin(i * 0.1))  # Slow modulation
        acf1 = nn_diff_acf1(nn)
        self.assertIsNotNone(acf1)
        self.assertGreater(acf1, 0.5)  # Strong positive correlation

    def test_nn_diff_acf1_white_noise_below_floor(self):
        # White noise NN intervals: differences have ACF1 ≈ -0.5
        # This should be below the OpenStrap floor of -0.35
        import random
        random.seed(42)
        nn = [800.0 + random.uniform(-50, 50) for _ in range(200)]
        acf1 = nn_diff_acf1(nn)
        self.assertIsNotNone(acf1)
        self.assertLess(acf1, ACF1_FLOOR)  # Should be below -0.35

    def test_nn_diff_acf1_alternating_pattern_strong_negative(self):
        # Alternating pattern (800, 810, 800, 810...) -> differences
        # alternate +10, -10 -> perfect negative correlation -> ACF1 ≈ -1
        nn = [800.0, 810.0] * 100
        acf1 = nn_diff_acf1(nn)
        self.assertIsNotNone(acf1)
        self.assertLess(acf1, -0.9)

    def test_rr_coverage_normal_stream(self):
        # Normal RR stream: sum of RR ≈ wall-clock span
        # Beat-end timestamps: each beat ends at 800ms intervals
        rr = [800.0] * 1000
        timestamps = [800 * (i + 1) for i in range(1000)]
        cov = rr_coverage(rr, timestamps)
        self.assertIsNotNone(cov)
        self.assertAlmostEqual(cov, 1.0, places=2)

    def test_rr_coverage_duplicate_beats_over_counted(self):
        # Duplicate beats: more beat-time than elapsed time
        rr = [800.0] * 2000
        timestamps = [800 * (i + 1) for i in range(1000)] * 2
        cov = rr_coverage(rr, timestamps)
        self.assertIsNotNone(cov)
        self.assertGreater(cov, RR_COVERAGE_CEILING)

    def test_rr_coverage_insufficient_span_returns_none(self):
        # Span < RR_COVERAGE_MIN_SPAN_S (600s) returns None
        # 500 beats at 800ms = 400s < 600s
        rr = [800.0] * 500
        timestamps = [800 * (i + 1) for i in range(500)]
        self.assertIsNone(rr_coverage(rr, timestamps))

    def test_rr_coverage_mismatched_lengths_returns_none(self):
        self.assertIsNone(rr_coverage([800.0, 810.0], [0]))

    def test_extended_diagnostics_includes_acf1_and_coverage(self):
        # Create a valid sleep period with RR data - need enough beats for coverage
        # Use a realistic RSA pattern: breathing at ~15 breaths/min = 0.25 Hz
        # At 60 bpm (1 beat/sec), this is 1 cycle per 4 beats
        # This gives ACF1 ≈ 0 for the successive differences (above floor of -0.35)
        import math
        import random
        random.seed(42)
        rows = []
        for i in range(1000):
            # RSA: 4 beats per breath cycle, plus small physiological noise
            rr_val = 800 + 20 * math.sin(i * 2 * math.pi / 4) + random.uniform(-2, 2)
            rows.append(sample(i, 60, 0.01, (int(rr_val), int(rr_val + 5))))
        diag = hrv_extended_diagnostics(rows)
        self.assertIsNotNone(diag.nn_diff_acf1)
        self.assertIsNotNone(diag.rr_coverage_ratio)
        self.assertIsNotNone(diag.acf1_below_floor)
        self.assertIsNotNone(diag.rr_over_coverage)
        self.assertFalse(diag.acf1_below_floor)  # RSA pattern should be above floor
        self.assertFalse(diag.rr_over_coverage)  # Normal coverage

    def test_extended_diagnostics_with_sws_epochs(self):
        rows = [sample(i, 60, 0.01, (800, 810)) for i in range(500)]
        diag = hrv_extended_diagnostics(rows, sws_epochs=[(100, 400)])
        self.assertEqual(diag.selected_calculation_window, "SWS_DEEP_SLEEP")

    def test_median_of_windowed_rmssd_basic(self):
        # Create a clean NN series with known RMSSD
        nn = [800.0, 810.0] * 50  # Alternating 800/810 -> RMSSD = 10
        timestamps = list(range(0, 100))
        rmssd = median_of_windowed_rmssd(nn, timestamps, window_seconds=300)
        self.assertIsNotNone(rmssd)
        # Each 5-min window has 300 beats -> 299 diffs, all ±10 -> RMSSD = 10
        self.assertAlmostEqual(rmssd, 10.0, places=1)

    def test_median_of_windowed_rmssd_insufficient_data(self):
        nn = [800.0, 810.0] * 5  # Only 10 beats
        timestamps = list(range(0, 10))
        self.assertIsNone(median_of_windowed_rmssd(nn, timestamps))

    def test_median_of_windowed_rmssd_mismatched_lengths(self):
        self.assertIsNone(median_of_windowed_rmssd([800.0, 810.0], [0]))


class TestRestingHrv(unittest.TestCase):
    def test_absent_without_a_long_enough_quiet_run(self):
        result, window = resting_hrv([sample(i, 70, 0.01, (800, 810)) for i in range(30)])
        self.assertEqual(window, 0)
        self.assertIsNone(result.rmssd_ms)

    def test_motion_seconds_are_excluded(self):
        rows = [sample(i, 70, 0.01, (800, 810)) for i in range(120)]
        rows += [sample(120 + i, 110, 0.9, (400, 1200)) for i in range(120)]
        result, window = resting_hrv(rows)
        self.assertEqual(window, 120)
        self.assertEqual(result.beats, 240)

    def test_longest_run_wins_over_an_earlier_short_one(self):
        rows = [sample(i, 70, 0.01, (800, 810)) for i in range(70)]
        rows += [sample(200 + i, 70, 0.01, (700, 720)) for i in range(200)]
        result, window = resting_hrv(rows)
        self.assertEqual(window, 200)
        self.assertAlmostEqual(result.mean_rr_ms, 710.0, places=6)

    def test_a_gap_splits_the_run(self):
        rows = [sample(i, 70, 0.01, (800, 810)) for i in range(100)]
        rows += [sample(500 + i, 70, 0.01, (800, 810)) for i in range(100)]
        _, window = resting_hrv(rows)
        self.assertEqual(window, 100)

    def test_missing_accel_is_not_assumed_quiet(self):
        rows = [sample(i, 70, 0.01, (800, 810)) for i in range(120)]
        for row in rows:
            row.dynamic_accel_g = None
        _, window = resting_hrv(rows)
        self.assertEqual(window, 0)

    def test_pooling_the_whole_capture_would_inflate_rmssd(self):
        quiet = [sample(i, 70, 0.01, (800, 802)) for i in range(200)]
        moving = [sample(200 + i, 110, 0.9, (760, 850)) for i in range(200)]
        resting, _ = resting_hrv(quiet + moving)
        pooled = hrv(quiet + moving)
        self.assertLess(resting.rmssd_ms, 5.0)
        self.assertGreater(pooled.rmssd_ms, 40.0)

    def test_sws_resting_hrv_selects_sws_when_available(self):
        # Light sleep (0 to 120s): RMSSD ~ 10 ms (800, 810)
        light = [sample(i, 65, 0.01, (800, 810)) for i in range(120)]
        # SWS deep sleep (120 to 240s): RMSSD ~ 30 ms (780, 810)
        deep = [sample(120 + i, 58, 0.01, (780, 810)) for i in range(120)]
        all_samples = light + deep

        res, win, is_sws = sws_resting_hrv(all_samples, deep_epochs=[(120, 239)], min_window_s=60)
        self.assertTrue(is_sws)
        self.assertEqual(win, 120)
        self.assertAlmostEqual(res.rmssd_ms, 30.0, places=1)

    def test_sws_resting_hrv_falls_back_when_no_sws(self):
        light = [sample(i, 65, 0.01, (800, 810)) for i in range(120)]
        res, win, is_sws = sws_resting_hrv(light, deep_epochs=None, min_window_s=60)
        self.assertFalse(is_sws)
        self.assertEqual(win, 120)
        self.assertAlmostEqual(res.rmssd_ms, 10.0, places=1)


class TestHrvKnownValues(unittest.TestCase):
    def test_rmssd_known_vector(self):
        # diffs 10, -20, 15 -> mean square 725/3 -> sqrt = 15.5456
        self.assertAlmostEqual(rmssd([800, 810, 790, 805]), 15.5456, places=3)

    def test_rmssd_constant_is_zero(self):
        self.assertEqual(rmssd([800, 800, 800]), 0.0)

    def test_rmssd_needs_two_beats(self):
        self.assertIsNone(rmssd([800]))
        self.assertIsNone(rmssd([]))

    def test_sdnn_known_vector(self):
        self.assertAlmostEqual(sdnn([100, 102, 104]), 2.0, places=6)

    def test_pnn50_known_vector(self):
        # |60|, |60|, |10| -> two of three exceed 50 ms
        self.assertAlmostEqual(pnn50([800, 860, 800, 810]), 200.0 / 3.0, places=6)

    def test_pnn50_none_when_flat(self):
        self.assertEqual(pnn50([800, 800, 800]), 0.0)

    def test_hrv_result_counts_and_ln(self):
        result = hrv_from_rr([800.0, 800.0, 400.0, 1200.0, 805.0, 800.0])
        self.assertEqual(result.beats, 6)
        self.assertEqual(result.nn_beats, 4)
        self.assertEqual(result.rejected_beats, 2)
        self.assertAlmostEqual(result.ln_rmssd, math.log(result.rmssd_ms), places=9)

    def test_hrv_empty_is_absent_not_zero(self):
        result = hrv_from_rr([])
        self.assertIsNone(result.rmssd_ms)
        self.assertIsNone(result.ln_rmssd)
        self.assertIsNone(result.mean_rr_ms)

    def test_hrv_from_samples(self):
        rows = [sample(1, 70, rr=(800, 810)), sample(2, 70, rr=(790, 805))]
        self.assertAlmostEqual(hrv(rows).rmssd_ms, 15.5456, places=3)


class TestHeartRateReserve(unittest.TestCase):
    def test_tanaka(self):
        self.assertAlmostEqual(age_predicted_max_hr(40), 180.0, places=6)

    def test_tanaka_rejects_nonpositive_age(self):
        with self.assertRaises(ValueError):
            age_predicted_max_hr(0)

    def test_karvonen(self):
        self.assertAlmostEqual(hr_reserve_ratio(130, 50, 190), 80.0 / 140.0, places=9)

    def test_clipped_to_unit_interval(self):
        self.assertEqual(hr_reserve_ratio(40, 50, 190), 0.0)
        self.assertEqual(hr_reserve_ratio(250, 50, 190), 1.0)

    def test_invalid_range_rejected(self):
        with self.assertRaises(ValueError):
            hr_reserve_ratio(130, 190, 190)


class TestTrimp(unittest.TestCase):
    def test_known_constant_effort(self):
        # 60 s at HR 130, RHR 50, MHR 190 -> HRR 4/7.
        # TRIMP = 1 min * (4/7) * 0.64 * exp(1.92 * 4/7) = 1.0956
        rows = [sample(i, 130) for i in range(60)]
        self.assertAlmostEqual(trimp(rows, max_hr=190, resting_hr=50), 1.0956, places=3)

    def test_female_coefficients_differ(self):
        rows = [sample(i, 130) for i in range(60)]
        male = trimp(rows, 190, 50, sex="male")
        female = trimp(rows, 190, 50, sex="female")
        self.assertNotAlmostEqual(male, female, places=3)

    def test_resting_effort_is_near_zero(self):
        rows = [sample(i, 50) for i in range(60)]
        self.assertAlmostEqual(trimp(rows, 190, 50), 0.0, places=9)

    def test_off_wrist_seconds_do_not_contribute(self):
        rows = [sample(i, 0) for i in range(60)]
        self.assertIsNone(trimp(rows, 190, 50))

    def test_invalid_sex_rejected(self):
        with self.assertRaises(ValueError):
            trimp([sample(1, 130)], 190, 50, sex="unknown")

    def test_invalid_hr_range_rejected(self):
        with self.assertRaises(ValueError):
            trimp([sample(1, 130)], 50, 50)


class TestRestingHeartRate(unittest.TestCase):
    def test_flat_quiet_window(self):
        rows = [sample(i, 60) for i in range(120)]
        self.assertAlmostEqual(resting_heart_rate(rows), 60.0, places=6)

    def test_single_artefact_beat_does_not_set_rhr(self):
        rows = [sample(i, 40 if i == 30 else 70) for i in range(60)]
        self.assertAlmostEqual(resting_heart_rate(rows), 69.5, places=6)

    def test_out_of_range_hr_rejected(self):
        # HR below 35 or above 220 should be filtered out, splitting runs
        rows = [
            sample(0, 55),
            sample(1, 30),  # below 35 - filtered
            sample(2, 57),
            sample(3, 58),
        ]
        # Without filtering: 4-second run, window_s=3 gives windows [47.33, 48.33], median=47.83
        # With filtering: runs are [0] and [2,3], both < 3 seconds, so no valid window
        self.assertIsNone(resting_heart_rate(rows, window_s=3))

    def test_lowest_window_is_chosen(self):
        rows = [sample(i, 75 if i < 60 else 58) for i in range(180)]
        self.assertAlmostEqual(resting_heart_rate(rows), 58.0, places=6)

    def test_gap_breaks_the_window(self):
        rows = [sample(i, 50) for i in range(30)]
        rows += [sample(i, 50) for i in range(100, 130)]
        self.assertIsNone(resting_heart_rate(rows))

    def test_motion_excludes_seconds(self):
        rows = [sample(i, 55, accel=0.5) for i in range(120)]
        self.assertIsNone(resting_heart_rate(rows))

    def test_missing_accel_is_not_assumed_quiet(self):
        rows = [sample(i, 55, accel=None) for i in range(120)]
        self.assertIsNone(resting_heart_rate(rows))

    def test_off_wrist_excluded(self):
        rows = [sample(i, 0) for i in range(120)]
        self.assertIsNone(resting_heart_rate(rows))

    def test_short_window_is_absent(self):
        rows = [sample(i, 55) for i in range(30)]
        self.assertIsNone(resting_heart_rate(rows))


class TestWindowedSleepHRV(unittest.TestCase):
    def test_averages_multiple_5min_windows_eliminating_longest_run_bias(self):
        from whoop.metrics import windowed_sleep_hrv
        # Window 1 (0..299): RMSSD = 20 ms (alternating 800, 820)
        # Window 2 (300..599): RMSSD = 40 ms (alternating 800, 840)
        # Window 3 (600..899): RMSSD = 60 ms (alternating 800, 860)
        w1 = [sample(t, 60, rr=[800 if t % 2 == 0 else 820], accel=0.02) for t in range(0, 300)]
        w2 = [sample(t, 60, rr=[800 if t % 2 == 0 else 840], accel=0.02) for t in range(300, 600)]
        w3 = [sample(t, 60, rr=[800 if t % 2 == 0 else 860], accel=0.02) for t in range(600, 900)]
        res, secs, n_win, used_fb = windowed_sleep_hrv(w1 + w2 + w3)
        self.assertEqual(n_win, 3)
        self.assertFalse(used_fb)
        self.assertIsNotNone(res.rmssd_ms)
        # Mean of (20, 40, 60) = 40 ms
        self.assertAlmostEqual(res.rmssd_ms, 40.0, delta=0.5)
        self.assertEqual(secs, 900)

    def test_rejects_overcounted_5min_window_without_losing_valid_windows(self):
        from whoop.metrics import windowed_sleep_hrv
        # Window 1 (0..299): normal 1 beat/sec -> 40 ms RMSSD
        w1 = [sample(t, 60, rr=[800 if t % 2 == 0 else 840], accel=0.02) for t in range(0, 300)]
        # Window 2 (300..599): over-counted 3 beats/sec -> >2.4x elapsed -> rejected
        w2 = [sample(t, 60, rr=[800, 900, 800], accel=0.02) for t in range(300, 600)]
        res, secs, n_win, _ = windowed_sleep_hrv(w1 + w2)
        self.assertEqual(n_win, 1)
        self.assertAlmostEqual(res.rmssd_ms, 40.0, delta=0.5)
        self.assertEqual(secs, 300)


if __name__ == "__main__":
    unittest.main()
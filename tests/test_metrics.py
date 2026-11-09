"""Known-value tests for the published metric definitions."""

import math
import unittest

from whoop.metrics import (
    age_predicted_max_hr,
    hrv,
    hrv_from_rr,
    hr_reserve_ratio,
    nn_intervals,
    pnn50,
    resting_heart_rate,
    resting_hrv,
    rmssd,
    sdnn,
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


if __name__ == "__main__":
    unittest.main()
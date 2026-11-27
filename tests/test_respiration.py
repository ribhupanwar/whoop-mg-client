"""Tests for the RSA respiratory-rate estimate from R-R timing."""

import math
import unittest

from whoop.health import _rr_segments, resp_rate_from_rr
from dataclasses import replace
from whoop.records import RecordHeader, V18Sample


def sample(unix, rr=()) -> V18Sample:
    return V18Sample(
        header=RecordHeader(
            version=18, flags=0x80, record_index=unix, unix=unix, subsec_q15=0
        ),
        heart_rate=58,
        rr_intervals_ms=list(rr),
        dynamic_accel_g=0.01,
    )


def rsa_series(start, seconds, bpm, amplitude_ms=80, base_ms=1000):
    """One beat per second with a sinusoidal R-R modulation at `bpm`."""
    phase = 2.0 * math.pi * (bpm / 60.0)
    return [
        sample(
            start + i,
            [int(round(base_ms + amplitude_ms * math.sin(phase * (start + i))))],
        )
        for i in range(seconds)
    ]


class TestRespRateFromRR(unittest.TestCase):
    def test_recovers_a_synthetic_15_breath_signal(self):
        result = resp_rate_from_rr(rsa_series(0, 900, 15))
        self.assertIsNotNone(result.breaths_per_min)
        self.assertGreaterEqual(result.breaths_per_min, 13.0)
        self.assertLessEqual(result.breaths_per_min, 17.0)
        self.assertEqual(result.beats, 900)
        self.assertGreaterEqual(result.windows, 1)
        self.assertIsNone(result.reason)

    def test_flat_tachogram_returns_no_estimate(self):
        rows = [sample(i, [1000]) for i in range(900)]
        result = resp_rate_from_rr(rows)
        self.assertIsNone(result.breaths_per_min)
        self.assertIn("no usable RSA peak train", result.reason)

    def test_too_few_beats_returns_a_reason(self):
        result = resp_rate_from_rr(rsa_series(0, 20, 15))
        self.assertIsNone(result.breaths_per_min)
        self.assertIn("at least 30", result.reason)
        self.assertEqual(result.beats, 20)

    def test_a_dropout_splits_the_series_without_fabricating_a_breath(self):
        rows = (
            rsa_series(0, 300, 15)
            + [sample(300 + i, ()) for i in range(60)]
            + rsa_series(360, 300, 15)
        )
        result = resp_rate_from_rr(rows)
        self.assertIsNotNone(result.breaths_per_min)
        self.assertGreaterEqual(result.breaths_per_min, 13.0)
        self.assertLessEqual(result.breaths_per_min, 17.0)
        self.assertEqual(result.beats, 600)
        self.assertGreaterEqual(result.windows, 2)

    def test_replayed_invalid_padding_cannot_displace_valid_beats(self):
        good = sample(0, [900, 920])
        bad = sample(0, [900, 0, 65535])
        for rows in ([bad, good], [good, bad]):
            self.assertEqual(_rr_segments(rows), [[(0, 900), (0, 920)]])

    def test_respiration_rejects_overcounted_beat_time(self):
        rows = [sample(i, [800, 840 if i % 2 else 880]) for i in range(600)]
        result = resp_rate_from_rr(rows)
        self.assertIsNone(result.breaths_per_min)
        self.assertIn("exceeded elapsed", result.reason)

    def test_compressed_beat_time_is_rejected(self):
        result = resp_rate_from_rr(rsa_series(0, 900, 11, amplitude_ms=40, base_ms=500))
        self.assertIsNone(result.breaths_per_min)
        self.assertIn("insufficient RR beat-time coverage", result.reason)

    def test_dominant_out_of_band_peak_cannot_masquerade_as_in_band_respiration(self):
        from whoop.health import _spectral_window_rates
        mixed = [80 * math.sin(2 * math.pi * 0.45 * i / 4)
                 + 20 * math.sin(2 * math.pi * (17 / 60) * i / 4)
                 for i in range(1200)]
        self.assertEqual(_spectral_window_rates(mixed, 0.8), [])
        in_band = [80 * math.sin(2 * math.pi * (17 / 60) * i / 4)
                   for i in range(1200)]
        result = _spectral_window_rates(in_band, 0.8)
        self.assertEqual(len(result), 1)
        self.assertAlmostEqual(result[0], 17, delta=0.4)

    def test_slow_respiration_is_not_doubled(self):
        result = resp_rate_from_rr(rsa_series(0, 900, 11))
        self.assertIsNotNone(result.breaths_per_min)
        self.assertAlmostEqual(result.breaths_per_min, 11, delta=1)

    def test_sparse_accepted_peaks_do_not_represent_whole_night(self):
        convincing = rsa_series(0, 900, 15)
        flat = [sample(t, [1000]) for t in range(960, 2760)]
        result = resp_rate_from_rr(convincing + flat)
        self.assertIsNone(result.breaths_per_min)
        self.assertIn("Insufficient RSA consensus", result.reason)

    def test_motion_and_missing_rr_are_boundaries(self):
        left = sample(0, [900])
        right = sample(2, [920])
        for middle in (
            sample(1, []),
            replace(sample(1, [910]), heart_rate=0),
            replace(sample(1, [910]), dynamic_accel_g=None),
            replace(sample(1, [910]), dynamic_accel_g=-0.01),
            replace(sample(1, [910]), dynamic_accel_g=float("nan")),
            replace(sample(1, [910]), dynamic_accel_g=0.5),
        ):
            self.assertEqual(_rr_segments([left, middle, right]), [[(0, 900)], [(2, 920)]])

    def test_out_of_band_breathing_is_rejected(self):
        # 5 breaths/min is a 12 s interval, outside the 2.5-10 s estimator band.
        result = resp_rate_from_rr(rsa_series(0, 900, 5))
        self.assertIsNone(result.breaths_per_min)
        self.assertIsNotNone(result.reason)

    def test_spectral_rsa_recovers_rate_over_multiple_windows(self):
        # 1800s -> 6 windows -> triggers spectral DFT path (>= 3 windows)
        result = resp_rate_from_rr(rsa_series(0, 1800, 18))
        self.assertIsNotNone(result.breaths_per_min)
        self.assertAlmostEqual(result.breaths_per_min, 18.0, delta=0.6)
        self.assertGreaterEqual(result.windows, 3)


if __name__ == "__main__":
    unittest.main()

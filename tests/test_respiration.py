"""Tests for the RSA respiratory-rate estimate from R-R timing."""

import math
import unittest

from whoop.health import resp_rate_from_rr
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

    def test_out_of_band_breathing_is_rejected(self):
        # 5 breaths/min is a 12 s interval, outside the 2.5-10 s estimator band.
        result = resp_rate_from_rr(rsa_series(0, 900, 5))
        self.assertIsNone(result.breaths_per_min)
        self.assertIsNotNone(result.reason)


if __name__ == "__main__":
    unittest.main()

import unittest
from whoop.records import RecordHeader, V18Sample
from whoop.metrics import sws_resting_hrv, resting_hrv, rmssd
from whoop.health import detect_sleep, MAX_SLEEP_WINDOW_S, MIN_SLEEP_S, SleepPeriod
from whoop.activity import suppress_duplicates, ActivitySession


def make_sample(unix: int, hr: int, rr_ms: list[int] | None = None, accel_g: float = 0.02) -> V18Sample:
    header = RecordHeader(
        version=18,
        flags=0,
        record_index=unix,
        unix=unix,
        subsec_q15=0,
    )
    return V18Sample(
        header=header,
        heart_rate=hr,
        dynamic_accel_g=accel_g,
        rr_intervals_ms=rr_ms or [],
    )


class TestWHOOP5802AlgorithmParity(unittest.TestCase):
    def test_sws_resting_hrv_preferred_when_sufficient_data(self):
        """When SWS deep epochs contain >= 20 NN beats, sws_resting_hrv returns SWS RMSSD."""
        base_unix = 1700000000
        samples = []
        # First 600s: generic quiet rest with RR ~ 900ms
        for t in range(base_unix, base_unix + 600):
            samples.append(make_sample(t, hr=60, rr_ms=[900, 910] if t % 10 == 0 else []))
        # Next 400s: SWS deep sleep with high parasympathetic tone (RR ~ 1050ms)
        sws_start = base_unix + 600
        sws_end = base_unix + 1000
        for t in range(sws_start, sws_end):
            samples.append(make_sample(t, hr=52, rr_ms=[1040, 1060] if t % 10 == 0 else []))

        deep_epochs = [(sws_start, sws_end)]
        res, window_s, is_sws = sws_resting_hrv(
            samples, deep_epochs=deep_epochs, min_window_s=300
        )
        self.assertTrue(is_sws)
        self.assertIsNotNone(res.rmssd_ms)
        self.assertGreaterEqual(res.nn_beats, 20)

    def test_sws_resting_hrv_fallback_to_quiet_when_insufficient_deep(self):
        """When deep sleep has < 20 NN beats, sws_resting_hrv safely falls back to quiet window."""
        base_unix = 1700000000
        samples = []
        for t in range(base_unix, base_unix + 600):
            samples.append(make_sample(t, hr=60, rr_ms=[900, 910] if t % 15 == 0 else []))
        # Deep sleep with only 2 beats
        deep_epochs = [(base_unix + 500, base_unix + 520)]

        res, window_s, is_sws = sws_resting_hrv(
            samples, deep_epochs=deep_epochs, min_window_s=300
        )
        self.assertFalse(is_sws)
        self.assertIsNotNone(res.rmssd_ms)

    def test_sleep_window_ceiling_twelve_hours(self):
        """WHOOP 5.80.2 SleepWindow.swift TWELVE_HOUR limit rejects runs > 12 hours."""
        self.assertEqual(MAX_SLEEP_WINDOW_S, 12 * 3600)
        self.assertEqual(MAX_SLEEP_WINDOW_S, 43200)

        base_unix = 1700000000
        # Create active samples to establish active median
        active_samples = [make_sample(base_unix + t, hr=85, accel_g=0.25) for t in range(300)]
        # Create 13-hour continuous quiet run (> 12 hours)
        excessive_run = [make_sample(base_unix + 300 + t, hr=55, accel_g=0.01) for t in range(13 * 3600)]

        periods = detect_sleep(active_samples + excessive_run)
        # Should not include a 13-hour period
        for p in periods:
            self.assertLessEqual(p.duration_s, MAX_SLEEP_WINDOW_S)

    def test_activity_duplicate_suppression(self):
        """Auto-detected activities overlapping >= 50% are suppressed."""
        sess1 = ActivitySession(
            start_unix=1000,
            end_unix=2000,
            kind="run",
            steps=1200,
            mean_hr=150.0,
            walk_ticks=0,
            run_ticks=500,
        )
        # sess2 overlaps with sess1 from 1200 to 2000 (800s out of 1000s duration = 80%)
        sess2 = ActivitySession(
            start_unix=1200,
            end_unix=2200,
            kind="run",
            steps=1100,
            mean_hr=148.0,
            walk_ticks=0,
            run_ticks=480,
        )
        # sess3 is non-overlapping (starts at 3000)
        sess3 = ActivitySession(
            start_unix=3000,
            end_unix=4000,
            kind="walk",
            steps=800,
            mean_hr=110.0,
            walk_ticks=400,
            run_ticks=0,
        )

        suppressed = suppress_duplicates([sess1, sess2, sess3])
        self.assertEqual(len(suppressed), 2)
        self.assertEqual(suppressed[0].start_unix, 1000)
        self.assertEqual(suppressed[1].start_unix, 3000)


    def test_duplicate_overlap_exact_half_inclusive(self):
        def session(start, end):
            return ActivitySession(start_unix=start, end_unix=end, kind="run",
                                   steps=0, mean_hr=100.0, walk_ticks=0, run_ticks=0)
        result = suppress_duplicates([session(1000, 1299), session(1150, 1449)])
        self.assertEqual(len(result), 1)

    def test_single_second_duplicate_and_disjoint(self):
        def session(start, end):
            return ActivitySession(start_unix=start, end_unix=end, kind="walk",
                                   steps=0, mean_hr=100.0, walk_ticks=0, run_ticks=0)
        self.assertEqual(len(suppress_duplicates([session(1000, 1100), session(1050, 1050)])), 1)
        self.assertEqual(len(suppress_duplicates([session(1000, 1100), session(1101, 1200)])), 2)



if __name__ == "__main__":
    unittest.main()

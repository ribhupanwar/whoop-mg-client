"""
tests/test_gym_comparison.py

Unit tests for DualBandGymComparator and ControlledGymTestExporter.
Verifies parsing, second-by-second alignment, cross-correlation lag detection,
statistical error computation, and report generation for controlled gym trials.
"""

import unittest
from whoop.accuracy.gym_comparison import (
    DualBandGymComparator,
    GymSample,
    WorkoutTelemetry,
)


class TestDualBandGymComparison(unittest.TestCase):
    def setUp(self):
        self.comparator = DualBandGymComparator(max_allowed_hr_mae=6.0, min_allowed_pearson_r=0.88)

    def test_parse_strap_workout_csv(self):
        """Parse simulated STRAP WorkoutDiagnostics CSV."""
        strap_csv = """# STRAP Controlled Workout Telemetry Export
# Activity: Weightlifting
# Start: 1700000000 | End: 1700000010 | Duration: 10s
# Mean HR: 142.5 bpm | Max HR: 165.0 bpm
# Workout Strain: 8.40 | Day Strain: 12.10
# Active Kcal: 185.0 | Steps: 240
# Detection Confidence: HIGH | Reason: ELEVATED_HR_PERSISTENT_MOTION
# Firmware: 50.42.1.0 | Decoder: V18-Gen5
unix,iso8601,record_index,subsec_q15,heart_rate_bpm,rr_ms,dynamic_accel_g,gravity_x_g,gravity_y_g,gravity_z_g,band_state,hr_quality_flags,is_workout_epoch
1700000000,2023-11-14T22:13:20.000Z,1,0,135,444|450,0.1250,0.1000,-0.8500,-0.5000,0,1,1
1700000001,2023-11-14T22:13:21.000Z,2,0,140,430,0.2200,0.1200,-0.8400,-0.5100,0,1,1
1700000002,2023-11-14T22:13:22.000Z,3,0,145,415,0.3500,0.1500,-0.8200,-0.5300,0,1,1
1700000003,2023-11-14T22:13:23.000Z,4,0,150,400,0.4100,0.1800,-0.8000,-0.5500,0,1,1
1700000004,2023-11-14T22:13:24.000Z,5,0,155,390,0.4800,0.2000,-0.7800,-0.5800,0,1,1
"""
        telem = self.comparator.parse_strap_workout_csv(strap_csv)
        self.assertEqual(telem.source, "STRAP")
        self.assertEqual(telem.activity_kind, "Weightlifting")
        self.assertEqual(telem.start_unix, 1700000000)
        self.assertEqual(telem.end_unix, 1700000004)
        self.assertEqual(len(telem.samples), 5)
        self.assertEqual(telem.mean_hr, 142.5)
        self.assertEqual(telem.max_hr, 165.0)
        self.assertEqual(telem.workout_strain, 8.40)
        self.assertEqual(telem.firmware_version, "50.42.1.0")

    def test_parse_whoop_workout_stream(self):
        """Parse simulated WHOOP workout heart-rate CSV."""
        whoop_csv = """unix,heart_rate_bpm
1700000000,136
1700000001,141
1700000002,144
1700000003,151
1700000004,154
"""
        telem = self.comparator.parse_whoop_workout_stream(
            whoop_csv,
            activity_kind="Weightlifting",
            start_unix=1700000000,
            end_unix=1700000004,
            whoop_strain=8.5,
            whoop_kcal=190.0,
        )
        self.assertEqual(telem.source, "WHOOP")
        self.assertEqual(len(telem.samples), 5)
        self.assertAlmostEqual(telem.mean_hr, 145.2, places=1)
        self.assertEqual(telem.max_hr, 154)
        self.assertEqual(telem.workout_strain, 8.5)

    def test_compare_aligned_gym_telemetry(self):
        """Compare synthetic aligned workout streams with 1 bpm error."""
        s_samples = [GymSample(unix=1700000000 + i, heart_rate=140 + (i % 10)) for i in range(100)]
        w_samples = [GymSample(unix=1700000000 + i, heart_rate=141 + (i % 10)) for i in range(100)]

        s_telem = WorkoutTelemetry(
            source="STRAP",
            activity_kind="Weightlifting",
            start_unix=1700000000,
            end_unix=1700000099,
            samples=s_samples,
            mean_hr=144.5,
            max_hr=149.0,
            workout_strain=9.2,
            active_kcal=210.0,
        )
        w_telem = WorkoutTelemetry(
            source="WHOOP",
            activity_kind="Weightlifting",
            start_unix=1700000000,
            end_unix=1700000099,
            samples=w_samples,
            mean_hr=145.5,
            max_hr=150.0,
            workout_strain=9.3,
            active_kcal=215.0,
        )

        res = self.comparator.compare(s_telem, w_telem)
        self.assertTrue(res.is_parity_acceptable)
        self.assertEqual(res.optimal_lag_seconds, 0)
        self.assertAlmostEqual(res.hr_mae, 1.0, places=2)
        self.assertAlmostEqual(res.hr_rmse, 1.0, places=2)
        self.assertGreaterEqual(res.hr_pearson_r, 0.99)
        self.assertAlmostEqual(res.strain_delta, -0.1, places=1)

        # Check Markdown report generation
        md = self.comparator.generate_markdown_report(res)
        self.assertIn("STRAP Controlled Dual-Band Gym Trial Report", md)
        self.assertIn("PARITY VERIFIED", md)
        self.assertIn("Mean Absolute Error (MAE)", md)

    def test_compare_with_clock_skew(self):
        """Detect clock skew when STRAP stream is shifted by 3 seconds."""
        s_samples = [GymSample(unix=1700000000 + i, heart_rate=130 + (i * 2)) for i in range(50)]
        # Shift WHOOP by +3 seconds
        w_samples = [GymSample(unix=1700000003 + i, heart_rate=130 + (i * 2)) for i in range(50)]

        s_telem = WorkoutTelemetry(
            source="STRAP",
            activity_kind="Weightlifting",
            start_unix=1700000000,
            end_unix=1700000049,
            samples=s_samples,
        )
        w_telem = WorkoutTelemetry(
            source="WHOOP",
            activity_kind="Weightlifting",
            start_unix=1700000003,
            end_unix=1700000052,
            samples=w_samples,
        )

        res = self.comparator.compare(s_telem, w_telem)
        self.assertEqual(res.optimal_lag_seconds, 3)
        self.assertAlmostEqual(res.hr_mae, 0.0, places=2)
        self.assertAlmostEqual(res.hr_pearson_r, 1.0, places=2)


if __name__ == "__main__":
    unittest.main()

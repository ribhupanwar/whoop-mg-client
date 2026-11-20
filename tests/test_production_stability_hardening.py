"""
tests/test_production_stability_hardening.py

Unit and regression tests verifying production stability hardening:
- 100 BLE Reconnect Cycles (exponential backoff bounding, state transitions)
- 100 Interrupted Historical Syncs (SQLite WAL atomicity, checkpoint rollback, deduplication)
- 24-Hour Continuous Replay (throughput, validity)
- Sleep Transitions & Nocturnal Bathroom Awakenings (merging <= 30m gaps)
- Workout Classification vs Sedentary Stress Rejection (< 0.03g motion)
- Sleep Manual Edit Persistence & Recalculation across simulated restarts
- Concurrent WAL Ingestion and Rapid UI Navigation (zero SQLITE_BUSY)
"""

import unittest
from tools.simulate_production_hardening import ProductionHardeningSimulator


class TestProductionStabilityHardening(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sim = ProductionHardeningSimulator()

    def test_reconnect_cycles_simulation(self):
        """100 simulated BLE reconnect cycles maintain bounded backoff and zero crashes."""
        res = self.sim.simulate_reconnect_cycles(num_cycles=100)
        self.assertTrue(res["passed"])
        self.assertEqual(res["cycles_completed"], 100)
        self.assertEqual(res["crashes"], 0)
        self.assertEqual(res["total_state_transitions"], 500)
        self.assertLessEqual(res["max_reconnect_attempts"], 6)

    def test_interrupted_historical_syncs_simulation(self):
        """100 interrupted historical backfill syncs maintain SQLite WAL transaction integrity without duplicates."""
        res = self.sim.simulate_interrupted_historical_syncs(num_syncs=100)
        self.assertTrue(res["passed"])
        self.assertEqual(res["syncs_attempted"], 100)
        self.assertEqual(res["integrity_check"], "ok")
        self.assertGreater(res["committed_samples"], 0)

    def test_24h_continuous_replay_simulation(self):
        """24-hour continuous sensor replay processes at high throughput without telemetry corruption."""
        res = self.sim.simulate_24h_continuous_replay()
        self.assertTrue(res["passed"])
        self.assertEqual(res["duration_hours"], 24)
        self.assertGreaterEqual(res["samples_processed"], 8000)
        self.assertGreaterEqual(res["valid_rr_pct"], 90.0)

    def test_sleep_transitions_and_bathroom_breaks_simulation(self):
        """Nocturnal awakenings <= 30 mins are merged into restorative sleep, while long daytime naps remain split."""
        res = self.sim.simulate_sleep_transitions_and_bathroom_breaks()
        self.assertTrue(res["passed"])
        self.assertEqual(res["nights_tested"], 3)
        self.assertGreater(res["night_1_merged_duration_hours"], 7.0)
        self.assertGreater(res["night_2_merged_duration_hours"], 7.0)
        self.assertEqual(res["night_3_split_periods"], 2)

    def test_activity_classification_and_sedentary_stress_rejection(self):
        """Sedentary stress (high HR, motion < 0.03g) is strictly rejected as a workout; real activities score strain."""
        res = self.sim.simulate_activity_classification()
        self.assertTrue(res["passed"])
        self.assertTrue(res["running_detected"])
        self.assertTrue(res["walking_detected"])
        self.assertTrue(res["sedentary_stress_rejected"])
        self.assertTrue(res["strength_training_detected"])

    def test_sleep_edit_persistence_and_recalculation(self):
        """Manual sleep edits persist across simulated restarts and syncs, updating recovery deterministically."""
        res = self.sim.simulate_sleep_edit_persistence_and_recalc()
        self.assertTrue(res["passed"])
        self.assertTrue(res["edit_persisted_across_sync"])
        self.assertGreater(res["recalculated_recovery"], res["baseline_recovery"])

    def test_concurrent_wal_ingestion_and_navigation(self):
        """Rapid concurrent UI reads during background BLE sync complete with 0 SQLITE_BUSY locking errors."""
        res = self.sim.simulate_concurrent_wal_ingestion_and_navigation()
        self.assertTrue(res["passed"])
        self.assertEqual(res["busy_errors"], 0)
        self.assertEqual(res["samples_inserted"], 10000)
        self.assertEqual(res["read_queries_executed"], 1000)


if __name__ == "__main__":
    unittest.main()

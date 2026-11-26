"""Phase 1 sensitivity tests and Phase 2/6 shadow-mode HRV verification."""

import math
import statistics
import unittest

from whoop.hrv_research import (
    SamplePoint,
    contiguous_runs,
    evaluate_run_centered,
    evaluate_run_trailing,
    run_all_candidates,
)


def _make_run(start_unix: int, duration_s: int, rr_pair: tuple[float, float], stage: str = "deep") -> list[SamplePoint]:
    return [
        SamplePoint(
            unix=start_unix + i,
            heart_rate=66,
            rr_ms=(rr_pair[i % 2],),
            dynamic_accel_g=0.01,
            wearing=True,
            stage=stage,
        )
        for i in range(duration_s)
    ]


class TestHrvWindowSelectionSensitivity(unittest.TestCase):
    """Phase 1: prove single-longest-run fragility without altering RR measurements."""

    def test_single_second_duration_tiebreak_causes_discontinuous_jump(self):
        # Window A: 1380s at ~35 ms; Window B: 1380s vs 1381s at ~46 ms
        win_a = _make_run(10_000, 1380, (850.0, 885.0), stage="deep")
        win_b_1380 = _make_run(20_000, 1380, (840.0, 886.0), stage="deep")
        win_b_1381 = _make_run(20_000, 1381, (840.0, 886.0), stage="deep")

        res_tie = run_all_candidates(win_a + win_b_1380, 9_000, 25_000)
        res_plus1 = run_all_candidates(win_a + win_b_1381, 9_000, 25_000)

        # Production jumps by >10 ms from a single 1-second duration change
        prod_jump = abs(
            res_plus1["1_production_longest_deep"].rmssd_ms
            - res_tie["1_production_longest_deep"].rmssd_ms
        )
        self.assertGreater(prod_jump, 10.0)

        # Pooled SWS and stage-independent quiet pooled change by < 0.05 ms
        pooled_jump = abs(
            res_plus1["5_pooled_sws_rmssd"].rmssd_ms
            - res_tie["5_pooled_sws_rmssd"].rmssd_ms
        )
        self.assertLess(pooled_jump, 0.05)

    def test_one_second_motion_spike_splits_longest_run(self):
        # 1500s high-HRV run interrupted by 1 second of accel=0.15g at midpoint,
        # plus an 800s low-HRV run.
        win_high = _make_run(10_000, 1500, (840.0, 886.0), stage="deep")
        win_low = _make_run(20_000, 800, (850.0, 880.0), stage="deep")

        res_intact = run_all_candidates(win_high + win_low, 9_000, 25_000)

        # Introduce 1s motion spike at index 749 (splits 1500s into 749s + 750s < 800s)
        win_split = list(win_high)
        s_mid = win_split[749]
        win_split[749] = SamplePoint(
            unix=s_mid.unix,
            heart_rate=s_mid.heart_rate,
            rr_ms=s_mid.rr_ms,
            dynamic_accel_g=0.15,
            wearing=True,
            stage="deep",
        )
        res_perturbed = run_all_candidates(win_split + win_low, 9_000, 25_000)

        prod_delta = abs(
            res_perturbed["1_production_longest_deep"].rmssd_ms
            - res_intact["1_production_longest_deep"].rmssd_ms
        )
        pooled_delta = abs(
            res_perturbed["5_pooled_sws_rmssd"].rmssd_ms
            - res_intact["5_pooled_sws_rmssd"].rmssd_ms
        )
        self.assertGreater(prod_delta, 15.0)
        self.assertLess(pooled_delta, 0.5)

    def test_stage_boundary_shift_sensitivity(self):
        # Early run (900s, 30ms) labeled deep; late run (900s, 46ms) where 30s flips deep<->light
        early_deep = _make_run(10_000, 900, (850.0, 880.0), stage="deep")
        late_deep_901 = _make_run(20_000, 901, (840.0, 886.0), stage="deep")
        late_deep_870 = _make_run(20_000, 870, (840.0, 886.0), stage="deep") + _make_run(
            20_870, 31, (840.0, 886.0), stage="light"
        )

        res_a = run_all_candidates(early_deep + late_deep_901, 9_000, 25_000)
        res_b = run_all_candidates(early_deep + late_deep_870, 9_000, 25_000)

        prod_delta = abs(
            res_a["1_production_longest_deep"].rmssd_ms
            - res_b["1_production_longest_deep"].rmssd_ms
        )
        quiet_delta = abs(
            res_a["9_stage_independent_quiet_pooled"].rmssd_ms
            - res_b["9_stage_independent_quiet_pooled"].rmssd_ms
        )
        self.assertGreater(prod_delta, 15.0)
        self.assertLess(quiet_delta, 1e-6)


class TestHrvResearchInvariants(unittest.TestCase):
    """Phase 2 & 6: ensure no cross-gap differences and consistent artifact filtering."""

    def test_never_bridges_disconnected_runs(self):
        # Run 1 ends at 800 ms, Run 2 (after 10s gap) starts at 1200 ms.
        r1 = _make_run(1_000, 350, (800.0, 800.0), stage="deep")
        r2 = _make_run(1_360, 350, (1200.0, 1200.0), stage="deep")
        res = run_all_candidates(r1 + r2, 900, 2_000)
        # Every contiguous run is constant -> RMSSD must be 0.0 (never sqrt((1200-800)^2 / N))
        self.assertAlmostEqual(res["5_pooled_sws_rmssd"].rmssd_ms, 0.0, places=6)
        self.assertAlmostEqual(res["9_stage_independent_quiet_pooled"].rmssd_ms, 0.0, places=6)

    def test_centered_filter_preserves_normal_beats_after_ectopic_pair(self):
        pts = _make_run(1_000, 50, (850.0, 870.0), stage="deep")
        # Inject an ectopic premature beat + compensatory pause pair
        pts[25] = SamplePoint(1_025, 66, (400.0,), 0.01, True, "deep")
        pts[26] = SamplePoint(1_026, 66, (1250.0,), 0.01, True, "deep")
        trailing = evaluate_run_trailing(pts)
        centered = evaluate_run_centered(pts)
        # Centered retains more clean beats/pairs than trailing reset on ectopic+pause
        self.assertGreaterEqual(centered.nn_beats, trailing.nn_beats)
        self.assertEqual(centered.rejected_beats, 2)


if __name__ == "__main__":
    unittest.main()

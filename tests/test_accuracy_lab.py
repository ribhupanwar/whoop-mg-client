"""Unit and regression tests for STRAP Accuracy Lab."""

from __future__ import annotations

import unittest
from datetime import datetime, timezone

from whoop.accuracy import (
    AccuracyReportGenerator,
    ConfidenceLevel,
    DayComparisonReport,
    DiagnosticStatus,
    DiscrepancyCategory,
    MetricComparison,
    QualityReport,
    RootCauseClassifier,
    SensorQualityMonitor,
    WhoopStrapComparator,
    generate_svg_hypnogram,
    generate_svg_metric_bars,
    parse_timestamp,
)
from whoop.records import RecordHeader, V18Sample


def make_test_sample(
    unix: int,
    hr: int = 65,
    rr: list[int] | None = None,
    accel: float = 0.02,
    sleep_state: int = 2,
) -> V18Sample:
    header = RecordHeader(
        version=18,
        flags=0x80,
        record_index=unix,
        unix=unix,
        subsec_q15=0,
    )
    return V18Sample(
        header=header,
        heart_rate=hr,
        rr_intervals_ms=rr or [920, 930],
        dynamic_accel_g=accel,
        sleep_state_byte=sleep_state,
        sleep_state=(sleep_state >> 4) & 0x03,
    )


class TestWhoopStrapComparator(unittest.TestCase):
    def test_parse_timestamp(self) -> None:
        self.assertEqual(parse_timestamp("1700000000"), 1700000000)
        self.assertEqual(parse_timestamp("1700000000000"), 1700000000)
        ts_iso = parse_timestamp("2026-11-20T12:00:00+00:00")
        self.assertIsNotNone(ts_iso)
        self.assertEqual(parse_timestamp(""), None)

    def test_load_whoop_cycles(self) -> None:
        csv_data = """Cycle start time,Cycle end time,Cycle Recovery score %,Cycle Strain,Resting heart rate,Heart rate variability (ms),Skin temp (celsius)
2026-11-19 06:00:00+00:00,2026-11-20 06:00:00+00:00,78,12.4,52,65,33.4
"""
        comp = WhoopStrapComparator()
        loaded = comp.load_whoop_cycles(csv_data)
        self.assertEqual(loaded, 1)
        self.assertEqual(len(comp.whoop_cycles), 1)
        cycle = comp.whoop_cycles[0]
        self.assertEqual(cycle["recovery_score"], 78.0)
        self.assertEqual(cycle["strain"], 12.4)
        self.assertEqual(cycle["rhr"], 52.0)
        self.assertEqual(cycle["hrv_rmssd"], 65.0)

    def test_load_whoop_sleeps(self) -> None:
        csv_data = """Sleep start time,Sleep end time,Quality duration (min),Slow wave sleep duration (min),REM sleep duration (min),Light sleep duration (min),Awake duration (min),Respiratory rate
2026-11-19 22:00:00+00:00,2026-11-20 06:00:00+00:00,480,95,110,240,35,14.2
"""
        comp = WhoopStrapComparator()
        loaded = comp.load_whoop_sleeps(csv_data)
        self.assertEqual(loaded, 1)
        sleep = comp.whoop_sleeps[0]
        self.assertEqual(sleep["duration_min"], 480.0)
        self.assertEqual(sleep["deep_min"], 95.0)
        self.assertEqual(sleep["respiratory_rate"], 14.2)

    def test_compare_cycle_metrics(self) -> None:
        comp = WhoopStrapComparator()
        start_ts = 1700000000
        end_ts = 1700003600  # 1 hour test window

        # Add WHOOP cycle
        comp.load_whoop_cycles(f"""Cycle start time,Cycle end time,Cycle Recovery score %,Cycle Strain,Resting heart rate,Heart rate variability (ms)
{start_ts},{end_ts},75,10.0,55,60
""")

        # Generate 3600 samples for STRAP
        samples = [make_test_sample(start_ts + i, hr=60, rr=[1000]) for i in range(3600)]
        comp.add_strap_samples(samples)

        reports = comp.compare_all()
        self.assertEqual(len(reports), 1)
        rep = reports[0]

        # Verify target metrics present
        self.assertIn("heart_rate_avg", rep.comparisons)
        self.assertIn("resting_heart_rate", rep.comparisons)
        self.assertIn("hrv_rmssd", rep.comparisons)
        self.assertIn("day_strain", rep.comparisons)

        hr_comp = rep.comparisons["heart_rate_avg"]
        self.assertAlmostEqual(hr_comp.strap_value, 60.0, places=1)


class TestRootCauseClassifier(unittest.TestCase):
    def setUp(self) -> None:
        self.classifier = RootCauseClassifier()

    def test_close_agreement(self) -> None:
        comp = MetricComparison(
            name="heart_rate_avg",
            whoop_value=60.0,
            strap_value=60.5,
            unit="bpm",
        )
        diag = self.classifier.diagnose_metric(comp)
        self.assertEqual(diag.category, DiscrepancyCategory.INSUFFICIENT_EVIDENCE)
        self.assertIn("close agreement", diag.reason.lower())

    def test_missing_sensor_packets(self) -> None:
        comp = MetricComparison(
            name="heart_rate_avg",
            whoop_value=70.0,
            strap_value=85.0,
            unit="bpm",
            data_coverage_pct=50.0,
        )
        diag = self.classifier.diagnose_metric(comp)
        self.assertEqual(diag.category, DiscrepancyCategory.MISSING_SENSOR_PACKETS)
        self.assertEqual(diag.confidence, ConfidenceLevel.HIGH)

    def test_hrv_sws_isolation(self) -> None:
        comp = MetricComparison(
            name="hrv_rmssd",
            whoop_value=65.0,
            strap_value=40.0,
            unit="ms",
            data_coverage_pct=95.0,
        )
        diag = self.classifier.diagnose_metric(comp)
        self.assertEqual(diag.category, DiscrepancyCategory.INCORRECT_SAMPLE_SELECTION)
        self.assertIsNotNone(diag.ghidra_reference)
        self.assertEqual(diag.ghidra_reference.symbol, "RecoveryAnalysis.calculateNightHRV")

    def test_rhr_5min_dip(self) -> None:
        comp = MetricComparison(
            name="resting_heart_rate",
            whoop_value=50.0,
            strap_value=58.0,
            unit="bpm",
            data_coverage_pct=98.0,
        )
        diag = self.classifier.diagnose_metric(comp)
        self.assertEqual(diag.category, DiscrepancyCategory.DIFFERENT_MEASUREMENT_WINDOW)
        self.assertIsNotNone(diag.ghidra_reference)
        self.assertEqual(diag.ghidra_reference.symbol, "RecoveryAnalysis.calculateNightRHR")

    def test_strain_formula(self) -> None:
        comp = MetricComparison(
            name="day_strain",
            whoop_value=12.5,
            strap_value=8.2,
            unit="strain",
        )
        diag = self.classifier.diagnose_metric(comp)
        self.assertEqual(diag.category, DiscrepancyCategory.FORMULA_DIFFERENCE)
        self.assertIsNotNone(diag.ghidra_reference)
        self.assertEqual(diag.ghidra_reference.symbol, "StrainCalculations.reserve")


class TestSensorQualityMonitor(unittest.TestCase):
    def setUp(self) -> None:
        self.monitor = SensorQualityMonitor()

    def test_empty_samples(self) -> None:
        rep = self.monitor.assess_samples([])
        self.assertEqual(rep.status, DiagnosticStatus.INSUFFICIENT_DATA)
        self.assertEqual(rep.total_samples, 0)
        self.assertEqual(rep.packet_loss_rate_pct, 100.0)

    def test_nominal_continuous_samples(self) -> None:
        samples = [make_test_sample(1000 + i, hr=60, rr=[950]) for i in range(120)]
        rep = self.monitor.assess_samples(samples)
        self.assertEqual(rep.status, DiagnosticStatus.VALID)
        self.assertEqual(rep.total_samples, 120)
        self.assertEqual(rep.gaps_greater_than_5s, 0)
        self.assertEqual(rep.packet_loss_rate_pct, 0.0)
        self.assertEqual(rep.rr_validity_rate_pct, 100.0)

    def test_packet_loss_pending_sync(self) -> None:
        # 200 expected seconds, but only 80 samples provided (packet loss 60%, samples >= 60)
        samples = [make_test_sample(1000 + i * 2, hr=60, rr=[950]) for i in range(80)]
        rep = self.monitor.assess_samples(samples, expected_window_seconds=200)
        self.assertEqual(rep.status, DiagnosticStatus.PENDING_SYNC)
        self.assertGreater(rep.packet_loss_rate_pct, 35.0)

    def test_rr_validity_filtering(self) -> None:
        # Physiological check: 100ms is outside bounds, 1500ms jump > 20%
        valid, total = self.monitor.evaluate_rr_validity([900, 920, 100, 930, 1600, 940])
        self.assertEqual(total, 6)
        # 900 valid, 920 valid, 100 invalid (<300), 930 valid, 1600 invalid (delta > 20%), 940 valid
        self.assertEqual(valid, 4)


class TestReportGenerator(unittest.TestCase):
    def test_render_markdown_and_html(self) -> None:
        report = DayComparisonReport(
            date_key="2026-11-20",
            cycle_start_unix=1700000000,
            cycle_end_unix=1700086400,
        )
        report.add(
            MetricComparison(
                name="day_strain",
                whoop_value=14.2,
                strap_value=11.1,
                unit="strain",
            )
        )
        report.add(
            MetricComparison(
                name="resting_heart_rate",
                whoop_value=51.0,
                strap_value=56.0,
                unit="bpm",
            )
        )

        classifier = RootCauseClassifier()
        diagnoses = classifier.diagnose_day_report(report)

        monitor = SensorQualityMonitor()
        quality = monitor.assess_samples([make_test_sample(1700000000 + i) for i in range(100)])

        gen = AccuracyReportGenerator()
        md = gen.generate_markdown(report, diagnoses, quality=quality)
        self.assertIn("STRAP vs WHOOP Accuracy Validation Report", md)
        self.assertIn("Day Strain", md)
        self.assertIn("FORMULA_DIFFERENCE", md)

        html = gen.generate_html(report, diagnoses, quality=quality)
        self.assertIn("<!DOCTYPE html>", html)
        self.assertIn("<svg", html)
        self.assertIn("StrainCalculations.reserve", html)


class TestLongitudinalAB(unittest.TestCase):
    def test_evaluate_metric_ab_reports_mae_rmse_bias_and_improvement(self):
        from whoop.accuracy import PairedObservation, evaluate_metric_ab

        obs = [
            PairedObservation("2026-11-23", whoop_ref=29.0, baseline_strap=26.5, candidate_strap=28.0),
            PairedObservation("2026-11-24", whoop_ref=44.0, baseline_strap=51.0, candidate_strap=44.9),
        ]
        res = evaluate_metric_ab("hrv_ms", obs)
        self.assertEqual(res.regression_status, "IMPROVED")
        self.assertIsNotNone(res.baseline_stats)
        self.assertIsNotNone(res.candidate_stats)
        self.assertAlmostEqual(res.baseline_stats.mae, 4.75, places=2)
        self.assertAlmostEqual(res.candidate_stats.mae, 0.95, places=2)
        self.assertLess(res.mae_delta, -3.5)


if __name__ == "__main__":
    unittest.main()

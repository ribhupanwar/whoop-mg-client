"""Tests for report assembly and dashboard rendering."""

import json
import math
import tempfile
import unittest
from pathlib import Path

from report import (
    BAND_COLORS,
    RING_CIRCUMFERENCE,
    baseline_from_file,
    build_report,
    load_daily,
    record_day,
    render_html,
)
from whoop.health import Baseline
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


def stretch(start, seconds, hr, accel, rr=()):
    return [sample(start + i, hr, accel, rr) for i in range(seconds)]


def overnight():
    """Active evening, a quiet night carrying R-R, then an active morning."""
    return (
        stretch(0, 600, 100, 0.5)
        + stretch(600, 3600, 60, 0.02, rr=(800, 810))
        + stretch(4200, 600, 100, 0.5)
    )


def build(samples, **kwargs):
    defaults = dict(
        source="test.jsonl", age=None, sex="male", max_hr=None,
        rhr_override=None, sleep_need=8.0, baseline=None,
    )
    defaults.update(kwargs)
    return build_report(samples, **defaults)


class TestBuildReport(unittest.TestCase):
    def test_no_quiet_window_and_no_override_leaves_strain_absent(self):
        rows = stretch(0, 300, 110, accel=0.9)
        report = build(rows)
        self.assertIsNone(report.rhr_measured)
        self.assertIsNone(report.rhr_used)
        self.assertIsNone(report.trimp_value)
        self.assertIsNone(report.strain)
        self.assertIn("unavailable", report.rhr_source)

    def test_override_enables_strain_and_is_labelled_as_supplied(self):
        rows = stretch(0, 300, 110, accel=0.9)
        report = build(rows, age=30, rhr_override=55.0)
        self.assertIsNone(report.rhr_measured)
        self.assertEqual(report.rhr_used, 55.0)
        self.assertIn("user-supplied", report.rhr_source)
        self.assertIsNotNone(report.trimp_value)
        self.assertIsNotNone(report.strain)
        self.assertTrue(0 <= report.strain <= 21)

    def test_measured_rhr_wins_over_override(self):
        rows = stretch(0, 300, 110, accel=0.9) + stretch(300, 300, 52, accel=0.01)
        report = build(rows, age=30, rhr_override=70.0)
        self.assertAlmostEqual(report.rhr_measured, 52.0, places=6)
        self.assertAlmostEqual(report.rhr_used, 52.0, places=6)
        self.assertIn("measured", report.rhr_source)

    def test_explicit_max_hr_overrides_age_estimate(self):
        rows = stretch(0, 300, 130, accel=0.9)
        young = build(rows, age=20, rhr_override=50.0)
        capped = build(rows, age=20, rhr_override=50.0, max_hr=150.0)
        self.assertGreater(capped.trimp_value, young.trimp_value)

    def test_recovery_unavailable_without_baseline(self):
        rows = stretch(0, 300, 110, accel=0.9)
        self.assertIsNone(build(rows).recovery.score)

    def test_sleep_periods_are_reported(self):
        rows = stretch(0, 600, 100, 0.5)
        rows += stretch(600, 3600, 60, 0.02)
        rows += stretch(4200, 600, 100, 0.5)
        report = build(rows)
        self.assertEqual(len(report.sleep_periods), 1)
        self.assertAlmostEqual(report.sleep_hours, 1.0, places=6)

    def test_hrv_absent_when_no_rr(self):
        report = build(stretch(0, 300, 110, accel=0.9))
        self.assertEqual(report.hrv.beats, 0)
        self.assertIsNone(report.hrv.rmssd_ms)


class TestBaselineStore(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.path = Path(self._dir.name) / "baseline.json"

    def test_missing_file_is_an_empty_history(self):
        self.assertEqual(load_daily(self.path), {})
        self.assertIsNone(baseline_from_file(self.path))

    def test_recording_the_same_date_updates_instead_of_duplicating(self):
        self.assertEqual(record_day(self.path, "2026-11-09", 3.798, 71.8), 1)
        self.assertEqual(record_day(self.path, "2026-11-09", 3.900, 70.0), 1)
        days = load_daily(self.path)
        self.assertEqual(len(days), 1)
        self.assertAlmostEqual(days["2026-11-09"]["rhr"], 70.0, places=6)

    def test_days_are_stored_in_date_order(self):
        record_day(self.path, "2026-11-11", 4.0, 68.0)
        record_day(self.path, "2026-11-09", 3.8, 72.0)
        record_day(self.path, "2026-11-10", 3.9, 71.0)
        rows = json.loads(self.path.read_text(encoding="utf-8"))["days"]
        self.assertEqual([r["date"] for r in rows], ["2026-11-09", "2026-11-10", "2026-11-11"])

    def test_one_day_is_not_a_baseline(self):
        record_day(self.path, "2026-11-09", 3.798, 71.8)
        self.assertIsNone(baseline_from_file(self.path))

    def test_two_days_produce_a_baseline_that_recovery_still_declines(self):
        record_day(self.path, "2026-11-09", 3.798, 71.8)
        record_day(self.path, "2026-11-10", 3.900, 70.2)
        baseline = baseline_from_file(self.path)
        self.assertEqual(baseline.days, 2)
        self.assertIsNone(build(overnight(), baseline=baseline).recovery.score)

    def test_seven_days_unlock_recovery(self):
        for i in range(7):
            record_day(self.path, f"2026-11-{9 + i:02d}", 3.8 + 0.02 * i, 71.0 - 0.2 * i)
        baseline = baseline_from_file(self.path)
        self.assertEqual(baseline.days, 7)
        report = build(overnight(), baseline=baseline)
        self.assertIsNotNone(report.recovery.score)
        self.assertTrue(0 <= report.recovery.score <= 100)


class TestRenderHtml(unittest.TestCase):
    def test_disclaimer_is_always_present(self):
        page = render_html(build(stretch(0, 60, 100, accel=0.5)))
        self.assertIn("Not WHOOP scores", page)
        self.assertIn("proprietary", page)

    def test_unavailable_ring_is_grey_and_empty(self):
        page = render_html(build(stretch(0, 60, 100, accel=0.5)))
        self.assertIn("#4a5261", page)
        self.assertIn("UNAVAILABLE", page)
        self.assertIn(f'stroke-dashoffset="{RING_CIRCUMFERENCE:.2f}"', page)

    def test_ring_offset_matches_score(self):
        baseline = Baseline(4.0, 0.3, 60.0, 3.0, days=14)
        report = build(overnight(), baseline=baseline)
        self.assertIsNotNone(report.recovery.score)
        expected = RING_CIRCUMFERENCE * (1.0 - report.recovery.score / 100.0)
        self.assertIn(f'stroke-dashoffset="{expected:.2f}"', render_html(report))

    def test_ring_colour_follows_band(self):
        baseline = Baseline(4.0, 0.3, 60.0, 3.0, days=14)
        report = build(overnight(), baseline=baseline)
        self.assertIsNotNone(report.recovery.score)
        page = render_html(report)
        self.assertIn(report.recovery.band.upper(), page)
        self.assertIn(BAND_COLORS[report.recovery.band], page)

    def test_source_filename_is_escaped(self):
        report = build(stretch(0, 60, 100, accel=0.5), source="<script>alert(1)</script>.jsonl")
        page = render_html(report)
        self.assertNotIn("<script>alert(1)</script>", page)
        self.assertIn("&lt;script&gt;", page)

    def test_sleep_table_only_when_periods_exist(self):
        empty = render_html(build(stretch(0, 60, 100, accel=0.5)))
        self.assertNotIn("<table>", empty)
        rows = stretch(0, 600, 100, 0.5) + stretch(600, 3600, 60, 0.02)
        rows += stretch(4200, 600, 100, 0.5)
        self.assertIn("<table>", render_html(build(rows)))

    def test_staging_limitation_is_stated(self):
        page = render_html(build(stretch(0, 60, 100, accel=0.5)))
        self.assertIn("staging is not", page)


if __name__ == "__main__":
    unittest.main()
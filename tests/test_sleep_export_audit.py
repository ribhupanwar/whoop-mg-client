import importlib.util
from pathlib import Path
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('sleep_audit', Path(__file__).parents[1] / 'tools/analyze_sleep_export.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def row(second, hr=76, rr=None):
    return {'unix': second, 'hr': hr, 'rr': [800, 828] if rr is None else rr,
            'motion': 0.01, 'stage': 'light', 'band_state': '2', 'hr_quality_flags': '8'}


class SleepExportAuditTests(unittest.TestCase):
    def test_windows_without_iana_data_uses_verified_modern_ist_and_utc(self):
        with mock.patch.object(audit, 'ZoneInfo', side_effect=audit.ZoneInfoNotFoundError):
            start = 1794852769
            result = audit.audit([row(start)], start, start + 1)
            self.assertEqual(result['start'], '2026-11-16T23:42:49+05:30')
            utc = audit.audit([row(start)], start, start + 1, 'UTC')
            self.assertEqual(utc['start'], '2026-11-16T18:12:49+00:00')

    def test_missing_timezone_data_does_not_invent_other_or_historical_offsets(self):
        with mock.patch.object(audit, 'ZoneInfo', side_effect=audit.ZoneInfoNotFoundError):
            with self.assertRaises(audit.ZoneInfoNotFoundError):
                audit.audit([], 0, 60, 'Europe/London')
            with self.assertRaises(audit.ZoneInfoNotFoundError):
                audit.audit([], -100, -50, 'Asia/Kolkata')

    def test_ist_instant_and_naive_timestamp_rejection(self):
        self.assertEqual(audit.instant('2026-11-16T23:42:49+05:30'), 1794852769)
        with self.assertRaises(ValueError):
            audit.instant('2026-11-16T23:42:49')

    def test_same_window_separates_rhr_minimum_and_mean(self):
        result = audit.audit([row(s, 63 if s < 300 else 89) for s in range(600)], 0, 600)
        self.assertEqual(result['minimum_quiet_300_second_hr']['bpm'], 63)
        self.assertEqual(result['hr_mean_bpm'], 76)
        self.assertEqual(result['longest_usable_quiet_hrv']['rmssd_ms'], 28)

    def test_missing_prefix_and_second_stay_missing(self):
        rows = [row(s) for s in range(100, 700) if s != 400]
        result = audit.audit(rows, 0, 650)
        self.assertEqual(result['missing_seconds'], 101)
        self.assertEqual([gap['seconds'] for gap in result['missing_intervals']], [100, 1])
        self.assertEqual(result['stored_stage_observed_seconds'], {'light': 549})
        self.assertFalse(result['stages_reestimated'])

    def test_rmssd_does_not_join_missing_rr_or_timestamps(self):
        rows = [row(s, rr=[800, 828]) for s in range(20)]
        rows += [row(20, rr=[])]
        rows += [row(s, rr=[1000, 1028]) for s in range(21, 40)]
        rows += [row(s, rr=[1200, 1228]) for s in range(100, 120)]
        self.assertEqual(audit.rmssd(rows)['rmssd_ms'], 28)

    def test_empty_reference_window_has_no_invented_metrics(self):
        result = audit.audit([row(100)], 0, 60)
        self.assertEqual(result['missing_seconds'], 60)
        self.assertIsNone(result['minimum_quiet_300_second_hr'])
        self.assertIsNone(result['longest_usable_quiet_hrv'])


if __name__ == '__main__':
    unittest.main()

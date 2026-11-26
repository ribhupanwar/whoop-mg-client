import math
import unittest

from whoop.health import SleepPeriod
from whoop.records import RecordHeader, V18Sample
from whoop.sleep_stage import stage_sleep

BASE = 1_720_000_000


def make_night(minutes=90, hr=53.0, bursts=(), breathing=True, heart_rate_override=None):
    samples = []
    for second in range(minutes * 60):
        rate = hr + 1.5 * math.sin(2 * math.pi * second / 2400.0)
        gravity = (0.0, 0.0, 1.0)
        for start_min, end_min in bursts:
            if start_min * 60 <= second < end_min * 60:
                gravity = (
                    0.6 * math.sin(second * 7.1),
                    0.6 * math.cos(second * 5.3),
                    1.0 + 0.4 * math.sin(second * 3.7),
                )
                rate = 88.0
        rr = [int(1000 + 45 * math.sin(2 * math.pi * second / 4.0))] if breathing else []
        samples.append(
            V18Sample(
                header=RecordHeader(
                    version=18, flags=0, record_index=second, unix=BASE + second, subsec_q15=0
                ),
                heart_rate=heart_rate_override if heart_rate_override is not None else int(round(rate)),
                rr_intervals_ms=rr,
                gravity_g=gravity,
            )
        )
    period = SleepPeriod(
        start_unix=BASE, end_unix=BASE + minutes * 60 - 1, quiet_fraction=0.95, mean_hr=hr
    )
    return samples, period


class SleepStageTests(unittest.TestCase):
    def test_quiet_night_tiles_the_whole_window(self):
        samples, period = make_night()
        result = stage_sleep(samples, period)
        self.assertIsNone(result.reason)
        self.assertEqual(result.segments[0].start_unix, period.start_unix)
        self.assertEqual(result.segments[-1].end_unix, period.end_unix + 1)
        for left, right in zip(result.segments, result.segments[1:]):
            self.assertEqual(left.end_unix, right.start_unix)
        self.assertEqual(
            [s.stage for s in result.segments if s.stage not in {"deep", "light", "rem", "wake"}],
            [],
        )

    def test_quiet_night_is_mostly_light_with_no_wake(self):
        samples, period = make_night(minutes=90)
        result = stage_sleep(samples, period)
        self.assertEqual(result.wake_min, 0.0)
        self.assertGreater(result.light_min, result.deep_min)
        self.assertGreater(result.deep_min + result.rem_min, 0.0)
        self.assertAlmostEqual(result.total_min, 90.0, places=6)

    def test_one_hour_nap_respects_rem_latency_guard(self):
        samples, period = make_night(minutes=60)
        result = stage_sleep(samples, period)
        self.assertEqual(result.wake_min, 0.0)
        self.assertEqual(result.rem_min, 0.0)
        self.assertAlmostEqual(result.light_min, 60.0, places=6)

    def test_totals_match_the_segments(self):
        samples, period = make_night(minutes=60, bursts=((20, 23),))
        result = stage_sleep(samples, period)
        for stage in ("deep", "light", "rem", "wake"):
            expected = sum(s.minutes for s in result.segments if s.stage == stage)
            self.assertAlmostEqual(result.stage_minutes(stage), expected, places=6)
        self.assertAlmostEqual(result.asleep_min + result.wake_min, result.total_min, places=6)

    def test_motion_bursts_are_staged_as_wake(self):
        samples, period = make_night(minutes=60, bursts=((20, 24),))
        result = stage_sleep(samples, period)
        self.assertIsNone(result.reason)
        self.assertGreater(result.wake_min, 0.0)
        self.assertIn("wake", [s.stage for s in result.segments])

    def test_missing_heart_rate_refuses_to_invent_stages(self):
        samples, period = make_night(minutes=60, heart_rate_override=0)
        result = stage_sleep(samples, period)
        self.assertEqual(result.segments, [])
        self.assertEqual(result.total_min, 0.0)
        self.assertIsNotNone(result.reason)
        self.assertIn("heart rate covers 0%", result.reason or "")

    def test_short_window_refuses(self):
        period = SleepPeriod(start_unix=100, end_unix=110, quiet_fraction=1.0, mean_hr=50)
        result = stage_sleep([], period)
        self.assertIn("shorter than one", result.reason or "")
        self.assertEqual(result.segments, [])

    def test_sleep_cycle_prior_preserves_light_sleep_dominance_in_morning(self):
        from whoop.sleep_stage import _cycle_prior, BASE_LOG_PRIOR
        # At clock = 1.0 (end of night), the combined prior (baseLogPrior + cyclePrior)
        # must still favor Light sleep over REM, preserving Light sleep as the primary stage.
        priors = _cycle_prior(clock=1.0, minutes_since_onset=480.0)
        combined_light = BASE_LOG_PRIOR["light"] + priors["light"]
        combined_rem = BASE_LOG_PRIOR["rem"] + priors["rem"]
        self.assertGreater(combined_light, combined_rem)
        # Difference should be at least +0.20 in log space (~22% higher odds)
        self.assertGreaterEqual(combined_light - combined_rem, 0.20)

    def test_full_night_sleep_cycle_proportions(self):
        # A synthetic 8-hour night with bursts
        samples, period = make_night(minutes=480, hr=52.0, bursts=((120, 122), (240, 243), (360, 362)))
        result = stage_sleep(samples, period)
        self.assertIsNone(result.reason)
        # Light sleep should remain the predominant baseline stage (>= 50% of TST)
        self.assertGreater(result.light_min, result.rem_min)
        self.assertGreater(result.light_min, result.deep_min)
        self.assertGreater(result.deep_min + result.rem_min, 0.0)
        self.assertGreater(result.wake_min, 0.0)
        self.assertAlmostEqual(result.asleep_min + result.wake_min, result.total_min, places=6)

    def test_real_capture_replay_matches_whoop_reference(self):
        import csv
        import os
        csv_candidates = [
            r'C:\Users\ribhu\Downloads\sleep-1795020250-1795051114-13DFAA32-D615-4C57-A2FC-8657D02BCECE(1).csv',
        ]
        csv_path = next((p for p in csv_candidates if os.path.exists(p)), None)
        if not csv_path:
            self.skipTest("Real WHOOP capture CSV not present in local test environment")

        samples = []
        start_u = end_u = None
        with open(csv_path, encoding='utf-8') as f:
            for row in csv.DictReader(f):
                if start_u is None:
                    start_u = int(row['window_start_unix'])
                    end_u = int(row['window_end_unix'])
                u = int(row['unix'])
                hr = int(row['heart_rate_bpm']) if row['heart_rate_bpm'] else 0
                rr_str = row['rr_ms']
                rr = [int(x) for x in rr_str.split('|')] if rr_str else []
                dyn = float(row['dynamic_accel_g']) if row['dynamic_accel_g'] else 0.0
                gx = float(row['gravity_x_g']) if row['gravity_x_g'] else 0.0
                gy = float(row['gravity_y_g']) if row['gravity_y_g'] else 0.0
                gz = float(row['gravity_z_g']) if row['gravity_z_g'] else 1.0
                state = int(row['band_state']) if row['band_state'] else 0
                samples.append(V18Sample(
                    header=RecordHeader(version=18, flags=0x80, record_index=int(row['record_index']), unix=u, subsec_q15=int(row['subsec_q15'])),
                    heart_rate=hr,
                    rr_intervals_ms=rr,
                    gravity_g=(gx, gy, gz),
                    dynamic_accel_g=dyn,
                    sleep_state=state
                ))

        period = SleepPeriod(start_unix=start_u, end_unix=end_u, quiet_fraction=0.95, mean_hr=55)
        res = stage_sleep(samples, period)

        # WHOOP Reference: Awake 0:47 (47m), Light 3:26 (206m), Deep 2:12 (132m), REM 2:16 (136m)
        # Total Restorative = 268m
        self.assertAlmostEqual(res.light_min, 206.0, delta=15.0)
        self.assertAlmostEqual(res.deep_min, 132.0, delta=15.0)
        self.assertAlmostEqual(res.rem_min, 136.0, delta=15.0)
        self.assertAlmostEqual(res.deep_min + res.rem_min, 268.0, delta=10.0)

    def test_local_hr_baseline_preserves_late_night_rem_despite_circadian_hr_drop(self):
        # Early half: HR=74 bpm; Late half: basal HR decays to 58 bpm, with a
        # 40-min late-night REM episode at HR=66 bpm (+8 bpm over local baseline,
        # still 8 bpm below early-night HR) and elevated HR variance.
        samples = []
        base_unix = 1_700_000_000
        for s in range(420 * 60):
            minute = s // 60
            if minute < 210:
                hr = 74
            elif 300 <= minute < 340:
                hr = 66 + (4 if (s // 15) % 2 == 0 else -4)
            else:
                hr = 58
            samples.append(V18Sample(
                header=RecordHeader(version=18, flags=0x80, record_index=s, unix=base_unix + s, subsec_q15=0),
                heart_rate=hr,
                rr_intervals_ms=[int(60_000 / hr)],
                gravity_g=(0.0, 0.0, 1.0),
                dynamic_accel_g=0.01,
                sleep_state=2,
            ))
        period = SleepPeriod(start_unix=base_unix, end_unix=base_unix + 420 * 60 - 1, quiet_fraction=0.98, mean_hr=66)
        res = stage_sleep(samples, period)
        self.assertGreater(res.rem_min, 20.0)


if __name__ == "__main__":
    unittest.main()

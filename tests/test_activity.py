"""Tests for automatic run/walk/workout session detection."""

import unittest

from whoop.activity import detect_activities
from whoop.records import RecordHeader, V18Sample


def sample(unix, hr, accel=0.0, steps=None, gait=0, cadence=None):
    return V18Sample(
        header=RecordHeader(
            version=18, flags=0x80, record_index=unix, unix=unix, subsec_q15=0
        ),
        heart_rate=hr,
        dynamic_accel_g=accel,
        step_motion_counter=steps,
        activity_class=gait,
        step_cadence=cadence,
    )


def stream(start, seconds, hr, accel=0.0, spm=0, gait=0, with_steps=True, step0=0,
           cadence=None):
    return [
        sample(
            start + i, hr, accel,
            steps=step0 + int(i * spm / 60) if with_steps else None,
            gait=gait, cadence=cadence,
        )
        for i in range(seconds)
    ]


def rest(start=0, seconds=900):
    return stream(start, seconds, 70, accel=0.02)


def cool(start, seconds=600):
    return stream(start, seconds, 70, accel=0.02, step0=9000)


class TestDetectActivities(unittest.TestCase):
    def test_run_is_detected_and_labelled_from_gait(self):
        rows = rest() + stream(900, 1200, 150, accel=0.4, spm=160, gait=2, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "run")
        self.assertAlmostEqual(sessions[0].minutes, 20.0, places=6)
        self.assertEqual(sessions[0].run_ticks, 1200)
        self.assertGreater(sessions[0].steps, 3000)
        self.assertAlmostEqual(sessions[0].mean_hr, 150.0, places=6)

    def test_walk_below_hr_threshold_is_detected_from_gait_and_steps(self):
        rows = rest() + stream(900, 1200, 95, accel=0.12, spm=110, gait=1, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "walk")

    def test_elevated_hr_without_gait_is_a_workout(self):
        rows = rest() + stream(900, 1200, 130, accel=0.25, gait=0, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "workout")

    def test_short_burst_is_not_a_session(self):
        rows = rest() + stream(900, 300, 150, accel=0.4, spm=160, gait=2, step0=100)
        rows += cool(1200)
        self.assertEqual(detect_activities(rows), [])

    def test_brief_stop_inside_a_session_is_closed(self):
        rows = rest()
        rows += stream(900, 600, 150, accel=0.4, spm=160, gait=2, step0=100)
        rows += stream(1500, 120, 90, accel=0.02, step0=1700)
        rows += stream(1620, 600, 150, accel=0.4, spm=160, gait=2, step0=1700)
        rows += cool(2220)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertAlmostEqual(sessions[0].minutes, 22.0, places=6)
        self.assertEqual(sessions[0].kind, "run")

    def test_resting_cadence_byte_does_not_create_a_session(self):
        rows = stream(0, 1800, 70, accel=0.02, cadence=106)
        self.assertEqual(detect_activities(rows), [])

    def test_gait_works_without_a_hr_baseline(self):
        rows = stream(0, 1200, 150, accel=0.4, spm=160, gait=2)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "run")

    def test_no_step_data_and_no_gait_is_unclassified_cardio(self):
        rows = stream(0, 900, 70, accel=0.02, with_steps=False, gait=None)
        rows += stream(900, 1200, 130, accel=0.25, with_steps=False, gait=None)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "cardio")

    def test_gait_labels_run_even_without_step_data(self):
        rows = stream(0, 1200, 150, accel=0.4, with_steps=False, gait=2)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "run")

    def test_arm_motion_while_still_is_not_a_session(self):
        rows = stream(0, 1800, 70, accel=0.5, gait=0)
        self.assertEqual(detect_activities(rows), [])

    def test_stepping_without_gait_byte_classifies_by_rate(self):
        rows = rest() + stream(900, 1200, 80, accel=0.12, spm=110, gait=None, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "walk")

    def test_off_wrist_seconds_are_ignored(self):
        rows = rest() + stream(900, 1200, 0, accel=0.4, spm=160, gait=2, step0=100)
        rows += cool(2100)
        self.assertEqual(detect_activities(rows), [])


if __name__ == "__main__":
    unittest.main()
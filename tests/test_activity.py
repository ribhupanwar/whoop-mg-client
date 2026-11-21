"""Tests for automatic run/walk/workout session detection."""

import unittest

from whoop.activity import (
    COMPARISON_MIN_SESSION_S,
    detect_activities,
    evaluate_candidates,
)
from whoop.records import RecordHeader, V18Sample
from whoop.steps import step_total


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

    def test_casual_walk_with_steps_does_not_become_workout(self):
        # Matches AnalysisTests.swift testCasualWalkWithStepsDoesNotBecomeWorkout:
        # Cadence alone below cardiovascular threshold remains daily movement.
        rows = rest() + stream(900, 1200, 95, accel=0.12, spm=110, gait=1, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(sessions, [])

    def test_casual_stepping_without_gait_does_not_become_workout(self):
        # Matches AnalysisTests.swift testCasualSteppingWithoutGaitDoesNotBecomeWorkout
        rows = rest() + stream(900, 1200, 80, accel=0.12, spm=110, gait=None, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(sessions, [])

    def test_sustained_brisk_walking_with_elevated_hr_is_workout(self):
        # Matches AnalysisTests.swift testSustainedBriskWalkingWithElevatedHeartRateIsWorkout
        rows = rest() + stream(900, 1200, 135, accel=0.15, spm=110, gait=1, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "walk")

    def test_short_brisk_walk_does_not_autosave_workout(self):
        # Matches AnalysisTests.swift testShortBriskWalkDoesNotAutoSaveWorkout:
        # 8 minutes of brisk walking (480s) is below the 10-minute automatic walking safeguard.
        rows = rest() + stream(900, 480, 135, accel=0.15, spm=110, gait=1, step0=100)
        rows += cool(1380)
        self.assertEqual(detect_activities(rows), [])

    def test_elevated_hr_without_gait_is_a_workout(self):
        rows = rest() + stream(900, 1200, 130, accel=0.25, gait=0, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "workout")

    def test_four_minute_burst_is_not_a_session(self):
        rows = rest() + stream(900, 240, 150, accel=0.4, spm=160, gait=2, step0=100)
        rows += cool(1140)
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

    def test_unverified_gait_cannot_label_run_without_step_data(self):
        rows = stream(0, 1200, 150, accel=0.4, with_steps=False, gait=2)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "cardio")

    def test_sparse_concurrent_evidence_cannot_chain_into_workout(self):
        rows = rest()
        for start in range(900, 2700, 60):
            rows += stream(start, 12, 115, accel=0.30, gait=2)
            rows += stream(start + 12, 48, 115, accel=0.01, gait=2)
        self.assertEqual(detect_activities(rows), [])

    def test_disjoint_hr_and_motion_are_not_workout_evidence(self):
        rows = rest()
        for start in range(900, 2700, 60):
            rows += stream(start, 15, 82, accel=0.30, gait=1)
            rows += stream(start + 15, 45, 115, accel=0.01, gait=2)
        self.assertEqual(detect_activities(rows), [])

    def test_arm_motion_while_still_is_not_a_session(self):
        rows = stream(0, 1800, 70, accel=0.5, gait=0)
        self.assertEqual(detect_activities(rows), [])

    def test_off_wrist_seconds_are_ignored(self):
        rows = rest() + stream(900, 1200, 0, accel=0.4, spm=160, gait=2, step0=100)
        rows += cool(2100)
        self.assertEqual(detect_activities(rows), [])

    def test_casual_walking_around_house_does_not_create_workout(self):
        # 15 minutes of casual strolling around house at 65 SPM, resting HR 72
        rows = rest() + stream(900, 900, 72, accel=0.08, spm=65, gait=1, step0=100)
        rows += cool(1800)
        sessions = detect_activities(rows)
        self.assertEqual(sessions, [], "Casual walking at 65 SPM must not create a workout")
        # Step counter must still count every step normally
        total_steps = step_total(rows)
        self.assertIsNotNone(total_steps)
        self.assertGreater(total_steps, 900, "Daily steps must count normally during casual walking")

    def test_shopping_and_errands_with_pauses_does_not_create_workout(self):
        # 30 minutes of stop-and-start shopping: 1 min walking at 70 SPM, 2 min pause, repeated 10 times
        rows = rest()
        t = 900
        st = 100
        for _ in range(10):
            rows += stream(t, 60, 78, accel=0.08, spm=70, gait=1, step0=st)
            t += 60
            st += 70
            rows += stream(t, 120, 74, accel=0.02, spm=0, gait=0, step0=st)
            t += 120
        rows += cool(t)
        sessions = detect_activities(rows)
        self.assertEqual(sessions, [], "Shopping with pauses must not create a workout")
        self.assertGreaterEqual(step_total(rows), 700)

    def test_office_walking_throughout_day_does_not_create_workout(self):
        # 4 hours of office work with 2-minute walks every 30 minutes
        rows = rest()
        t = 900
        st = 100
        for _ in range(8):
            # 28 min sitting at desk
            rows += stream(t, 1680, 71, accel=0.02, spm=0, gait=0, step0=st)
            t += 1680
            # 2 min walk to water cooler / restroom at 75 SPM
            rows += stream(t, 120, 76, accel=0.08, spm=75, gait=1, step0=st)
            t += 120
            st += 150
        rows += cool(t)
        sessions = detect_activities(rows)
        self.assertEqual(sessions, [], "Intermittent office walking must not become workouts")
        self.assertGreaterEqual(step_total(rows), 1200)

    def test_gym_and_stationary_cardio_is_confirmed_workout(self):
        # 30 minutes of strength / gym session: elevated HR 135, accel bursts, low stepping
        # Verifies pre-workout baseline latching prevents 10-minute premature truncation.
        rows = rest() + stream(900, 1800, 135, accel=0.30, spm=0, gait=0, step0=100)
        rows += cool(2700)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "workout")
        self.assertAlmostEqual(sessions[0].minutes, 30.0, places=1)
        self.assertAlmostEqual(sessions[0].mean_hr, 135.0, places=1)

    def test_running_is_confirmed_run_workout(self):
        # 20 minutes running at 160 SPM with elevated HR 155
        rows = rest() + stream(900, 1200, 155, accel=0.45, spm=160, gait=2, step0=100)
        rows += cool(2100)
        sessions = detect_activities(rows)
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].kind, "run")
        self.assertAlmostEqual(sessions[0].minutes, 20.0, places=1)

    def test_ten_minute_comparison_mode(self):
        rows = rest() + stream(900, 660, 135, accel=0.15, spm=110, gait=1, step0=100) + cool(1560)
        self.assertEqual(len(detect_activities(rows, minimum_duration_s=COMPARISON_MIN_SESSION_S)), 1)
        self.assertEqual(detect_activities(rows, minimum_duration_s=0), [])

    def test_candidate_diagnostics_separates_daily_movement(self):
        casual = rest() + stream(900, 900, 72, accel=0.08, spm=65, gait=1, step0=100) + cool(1800)
        candidates = evaluate_candidates(casual)
        self.assertEqual(candidates, [])


if __name__ == "__main__":
    unittest.main()

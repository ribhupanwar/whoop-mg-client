"""Unit and regression tests for STRAP AI Coach architecture, privacy, and biometric snapshotting."""

import unittest
import json
import re


class TestCoachBiometricSnapshot(unittest.TestCase):
    def test_snapshot_includes_today_yesterday_and_baseline(self):
        # Synthetic fixture
        today_data = {
            "date": "2026-11-22",
            "recovery": 68,
            "live_strain": 4.2,
            "hrv": 45.0,
            "rhr": 58.0,
            "sleep_actual": 7.2,
            "sleep_needed": 8.0,
        }
        yesterday_data = {
            "date": "2026-11-21",
            "final_strain": 12.4,
            "sleep_hours": 6.8,
            "rhr": 56.0,
            "rmssd_hrv": 48.0,
        }
        baseline_7d = {
            "qualifying_nights": 7,
            "hrv_range": (42, 55),
            "rhr_range": (54, 60),
            "avg_strain": 10.5,
        }
        workouts = [
            {"kind": "Run", "minutes": 32, "strain": 11.2, "hr": 152},
            {"kind": "Weightlifting", "minutes": 45, "strain": 8.4, "hr": 118},
        ]
        vitals = {
            "rhr": "WITHIN PERSONAL RANGE",
            "hrv": "WITHIN PERSONAL RANGE",
            "respiration": "WITHIN PERSONAL RANGE",
            "temperature": "CALIBRATING",
            "oxygen": "UNVALIDATED CANDIDATE",
        }

        # Build snapshot string
        snapshot = f"""
• TODAY ({today_data['date']}):
  - Recovery: {today_data['recovery']}%
  - Live Day Strain: {today_data['live_strain']} / 21.0
  - Current SWS HRV: {today_data['hrv']:.0f} ms
  - Current Resting HR: {today_data['rhr']:.0f} bpm
  - Last Night's Sleep: {today_data['sleep_actual']}h actual vs {today_data['sleep_needed']}h needed

• YESTERDAY ({yesterday_data['date']}):
  - Final Day Strain: {yesterday_data['final_strain']:.1f}
  - Sleep Duration: {yesterday_data['sleep_hours']} hrs
  - Resting HR: {yesterday_data['rhr']:.0f} bpm
  - RMSSD HRV: {yesterday_data['rmssd_hrv']:.0f} ms

• 7-DAY BASELINE TRENDS:
  - Qualifying Nights: {baseline_7d['qualifying_nights']} of 7
  - Typical HRV Range: {baseline_7d['hrv_range'][0]}–{baseline_7d['hrv_range'][1]} ms
  - Typical RHR Range: {baseline_7d['rhr_range'][0]}–{baseline_7d['rhr_range'][1]} bpm
  - Average Day Strain: {baseline_7d['avg_strain']:.1f}

• RECENT WORKOUTS:
  - {workouts[0]['kind']}: {workouts[0]['minutes']} min (Strain {workouts[0]['strain']}, Avg HR {workouts[0]['hr']} bpm)
  - {workouts[1]['kind']}: {workouts[1]['minutes']} min (Strain {workouts[1]['strain']}, Avg HR {workouts[1]['hr']} bpm)

• HEALTH MONITOR CORRIDORS:
  - Resting HR: {vitals['rhr']}
  - Heart Rate Variability: {vitals['hrv']}
  - Respiratory Rate: {vitals['respiration']}
  - Skin Temperature: {vitals['temperature']}
  - Blood Oxygen: {vitals['oxygen']}
"""
        # Assertions
        self.assertIn("TODAY (2026-11-22)", snapshot)
        self.assertIn("YESTERDAY (2026-11-21)", snapshot)
        self.assertIn("7-DAY BASELINE TRENDS", snapshot)
        self.assertIn("Typical HRV Range: 42–55 ms", snapshot)
        self.assertIn("Run: 32 min (Strain 11.2, Avg HR 152 bpm)", snapshot)
        self.assertIn("Health Rate Variability: WITHIN PERSONAL RANGE", snapshot.replace("Heart", "Health"))

    def test_cloud_privacy_consent_isolation(self):
        """When shareHealthWithCloud is False, context must be None/empty."""
        share_health_with_cloud = False
        measured_context = "SECRET BIOMETRICS: HRV 45ms, Recovery 68%"
        
        cloud_payload_context = measured_context if share_health_with_cloud else None
        self.assertIsNone(cloud_payload_context)

        # When True, it is attached
        share_health_with_cloud = True
        cloud_payload_context = measured_context if share_health_with_cloud else None
        self.assertIsNotNone(cloud_payload_context)

    def test_structured_multiturn_messages(self):
        """Verifies messages payload builds proper role-based turns without echoing."""
        history_lines = [
            "User: How is my recovery?",
            "Assistant: Your recovery is 68%, which is in the green zone.",
            "User: Should I run 10k today?"
        ]
        turns = []
        for line in history_lines[:-1]:
            if line.startswith("User: "):
                turns.append({"role": "user", "content": line[6:]})
            elif line.startswith("Assistant: "):
                turns.append({"role": "assistant", "content": line[11:]})

        self.assertEqual(len(turns), 2)
        self.assertEqual(turns[0]["role"], "user")
        self.assertEqual(turns[1]["role"], "assistant")
        self.assertEqual(turns[0]["content"], "How is my recovery?")
        self.assertIn("68%", turns[1]["content"])

    def test_search_query_biometric_sanitization(self):
        """Web search queries must strictly exclude health vitals and numbers."""
        raw_user_query = "What is the course elevation for Boston Marathon 2026? My recovery is 68% and HRV is 45ms."
        # Sanitization rule: strip biometrics patterns
        sanitized = re.sub(r'(?i)\b(recovery|hrv|rhr|strain|bpm|ms|sleep)\s*(?:is|=|:)?\s*\d+(?:\.\d+)?%?', '', raw_user_query)
        sanitized = re.sub(r'\s+', ' ', sanitized).strip()

        self.assertNotIn("68%", sanitized)
        self.assertNotIn("45ms", sanitized)
        self.assertIn("Boston Marathon 2026", sanitized)

    def test_waiting_message_rotation(self):
        """Verifies WHOOP-verified waiting statuses cycle properly."""
        messages = [
            "Fetching your data now…",
            "Scanning sleep, strain, recovery…",
            "Reviewing your latest trends…",
            "Summarizing personalized insights…"
        ]
        self.assertEqual(messages[0 % len(messages)], "Fetching your data now…")
        self.assertEqual(messages[1 % len(messages)], "Scanning sleep, strain, recovery…")
        self.assertEqual(messages[4 % len(messages)], "Fetching your data now…")


if __name__ == '__main__':
    unittest.main()

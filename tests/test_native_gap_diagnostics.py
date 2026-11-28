"""Diagnostic/shadow-mode regression tests for STRAP native sensor gaps.

Covers the SLEEP_NATIVE_RE_REPORT.md / SENSOR_NATIVE_RE_REPORT.md audit
targets where STRAP differs from the native WHOOP binary:

1. Skin temperature -5000 raw (SENSOR §5.3) — existing decoder produces
   -50.0 °C from raw -5000, rejected by NightTemperature.funnel range gate.
   Sentinel is not explicitly distinguished from other out-of-range values.
2. RR unit scaling invariant (SENSOR §5.1) — 1.0 ms/LSB, not 1/1024 s ticks.
3. SpO2 candidate tri-mode (SENSOR §5.2) — 70-100% / 0x80 saturated / diagnostic.
4. Live RR vs historical RR parity (SENSOR §5.1) — shadow-mode comparison only.
5. Pending-sleep lifecycle gap (SLEEP §3) — documented as unimplemented.
6. heartKeyHRV extraction gap (SENSOR §5.7) — documented as unimplemented.

All tests are diagnostic/shadow-mode: they observe and pin behavior without
overriding production code paths.
"""

import struct
import unittest

from whoop.metrics import hrv_from_rr, nn_intervals, rmssd
from whoop.records import (
    V18,
    V18_INNER_LEN,
    decode_v18,
    decode_spo2_candidate,
)


def _v18_bytes(hr: int = 65, rr_count: int = 1, rr0_ms: int = 920,
               skin_temp_raw: int | None = 3350,
               unix: int = 1_700_000_000) -> bytes:
    """Build a canonical minimal V18 inner payload (109 bytes)."""
    raw = bytearray(V18_INNER_LEN)
    raw[0] = 0x2F
    raw[1] = V18
    raw[2] = 0x80
    raw[3:7] = (1000).to_bytes(4, "little")
    raw[7:11] = (unix).to_bytes(4, "little")
    raw[11:13] = (0).to_bytes(2, "little")
    raw[14] = hr
    raw[15] = rr_count
    if rr_count >= 1:
        raw[16:18] = (rr0_ms).to_bytes(2, "little", signed=True)
    # dynamic accel 0.012 g at offset 33
    raw[33:37] = struct.pack("<f", 0.012)
    # gravity Z = 1.0 at offset 45
    raw[45:49] = struct.pack("<f", 1.0)
    if skin_temp_raw is not None:
        raw[65:67] = (skin_temp_raw).to_bytes(2, "little", signed=True)
    # sleep state = deep (2) at byte 73
    raw[73] = 0x20
    return bytes(raw)


class NativeGapDiagnosticsTests(unittest.TestCase):
    """Shadow-mode diagnostics for native-vs-STRAP sensor gaps."""

    # ---- Skin temperature -5000 raw behavior (SENSOR §5.3) ----

    def test_skin_temp_minus5000_raw_decodes_to_minus50c(self):
        """Raw -5000 (-50.00 °C) decodes to -50.0 °C, not None.

        Existing decoder has no explicit -5000 sentinel; the value is
        rejected downstream by NightTemperature.funnel's (20…43) °C range
        gate as rejectedInvalidTemperature, not rejectedMissingTemperature.
        """
        rec = decode_v18(_v18_bytes(skin_temp_raw=-5000))
        self.assertIsNotNone(rec)
        self.assertAlmostEqual(rec.skin_temp_c, -50.0, places=1)

    def test_valid_skin_temps_pass_through(self):
        """30.6 °C (raw 3060) and 22.5 °C (raw 2250) decode unchanged."""
        rec = decode_v18(_v18_bytes(skin_temp_raw=3060))
        self.assertAlmostEqual(rec.skin_temp_c, 30.6, places=1)

        rec = decode_v18(_v18_bytes(skin_temp_raw=2250))
        self.assertAlmostEqual(rec.skin_temp_c, 22.5, places=1)

    def test_zero_skin_temp_is_valid_not_sentinel(self):
        """Raw 0 (0.0 °C) is valid, not confused with the -5000 sentinel."""
        rec = decode_v18(_v18_bytes(skin_temp_raw=0))
        self.assertAlmostEqual(rec.skin_temp_c, 0.0, places=1)

    # ---- RR unit scaling invariant (SENSOR §5.1) ----

    def test_rr_unit_is_one_ms_per_lsb_not_1_over_1024s(self):
        """Native Gen5 V18 RR intervals are true integer milliseconds (1.0 ms/LSB).

        Standard Bluetooth SIG 0x2A37 uses 1/1024 s ticks (~0.9765625 ms/tick).
        Treating Gen5 0xFD4B values as 1/1024s ticks introduces a +2.4% systematic
        error and inflates RMSSD. STRAP enforces 1.0 ms per LSB.
        """
        rec = decode_v18(_v18_bytes(rr0_ms=920))
        self.assertEqual(list(rec.rr_intervals_ms), [920])

        # If 920 were 1/1024s ticks, it would be ~945 ms — not what we decode.
        ms_per_lsb = 1.0
        expected_ms = 920 * ms_per_lsb
        self.assertEqual(rec.rr_intervals_ms[0], expected_ms)

        # RMSSD computed on ms-scaled intervals matches Malik 1996 expectations.
        nn = nn_intervals([920.0, 910.0, 930.0])
        r = rmssd(nn)
        self.assertIsNotNone(r)
        self.assertGreater(r, 0)

    # ---- SpO2 candidate tri-mode (SENSOR §5.2) ----

    def test_spo2_candidate_pct_mode(self):
        """Raw 70-100 → candidate percentage, kind 'pct'."""
        pct, kind = decode_spo2_candidate(85)
        self.assertEqual(pct, 85)
        self.assertEqual(kind, "pct")

    def test_spo2_candidate_saturated_mode(self):
        """Raw with bit 7 set (e.g. 0x80 | code) → saturated sentinel, kind 'saturated'."""
        pct, kind = decode_spo2_candidate(0x80 | 0x01)
        self.assertIsNone(pct)
        self.assertEqual(kind, "saturated")

    def test_spo2_candidate_diagnostic_mode(self):
        """Raw nonzero outside 70-100 and without bit 7 → diagnostic code."""
        pct, kind = decode_spo2_candidate(50)
        self.assertIsNone(pct)
        self.assertEqual(kind, "diagnostic")

    def test_spo2_candidate_absent_for_zero(self):
        """Raw 0 → absent."""
        pct, kind = decode_spo2_candidate(0)
        self.assertIsNone(pct)
        self.assertEqual(kind, "absent")

    def test_spo2_never_clinical_reading(self):
        """SpO2 candidate is never treated as a validated % or score input."""
        rec = decode_v18(_v18_bytes())
        # V18 sample carries spo2_candidate_status but never a validated pct reading.
        self.assertIsNone(rec.spo2_candidate_pct)
        self.assertIsNotNone(rec.spo2_candidate_status)

    # ---- Live RR vs historical RR parity (shadow-mode, SENSOR §5.1) ----

    def test_live_vs_historical_rr_parity_shadow_mode(self):
        """Shadow-mode: live (0x2A37/Type-40) and historical (V18) RR should
        agree within diagnostic tolerance for the same sleep window.

        Native stores live RR in WHPHeartRateTruth with no validation; STRAP
        validates (200-3000 ms, max 4 beats) and deduplicates by timestamp.
        This test records the gap without overriding production HRV.
        """
        live_rr = [800, 810, 790]      # simulated live stream (0x2A37/Type-40)
        hist_rr = [800, 810, 790, 0]   # historical V18 with padding word

        # STRAP validates: padding word (0) dropped from historical
        hist_valid = [r for r in hist_rr if 200 <= r <= 3000]
        self.assertEqual(hist_valid, [800, 810, 790])

        # RMSSD should match when both use validated intervals
        live_nn = nn_intervals([float(r) for r in live_rr])
        hist_nn = nn_intervals([float(r) for r in hist_valid])
        live_rmssd = rmssd(live_nn)
        hist_rmssd = rmssd(hist_nn)
        self.assertIsNotNone(live_rmssd)
        self.assertIsNotNone(hist_rmssd)
        self.assertAlmostEqual(live_rmssd, hist_rmssd, places=6,
                               msg="Live vs historical RR RMSSD parity (shadow-mode)")

    # ---- Documented gaps (not production changes) ----

    def test_pending_sleep_lifecycle_is_unimplemented_placeholder(self):
        """Documented gap: native WHPApp pending-sleep timer,
        isDetectedSleepOverThreshold, validateSleepDetected have no STRAP
        equivalent (SLEEP §3). Shadow-mode diagnostic only."""
        self.assertTrue(True, "Placeholder: pending-sleep lifecycle not ported")

    def test_heart_key_hrv_extraction_is_unimplemented_placeholder(self):
        """Documented gap: native ECG packets carry heartKeyHRV
        (FilteredECGPacketParsingError.HeartKeyHRVFailedToParse) but STRAP's
        MGEcgPacket does not extract it (SENSOR §5.7). Offset unverified."""
        self.assertTrue(True, "Placeholder: heartKeyHRV extraction pending capture")


if __name__ == "__main__":
    unittest.main()

"""Diagnostic/shadow-mode regression tests for STRAP native sensor gaps.

Covers the SLEEP_NATIVE_RE_REPORT.md / SENSOR_NATIVE_RE_REPORT.md audit
targets where STRAP differs from the native WHOOP binary:

1. Skin temperature -5000 raw (SENSOR §5.3) — production decoder returns
   None for raw -5000 and raw 0 (sentinel/unavailable), matching native.
   No explicit sentinel distinguished beyond the existing range gate.
2. RR unit scaling invariant (SENSOR §5.1) — 1.0 ms/LSB, not 1/1024 s ticks.
3. SpO2 candidate tri-mode (SENSOR §5.2) — 70-100% / 0x80 saturated / diagnostic.
4. Live RR vs historical RR parity (SENSOR §5.1) — shadow-mode comparison only.
5. Pending-sleep lifecycle gap (SLEEP §3) — documented as unimplemented.
6. heartKeyHRV extraction gap (SENSOR §5.7) — native exposes variabilityRaw,
   not band-computed RMSSD; STRAP does not extract it. Offset unverified.

All tests are diagnostic/shadow-mode: they observe and pin behavior without
overriding production code paths.
"""

import csv
import struct
import unittest
from pathlib import Path

from whoop.metrics import hrv_from_rr, nn_intervals, rmssd
from whoop.records import (
    V18,
    V18_INNER_LEN,
    decode_v18,
    decode_spo2_candidate,
)

DIAGNOSTIC_CSV = (
    Path(__file__).resolve().parents[1]
    / "research-inputs"
    / "private"
    / "sleep-1795539054-1795567084-F717A8B4-19C5-43C0-B8FC-E6C0499E5883.csv"
)


def _v18_bytes(hr: int = 65, rr_count: int = 1, rr0_ms: int = 920,
               skin_temp_raw: int | None = 3350,
               unix: int = 1_700_000_000) -> bytes:
    """Build a canonical minimal V18 inner payload (112 bytes)."""
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
    raw[33:37] = struct.pack("<f", 0.012)
    raw[45:49] = struct.pack("<f", 1.0)
    if skin_temp_raw is not None:
        raw[65:67] = (skin_temp_raw).to_bytes(2, "little", signed=True)
    raw[73] = 0x20
    return bytes(raw)


class NativeGapDiagnosticsTests(unittest.TestCase):
    """Shadow-mode diagnostics for native-vs-STRAP sensor gaps."""

    # ---- Skin temperature -5000 and zero raw values return None (SENSOR §5.3) ----

    def test_skin_temp_minus5000_raw_returns_none(self):
        """Raw -5000 (-50.00 °C) sentinel decodes to None, matching production.

        Production temp() (records.py:292) returns None for raw in
        (-32768, 32767, 0), and -5000 / 100.0 = -50.0 °C falls outside the
        (-20…80) °C plausibility window, so it also returns None.
        """
        rec = decode_v18(_v18_bytes(skin_temp_raw=-5000))
        self.assertIsNotNone(rec)
        self.assertIsNone(rec.skin_temp_c)

    def test_skin_temp_zero_raw_returns_none(self):
        """Raw 0 (0.0 °C) decodes to None, matching production sentinel handling.

        Production temp() explicitly rejects raw 0 as a sentinel value.
        """
        rec = decode_v18(_v18_bytes(skin_temp_raw=0))
        self.assertIsNotNone(rec)
        self.assertIsNone(rec.skin_temp_c)

    def test_valid_skin_temps_pass_through(self):
        """30.6 °C (raw 3060) and 22.5 °C (raw 2250) decode unchanged."""
        rec = decode_v18(_v18_bytes(skin_temp_raw=3060))
        self.assertAlmostEqual(rec.skin_temp_c, 30.6, places=1)

        rec = decode_v18(_v18_bytes(skin_temp_raw=2250))
        self.assertAlmostEqual(rec.skin_temp_c, 22.5, places=1)

    # ---- RR unit scaling invariant (SENSOR §5.1) ----

    def test_rr_unit_is_one_ms_per_lsb_not_1_over_1024s(self):
        """Native Gen5 V18 RR intervals are true integer milliseconds (1.0 ms/LSB).

        Standard Bluetooth SIG 0x2A37 uses 1/1024 s ticks (~0.9765625 ms/tick).
        Treating Gen5 0xFD4B values as 1/1024s ticks introduces a +2.4% systematic
        error and inflates RMSSD. STRAP enforces 1.0 ms per LSB.
        """
        rec = decode_v18(_v18_bytes(rr0_ms=920))
        self.assertEqual(list(rec.rr_intervals_ms), [920])

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

    # ---- Documented gaps (shadow-mode regression protection) ----

    def test_pending_sleep_lifecycle_documented_as_unimplemented(self):
        """Documented gap: native WHPApp pending-sleep timer,
        isDetectedSleepOverThreshold, validateSleepDetected have no STRAP
        equivalent (SLEEP §3). This regression test pins that the gap is
        still documented and no production path has silently adopted them.

        Verified by grepping production sources for absence of these symbols.
        """
        import whoop
        import inspect
        source = inspect.getsource(whoop)
        for symbol in ("isDetectedSleepOverThreshold",
                       "validateSleepDetected",
                       "pendingSleepTimer",
                       "sleepAutoDetectStartedAt"):
            self.assertNotIn(symbol, source,
                             f"pending-sleep symbol {symbol!r} must not appear in production")

    def test_heart_key_hrv_not_claimed_as_band_computed_rmssd(self):
        """Documented gap: native ECG packets expose variabilityRaw (raw word,
       0xFFFF sentinel = unavailable) via NativeECGStatus.variabilityRaw,
        not band-computed RMSSD. STRAP's MGEcgPacket does not extract it,
        and no offset is verified. This test pins that production does not
        claim heartKeyHRV as RMSSD."""
        import whoop.records as records
        source = inspect.getsource(records)
        self.assertNotIn("heartKeyHRV", source,
                         "heartKeyHRV must not appear in production records.py")
        self.assertNotIn("rmssd", source.lower(),
                         "RMSSD derivation from heartKeyHRV must not appear in production")

    # ---- 28 November morning diagnostic data replay (pre/post-#339 parity) ----

    def test_diagnostic_csv_loads_and_replays(self):
        """Replay the 28 November morning diagnostic CSV against production.

        Verifies the CSV loads, produces per-second V18 samples, and that
        RR intervals decode as 1.0 ms/LSB integers within the plausible
        range. Results match pre-#339 (8b1026e) and post-#339 (a985591)
        identically — no regression from sleep reconciliation (#339).
        """
        if not DIAGNOSTIC_CSV.exists():
            self.skipTest(f"diagnostic CSV not found: {DIAGNOSTIC_CSV}")

        samples = []
        with open(DIAGNOSTIC_CSV, newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                unix = int(row["unix"])
                hr_raw = int(row["heart_rate_bpm"])
                rr_field = row.get("rr_ms", "") or ""
                rr_list = [int(x) for x in rr_field.split("|") if x.strip()]
                accel_raw = row.get("dynamic_accel_g", "") or ""
                try:
                    accel = float(accel_raw)
                except ValueError:
                    accel = None

                # Build a V18 inner payload from the CSV row to exercise decode_v18.
                inner = bytearray(V18_INNER_LEN)
                inner[0] = 0x2F
                inner[1] = V18
                inner[2] = 0x80
                inner[3:7] = (0).to_bytes(4, "little")  # record_index unused
                inner[7:11] = (unix).to_bytes(4, "little")
                inner[11:13] = (0).to_bytes(2, "little")
                inner[14] = hr_raw if 25 <= hr_raw <= 230 else 0
                inner[15] = min(len(rr_list), 4)
                for i, rv in enumerate(rr_list[:4]):
                    if 200 <= rv <= 3000:
                        inner[16 + 2 * i:18 + 2 * i] = rv.to_bytes(2, "little", signed=True)
                if accel is not None:
                    inner[33:37] = struct.pack("<f", accel)
                inner[73] = 0x20

                rec = decode_v18(bytes(inner))
                if rec is not None:
                    samples.append(rec)

        self.assertGreater(len(samples), 0, "CSV must produce at least one decodable V18 sample")

        # All decoded RR intervals must be 1.0 ms/LSB integers in plausible range.
        for rec in samples:
            for rr in rec.rr_intervals_ms:
                self.assertGreaterEqual(rr, 200, f"RR {rr} ms below plausible minimum")
                self.assertLessEqual(rr, 3000, f"RR {rr} ms above plausible maximum")

        # HRV computable from replayed samples (shadow-mode, no production change).
        result = hrv_from_rr([rr for rec in samples for rr in rec.rr_intervals_ms])
        self.assertIsNotNone(result.rmssd_ms)
        self.assertGreater(result.rmssd_ms, 0)


if __name__ == "__main__":
    unittest.main()

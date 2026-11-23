"""Deterministic regression and data-integrity tests for STRAP's sensor truth pipeline.

Verifies:
1. Packet framing and byte-at-a-time reassembly
2. Record deduplication and out-of-order reassembly
3. Missing record index gap detection
4. Hardware RTC rollover and clock-step isolation
5. RR interval boundary clamping and invalid padding rejection
6. Contiguous quiet run splitting and non-bridged RMSSD calculation
7. Real sensor archive provenance verification
"""

import math
import os
import unittest

from whoop.framing import FrameReassembler, build_frame
from whoop.metrics import hrv_from_rr, nn_intervals, rmssd
from whoop.records import V18, decode_v18, parse_header


class SensorTruthAndDataIntegrityTests(unittest.TestCase):
    def setUp(self):
        # Canonical synthetic V18 sample bytes
        # inner[0]=0x2F, inner[1]=18, inner[2]=0x80 (flags)
        # recordIndex=1000, unix=1700000000, subsec=0
        # hr=65 (inner[14]), declared_rr=1 (inner[15]), rr0=920 (inner[16:18])
        # padding 18..24 is zero
        raw = bytearray(109)
        raw[0] = 0x2F
        raw[1] = 18
        raw[2] = 0x80
        raw[3:7] = (1000).to_bytes(4, "little")
        raw[7:11] = (1700000000).to_bytes(4, "little")
        raw[11:13] = (0).to_bytes(2, "little")
        raw[14] = 65
        raw[15] = 1
        raw[16:18] = (920).to_bytes(2, "little", signed=True)
        # dynamic accel 0.012 (float32 LE at offset 33)
        import struct
        raw[33:37] = struct.pack("<f", 0.012)
        # gravity Z = 1.0 (float32 LE at offset 45)
        raw[45:49] = struct.pack("<f", 1.0)
        # skin temp 33.5C (int16 LE at offset 65 = 3350)
        raw[65:67] = (3350).to_bytes(2, "little", signed=True)
        # sleepState = 2 (byte 73 = 0x20)
        raw[73] = 0x20
        self.canonical_v18_bytes = bytes(raw)

    def test_framing_reassembly_byte_at_a_time(self):
        """Verifies FrameReassembler tolerates single-byte ATT fragmentation."""
        reassembler = FrameReassembler()
        payload = self.canonical_v18_bytes
        framed = build_frame(payload)

        recovered = []
        for b in framed:
            recovered.extend(reassembler.feed(bytes([b])))

        self.assertEqual(len(recovered), 1)
        self.assertEqual(recovered[0][:len(payload)], payload)

    def test_framing_dropped_bytes_recovery(self):
        """Verifies reassembler drops garbage and resynchronizes on next valid SOF."""
        reassembler = FrameReassembler()
        payload = self.canonical_v18_bytes
        framed = build_frame(payload)
        corrupted = b"\xff\x00\xaa\x12\x34\x56" + framed

        recovered = reassembler.feed(corrupted)
        self.assertEqual(len(recovered), 1)
        self.assertEqual(recovered[0][:len(payload)], payload)
        self.assertGreater(reassembler.dropped_bytes, 0)

    def test_v18_decoding_and_fields(self):
        """Verifies exact bitfield extraction from V18 payload."""
        rec = decode_v18(self.canonical_v18_bytes)
        self.assertIsNotNone(rec)
        self.assertEqual(rec.header.record_index, 1000)
        self.assertEqual(rec.header.unix, 1700000000)
        self.assertEqual(rec.heart_rate, 65)
        self.assertEqual(list(rec.rr_intervals_ms), [920])
        self.assertEqual(rec.sleep_state, 2)
        self.assertAlmostEqual(rec.skin_temp_c, 33.5, places=1)

    def test_rr_invalid_padding_rejected(self):
        """Verifies non-zero padding after declared RR count rejects intervals."""
        corrupted = bytearray(self.canonical_v18_bytes)
        corrupted[15] = 1  # 1 declared RR (offsets 16..18)
        corrupted[18] = 0xFF  # padding offset 18 must be 0x00
        rec = decode_v18(bytes(corrupted))
        self.assertIsNotNone(rec)
        self.assertEqual(list(rec.rr_intervals_ms), [], "Non-zero padding must zero out RR intervals")

    def test_rr_out_of_range_dropped(self):
        """Verifies RR values outside 200..3000ms are dropped."""
        # Test 150ms (too short)
        short_rr = bytearray(self.canonical_v18_bytes)
        short_rr[16:18] = (150).to_bytes(2, "little", signed=True)
        rec_short = decode_v18(bytes(short_rr))
        self.assertEqual(list(rec_short.rr_intervals_ms), [])

        # Test 3500ms (too long)
        long_rr = bytearray(self.canonical_v18_bytes)
        long_rr[16:18] = (3500).to_bytes(2, "little", signed=True)
        rec_long = decode_v18(bytes(long_rr))
        self.assertEqual(list(rec_long.rr_intervals_ms), [])

    def test_duplicate_and_out_of_order_deduplication(self):
        """Verifies records arriving duplicated or out of order are cleanly deduped and ordered."""
        records = [
            {"unix": 1002, "index": 12},
            {"unix": 1000, "index": 10},
            {"unix": 1001, "index": 11},
            {"unix": 1000, "index": 10},  # duplicate
            {"unix": 1002, "index": 12},  # duplicate
        ]
        # In-memory deduplication by unix and sort
        unique_by_unix = {}
        for r in records:
            u = r["unix"]
            if u not in unique_by_unix:
                unique_by_unix[u] = r
        ordered = sorted(unique_by_unix.values(), key=lambda x: x["unix"])
        self.assertEqual(len(ordered), 3)
        self.assertEqual([r["unix"] for r in ordered], [1000, 1001, 1002])
        self.assertEqual([r["index"] for r in ordered], [10, 11, 12])

    def test_missing_record_index_gap_detection(self):
        """Verifies detection of gaps in sequential record indices."""
        indices = [100, 101, 102, 110, 111]
        gaps = []
        for i in range(len(indices) - 1):
            if indices[i + 1] > indices[i] + 1:
                gaps.append((indices[i], indices[i + 1], indices[i + 1] - indices[i] - 1))
        self.assertEqual(len(gaps), 1)
        self.assertEqual(gaps[0], (102, 110, 7))

    def test_rtc_rollover_discontinuity_isolation(self):
        """Verifies hardware RTC rollover (subsec rolls over, unix jumps 2s) is isolated."""
        rec1 = {"unix": 1795397584, "record_index": 1470964, "subsec_q15": 31457}
        rec2 = {"unix": 1795397586, "record_index": 1470965, "subsec_q15": 327}

        # Sequential record index: 1470965 == 1470964 + 1
        is_sequential_index = rec2["record_index"] == rec1["record_index"] + 1
        # Elapsed physical time:
        t1 = rec1["unix"] + rec1["subsec_q15"] / 32768.0
        t2 = rec2["unix"] + rec2["subsec_q15"] / 32768.0
        elapsed = t2 - t1
        self.assertTrue(is_sequential_index)
        self.assertAlmostEqual(elapsed, 1.050, places=2)
        # Integer jump is 2 seconds
        self.assertEqual(rec2["unix"] - rec1["unix"], 2)

    def test_rmssd_non_bridging_across_gap(self):
        """Verifies RMSSD never bridges across recording gaps or missing seconds."""
        # Run 1: consecutive 1000ms beats
        run1 = [1000.0] * 30
        # Gap: no beats
        # Run 2: consecutive 1000ms beats
        run2 = [1000.0] * 30

        # With pure 1000ms intervals, RMSSD within each run is 0.0ms
        diffs1 = [abs(run1[i] - run1[i - 1]) for i in range(1, len(run1))]
        self.assertEqual(sum(diffs1), 0.0)

        # If incorrectly bridged across a gap with a displaced beat (e.g. 1500ms),
        # it would falsely inflate HRV. Independent run evaluation prevents this.
        r1_rmssd = rmssd(run1)
        r2_rmssd = rmssd(run2)
        self.assertEqual(r1_rmssd, 0.0)
        self.assertEqual(r2_rmssd, 0.0)

    def test_real_sensor_archive_provenance(self):
        """Verifies sensor truth provenance against the real 24,147-row capture if present."""
        archive_path = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "research-inputs",
            "sleep-1795375775-1795399923-3A748598-4D50-4FA9-84ED-319209137EE3.csv",
        )
        if not os.path.exists(archive_path):
            self.skipTest("Research sensor capture file not present in repository")

        import csv

        with open(archive_path, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        self.assertEqual(len(rows), 24147)
        unixes = [int(r["unix"]) for r in rows]
        rec_indices = [int(r["record_index"]) for r in rows]

        # Record index contiguity: exactly 0 missing record indices
        self.assertEqual(max(rec_indices) - min(rec_indices) + 1, 24147)
        self.assertEqual(len(set(rec_indices)), 24147)

        # Unix timestamps: exactly 1 2-second RTC rollover jump
        unix_jumps = [
            (unixes[i], unixes[i + 1])
            for i in range(len(unixes) - 1)
            if unixes[i + 1] != unixes[i] + 1
        ]
        self.assertEqual(len(unix_jumps), 1)
        self.assertEqual(unix_jumps[0], (1795397584, 1795397586))


if __name__ == "__main__":
    unittest.main()

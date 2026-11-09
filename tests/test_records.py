"""Decoder tests anchored to a real WHOOP MG capture (firmware 50.43.2.0)."""

import unittest

from whoop.records import (
    V18,
    decode_record,
    decode_v18,
    parse_header,
)

# v18 record captured from a real MG, CRC-validated on arrival.
REAL_V18 = bytes.fromhex(
    "2f1280f656e501af8bf16a707d005e00000000000000000002715408045e0000"
    "c52ccaf1409a593f3dd723c33d5c8b5b3ff603780066060010000000003b014e"
    "01080d400b010c060c0100000000000000000000000000000000000000000000"
    "01008e578080000000fba96bbf000000"
)


class TestHeader(unittest.TestCase):
    def test_real_header(self):
        header = parse_header(REAL_V18)
        self.assertIsNotNone(header)
        self.assertEqual(header.version, V18)
        self.assertEqual(header.flags, 0x80)
        self.assertEqual(header.record_index, 31807222)
        self.assertEqual(header.unix, 1794214831)
        self.assertEqual(header.subsec_q15, 32112)
        self.assertEqual(header.ppg_sample_rate_hz, 25)
        self.assertAlmostEqual(header.timestamp, 1794214831 + 32112 / 32768.0, places=6)

    def test_flags_bit7_selects_ppg_rate(self):
        low = bytearray(REAL_V18)
        low[2] = 0x00
        self.assertEqual(parse_header(bytes(low)).ppg_sample_rate_hz, 50)

    def test_rejects_non_historical(self):
        self.assertIsNone(parse_header(b"\x28\x12\x80" + b"\x00" * 20))

    def test_rejects_short(self):
        self.assertIsNone(parse_header(b"\x2f\x12"))


class TestV18(unittest.TestCase):
    def test_real_record_fields(self):
        sample = decode_v18(REAL_V18)
        self.assertIsNotNone(sample)
        self.assertEqual(sample.heart_rate, 94)
        self.assertTrue(sample.wearing)
        self.assertEqual(sample.rr_intervals_ms, [])
        self.assertAlmostEqual(sample.skin_temp_c, 33.36, places=2)
        self.assertAlmostEqual(sample.temp_aux1_c, 31.5, places=2)
        self.assertAlmostEqual(sample.temp_aux2_c, 33.4, places=2)
        self.assertEqual(sample.step_motion_counter, 1014)
        self.assertEqual(sample.step_cadence, 120)
        self.assertEqual(sample.sleep_state_byte, 1)
        self.assertIsNotNone(sample.gravity_g)
        self.assertAlmostEqual(sample.gravity_g[0], 0.0468, places=3)
        self.assertAlmostEqual(sample.gravity_g[1], 0.0952, places=3)
        self.assertAlmostEqual(sample.gravity_g[2], 0.8576, places=3)

    def test_dispatch_via_decode_record(self):
        self.assertIsNotNone(decode_record(REAL_V18))

    def test_implausible_hr_zeroes_only_hr(self):
        # One artefact bpm must not discard the second's temperature and motion.
        bad = bytearray(REAL_V18)
        bad[14] = 250
        sample = decode_v18(bytes(bad))
        self.assertIsNotNone(sample)
        self.assertEqual(sample.heart_rate, 0)
        self.assertFalse(sample.wearing)
        self.assertAlmostEqual(sample.skin_temp_c, 33.36, places=2)
        self.assertEqual(sample.step_motion_counter, 1014)

    def test_implausible_rr_is_dropped_not_the_record(self):
        bad = bytearray(REAL_V18)
        bad[15] = 1
        bad[16:18] = (50).to_bytes(2, "little", signed=True)  # below MIN_RR_MS
        sample = decode_v18(bytes(bad))
        self.assertIsNotNone(sample)
        self.assertEqual(sample.rr_intervals_ms, [])
        self.assertEqual(sample.heart_rate, 94)

    def test_plausible_rr_is_accepted(self):
        good = bytearray(REAL_V18)
        good[15] = 2
        good[16:18] = (800).to_bytes(2, "little", signed=True)
        good[18:20] = (820).to_bytes(2, "little", signed=True)
        sample = decode_v18(bytes(good))
        self.assertEqual(sample.rr_intervals_ms, [800, 820])

    def test_rr_count_above_four_is_ignored(self):
        bad = bytearray(REAL_V18)
        bad[15] = 9
        self.assertEqual(decode_v18(bytes(bad)).rr_intervals_ms, [])

    def test_wrong_version_rejected(self):
        other = bytearray(REAL_V18)
        other[1] = 20
        self.assertIsNone(decode_v18(bytes(other)))

    def test_truncated_record_rejected(self):
        self.assertIsNone(decode_v18(REAL_V18[:60]))

    def test_out_of_range_accel_dropped_only(self):
        bad = bytearray(REAL_V18)
        bad[37:41] = __import__("struct").pack("<f", 99.0)  # beyond +/-16 g
        sample = decode_v18(bytes(bad))
        self.assertIsNotNone(sample)
        self.assertIsNone(sample.gravity_g)
        self.assertEqual(sample.heart_rate, 94)


if __name__ == "__main__":
    unittest.main()

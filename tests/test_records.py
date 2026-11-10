"""Decoder tests anchored to a real WHOOP MG capture (firmware 50.43.2.0)."""

import struct
import unittest

from whoop.records import (
    V18,
    V26,
    V26_DELTA_OFFSET,
    V26_SAMPLE_COUNT,
    decode_record,
    decode_spo2_candidate,
    decode_v18,
    decode_v26,
    parse_header,
)

# v18 record captured from a real MG, CRC-validated on arrival.
REAL_V18 = bytes.fromhex(
    "2f1280f656e501af8bf16a707d005e00000000000000000002715408045e0000"
    "c52ccaf1409a593f3dd723c33d5c8b5b3ff603780066060010000000003b014e"
    "01080d400b010c060c0100000000000000000000000000000000000000000000"
    "01008e578080000000fba96bbf000000"
)

# v26 optical waveform from the same capture, one of 40 contiguous seconds.
REAL_V26 = bytes.fromhex(
    "2f1a800f5ce501c396f16aae670100719205008e006d0094009c009100efff12"
    "ffeefecafe22ffa1fffeff2800aaff99ffbaffe0ffb5ff28001e0023004a006b"
    "0080000085de3b500a000100"
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


class TestSpo2Candidate(unittest.TestCase):
    def test_in_band_values_are_candidates(self):
        for raw in (70, 95, 100):
            self.assertEqual(decode_spo2_candidate(raw), (raw, "pct"))

    def test_absent_values(self):
        self.assertEqual(decode_spo2_candidate(0), (None, "absent"))
        self.assertEqual(decode_spo2_candidate(None), (None, "absent"))

    def test_bit_seven_is_a_saturation_sentinel(self):
        for raw in (0x80, 0xA0, 0xFF):
            self.assertEqual(decode_spo2_candidate(raw), (None, "saturated"))

    def test_other_nonzero_values_are_diagnostic(self):
        for raw in (1, 65, 69, 101, 127):
            self.assertEqual(decode_spo2_candidate(raw), (None, "diagnostic"))

    def test_decode_v18_carries_the_candidate(self):
        frame = bytearray(REAL_V18)
        frame[74] = 96
        sample = decode_v18(bytes(frame))
        self.assertEqual(sample.spo2_candidate_raw, 96)
        self.assertEqual(sample.spo2_candidate_pct, 96)
        self.assertEqual(sample.spo2_candidate_status, "pct")

    def test_decode_v18_never_promotes_a_sentinel_to_a_value(self):
        frame = bytearray(REAL_V18)
        frame[74] = 0x80
        sample = decode_v18(bytes(frame))
        self.assertEqual(sample.spo2_candidate_raw, 0x80)
        self.assertIsNone(sample.spo2_candidate_pct)
        self.assertEqual(sample.spo2_candidate_status, "saturated")


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
        self.assertEqual(sample.sleep_state, 0)
        self.assertAlmostEqual(sample.signal_quality_log_variance, -0.9206, places=4)
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
        bad[37:41] = struct.pack("<f", 99.0)  # beyond +/-16 g
        sample = decode_v18(bytes(bad))
        self.assertIsNotNone(sample)
        self.assertIsNone(sample.gravity_g)
        self.assertEqual(sample.heart_rate, 94)

    def test_sleep_state_is_only_bits_four_and_five(self):
        for byte, expected in ((0x00, 0), (0x10, 1), (0x20, 2), (0x30, 3), (0xFF, 3), (0xCF, 0)):
            with self.subTest(byte=byte):
                record = bytearray(REAL_V18)
                record[73] = byte
                sample = decode_v18(bytes(record))
                self.assertEqual(sample.sleep_state_byte, byte)
                self.assertEqual(sample.sleep_state, expected)

    def test_signal_quality_has_no_physical_clamp(self):
        # A log variance is unbounded, unlike the accelerometer fields. Clamping
        # it to the range seen in one capture would silently drop real seconds.
        for value in (-40.0, -0.5, 0.0, 12.5):
            with self.subTest(value=value):
                record = bytearray(REAL_V18)
                record[105:109] = struct.pack("<f", value)
                self.assertAlmostEqual(
                    decode_v18(bytes(record)).signal_quality_log_variance, value, places=3
                )

    def test_non_finite_signal_quality_dropped_only(self):
        for value in (float("nan"), float("inf"), float("-inf")):
            with self.subTest(value=value):
                record = bytearray(REAL_V18)
                record[105:109] = struct.pack("<f", value)
                sample = decode_v18(bytes(record))
                self.assertIsNotNone(sample)
                self.assertIsNone(sample.signal_quality_log_variance)
                self.assertEqual(sample.heart_rate, 94)
                self.assertEqual(sample.sleep_state, 0)


class TestV26(unittest.TestCase):
    def test_real_record_fields(self):
        wave = decode_v26(REAL_V26)
        self.assertIsNotNone(wave)
        self.assertEqual(wave.header.version, V26)
        self.assertEqual(wave.unix, 1794217667)
        self.assertEqual(wave.header.record_index, 31808527)
        self.assertEqual(wave.header.subsec_q15, 26542)
        self.assertEqual(wave.sample_rate_hz, 25)
        self.assertFalse(wave.saturated)
        self.assertEqual(len(wave.samples), V26_SAMPLE_COUNT)
        self.assertEqual(wave.samples[0], 365169)
        self.assertEqual(wave.samples[-1], 364799)
        self.assertAlmostEqual(wave.dynamic_accel_g, 0.00679076, places=6)
        self.assertEqual(wave.channel_state, 2640)
        self.assertEqual(wave.morphology_pass, 1)

    def test_one_record_is_exactly_one_second_at_25_hz(self):
        # 25 samples at the flagged 25 Hz is what makes v26 a 1 Hz record stream.
        self.assertEqual(decode_v26(REAL_V26).duration_s, 1.0)

    def test_flag_clear_means_50_hz_and_half_a_second(self):
        fast = bytearray(REAL_V26)
        fast[2] = 0x00
        wave = decode_v26(bytes(fast))
        self.assertEqual(wave.sample_rate_hz, 50)
        self.assertEqual(wave.duration_s, 0.5)

    def test_every_step_equals_the_stored_delta(self):
        wave = decode_v26(REAL_V26)
        for i in range(V26_SAMPLE_COUNT - 1):
            delta = struct.unpack_from("<h", REAL_V26, V26_DELTA_OFFSET + 2 * i)[0]
            self.assertEqual(wave.samples[i + 1] - wave.samples[i], delta)

    def test_deltas_are_not_the_samples(self):
        # Reading the block as raw samples is the mistake that hid the encoding:
        # the anchor is ~365k while the deltas are tiny signed steps.
        wave = decode_v26(REAL_V26)
        raw = list(struct.unpack_from("<24h", REAL_V26, V26_DELTA_OFFSET))
        self.assertNotEqual(wave.samples[1:], raw)
        self.assertGreater(min(wave.samples), 300000)
        self.assertLess(max(abs(d) for d in raw), 1000)

    def test_negative_anchor_is_sign_extended_from_20_bits(self):
        negative = bytearray(REAL_V26)
        negative[15:19] = struct.pack("<i", (1 << 20) - 1)
        self.assertEqual(decode_v26(bytes(negative)).samples[0], -1)

    def test_positive_anchor_below_the_sign_bit_is_unchanged(self):
        positive = bytearray(REAL_V26)
        positive[15:19] = struct.pack("<i", (1 << 19) - 1)
        self.assertEqual(decode_v26(bytes(positive)).samples[0], 524287)

    def test_saturated_delta_truncates_the_poisoned_tail(self):
        for rail in (-32768, 32767):
            with self.subTest(rail=rail):
                bad = bytearray(REAL_V26)
                bad[V26_DELTA_OFFSET + 2 * 5 : V26_DELTA_OFFSET + 2 * 6] = struct.pack("<h", rail)
                wave = decode_v26(bytes(bad))
                self.assertTrue(wave.saturated)
                # Samples 0..5 survive; the overflowed step and everything after it do not.
                self.assertEqual(len(wave.samples), 6)
                good = decode_v26(REAL_V26)
                self.assertEqual(wave.samples, good.samples[:6])

    def test_unsaturated_record_keeps_all_samples(self):
        self.assertEqual(len(decode_v26(REAL_V26).samples), V26_SAMPLE_COUNT)

    def test_out_of_range_accel_dropped_only(self):
        bad = bytearray(REAL_V26)
        bad[67:71] = struct.pack("<f", 99.0)
        wave = decode_v26(bytes(bad))
        self.assertIsNone(wave.dynamic_accel_g)
        self.assertEqual(len(wave.samples), V26_SAMPLE_COUNT)
        self.assertEqual(wave.channel_state, 2640)

    def test_wrong_length_rejected(self):
        self.assertIsNone(decode_v26(REAL_V26[:75]))
        self.assertIsNone(decode_v26(REAL_V26 + b"\x00"))

    def test_wrong_version_rejected(self):
        other = bytearray(REAL_V26)
        other[1] = 18
        self.assertIsNone(decode_v26(bytes(other)))

    def test_not_historical_rejected(self):
        other = bytearray(REAL_V26)
        other[0] = 0x28
        self.assertIsNone(decode_v26(bytes(other)))

    def test_v26_is_not_mixed_into_the_per_second_stream(self):
        self.assertIsNone(decode_record(REAL_V26))


if __name__ == "__main__":
    unittest.main()
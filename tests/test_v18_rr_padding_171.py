"""Issue #171: declared V18 RR beats must not depend on opaque unused bytes.

The synthetic records deliberately do not claim to be observed hardware packets.
Framing integrity is tested separately; this tests record field interpretation.
"""
import unittest
from whoop.records import decode_v18
from whoop.framing import build_frame, parse_frame


class V18DeclaredRRTests(unittest.TestCase):
    @staticmethod
    def sample(count=1, rr=(800,), unused=None):
        data = bytearray(112)
        data[0] = 0x2F
        data[1] = 18
        data[2] = 0x80
        data[14] = 65
        data[15] = count
        for index, value in enumerate(rr):
            data[16 + 2 * index:18 + 2 * index] = value.to_bytes(2, "little", signed=True)
        for offset, value in (unused or {}).items():
            assert offset >= 16 + 2 * count and offset < 24
            data[offset] = value
        return bytes(data)

    def test_one_declared_beat_ignores_unused_bytes(self):
        result = decode_v18(self.sample(1, (800,), {18: 0xAB, 23: 0xCD}))
        self.assertEqual(result.rr_intervals_ms, [800])

    def test_two_declared_beats_ignore_unused_bytes(self):
        result = decode_v18(self.sample(2, (800, 820), {22: 0xAA}))
        self.assertEqual(result.rr_intervals_ms, [800, 820])

    def test_zero_declared_beats_does_not_create_beats(self):
        result = decode_v18(self.sample(0, (), {16: 0xFF, 23: 0xCD}))
        self.assertEqual(result.rr_intervals_ms, [])

    def test_invalid_declared_slot_is_filtered_individually(self):
        result = decode_v18(self.sample(2, (100, 800), {23: 0xAA}))
        self.assertEqual(result.rr_intervals_ms, [800])

    def test_out_of_range_count_is_not_trusted(self):
        result = decode_v18(self.sample(5, (800, 820)))
        self.assertEqual(result.rr_intervals_ms, [])
        self.assertFalse(result.rr_padding_valid)
        self.assertEqual(result.step_counter, result.step_motion_counter)

    def test_extreme_out_of_range_count_marks_padding_invalid(self):
        for invalid_count in (5, 9, 16, 255):
            with self.subTest(invalid_count=invalid_count):
                result = decode_v18(self.sample(invalid_count, (800, 820)))
                self.assertEqual(result.rr_intervals_ms, [])
                self.assertFalse(result.rr_padding_valid)

    def test_crc_corruption_is_rejected_before_rr_decode(self):
        record = self.sample(1, (800,), {18: 0xAA})
        frame = bytearray(build_frame(record))
        self.assertEqual(decode_v18(parse_frame(bytes(frame))).rr_intervals_ms, [800])
        frame[8 + 16] ^= 0x01
        self.assertIsNone(parse_frame(bytes(frame)))

    def test_truncated_v18_is_rejected(self):
        self.assertIsNone(decode_v18(self.sample()[:60]))

    def test_wrong_record_version_is_rejected(self):
        sample = bytearray(self.sample())
        sample[1] = 20
        self.assertIsNone(decode_v18(bytes(sample)))


if __name__ == "__main__":
    unittest.main()

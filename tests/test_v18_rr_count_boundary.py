"""Synthetic oversized V18 count parity tests; existing frozen tests stay intact."""
import unittest

from whoop.records import decode_v18


class V18RRCountBoundaryTests(unittest.TestCase):
    @staticmethod
    def record(count):
        data = bytearray(112)
        data[0] = 0x2F
        data[1] = 18
        data[2] = 0x80
        data[14] = 65
        data[15] = count
        for index, value in enumerate((800, 820, 840, 860)):
            data[16 + 2 * index:18 + 2 * index] = value.to_bytes(2, "little", signed=True)
        return bytes(data)

    def test_oversized_count_marks_padding_invalid_without_emitting_rr(self):
        for count in (5, 9, 16, 255):
            with self.subTest(count=count):
                result = decode_v18(self.record(count))
                self.assertIsNotNone(result)
                self.assertEqual(result.rr_intervals_ms, [])
                self.assertFalse(result.rr_padding_valid)
                self.assertEqual(result.step_counter, result.step_motion_counter)

    def test_four_declared_intervals_remain_valid(self):
        result = decode_v18(self.record(4))
        self.assertIsNotNone(result)
        self.assertEqual(result.rr_intervals_ms, [800, 820, 840, 860])
        self.assertTrue(result.rr_padding_valid)


if __name__ == "__main__":
    unittest.main()

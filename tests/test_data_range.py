import struct
import unittest

from whoop.data_range import (
    DataRangeResponse,
    decode_data_range_response,
)


class TestDataRangeResponse(unittest.TestCase):
    def _make_payload(
        self,
        rev=1,
        raw_old=10,
        read_p=20,
        write_p=130,
        trim_p=100,
        wrap_c=0,
        total_p=131072,
        used_rec=5000,
        free_rec=80000,
        oldest_s=1780000000,
        trim_s=1781000000,
        read_s=1782000000,
        newest_s=1786000000,
    ) -> bytes:
        return struct.pack(
            "<B8I8I",
            rev,
            raw_old,
            read_p,
            write_p,
            trim_p,
            wrap_c,
            total_p,
            used_rec,
            free_rec,
            oldest_s,
            0,
            trim_s,
            0,
            read_s,
            0,
            newest_s,
            0,
        )

    def test_decode_valid_payload(self):
        payload = self._make_payload()
        res = decode_data_range_response(payload)
        self.assertIsNotNone(res)
        self.assertEqual(res.revision, 1)
        self.assertEqual(res.write_page, 130)
        self.assertEqual(res.trim_page, 100)
        self.assertEqual(res.pages_behind, 30)
        self.assertEqual(res.oldest_unix, 1780000000)
        self.assertEqual(res.newest_unix, 1786000000)
        self.assertFalse(res.is_empty)

    def test_pages_behind_ring_wrap(self):
        payload = self._make_payload(write_p=5, trim_p=131070, total_p=131072)
        res = decode_data_range_response(payload)
        self.assertIsNotNone(res)
        self.assertEqual(res.pages_behind, 7)

    def test_truncated_payload_returns_none(self):
        self.assertIsNone(decode_data_range_response(b"short"))

    def test_sentinel_newest_returns_none_for_unix(self):
        payload = self._make_payload(newest_s=0xFFFFFFFF)
        res = decode_data_range_response(payload)
        self.assertIsNotNone(res)
        self.assertIsNone(res.newest_unix)
        self.assertTrue(res.is_empty)


if __name__ == "__main__":
    unittest.main()

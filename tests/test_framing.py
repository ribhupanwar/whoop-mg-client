"""Hardware-free tests for the framing layer. These run in CI on any OS."""

import unittest

from whoop.crc import crc8, crc16_modbus, crc32
from whoop.framing import (
    GEN4_PROFILE,
    GEN5_PROFILE,
    FrameReassembler,
    build_frame,
    pad_inner,
    parse_frame,
)
from whoop.constants import Command, PacketType, build_command


class TestChecksums(unittest.TestCase):
    def test_crc8_known_vector(self):
        # "123456789" with poly 0x07 / init 0x00 is the standard CRC-8 check value.
        self.assertEqual(crc8(b"123456789"), 0xF4)

    def test_crc16_modbus_known_vector(self):
        self.assertEqual(crc16_modbus(b"123456789"), 0x4B37)

    def test_crc32_matches_zlib(self):
        self.assertEqual(crc32(b"hello"), 0x3610A686)


class TestFraming(unittest.TestCase):
    def test_padding_rounds_to_multiple_of_four(self):
        for n in range(0, 17):
            padded = pad_inner(b"\x01" * n)
            self.assertEqual(len(padded) % 4, 0)
            self.assertGreaterEqual(len(padded), n)

    def test_roundtrip_both_generations(self):
        inner = bytes([PacketType.COMMAND, 0x01, Command.GET_CLOCK])
        for profile in (GEN4_PROFILE, GEN5_PROFILE):
            with self.subTest(profile=profile.name):
                frame = build_frame(inner, profile)
                self.assertEqual(len(frame), profile.total_len(profile.declared_len(frame)))
                self.assertEqual(parse_frame(frame, profile), pad_inner(inner))

    def test_gen5_client_hello_matches_hardware_vector(self):
        # Byte-for-byte frame observed on a real WHOOP gen5 band. Independently
        # validates crc16-modbus, crc32, header layout, and padding at once.
        inner = build_command(Command.HELLO_GEN5, body=b"\x01", seq=1)
        expected = bytes.fromhex("aa0108000001e6712301910136 3e5c8d".replace(" ", ""))
        self.assertEqual(build_frame(inner, GEN5_PROFILE), expected)

    def test_gen5_header_layout(self):
        frame = build_frame(b"\x23\x00\x0b", GEN5_PROFILE)
        self.assertEqual(frame[0], 0xAA)
        self.assertEqual(frame[1], 0x01)
        self.assertEqual(frame[4:6], b"\x00\x01")  # outbound marker
        self.assertTrue(GEN5_PROFILE.header_valid(frame))

    def test_inbound_marker_is_not_rejected(self):
        # Real strap->host frames carry [0x01, 0x00]. Header validity must not
        # depend on the direction marker, or nearly every notification is dropped.
        frame = bytearray(build_frame(b"\x30\x00\x01", GEN5_PROFILE))
        frame[4:6] = b"\x01\x00"
        frame[6:8] = crc16_modbus(bytes(frame[0:6])).to_bytes(2, "little")
        self.assertTrue(GEN5_PROFILE.header_valid(bytes(frame)))
        self.assertIsNotNone(parse_frame(bytes(frame), GEN5_PROFILE))

    def test_corrupt_payload_is_rejected(self):
        frame = bytearray(build_frame(b"\x28\x00\x01\x02\x03", GEN5_PROFILE))
        frame[-1] ^= 0xFF
        self.assertIsNone(parse_frame(bytes(frame), GEN5_PROFILE))

    def test_corrupt_header_is_rejected(self):
        frame = bytearray(build_frame(b"\x28\x00\x01", GEN5_PROFILE))
        frame[6] ^= 0xFF
        self.assertIsNone(parse_frame(bytes(frame), GEN5_PROFILE))


class TestReassembler(unittest.TestCase):
    def test_byte_at_a_time_delivery(self):
        inner = bytes([PacketType.REALTIME_DATA, 0x07, 0x42]) + b"\xAA" * 9
        frame = build_frame(inner, GEN5_PROFILE)
        reasm = FrameReassembler(GEN5_PROFILE)
        out = []
        for i in range(len(frame)):
            out.extend(reasm.feed(frame[i : i + 1]))
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0], pad_inner(inner))
        self.assertEqual(reasm.pending, 0)

    def test_sof_bytes_inside_payload_do_not_resync(self):
        # A payload saturated with 0xAA must survive arbitrary split points.
        inner = bytes([PacketType.HISTORICAL_DATA, 0x01, 0x18]) + b"\xAA" * 61
        frame = build_frame(inner, GEN5_PROFILE)
        for split in range(1, len(frame)):
            with self.subTest(split=split):
                reasm = FrameReassembler(GEN5_PROFILE)
                out = reasm.feed(frame[:split]) + reasm.feed(frame[split:])
                self.assertEqual(len(out), 1)
                self.assertEqual(out[0], pad_inner(inner))
                self.assertEqual(reasm.bad_frames, 0)

    def test_multiple_frames_in_one_chunk(self):
        a = build_frame(b"\x28\x00\x01", GEN5_PROFILE)
        b = build_frame(b"\x30\x00\x02", GEN5_PROFILE)
        reasm = FrameReassembler(GEN5_PROFILE)
        out = reasm.feed(a + b)
        self.assertEqual(len(out), 2)

    def test_leading_garbage_is_discarded(self):
        frame = build_frame(b"\x28\x00\x01", GEN5_PROFILE)
        reasm = FrameReassembler(GEN5_PROFILE)
        out = reasm.feed(b"\x00\xff\x13" + frame)
        self.assertEqual(len(out), 1)
        self.assertEqual(reasm.dropped_bytes, 3)

    def test_truncated_frame_stays_pending(self):
        frame = build_frame(b"\x28\x00\x01", GEN5_PROFILE)
        reasm = FrameReassembler(GEN5_PROFILE)
        self.assertEqual(reasm.feed(frame[:-2]), [])
        self.assertGreater(reasm.pending, 0)


class TestCommandSafety(unittest.TestCase):
    def test_destructive_command_refused(self):
        with self.assertRaises(ValueError):
            build_command(0x0F)

    def test_command_layout(self):
        self.assertEqual(build_command(Command.GET_CLOCK, seq=5), b"\x23\x05\x0b")


if __name__ == "__main__":
    unittest.main()

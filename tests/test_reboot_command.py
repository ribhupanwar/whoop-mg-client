"""Tests for WHOOP 5/MG reboot command, command response parsing, family offset rules, and erase safety."""

import unittest
from whoop.constants import (
    Command,
    CommandResult,
    PacketType,
    DESTRUCTIVE_COMMANDS,
    build_command,
    build_reboot_command,
    parse_command_response_result,
    parse_inner_command_response,
)
from whoop.framing import GEN5_PROFILE, build_frame, parse_frame, pad_inner


class TestRebootCommandAndEraseSafety(unittest.TestCase):
    def test_reboot_strap_opcode(self):
        """Verify REBOOT_STRAP is command 29 (0x1D) and POWER_CYCLE_STRAP is 32 (0x20)."""
        self.assertEqual(Command.REBOOT_STRAP, 0x1D)
        self.assertEqual(Command.REBOOT_STRAP, 29)
        self.assertEqual(Command.POWER_CYCLE_STRAP, 0x20)
        self.assertEqual(Command.POWER_CYCLE_STRAP, 32)
        self.assertEqual(Command.FORCE_TRIM, 0x19)
        self.assertEqual(Command.FORCE_TRIM, 25)

    def test_build_reboot_command(self):
        """build_reboot_command builds a valid non-destructive command with empty payload."""
        cmd = build_reboot_command(seq=7)
        self.assertEqual(cmd, bytes([PacketType.COMMAND, 7, Command.REBOOT_STRAP]))

        # Gen5 frame envelope check
        frame = build_frame(cmd, GEN5_PROFILE)
        self.assertEqual(frame[0], 0xAA)
        self.assertEqual(frame[1], 0x01)
        payload = parse_frame(frame, GEN5_PROFILE)
        self.assertEqual(payload, pad_inner(cmd))

    def test_destructive_commands_contain_force_trim_and_power_cycle(self):
        """DESTRUCTIVE_COMMANDS quarantines FORCE_TRIM (0x19), POWER_CYCLE_STRAP (0x20), and FORGET_BONDS (0x0F)."""
        self.assertIn(Command.FORCE_TRIM, DESTRUCTIVE_COMMANDS)
        self.assertIn(Command.POWER_CYCLE_STRAP, DESTRUCTIVE_COMMANDS)
        self.assertIn(Command.FORGET_BONDS, DESTRUCTIVE_COMMANDS)

        # REBOOT_STRAP (0x1D) is non-destructive warm restart and must NOT be blocked
        self.assertNotIn(Command.REBOOT_STRAP, DESTRUCTIVE_COMMANDS)

        # Attempting to build destructive commands directly must raise ValueError
        for op in (Command.FORCE_TRIM, Command.POWER_CYCLE_STRAP, Command.FORGET_BONDS):
            with self.subTest(opcode=op):
                with self.assertRaises(ValueError):
                    build_command(op)

    def test_family_aware_response_offset(self):
        """
        Verify the +4 offset shift between WHOOP 4.0 and WHOOP 5/MG.
        Reading offset 8 on WHOOP 5/MG frame returns 0x24 (inner type byte),
        while the actual result code is at offset 12.
        """
        # Synthetic WHOOP 5/MG frame with distinct sentinels
        raw_whoop5 = bytearray(16)
        raw_whoop5[8] = 0x24   # Inner type byte (COMMAND_RESPONSE)
        raw_whoop5[12] = 0x01  # True result: SUCCESS (1)

        # Reading WHOOP 5/MG offset
        res_whoop5 = parse_command_response_result(bytes(raw_whoop5), family="whoop5")
        self.assertEqual(res_whoop5, 1)

        # Synthetic WHOOP 4.0 frame
        raw_whoop4 = bytearray(16)
        raw_whoop4[8] = 0x01   # 4.0 result lives at offset 8
        res_whoop4 = parse_command_response_result(bytes(raw_whoop4), family="whoop4")
        self.assertEqual(res_whoop4, 1)

        # Short frame guard
        short_frame = bytes([0xAA, 0x01, 0x00, 0x00])
        self.assertNil = self.assertIsNone(parse_command_response_result(short_frame, family="whoop5"))

    def test_parse_inner_command_response(self):
        """Inner packet parser correctly decodes opcode, sequence, result, and payload."""
        # Success response to REBOOT_STRAP (29)
        inner_success = bytes([
            PacketType.COMMAND_RESPONSE,  # 0x24
            0x05,                         # resp_seq
            Command.REBOOT_STRAP,         # cmd: 0x1D (29)
            0x02,                         # origin_seq
            CommandResult.SUCCESS,        # result: 1
            0x00, 0x00, 0x00              # padding/payload
        ])

        parsed = parse_inner_command_response(inner_success)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed["packet_type"], PacketType.COMMAND_RESPONSE)
        self.assertEqual(parsed["resp_seq"], 5)
        self.assertEqual(parsed["cmd"], 29)
        self.assertEqual(parsed["origin_seq"], 2)
        self.assertEqual(parsed["result"], 1)
        self.assertTrue(parsed["is_success"])

        # Failure response
        inner_failure = bytes([
            PacketType.COMMAND_RESPONSE,
            0x06,
            Command.REBOOT_STRAP,
            0x03,
            CommandResult.FAILURE,
        ])
        parsed_fail = parse_inner_command_response(inner_failure)
        self.assertIsNotNone(parsed_fail)
        self.assertEqual(parsed_fail["result"], 0)
        self.assertFalse(parsed_fail["is_success"])

    def test_real_mg_toggle_response_frame_decoding(self):
        """
        Verify real WHOOP 5 MG response frames (from NOOP #891 hardware captures)
        decode cleanly with result code at offset 12 and cmd at offset 10.
        """
        # TOGGLE_LABRADOR_FILTERED(139 / 0x8B): aa010c0001002711 24 14 8b 2f 01 01 00 00 845a1705
        frame_hex = "aa010c000100271124148b2f01010000845a1705"
        raw_frame = bytes.fromhex(frame_hex)

        # Check raw result extraction at offset 12
        result_byte = parse_command_response_result(raw_frame, family="whoop5")
        self.assertEqual(result_byte, 1)

        # Parse frame envelope
        payload = parse_frame(raw_frame, GEN5_PROFILE)
        self.assertIsNotNone(payload)

        # Parse inner packet
        inner = parse_inner_command_response(payload)
        self.assertIsNotNone(inner)
        self.assertEqual(inner["cmd"], 0x8B)  # 139
        self.assertEqual(inner["result"], 1)
        self.assertTrue(inner["is_success"])


if __name__ == "__main__":
    unittest.main()

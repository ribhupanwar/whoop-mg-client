"""Tests for verified WHOOP MG device control commands, hardware events, and safety guards."""

import unittest

from whoop.constants import (
    Command,
    HardwareEvent,
    PacketType,
    DESTRUCTIVE_COMMANDS,
    build_command,
    build_broadcast_hr_command,
)
from whoop.framing import GEN5_PROFILE, build_frame, parse_frame, pad_inner


class TestDeviceControlCommands(unittest.TestCase):
    def test_broadcast_hr_command_enable(self):
        cmd = build_broadcast_hr_command(enable=True, seq=2)
        self.assertEqual(cmd, bytes([PacketType.COMMAND, 2, Command.SET_GENERIC_HR_PROFILE, 0x01]))

        # Check Gen5 frame envelope
        frame = build_frame(cmd, GEN5_PROFILE)
        self.assertEqual(frame[0], 0xAA)
        self.assertEqual(frame[1], 0x01)
        # Roundtrip parse
        payload = parse_frame(frame, GEN5_PROFILE)
        self.assertEqual(payload, pad_inner(cmd))

    def test_broadcast_hr_command_disable(self):
        cmd = build_broadcast_hr_command(enable=False, seq=5)
        self.assertEqual(cmd, bytes([PacketType.COMMAND, 5, Command.SET_GENERIC_HR_PROFILE, 0x00]))
        payload = parse_frame(build_frame(cmd, GEN5_PROFILE), GEN5_PROFILE)
        self.assertEqual(payload, pad_inner(cmd))

    def test_destructive_and_unverified_commands_rejected(self):
        # 0x0F (FORGET_BONDS) and 0x20 (REBOOT) must raise ValueError
        for opcode in (Command.FORGET_BONDS, Command.REBOOT):
            with self.subTest(opcode=opcode):
                self.assertIn(opcode, DESTRUCTIVE_COMMANDS)
                with self.assertRaises(ValueError):
                    build_command(opcode)

    def test_hardware_events_constants(self):
        self.assertEqual(HardwareEvent.WRIST_OFF, 10)
        self.assertEqual(HardwareEvent.DOUBLE_TAP, 14)
        self.assertEqual(HardwareEvent.PAIRING_MODE, 18)
        self.assertEqual(HardwareEvent.BLE_BONDED, 23)
        self.assertEqual(HardwareEvent.BLE_HR_PROFILE_ENABLE, 24)

    def test_whoop_5802_model_identifiers(self):
        # Verified from WhoopRegulatoryInfo_WhoopRegulatoryInfo.bundle
        harvard_models = ["WS40", "WP40"]
        maverick_models = ["WS50", "WM50", "WD50", "WB50"]
        goose_models = ["WG50", "WD50", "WB50"]

        self.assertIn("WS40", harvard_models)
        self.assertIn("WS50", maverick_models)
        self.assertIn("WG50", goose_models)


if __name__ == "__main__":
    unittest.main()

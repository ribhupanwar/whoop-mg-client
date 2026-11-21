"""Packet types and command opcodes.

Inner packet layout: [packet_type @0][seq @1][opcode|event_id|record_type @2][body...]

Destructive commands are named but never sent by any code here. FORGET_BONDS
drops the link and forces a from-scratch re-pair with no undo. FORCE_TRIM and
POWER_CYCLE_STRAP are strictly quarantined to protect on-band SPI flash.
REBOOT_STRAP (0x1D / 29) is the verified, non-destructive warm restart that preserves
circular buffer sensor data in flash.
"""

from enum import IntEnum


class PacketType(IntEnum):
    COMMAND = 0x23
    COMMAND_RESPONSE = 0x24
    PUFFIN_COMMAND = 0x25
    PUFFIN_COMMAND_RESPONSE = 0x26
    REALTIME_DATA = 0x28
    REALTIME_RAW_DATA = 0x2B
    HISTORICAL_DATA = 0x2F
    EVENT = 0x30
    METADATA = 0x31
    CONSOLE_LOGS = 0x32
    REALTIME_IMU_STREAM = 0x33
    HISTORICAL_IMU_STREAM = 0x34


class Command(IntEnum):
    LINK_VALID = 0x01
    GET_MAX_PROTOCOL_VERSION = 0x02  # gen4 only; gen5 silently no-ops
    TOGGLE_REALTIME_HR = 0x03
    REPORT_VERSION_INFO = 0x07  # gen4 only; gen5 silently no-ops
    SET_CLOCK = 0x0A
    GET_CLOCK = 0x0B
    SET_GENERIC_HR_PROFILE = 0x0E  # enables standard 0x180D broadcast, persists to NV (14)
    FORGET_BONDS = 0x0F  # destructive; unpairs device
    ABORT_HISTORICAL_TRANSMITS = 0x14
    SEND_HISTORICAL_DATA = 0x16
    HISTORICAL_DATA_RESULT = 0x17  # host ACK of a HISTORY_END burst
    FORCE_TRIM = 0x19  # command 25: destructive on-band flash sector trim, quarantined
    REBOOT_STRAP = 0x1D  # command 29 (0x1D): verified non-destructive warm MCU reboot
    POWER_CYCLE_STRAP = 0x20  # command 32 (0x20): cold SoC power-cycle, quarantined
    GET_DATA_RANGE = 0x22
    GET_HELLO_HARVARD = 0x23  # gen4
    HELLO_GEN5 = 0x91  # gen5 CLIENT_HELLO; write-with-response triggers just-works bond

    # Backwards compatibility alias
    REBOOT = POWER_CYCLE_STRAP


class CommandResult(IntEnum):
    FAILURE = 0
    SUCCESS = 1
    PENDING = 2
    UNSUPPORTED = 3


class HardwareEvent(IntEnum):
    """Event opcodes emitted asynchronously on characteristic fd4b0004."""
    WRIST_ON = 0x09               # Optical/capacitive sensor on-wrist
    WRIST_OFF = 0x0A              # Optical sensor off-wrist
    BLE_CONNECTION_UP = 0x0B      # Link connected
    BLE_CONNECTION_DOWN = 0x0C    # Link dropped
    DOUBLE_TAP = 0x0E             # Accelerometer registered double-tap gesture
    BOOT = 0x0F                   # Power-on / reset
    PAIRING_MODE = 0x12           # Entered pairing mode (pulsing blue LED)
    BATTERY_PACK_CONNECTED = 0x15 # Charger / power pack attached
    BATTERY_PACK_REMOVED = 0x16   # Charger / power pack detached
    BLE_BONDED = 0x17             # BLE security bonding completed
    BLE_HR_PROFILE_ENABLE = 0x18  # 0x180D broadcast enabled


# Never transmit these. FORGET_BONDS drops link; FORCE_TRIM deletes on-band records;
# POWER_CYCLE_STRAP is an unverified cold power reset.
DESTRUCTIVE_COMMANDS = frozenset({Command.FORGET_BONDS, Command.POWER_CYCLE_STRAP, Command.FORCE_TRIM})


def build_command(opcode: int, body: bytes = b"", seq: int = 0) -> bytes:
    if opcode in DESTRUCTIVE_COMMANDS:
        raise ValueError(f"refusing to build destructive command 0x{opcode:02X}")
    return bytes([PacketType.COMMAND, seq & 0xFF, opcode]) + body


def build_broadcast_hr_command(enable: bool, seq: int = 0) -> bytes:
    """Build verified Command 14 (0x0E) to enable/disable standard BLE HR broadcast."""
    return build_command(Command.SET_GENERIC_HR_PROFILE, body=b"\x01" if enable else b"\x00", seq=seq)


def build_reboot_command(seq: int = 0) -> bytes:
    """Build verified Command 29 (0x1D) to warm-reboot the WHOOP strap without flash data loss."""
    return build_command(Command.REBOOT_STRAP, body=b"", seq=seq)


def parse_command_response_result(frame: bytes, family: str = "whoop5") -> int | None:
    """Extract result byte from a raw COMMAND_RESPONSE frame using family-specific offsets.

    WHOOP 4.0: 4-byte header; inner starts at offset 4 -> result is at offset 8.
    WHOOP 5/MG: 8-byte Puffin header; inner starts at offset 8 -> result is at offset 12.
    Reading offset 8 on a WHOOP 5 frame falsely reads the inner type byte (0x24 = 36),
    causing false 'REJECTED' interpretations of successful commands.
    """
    inner_offset = 8 if family == "whoop5" else 4
    result_idx = inner_offset + 4
    if len(frame) <= result_idx:
        return None
    return frame[result_idx]


def parse_inner_command_response(inner: bytes) -> dict | None:
    """Parse an inner COMMAND_RESPONSE packet (where envelope headers are already stripped).

    inner[0]: PacketType (0x24 or 0x26)
    inner[1]: Response sequence
    inner[2]: Command opcode echoed
    inner[3]: Origin sequence
    inner[4]: Result code (0=FAILURE, 1=SUCCESS, 2=PENDING, 3=UNSUPPORTED)
    inner[5:]: Payload body
    """
    if len(inner) < 5:
        return None
    pkt_type = inner[0]
    if pkt_type not in (PacketType.COMMAND_RESPONSE, PacketType.PUFFIN_COMMAND_RESPONSE):
        return None
    return {
        "packet_type": pkt_type,
        "resp_seq": inner[1],
        "cmd": inner[2],
        "origin_seq": inner[3],
        "result": inner[4],
        "is_success": inner[4] == CommandResult.SUCCESS,
        "payload": inner[5:],
    }

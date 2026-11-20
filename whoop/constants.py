"""Packet types and command opcodes.

Inner packet layout: [packet_type @0][seq @1][opcode|event_id|record_type @2][body...]

Destructive commands are named but never sent by any code here. FORGET_BONDS
drops the link and forces a from-scratch re-pair with no undo.
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
    REBOOT = 0x20  # command 32: unverified power-cycle, quarantined
    GET_DATA_RANGE = 0x22
    GET_HELLO_HARVARD = 0x23  # gen4
    HELLO_GEN5 = 0x91  # gen5 CLIENT_HELLO; write-with-response triggers just-works bond


class HardwareEvent(IntEnum):
    """Event opcodes emitted asynchronously on characteristic fd4b0004."""
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


# Never transmit these. FORGET_BONDS drops link; REBOOT has unresolved side effects.
DESTRUCTIVE_COMMANDS = frozenset({Command.FORGET_BONDS, Command.REBOOT})


def build_command(opcode: int, body: bytes = b"", seq: int = 0) -> bytes:
    if opcode in DESTRUCTIVE_COMMANDS:
        raise ValueError(f"refusing to build destructive command 0x{opcode:02X}")
    return bytes([PacketType.COMMAND, seq & 0xFF, opcode]) + body


def build_broadcast_hr_command(enable: bool, seq: int = 0) -> bytes:
    """Build verified Command 14 (0x0E) to enable/disable standard BLE HR broadcast."""
    return build_command(Command.SET_GENERIC_HR_PROFILE, body=b"\x01" if enable else b"\x00", seq=seq)

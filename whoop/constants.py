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
    SET_GENERIC_HR_PROFILE = 0x0E  # enables standard 0x180D broadcast, persists to NV
    ABORT_HISTORICAL_TRANSMITS = 0x14
    SEND_HISTORICAL_DATA = 0x16
    HISTORICAL_DATA_RESULT = 0x17  # host ACK of a HISTORY_END burst
    GET_DATA_RANGE = 0x22
    GET_HELLO_HARVARD = 0x23  # gen4
    HELLO_GEN5 = 0x91  # gen5 CLIENT_HELLO; write-with-response triggers just-works bond


# Never transmit these.
DESTRUCTIVE_COMMANDS = frozenset({0x0F})  # FORGET_BONDS


def build_command(opcode: int, body: bytes = b"", seq: int = 0) -> bytes:
    if opcode in DESTRUCTIVE_COMMANDS:
        raise ValueError(f"refusing to build destructive command 0x{opcode:02X}")
    return bytes([PacketType.COMMAND, seq & 0xFF, opcode]) + body


def build_history_ack(seq: int, token: bytes) -> bytes:
    """Positive HISTORY_END result: [0x23][seq][0x17][0x01] + the 8-byte token.

    The token is echoed verbatim from inner[13:21] of the HISTORY_END marker.
    Without this ACK the strap re-announces the same burst indefinitely and the
    offload never advances.
    """
    if len(token) != 8:
        raise ValueError(f"batch token must be 8 bytes, got {len(token)}")
    return bytes([PacketType.COMMAND, seq & 0xFF, Command.HISTORICAL_DATA_RESULT, 0x01]) + token
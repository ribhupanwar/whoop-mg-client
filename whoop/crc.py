"""Checksum primitives for the WHOOP wire format.

Polynomials and initial values are protocol facts, not implementation choices.
"""

import zlib


def crc8(data: bytes) -> int:
    """Gen4 header check: poly 0x07, init 0x00, no reflection, no xorout."""
    crc = 0x00
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def crc16_modbus(data: bytes) -> int:
    """Gen5 header check: reflected poly 0xA001, init 0xFFFF."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def crc32(data: bytes) -> int:
    """Payload check, identical on gen4 and gen5."""
    return zlib.crc32(data) & 0xFFFFFFFF

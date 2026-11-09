"""Clean-room WHOOP BLE protocol layer.

Original implementation written from publicly documented protocol facts for
interoperability with a device the user owns. Contains no vendor code, assets,
or binaries.
"""

from .crc import crc8, crc16_modbus, crc32
from .framing import (
    GEN4_PROFILE,
    GEN5_PROFILE,
    BandProfile,
    FrameReassembler,
    build_frame,
    parse_frame,
)
from .gatt import GEN4, GEN5, GattProfile, profile_for_service

__all__ = [
    "crc8",
    "crc16_modbus",
    "crc32",
    "BandProfile",
    "GEN4_PROFILE",
    "GEN5_PROFILE",
    "FrameReassembler",
    "build_frame",
    "parse_frame",
    "GattProfile",
    "GEN4",
    "GEN5",
    "profile_for_service",
]
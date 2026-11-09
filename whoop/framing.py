"""Frame envelope and length-based reassembly.

Gen4 header (4 bytes): [0xAA][u16 declared LE][crc8 over the two size bytes]
Gen5 header (8 bytes): [0xAA][0x01][u16 declared LE][dir marker x2][crc16-modbus LE over bytes 0:6]

Both: declared = len(inner padded to a multiple of 4) + 4, and the frame ends
with a u32 LE CRC32 over that padded inner.

The direction marker differs by sender: host->strap is [0x00, 0x01], strap->host
is [0x01, 0x00]. Inbound frames must never be validated against the outbound
marker, or nearly every real notification gets rejected.
"""

from dataclasses import dataclass

from .crc import crc8, crc16_modbus, crc32
from .gatt import SOF

OUTBOUND_MARKER = b"\x00\x01"
INBOUND_MARKER = b"\x01\x00"


@dataclass(frozen=True)
class BandProfile:
    name: str
    header_len: int
    size_offset: int

    def total_len(self, declared: int) -> int:
        return self.header_len + declared

    def declared_len(self, frame: bytes) -> int:
        return frame[self.size_offset] | (frame[self.size_offset + 1] << 8)

    def header_valid(self, frame: bytes) -> bool:
        if len(frame) < self.header_len:
            return False
        if self.name == "gen4":
            return frame[3] == crc8(frame[1:3])
        want = frame[6] | (frame[7] << 8)
        return crc16_modbus(frame[0:6]) == want

    def build_header(self, declared: int) -> bytes:
        if self.name == "gen4":
            size = declared.to_bytes(2, "little")
            return bytes([SOF]) + size + bytes([crc8(size)])
        head = bytearray(8)
        head[0] = SOF
        head[1] = 0x01
        head[2:4] = declared.to_bytes(2, "little")
        head[4:6] = OUTBOUND_MARKER
        head[6:8] = crc16_modbus(bytes(head[0:6])).to_bytes(2, "little")
        return bytes(head)


GEN4_PROFILE = BandProfile("gen4", 4, 1)
GEN5_PROFILE = BandProfile("gen5", 8, 2)


def pad_inner(inner: bytes) -> bytes:
    remainder = len(inner) % 4
    return inner if remainder == 0 else inner + b"\x00" * (4 - remainder)


def build_frame(inner: bytes, profile: BandProfile = GEN5_PROFILE) -> bytes:
    padded = pad_inner(inner)
    declared = len(padded) + 4
    return profile.build_header(declared) + padded + crc32(padded).to_bytes(4, "little")


def parse_frame(frame: bytes, profile: BandProfile = GEN5_PROFILE) -> bytes | None:
    """Return the unpadded-significant inner payload, or None if the frame is bad.

    Padding is left intact; record decoders index fixed offsets and expect it.
    """
    if len(frame) < profile.header_len or frame[0] != SOF:
        return None
    if not profile.header_valid(frame):
        return None
    declared = profile.declared_len(frame)
    if declared < 4 or len(frame) < profile.total_len(declared):
        return None
    body = frame[profile.header_len : profile.total_len(declared)]
    inner, tail = body[:-4], body[-4:]
    if int.from_bytes(tail, "little") != crc32(inner):
        return None
    return inner


class FrameReassembler:
    """Accumulates BLE notification chunks and yields complete frames.

    Resassembly is driven by the declared length, never by scanning for 0xAA.
    Sensor payloads are full of 0xAA bytes and BLE splits land on them, so an
    SOF-triggered resync would shred records.
    """

    def __init__(self, profile: BandProfile = GEN5_PROFILE) -> None:
        self.profile = profile
        self._buffer = bytearray()
        self.dropped_bytes = 0
        self.bad_frames = 0

    def feed(self, chunk: bytes) -> list[bytes]:
        self._buffer.extend(chunk)
        frames: list[bytes] = []
        while True:
            if len(self._buffer) < self.profile.header_len:
                break
            if self._buffer[0] != SOF:
                # Only resync when the head is not a plausible frame start.
                del self._buffer[0]
                self.dropped_bytes += 1
                continue
            declared = self.profile.declared_len(self._buffer)
            total = self.profile.total_len(declared)
            if declared < 4 or total > 65535:
                del self._buffer[0]
                self.dropped_bytes += 1
                continue
            if len(self._buffer) < total:
                break
            candidate = bytes(self._buffer[:total])
            del self._buffer[:total]
            inner = parse_frame(candidate, self.profile)
            if inner is None:
                self.bad_frames += 1
                continue
            frames.append(inner)
        return frames

    @property
    def pending(self) -> int:
        return len(self._buffer)
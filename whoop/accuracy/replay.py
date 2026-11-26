"""BLE Packet Replay and Wire Simulation Engine.

Replays raw WHOOP BLE notifications through production decoders
(FrameReassembler, decode_v18, decode_v26, decode_v21) under realistic
wire impairments:
- MTU fragmentation (ATT MTU splits: 20, 23, 128, 247 bytes)
- Dropped / lost frames
- Out-of-order packet delivery
- Duplicate packet injection
- Byte corruption / CRC mismatch injection
- Disconnect / reconnect state reset
- Timestamp rollover and wrap handling
"""

from __future__ import annotations

import random
import re
import struct
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable, Generator, Iterable, Sequence

from ..framing import GEN4_PROFILE, GEN5_PROFILE, BandProfile, FrameReassembler, build_frame
from ..records import (
    IMUBuffer,
    RecordHeader,
    V18,
    V21,
    V26,
    V18Sample,
    V26Waveform,
    decode_v18,
    decode_v21,
    decode_v26,
    parse_header,
)

# Bounded timestamp cache: evicts oldest entries to prevent unbounded memory
# growth during long replay streams while preserving duplicate suppression.
MAX_SEEN_TIMESTAMPS = 100_000


@dataclass
class ReplayStats:
    """Statistics gathered during BLE replay execution."""

    chunks_fed: int = 0
    raw_bytes_fed: int = 0
    frames_reassembled: int = 0
    v18_decoded: int = 0
    v26_decoded: int = 0
    v21_decoded: int = 0
    other_frames: int = 0
    dropped_bytes: int = 0
    bad_frames: int = 0
    corrupted_injected: int = 0
    dropped_injected: int = 0
    duplicated_injected: int = 0
    duplicate_frames_suppressed: int = 0
    reconnect_events: int = 0


@dataclass
class WireImpairmentConfig:
    """Configuration for physical layer and BLE wire impairments."""

    mtu_chunk_size: int = 244  # ATT MTU chunk size (default 247 - 3 byte ATT header = 244)
    drop_rate: float = 0.0  # Probability (0.0 - 1.0) of dropping a chunk
    duplicate_rate: float = 0.0  # Probability of duplicating a chunk
    corrupt_rate: float = 0.0  # Probability of flipping a random byte in a chunk
    reorder_depth: int = 0  # Reorder window buffer (0 = strictly in-order)
    reconnect_every_n_chunks: int = 0  # Trigger connection reset every N chunks
    random_seed: int | None = 42


@dataclass
class DecodedRecordEvent:
    """A successfully decoded BLE record yielded during replay."""

    record_type: str  # "v18", "v26", "v21", "frame"
    timestamp: float
    data: V18Sample | V26Waveform | IMUBuffer | bytes
    raw_frame: bytes


class BlePacketReplayEngine:
    """Offline BLE notification reassembler and record decoder with wire simulation."""

    def __init__(
        self,
        profile: BandProfile = GEN5_PROFILE,
        impairments: WireImpairmentConfig | None = None,
    ) -> None:
        self.profile = profile
        self.impairments = impairments or WireImpairmentConfig()
        self.reassembler = FrameReassembler(profile=self.profile)
        self.stats = ReplayStats()
        # Timestamps of already-emitted decoded records, used to suppress
        # duplicate history packets that survive wire reassembly.
        # Bounded deque + set: deque provides FIFO eviction order, set provides O(1) membership.
        self._seen_timestamps_deque: deque[float] = deque(maxlen=MAX_SEEN_TIMESTAMPS)
        self._seen_timestamps: set[float] = set()
        if self.impairments.random_seed is not None:
            self._rng = random.Random(self.impairments.random_seed)
        else:
            self._rng = random.Random()

    def reset(self) -> None:
        """Reset internal reassembler state and statistics."""
        self.reassembler = FrameReassembler(profile=self.profile)
        self.stats = ReplayStats()
        self._seen_timestamps_deque = deque(maxlen=MAX_SEEN_TIMESTAMPS)
        self._seen_timestamps = set()

    def fragment_frame(self, frame_bytes: bytes, mtu: int | None = None) -> list[bytes]:
        """Split a complete BLE frame into ATT MTU chunks."""
        chunk_size = mtu or self.impairments.mtu_chunk_size
        if chunk_size <= 0:
            return [frame_bytes]
        return [frame_bytes[i : i + chunk_size] for i in range(0, len(frame_bytes), chunk_size)]

    def _apply_impairments(self, chunks: list[bytes]) -> list[bytes]:
        """Apply drop, corruption, duplication, and reordering to chunk stream."""
        if not (
            self.impairments.drop_rate > 0.0
            or self.impairments.duplicate_rate > 0.0
            or self.impairments.corrupt_rate > 0.0
            or self.impairments.reorder_depth > 0
        ):
            return list(chunks)

        impaired: list[bytes] = []
        window: list[bytes] = []

        for chunk in chunks:
            # Drop check
            if self.impairments.drop_rate > 0.0 and self._rng.random() < self.impairments.drop_rate:
                self.stats.dropped_injected += 1
                continue

            current = bytearray(chunk)

            # Corrupt check
            if self.impairments.corrupt_rate > 0.0 and self._rng.random() < self.impairments.corrupt_rate:
                if len(current) > 0:
                    flip_idx = self._rng.randint(0, len(current) - 1)
                    current[flip_idx] ^= 0xFF
                    self.stats.corrupted_injected += 1

            processed_chunk = bytes(current)

            # Duplicate check
            duplicates = 1
            if self.impairments.duplicate_rate > 0.0 and self._rng.random() < self.impairments.duplicate_rate:
                duplicates = 2
                self.stats.duplicated_injected += 1

            for _ in range(duplicates):
                if self.impairments.reorder_depth > 0:
                    window.append(processed_chunk)
                    if len(window) >= self.impairments.reorder_depth:
                        # Pop a random element from window
                        pick_idx = self._rng.randint(0, len(window) - 1)
                        impaired.append(window.pop(pick_idx))
                else:
                    impaired.append(processed_chunk)

        # Flush remaining window
        while window:
            pick_idx = self._rng.randint(0, len(window) - 1)
            impaired.append(window.pop(pick_idx))

        return impaired

    def feed_chunk(self, chunk: bytes) -> list[DecodedRecordEvent]:
        """Feed a single BLE notification chunk into the reassembler."""
        self.stats.chunks_fed += 1
        self.stats.raw_bytes_fed += len(chunk)

        # Periodic reconnect simulation check
        if (
            self.impairments.reconnect_every_n_chunks > 0
            and self.stats.chunks_fed % self.impairments.reconnect_every_n_chunks == 0
        ):
            self.stats.reconnect_events += 1
            # Reconnection purges fragmented in-flight buffers
            self.reassembler = FrameReassembler(profile=self.profile)

        frames = self.reassembler.feed(chunk)
        self.stats.dropped_bytes = self.reassembler.dropped_bytes
        self.stats.bad_frames = self.reassembler.bad_frames

        events: list[DecodedRecordEvent] = []
        for inner in frames:
            self.stats.frames_reassembled += 1
            event = self._decode_frame(inner)
            if event is None:
                # Duplicate history packet already emitted for this second.
                self.stats.duplicate_frames_suppressed += 1
                continue
            if event.record_type == "v18":
                self.stats.v18_decoded += 1
            elif event.record_type == "v26":
                self.stats.v26_decoded += 1
            elif event.record_type == "v21":
                self.stats.v21_decoded += 1
            else:
                self.stats.other_frames += 1
            events.append(event)
        return events

    def _decode_frame(self, inner: bytes) -> DecodedRecordEvent | None:
        """Route inner frame payload to the appropriate record decoder.

        Returns None for a duplicate history packet (same timestamp as an
        already-emitted record) so the caller can suppress it.
        """
        if len(inner) >= 2 and inner[0] == 0x2F:
            hist_ver = inner[1]
            header = parse_header(inner)
            ts = header.timestamp if header else 0.0

            if hist_ver == V18:
                v18_rec = decode_v18(inner)
                return self._emit_or_suppress("v18", v18_rec.header.timestamp, v18_rec, inner)
            elif hist_ver == V26:
                v26_rec = decode_v26(inner)
                return self._emit_or_suppress("v26", v26_rec.header.timestamp, v26_rec, inner)
            elif hist_ver == V21:
                v21_rec = decode_v21(inner)
                return self._emit_or_suppress("v21", v21_rec.header.timestamp, v21_rec, inner)

        return DecodedRecordEvent(
            record_type="frame",
            timestamp=0.0,
            data=inner,
            raw_frame=inner,
        )

    def _emit_or_suppress(
        self,
        record_type: str,
        timestamp: float,
        data: V18Sample | V26Waveform | IMUBuffer,
        raw_frame: bytes,
    ) -> DecodedRecordEvent | None:
        """Emit a record once per timestamp; suppress duplicate history packets."""
        if timestamp in self._seen_timestamps:
            return None
        # Evict oldest entry when cache is full to bound memory growth.
        if len(self._seen_timestamps_deque) >= MAX_SEEN_TIMESTAMPS:
            oldest = self._seen_timestamps_deque.popleft()
            self._seen_timestamps.discard(oldest)
        self._seen_timestamps_deque.append(timestamp)
        self._seen_timestamps.add(timestamp)
        return DecodedRecordEvent(
            record_type=record_type,
            timestamp=timestamp,
            data=data,
            raw_frame=raw_frame,
        )

    def replay_chunks(self, chunks: Iterable[bytes]) -> Generator[DecodedRecordEvent, None, None]:
        """Stream chunks with simulated impairments and yield decoded record events."""
        chunk_list = list(chunks)
        impaired_chunks = self._apply_impairments(chunk_list)

        for chunk in impaired_chunks:
            events = self.feed_chunk(chunk)
            for event in events:
                yield event

    def replay_raw_frames(self, frames: Iterable[bytes]) -> Generator[DecodedRecordEvent, None, None]:
        """Convert complete frames to MTU-chunked stream with impairments and replay."""
        all_chunks: list[bytes] = []
        for frame in frames:
            chunks = self.fragment_frame(frame)
            all_chunks.extend(chunks)

        yield from self.replay_chunks(all_chunks)

    def parse_hex_log(self, text_or_lines: str | Sequence[str]) -> list[bytes]:
        """Parse raw BLE hex dumps or log lines into binary notification chunks.

        Supports formats:
        - Clean hex: 'aa010074...'
        - Wireshark Value: 'Value: 2f 12 80 00 ...'
        - Hex spaced: 'aa 01 00 74'
        - Prefixed: '0xaa, 0x01, 0x00...'
        """
        if isinstance(text_or_lines, str):
            lines = text_or_lines.splitlines()
        else:
            lines = list(text_or_lines)

        chunks: list[bytes] = []
        for line in lines:
            line_str = line.strip()
            if not line_str or line_str.startswith("#") or line_str.startswith("//"):
                continue

            # Strip prefixes like "Value: ", "Rx: ", "chunk: "
            if ":" in line_str:
                parts = line_str.split(":", 1)
                # If the part before colon has letters like 'Value' or 'chunk', strip it
                if any(k in parts[0].lower() for k in ("val", "rx", "chunk", "ble", "notify", "data")):
                    line_str = parts[1].strip()

            # Remove 0x, commas, spaces
            cleaned = re.sub(r"0x|,|\s+", "", line_str)
            if not cleaned:
                continue

            # Check if valid hex
            try:
                raw_chunk = bytes.fromhex(cleaned)
                if raw_chunk:
                    chunks.append(raw_chunk)
            except ValueError:
                # Skip non-hex line
                continue

        return chunks

    def replay_hex_log(self, text_or_lines: str | Sequence[str]) -> Generator[DecodedRecordEvent, None, None]:
        """Parse hex log lines and replay them."""
        chunks = self.parse_hex_log(text_or_lines)
        yield from self.replay_chunks(chunks)

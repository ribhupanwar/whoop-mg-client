"""Unit tests for the BLE Packet Replay and Wire Simulation Engine."""

from __future__ import annotations

import struct
import unittest

from whoop.accuracy import (
    BlePacketReplayEngine,
    DecodedRecordEvent,
    MAX_SEEN_TIMESTAMPS,
    WireImpairmentConfig,
)
from whoop.framing import GEN5_PROFILE, build_frame
from whoop.records import V18, V21, V26, IMUBuffer, V18Sample, V26Waveform


def make_dummy_v18_inner(unix: int = 1700000000, hr: int = 72) -> bytes:
    """Build a mock 112-byte inner payload for a V18 record."""
    buf = bytearray(112)
    buf[0] = 0x2F  # Record packet type
    buf[1] = V18   # Hist version 18
    buf[2] = 0x80  # Flags (optical 25 Hz)
    struct.pack_into("<I", buf, 3, 1001)       # record_index
    struct.pack_into("<I", buf, 7, unix)       # unix
    struct.pack_into("<H", buf, 11, 0)         # subsec_q15
    buf[13] = 0
    buf[14] = hr                               # heart_rate (offset 14)
    buf[15] = 0                                # rr_count (offset 15)
    # Set dynamic accel float at offset 33
    struct.pack_into("<f", buf, 33, 0.045)
    return bytes(buf)


def make_dummy_v26_inner(unix: int = 1700000000) -> bytes:
    """Build a mock 76-byte inner payload for a V26 record."""
    buf = bytearray(76)
    buf[0] = 0x2F
    buf[1] = V26
    buf[2] = 0x80
    struct.pack_into("<I", buf, 3, 2002)
    struct.pack_into("<I", buf, 7, unix)
    struct.pack_into("<H", buf, 11, 0)
    return bytes(buf)


def make_dummy_v21_inner(unix: int = 1700000000) -> bytes:
    """Build a mock 1232-byte inner payload for a V21 IMU record."""
    buf = bytearray(1232)
    buf[0] = 0x2F
    buf[1] = V21
    buf[2] = 0x80
    struct.pack_into("<I", buf, 3, 3003)
    struct.pack_into("<I", buf, 7, unix)
    struct.pack_into("<H", buf, 11, 0)
    struct.pack_into("<H", buf, 16, 50)  # accel_count = 50
    struct.pack_into("<H", buf, 622, 50) # gyro_count = 50
    return bytes(buf)


class TestBlePacketReplay(unittest.TestCase):
    def test_clean_frame_reassembly_and_v18_decode(self) -> None:
        inner = make_dummy_v18_inner(unix=1700000050, hr=75)
        frame = build_frame(inner, profile=GEN5_PROFILE)

        engine = BlePacketReplayEngine()
        # Fragment into 20-byte ATT chunks (common BLE default MTU)
        chunks = engine.fragment_frame(frame, mtu=20)
        self.assertGreater(len(chunks), 1)

        events: list[DecodedRecordEvent] = []
        for chunk in chunks:
            events.extend(engine.feed_chunk(chunk))

        self.assertEqual(len(events), 1)
        event = events[0]
        self.assertEqual(event.record_type, "v18")
        self.assertEqual(event.timestamp, 1700000050.0)
        self.assertIsInstance(event.data, V18Sample)
        self.assertEqual(event.data.heart_rate, 75)
        self.assertEqual(engine.stats.v18_decoded, 1)
        self.assertEqual(engine.stats.frames_reassembled, 1)
        self.assertEqual(engine.stats.dropped_bytes, 0)

    def test_v26_and_v21_replay(self) -> None:
        inner26 = make_dummy_v26_inner(unix=1700000100)
        frame26 = build_frame(inner26, profile=GEN5_PROFILE)

        inner21 = make_dummy_v21_inner(unix=1700000200)
        frame21 = build_frame(inner21, profile=GEN5_PROFILE)

        engine = BlePacketReplayEngine()
        events = list(engine.replay_raw_frames([frame26, frame21]))

        self.assertEqual(len(events), 2)
        self.assertEqual(events[0].record_type, "v26")
        self.assertIsInstance(events[0].data, V26Waveform)
        self.assertEqual(events[1].record_type, "v21")
        self.assertIsInstance(events[1].data, IMUBuffer)
        self.assertEqual(engine.stats.v26_decoded, 1)
        self.assertEqual(engine.stats.v21_decoded, 1)

    def test_corrupted_chunk_impairment(self) -> None:
        inner = make_dummy_v18_inner(unix=1700000010, hr=80)
        frame = build_frame(inner, profile=GEN5_PROFILE)

        # 100% corruption rate
        config = WireImpairmentConfig(corrupt_rate=1.0, random_seed=42)
        engine = BlePacketReplayEngine(impairments=config)
        chunks = engine.fragment_frame(frame, mtu=50)

        events = list(engine.replay_chunks(chunks))
        # Corrupted frame should fail CRC32 and produce 0 decoded records
        self.assertEqual(len(events), 0)
        self.assertGreater(engine.stats.corrupted_injected, 0)
        self.assertGreater(engine.stats.dropped_bytes, 0)

    def test_dropped_chunk_recovery(self) -> None:
        inner1 = make_dummy_v18_inner(unix=1700000010, hr=80)
        frame1 = build_frame(inner1, profile=GEN5_PROFILE)
        inner2 = make_dummy_v18_inner(unix=1700000011, hr=81)
        frame2 = build_frame(inner2, profile=GEN5_PROFILE)

        engine = BlePacketReplayEngine()
        chunks1 = engine.fragment_frame(frame1, mtu=30)
        chunks2 = engine.fragment_frame(frame2, mtu=30)

        # Drop the middle chunk of frame 1
        corrupted_stream = [chunks1[0]] + chunks2
        events = list(engine.replay_chunks(corrupted_stream))

        # Frame 1 failed due to missing chunks, but frame 2 cleanly reassembles
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].data.heart_rate, 81)

    def test_hex_log_parsing(self) -> None:
        inner = make_dummy_v18_inner(unix=1700000020, hr=68)
        frame = build_frame(inner, profile=GEN5_PROFILE)

        # Generate hex text lines with Wireshark/spaced formatting
        hex_str = frame.hex()
        half = len(hex_str) // 2
        log_text = f"""
# Raw BLE notification capture
Value: {hex_str[:half]}
Rx: {hex_str[half:]}
"""
        engine = BlePacketReplayEngine()
        events = list(engine.replay_hex_log(log_text))

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].data.heart_rate, 68)

    def test_duplicate_history_packets_are_suppressed(self) -> None:
        """Fault condition: duplicate history packets must not yield duplicate records."""
        inner = make_dummy_v18_inner(unix=1700000050, hr=72)
        frame = build_frame(inner, profile=GEN5_PROFILE)

        engine = BlePacketReplayEngine(profile=GEN5_PROFILE)
        chunks = engine.fragment_frame(frame, mtu=20)

        # Re-stream the identical frame (duplicate history packet).
        stream = chunks + chunks
        events = list(engine.replay_chunks(stream))

        # Exactly one record emitted despite two identical frames on the wire.
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].data.heart_rate, 72)
        self.assertEqual(engine.stats.frames_reassembled, 2)
        self.assertEqual(engine.stats.duplicate_frames_suppressed, 1)
        self.assertEqual(engine.stats.v18_decoded, 1)

    def test_reordered_chunks_still_reassemble(self) -> None:
        """Fault condition: out-of-order chunk delivery must not produce false records.

        FrameReassembler expects in-order chunks within a frame. With MTU large enough
        for each frame to fit in one chunk, reordering only changes frame arrival order,
        not chunk order within a frame. All frames must still decode.
        """
        inner1 = make_dummy_v18_inner(unix=1700000010, hr=80)
        inner2 = make_dummy_v18_inner(unix=1700000011, hr=81)
        frame1 = build_frame(inner1, profile=GEN5_PROFILE)
        frame2 = build_frame(inner2, profile=GEN5_PROFILE)

        # MTU large enough that each frame is a single chunk.
        config = WireImpairmentConfig(reorder_depth=4, random_seed=42)
        engine = BlePacketReplayEngine(impairments=config)

        chunks1 = engine.fragment_frame(frame1, mtu=300)
        chunks2 = engine.fragment_frame(frame2, mtu=300)
        self.assertEqual(len(chunks1), 1)
        self.assertEqual(len(chunks2), 1)

        events = list(engine.replay_chunks(chunks1 + chunks2))

        # Both frames decode regardless of arrival order.
        self.assertEqual(len(events), 2)
        hr_values = {e.data.heart_rate for e in events}
        self.assertEqual(hr_values, {80, 81})

    def test_reconnect_resets_state_and_decodes_subsequent_frames(self) -> None:
        """Fault condition: periodic reconnect must reset reassembler without losing subsequent frames."""
        inner1 = make_dummy_v18_inner(unix=1700000010, hr=80)
        inner2 = make_dummy_v18_inner(unix=1700000011, hr=81)
        frame1 = build_frame(inner1, profile=GEN5_PROFILE)
        frame2 = build_frame(inner2, profile=GEN5_PROFILE)

        # Small MTU so each frame = few chunks; reconnect every 2 chunks resets between frames.
        config = WireImpairmentConfig(reconnect_every_n_chunks=2)
        engine = BlePacketReplayEngine(impairments=config)

        chunks1 = engine.fragment_frame(frame1, mtu=200)
        chunks2 = engine.fragment_frame(frame2, mtu=200)
        all_chunks = chunks1 + chunks2

        events = list(engine.replay_chunks(all_chunks))

        # Reconnect purges in-flight partial frames, but subsequent intact frames decode.
        self.assertGreaterEqual(len(events), 1)
        # At least the second frame (after reconnect) should decode.
        self.assertIn(81, {e.data.heart_rate for e in events})
        self.assertGreaterEqual(engine.stats.reconnect_events, 1)

    def test_bounded_seen_timestamps_evicts_oldest(self) -> None:
        """Fault condition: _seen_timestamps must not grow unbounded during long replay."""
        engine = BlePacketReplayEngine()

        # Emit records with distinct timestamps beyond the cache bound.
        for i in range(MAX_SEEN_TIMESTAMPS + 100):
            inner = make_dummy_v18_inner(unix=1700000000 + i, hr=70)
            frame = build_frame(inner, profile=GEN5_PROFILE)
            chunks = engine.fragment_frame(frame, mtu=10)
            list(engine.replay_chunks(chunks))

        # Cache must remain bounded.
        self.assertLessEqual(len(engine._seen_timestamps), MAX_SEEN_TIMESTAMPS)
        self.assertLessEqual(len(engine._seen_timestamps_deque), MAX_SEEN_TIMESTAMPS)

        # Oldest timestamps should have been evicted; re-emitting them should produce new records.
        inner = make_dummy_v18_inner(unix=1700000000, hr=70)
        frame = build_frame(inner, profile=GEN5_PROFILE)
        chunks = engine.fragment_frame(frame, mtu=10)
        events = list(engine.replay_chunks(chunks))
        self.assertEqual(len(events), 1)  # Re-emitted after eviction, not suppressed


if __name__ == "__main__":
    unittest.main()

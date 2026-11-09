"""Console stream tests anchored to a real WHOOP MG offload (firmware 50.43.2.0)."""

import struct
import unittest

from whoop.console import (
    CONSOLE_TEXT_OFFSET,
    ConsoleStream,
    parse_body_transition,
    parse_wear_detect,
)
from whoop.constants import PacketType

# One real 64-byte CONSOLE_LOGS inner. Its text is a mid-token fragment:
# "t_ir_near_m = 3.131716, opt_ir_m_ratio = 5.040586," with no newline.
REAL_FRAGMENT = bytes.fromhex(
    "32cf0200af8bf16a146e340001"
    "745f69725f6e6561725f6d203d20332e3133313731362c206f70745f69725f6d"
    "5f726174696f203d20352e3034303538362c00"
)
REAL_FRAGMENT_TEXT = "t_ir_near_m = 3.131716, opt_ir_m_ratio = 5.040586,"
REAL_UNIX = 1794214831

REAL_WEAR_LINE = (
    "72, 913983509: SIGPROC-WEAR-DETECT V5: moving from state 5 to state 3 "
    "(debug = 39), state_cnt = 138, opt_ir_near_m = 5.030884, "
    "opt_ir_m_ratio = 7.152284, opt_amb_m = 0.033682, range_stab = 0.629746, "
    "num_rec = 3, orient_60 = 1.000000, orient_30 = 0.000000, "
    "acc_x = -0.086042, acc_y = 0.271743, sleep = 0, lm_w = 1, lm_w_cnt = 38, "
    "lm_hr_pk_m = 117.096138, lm_hr_pk_dev = 32.207169, lm_harm_perc = 0.026316, "
    "skin_temp = 32.893230, hrc = 223"
)


def console_inner(text: bytes, seq: int = 0, unix: int = REAL_UNIX) -> bytes:
    head = (
        bytes([PacketType.CONSOLE_LOGS, seq & 0xFF, 0x02, 0x00])
        + struct.pack("<I", unix)
        + bytes([0x14, 0x6E, 0x34, 0x00, 0x01])
    )
    assert len(head) == CONSOLE_TEXT_OFFSET
    return head + text + b"\x00"


class TestConsoleStream(unittest.TestCase):
    def test_real_fragment_prefix_and_terminator(self):
        stream = ConsoleStream()
        self.assertEqual(stream.feed(REAL_FRAGMENT), [])
        self.assertEqual(stream.fragments, 1)
        # 50 text bytes; the trailing 0x00 is a terminator, not content.
        self.assertEqual(stream.pending, len(REAL_FRAGMENT_TEXT))

        tail = " opt_amb_m = 0.118761\n"
        lines = stream.feed(console_inner(tail.encode(), seq=0xD0))
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0].text, REAL_FRAGMENT_TEXT + tail.rstrip("\n"))
        self.assertEqual(lines[0].unix, REAL_UNIX)
        self.assertEqual(stream.pending, 0)

    def test_line_split_at_every_point(self):
        text = (REAL_WEAR_LINE + "\n").encode()
        for split in range(1, len(text)):
            with self.subTest(split=split):
                stream = ConsoleStream()
                out = stream.feed(console_inner(text[:split]))
                out += stream.feed(console_inner(text[split:], seq=1))
                self.assertEqual(len(out), 1)
                self.assertEqual(out[0].text, REAL_WEAR_LINE)

    def test_seq_wrap_must_not_reorder_fragments(self):
        # seq wraps at 256; joining in arrival order is the only correct order.
        stream = ConsoleStream()
        parts = [b"alpha ", b"beta ", b"gamma ", b"delta\n"]
        seqs = [0xFE, 0xFF, 0x00, 0x01]
        out = []
        for part, seq in zip(parts, seqs):
            out.extend(stream.feed(console_inner(part, seq=seq)))
        self.assertEqual([line.text for line in out], ["alpha beta gamma delta"])

    def test_multiple_lines_in_one_fragment(self):
        stream = ConsoleStream()
        out = stream.feed(console_inner(b"first\nsecond\nthird\n"))
        self.assertEqual([line.text for line in out], ["first", "second", "third"])

    def test_flush_emits_unterminated_tail(self):
        stream = ConsoleStream()
        self.assertEqual(stream.feed(console_inner(b"no newline yet")), [])
        out = stream.flush()
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0].text, "no newline yet")
        self.assertEqual(stream.pending, 0)
        self.assertEqual(stream.flush(), [])

    def test_non_console_packet_ignored(self):
        stream = ConsoleStream()
        self.assertEqual(stream.feed(b"\x2f\x12\x80" + b"\x00" * 61), [])
        self.assertEqual(stream.fragments, 0)

    def test_short_inner_ignored(self):
        stream = ConsoleStream()
        self.assertEqual(stream.feed(b"\x32\x00\x02"), [])
        self.assertEqual(stream.fragments, 0)

    def test_line_unix_is_the_fragment_where_the_line_started(self):
        stream = ConsoleStream()
        stream.feed(console_inner(b"started here ", unix=1000))
        out = stream.feed(console_inner(b"finished here\n", unix=2000))
        self.assertEqual(out[0].unix, 1000)

    def test_module_extraction(self):
        stream = ConsoleStream()
        out = stream.feed(console_inner((REAL_WEAR_LINE + "\n").encode()))
        self.assertEqual(out[0].module, "SIGPROC-WEAR-DETECT V5")


class TestWearDetect(unittest.TestCase):
    def test_real_line_fields(self):
        event = parse_wear_detect(REAL_WEAR_LINE)
        self.assertIsNotNone(event)
        self.assertEqual(event.from_state, 5)
        self.assertEqual(event.to_state, 3)
        self.assertEqual(event.debug, 39)
        self.assertEqual(event.state_cnt, 138)
        self.assertAlmostEqual(event.skin_temp_c, 32.893230, places=6)
        self.assertEqual(event.hrc, 223.0)
        self.assertAlmostEqual(event.fields["lm_hr_pk_m"], 117.096138, places=6)
        self.assertAlmostEqual(event.fields["acc_x"], -0.086042, places=6)
        self.assertEqual(event.fields["sleep"], 0.0)

    def test_unrelated_line_rejected(self):
        self.assertIsNone(parse_wear_detect("72, 913847859: SENSORS: IMU double tap detected"))

    def test_wear_line_without_transition_rejected(self):
        self.assertIsNone(parse_wear_detect("SIGPROC-WEAR-DETECT V5: had an opt-only ON transition"))

    def test_body_transition(self):
        line = "72, 913983509: SIGPROC: wear-detection moving from on-body to off-body"
        self.assertEqual(parse_body_transition(line), ("on-body", "off-body"))

    def test_body_transition_reverse(self):
        line = "73, 589889: SIGPROC: wear-detection moving from off-body to on-body"
        self.assertEqual(parse_body_transition(line), ("off-body", "on-body"))

    def test_no_transition_returns_none(self):
        self.assertIsNone(parse_body_transition(REAL_WEAR_LINE))


if __name__ == "__main__":
    unittest.main()
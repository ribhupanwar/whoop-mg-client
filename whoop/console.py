"""Reassemble the gen5 CONSOLE_LOGS stream and parse wear-detection events.

The band emits its firmware log as one continuous newline-separated text stream
chopped into fixed-size fragments. Each 0x32 inner carries:
  [1] seq (wraps at 256)   [2] stream id   [4:8] unix u32 LE
  [13:] text fragment, terminated by a single 0x00

Fragments MUST be joined in arrival order. Sorting by seq scrambles the stream
because seq wraps several times within a single offload.

A log line reads "<core>, <tick>: <MODULE>: <message>". SIGPROC-WEAR-DETECT V5
lines carry the band's own on-body decision inputs, which is the diagnostic for
a capture where v18 R-R counts are all zero.
"""

import re
import struct
from dataclasses import dataclass, field

from .constants import PacketType

CONSOLE_TEXT_OFFSET = 13

_WEAR_RE = re.compile(
    r"moving from state (\d+) to state (\d+) \(debug = (\d+)\), state_cnt = (\d+)"
)
_KV_RE = re.compile(r"([A-Za-z_][A-Za-z_0-9]*) = (-?\d+(?:\.\d+)?)")
_BODY_RE = re.compile(r"wear-detection moving from (on-body|off-body) to (on-body|off-body)")
_LINE_RE = re.compile(r"^\s*(\d+),\s*(\d+):\s*([^:]+):\s*(.*)$")


@dataclass
class ConsoleLine:
    unix: int | None
    text: str

    @property
    def module(self) -> str | None:
        match = _LINE_RE.match(self.text)
        return match.group(3).strip() if match else None


@dataclass
class WearDetectEvent:
    from_state: int
    to_state: int
    debug: int
    state_cnt: int
    fields: dict[str, float] = field(default_factory=dict)

    @property
    def skin_temp_c(self) -> float | None:
        return self.fields.get("skin_temp")

    @property
    def hrc(self) -> float | None:
        return self.fields.get("hrc")


class ConsoleStream:
    """Joins console fragments and yields complete lines.

    Mirrors FrameReassembler: a partial trailing line stays buffered until
    flush(), so a line split across fragments is never emitted half-decoded.
    """

    def __init__(self) -> None:
        self._buffer = bytearray()
        self._line_unix: int | None = None
        self.fragments = 0

    def feed(self, inner: bytes) -> list[ConsoleLine]:
        if len(inner) <= CONSOLE_TEXT_OFFSET or inner[0] != PacketType.CONSOLE_LOGS:
            return []
        unix = struct.unpack_from("<I", inner, 4)[0] if len(inner) >= 8 else None
        text = bytes(inner[CONSOLE_TEXT_OFFSET:]).removesuffix(b"\x00")
        self.fragments += 1

        if not self._buffer:
            self._line_unix = unix
        self._buffer.extend(text)

        lines: list[ConsoleLine] = []
        while True:
            index = self._buffer.find(b"\n")
            if index < 0:
                break
            raw = bytes(self._buffer[: index])
            del self._buffer[: index + 1]
            decoded = raw.decode("utf-8", "replace").strip()
            if decoded:
                lines.append(ConsoleLine(unix=self._line_unix, text=decoded))
            self._line_unix = unix
        return lines

    def flush(self) -> list[ConsoleLine]:
        if not self._buffer:
            return []
        decoded = bytes(self._buffer).decode("utf-8", "replace").strip()
        self._buffer.clear()
        return [ConsoleLine(unix=self._line_unix, text=decoded)] if decoded else []

    @property
    def pending(self) -> int:
        return len(self._buffer)


def parse_wear_detect(text: str) -> WearDetectEvent | None:
    if "SIGPROC-WEAR-DETECT" not in text:
        return None
    match = _WEAR_RE.search(text)
    if match is None:
        return None
    fields = {key: float(value) for key, value in _KV_RE.findall(text[match.end():])}
    return WearDetectEvent(
        from_state=int(match.group(1)),
        to_state=int(match.group(2)),
        debug=int(match.group(3)),
        state_cnt=int(match.group(4)),
        fields=fields,
    )


def parse_body_transition(text: str) -> tuple[str, str] | None:
    match = _BODY_RE.search(text)
    return (match.group(1), match.group(2)) if match else None
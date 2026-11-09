"""WHOOP gen5 (5.0 / MG) historical record decoders.

Clean-room implementation from documented byte offsets. v18 is the per-second
biometric summary and the only gen5 record that becomes a 1 Hz sample.

Shared header, inner-relative:
  [0] packet type 0x2F   [1] hist_version   [2] flags
  [3:7] record_index u32 (monotonic, NOT unix)   [7:11] unix u32
  [11:13] sub-second u16, Q15 fraction (value / 32768)

flags bit 7 set => optical front end at 25 Hz, clear => 50 Hz.
"""

import struct
from dataclasses import dataclass, field

V18 = 18
V18_INNER_LEN = 112
V18_MIN_READABLE = 109

# Physiological plausibility window for R-R intervals in milliseconds.
MIN_RR_MS = 200
MAX_RR_MS = 3000

# HR outside this window is treated as absent, not as a reading.
MIN_HR = 25
MAX_HR = 230

FULL_SCALE_G = 16.0


def _f32(inner: bytes, offset: int) -> float | None:
    if offset + 4 > len(inner):
        return None
    value = struct.unpack_from("<f", inner, offset)[0]
    return value if value == value and abs(value) != float("inf") else None


def _i16(inner: bytes, offset: int) -> int | None:
    if offset + 2 > len(inner):
        return None
    return struct.unpack_from("<h", inner, offset)[0]


def _u16(inner: bytes, offset: int) -> int | None:
    if offset + 2 > len(inner):
        return None
    return struct.unpack_from("<H", inner, offset)[0]


def _u32(inner: bytes, offset: int) -> int | None:
    if offset + 4 > len(inner):
        return None
    return struct.unpack_from("<I", inner, offset)[0]


@dataclass
class RecordHeader:
    version: int
    flags: int
    record_index: int
    unix: int
    subsec_q15: int

    @property
    def ppg_sample_rate_hz(self) -> int:
        return 25 if self.flags & 0x80 else 50

    @property
    def timestamp(self) -> float:
        return self.unix + self.subsec_q15 / 32768.0


def parse_header(inner: bytes) -> RecordHeader | None:
    if len(inner) < 13 or inner[0] != 0x2F:
        return None
    return RecordHeader(
        version=inner[1],
        flags=inner[2],
        record_index=_u32(inner, 3) or 0,
        unix=_u32(inner, 7) or 0,
        subsec_q15=_u16(inner, 11) or 0,
    )


@dataclass
class V18Sample:
    header: RecordHeader
    heart_rate: int  # 0 means absent / off-skin, not bradycardia
    rr_intervals_ms: list[int] = field(default_factory=list)
    dynamic_accel_g: float | None = None
    gravity_g: tuple[float, float, float] | None = None
    step_motion_counter: int | None = None
    step_cadence: int | None = None
    activity_class: int | None = None
    skin_temp_c: float | None = None
    temp_aux1_c: float | None = None
    temp_aux2_c: float | None = None
    sleep_state_byte: int | None = None
    cardiac_flags: int | None = None
    hr_quality_flags: int | None = None
    spo2_candidate_raw: int | None = None

    @property
    def unix(self) -> int:
        return self.header.unix

    @property
    def wearing(self) -> bool:
        return self.heart_rate > 0


def decode_v18(inner: bytes) -> V18Sample | None:
    """Decode a v18 per-second biometric summary.

    An implausible individual field is dropped, never the whole record: one
    artefact bpm must not discard that second's R-R beats, temperature and
    motion. Absence is reported as None/0 rather than fabricated.
    """
    if len(inner) < V18_MIN_READABLE or inner[1] != V18:
        return None
    header = parse_header(inner)
    if header is None:
        return None

    hr_raw = inner[14]
    hr = hr_raw if MIN_HR <= hr_raw <= MAX_HR else 0

    rr: list[int] = []
    declared = inner[15]
    if declared <= 4:
        for i in range(declared):
            value = _i16(inner, 16 + 2 * i)
            if value is not None and MIN_RR_MS <= value <= MAX_RR_MS:
                rr.append(value)

    dyn = _f32(inner, 33)
    if dyn is not None and not (0 <= dyn <= FULL_SCALE_G):
        dyn = None

    axes = (_f32(inner, 37), _f32(inner, 41), _f32(inner, 45))
    gravity = None
    if all(a is not None and abs(a) <= FULL_SCALE_G for a in axes):
        gravity = (round(axes[0], 4), round(axes[1], 4), round(axes[2], 4))

    def temp(offset: int, scale: float) -> float | None:
        raw = _i16(inner, offset)
        return round(raw / scale, 2) if raw is not None else None

    return V18Sample(
        header=header,
        heart_rate=hr,
        rr_intervals_ms=rr,
        dynamic_accel_g=round(dyn, 4) if dyn is not None else None,
        gravity_g=gravity,
        step_motion_counter=_u16(inner, 49),
        step_cadence=inner[51] if len(inner) > 51 else None,
        activity_class=inner[55] if len(inner) > 55 else None,
        temp_aux1_c=temp(61, 10.0),
        temp_aux2_c=temp(63, 10.0),
        skin_temp_c=temp(65, 100.0),
        sleep_state_byte=inner[73] if len(inner) > 73 else None,
        cardiac_flags=inner[25] if len(inner) > 25 else None,
        hr_quality_flags=inner[28] if len(inner) > 28 else None,
        spo2_candidate_raw=inner[74] if len(inner) > 74 else None,
    )


def decode_record(inner: bytes) -> V18Sample | None:
    """Dispatch on hist_version. Only v18 is implemented so far."""
    if len(inner) < 2 or inner[0] != 0x2F:
        return None
    if inner[1] == V18:
        return decode_v18(inner)
    return None

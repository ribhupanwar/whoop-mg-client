"""WHOOP gen5 (5.0 / MG) historical record decoders.

Clean-room implementation from documented byte offsets. v18 is the per-second
biometric summary and the only gen5 record that becomes a 1 Hz sample. v26 is a
25 Hz optical waveform, decoded separately because it is not a per-second summary.
v18's last data byte is a tri-mode SpO2 candidate; it is decoded but never
treated as a validated percentage.

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

V26 = 26
V26_INNER_LEN = 76
V26_SAMPLE_COUNT = 25
V26_DELTA_COUNT = V26_SAMPLE_COUNT - 1
V26_ANCHOR_OFFSET = 15
V26_DELTA_OFFSET = 19
V26_ACCEL_OFFSET = 67
V26_CHANNEL_STATE_OFFSET = 71
V26_MORPHOLOGY_OFFSET = 74

# A delta at either int16 rail means the true step overflowed the field.
DELTA_RAILS = (-32768, 32767)

ANCHOR_BITS = 20

# Physiological plausibility window for R-R intervals in milliseconds.
MIN_RR_MS = 200
MAX_RR_MS = 3000

# HR outside this window is treated as absent, not as a reading.
MIN_HR = 25
MAX_HR = 230

# v18 inner[74] (frame byte 82) is a tri-mode SpO2 candidate, not a reading.
SPO2_CANDIDATE_MIN = 70
SPO2_CANDIDATE_MAX = 100
SPO2_SATURATED_BIT = 0x80

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
    # Bits 4-5 of sleep_state_byte. The enum is NOT established: do not attach
    # stage names to these values until an overnight capture pins them down.
    sleep_state: int | None = None
    cardiac_flags: int | None = None
    hr_quality_flags: int | None = None
    spo2_candidate_raw: int | None = None
    # 70-100 = the band's own candidate percentage. Candidate only: cross-device
    # validation is split, so it never becomes a scored metric.
    spo2_candidate_pct: int | None = None
    # "absent" / "pct" / "saturated" / "diagnostic"; see decode_spo2_candidate.
    spo2_candidate_status: str | None = None
    # The band's own log-variance quality weight; lower is cleaner. Unlike the
    # accelerometer fields it has no physical bound, so only NaN/inf are dropped.
    signal_quality_log_variance: float | None = None

    @property
    def unix(self) -> int:
        return self.header.unix

    @property
    def wearing(self) -> bool:
        return self.heart_rate > 0


def decode_spo2_candidate(raw: int | None) -> tuple[int | None, str | None]:
    """Classify the v18 SpO2 candidate byte (inner[74] / frame 82).

    The byte is tri-mode: 70-100 is the band's own candidate percentage, bit 7
    marks a saturation sentinel, any other nonzero value is a diagnostic code,
    and zero means absent. It is only populated while the band records sleep.

    This is a CANDIDATE, not a validated measurement. A public multi-night
    validation with real spread exists, but two other capture nights moved
    opposite to the vendor app, so the evidence is split. Never present the
    value as a clinical SpO2 or feed it into a score.
    """
    if raw is None or raw == 0:
        return None, "absent"
    if SPO2_CANDIDATE_MIN <= raw <= SPO2_CANDIDATE_MAX:
        return raw, "pct"
    if raw & SPO2_SATURATED_BIT:
        return None, "saturated"
    return None, "diagnostic"


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

    quality = _f32(inner, 105)
    sleep_byte = inner[73] if len(inner) > 73 else None
    spo2_raw = inner[74] if len(inner) > 74 else None
    spo2_pct, spo2_status = decode_spo2_candidate(spo2_raw)

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
        sleep_state_byte=sleep_byte,
        sleep_state=(sleep_byte >> 4) & 0x03 if sleep_byte is not None else None,
        cardiac_flags=inner[25] if len(inner) > 25 else None,
        hr_quality_flags=inner[28] if len(inner) > 28 else None,
        spo2_candidate_raw=spo2_raw,
        spo2_candidate_pct=spo2_pct,
        spo2_candidate_status=spo2_status,
        signal_quality_log_variance=round(quality, 4) if quality is not None else None,
    )


def decode_record(inner: bytes) -> V18Sample | None:
    """Decode the per-second sample stream. Only v18 qualifies.

    v26 is deliberately not returned here: it is a 25-sample optical waveform,
    not a one-second summary, and mixing it into a 1 Hz series would corrupt
    every downstream metric. Use decode_v26 for it.
    """
    if len(inner) < 2 or inner[0] != 0x2F:
        return None
    if inner[1] == V18:
        return decode_v18(inner)
    return None


@dataclass
class V26Waveform:
    header: RecordHeader
    samples: list[int]
    saturated: bool
    dynamic_accel_g: float | None
    channel_state: int
    morphology_pass: int

    @property
    def unix(self) -> int:
        return self.header.unix

    @property
    def sample_rate_hz(self) -> int:
        return self.header.ppg_sample_rate_hz

    @property
    def duration_s(self) -> float:
        return len(self.samples) / self.sample_rate_hz


def decode_v26(inner: bytes) -> V26Waveform | None:
    """Reconstruct the absolute optical waveform from a delta-coded v26 record.

    The record carries one 20-bit absolute anchor followed by 24 int16 deltas,
    giving 25 samples. At the 25 Hz the header flag selects, that is exactly one
    second per record. The cumulative sum is load-bearing: on a real capture the
    raw delta block is 3.6x rougher than the reconstructed signal, and only the
    reconstruction reproduces the 49 beats v18 reported for the same window.

    A delta sitting on an int16 rail means the true step overflowed, so every
    sample after it is wrong. Those are dropped rather than returned as
    plausible-looking data, and `saturated` says the record is partial.
    """
    if len(inner) != V26_INNER_LEN or inner[1] != V26:
        return None
    header = parse_header(inner)
    if header is None:
        return None

    anchor = struct.unpack_from("<i", inner, V26_ANCHOR_OFFSET)[0]
    if anchor >= 1 << (ANCHOR_BITS - 1):
        anchor -= 1 << ANCHOR_BITS

    samples = [anchor]
    saturated = False
    for i in range(V26_DELTA_COUNT):
        delta = struct.unpack_from("<h", inner, V26_DELTA_OFFSET + 2 * i)[0]
        if delta in DELTA_RAILS:
            saturated = True
            break
        samples.append(samples[-1] + delta)

    accel = _f32(inner, V26_ACCEL_OFFSET)
    if accel is not None and not (0 <= accel <= FULL_SCALE_G):
        accel = None

    return V26Waveform(
        header=header,
        samples=samples,
        saturated=saturated,
        dynamic_accel_g=accel,
        channel_state=struct.unpack_from("<H", inner, V26_CHANNEL_STATE_OFFSET)[0],
        morphology_pass=inner[V26_MORPHOLOGY_OFFSET],
    )
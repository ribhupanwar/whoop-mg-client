"""Decode a captured WHOOP gen5 session into per-second samples and metrics.

Reads the JSONL written by session.py, decodes v18 historical records, and
reports heart rate, HRV from R-R intervals, skin temperature and motion.
Writes a CSV for further analysis. No band required.
"""

import argparse
import csv
import json
import math
import statistics
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from whoop.console import ConsoleStream, parse_body_transition, parse_wear_detect
from whoop.records import (
    IMUBuffer,
    V26Waveform,
    decode_record,
    decode_v21,
    decode_v26,
)


def load_console(path: Path) -> list:
    """Reassemble the firmware log in arrival order, never sorted by seq."""
    stream = ConsoleStream()
    lines = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            frame = json.loads(line).get("frame")
            if not frame or frame.get("packet_type") != 0x32:
                continue
            lines.extend(stream.feed(bytes.fromhex(frame["inner"])))
    lines.extend(stream.flush())
    return lines


def report_console(lines: list) -> None:
    if not lines:
        return
    print(f"\n=== Firmware log ({len(lines)} lines) ===")
    modules = Counter(line.module for line in lines if line.module)
    print("  top modules: " + ", ".join(f"{m}={n}" for m, n in modules.most_common(6)))

    transitions = [(l.unix, parse_body_transition(l.text)) for l in lines]
    transitions = [(u, t) for u, t in transitions if t]
    if transitions:
        print("\n  Wear-state transitions (the band's own on-body decision):")
        for unix, (before, after) in transitions:
            stamp = (
                datetime.fromtimestamp(unix, timezone.utc).strftime("%H:%M:%S")
                if unix else "?"
            )
            print(f"    {stamp}  {before} -> {after}")
        if any(after == "off-body" for _, (_, after) in transitions):
            print("    Strap went OFF-BODY during this window. HR and R-R are not")
            print("    produced off-body, so those seconds show HR=0.")
    else:
        print("  no wear-state transition logged in this window")

    events = [(l.unix, parse_wear_detect(l.text)) for l in lines]
    events = [(u, e) for u, e in events if e]
    if events:
        print(f"\n  Wear-detect snapshots: {len(events)}")
        for unix, event in events:
            stamp = (
                datetime.fromtimestamp(unix, timezone.utc).strftime("%H:%M:%S")
                if unix else "?"
            )
            temp = f"{event.skin_temp_c:.2f} C" if event.skin_temp_c is not None else "n/a"
            hrc = f"{event.hrc:.0f}" if event.hrc is not None else "n/a"
            print(
                f"    {stamp}  state {event.from_state}->{event.to_state}"
                f"  skin_temp={temp}  hrc={hrc}"
                f"  hr_pk={event.fields.get('lm_hr_pk_m', 0.0):.1f}"
            )


def load_samples(path: Path) -> list:
    samples = []
    undecoded = Counter()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            frame = row.get("frame")
            if not frame or frame.get("packet_type") != 0x2F:
                continue
            inner = bytes.fromhex(frame["inner"])
            sample = decode_record(inner)
            if sample is None:
                undecoded[inner[1] if len(inner) > 1 else -1] += 1
                continue
            samples.append(sample)
    samples.sort(key=lambda s: (s.unix, s.header.record_index))
    if undecoded:
        print(f"  historical versions outside the 1 Hz stream: {dict(undecoded)}")
    return samples


def load_waveforms(path: Path) -> list[V26Waveform]:
    """v26 optical waveforms, kept separate from the 1 Hz sample stream."""
    waves = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            frame = json.loads(line).get("frame")
            if not frame or frame.get("packet_type") != 0x2F:
                continue
            wave = decode_v26(bytes.fromhex(frame["inner"]))
            if wave is not None:
                waves.append(wave)
    waves.sort(key=lambda w: (w.unix, w.header.record_index))
    return waves


def report_waveforms(waves: list[V26Waveform], samples: list) -> None:
    if not waves:
        return
    total_s = sum(w.duration_s for w in waves)
    saturated = sum(1 for w in waves if w.saturated)
    print(f"\n=== Optical waveform (v26) ===")
    print(f"  records: {len(waves)}  rate: {waves[0].sample_rate_hz} Hz  covered: {total_s:.1f} s")
    print(f"  samples decoded: {sum(len(w.samples) for w in waves)}")
    if saturated:
        print(f"  saturated (tail dropped): {saturated}/{len(waves)}")

    # The accel float in the v26 tail must equal the same second's v18 value.
    # Agreement is what pins the tail layout; a mismatch means the offsets slid.
    by_unix = {s.unix: s for s in samples}
    diffs = [
        abs(w.dynamic_accel_g - by_unix[w.unix].dynamic_accel_g)
        for w in waves
        if w.dynamic_accel_g is not None
        and w.unix in by_unix
        and by_unix[w.unix].dynamic_accel_g is not None
    ]
    if diffs:
        print(f"  accel cross-check vs v18: {len(diffs)} seconds, max diff {max(diffs):.2e} g")
    amplitudes = [max(w.samples) - min(w.samples) for w in waves if len(w.samples) > 1]
    if amplitudes:
        print(f"  peak-to-peak ADC counts: median {statistics.median(amplitudes):.0f}"
              f"  range {min(amplitudes)}-{max(amplitudes)}")
    print("  25 Hz means one sample is 40 ms, far coarser than v18's 1 ms R-R slots.")
    print("  Use v18 R-R for resting HRV; the waveform's value is beat detection")
    print("  during motion, when v18 emits no R-R at all.")


def load_imu(path: Path) -> list[IMUBuffer]:
    """v21 IMU buffers, kept separate from the 1 Hz sample stream."""
    buffers = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            frame = json.loads(line).get("frame")
            if not frame or frame.get("packet_type") not in (0x2B, 0x2F):
                continue
            buffer = decode_v21(bytes.fromhex(frame["inner"]))
            if buffer is not None:
                buffers.append(buffer)
    buffers.sort(key=lambda b: (b.unix, b.header.record_index))
    return buffers


def report_imu(buffers: list[IMUBuffer]) -> None:
    if not buffers:
        return
    accel = [sample for b in buffers for sample in b.accel_g]
    covered_s = sum(b.duration_s for b in buffers)
    print("\n=== IMU buffer (v21, 100 Hz) ===")
    print(f"  records: {len(buffers)}  covered: {covered_s:.2f} s"
          f"  accel samples: {len(accel)}")
    counts = sorted({(b.accel_count, b.gyro_count) for b in buffers})
    print(f"  declared (accel, gyro) counts: {counts}")
    magnitudes = [math.sqrt(sum(v * v for v in sample)) for sample in accel]
    if magnitudes:
        print(f"  median |accel|: {statistics.median(magnitudes):.2f} g"
              "  (a still wrist sits near 1 g)")
    print("  Axis layout is cross-project reverse engineering, not yet confirmed on")
    print("  this device: read the numbers above as diagnostics, not as a metric.")


def rmssd(rr: list[float]) -> float | None:
    if len(rr) < 2:
        return None
    diffs = [b - a for a, b in zip(rr, rr[1:])]
    return math.sqrt(sum(d * d for d in diffs) / len(diffs))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", nargs="?", default="session3.jsonl")
    parser.add_argument("--csv", default="samples.csv")
    args = parser.parse_args()

    path = Path(args.capture)
    if not path.exists():
        print(f"Capture not found: {path}")
        return 1

    print(f"Decoding {path} ...")
    console_lines = load_console(path)
    samples = load_samples(path)
    if not samples:
        print("No decodable v18 records found.")
        report_console(console_lines)
        return 1

    first = datetime.fromtimestamp(samples[0].unix, timezone.utc)
    last = datetime.fromtimestamp(samples[-1].unix, timezone.utc)
    wearing = [s for s in samples if s.wearing]
    hrs = [s.heart_rate for s in wearing]
    all_rr = [rr for s in samples for rr in s.rr_intervals_ms]
    temps = [s.skin_temp_c for s in samples if s.skin_temp_c is not None]

    print(f"\n=== Decoded {len(samples)} per-second samples ===")
    print(f"  window (UTC): {first.isoformat()}  ->  {last.isoformat()}")
    print(f"  span: {(last - first).total_seconds():.0f}s")
    print(f"  on-wrist samples (HR present): {len(wearing)}")
    print(f"  PPG rate: {samples[0].header.ppg_sample_rate_hz} Hz")

    if hrs:
        print(f"\n=== Heart rate ===")
        print(f"  min={min(hrs)}  max={max(hrs)}  mean={statistics.mean(hrs):.1f} bpm")
        print(f"  median={statistics.median(hrs):.0f} bpm")

    print(f"\n=== R-R intervals / HRV ===")
    print(f"  total R-R beats: {len(all_rr)}")
    records_with_rr = sum(1 for s in samples if s.rr_intervals_ms)
    print(f"  records carrying R-R: {records_with_rr}/{len(samples)}")
    if all_rr:
        print(f"  range: {min(all_rr)} - {max(all_rr)} ms")
        print(f"  mean R-R: {statistics.mean(all_rr):.1f} ms")
        value = rmssd([float(r) for r in all_rr])
        if value is not None:
            print(f"  RMSSD: {value:.2f} ms")
        if len(all_rr) > 2:
            print(f"  SDNN:  {statistics.stdev(all_rr):.2f} ms")
    else:
        print("  No R-R intervals in this capture.")
        print("  v18 declares R-R count at inner[15]; every record here reports 0.")
        on_wrist_motion = [s.dynamic_accel_g for s in wearing if s.dynamic_accel_g is not None]
        moving = [s for s in wearing if s.step_cadence]
        if on_wrist_motion:
            print(
                f"  On-wrist seconds: {len(wearing)}, of which {len(moving)} report non-zero cadence."
            )
            print(f"  On-wrist dynamic accel: mean={statistics.mean(on_wrist_motion):.2f} g")
        print("  R-R is populated at rest; a high-motion window yields none.")
        print("  Capture a still or sleeping window to get HRV.")

    if temps:
        print(f"\n=== Skin temperature ===")
        print(f"  min={min(temps):.2f}  max={max(temps):.2f}  mean={statistics.mean(temps):.2f} C")

    motion = [s.dynamic_accel_g for s in samples if s.dynamic_accel_g is not None]
    if motion:
        print(f"\n=== Motion ===")
        print(f"  dynamic accel: mean={statistics.mean(motion):.3f} g  max={max(motion):.3f} g")
    steps = [s.step_motion_counter for s in samples if s.step_motion_counter is not None]
    if steps:
        print(f"  step counter: {min(steps)} -> {max(steps)} (delta {max(steps)-min(steps)})")

    sleep_states = Counter(s.sleep_state for s in samples if s.sleep_state is not None)
    if sleep_states:
        print(f"\n=== Band-reported sleep state (raw bits 4-5 of inner[73]) ===")
        for state, count in sorted(sleep_states.items()):
            group = [s for s in samples if s.sleep_state == state]
            hr = [s.heart_rate for s in group if s.wearing]
            accel = [s.dynamic_accel_g for s in group if s.dynamic_accel_g is not None]
            detail = []
            if hr:
                detail.append(f"mean HR {statistics.mean(hr):.1f} bpm")
            if accel:
                detail.append(f"mean accel {statistics.mean(accel):.3f} g")
            suffix = "  " + ", ".join(detail) if detail else ""
            print(f"  state {state}: {count} samples{suffix}")
        print("  Enum NOT labelled. Pin it down against an overnight capture before naming stages.")

    quality = [
        s.signal_quality_log_variance for s in samples
        if s.signal_quality_log_variance is not None
    ]
    if quality:
        print(f"\n=== HR signal quality (band log variance, lower = cleaner) ===")
        print(f"  populated: {len(quality)}/{len(samples)} seconds")
        on_wrist_q = [
            s.signal_quality_log_variance for s in wearing
            if s.signal_quality_log_variance is not None
        ]
        if on_wrist_q:
            print(f"  on-wrist: min={min(on_wrist_q):.3f}  max={max(on_wrist_q):.3f}"
                  f"  mean={statistics.mean(on_wrist_q):.3f}")
        off_body = [s for s in samples if not s.wearing]
        if off_body:
            off_zero = sum(1 for s in off_body if s.signal_quality_log_variance == 0.0)
            print(f"  off-body seconds reporting exactly 0.0: {off_zero}/{len(off_body)}")
        print("  Reported only. Not yet used to weight RMSSD.")

    report_waveforms(load_waveforms(path), samples)
    report_imu(load_imu(path))
    report_console(console_lines)

    out = Path(args.csv)
    with out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["unix", "utc", "record_index", "hr_bpm", "rr_count", "rr_ms",
             "skin_temp_c", "dynamic_accel_g", "gx", "gy", "gz",
             "step_counter", "cadence", "activity_class",
             "sleep_state_byte", "sleep_state", "signal_quality_log_variance"]
        )
        for s in samples:
            g = s.gravity_g or (None, None, None)
            writer.writerow(
                [s.unix, datetime.fromtimestamp(s.unix, timezone.utc).isoformat(),
                 s.header.record_index, s.heart_rate, len(s.rr_intervals_ms),
                 "|".join(str(r) for r in s.rr_intervals_ms), s.skin_temp_c,
                 s.dynamic_accel_g, g[0], g[1], g[2], s.step_motion_counter,
                 s.step_cadence, s.activity_class, s.sleep_state_byte,
                 s.sleep_state, s.signal_quality_log_variance]
            )
    print(f"\n  CSV written -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
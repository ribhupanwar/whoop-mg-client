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

from whoop.records import decode_record


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
        print(f"  undecoded historical versions: {dict(undecoded)}")
    return samples


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
    samples = load_samples(path)
    if not samples:
        print("No decodable v18 records found.")
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
        print("  v18 declares R-R count at inner[15]; these records report 0.")
        print("  R-R is typically populated during rest/sleep, not motion.")

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

    sleep_states = Counter(s.sleep_state_byte for s in samples if s.sleep_state_byte is not None)
    if sleep_states:
        print(f"\n=== Band sleep/wake state (envelope, not sleep stage) ===")
        for state, count in sorted(sleep_states.items()):
            print(f"  state {state}: {count} samples")

    out = Path(args.csv)
    with out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["unix", "utc", "record_index", "hr_bpm", "rr_count", "rr_ms",
             "skin_temp_c", "dynamic_accel_g", "gx", "gy", "gz",
             "step_counter", "cadence", "activity_class", "sleep_state"]
        )
        for s in samples:
            g = s.gravity_g or (None, None, None)
            writer.writerow(
                [s.unix, datetime.fromtimestamp(s.unix, timezone.utc).isoformat(),
                 s.header.record_index, s.heart_rate, len(s.rr_intervals_ms),
                 "|".join(str(r) for r in s.rr_intervals_ms), s.skin_temp_c,
                 s.dynamic_accel_g, g[0], g[1], g[2], s.step_motion_counter,
                 s.step_cadence, s.activity_class, s.sleep_state_byte]
            )
    print(f"\n  CSV written -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

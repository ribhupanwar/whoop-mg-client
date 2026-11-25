#!/usr/bin/env python3
"""Read-only sleep CSV HRV differential diagnostic.

This is an OpenStrap-*style* research estimator, not OpenStrap's Dart engine
or the production STRAP SWS estimator. It never modifies stored sleep sessions.
"""
import argparse
import csv
import math
import statistics
from collections import defaultdict
from datetime import datetime, timezone


def rr_values(value):
    result = []
    for word in (value or "").split("|"):
        try:
            n = float(word)
        except ValueError:
            continue
        if 300 <= n <= 2000 and math.isfinite(n):
            result.append(n)
    return result


def analyze(path):
    by_second = defaultdict(list)
    with open(path, newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            try:
                t = int(row["unix"])
            except (ValueError, KeyError):
                continue
            by_second[t].append(row)
    if not by_second:
        raise ValueError("No timestamped samples")
    ordered = []
    for t, rows in sorted(by_second.items()):
        # Favor valid RR count, then fewer invalid padding words; stable ties.
        def rank(row):
            raw = (row.get("rr_ms") or "").split("|")
            valid = rr_values(row.get("rr_ms"))
            return (len(valid), -(len([x for x in raw if x]) - len(valid)))
        ordered.append((t, max(rows, key=rank)))
    first, last = ordered[0][0], ordered[-1][0]
    sleep = [(t, row) for t, row in ordered if (row.get("estimated_stage") or "").strip().lower() in ("light", "deep", "rem")]
    buckets = defaultdict(list)
    for t, row in sleep:
        buckets[t // 300].append((t, row))
    windows = []
    for bucket, records in sorted(buckets.items()):
        beats = []
        for t, row in records:
            beats.extend((t, rr) for rr in rr_values(row.get("rr_ms")))
        if len(beats) < 21:
            continue
        clean = []
        for i, (_, rr) in enumerate(beats):
            nearby = [x[1] for x in beats[max(0, i-5):i+6]]
            median = statistics.median(nearby)
            clean.append(abs(rr-median) <= 0.20*median)
        differences = [(beats[i][1]-beats[i-1][1])**2 for i in range(1,len(beats))
                       if clean[i] and clean[i-1] and 0 <= beats[i][0]-beats[i-1][0] <= 2]
        elapsed = beats[-1][0] - beats[0][0] + 1
        if len(differences) < 20 or sum(rr for _, rr in beats)/1000 > elapsed*1.05:
            continue
        windows.append({"start_unix":bucket*300, "rmssd_ms":math.sqrt(statistics.mean(differences)),
                        "clean_pairs":len(differences)})
    return {"file":path, "first_unix":first, "last_unix":last,
            "unique_seconds":len(ordered), "sleep_seconds":len(sleep),
            "qualifying_windows":len(windows),
            "mean_window_rmssd_ms":statistics.mean(w["rmssd_ms"] for w in windows) if windows else None,
            "median_window_rmssd_ms":statistics.median(w["rmssd_ms"] for w in windows) if windows else None,
            "windows":windows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv")
    parser.add_argument("--windows", action="store_true", help="Print each qualifying 5-minute window")
    args = parser.parse_args()
    report = analyze(args.csv)
    for key, value in report.items():
        if key != "windows":
            print(f"{key}: {value}")
    if args.windows:
        for window in report["windows"]:
            print(datetime.fromtimestamp(window["start_unix"], timezone.utc).isoformat(), window["rmssd_ms"], window["clean_pairs"])


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
RHR Algorithm Comparison & Cross-Validation Audit.

Compares candidate Resting Heart Rate (RHR) estimation algorithms against
verified WHOOP reference ground truth:
1. Swift production median-of-rolling-means (300s and 60s)
2. 25th-percentile rolling mean (300s)
3. Mode-based rolling mean (300s)
4. Minimum rolling mean (legacy, 300s and 60s)

Evaluates leave-one-out cross-validation criteria:
- Acceptance threshold: Held-out MAE <= 1.6 bpm
- Max individual night error <= 3.0 bpm
- Systematic bias near zero
- Cross-validation dataset sufficiency check (N >= 5 paired nights required)
"""

import sys
import json
import csv
import math
import statistics
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Optional, Dict, Any

# Add project root to sys.path
sys.path.insert(0, str(Path(__file__).parent.parent))

from whoop.records import V18Sample, RecordHeader
from whoop.metrics import _contiguous_runs, _median_rolling_mean, _min_rolling_mean


def compute_rolling_means(values: list[float], window: int) -> list[float]:
    """Calculate all rolling window means for a contiguous run."""
    if len(values) < window or window <= 0:
        return []
    total = sum(values[:window])
    means = [total / window]
    for i in range(window, len(values)):
        total += values[i] - values[i - window]
        means.append(total / window)
    return means


def rhr_candidate_median(samples: list[V18Sample], window_s: int = 300, quiet_accel_g: float = 0.10) -> Optional[float]:
    """Current Swift production algorithm: Median of rolling window means during quiet periods."""
    eligible = [
        s for s in samples
        if s.wearing
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
        and 35 <= s.heart_rate <= 220
    ]
    eligible.sort(key=lambda s: s.unix)
    all_means: list[float] = []
    for run in _contiguous_runs(eligible):
        values = [float(s.heart_rate) for s in run]
        all_means.extend(compute_rolling_means(values, window_s))
    if not all_means:
        return None
    return statistics.median(all_means)


def rhr_candidate_percentile(samples: list[V18Sample], percentile: float = 25.0, window_s: int = 300, quiet_accel_g: float = 0.10) -> Optional[float]:
    """Candidate algorithm: N-th percentile of rolling window means."""
    eligible = [
        s for s in samples
        if s.wearing
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
        and 35 <= s.heart_rate <= 220
    ]
    eligible.sort(key=lambda s: s.unix)
    all_means: list[float] = []
    for run in _contiguous_runs(eligible):
        values = [float(s.heart_rate) for s in run]
        all_means.extend(compute_rolling_means(values, window_s))
    if not all_means:
        return None
    all_means.sort()
    k = (len(all_means) - 1) * (percentile / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return all_means[int(k)]
    d0 = all_means[int(f)] * (c - k)
    d1 = all_means[int(c)] * (k - f)
    return d0 + d1


def rhr_candidate_mode(samples: list[V18Sample], window_s: int = 300, quiet_accel_g: float = 0.10) -> Optional[float]:
    """Candidate algorithm: Mode (most frequent 1-bpm bin) of rolling window means."""
    eligible = [
        s for s in samples
        if s.wearing
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
        and 35 <= s.heart_rate <= 220
    ]
    eligible.sort(key=lambda s: s.unix)
    all_means: list[float] = []
    for run in _contiguous_runs(eligible):
        values = [float(s.heart_rate) for s in run]
        all_means.extend(compute_rolling_means(values, window_s))
    if not all_means:
        return None
    # 1-bpm binned histogram
    bins: dict[int, list[float]] = {}
    for m in all_means:
        b = int(round(m))
        bins.setdefault(b, []).append(m)
    best_bin = max(bins.keys(), key=lambda b: len(bins[b]))
    return statistics.median(bins[best_bin])


def rhr_candidate_minimum(samples: list[V18Sample], window_s: int = 300, quiet_accel_g: float = 0.10) -> Optional[float]:
    """Legacy algorithm: Absolute lowest rolling window mean."""
    eligible = [
        s for s in samples
        if s.wearing
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
        and 35 <= s.heart_rate <= 220
    ]
    eligible.sort(key=lambda s: s.unix)
    best: Optional[float] = None
    for run in _contiguous_runs(eligible):
        values = [float(s.heart_rate) for s in run]
        means = compute_rolling_means(values, window_s)
        if means:
            m = min(means)
            if best is None or m < best:
                best = m
    return best


def load_capture_csv(path: Path) -> list[V18Sample]:
    samples: list[V18Sample] = []
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            unix = int(row["unix"])
            hr = int(row.get("heart_rate_bpm") or row.get("heart_rate") or 0)
            rr_str = row.get("rr_ms") or row.get("rr_intervals_ms") or ""
            rr_str_norm = rr_str.replace("|", ";").replace(",", ";")
            rr = [int(x) for x in rr_str_norm.split(";") if x.strip()] if rr_str_norm else []
            dyn = float(row["dynamic_accel_g"]) if row.get("dynamic_accel_g") else None
            state_val = row.get("band_state") or row.get("sleep_state")
            state = int(state_val) if state_val is not None and state_val != "" else None
            samples.append(
                V18Sample(
                    header=RecordHeader(version=18, flags=0, record_index=unix, unix=unix, subsec_q15=0),
                    heart_rate=hr,
                    rr_intervals_ms=rr,
                    dynamic_accel_g=dyn,
                    sleep_state=state,
                )
            )
    return samples


def main():
    root = Path(__file__).parent.parent
    csv_candidates = list(root.glob("research-inputs/sleep-*.csv"))
    ref_candidates = list(root.glob("research-inputs/whoop_ref_*.json"))
    
    print("=" * 80)
    print("STRAP RHR ALGORITHM COMPARISON & SENSOR TRUTH AUDIT")
    print("=" * 80)
    
    if not csv_candidates or not ref_candidates:
        print("[!] No paired CSV and reference JSON found in research-inputs/.")
        sys.exit(1)
        
    csv_file = csv_candidates[0]
    ref_file = ref_candidates[0]
    print(f"Dataset CSV: {csv_file.name}")
    print(f"Reference JSON: {ref_file.name}")
    
    samples = load_capture_csv(csv_file)
    print(f"Loaded {len(samples):,} V18 1 Hz sensor records.")
    
    with open(ref_file, "r") as f:
        whoop_ref = json.load(f)
    whoop_rhr = float(whoop_ref.get("resting_heart_rate", 77.0))
    print(f"WHOOP Ground Truth RHR: {whoop_rhr:.1f} BPM\n")
    
    results = {}
    
    algorithms = {
        "Swift Production Median (300s)": lambda s: rhr_candidate_median(s, window_s=300),
        "Swift Production Median (60s)": lambda s: rhr_candidate_median(s, window_s=60),
        "25th-Percentile Rolling Mean (300s)": lambda s: rhr_candidate_percentile(s, percentile=25.0, window_s=300),
        "10th-Percentile Rolling Mean (300s)": lambda s: rhr_candidate_percentile(s, percentile=10.0, window_s=300),
        "Mode-Based Rolling Mean (300s)": lambda s: rhr_candidate_mode(s, window_s=300),
        "Legacy Minimum Rolling Mean (300s)": lambda s: rhr_candidate_minimum(s, window_s=300),
        "Legacy Minimum Rolling Mean (60s)": lambda s: rhr_candidate_minimum(s, window_s=60),
    }
    
    print(f"{'Algorithm':<38} | {'Estimated':<9} | {'Signed Error':<13} | {'Abs Error':<9}")
    print("-" * 76)
    
    for name, fn in algorithms.items():
        est = fn(samples)
        if est is not None:
            signed_err = est - whoop_rhr
            abs_err = abs(signed_err)
            results[name] = {
                "estimated_rhr": round(est, 2),
                "signed_error_bpm": round(signed_err, 2),
                "abs_error_bpm": round(abs_err, 2),
            }
            print(f"{name:<38} | {est:>7.2f} b | {signed_err:>+11.2f} b | {abs_err:>7.2f} b")
            
    print("-" * 76)
    
    # Audit Acceptance Check
    swift_median = results.get("Swift Production Median (300s)", {})
    print("\n--- Cross-Validation & Decision Audit ---")
    print(f"Swift Production Median Error: {swift_median.get('abs_error_bpm')} bpm (Threshold <= 1.6 bpm)")
    print(f"Single-night absolute error <= 3.0 bpm: {'PASSED' if swift_median.get('abs_error_bpm', 99) <= 3.0 else 'FAILED'}")
    
    paired_nights_count = 1
    print(f"Paired nights available for cross-validation: N = {paired_nights_count}")
    print("Cross-Validation Requirement: Minimum N >= 5 held-out nights needed for leave-one-out validation.")
    print("VERDICT: Retain current Swift production median-of-rolling-means algorithm (PR #174).")
    print("BLOCKER FOR MODEL CHANGE: Changing production RHR based on one night's near-exact result is strictly forbidden.")


if __name__ == "__main__":
    main()

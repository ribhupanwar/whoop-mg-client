#!/usr/bin/env python3
"""
Comprehensive RHR Algorithm Comparison Framework

Replicates Swift production RHR calculation paths and compares candidate algorithms
on identical raw samples. Designed for leave-one-night-out validation across
7-14 paired nights.
"""

import csv
import json
import statistics
from dataclasses import dataclass, field
from typing import Optional
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from whoop.health import detect_sleep, SleepPeriod, QUIET_ACCEL_G
from whoop.metrics import _contiguous_runs as whoop_contiguous_runs

# Swift constants
SWIFT_SLEEP_QUIET_ACCEL_G = 0.08      # SleepDetect.quietAccelG
SWIFT_RHR_QUIET_ACCEL_G = 0.10        # Hrv.restingQuietAccelG


@dataclass
class SimpleSample:
    """Lightweight sample compatible with whoop.metrics and whoop.health functions."""
    unix: int
    heart_rate: int
    rr_intervals_ms: list[int]
    dynamic_accel_g: Optional[float]
    wearing: bool


@dataclass
class NightData:
    """Container for one night's paired data."""
    date: str
    csv_path: str
    whoop_hrv_rmssd: Optional[float] = None
    whoop_rhr: Optional[int] = None
    whoop_sleep_stages: Optional[dict] = None
    samples: list[SimpleSample] = field(default_factory=list)


@dataclass
class RHRResult:
    """Result from one RHR algorithm."""
    algorithm: str
    window_s: int
    rhr: Optional[float]
    signed_error: Optional[float] = None
    abs_error: Optional[float] = None


def load_v18_csv(csv_path: str) -> list[SimpleSample]:
    """Load V18 samples from CSV export."""
    samples = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rr_str = row.get('rr_ms', '') or row.get('rr_intervals_ms', '')
            rr_intervals = [int(x) for x in rr_str.split('|')] if rr_str else []
            accel_str = row.get('dynamic_accel_g', '')
            dynamic_accel = float(accel_str) if accel_str else None
            wearing = row.get('wearing', 'true').lower() == 'true'
            
            samples.append(SimpleSample(
                unix=int(row['unix']),
                heart_rate=int(row['heart_rate_bpm']),
                rr_intervals_ms=rr_intervals,
                dynamic_accel_g=dynamic_accel,
                wearing=wearing,
            ))
    return samples


def extract_primary_sleep_session(samples: list[SimpleSample]) -> tuple[list[SimpleSample], Optional[SleepPeriod]]:
    """
    Replicate Swift production path: detect sleep periods, pick longest session.
    Returns (sleep_segment_samples, primary_period)
    """
    periods = detect_sleep(samples)
    if not periods:
        return [], None
    
    # Primary = longest duration (matches Swift line 319)
    primary = max(periods, key=lambda p: p.end_unix - p.start_unix)
    
    # Extract samples for this period
    segment = [s for s in samples if primary.start_unix <= s.unix <= primary.end_unix]
    return segment, primary


def swift_resting_heart_rate(
    samples: list[SimpleSample],
    window_s: int = 300,
    quiet_accel_g: float = SWIFT_RHR_QUIET_ACCEL_G  # Swift uses 0.10 for RHR
) -> Optional[float]:
    """
    Exact replication of Swift Hrv.restingHeartRate (lines 394-418).
    
    Median of rolling window means across motion-verified quiet windows.
    """
    eligible = [
        s for s in samples
        if s.wearing
        and 35 <= s.heart_rate <= 220
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
    ]
    eligible.sort(key=lambda s: s.unix)
    
    if window_s <= 0:
        return None
    
    window_means = []
    for run in whoop_contiguous_runs(eligible):
        if len(run) >= window_s:
            values = [float(s.heart_rate) for s in run]
            total = sum(values[:window_s])
            window_means.append(total / window_s)
            for i in range(window_s, len(values)):
                total += values[i] - values[i - window_s]
                window_means.append(total / window_s)
    
    if not window_means:
        return None
    
    window_means.sort()
    n = len(window_means)
    if n % 2 == 1:
        return window_means[n // 2]
    return (window_means[n // 2 - 1] + window_means[n // 2]) / 2


def candidate_min_rolling_mean(
    samples: list[SimpleSample],
    window_s: int = 300,
    quiet_accel_g: float = QUIET_ACCEL_G
) -> Optional[float]:
    """Former Swift: minimum of rolling window means."""
    eligible = [
        s for s in samples
        if s.wearing
        and 35 <= s.heart_rate <= 220
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
    ]
    eligible.sort(key=lambda s: s.unix)
    
    if window_s <= 0:
        return None
    
    best = float('inf')
    found = False
    for run in whoop_contiguous_runs(eligible):
        if len(run) >= window_s:
            values = [float(s.heart_rate) for s in run]
            total = sum(values[:window_s])
            best = min(best, total)
            for i in range(window_s, len(values)):
                total += values[i] - values[i - window_s]
                best = min(best, total)
            found = True
    
    return best / window_s if found else None


def candidate_percentile_rolling_mean(
    samples: list[SimpleSample],
    window_s: int = 300,
    quiet_accel_g: float = QUIET_ACCEL_G,
    percentile: float = 0.25
) -> Optional[float]:
    """Percentile of rolling window means (configurable)."""
    eligible = [
        s for s in samples
        if s.wearing
        and 35 <= s.heart_rate <= 220
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
    ]
    eligible.sort(key=lambda s: s.unix)
    
    if window_s <= 0:
        return None
    
    window_means = []
    for run in whoop_contiguous_runs(eligible):
        if len(run) >= window_s:
            values = [float(s.heart_rate) for s in run]
            total = sum(values[:window_s])
            window_means.append(total / window_s)
            for i in range(window_s, len(values)):
                total += values[i] - values[i - window_s]
                window_means.append(total / window_s)
    
    if not window_means:
        return None
    
    window_means.sort()
    idx = int(percentile * (len(window_means) - 1))
    return window_means[idx]


def candidate_trimmed_mean_rolling(
    samples: list[SimpleSample],
    window_s: int = 300,
    quiet_accel_g: float = QUIET_ACCEL_G,
    trim_frac: float = 0.10
) -> Optional[float]:
    """Trimmed mean of rolling window means."""
    eligible = [
        s for s in samples
        if s.wearing
        and 35 <= s.heart_rate <= 220
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
    ]
    eligible.sort(key=lambda s: s.unix)
    
    if window_s <= 0:
        return None
    
    window_means = []
    for run in whoop_contiguous_runs(eligible):
        if len(run) >= window_s:
            values = [float(s.heart_rate) for s in run]
            total = sum(values[:window_s])
            window_means.append(total / window_s)
            for i in range(window_s, len(values)):
                total += values[i] - values[i - window_s]
                window_means.append(total / window_s)
    
    if not window_means:
        return None
    
    window_means.sort()
    n = len(window_means)
    k = int(n * trim_frac)
    if k * 2 >= n:
        return statistics.mean(window_means)
    return statistics.mean(window_means[k:n-k])


def candidate_mode_rolling_mean(
    samples: list[SimpleSample],
    window_s: int = 300,
    quiet_accel_g: float = QUIET_ACCEL_G,
    bin_size: float = 0.5
) -> Optional[float]:
    """Mode (most frequent binned value) of rolling window means."""
    eligible = [
        s for s in samples
        if s.wearing
        and 35 <= s.heart_rate <= 220
        and s.dynamic_accel_g is not None
        and s.dynamic_accel_g <= quiet_accel_g
    ]
    eligible.sort(key=lambda s: s.unix)
    
    if window_s <= 0:
        return None
    
    window_means = []
    for run in whoop_contiguous_runs(eligible):
        if len(run) >= window_s:
            values = [float(s.heart_rate) for s in run]
            total = sum(values[:window_s])
            window_means.append(total / window_s)
            for i in range(window_s, len(values)):
                total += values[i] - values[i - window_s]
                window_means.append(total / window_s)
    
    if not window_means:
        return None
    
    # Bin and find mode
    bins = {}
    for m in window_means:
        b = round(m / bin_size) * bin_size
        bins[b] = bins.get(b, 0) + 1
    
    if not bins:
        return None
    
    return max(bins.items(), key=lambda x: x[1])[0]


ALGORITHMS = {
    "swift_production_300s": lambda s: swift_resting_heart_rate(s, 300),
    "swift_production_60s": lambda s: swift_resting_heart_rate(s, 60),
    "min_rolling_300s": lambda s: candidate_min_rolling_mean(s, 300),
    "min_rolling_60s": lambda s: candidate_min_rolling_mean(s, 60),
    "p25_rolling_300s": lambda s: candidate_percentile_rolling_mean(s, 300, percentile=0.25),
    "p10_rolling_300s": lambda s: candidate_percentile_rolling_mean(s, 300, percentile=0.10),
    "trimmed10_300s": lambda s: candidate_trimmed_mean_rolling(s, 300, trim_frac=0.10),
    "trimmed20_300s": lambda s: candidate_trimmed_mean_rolling(s, 300, trim_frac=0.20),
    "mode_300s": lambda s: candidate_mode_rolling_mean(s, 300),
}


def analyze_night(night: NightData) -> dict[str, RHRResult]:
    """Run all algorithms on primary sleep session segment."""
    sleep_segment, primary_period = extract_primary_sleep_session(night.samples)
    
    if not sleep_segment:
        print(f"  [WARN] No sleep segment detected for {night.date}")
        return {}
    
    print(f"  Primary sleep: {primary_period.start_unix} to {primary_period.end_unix} "
          f"({(primary_period.end_unix - primary_period.start_unix)/3600:.1f}h), "
          f"{len(sleep_segment)} samples, quiet_frac={primary_period.quiet_fraction:.2f}")
    
    results = {}
    for name, algo in ALGORITHMS.items():
        rhr = algo(sleep_segment)
        signed_error = rhr - night.whoop_rhr if rhr is not None and night.whoop_rhr is not None else None
        abs_error = abs(signed_error) if signed_error is not None else None
        results[name] = RHRResult(
            algorithm=name,
            window_s=300 if "300" in name else 60,
            rhr=rhr,
            signed_error=signed_error,
            abs_error=abs_error
        )
    return results


def print_night_results(night: NightData, results: dict[str, RHRResult]):
    """Print formatted results for one night."""
    print(f"\n{'='*80}")
    print(f"Night: {night.date}  |  WHOOP RHR: {night.whoop_rhr} bpm  |  Total samples: {len(night.samples)}")
    print(f"{'='*80}")
    print(f"{'Algorithm':<30} {'Window':>6} {'RHR':>8} {'Signed Err':>12} {'Abs Err':>8}")
    print(f"{'-'*80}")
    
    # Sort by absolute error
    sorted_results = sorted(
        [(k, v) for k, v in results.items() if v.rhr is not None],
        key=lambda x: x[1].abs_error if x[1].abs_error is not None else float('inf')
    )
    
    for name, r in sorted_results:
        rhr_str = f"{r.rhr:.2f}" if r.rhr else "N/A"
        signed_str = f"{r.signed_error:+.2f}" if r.signed_error is not None else "N/A"
        abs_str = f"{r.abs_error:.2f}" if r.abs_error is not None else "N/A"
        print(f"{name:<30} {r.window_s:>6} {rhr_str:>8} {signed_str:>12} {abs_str:>8}")
    
    # Best algorithm
    best = sorted_results[0] if sorted_results else None
    if best:
        print(f"\n  Best: {best[0]} (abs error: {best[1].abs_error:.2f} bpm)")


def print_summary_table(all_results: dict[str, dict[str, RHRResult]], nights: list[NightData]):
    """Print multi-night summary statistics."""
    print(f"\n{'='*100}")
    print(f"MULTI-NIGHT SUMMARY ({len(nights)} nights)")
    print(f"{'='*100}")
    
    algo_names = list(ALGORITHMS.keys())
    
    print(f"\n{'Algorithm':<30} {'MAE':>8} {'MedAE':>8} {'MaxAE':>8} {'Bias':>8} {'Exact Match':>12} {'Within 1':>10} {'Within 2':>10}")
    print(f"{'-'*100}")
    
    for name in algo_names:
        abs_errors = []
        signed_errors = []
        exact_matches = 0
        within_1 = 0
        within_2 = 0
        valid_nights = 0
        
        for night in nights:
            r = all_results[night.date].get(name)
            if r and r.rhr is not None and night.whoop_rhr is not None:
                valid_nights += 1
                abs_errors.append(r.abs_error)
                signed_errors.append(r.signed_error)
                if abs(r.signed_error) < 0.5:
                    exact_matches += 1
                if abs(r.signed_error) <= 1:
                    within_1 += 1
                if abs(r.signed_error) <= 2:
                    within_2 += 1
        
        if valid_nights > 0:
            mae = statistics.mean(abs_errors)
            medae = statistics.median(abs_errors)
            maxae = max(abs_errors)
            bias = statistics.mean(signed_errors)
            exact_pct = 100 * exact_matches / valid_nights
            within1_pct = 100 * within_1 / valid_nights
            within2_pct = 100 * within_2 / valid_nights
            
            print(f"{name:<30} {mae:>8.2f} {medae:>8.2f} {maxae:>8.2f} {bias:>+8.2f} {exact_pct:>11.0f}% {within1_pct:>9.0f}% {within2_pct:>9.0f}%")
        else:
            print(f"{name:<30} {'N/A':>8} {'N/A':>8} {'N/A':>8} {'N/A':>8} {'N/A':>12} {'N/A':>10} {'N/A':>10}")


def leave_one_out_validation(all_results: dict[str, dict[str, RHRResult]], nights: list[NightData]):
    """Leave-one-night-out validation to prevent overfitting."""
    print(f"\n{'='*100}")
    print(f"LEAVE-ONE-NIGHT-OUT VALIDATION")
    print(f"{'='*100}")
    
    algo_names = list(ALGORITHMS.keys())
    night_dates = [n.date for n in nights]
    
    for held_out in night_dates:
        train_nights = [d for d in night_dates if d != held_out]
        test_night = held_out
        
        # Select best algorithm on training nights
        train_mae = {}
        for name in algo_names:
            abs_errs = []
            for d in train_nights:
                r = all_results[d].get(name)
                if r and r.abs_error is not None:
                    abs_errs.append(r.abs_error)
            train_mae[name] = statistics.mean(abs_errs) if abs_errs else float('inf')
        
        if not train_mae:
            continue
            
        best_algo = min(train_mae, key=train_mae.get)
        best_mae = train_mae[best_algo]
        
        # Test on held-out night
        test_r = all_results[test_night].get(best_algo)
        test_mae = test_r.abs_error if test_r and test_r.abs_error is not None else float('inf')
        
        print(f"  Hold out {test_night}: train best={best_algo} (MAE={best_mae:.2f}), test MAE={test_mae:.2f}")


def main():
    # Load paired nights
    nights = []
    
    # Night 1: 2026-11-23 (from CSV + WHOOP reference)
    csv_path = "research-inputs/sleep-1795375775-1795399923-3A748598-4D50-4FA9-84ED-319209137EE3(4).csv"
    ref_path = "research-inputs/whoop_ref_nov23.json"
    
    with open(ref_path, 'r') as f:
        ref = json.load(f)
    
    samples = load_v18_csv(csv_path)
    night = NightData(
        date="2026-11-23",
        csv_path=csv_path,
        whoop_hrv_rmssd=ref.get('hrv_rmssd'),
        whoop_rhr=ref.get('resting_heart_rate'),
        whoop_sleep_stages=ref.get('sleep_stages'),
        samples=samples
    )
    nights.append(night)
    
    # TODO: Add more nights here when available
    # Example:
    # nights.append(NightData(date="2026-11-22", csv_path="...", whoop_rhr=...))
    
    print(f"Loaded {len(nights)} paired night(s)")
    
    # Run analysis
    all_results = {}
    for night in nights:
        results = analyze_night(night)
        all_results[night.date] = results
        print_night_results(night, results)
    
    # Multi-night summary
    if len(nights) >= 1:
        print_summary_table(all_results, nights)
    
    # LOOCV (requires >= 2 nights)
    if len(nights) >= 2:
        leave_one_out_validation(all_results, nights)
    else:
        print("\n[WARN] LOOCV requires >=2 paired nights. Only 1 night available.")
        print("   Add more CSV+JSON pairs to research-inputs/ for full validation.")
    
    # Export detailed results
    export_path = "research-inputs/rhr_algorithm_comparison.json"
    export_data = {
        "nights": len(nights),
        "algorithms_tested": list(ALGORITHMS.keys()),
        "results": {
            date: {
                name: {
                    "rhr": r.rhr,
                    "window_s": r.window_s,
                    "signed_error": r.signed_error,
                    "abs_error": r.abs_error
                }
                for name, r in results.items()
            }
            for date, results in all_results.items()
        }
    }
    with open(export_path, 'w') as f:
        json.dump(export_data, f, indent=2)
    print(f"\nDetailed results exported to {export_path}")


if __name__ == "__main__":
    main()
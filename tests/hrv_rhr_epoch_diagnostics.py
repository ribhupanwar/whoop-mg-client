#!/usr/bin/env python3
"""
Per-epoch HRV/RHR diagnostic analysis for WHOOP comparison.

This script implements the bounded engineering experiment from
docs/research/hrv-rhr-window-evidence-2026-11-16.md:

1. Build per-epoch 300-second HRV diagnostics (epoch start/end, sample coverage,
   accepted/rejected RR, RMSSD, mean HR, motion, stage evidence)
2. Compare existing nightly weighted estimator with:
   (a) last qualified deep-sleep 5-minute epoch
   (b) weighted late-night/SWS epochs
3. Compare to WHOOP reference values for multiple paired nights, report MAE and coverage
4. Keep independent RHR comparison (lowest sustained vs stable 5-minute median)

Usage:
    python tests/hrv_rhr_epoch_diagnostics.py <path_to_v18_csv> [--whoop-reference <json>]

The CSV must contain V18 samples with: unix, heart_rate, rr_intervals_ms,
dynamic_accel_g, sleep_state, wearing
"""

import sys
import json
import csv
import math
import statistics
from dataclasses import dataclass, asdict
from typing import List, Optional, Tuple, Dict, Any
from pathlib import Path

# Add whoop module to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from whoop.records import V18Sample, RecordHeader, decode_spo2_candidate
from whoop.metrics import (
    nn_intervals, rmssd, sdnn, pnn50, hrv_from_rr,
    resting_hrv, sws_resting_hrv, resting_heart_rate,
    _contiguous_runs, _min_rolling_mean,
    NN_MAX_DEVIATION, NN_REFERENCE_BEATS,
    MIN_RR_MS, MAX_RR_MS
)
from whoop.health import (
    detect_sleep, SleepPeriod, total_sleep_hours,
    Baseline, recovery_score, RecoveryResult,
    QUIET_ACCEL_G, MIN_SLEEP_S, MAX_SLEEP_WINDOW_S,
    SLEEP_GAP_TOLERANCE_S, HR_DROP_BPM
)

EPOCH_SECONDS = 300  # 5-minute epochs


@dataclass
class EpochDiagnostic:
    """Per-epoch HRV diagnostic data."""
    epoch_index: int
    start_unix: int
    end_unix: int
    duration_seconds: int
    sample_count: int
    wearing_count: int
    rr_beats_total: int
    rr_beats_valid: int
    rr_beats_accepted: int
    rr_beats_rejected: int
    mean_hr: Optional[float]
    rmssd_ms: Optional[float]
    ln_rmssd: Optional[float]
    sdnn_ms: Optional[float]
    pnn50_pct: Optional[float]
    mean_rr_ms: Optional[float]
    motion_fraction: Optional[float]
    max_dynamic_accel: Optional[float]
    sleep_stage: Optional[str]  # "wake", "light", "deep", "rem", or None
    band_state: Optional[int]   # 0, 1, 2, 3 or None
    is_quiet: bool
    coverage_pct: float


@dataclass
class NightlyComparison:
    """Comparison of different HRV/RHR estimators for one night."""
    night_start: int
    night_end: int
    # Production estimator (current STRAP: primary sleep SWS HRV with fallback)
    production_hrv_rmssd: Optional[float]
    production_hrv_window_s: int
    production_hrv_is_sws: bool
    production_rhr: Optional[float]
    # Swift production RHR (median of rolling 300s windows - matches dashboard)
    swift_production_rhr: Optional[float]
    # Estimator A: Last qualified deep-sleep 5-minute epoch
    estimator_a_hrv_rmssd: Optional[float]
    estimator_a_hrv_window_s: int
    estimator_a_rhr: Optional[float]
    # Estimator B: Weighted late-night/SWS epochs
    estimator_b_hrv_rmssd: Optional[float]
    estimator_b_hrv_window_s: int
    estimator_b_rhr: Optional[float]
    # WHOOP reference (if provided)
    whoop_hrv_rmssd: Optional[float] = None
    whoop_rhr: Optional[float] = None
    whoop_sleep_stages: Optional[Dict[str, float]] = None


def load_v18_csv(csv_path: str) -> List[V18Sample]:
    """Load V18 samples from CSV export."""
    samples = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Parse RR intervals (semicolon-separated in rr_ms column)
            rr_str = row.get('rr_ms', '') or row.get('rr_intervals_ms', '') or row.get('rr', '')
            rr_intervals = []
            if rr_str:
                try:
                    rr_intervals = [int(x) for x in rr_str.split(';') if x.strip()]
                except ValueError:
                    rr_intervals = []
            
            # Parse dynamic accel
            accel = None
            if row.get('dynamic_accel_g'):
                try:
                    accel = float(row['dynamic_accel_g'])
                except ValueError:
                    pass
            
            # Parse sleep state / band state
            sleep_state = None
            if row.get('band_state'):
                try:
                    sleep_state = int(row['band_state'])
                except ValueError:
                    pass
            elif row.get('sleep_state'):
                try:
                    sleep_state = int(row['sleep_state'])
                except ValueError:
                    pass
            
            # Parse wearing
            wearing = True
            if row.get('wearing') is not None:
                wearing = row['wearing'].lower() in ('true', '1', 'yes')
            
            # Parse SpO2
            spo2_raw = None
            if row.get('spo2_candidate_raw'):
                try:
                    spo2_raw = int(row['spo2_candidate_raw'])
                except ValueError:
                    pass
            
            spo2_pct, spo2_status = decode_spo2_candidate(spo2_raw)
            
            # Parse heart rate
            hr = 0
            if row.get('heart_rate_bpm'):
                try:
                    hr = int(row['heart_rate_bpm'])
                except ValueError:
                    pass
            elif row.get('heart_rate'):
                try:
                    hr = int(row['heart_rate'])
                except ValueError:
                    pass
            
            sample = V18Sample(
                header=RecordHeader(
                    version=18, flags=0x80,
                    record_index=int(row.get('record_index', 0)),
                    unix=int(row['unix']),
                    subsec_q15=0
                ),
                heart_rate=hr,
                rr_intervals_ms=rr_intervals,
                dynamic_accel_g=accel,
                gravity_g=None,
                step_motion_counter=None,
                step_cadence=None,
                activity_class=0,
                skin_temp_c=None,
                temp_aux1_c=None,
                temp_aux2_c=None,
                sleep_state_byte=sleep_state << 4 if sleep_state is not None else None,
                sleep_state=sleep_state,
                cardiac_flags=None,
                hr_quality_flags=None,
                spo2_candidate_raw=spo2_raw,
                spo2_candidate_pct=spo2_pct,
                spo2_candidate_status=spo2_status,
                signal_quality_log_variance=None
            )
            samples.append(sample)
    return samples


def build_epoch_diagnostics(samples: List[V18Sample], sleep_periods: List[SleepPeriod]) -> List[EpochDiagnostic]:
    """Build per-epoch 300-second HRV diagnostics across sleep periods."""
    diagnostics = []
    
    # Sort samples by timestamp
    ordered = sorted(samples, key=lambda s: s.unix)
    if not ordered:
        return diagnostics
    
    # Determine overall time range covering all sleep periods
    all_start = min(p.start_unix for p in sleep_periods)
    all_end = max(p.end_unix for p in sleep_periods) + 1  # inclusive
    
    # Align to 300-second grid
    grid_start = all_start - (all_start % EPOCH_SECONDS)
    
    # Build sleep stage lookup from SleepStager if available
    # For now, use band state as proxy
    sleep_state_map = {}
    for s in ordered:
        if s.sleep_state is not None:
            sleep_state_map[s.unix] = s.sleep_state
    
    epoch_index = 0
    current = grid_start
    while current < all_end:
        epoch_start = max(all_start, current)
        epoch_end = min(all_end, current + EPOCH_SECONDS)
        
        # Collect samples in this epoch
        epoch_samples = [s for s in ordered if epoch_start <= s.unix < epoch_end]
        
        if epoch_samples:
            # Filter wearing samples with valid HR
            wearing = [s for s in epoch_samples if s.wearing and 35 <= s.heart_rate <= 220]
            wearing_count = len(wearing)
            sample_count = len(epoch_samples)
            
            # RR analysis
            all_rr = []
            for s in wearing:
                all_rr.extend(s.rr_intervals_ms)
            rr_beats_total = len(all_rr)
            
            # Valid RR (in range)
            valid_rr = [r for r in all_rr if MIN_RR_MS <= r <= MAX_RR_MS]
            rr_beats_valid = len(valid_rr)
            
            # NN filtering
            nn = nn_intervals([float(r) for r in valid_rr])
            rr_beats_accepted = len(nn)
            rr_beats_rejected = rr_beats_valid - rr_beats_accepted
            
            # HRV metrics
            hrv_result = hrv_from_rr([float(r) for r in nn]) if nn else None
            
            # Mean HR
            mean_hr = statistics.mean([s.heart_rate for s in wearing]) if wearing else None
            
            # Motion
            motion_samples = [s for s in epoch_samples if s.dynamic_accel_g is not None]
            motion_fraction = None
            max_dynamic_accel = None
            if motion_samples:
                motion_fraction = sum(1 for s in motion_samples if s.dynamic_accel_g >= 0.12) / len(motion_samples)
                max_dynamic_accel = max(s.dynamic_accel_g for s in motion_samples)
            
            # Sleep stage from band state
            band_states = [s.sleep_state for s in epoch_samples if s.sleep_state is not None]
            band_state = max(set(band_states), key=band_states.count) if band_states else None
            
            # Map band state to stage label
            stage_map = {0: "wake", 1: "light", 2: "deep", 3: "wake"}
            sleep_stage = stage_map.get(band_state) if band_state is not None else None
            
            # Quiet check
            is_quiet = motion_fraction is not None and motion_fraction < 0.25
            
            # Coverage
            coverage_pct = (wearing_count / (epoch_end - epoch_start)) * 100 if epoch_end > epoch_start else 0
            
            diag = EpochDiagnostic(
                epoch_index=epoch_index,
                start_unix=epoch_start,
                end_unix=epoch_end - 1,
                duration_seconds=epoch_end - epoch_start,
                sample_count=sample_count,
                wearing_count=wearing_count,
                rr_beats_total=rr_beats_total,
                rr_beats_valid=rr_beats_valid,
                rr_beats_accepted=rr_beats_accepted,
                rr_beats_rejected=rr_beats_rejected,
                mean_hr=mean_hr,
                rmssd_ms=hrv_result.rmssd_ms if hrv_result else None,
                ln_rmssd=hrv_result.ln_rmssd if hrv_result else None,
                sdnn_ms=hrv_result.sdnn_ms if hrv_result else None,
                pnn50_pct=hrv_result.pnn50_pct if hrv_result else None,
                mean_rr_ms=hrv_result.mean_rr_ms if hrv_result else None,
                motion_fraction=motion_fraction,
                max_dynamic_accel=max_dynamic_accel,
                sleep_stage=sleep_stage,
                band_state=band_state,
                is_quiet=is_quiet,
                coverage_pct=coverage_pct
            )
            diagnostics.append(diag)
        
        current += EPOCH_SECONDS
        epoch_index += 1
    
    return diagnostics


def estimator_last_deep_epoch(diagnostics: List[EpochDiagnostic]) -> Tuple[Optional[float], int]:
    """Estimator A: Last qualified deep-sleep 5-minute epoch RMSSD."""
    # Find deep sleep epochs (band_state == 2 or stage == "deep")
    deep_epochs = [d for d in diagnostics if d.band_state == 2 or d.sleep_stage == "deep"]
    qualified = [d for d in deep_epochs if d.rmssd_ms is not None and d.rr_beats_accepted >= 20 and d.duration_seconds >= 300]
    
    if qualified:
        last = qualified[-1]
        return last.rmssd_ms, last.duration_seconds
    return None, 0


def estimator_weighted_late_night_sws(diagnostics: List[EpochDiagnostic]) -> Tuple[Optional[float], int]:
    """Estimator B: Weighted late-night/SWS epochs."""
    # Weight by recency (later epochs get higher weight) and SWS evidence
    sws_epochs = [d for d in diagnostics if d.band_state == 2 or d.sleep_stage == "deep"]
    qualified = [d for d in sws_epochs if d.rmssd_ms is not None and d.rr_beats_accepted >= 20 and d.duration_seconds >= 300]
    
    if not qualified:
        return None, 0
    
    # Weight by recency (normalized position in night) and HRV quality
    total_weight = 0.0
    weighted_sum = 0.0
    total_window = 0
    
    n = len(qualified)
    for i, epoch in enumerate(qualified):
        # Recency weight: later epochs get higher weight
        recency = (i + 1) / n
        # Quality weight: more beats = more reliable
        quality = min(1.0, epoch.rr_beats_accepted / 100.0)
        weight = recency * quality
        
        weighted_sum += epoch.rmssd_ms * weight
        total_weight += weight
        total_window += epoch.duration_seconds
    
    if total_weight > 0:
        return weighted_sum / total_weight, total_window
    return None, 0


def estimator_lowest_sustained_rhr(samples: List[V18Sample], window_s: int = 300) -> Optional[float]:
    """RHR Estimator: Lowest sustained heart rate across quiet windows (current STRAP)."""
    return resting_heart_rate(samples, window_s=window_s, quiet_accel_g=QUIET_ACCEL_G)


def estimator_median_rolling_rhr(samples: List[V18Sample], window_s: int = 300) -> Optional[float]:
    """RHR Estimator: Median of rolling 5-minute windows across quiet periods (Swift production)."""
    eligible = [
        s for s in samples
        if s.wearing and 35 <= s.heart_rate <= 220
        and s.dynamic_accel_g is not None and s.dynamic_accel_g <= QUIET_ACCEL_G
    ]
    eligible.sort(key=lambda s: s.unix)
    
    window_means = []
    for run in _contiguous_runs(eligible):
        if len(run) >= window_s:
            values = [float(s.heart_rate) for s in run]
            for i in range(len(values) - window_s + 1):
                window_means.append(statistics.mean(values[i:i+window_s]))
    
    if window_means:
        return statistics.median(window_means)
    return None


def estimator_swift_production_rhr(samples: List[V18Sample], window_s: int = 300) -> Optional[float]:
    """RHR Estimator: Swift production median-of-rolling-means (matches dashboard)."""
    # This mirrors ios/Strap/Analysis/Hrv.swift restingHeartRate()
    return estimator_median_rolling_rhr(samples, window_s)


def run_comparison(samples: List[V18Sample], whoop_ref: Optional[Dict] = None) -> List[NightlyComparison]:
    """Run the full comparison for all detected sleep periods."""
    # Detect sleep periods
    periods = detect_sleep(
        samples,
        quiet_accel_g=QUIET_ACCEL_G,
        min_sleep_s=MIN_SLEEP_S,
        gap_tolerance_s=SLEEP_GAP_TOLERANCE_S,
        hr_drop_bpm=HR_DROP_BPM
    )
    
    comparisons = []
    
    for period in periods:
        # Get samples for this sleep period
        night_samples = [s for s in samples if period.start_unix <= s.unix <= period.end_unix]
        
        # Build epoch diagnostics
        diagnostics = build_epoch_diagnostics(night_samples, [period])
        
        # Production estimator (current STRAP: SWS HRV with fallback)
        deep_epochs = [(d.start_unix, d.end_unix) for d in diagnostics if d.band_state == 2 or d.sleep_stage == "deep"]
        sws_result = sws_resting_hrv(night_samples, deep_epochs=deep_epochs, min_window_s=300)
        production_hrv = sws_result[0].rmssd_ms if sws_result[0].rmssd_ms else None
        production_window = sws_result[1]
        production_is_sws = sws_result[2]
        production_rhr = resting_heart_rate(night_samples, window_s=300)
        swift_production_rhr = estimator_swift_production_rhr(night_samples, window_s=300)
        
        # Estimator A: Last qualified deep-sleep epoch
        est_a_hrv, est_a_window = estimator_last_deep_epoch(diagnostics)
        est_a_rhr = estimator_lowest_sustained_rhr(night_samples)
        
        # Estimator B: Weighted late-night/SWS
        est_b_hrv, est_b_window = estimator_weighted_late_night_sws(diagnostics)
        est_b_rhr = estimator_median_rolling_rhr(night_samples)
        
        # WHOOP reference
        whoop_hrv = whoop_ref.get('hrv_rmssd') if whoop_ref else None
        whoop_rhr = whoop_ref.get('resting_heart_rate') if whoop_ref else None
        whoop_stages = whoop_ref.get('sleep_stages') if whoop_ref else None
        
        comp = NightlyComparison(
            night_start=period.start_unix,
            night_end=period.end_unix,
            production_hrv_rmssd=production_hrv,
            production_hrv_window_s=production_window,
            production_hrv_is_sws=production_is_sws,
            production_rhr=production_rhr,
            swift_production_rhr=swift_production_rhr,
            estimator_a_hrv_rmssd=est_a_hrv,
            estimator_a_hrv_window_s=est_a_window,
            estimator_a_rhr=est_a_rhr,
            estimator_b_hrv_rmssd=est_b_hrv,
            estimator_b_hrv_window_s=est_b_window,
            estimator_b_rhr=est_b_rhr,
            whoop_hrv_rmssd=whoop_hrv,
            whoop_rhr=whoop_rhr,
            whoop_sleep_stages=whoop_stages
        )
        comparisons.append(comp)
    
    return comparisons


def print_comparison_table(comparisons: List[NightlyComparison]):
    """Print formatted comparison table."""
    print("\n" + "=" * 140)
    print("HRV/RHR ESTIMATOR COMPARISON")
    print("=" * 140)
    
    for i, c in enumerate(comparisons):
        print(f"\nNight {i+1}: {c.night_start} to {c.night_end} ({(c.night_end - c.night_start)/3600:.1f}h)")
        print("-" * 140)
        
        # HRV comparison
        print(f"{'Estimator':<35} {'RMSSD (ms)':<12} {'Window (s)':<12} {'SWS':<6} {'MAE vs WHOOP':<15}")
        print("-" * 80)
        
        estimators = [
            ("Production (SWS + fallback)", c.production_hrv_rmssd, c.production_hrv_window_s, c.production_hrv_is_sws),
            ("Estimator A: Last Deep Epoch", c.estimator_a_hrv_rmssd, c.estimator_a_hrv_window_s, None),
            ("Estimator B: Weighted Late SWS", c.estimator_b_hrv_rmssd, c.estimator_b_hrv_window_s, None),
        ]
        
        for name, hrv, window, is_sws in estimators:
            mae = ""
            if c.whoop_hrv_rmssd is not None and hrv is not None:
                mae = f"{abs(hrv - c.whoop_hrv_rmssd):.1f}"
            sws_str = "Yes" if is_sws else ("No" if is_sws is not None else "")
            print(f"{name:<35} {hrv if hrv else 'N/A':<12} {window:<12} {sws_str:<6} {mae:<15}")
        
        if c.whoop_hrv_rmssd is not None:
            print(f"{'WHOOP Reference':<35} {c.whoop_hrv_rmssd:<12}")
        
        print()
        
        # RHR comparison
        print(f"{'RHR Estimator':<40} {'RHR (bpm)':<12} {'MAE vs WHOOP':<15}")
        print("-" * 70)
        
        rhr_estimators = [
            ("Python Production: Lowest Sustained (300s)", c.production_rhr),
            ("Swift Production: Median Rolling (300s)", c.swift_production_rhr),
            ("Estimator A: Lowest Sustained", c.estimator_a_rhr),
            ("Estimator B: Median Rolling (300s)", c.estimator_b_rhr),
        ]
        
        for name, rhr in rhr_estimators:
            mae = ""
            if c.whoop_rhr is not None and rhr is not None:
                mae = f"{abs(rhr - c.whoop_rhr):.1f}"
            print(f"{name:<40} {rhr if rhr else 'N/A':<12} {mae:<15}")
        
        if c.whoop_rhr is not None:
            print(f"{'WHOOP Reference':<40} {c.whoop_rhr:<12}")


def print_epoch_diagnostics(diagnostics: List[EpochDiagnostic], max_epochs: int = 20):
    """Print per-epoch diagnostics table."""
    print("\n" + "=" * 160)
    print(f"PER-EPOCH HRV DIAGNOSTICS (showing first {min(max_epochs, len(diagnostics))} of {len(diagnostics)} epochs)")
    print("=" * 160)
    print(f"{'Idx':<4} {'Start':<12} {'Dur':<4} {'Wear':<5} {'RR_T':<5} {'RR_V':<5} {'RR_A':<5} {'RR_R':<5} "
          f"{'HR':<6} {'RMSSD':<7} {'lnRMSSD':<8} {'SDNN':<7} {'pNN50':<6} {'Mot%':<6} {'MaxAcc':<7} "
          f"{'Stage':<6} {'Band':<4} {'Quiet':<5} {'Cov%':<5}")
    print("-" * 160)
    
    for d in diagnostics[:max_epochs]:
        stage = d.sleep_stage or "-"
        band = str(d.band_state) if d.band_state is not None else "-"
        print(f"{d.epoch_index:<4} {d.start_unix:<12} {d.duration_seconds:<4} "
              f"{d.wearing_count:<5} {d.rr_beats_total:<5} {d.rr_beats_valid:<5} {d.rr_beats_accepted:<5} {d.rr_beats_rejected:<5} "
              f"{(d.mean_hr or 0):<6.1f} {(d.rmssd_ms or 0):<7.1f} {(d.ln_rmssd or 0):<8.3f} "
              f"{(d.sdnn_ms or 0):<7.1f} {(d.pnn50_pct or 0):<6.1f} "
              f"{(d.motion_fraction or 0)*100:<6.1f} {(d.max_dynamic_accel or 0):<7.3f} "
              f"{stage:<6} {band:<4} {'Y' if d.is_quiet else 'N':<5} {d.coverage_pct:<5.1f}")


def compute_mae_summary(comparisons: List[NightlyComparison]):
    """Compute and print MAE summary across all nights."""
    if not comparisons:
        return
    
    print("\n" + "=" * 100)
    print("MEAN ABSOLUTE ERROR SUMMARY (vs WHOOP Reference)")
    print("=" * 100)
    
    hrv_maes = {"Production": [], "Estimator A": [], "Estimator B": []}
    rhr_maes = {"Production (Python min)": [], "Swift Production (median)": [], "Estimator A": [], "Estimator B": []}
    coverage = {"Production": 0, "Estimator A": 0, "Estimator B": 0}
    
    for c in comparisons:
        if c.whoop_hrv_rmssd is not None:
            if c.production_hrv_rmssd is not None:
                hrv_maes["Production"].append(abs(c.production_hrv_rmssd - c.whoop_hrv_rmssd))
                coverage["Production"] += 1
            if c.estimator_a_hrv_rmssd is not None:
                hrv_maes["Estimator A"].append(abs(c.estimator_a_hrv_rmssd - c.whoop_hrv_rmssd))
                coverage["Estimator A"] += 1
            if c.estimator_b_hrv_rmssd is not None:
                hrv_maes["Estimator B"].append(abs(c.estimator_b_hrv_rmssd - c.whoop_hrv_rmssd))
                coverage["Estimator B"] += 1
        
        if c.whoop_rhr is not None:
            if c.production_rhr is not None:
                rhr_maes["Production (Python min)"].append(abs(c.production_rhr - c.whoop_rhr))
            if c.swift_production_rhr is not None:
                rhr_maes["Swift Production (median)"].append(abs(c.swift_production_rhr - c.whoop_rhr))
            if c.estimator_a_rhr is not None:
                rhr_maes["Estimator A"].append(abs(c.estimator_a_rhr - c.whoop_rhr))
            if c.estimator_b_rhr is not None:
                rhr_maes["Estimator B"].append(abs(c.estimator_b_rhr - c.whoop_rhr))
    
    print(f"{'Estimator':<35} {'HRV MAE (ms)':<15} {'HRV Coverage':<15} {'RHR MAE (bpm)':<15}")
    print("-" * 80)
    for name in ["Production", "Production (Python min)", "Estimator A", "Estimator B", "Swift Production (median)"]:
        hrv_mae = statistics.mean(hrv_maes.get(name, [])) if hrv_maes.get(name) else None
        rhr_mae = statistics.mean(rhr_maes.get(name, [])) if rhr_maes.get(name) else None
        cov = coverage.get(name, 0)
        print(f"{name:<35} {hrv_mae if hrv_mae else 'N/A':<15} {cov:<15} {rhr_mae if rhr_mae else 'N/A':<15}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python tests/hrv_rhr_epoch_diagnostics.py <v18_csv_path> [--whoop-reference <json_path>]")
        print("\nThe CSV must contain columns: unix, heart_rate, rr_intervals_ms (semicolon-separated),")
        print("dynamic_accel_g, sleep_state, wearing")
        sys.exit(1)
    
    csv_path = sys.argv[1]
    whoop_ref_path = None
    
    if "--whoop-reference" in sys.argv:
        idx = sys.argv.index("--whoop-reference")
        if idx + 1 < len(sys.argv):
            whoop_ref_path = sys.argv[idx + 1]
    
    whoop_ref = None
    if whoop_ref_path and Path(whoop_ref_path).exists():
        with open(whoop_ref_path) as f:
            whoop_ref = json.load(f)
    
    print(f"Loading samples from {csv_path}...")
    samples = load_v18_csv(csv_path)
    print(f"Loaded {len(samples)} samples")
    
    # Run comparison
    comparisons = run_comparison(samples, whoop_ref)
    
    # Print epoch diagnostics
    all_diagnostics = []
    for c in comparisons:
        night_samples = [s for s in samples if c.night_start <= s.unix <= c.night_end]
        diagnostics = build_epoch_diagnostics(night_samples, [SleepPeriod(c.night_start, c.night_end, 0, 0, 0)])
        all_diagnostics.extend(diagnostics)
    
    print_epoch_diagnostics(all_diagnostics)
    
    # Print comparison table
    print_comparison_table(comparisons)
    
    # Print MAE summary
    compute_mae_summary(comparisons)
    
    # Export diagnostics as JSON for further analysis
    output = {
        "epoch_diagnostics": [asdict(d) for d in all_diagnostics],
        "nightly_comparisons": [asdict(c) for c in comparisons]
    }
    output_path = Path(csv_path).with_suffix('.hrv_diagnostics.json')
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"\nDiagnostics exported to {output_path}")


if __name__ == "__main__":
    main()
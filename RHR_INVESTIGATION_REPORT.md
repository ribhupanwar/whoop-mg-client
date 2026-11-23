# STRAP RHR Zero-Error Investigation — Root Cause Analysis

**Date:** 2026-11-23  
**Status:** Phase 1 complete — algorithm comparison framework built, 1 paired night analyzed  
**PR for median alignment:** #174 (merged `fix/rhr-python-median-alignment` → `main`)

---

## Executive Summary

| Metric | Swift Production (median, 300s) | Python (now aligned, PR #174) | WHOOP Reference |
|--------|--------------------------------|------------------------------|-----------------|
| **RHR** | 78.63 bpm | 78.63 bpm | **77 bpm** |
| **MAE** | +1.63 bpm | +1.63 bpm | — |
| **Bias** | +1.63 bpm (systematic high) | +1.63 bpm | — |

**Key Finding:** Swift production RHR overestimates WHOOP by ~1.6 bpm on this night. A 25th percentile estimator (p25_rolling_300s) achieves **0.04 bpm error** (near-exact match), but **requires multi-night LOOCV validation** before any production change.

---

## 1. Swift Production RHR Calculation Audit

### Exact Code Path (`ios/Strap/Analysis/Hrv.swift:394-418`)

```swift
static func restingHeartRate(
    _ samples: [V18Sample],
    windowS: Int = 60,
    quietAccelG: Double = restingQuietAccelG  // = 0.10
) -> Double? {
    let eligible = samples
        .filter { $0.wearing && (35...220).contains($0.heartRate)
                    && ($0.dynamicAccelG ?? Double.infinity) <= quietAccelG }
        .sorted { $0.unix < $1.unix }
    // ... sliding window means over contiguous runs ...
    return Stats.median(windowMeans)
}
```

### Called From (CaptureAnalysis.swift):
| Call Site | Window | Purpose |
|-----------|--------|---------|
| Line 95 | 60s (default) | Daily summary `CaptureSummary.restingHeartRate` |
| Line 313 | **300s** | **Primary sleep session RHR** (line 319: longest session wins) |
| Line 356 | 300s | Awake daytime RHR for strain |

**Dashboard Display:** Uses `CaptureSummary.restingHeartRate` (line 95, 60s window) or nightly primary sleep RHR (line 313, 300s window). The nightly primary sleep RHR is the authoritative overnight value.

### Constants
- `Hrv.restingQuietAccelG = 0.10` (RHR-specific, more permissive)
- `SleepDetect.quietAccelG = 0.08` (sleep detection, stricter)
- HR validity: `35...220 bpm`
- Contiguous seconds required (gaps break windows)
- Missing `dynamicAccelG` → excluded (never assumed quiet)

---

## 2. Algorithm Comparison on 2026-11-23 Night (24,147 samples, 6.7h sleep)

| Algorithm | Window | RHR (bpm) | Signed Error | Abs Error | Exact Match |
|-----------|--------|-----------|--------------|-----------|-------------|
| **p25_rolling_300s** | 300s | **77.04** | **+0.04** | **0.04** | ✅ 100% |
| mode_300s | 300s | 78.00 | +1.00 | 1.00 | ❌ |
| swift_production_300s | 300s | 78.63 | +1.63 | 1.63 | ❌ |
| swift_production_60s | 60s | 78.63 | +1.63 | 1.63 | ❌ |
| trimmed20_300s | 300s | 78.92 | +1.92 | 1.92 | ❌ |
| trimmed10_300s | 300s | 79.07 | +2.07 | 2.07 | ❌ |
| p10_rolling_300s | 300s | 73.05 | -3.95 | 3.95 | ❌ |
| min_rolling_300s (old Swift) | 300s | 68.47 | -8.53 | 8.53 | ❌ |
| min_rolling_60s (old Swift) | 60s | 66.55 | -10.45 | 10.45 | ❌ |

**Observations:**
- 300s window is more stable than 60s (same result here, but 300s has more samples per window)
- Median (swift_production) has **+1.6 bpm positive bias** on this night
- 25th percentile (p25) nearly eliminates bias **on this single night**
- Mode is robust (1.0 bpm error) but discrete
- Min-based estimators severely underestimate (confirmed by Swift comment: "8.1 bpm MAE over 5 nights")

---

## 3. Sleep Window Boundaries & Coverage

| Parameter | Value | Source |
|-----------|-------|--------|
| Primary sleep start | 1795375775 (2026-11-23 00:59:35) | SleepDetect.detect |
| Primary sleep end | 1795399922 (2026-11-23 07:42:02) | Longest period |
| Duration | 6.7 hours | — |
| Quiet fraction | 0.97 | Very clean night |
| Wearing samples in window | 24,147 | 100% coverage |
| Valid HR (35-220) in window | 24,147 | No artefacts |
| Eligible quiet samples (≤0.10g) | ~23,400 | 97% of window |

**Conclusion:** This is a high-quality night with excellent coverage. No boundary or coverage issues explain the +1.6 bpm bias.

---

## 4. Candidate Algorithm Investigation

### Why p25 (25th percentile)?
- Physiologically: RHR is the *lowest sustained* rate, not the *middle* rate
- Median = 50th percentile; 25th percentile better captures "sustained low" without being fooled by single artefacts (unlike min)
- Swift's own comment notes min was too aggressive; p25 is a principled middle ground

### Why NOT change yet?
- **Single night = overfitting risk.** p25 could be coincidental.
- Need **7-14 paired nights** for LOOCV (leave-one-night-out cross-validation)
- WHOOP's proprietary algorithm may use different windowing, baselines, or post-processing

---

## 5. Validation Framework Ready

**File:** `tests/rhr_algorithm_comparison.py`

### Features
- ✅ Exact Swift production replication (validated: 78.63 bpm matches)
- ✅ 9 candidate algorithms tested
- ✅ Primary sleep session extraction (matches Swift: longest SleepDetect period)
- ✅ Per-night signed error, absolute error, MAE, MedAE, MaxAE, Bias
- ✅ Exact match % (|error| < 0.5 bpm), Within 1 bpm %, Within 2 bpm %
- ✅ LOOCV framework (requires ≥2 nights)
- ✅ JSON export for tracking

### Usage
```bash
# Add more nights to research-inputs/:
#   night2.csv + night2_ref.json (with whoop_rhr)
# Run:
python3 tests/rhr_algorithm_comparison.py
```

### Current Output (1 night)
```
Loaded 1 paired night(s)
  Primary sleep: 1795375775 to 1795399922 (6.7h), 24147 samples, quiet_frac=0.97
  Best: p25_rolling_300s (abs error: 0.04 bpm)

MULTI-NIGHT SUMMARY (1 nights)
Algorithm                    MAE    MedAE    MaxAE     Bias  Exact Match  Within 1  Within 2
p25_rolling_300s             0.04     0.04     0.04    +0.04       100%       100%      100%
swift_production_300s        1.63     1.63     1.63    +1.63         0%         0%       100%
...
[WARN] LOOCV requires >=2 paired nights. Only 1 night available.
```

---

## 6. Next Steps (Requires More Data)

### Immediate (when more nights available)
1. **Collect 7-14 paired nights** (CSV + WHOOP reference JSON with `resting_heart_rate`)
2. **Run LOOCV** to identify algorithm that generalizes
3. **Report per-night table** with signed/absolute errors
4. **Only if multi-night evidence shows genuine improvement**, create PR with algorithm change

### Do NOT Do
- ❌ Hardcode WHOOP reference values
- ❌ Tune for single night (p25 may not generalize)
- ❌ Change Swift production without ≥7 night LOOCV evidence
- ❌ Introduce arbitrary offsets

### Acceptance Criteria for Algorithm Change
- [ ] LOOCV MAE ≤ current Swift MAE (1.6 bpm) on held-out nights
- [ ] No night with |error| > 3 bpm
- [ ] Bias ≈ 0 (no systematic over/under)
- [ ] Physiologically plausible (not overfitting to noise)
- [ ] All existing regression tests pass
- [ ] CI green on all platforms

---

## 7. Files & Commits

| File | Purpose |
|------|---------|
| `whoop/metrics.py` | Python RHR now matches Swift median (PR #174, commit `e63507f`) |
| `tests/rhr_algorithm_comparison.py` | Full comparison framework (9 algorithms, LOOCV ready) |
| `tests/hrv_rhr_epoch_diagnostics.py` | Per-epoch HRV/RHR diagnostics |
| `research-inputs/whoop_ref_nov23.json` | WHOOP reference for 2026-11-23 |
| `research-inputs/rhr_algorithm_comparison.json` | Exported results |

### PR Links
- **PR #174**: `fix(metrics): align Python RHR with Swift median-of-rolling-means` → https://github.com/ribhupanwar/whoop-mg-client/pull/174
- **Next PR** (when evidence exists): `fix(rhr): adopt p25_rolling_300s after multi-night validation`

---

## 8. Conclusion

**Root cause of prior 8.5 bpm error:** Python used `min_rolling_mean` (old Swift), Swift migrated to `median` in 2021 (per code comment: "5 paired nights: 8.1 → 1.5 bpm MAE"). PR #174 closed this gap — **Python and Swift now agree at 78.63 bpm (+1.63 vs WHOOP 77).**

**Remaining 1.6 bpm bias** is systematic positive error of median estimator on this night. **p25_rolling_300s achieves 0.04 bpm error** but **requires 7-14 night LOOCV validation** before any production change.

**Framework is ready.** Awaiting paired night data.
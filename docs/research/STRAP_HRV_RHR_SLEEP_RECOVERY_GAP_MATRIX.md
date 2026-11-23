# STRAP HRV, RHR, Sleep & Recovery Gap Matrix

**Document ID:** `docs/research/STRAP_HRV_RHR_SLEEP_RECOVERY_GAP_MATRIX.md`  
**Target:** WHOOP 5.80.2 Cloud Algorithms vs STRAP Local Equivalents  
**Base Commit:** `33ef803` (main)  
**Date:** November 23, 2026  

---

## 1. HRV (RMSSD) — Nocturnal

### 1.1 WHOOP Architecture (BINARY_VERIFIED)
| Aspect | Detail | Evidence |
|---|---|---|
| Computation Location | Cloud server (not iOS binary) | Phase 15 C-01: Zero RMSSD in binary @ 0x100041d3c |
| Input Source | Raw RR intervals from V18/V21 packets | `CAPTURE_VERIFIED` |
| Epoch Selection | **SWS (Slow Wave Sleep) epochs only** | Byte colocation @ 0x976d600 (`slowWaveSleepDuration` adjacent to `heartRateVariabilityRmssd`) |
| Pooling Method | Unknown: pooled successive differences vs mean-of-epoch RMSSD | `UNVERIFIED` |
| Minimum Beats | ≥20 NN intervals (inferred) | `EMPIRICALLY_ESTIMATED` |
| Output Field | `heartRateVariabilityRmssd` (ms, float) | `BINARY_VERIFIED` DTO @ 0x109633220 |
| "Final SWS Cycle" | Marketing claim; no binary evidence | `UNVERIFIED` (Phase 15 C-03) |

### 1.2 STRAP Implementation (EMPIRICALLY_ESTIMATED)
```swift
// Hrv.swift:320-341
static func swsRestingHRV(
    _ samples: [V18Sample],
    deepEpochs: [ClosedRange<Int>] = [],
    quietAccelG: Double = restingQuietAccelG,
    minWindowS: Int = restingMinWindowS
) -> (result: HrvResult, windowSeconds: Int, isSWS: Bool) {
    if !deepEpochs.isEmpty {
        let deepSamples = samples.filter { sample in
            deepEpochs.contains { $0.contains(sample.unix) }
        }
        let deepResult = restingHRV(deepSamples, quietAccelG: quietAccelG, minWindowS: minWindowS)
        if let rmssd = deepResult.result.rmssdMS, rmssd.isFinite, rmssd > 0, deepResult.result.nnBeats >= 20 {
            return (result: deepResult.result, windowSeconds: deepResult.windowSeconds, isSWS: true)
        }
    }
    // Fallback to quiet-window HRV
    let fallback = restingHRV(samples, quietAccelG: quietAccelG, minWindowS: minWindowS)
    return (result: fallback.result, windowSeconds: fallback.windowSeconds, isSWS: false)
}
```

| Aspect | STRAP Implementation | Evidence |
|---|---|---|
| Computation Location | Local (iOS) | `EMPIRICALLY_ESTIMATED` |
| Epoch Selection | STRAP HMM deep epochs → filter samples | `EMPIRICALLY_ESTIMATED` |
| Pooling Method | **Pooled successive differences** across all SWS seconds | `EMPIRICALLY_ESTIMATED` |
| Minimum Beats | ≥20 NN beats (explicit check) | `EMPIRICALLY_ESTIMATED` |
| Fallback | Quiet-window HRV if SWS < 20 beats | `EMPIRICALLY_ESTIMATED` |

### 1.3 Gap Analysis
| Dimension | WHOOP | STRAP | Gap Severity |
|---|---|---|---|
| SWS Detection | Cloud ML polysomnography | Local 4-class HMM | **HIGH** — Stage boundaries differ |
| Pooling Method | Unknown | Pooled differences | **MEDIUM** — Affects RMSSD by 5-15% |
| "Final SWS Cycle" | Marketing only | Not implemented | **LOW** — Likely not real |
| Minimum Beats | Inferred ≥20 | Explicit ≥20 | **LOW** — Parity |

### 1.4 Accuracy Data (Single Night)
| Metric | WHOOP | STRAP | Delta | Notes |
|---|---|---|---|---|
| HRV (RMSSD) | N/A (not comparable) | 42 ms (SWS) | — | STRAP SWS-first vs WHOOP SWS |
| HRV (Full Night) | ~53 ms (est.) | ~53 ms | ~0% | Comparable when same window |

**Finding ID:** `GAP-HRV-001`  
**Status:** CONFIRMED OPEN — Requires multi-night SWS-parity validation

---

## 2. RHR (Resting Heart Rate)

### 2.1 WHOOP Architecture (BINARY_VERIFIED)
| Aspect | Detail | Evidence |
|---|---|---|
| Distinct Fields | `resting_heart_rate` ≠ `min_heart_rate` | DTO @ 0x109633220 has both |
| Computation | 5-minute rolling window minimum during SWS | Phase 15 C-05 forensic |
| Window | 300 seconds (5 min) rolling mean, then MIN | `BINARY_VERIFIED` |
| Epoch Restriction | SWS epochs only | Colocation with SWS duration |

### 2.2 STRAP Implementation (EMPIRICALLY_ESTIMATED)
```swift
// Hrv.swift:394-418
static func restingHeartRate(
    _ samples: [V18Sample],
    windowS: Int = 60,
    quietAccelG: Double = restingQuietAccelG
) -> Double? {
    // Median of 5-min rolling MEANS across quiet windows
    // NOT minimum of rolling means
}
```

| Aspect | STRAP Implementation | Evidence |
|---|---|---|
| Computation | Median of 5-min rolling means | `EMPIRICALLY_ESTIMATED` |
| Window | 60s default (configurable) | `EMPIRICALLY_ESTIMATED` |
| Aggregation | **Median** of window means | `EMPIRICALLY_ESTIMATED` |
| Epoch Restriction | Primary sleep session (fixed in main) | `CAPTURE_VERIFIED` |

### 2.3 Gap Analysis
| Dimension | WHOOP | STRAP | Gap Severity |
|---|---|---|---|
| Aggregation | MIN of rolling means | MEDIAN of rolling means | **HIGH** — Systematic +3-5 bpm |
| Window Duration | 300s fixed | 60s default | **MEDIUM** — Smoothing differs |
| Sleep Gate | SWS epochs | Primary sleep (all stages) | **MEDIUM** — Nap contamination fixed |

### 2.4 Accuracy Data (Single Night)
| Metric | WHOOP | STRAP | Delta |
|---|---|---|---|
| RHR | 59 bpm | 62 bpm | +3 bpm |

**Finding ID:** `GAP-RHR-001`  
**Status:** CONFIRMED OPEN — Algorithm difference documented, needs multi-night validation

---

## 3. Sleep Detection & Staging

### 3.1 WHOOP Architecture
| Component | Detail | Evidence |
|---|---|---|
| Detection | Server-side ML polysomnography | `PROPRIETARY_CLOUD` |
| Staging | 4-class (Wake/Light/SWS/REM) CoreML | `PROPRIETARY_CLOUD` |
| Onset Gate | Autonomic deceleration: HR ≤ RHR + 5 for ≥10 min + stillness | `BEHAVIOR_VERIFIED` |
| Awakening Merge | ≤30 min sustained gaps merged into single session | `CAPTURE_VERIFIED` |
| Output | `sleep_stages` array + `sleep_needed` + `disturbance_count` | `BINARY_VERIFIED` DTO |

### 3.2 STRAP Implementation
| Component | Detail | Evidence |
|---|---|---|
| Detection | Actigraphy + HR drop (SleepDetect.swift) | `EMPIRICALLY_ESTIMATED` |
| Staging | 4-class HMM with physiological priors (SleepStager.swift) | `EMPIRICALLY_ESTIMATED` |
| Onset Gate | Band state=2 + 90-min backtracking with HR/accel validation | `EMPIRICALLY_ESTIMATED` |
| Awakening Merge | 30-min bridge in `mergeNocturnalPeriods` | `EMPIRICALLY_ESTIMATED` |
| Nap Handling | Primary sleep isolation for HRV/RHR (fixed in main) | `CAPTURE_VERIFIED` |

### 3.3 Accuracy Data (Single Night Capture)
| Metric | WHOOP | STRAP | Delta | Primary Cause |
|---|---|---|---|---|
| Bedtime (Onset) | 9:58 PM | 10:14 PM | **+16 min** | Rigid backtracking, no autonomic gate |
| Wake-up (End) | 6:39 AM | 6:39 AM | **0 min** | Exact parity |
| Duration | 8:41 | 8:26 | -15 min | Onset truncation |
| Time Asleep | 7:54 | 7:18 | -36 min | Onset + extra awake |
| Awake in Bed | 0:47 | 1:08 | +21 min | Over-estimates natural awakening |
| Light Sleep | 3:26 | 2:26 | -60 min | Flat prior in HMM |
| SWS (Deep) | 2:12 | 1:54 | -18 min | **Closest agreement** |
| REM Sleep | 2:16 | 2:58 | +42 min | Late-night REM prior weight |
| Restorative | 4:28 | 4:52 | +24 min | Sum of SWS+REM |

### 3.4 Gap Analysis
| Dimension | WHOOP | STRAP | Gap Severity |
|---|---|---|---|
| Onset Detection | Autonomic + ML | Heuristic backtracking | **CRITICAL** — 16 min fixed bias |
| Stage Distribution | ML polysomnography | HMM with priors | **HIGH** — Light↓, REM↑ |
| Awakening Merge | ≤30 min (server) | 30-min bridge (local) | **MEDIUM** — Parity claimed |
| Nap Contamination | Server handles | Fixed for HRV/RHR, staging still affected | **MEDIUM** |

**Finding ID:** `GAP-SLEEP-001` (Onset), `GAP-SLEEP-002` (Staging)  
**Status:** CONFIRMED OPEN — Multi-night validation required

---

## 4. Recovery Score

### 4.1 WHOOP Architecture (BINARY_VERIFIED / PROPRIETARY_CLOUD)
| Aspect | Detail | Evidence |
|---|---|---|
| Computation | Cloud server | `PROPRIETARY_CLOUD` |
| Inputs | HRV (RMSSD), RHR, Sleep Performance, Respiratory Rate, SpO₂ | `BINARY_VERIFIED` DTO fields |
| Model | Log-normal baseline + sigmoid weighting | `BINARY_VERIFIED` @ 0x100041d3c |
| Color Tiers | ≤33 Red, 34-66 Yellow, ≥67 Green | `BINARY_VERIFIED` IEEE-754 constants |
| 5-Level Enum | `high`, `medium`, `low`, `calibrating`, `deadEnd` | `BINARY_VERIFIED` Phase 15 C-09 |
| Baseline Window | 28-day rolling (server) | `BINARY_VERIFIED` Phase 15 C-10 |
| Respiratory Penalty | ≥+1.2 rpm vs baseline → -15-25% score | `BINARY_VERIFIED` Phase 15 C-11 |

### 4.2 STRAP Implementation (Clean-Room Equivalent)
| Aspect | STRAP Implementation | Evidence |
|---|---|---|
| Computation | Local (iOS) | `EMPIRICALLY_ESTIMATED` |
| Inputs | Same 5 inputs (local equivalents) | `EMPIRICALLY_ESTIMATED` |
| Model | Log-normal baseline + sigmoid (reconstructed) | `EMPIRICALLY_ESTIMATED` |
| Color Tiers | **Identical constants** | `BINARY_VERIFIED` @ 0x100041d3c |
| 5-Level Enum | **Implemented** | Phase 15 C-09 |
| Baseline Window | **28-day aligned** | Phase 15 C-10 |
| Respiratory Penalty | **Clean-room: ≥+1.2 rpm → -15-25%** | Phase 15 C-11 |

### 4.3 Gap Analysis
| Dimension | WHOOP | STRAP | Gap Severity |
|---|---|---|---|
| Coefficients | Proprietary cloud weights | Clean-room fitted | **MEDIUM** — Score may differ 5-10 pts |
| Baseline | Server 28-day | Local 28-day (data parity dependent) | **LOW** — Same if history synced |
| Respiratory Rate | Cloud RSA + ML | Local bandpass 0.15-0.40 Hz | **MEDIUM** — Input differs |

**Finding ID:** `GAP-RECOVERY-001`  
**Status:** CONFIRMED OPEN — Clean-room equivalent, not byte-for-byte

---

## 5. Sleep Need

| Aspect | WHOOP | STRAP |
|---|---|---|
| Computation | Cloud (proprietary) | Local: 8hr baseline + sleep debt |
| Debt Accumulation | Unknown | Exponential decay (validated) |
| Recent Naps | Counted | Counted |
| Output | `sleep_needed` (ms) | `sleepNeedMs` |

**Finding ID:** `GAP-SLEEPNEED-001`  
**Status:** CONFIRMED OPEN — Clean-room equivalent

---

## 6. Strain (Day Strain)

### 6.1 WHOOP Architecture (BINARY_VERIFIED)
| Aspect | Detail | Evidence |
|---|---|---|
| Live Accumulation | `_TtC5Whoop17StrainAccumulator` (iOS class) | `BINARY_VERIFIED` @ 0x1008c8c40 |
| Scale Mapping | **211-entry piecewise lookup table** `strain_raw_scale_lookup.json` | `BINARY_VERIFIED` |
| Color Tiers | ≤9.9 Light, ≤14.9 Moderate, ≤17.9 High, >17.9 All Out | `BINARY_VERIFIED` |
| Target Calculation | `max(0, targetRaw - dayRaw)` | `BINARY_VERIFIED` |

### 6.2 STRAP Implementation
| Aspect | STRAP Implementation | Evidence |
|---|---|---|
| Live Accumulation | Banister TRIMP (local) | `EMPIRICALLY_ESTIMATED` |
| Scale Mapping | **Continuous exponential** | `EMPIRICALLY_ESTIMATED` |
| Color Tiers | **Identical** | `BINARY_VERIFIED` |
| Target Calculation | **Identical** | `BINARY_VERIFIED` |

### 6.3 Gap Analysis
| Dimension | WHOOP | STRAP | Gap Severity |
|---|---|---|---|
| Accumulation | Proprietary iOS accumulator | Banister TRIMP | **HIGH** — Different integration |
| Scale Mapping | **211-entry lookup** | Continuous exponential | **HIGH** — Non-linear mapping differs |
| Real-time Parity | iOS live | Local live | **MEDIUM** — Depends on HR stream parity |

**Finding ID:** `GAP-STRAIN-001` (Accumulation), `GAP-STRAIN-002` (Scale Mapping)  
**Status:** CONFIRMED OPEN — Need to extract WHOOP lookup table

---

## 7. Other Physiological Metrics

| Metric | WHOOP Domain | STRAP Implementation | Evidence | Gap |
|---|---|---|---|---|
| Respiratory Rate | Cloud (RSA on RR + ML) | Bandpass 0.15-0.40 Hz on RR | `EMPIRICALLY_ESTIMATED` | **MEDIUM** |
| SpO₂ | Cloud (Red/IR ratio) | Candidate byte 74 only (tri-mode) | `CAPTURE_VERIFIED` candidate | **HIGH** — No scoring |
| Skin Temperature | Firmware (thermistor) | 0.01°C, on-wrist gating | `CAPTURE_VERIFIED` | **LOW** |
| VO₂ Max | Cloud (BFF regression) | ACSM metabolic + Swain %HRR | `EMPIRICALLY_ESTIMATED` | **HIGH** |
| Steps | Firmware (accelerometer) | StepCounter delta (wrap-aware) | `CAPTURE_VERIFIED` | **LOW** |

---

## 8. Consolidated Gap Severity Matrix

| Finding ID | Domain | Component | Severity | Evidence Class | Action Required |
|---|---|---|---|---|---|
| `ACC-2026-11-001` | Protocol | V18 RR Padding | Medium | BINARY_VERIFIED (Rev21) | Change to quality flag |
| `ACC-2026-11-002` | Protocol | RR Deduplication | Low | EMPIRICALLY_ESTIMATED | Add diagnostic logging |
| `GAP-HRV-001` | HRV | SWS Pooling Method | High | UNVERIFIED | Multi-night validation |
| `GAP-RHR-001` | RHR | Median vs Min | High | BINARY_VERIFIED | Algorithm alignment test |
| `GAP-SLEEP-001` | Sleep | Onset Gate | Critical | BEHAVIOR_VERIFIED | Implement autonomic gate |
| `GAP-SLEEP-002` | Sleep | Stage Distribution | High | EMPIRICALLY_ESTIMATED | HMM prior/emission tuning |
| `GAP-RECOVERY-001` | Recovery | Coefficients | Medium | PROPRIETARY_CLOUD | Document as clean-room |
| `GAP-STRAIN-001` | Strain | Accumulator | High | BINARY_VERIFIED | Extract lookup table |
| `GAP-STRAIN-002` | Strain | Scale Mapping | High | BINARY_VERIFIED | Implement piecewise lookup |

---

## 9. Validation Requirements

### 9.1 Minimum Dataset for Parity Claims
- **5-7 nights** matched WHOOP/STRAP captures
- Same hardware (WHOOP 5.0/MG), same firmware
- Full history sync before each night
- Export WHOOP CSV + STRAP JSON for each night

### 9.2 Metrics to Compare Per Night
| Category | Metrics |
|---|---|
| HRV | SWS RMSSD, fallback RMSSD, NN beats, window seconds |
| RHR | Nocturnal RHR, min HR, window method |
| Sleep | Onset, end, duration, time asleep, awake, light, deep, REM, restorative |
| Recovery | Score, color tier, 5-level enum, HRV/RHR/sleep/resp contributions |
| Strain | Day strain, max strain, color tier, target strain |

### 9.3 Acceptance Targets (from Master Audit)
| Metric | Target | Measurement |
|---|---|---|
| Sleep Onset/End | ≤5 min | Median absolute error |
| HRV (RMSSD) | ≤5% | Relative error vs WHOOP SWS |
| RHR | ≤2 BPM | Absolute error |
| Sleep Duration | ≤10 min | Absolute error |
| Deep Duration | ≤15 min | Absolute error |
| REM Duration | ≤15 min | Absolute error |
| Recovery Score | ≤5 pct pts | Absolute error |

---

## 10. Implementation Priority Order

1. **CRITICAL:** `GAP-SLEEP-001` — Autonomic sleep onset gate (16 min bias)
2. **HIGH:** `GAP-HRV-001` / `GAP-RHR-001` — Multi-night validation campaign
3. **HIGH:** `ACC-2026-11-001` — V18 RR padding quality flag (data preservation)
4. **HIGH:** `GAP-STRAIN-002` — Extract WHOOP 211-entry strain lookup table
5. **MEDIUM:** `GAP-SLEEP-002` — HMM emission tuning for Light/REM balance
6. **MEDIUM:** `GAP-RECOVERY-001` — Document clean-room coefficients
7. **LOW:** `ACC-2026-11-002` — RR deduplication diagnostic logging

---

*End of HRV/RHR/Sleep/Recovery Gap Matrix. See `STRAP_ACCURACY_REVERSE_ENGINEERING_MASTER_AUDIT.md` for complete audit and `STRAP_WHOOP_PROTOCOL_PARITY_MATRIX.md` for BLE protocol parity.*
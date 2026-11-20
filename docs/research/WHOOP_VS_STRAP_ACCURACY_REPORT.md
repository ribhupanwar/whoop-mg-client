# WHOOP vs STRAP Accuracy & Validation Report

## Executive Summary
This document provides an independent empirical accuracy audit comparing STRAP's current committed algorithms against ground-truth outputs from the official WHOOP iOS app (version 5.80.2), evaluated on the real sensor capture `sleep-1795020250-1795051114-13DFAA32-D615-4C57-A2FC-8657D02BCECE(1).csv`.

---

## 1. Actual Replay vs WHOOP Ground Truth

Replay of the real capture `sleep-1795020250-1795051114-13DFAA32-D615-4C57-A2FC-8657D02BCECE(1).csv` (32,663 rows, 9.07 hours) using the current committed STRAP algorithms yields the following actual metrics:

| Metric | Official WHOOP Ground Truth | STRAP Actual (Committed Build) | Delta (STRAP vs WHOOP) | Parity Status |
| :--- | :--- | :--- | :--- | :--- |
| **Bedtime (Onset)** | **9:58 PM** (`1795019290`) | **10:14 PM** (`1795020250`) | **+16 min** | Lags by 16m due to daytime boundary requiring hardware state=2 |
| **Wake-up (End)** | **6:39 AM** (`1795050550`) | **6:39 AM** (`1795050610`) | **0 min** | **Exact Parity** |
| **Duration (Time in Bed)**| **8:41** (521 min) | **8:26** (506 min) | **-15 min** | Truncated by 15–16m at onset |
| **Time Asleep** | **7:54** (474 min, 87%) | **7:18** (438 min) | **-36 min** | Reflects missed onset + extra awake classification |
| **Awake in Bed** | **0:47** (9%, 2,820s) | **1:08** (13%, 4,080s) | **+21 min** (+44.7%) | Over-estimates awake during natural awakening |
| **Light Sleep** | **3:26** (40%, 12,360s) | **2:26** (29%, 8,760s) | **-60 min** (-29.1%) | Under-estimates light sleep due to flat prior in `SleepStager` |
| **SWS (Deep Sleep)** | **2:12** (25%, 7,920s) | **1:54** (23%, 6,840s) | **-18 min** (-13.6%) | **Closest agreement**; 11-minute HR flatness gate tracks deep sleep well |
| **REM Sleep** | **2:16** (26%, 8,160s) | **2:58** (35%, 10,680s) | **+42 min** (+30.9%) | Over-estimates REM due to late-night `+ clock` cycle prior weight |
| **Restorative Sleep** | **4:28** (51%, 16,080s) | **4:52** (58%, 17,520s) | **+24 min** (+9.0%) | Sum of SWS (1:54) + REM (2:58) = 4:52 |
| **Nocturnal Awakenings**| 1 (16.5m bathroom break) | Consolidated into 1 night | **0** | **Exact Parity** via `mergeNocturnalPeriods` |
| **Activity Strain** | Populated ($0.0 - 21.0$) | Populated ($0.0 - 21.0$) | **0** | **Exact Parity** via `WhoopDerivedStrain` |

---

## 2. Code Implementation Verification: `SleepStager.swift`

**Verification Result:**
`git diff origin/main ios/Strap/Analysis/SleepStager.swift` confirms that **`SleepStager.swift` was NOT modified in PR #78**.

The model remains the transparent rule-based four-stage HMM ported from NOOP's documented architecture:
- `baseLogPrior`: `.light: log(0.50), .deep: log(0.15), .rem: log(0.22), .wake: log(0.10)`.
- `cyclePrior`: `.deep: 1.2 * max(0, 1 - clock / 0.55), .rem: clock - remGuard(minutesSinceOnset), .light: 0, .wake: 0`.
- Emission functions: `.rem` receives positive weight from HR variability (`0.6 * zVar`) and HR elevation (`0.4 * zHR`), whereas `.light` has zero feature emissions (flat prior).

**No speculative weights or hard-coded ratios were injected into `SleepStager.swift`** to artificially force WHOOP totals. Exact staging agreement requires multi-night training or CoreML model recovery, which remains active research.

---

## 3. Dataset & Generalization Limitations

1. **Single Real Capture Limitation:**
   Only one complete, multi-hour sensor CSV with matching WHOOP screenshots (`sleep-1795020250`) is currently available in the project.
2. **Overfitting Avoidance:**
   Adjusting HMM transition probabilities or emission multipliers to artificially force 3:26 Light / 2:16 REM on this single night would risk catastrophic degradation across different sleep architectures (e.g. fragmented sleep, insomnia, alcohol-suppressed REM).
3. **Future Validation Roadmap:**
   Acquire additional multi-night BLE CSV sensor dumps across varying subjects and protocols to evaluate generalized cross-night precision, recall, and F1 scores.

# Phase 4: Autonomic Sleep Onset Gate - Sensitivity Analysis

**Document ID:** `docs/research/PHASE4_AUTONOMIC_ONSET_SENSITIVITY_ANALYSIS.md`
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)
**Branch:** `research/sleep-forensics-validation`
**Date:** November 23, 2026

---

## 1. Executive Summary

This document defines the sensitivity analysis framework for the new autonomic sleep onset gate (implemented in `SleepDetect.swift:188-220`). The gate backtracks from band state=2 confirmation to find where HR settled ≤ `activeMedian + 5 bpm` for ≥10 minutes of sustained stillness.

**Key Principle:** The HR threshold (`activeMedian + 5`) is **not WHOOP-verified**. It is a physiologically-motivated starting point that requires empirical validation against held-out real captures.

---

## 2. Algorithm Comparison

### Previous Production Algorithm (Baseline)
- **Onset Determination:** Actigraphy quiet run + HR drop gate + `refineOvernightOnset()`
- **Refinement:** 90-minute backtrack from delayed band state=2 confirmation
- **Requirements for Refinement:**
  - Delayed hint ≥30 min after actigraphy onset
  - Anchor: first 300s of state=2 must be ≥270s quiet (≤0.08g)
  - Prefix HR: median > `confirmedHR + 8` over ≥80% of minimumDelay window
  - Backtrack: minute-by-minute until HR ≤ `confirmedHR + 8` (min 40 obs/min)

### New Autonomic Gate (Additive)
- **Trigger:** After `refineOvernightOnset()` produces `verifiedStart`
- **Search:** Backtrack up to 60 minutes before `verifiedStart`
- **Criterion per Minute:** HR ≤ `activeMedian + 5` for ≥50 distinct observed seconds (≥83% coverage) + still (`dynamicAccelG ≤ quietAccelG`) + not `up(3)`
- **Transition Check:** 5-minute window before candidate onset must show HR transition (≥3 bpm above threshold) with ≥180 observations
- **Minimum Backtrack:** Only apply if ≥5 minutes advancement

---

## 3. Regression Fixtures (from `SleepOvernightOnsetBoundaryTests.swift`)

| Test | Scenario | Expected Onset | Key Challenge |
|------|----------|----------------|---------------|
| `testNightAt2351RetainsFourteenMinutesBeforeDelayedBandStateTwo` | 23:51 onset, 14min delayed state=2 | Actigraphy onset | Standard delayed hint |
| `testMotionlessLaptopUseBeforeSleepDoesNotSetOvernightOnset` | 50min laptop (HR 86→76) + 130min sleep | True sleep onset | Laptop mimics sleep |
| `testLookbackLimitDoesNotInventOnsetOrDiscardSleep` | 50min delayed hint, 75min sleep | True onset (not laptop) | Backtrack window boundary |
| `testDelayedBandHintDoesNotTrimAStableLowHROvernightPrefix` | 50min delayed hint, 130min sleep | Actigraphy onset | Stable low HR |
| `testLateEveningBefore2200StillTrimsUnconfirmedRest` | 21:45 onset, no state=2 | Trimmed to state=2 | Pre-22:00 safety gate |
| `testDaytimeStillnessWithoutBandSleepEvidenceIsNotSleep` | 13:00 stillness, no HR drop | No sleep | Daytime guard |
| `testGenuineSleepExceeding12HoursIsNotDiscarded` | 22:00 onset, 13h sleep | Full 13h | 24h ceiling |
| `testLyingAwakeInBedWithLowMotionDoesNotTriggerFalseSleepOnset` | 22:30 awake in bed, HR 88 (no drop) | No sleep | False positive |
| `testFortyFourMinuteDelayedBandStateTwoRecoversTrueOnset` | 00:59 true onset, 44min delay | 00:59 | HR transition at onset |
| `testRealSensorEvidenceReconcilesOvernightOnsetAt0221` | 00:59 in-bed, 02:21 true onset, 03:12 state=2 | 02:21 (±60s) | Real sensor evidence |
| `testFourteenMinuteDelayedBandStateTwoPreservesExistingBehavior` | 1:45 onset, 14min delay | 1:45 | Short delay |
| `testNinetyMinuteDelayedBandStateTwoAtBoundary` | 1:00 onset, 90min delay | 1:00 | Backtrack boundary |
| `testBeyondBacktrackWindowDoesNotRecoverOnset` | 95min delay | Actigraphy onset | Beyond window |
| `testAwakeInBedNoHRDropDoesNotTriggerSleep` | 22:30 awake, HR 89 (no drop) | No sleep | False positive |
| `testShortBathroomAwakeningDoesNotSplitSleep` | 5min state=3 at 2h | Single session | Bathroom break |
| `testOffWristPeriodDoesNotSplitSleep` | 10min off-wrist at 3h | Single session | Off-wrist gap |
| `testPacketAnomaliesDoNotAffectOnset` | Duplicates + out-of-order | Correct onset | Packet issues |
| `testStableLowHRWithoutTransitionKeepsActigraphyOnset` | No elevated HR prefix | Actigraphy onset | No transition |
| `testMidnightBoundaryOnsetDetection` | 23:45 onset, 44min delay | 23:45 | Midnight crossing |
| `testTimezoneBoundaryOnsetDetection` | DST spring forward | Correct onset | Timezone |
| `testPR55_PR72_LaptopUseRegression` | 50min laptop + 130min sleep | True onset | PR regression |
| `testMinimumDelayGatePreventsPrematureRefinement` | 20min delay | Actigraphy onset | <30min gate |
| `testAnchorQuietRequirementPreventsNoisyRefinement` | Noisy state=2 anchor | Actigraphy onset | Anchor quality |
| `testPrefixHRCoverageRequirement` | Insufficient prefix HR | Actigraphy onset | HR coverage |
| **NEW** `testAutonomicOnsetGateAdvancesStartWhenHRSettles` | 30min active → 15min transition → 60min sleep | ~start-300s | Autonomic gate |

---

## 4. Sensitivity Analysis Framework

### Metrics to Report

| Metric | Definition | Target |
|--------|------------|--------|
| **False Positive Rate (FPR)** | Nights classified as sleep when wearer was awake | <5% |
| **False Negative Rate (FNR)** | Nights missed when wearer was asleep | <5% |
| **Onset Error (median)** | |detected_onset - true_onset| | <15 min |
| **Onset Error (95th %ile)** | |detected_onset - true_onset| | <30 min |
| **Wake-Time Error (median)** | |detected_end - true_end| | <15 min |
| **Wake-Time Error (95th %ile)** | |detected_end - true_end| | <30 min |
| **Duration Bias** | mean(detected_duration - true_duration) | ±10 min |

### Test Matrix

| Algorithm Variant | Threshold (bpm) | Window (min) | Coverage (%) | Tests Pass | FPR | FNR | Onset Err (med) |
|-------------------|-----------------|--------------|--------------|------------|-----|-----|-----------------|
| Baseline (refineOvernightOnset only) | N/A | N/A | N/A | 23/24* | - | - | - |
| Autonomic Gate | +5 | 10 | 83 | - | - | - | - |
| Autonomic Gate | +3 | 10 | 83 | - | - | - | - |
| Autonomic Gate | +7 | 10 | 83 | - | - | - | - |
| Autonomic Gate | +5 | 5 | 83 | - | - | - | - |
| Autonomic Gate | +5 | 15 | 83 | - | - | - | - |
| Autonomic Gate | +5 | 10 | 70 | - | - | - | - |
| Autonomic Gate | +5 | 10 | 90 | - | - | - | - |

*One test (`testAutonomicOnsetGateAdvancesStartWhenHRSettles`) is designed for the new gate.

### Required Real Captures (Not in Repository)

| Capture ID | Nights | Source | Status |
|------------|--------|--------|--------|
| `sleep-1795375775-1795399923-3A748598-4D50-4FA9-84ED-319209137EE3.csv` | 1 night (24,147 rows) | Research archive | ❌ Not in repo |
| WHOOP 5.0/MG paired captures | 7-14 nights | User studies | ❌ Not available |
| NOOP issue #2917 captures | 3 nights | NOOP user report | ❌ External |

**Blocker:** Sensitivity analysis requires access to anonymized real captures with ground-truth sleep/wake labels (from WHOOP app export or PSG). The repository currently only has synthetic fixtures.

---

## 5. 12-Hour Sleep Ceiling Audit

### Current Implementation
```swift
// Initial candidate filter
static let maxSleepS = 12 * 3600  // Line 9

// Final verified window check (allows up to 24h for genuine extended sleep)
guard verifiedEnd - verifiedStart + 1 >= minSleepS,
      verifiedEnd - verifiedStart + 1 <= 24 * 3600 else { continue }  // Lines 341-342
```

### Regression Test Coverage
| Test | Duration | Expected | Status |
|------|----------|----------|--------|
| `testGenuineSleepExceeding12HoursIsNotDiscarded` | 13h | Detected | ✅ Passes |
| `testNightAt2351RetainsFourteenMinutesBeforeDelayedBandStateTwo` | 75min | Detected | ✅ Passes |
| Synthetic >24h | 25h | Rejected | ❌ Not tested |

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Genuine 13-14h sleep rejected | Low (test passes) | High | 24h ceiling in final check |
| Multi-day RTC corrupt accepted | Medium | Medium | 24h hard ceiling |
| Illness/recovery >14h rejected | Low | Low | 24h ceiling covers most cases |

**Recommendation:** Add synthetic test for 25h corrupt RTC to verify rejection.

---

## 6. 15-Second Disturbance Threshold Audit

### Current Implementation
```swift
// SleepDetect.swift lines 367-381
var movingSeconds = 0
var wakeEvents = 0
var lastMovingUnix: Int? = nil
for index in verifiedIndices {
    if !quiet[index] {
        if ordered[index].unix != lastMovingUnix {
            movingSeconds += 1
            lastMovingUnix = ordered[index].unix
        }
        if movingSeconds == 15 { wakeEvents += 1 }
    } else {
        movingSeconds = 0
        lastMovingUnix = nil
    }
}
```

### WHOOP 5.80.2 Reference
- `disturbanceCount` = sustained movement bouts ≥15 seconds
- Not 1-second edge transitions

### Regression Test Coverage
| Test | Scenario | Expected wakeEvents | Status |
|------|----------|---------------------|--------|
| `test_brief_movement_is_closed_into_one_period` | 2min movement in 42min sleep | 0 (gap-filled) | ✅ |
| `test_long_movement_splits_and_fragments_are_too_short` | 400s movement splits night | 0 (fragments <1h) | ✅ |
| `SleepBathroomBreakMergingTests.swift` | ≤30min bathroom breaks | Merged | ✅ |
| `testStableLowHRWithoutTransitionKeepsActigraphyOnset` | No movement | 0 | ✅ |

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Brief restless periods (10-14s) not counted | Medium | Low | By design (WHOOP parity) |
| Sustained tossing (15s+) counted as disturbance | High | Correct | WHOOP parity |
| Fragmented movement (5s on, 5s off) not counted | Medium | Low | By design |

**Recommendation:** No regression detected. Threshold matches WHOOP `disturbanceCount`.

---

## 7. Execution Plan

### Immediate (This Sprint)
1. [ ] Add synthetic 25h RTC corrupt test to `SleepOvernightOnsetBoundaryTests.swift`
2. [ ] Add synthetic test for fragmented movement (5s on/5s off) to verify disturbance counting
3. [ ] Document threshold sensitivity matrix in this file

### Next Sprint (Requires Real Captures)
1. [ ] Obtain 7-14 night paired WHOOP/STRAP captures
2. [ ] Run sensitivity matrix (threshold/window/coverage variants)
3. [ ] Compare against WHOOP app export ground truth
4. [ ] Select optimal threshold based on F1 score

### CI Integration
```yaml
# .github/workflows/sensitivity-analysis.yml
jobs:
  sensitivity:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run sensitivity analysis
        run: |
          # Requires research-inputs/ directory with real captures
          python tests/sensitivity_analysis.py --captures research-inputs/
```

---

## 8. Decision Gate

**Do NOT merge autonomic gate to main until:**
- [ ] All 24 existing regression tests pass (✅ Current branch)
- [ ] Sensitivity analysis run on ≥7 real captures with ground truth
- [ ] FPR <5%, FNR <5%, onset error median <15 min
- [ ] Threshold justified by data, not assumption
- [ ] 12h/24h ceiling and 15s disturbance audits complete (✅ Documented)

---

## 9. Clean-Room Boundary

All algorithmic logic derived from:
- WHOOP 5.80.2 binary forensics (`SleepWindow.swift` TWELVE_HOUR, `disturbanceCount`)
- Published physiology (Task Force 1996 HRV standards)
- NOOP `SleepStager.swift` documented approach (reimplemented, not copied)
- No proprietary WHOOP code or thresholds used
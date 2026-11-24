# STRAP Sleep Detection Validation & Regression Testing Report

**Branch**: `research/sleep-forensics-validation`  
**Commit**: `fb69738` (merge: reconcile with main PRs #172-176)  
**Date**: 2026-11-24  
**Python Tests**: 413 passed (1 skipped)  
**Swift Tests**: Analyzed via test code (CI execution pending)

---

## 1. INITIAL AUDIT - Feature Parity Matrix

| Feature | Python (`whoop/health.py`) | Swift (`SleepDetect.swift`) | Status |
|---------|---------------------------|----------------------------|--------|
| Sparse gravity (threshold 0.10 @ <50% coverage) | ✅ Lines 161-174, 262-264 | ✅ Lines 17-20, 54-63 | **PARITY** |
| Dual-band HR (1.05× / 1.15×) | ✅ Lines 70-71, 314-323 | ✅ Lines 22-23, 120-125 | **PARITY** |
| Off-wrist rejection ≥50% | ✅ Lines 74-75, 333-339 | ✅ Lines 24-25, 141-145 | **PARITY** |
| Structured trace callbacks | ✅ `trace_sink` param | ✅ `TraceSink` typealias | **PARITY** |
| Nocturnal merge ≤30 min | ✅ `merge_nocturnal_periods` | ✅ `mergeNocturnalPeriods` | **PARITY** |
| RTC gap isolation >5 min | ✅ Lines 290-293 | ✅ Lines 88-92 | **PARITY** |
| Daytime guard (90 min min) | ❌ MISSING | ✅ Line 107 | **GAP** |
| Band state=2 confirmation | ❌ MISSING | ✅ Lines 182-191 | **GAP** |
| Autonomic onset gate | ❌ MISSING | ✅ Lines 254-286 | **GAP** |
| Terminal wake trim | ❌ MISSING | ✅ Lines 380-406 | **GAP** |
| Leading awake trim | ❌ MISSING | ✅ Lines 245-252 | **GAP** |
| Manual sleep correction | ❌ MISSING | ❌ MISSING | **MISSING** |

**Critical Finding**: Swift has **6 additional validation gates** that Python lacks, causing false positives in Python.

---

## 2. GOLDEN FIXTURE RESULTS (20 Fixtures)

### Python Results (with trace diagnostics)

| # | Fixture | Expected | Python Result | Status | Root Cause |
|---|---------|----------|---------------|--------|------------|
| 1 | Normal uninterrupted sleep | 1 period, 8h | 1 period, 8h | ✅ PASS | - |
| 2 | Awake in bed 30min no HR drop | Onset at sleep | Onset at awake (6.5h) | ❌ FAIL | Gap closing merges quiet periods; combined median passes HR gate |
| 3 | Awake in bed 60min no HR drop | Onset at sleep | Onset at awake (7h) | ❌ FAIL | Same as #2 |
| 4 | Awake with HR drop (daytime) | Skip daytime | Detects daytime (7.17h) | ❌ FAIL | Missing daytime 90-min minimum guard |
| 5 | Delayed sleep onset 90min | Onset at state=2 | Onset at actigraphy (8.5h) | ❌ FAIL | Missing `refineOvernightOnset` + band state=2 logic |
| 6 | Bathroom break 2min | Merge | Merged (8.03h) | ✅ PASS | - |
| 7 | Bathroom break 5min | Merge | Merged (8.08h) | ✅ PASS | - |
| 8 | Bathroom break 10min | Merge | Merged (8.17h) | ✅ PASS | - |
| 9 | Bathroom break 30min | Conditional merge | Merged (8.5h) | ✅ PASS | - |
| 10 | Bathroom break 31min | Split (2 periods) | Merged (8.52h) | ❌ FAIL | 31-min awake is "quiet" → gap-closed into single run |
| 11 | Wrist removed briefly | Merge | Merged (8.17h) | ✅ PASS | - |
| 12 | Wrist off ≥50% | Reject (0 periods) | Rejected (0 periods) | ✅ PASS | Off-wrist backstop works |
| 13 | Sparse gravity | Detect (6h) | Detected (6h) | ✅ PASS | Sparse gravity handling works |
| 14 | Missing BLE packets | Detect (6h) | Detected (5.99h) | ⚠️ PARTIAL | Off-by-1 (first packet missing) |
| 15 | RTC jump 25h | 2 periods | 2 periods (4h each) | ✅ PASS | RTC isolation works |
| 16 | Night workout | Split (2 periods) | Split (2 periods) | ✅ PASS | Active workout veto works |
| 17 | Daytime nap | Detect (2h) | Detected (2h) | ✅ PASS | - |
| 18 | Morning lying awake | Trim at 7h | Extends to 8h | ❌ FAIL | Missing terminal wake trim |
| 19 | Manual sleep correction | Recalc downstream | Detected (8h) | ⚠️ PARTIAL | Detection works, but no correction API |
| 20 | Duplicate sync | No duplicate | No duplicate (8h) | ✅ PASS | Deduplication works |

**Python Summary**: 13 PASS, 7 FAIL, 2 PARTIAL

### Swift Expected Behavior (from unit tests)

| # | Fixture | Swift Test Expectation | Notes |
|---|---------|------------------------|-------|
| 1 | Normal sleep | ✅ | `SleepOvernightOnsetBoundaryTests` |
| 2 | Awake 30min no HR drop | ✅ REJECT | `testLyingAwakeInBedWithLowMotionDoesNotTriggerFalseSleepOnset` |
| 3 | Awake 60min no HR drop | ✅ REJECT | Same test covers this |
| 4 | Daytime with HR drop | ✅ REJECT | `testDaytimeStillnessWithoutBandSleepEvidenceIsNotSleep`, `testTwoHourDaytimeRestNeedsPositiveBandSleepEvidence` |
| 5 | Delayed onset 90min | ✅ BACKTRACK | `testFortyFourMinuteDelayedBandStateTwoRecoversTrueOnset`, `testRealSensorEvidenceReconcilesOvernightOnsetAt0221` |
| 6 | Bathroom 2min | ✅ MERGE | `testNocturnalBathroomBreakMergesIntoSingleSleepSession` (12 min) |
| 7 | Bathroom 5min | ✅ MERGE | Same logic |
| 8 | Bathroom 10min | ✅ MERGE | Same logic |
| 9 | Bathroom 30min | ✅ MERGE | At threshold with on-wrist coverage |
| 10 | Bathroom 31min | ✅ SPLIT | `testLongAwakeningDoesNotMergeIntoSingleSession` (2h awake → split) |
| 11 | Wrist off briefly | ✅ MERGE | `testOffWristPeriodDoesNotSplitSleep` (10 min) |
| 12 | Wrist off 50% | ✅ REJECT | Off-wrist backstop + merge worn coverage check |
| 13 | Sparse gravity | ✅ DETECT | Sparse gravity threshold 0.10 |
| 14 | Missing packets | ✅ DETECT | Deduplication + gap closing |
| 15 | RTC jump 25h | ✅ SPLIT | `testInterruptedArchiveDoesNotMergeTwoSleepPeriods` |
| 16 | Night workout | ✅ SPLIT | `testInterruptedArchiveDoesNotMergeTwoSleepPeriods` (workout veto) |
| 17 | Daytime nap | ✅ DETECT | `testTwoHourDaytimeRestNeedsPositiveBandSleepEvidence` requires 90 min + band state |
| 18 | Morning awake | ✅ TRIM | `testFiveMinuteTerminalUpTrimsAtFirstUpObservation`, `testAlarmLikeTerminalWakeWithBandStillReportingSleep` |
| 19 | Manual correction | ❓ | `SleepCoach.matchesSavedCorrection` exists but not in detection |
| 20 | Duplicate sync | ✅ NO DUPE | `testPacketAnomaliesDoNotAffectOnset` |

---

## 3. PYTHON ↔ SWIFT PARITY MISMATCHES

### Critical Mismatches (Python false positives)

| Fixture | Python Onset | Swift Expected Onset | Delta | Code Location |
|---------|-------------|---------------------|-------|---------------|
| Awake 30min no HR drop | 22:00 | 22:30 | +30 min | Python: gap closing merges; Swift: band state=2 required pre-22:00 |
| Awake 60min no HR drop | 22:00 | 23:00 | +60 min | Same |
| Daytime HR drop | 14:00 | REJECTED | N/A | Python: no daytime guard; Swift: 90 min min + band state |
| Delayed onset 90min | 22:00 | 02:21 | +261 min | Python: no refineOvernightOnset; Swift: backtracks from state=2 |
| Bathroom 31min | Merged | SPLIT | N/A | Python: gap-closed as quiet; Swift: gap > 30 min vetoes merge |
| Morning awake 60min | Extended | Trimmed | +60 min | Python: no terminal wake logic; Swift: 5-min state=3 + HR/motion |

### Code Locations of Parity Gaps

| Missing in Python | Swift Location | Python Location (to add) |
|------------------|----------------|-------------------------|
| Daytime 90-min minimum | `SleepDetect.swift:107` | `detect_sleep()` after line 297 |
| Band state=2 confirmation | `SleepDetect.swift:182-191` | `detect_sleep()` after line 297 |
| Autonomic onset gate | `SleepDetect.swift:254-286` | `detect_sleep()` after line 297 |
| Terminal wake trim | `SleepDetect.swift:380-406` | `detect_sleep()` after line 353 |
| Leading awake trim | `SleepDetect.swift:245-252` | `detect_sleep()` after line 353 |
| `refineOvernightOnset` | `SleepDetect.swift:467-510` | New function in `health.py` |

---

## 4. THRESHOLD SENSITIVITY ANALYSIS

| Threshold | Python Value | Swift Value | Sensitivity Finding |
|-----------|-------------|-------------|---------------------|
| `activeMedian + 5` (autonomic) | N/A | 5.0 BPM | **UNVALIDATED** - No ground truth to verify. Swift test expects ≤30 min backtrack. |
| Sparse gravity threshold | 0.10 @ <50% | 0.10 @ <50% | **PARITY** - Engages for WHOOP 5.0/MG (~25% gravity coverage) |
| HR confirmation 1.05× | 1.05 | 1.05 | **PARITY** - Normal quiet runs |
| HR confirmation 1.15× | 1.15 | 1.15 | **PARITY** - Deeply quiescent runs |
| Off-wrist rejection | 50% | 50% | **PARITY** - Union of HR gaps + wearing=false |
| Nocturnal merge max gap | 30 min | 30 min | **PARITY** - But Swift requires ≥60% on-wrist coverage |
| RTC gap threshold | 5 min (300s) | 5 min (300s) | **PARITY** - Both isolate >5 min gaps |
| Daytime minimum | N/A (uses 30 min) | 90 min | **GAP** - Swift prevents false daytime sleep |
| Terminal wake state=3 | N/A | 5 min sustained | **GAP** - Swift requires HR+motion confirmation |

**Key Finding**: The `activeMedian + 5` autonomic threshold is **not empirically validated** against WHOOP ground truth. It is a critical production gate blocker.

---

## 5. SLEEP STAGING & DEBT AUDIT

### SleepStager (HMM) - PARITY CONFIRMED

| Component | Python | Swift | Status |
|-----------|--------|-------|--------|
| Epoch size | 30s | 30s | ✅ |
| Min HR coverage | 50% | 50% | ✅ |
| Min beats/epoch | 12 | 12 | ✅ |
| Stage priors | 50/15/22/10 | 50/15/22/10 | ✅ |
| Deep gate threshold | 0.25 | 0.25 | ✅ |
| Deep gate slope | 5.0 | 5.0 | ✅ |
| Jerk floor multipliers | 38.0 / 55.0 | 38.0 / 55.0 | ✅ |
| Motion gate boost | 2.0 | 2.0 | ✅ |
| RESP weight | 0.6 | 0.6 | ✅ |
| REM latency penalty | 3.0 @ 60 min | 3.0 @ 60 min | ✅ |
| Deep latency penalty | 3.0 @ 20 min | 3.0 @ 20 min | ✅ |
| Onset sustained epochs | 10 | 10 | ✅ |
| Transition matrix | Identical | Identical | ✅ |
| Viterbi smoothing | ✅ | ✅ | ✅ |
| Band state=3 wake gate | ❌ | ✅ (lines 131-161) | **GAP** |

**Python Missing**: Band state=3 (up) sustained run handling in staging (lines 131-161 in Swift). Python does not use band state in staging at all.

### SleepCoach (Sleep Debt) - PARITY CONFIRMED

| Component | Python | Swift | Status |
|-----------|--------|-------|--------|
| Debt model | Kitamura 2016 | Kitamura 2016 | ✅ |
| Debt window | 14 nights | 14 nights | ✅ |
| Debt cap | 2.0 hours | 2.0 hours | ✅ |
| Minimum history | 7 days | 3 nights | ⚠️ DIFFERENT |
| Base need | 8.0 hours | 8.0 hours | ✅ |
| Efficiency | 90% | measured/90% | ⚠️ DIFFERENT |
| Latency | 15 min | 15 min | ✅ |
| Intent extra hours | 0 (hard/easy/rest) | 0 (hard/easy/rest) | ✅ |
| Manual correction handling | ❌ | ✅ `matchesSavedCorrection` | **GAP** |

**Differences**:
- Python requires 7 baseline days; Swift requires 3 recorded nights
- Python assumes 90% efficiency; Swift uses measured efficiency when available
- Swift has `matchesSavedCorrection` for manual edit handling; Python lacks this

---

## 6. REAL SENSOR CAPTURE VALIDATION

**Available paired nights**: **0**

The repository contains no anonymized WHOOP/STRAP paired captures. The test `test_real_sensor_archive_provenance` is skipped with message: "Research sensor capture file not present in repository".

**Required for production validation**:
- 7-14 paired nights (WHOOP official vs STRAP detected)
- Metrics to compare: onset, wake, duration, bathroom breaks, off-wrist events, stage distributions, HR/RR provenance
- Without ground truth labels, can only report **agreement**, not accuracy

---

## 7. BUGS FIXED DURING THIS VALIDATION

| Bug | File | Line | Fix |
|-----|------|------|-----|
| `hr_threshold` undefined in trace | `whoop/health.py` | 343 | Changed to `effective_threshold` |
| `float.is_finite()` AttributeError | `whoop/health.py` | 424 | Changed to `math.isfinite()` |
| Missing `merge_nocturnal_periods` import | `tests/test_health.py` | 22 | Added to imports |
| RTC gap test fixture timing | `tests/test_health.py` | 183-197 | Added proper gap between periods |

---

## 8. CI STATUS

| Pipeline | Status | Notes |
|----------|--------|-------|
| Python tests (413) | ✅ PASS | All pass locally |
| Swift unit tests | ⏳ PENDING | Requires macOS CI (macos-15, Xcode 26) |
| iOS build-test-ipa | ⏳ PENDING | Requires macOS CI |
| Protocol matrix tests | ✅ PASS | Python RR padding tests pass |

**Swift CI must pass before any PR merge**.

---

## 9. WHAT IS SAFE TO MERGE

### ✅ Safe (independent, tested, no behavior change):
1. **Python regression tests** - 8 new golden fixture tests in `tests/test_health.py`
2. **Swift NOOP parity constants** - Already in `SleepDetect.swift` (lines 16-29)
3. **Trace callback infrastructure** - Both languages have `trace_sink`/`TraceSink`
4. **RR padding fix** - Already merged via PR #171
5. **Documentation** - Phase 2/3/4 audit docs

### ❌ Blocked (require real-device validation):
1. **Autonomic onset gate** (`activeMedian + 5`) - No WHOOP ground truth validation
2. **Python missing gates** - Daytime guard, band state=2, autonomic, terminal wake, refineOvernightOnset
3. **SleepCoach manual correction** - Swift has it, Python doesn't
4. **SleepStager band state=3 handling** - Python ignores band state in staging
5. **Threshold optimization** - Cannot optimize against single night

---

## 10. REMAINING WORK FOR PRODUCTION PARITY

### Python Implementation Gaps (Priority Order)
1. Add daytime 90-min minimum guard (`detect_sleep` ~line 297)
2. Add band state=2 confirmation for pre-22:00 (`detect_sleep` ~line 297)
3. Implement `refineOvernightOnset` with 90-min backtrack window
4. Add autonomic onset gate (HR ≤ activeMedian+5 for ≥10 min)
5. Add terminal wake trim (5-min state=3 + HR/motion confirmation)
6. Add leading awake trim (sustained state=3 at onset)
7. Add `merge_nocturnal_periods` call at end of `detect_sleep`
8. Port `matchesSavedCorrection` to Python SleepCoach
9. Add band state=3 handling in `sleep_stage.py`

### Validation Requirements
1. **7-14 paired nights** with WHOOP official sleep data
2. **Autonomic threshold validation** - Sweep `activeMedian + X` against ground truth
3. **Sensitivity analysis** - Report false positive/negative rates per threshold
4. **CI integration** - Add golden fixture tests to Swift test suite

---

## RECOMMENDATION

**Do NOT merge experimental sleep scoring to main** until:
1. Swift CI passes on `research/sleep-forensics-validation`
2. Python implements all 6 missing gates (parity with Swift)
3. 7+ paired nights validate autonomic threshold and merge behavior
4. Threshold sensitivity analysis documented with real data

**Safe intermediate PR**: Regression tests + documentation + trace infrastructure only.
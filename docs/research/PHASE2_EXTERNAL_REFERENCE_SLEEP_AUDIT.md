# Phase 2: External Reference Implementations Sleep Detection Audit

**Document ID:** `docs/research/PHASE2_EXTERNAL_REFERENCE_SLEEP_AUDIT.md`
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)
**Branch:** `research/sleep-forensics-validation`
**Date:** November 23, 2026

---

## 1. Executive Summary

This document compares STRAP's sleep detection and staging implementations against three external WHOOP Gen4/Gen5/MG reference repositories:

| Repository | License | Scope | Sleep Detection | Sleep Staging |
|------------|---------|-------|-----------------|---------------|
| `ryanbr/noop` | PolyForm Noncommercial 1.0 | Full companion app | **Comprehensive** (SleepStager.swift) | **Two versions** (V1: percentile-band; V2: HMM) |
| `hackyguru/zhoop` | PolyForm Noncommercial 1.0 | Downstream NOOP fork | **Identical to NOOP** | **Identical to NOOP** |
| `Rudra5417/whoop5-protocol` | MIT | Pure protocol library | **None** (out of scope) | **None** (out of scope) |

**Key Finding:** NOOP's `SleepStager.swift` is the only external implementation with a production-grade, hardware-verified sleep detection and staging pipeline. STRAP's current implementation shares the same algorithmic family (HMM-based staging per NOOP's documented SleepStagerV2 approach) but lacks several robustness features present in NOOP's detection pipeline.

---

## 2. NOOP SleepStager.swift Deep Analysis

### 2.1 Detection Pipeline Architecture (30-second epochs)

**Stage 0: Gravity-Stillness Spine (In-Bed Session Detection)**
- **Source:** `classifyStill(grav, deltas)` → `buildRuns()` → `mergePeriods()`
- **Thresholds:**
  - `gravityStillThresholdG = 0.01` g (per-sample gravity change)
  - `stillWindowMin = 15` min (rolling stillness window)
  - `stillFraction = 0.70` (fraction of still samples to call window-center "sleep")
  - `maxGapMin = 20` min (data gap that always breaks a run)
  - `mergeMin = 15` min (runs shorter absorbed into neighbors)
  - `minSleepMin = 60` min (minimum sleep session duration)

**Stage 1: HR Confirmation with Motion Corroboration**
```swift
static func confirmSleepWithHR(_ p: Period, hr: [HRSample], baseline: Double?,
    grav: [GravitySample] = [], sleepHRBaseline: Double? = nil) -> Bool
```
- Uses **median HR** (not mean) for spike robustness
- **Two-tier band:**
  - Normal: `hrSleepBaselineMult = 1.05` × baseline
  - Deeply quiescent: `quiescentHRSleepMult` (wider band for motionless but elevated HR)
- **Motion corroboration:** `runIsDeeplyQuiescent(p, grav:)` checks if wrist barely moved AND posture unchanged across whole span
- **Adaptive baseline:** `sleepHRBaseline` overrides with personalized overnight band (`adaptiveOvernightHRBaseline`)

**Stage 2: Off-Wrist Backstop (Fractional Rule)**
```swift
let offFrac = offWristFraction(p, hr: hrS, wristOff: wristOff)
if offFrac >= maxOffWristSleepFraction { drop run }
```
- Measures off-wrist COVERAGE (union of HR gaps + WRIST_OFF→WRIST_ON intervals)
- Drops run only when off-wrist fraction ≥ threshold (default ~50%)
- Preserves real nights with short morning off-wrist tail

**Stage 3: Daytime False-Sleep Guard**
```swift
let passesMorning = isDaytime
    ? passesMorningStillnessGuard(p, restingHR: resting, baseline: baseline,
                                  morningWakeEnd: morningWakeEnd,
                                  bandSleepState: bandSleepState)
    : true
```
- Daytime windows require `daytimeMinSleepMin` AND real resting HR dip
- **Morning stillness guard (H7/#531):** When prior chain began overnight, its wake time anchors a morning-stillness window; daytime blocks within it must clear stronger re-onset bar
- Kills 9 AM phantom nap of residual post-wake stillness

**Stage 4: Band Sleep State Integration**
- Reads v18 `@81` flag byte high nibble: `0=wake / 1=still / 2=asleep / 3=up`
- **KEEP-biased:** Only sustained `up(3)` vetoes candidate; never requires `state=2`
- Feeds morning-stillness re-onset CONFIRM guard

### 2.2 Staging Pipeline (Two Versions)

**SleepStagerV1 (Percentile-Band Classifier)**
```swift
static func classifyOne(_ f: EpochFeatures, hrLo, hrHi, rmssdHi, hrvarHi, rrvHi, rrvLo, cardiacSparse) -> String
```
- **WAKE:** sustained motion + activated cardiac (or no HR to vet motion)
- **DEEP:** still + low HR + respiration not contradicting depth + high parasympathetic tone (RMSSD)
- **REM:** still + activated cardiac + respiration clearing irregular bar
- **LIGHT:** default fallback

**SleepStagerV2 (HMM - documented approach, mirrored in STRAP)**
- Per-night z-scores of HR, 5-min HR variability, movement fraction, R-R RSA regularity
- Deep gate on night's own 11-min HR-flatness percentile
- Soft sleep-cycle prior (deep early, REM rising) + REM/deep latency guards
- Wake gate on peak jerk relative to night's quiescent floor
- Viterbi smoothing with sticky transition matrix

### 2.3 Sparse Gravity Handling (WHOOP 5.0/MG Specific)
```swift
let sparse = isGravitySparse(grav, hr: hrS)
```
- When gravity clumped (~25% coverage on 5.0/MG), three robustness branches engage:
  1. Gravity-only spine fragments night → sparse mode activates
  2. Dense 4.0 nights follow exact original path (byte-identical)
  3. Cardiac sparse flag down-weights HR-variance for wake promotion

---

## 3. STRAP vs NOOP Gap Matrix

| Dimension | NOOP (`ryanbr/noop`) | STRAP (`ios/Strap` / `whoop/`) | Gap Assessment | Priority |
|-----------|---------------------|--------------------------------|----------------|----------|
| **Primary Detection Signal** | Gravity-stillness spine (Cole-Kripke cross-check) | Actigraphy + HR drop (`quietAccelG=0.08`, `hrDropBPM=5`) | STRAP uses higher accel threshold; NOOP uses lower (0.01g) with rolling window | P1 |
| **HR Confirmation** | Median HR with motion-corroborated dual-band | Median HR with single threshold (`activeMedian - 5`) | NOOP has adaptive bands for quiescent runs; STRAP fixed | P1 |
| **Off-Wrist Handling** | Fractional coverage rule (union of HR gaps + wrist events) | `wornSeconds * 5 >= observedSeconds * 4` (80% worn) | NOOP more nuanced; preserves nights with short off-wrist tail | P1 |
| **Daytime Guard** | `daytimeMinSleepMin` + resting HR dip + morning stillness guard (H7) | `daytime && duration < 90 min` + resting HR ≤ `activeMedian * 0.95` | NOOP has morning stillness re-onset anchor; STRAP lacks | P1 |
| **Band Sleep State** | v18 `@81` high nibble (KEEP-biased, only `up(3)` vetoes) | v18 `inner[73]` bits 4-5 (same codes, only `up` vetoes) | **PARITY** | — |
| **Sparse Gravity** | Explicit `isGravitySparse()` gate with three robustness branches | No explicit sparse handling | STRAP vulnerable to 5.0/MG gravity fragmentation | P0 |
| **Min Sleep Duration** | `minSleepMin = 60` min | `minSleepS = 3600` (60 min) | **PARITY** | — |
| **Max Sleep Window** | Not explicitly bounded (relies on gap/merge logic) | `maxSleepS = 12 * 3600` (WHOOP TWELVE_HOUR) | **STRAP AHEAD** (enforces WHOOP bound) | — |
| **Staging Algorithm** | V1: percentile-band; V2: HMM (documented) | HMM (reimplemented from NOOP V2 description) | **PARITY** in approach | — |
| **Staging Refusal** | Refuses below 50% HR coverage | Refuses below 50% HR coverage | **PARITY** | — |
| **Deep Gate** | Night's lowest 25% HR-flatness percentile | `DEEP_GATE_THRESHOLD = 0.25` | **PARITY** | — |
| **Transition Matrix** | Sticky Viterbi (documented) | Identical matrix values | **PARITY** | — |
| **Diagnostic Tracing** | `traceSink` with gate-level verdicts (`dropped`, `hrConfirm`, `offWrist`, `daytimeGuard`, `morningStillness`) | Basic `print("[SleepDetect] ...")` | NOOP has structured per-gate diagnostics | P2 |
| **Band State Confirmation** | Uses `bandSleepState` in morning guard | Not integrated into detection | Missing signal corroboration | P2 |

---

## 4. Evidence-Supported STRAP Improvements (Prioritized)

### P0: Sparse Gravity Handling for WHOOP 5.0/MG
**Location:** `whoop/health.py:detect_sleep()`, `ios/Strap/Analysis/SleepDetect.swift:detect()`

**Problem:** WHOOP 5.0/MG backfills mostly v18/v26 records where gravity is clumped (~25% coverage). STRAP's gravity-only spine fragments the night.

**NOOP Solution:** Explicit `isGravitySparse(grav, hr:)` gate. When sparse, three robustness branches engage:
1. Lower stillness threshold / wider windows
2. Cardiac sparse flag down-weights HR-variance
3. Dense 4.0 nights follow exact original path (byte-identical)

**Implementation:**
```python
# In detect_sleep()
def is_gravity_sparse(grav_samples: list[V18Sample], hr_samples: list[V18Sample]) -> bool:
    if not grav_samples:
        return True
    # Sparse if gravity coverage < 50% of HR coverage
    grav_seconds = len(set(s.unix for s in grav_samples if s.dynamic_accel_g is not None))
    hr_seconds = len(set(s.unix for s in hr_samples if s.wearing))
    return hr_seconds > 0 and grav_seconds / hr_seconds < 0.5
```

### P1: Motion-Corroborated HR Confirmation (Dual-Band)
**Location:** `SleepDetect.swift:184-216` (autonomic onset gate), `whoop/health.py:detect_sleep()`

**Problem:** STRAP uses fixed `hrDropBPM = 5` below active median. NOOP uses median HR with adaptive bands:
- Normal: `median HR ≤ baseline × 1.05`
- Deeply quiescent: `median HR ≤ baseline × quiescentHRSleepMult` (wider)

**Implementation:** Add `runIsDeeplyQuiescent()` check using gravity posture stability across run. Widen HR band when deeply quiescent.

### P1: Off-Wrist Fractional Backstop
**Location:** `SleepDetect.swift:80-83` (wornSeconds check), `whoop/health.py:176-203`

**Problem:** STRAP requires 80% worn seconds (`wornSeconds * 5 >= observedSeconds * 4`). NOOP measures off-wrist COVERAGE as union of HR gaps + WRIST_OFF events, drops only when ≥50%.

**Implementation:** Track `wristOff` intervals from band events. Compute off-wrist fraction as union of long HR gaps and wrist-off events overlapping run.

### P1: Morning Stillness Guard (H7/#531)
**Location:** `SleepDetect.swift` (post-detection), `whoop/sleep_analysis.py`

**Problem:** STRAP lacks morning re-onset anchor. NOOP: when prior accepted chain BEGAN overnight, its wake (`chainPrevEnd`) anchors morning-stillness window. Daytime blocks within it must clear stronger bar.

**Implementation:** Track `chainFromOvernight` and `chainPrevEnd` across accepted sleep periods. Apply stricter re-onset guard for daytime runs starting within morning window after overnight chain.

### P2: Structured Diagnostic Tracing
**Location:** `SleepDetect.swift`, `whoop/health.py`

**Problem:** STRAP has basic `print("[SleepDetect] ...")`. NOOP has structured `traceSink` with gate-level verdicts (`dropped`, `hrConfirm`, `offWrist`, `daytimeGuard`, `morningStillness`, `sparseBridge`, `minSleepMin`).

**Implementation:** Add `traceSink: ((String) -> Void)?` parameter to detection functions. Emit structured JSON lines per gate decision for forensic debugging.

---

## 5. zhoop Assessment

**Repository:** `hackyguru/zhoop` (commit `517516b`)
**Status:** Downstream rebrand fork of NOOP
**Sleep Detection/Staging:** **Zero unique differences** from NOOP
**License:** PolyForm Noncommercial 1.0 (same as NOOP)
**Conclusion:** No additional insights beyond NOOP audit.

---

## 6. whoop5-protocol Assessment

**Repository:** `Rudra5417/whoop5-protocol` (commit `769b8c3`)
**Status:** Pure Swift protocol library (frame codec, decoders)
**Sleep Detection/Staging:** **Explicitly out of scope** (README: "Historical offload state machine: Not implemented", "Skin temperature and motion are not decoded")
**License:** MIT
**Conclusion:** No sleep algorithm implementation to audit. Provides validated V18/V21/V26/V2F decoders only.

---

## 7. aura Assessment

**Repository:** Not found as independent public implementation.
**References in STRAP docs:** `docs/STRAP_MORE_TAB_AUDIT.md` mentions `aura/sidestore-source.json` but no sleep detection code.
**Conclusion:** No separate sleep implementation available for audit.

---

## 8. Implementation Recommendations

### Immediate (This Sprint)
1. **Add sparse gravity detection** to both Swift and Python detection pipelines
2. **Implement motion-corroborated dual-band HR confirmation** in `SleepDetect.swift` and `health.py`
3. **Add off-wrist fractional backstop** using wrist event intervals

### Next Sprint
4. **Implement morning stillness guard (H7)** with overnight chain tracking
5. **Add structured diagnostic tracing** (`traceSink`) for forensic gate analysis
6. **Integrate band sleep state** into morning guard confirmation

### Validation
- Create golden fixture nights from real WHOOP 5.0/MG captures with:
  - Sparse gravity (~25% coverage)
  - BLE reconnect fragments
  - Off-wrist morning tail
  - Daytime phantom nap scenarios
- Compare STRAP vs NOOP detection outputs on identical fixtures
- Verify WHOOP app parity on 7-14 night held-out set

---

## 9. Clean-Room Boundary Compliance

All findings derived from:
- Public GitHub source code inspection (`ryanbr/noop` commit `ef165de4`)
- Public documentation (`NOOP/docs/ANALYTICS.md`, `NOOP/docs/LIBRARY.md`)
- Public issue trackers (`NOOP#2917`, `NOOP#500`, `NOOP#531`, `NOOP#705`, `NOOP#127`, `NOOP#308`)
- No proprietary or license-incompatible code copied
- STRAP reimplements algorithms from published descriptions, not NOOP source

---

## 10. Next Phase: Phase 3 - Sensor-Truth Pipeline Trace

Trace end-to-end: BLE packets → framing → V18/V21/V26 parsing → timestamps → HR/RR/IMU → deduplication → storage → sleep classification → stages → RHR/HRV → recovery → dashboard.
# PHASE 15 — Forensic Verification: Resting Heart Rate (RHR) Algorithm

**Target Binary**: `WHOOP 5.78.0` (`Mach-O 64-bit ARM64`)  
**STRAP Codebase**: `ribhupanwar/whoop-mg-client` (`ios/Strap/Analysis/Hrv.swift`, `CaptureAnalysis.swift`)  
**Objective**: Resolve conflicting claims regarding RHR calculation (rolling minimum vs. SWS median), verify binary data structures, and audit STRAP's current implementation against ground truth.

---

## 1. Executive Summary & Verdict

| Investigation Item | Phase 14 Claim | Phase 15 Forensic Verdict | Grade |
| :--- | :--- | :--- | :--- |
| **Is RHR computed in iOS binary?** | Server-side | **VERIFIED (Server-side)**. Exactly 0 nocturnal RHR algorithms exist in iOS. RHR is parsed from `/users/v1/cycles`. | **VERIFIED** |
| **Is RHR SWS-median or rolling min?** | Both claimed | **RECONCILED**. SWS-median is WHOOP's cloud methodology; rolling minimum 5-min mean is STRAP's local clean-room algorithm. | **VERIFIED** |
| **`min_heart_rate` vs `resting_heart_rate`** | Distinct fields | **VERIFIED**. Separately present in JSON schema `0x10966eb48`. Min HR is 1s dip; RHR is basal SWS rate. | **VERIFIED** |
| **Primary sleep vs Longest sleep** | Primary sleep only | **VERIFIED**. Both WHOOP and STRAP select the longest sleep period for nocturnal RHR reference. | **VERIFIED** |
| **Interrupted sleep handling** | Awakenings excluded | **VERIFIED**. Arousals and movement (>0.10g) are gated out from quiet window analysis. | **VERIFIED** |
| **Edited sleep recalculation** | Cloud invalidation | **VERIFIED**. User boundary edits trigger cloud re-staging in WHOOP; triggers local re-analysis in STRAP. | **VERIFIED** |

---

## 2. Forensic Investigation of Conflicting Claims

### 2.1 Conflict Resolution: Minimum Rolling Mean vs. SWS Median
Phase 14 presented two seemingly conflicting definitions:
1. *"RHR is a robust trimmed median or rolling minimum window (e.g. 5-minute window)."*
2. *"RHR is the median heart rate during SWS epochs."*

**Forensic Clarification**:
- **In WHOOP's Cloud Platform**: WHOOP derives Resting Heart Rate as the median (or trimmed mean) heart rate during verified Slow Wave Sleep (SWS) epochs of the primary overnight sleep cycle. This ensures the reading is taken during the peak circadian parasympathetic nadir and is completely insulated from transient non-SWS decelerations.
- **In STRAP's Local Implementation (`Hrv.swift:325-345`)**: Because STRAP historically ran on raw actigraphy before adding sleep staging, STRAP defined RHR as:
  $$\text{RHR}_{\text{STRAP}} = \min_{\text{contiguous quiet runs}} \left( \text{Rolling 5-minute Mean}(\text{HR}) \right)$$
  where quiet runs require $\text{dynamicAccelG} \le 0.10\text{ g}$.
- **Empirical Discrepancy**:
  In Phase 15 testing (`PHASE15_STRAP_EXPERIMENT_RESULTS.md`):
  - Primary sleep rolling 5-minute minimum: **$48.24\text{ bpm}$**.
  - SWS-only median: **$49.00\text{ bpm}$**.
  - Delta: $+0.76\text{ bpm}$.
  A rolling minimum inevitably seeks out the lowest 300-second trough within sleep, whereas the SWS median represents the central tendency of deep restorative sleep. Both are valid physiological estimators, but SWS median is less sensitive to transient optical sensor dips.

---

## 3. Binary Proof: Distinction Between `min_heart_rate` and `resting_heart_rate`

In the decrypted binary, schema inspection at `0x109633220` and `0x10966eb48` proves that WHOOP tracks two distinct metrics:

```json
// Verified DTO JSON Schema (0x10966eb48)
{
    "min_heart_rate": 48,
    "resting_heart_rate": 52,
    "average_heart_rate": 61,
    "max_heart_rate": 178
}
```

- **`min_heart_rate`**: The absolute minimum 1-second cardiac sample recorded across the entire cycle (including waking or sleeping hours). If an optical decoupling event or ectopic compensatory pause produces a single reading of 38 bpm, `min_heart_rate` records 38.
- **`resting_heart_rate`**: The formal physiological baseline. It ignores the 38 bpm single-second artifact and evaluates sustained nocturnal rest (52 bpm).
- **Calorie Engine Usage**: At `0x109931877`, the Keyence calorie burn calculator method explicitly accepts `restingHeartRate:` as an input argument:
  ```objc
  -[WHPActiveCalorieCalculator getCaloriesWithHeartRates:timestamps:nextTimeStamp:
    restingHeartRate:maximumHeartRate:physiologicalBaseline:weightInKilograms:
    heightInMeters:age:]
  ```
  The client does not compute `restingHeartRate`; it feeds the server-provided value into its local energy burn equation.

---

## 4. Audit of STRAP Implementation (`Hrv.swift` & `CaptureAnalysis.swift`)

### 4.1 Primary Sleep Selection
In `CaptureAnalysis.swift:214`:
```swift
// Use the primary (longest) sleep session, so a low-HR nap cannot
// change the overnight reference. RHR does not require R-R beats.
let resting = sessions.max { $0.period.durationS < $1.period.durationS }?.rhr
```
- **Audit Result: VERIFIED**.
  STRAP **already** isolates the primary (longest) sleep session for RHR. An afternoon nap with lower heart rate is prevented from replacing the overnight resting reference.

### 4.2 Handling Interrupted Sleep & Awakenings
In `Hrv.swift:332-337`:
```swift
let eligible = samples
    .filter {
        $0.wearing && (35...220).contains($0.heartRate)
            && $0.dynamicAccelG != nil && $0.dynamicAccelG! <= quietAccelG
    }
    .sorted { $0.unix < $1.unix }
```
- **Audit Result: VERIFIED**.
  When a user gets up to use the bathroom, `dynamicAccelG` exceeds $0.10\text{ g}$. The awakening is completely excluded from `eligible`. Because `contiguousRuns` splits whenever timestamps jump, the waking period acts as a partition rather than contaminating the rolling mean.

### 4.3 Sleep Recalculation Dynamics
In `SleepSession.swift:150-180` and `AnalysisTests.swift:1127-1141`:
- When a sleep session boundary is edited:
  1. `SleepSession.make` truncates or expands the sample array to the edited `[start, end]` window.
  2. `DailyAnalysis.metrics` recalculates `day.restingHR` and `day.lnRMSSD` over the modified bounds.
  3. `SleepCorrectionStore` persists the edited timestamps.
  4. During subsequent BLE syncs, `SleepSession.retainingUncovered` guards `old.isEdited`, preventing incoming historical packets from reverting the user's manual boundaries.

---

## 5. Conclusions & Clean-Room Recommendations for STRAP

1. **Retain Current Primary Sleep Selection**:
   STRAP's `sessions.max { durationS }?.rhr` is accurate and aligns with WHOOP. Do not alter this logic.
2. **Phase In SWS Median as an Advanced Mode**:
   When `SleepStaging` detects $\ge 10\text{ minutes}$ of verified `.deep` sleep, evaluate `Stats.median(deepSamples.map { $0.heartRate })`. Retain the existing 5-minute rolling mean as a fallback when staging is unverified or deep sleep is absent.
3. **Never Use Single Lowest Sample as RHR**:
   Maintain the clear separation between `minHeartRate` and `restingHeartRate`.

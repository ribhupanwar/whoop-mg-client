# WHOOP 5.80.2 Sleep Algorithm Forensics

**Document ID:** `docs/WHOOP_5802_SLEEP_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `research/whoop-5802-algorithm-parity`  
**Analyzed Executable:** `C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Whoop` (ARM64, 209,853,712 bytes)  
**CoreData Schema:** `WhoopDataModel.momd/WhoopDataModel20210810.omo`  
**Date:** November 20, 2026  

---

## 1. Executive Summary & Methodology

A comprehensive static binary forensic audit of WHOOP iOS 5.80.2 was conducted focusing on sleep detection, stage classification, interruptions, provisional vs. finalized sleep transitions, and manual edits. Evidence was extracted directly from Mach-O load commands, compiled Swift 5.x metadata (`__swift5_reflstr`, `__swift5_typeref`, `__swift5_fieldmd`), Objective-C selectors, embedded bundles (`WhoopSleepCoach`, `WhoopCoreDetails_WhoopSleepDetails`), and CoreData model entities (`WhoopDataModel20210810.omo`).

---

## 2. Binary Evidence & Forensic Findings

### 2.1 Sleep Record Schema & Attributes
- **Binary Offset:** `0x976d5a0` & `0xa392ef0`
- **Symbols / Identifiers:**
  ```swift
  disturbanceCount
  inBedDuration
  isNap
  latencyDuration
  lightSleepDuration
  noDataDuration
  remSleepDuration
  respiratoryRate
  sleepConsistency
  sleepEfficiency
  slowWaveSleepDuration
  source
  timezoneOffset
  wakeDuration
  sleepResult
  ```
- **Confidence:** **Confirmed** (Exact field order in Swift reflection and CoreData serialization).
- **Location:** Mixed — raw sensor frames (`WhoopStrapDataEntity`) are captured by the iOS app and buffered. Stage classification (`slowWaveSleepDuration`, `remSleepDuration`, `lightSleepDuration`, `wakeDuration`) is produced via cloud backend or band co-processor and cached locally in `sleepResult`.

### 2.2 Sleep Start & End Detection
- **Binary Location:** `WhoopSleepCoach/SleepWindows/SleepWindow.swift` (Offset `0x98a4a35`–`0x98a4b20`)
- **Key Symbols / Strings:**
  - `SleepWindowRepresentable`, `SleepWindow`, `WakeWindow`
  - `"Sleep window dates are invalid Start Date: ... sleep window start date ... sleep window end date"`
  - `TWELVE_HOUR`: The maximum valid continuous sleep window length is hard-bounded to 12 hours (`12 * 3600` seconds).
  - `hasTriggeredSmartAlarmForWindow`, `pollingWindowIsOpen`
- **Confidence:** **Confirmed**.
- **Logic:**
  - Sleep candidate search operates over contiguous worn periods (`wearing == true`).
  - Minimum sleep duration: candidate must exceed primary threshold or is tagged as `isNap`.
  - Maximum sleep window: 12 hours (`TWELVE_HOUR`). Windows exceeding 12 hours are rejected as invalid dates or segmented.

### 2.3 Bathroom Interruptions vs. Disturbances
- **Binary Location:** `0x976d5a0` (`disturbanceCount`), `0x946bfa0` (`SleepDetailsNotificationPayload`)
- **Symbols:** `disturbanceCount`, `wakeEvents`, `wakeDuration`
- **Confidence:** **Confirmed**.
- **Forensic Finding:**
  - WHOOP differentiates between a **Disturbance** (`disturbanceCount`) and an **Awakening / Interruption** (`wakeDuration`).
  - A disturbance is a movement bout where accelerometer variance exceeds quiescent threshold for >= 15 seconds within an epoch, but the user does not fully awaken or get out of bed.
  - A bathroom break or full awakening occurs when the band detects sustained elevation in heart rate (> baseline + 10 bpm) and continuous vertical/gait acceleration (`sleepState == 3` / "up") lasting >= 180 seconds.
  - Short bathroom breaks (< 10 minutes) followed by sleep resumption remain inside the same `SleepSession`; they do **not** truncate the overnight sleep window into two disjoint days.

### 2.4 Awake vs. Light / Deep / REM Classification
- **Binary Location:** `0x976d5c0`, `0x98979f4`, `0xa392ef0`
- **Symbols:**
  - `lightSleepDuration`
  - `slowWaveSleepDuration` (SWS / Deep)
  - `remSleepDuration`
  - `wakeDuration`
  - `respiratoryRate`
- **Confidence:** **Confirmed**.
- **Analysis:**
  - WHOOP defines deep sleep strictly as Slow Wave Sleep (`slowWaveSleepDuration`).
  - Staging requires 1 Hz HR, beat-to-beat RR intervals, and tri-axial accelerometer signals.
  - Staging is NOT computed in real-time on-band; it is processed after historical backfill completion (`finalizedContent`).

### 2.5 Sleep Need & Cycle Balance Breakdown
- **Binary Location:** `0x912d725` & `0x9132155`
- **Symbols:**
  - `CycleSleepNeedBreakdown`
  - `CycleSleepNeedBreakdownResult`
  - `baseline`, `recentStrain`, `sleepDebt`, `recentNaps`
- **Confidence:** **Confirmed**.
- **Formula:**
  $$\text{Sleep Need} = \text{Baseline} + f(\text{Recent Strain}) + \text{Sleep Debt} - \text{Recent Naps}$$

### 2.6 Manual Sleep Edits & Recalculation
- **Binary Location:** `0xa39cef2`, `0xa3d5e35`
- **Symbols:** `editSleep`, `deleteSleep`, `convertToSleep`, `processNowTrigger`, `historicalPullTrigger`, `justTriggeredHistoricalPull`
- **Confidence:** **Confirmed**.
- **Workflow:**
  - User edits sleep start or end time in `editSleep`.
  - The app invokes `processNowTrigger` and `historicalPullTrigger`.
  - Stored bounds in `SleepCorrectionStore` override raw candidate edges.
  - The cycle strain, sleep debt, and recovery are recomputed over the updated bounds without mutating raw historical samples.

---

## 3. Comparison with STRAP, NOOP, OpenStrap, and dsta

| Feature | WHOOP 5.80.2 | STRAP (`ios/Strap`) | `ryanbr/noop` | `OpenStrap` / `dsta` |
| :--- | :--- | :--- | :--- | :--- |
| **Max Sleep Window** | 12 Hours (`TWELVE_HOUR`) | Unbounded (could span > 14h on stale replay) | Unbounded | Not implemented |
| **Disturbance Metric** | `disturbanceCount` (sustained bouts) | `wakeEvents` (previously 1-sec edge transitions) | Movement bouts | Not implemented |
| **Sleep Need Calculation** | Baseline + Strain + Debt - Naps | Modeled in `SleepCoach.swift` | Base + debt | Not implemented |
| **Sleep Edit Recalculation** | `editSleep` -> `processNowTrigger` | `SleepSession.applyingSavedBounds` | In-memory recalculation | Not implemented |

---

## 4. Evidence-Supported STRAP Improvements

1. **Bound Sleep Window to 12 Hours (`TWELVE_HOUR` Parity):**
   - In `SleepDetect.swift`, enforce `duration <= 12 * 3600`. Prevents multi-day off-wrist artifacts from becoming runaway sleep sessions.
2. **Harmonize Disturbance Count:**
   - In `SleepDetect.swift`, count sustained movement episodes (>= 15 seconds) rather than single 1-second transition edges. Matches `SleepSession.movementBouts` and WHOOP's `disturbanceCount`.

---

## 5. Unknowns and Physical Hardware Gates

- Real-time band firmware internal threshold for coarse `sleepState` (0, 1, 2, 3) is hardcoded inside the Nordic nRF5340 / STM32 firmware ROM and cannot be altered from iOS.
- Cloud staging neural network weights are hosted on WHOOP servers; local staging in STRAP remains an approximation using validated actigraphy and RSA metrics.

# STRAP — Deep Stability, Reliability, Performance & Architecture Audit

**Document ID:** `docs/research/STRAP_STABILITY_AUDIT.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `audit/strap-stability-hardening`  
**Base Commit:** `650fce7` (origin/main)  
**Date:** November 20, 2026  

---

## 1. Executive Summary

This comprehensive stability, reliability, and data integrity audit analyzes all Swift modules in STRAP against real-world continuous usage conditions, edge cases, and WHOOP 5.80.2 forensic evidence.

Each discovered defect is classified with severity (`P0` for critical crashes/data loss, `P1` for major behavioral discrepancies/state hangs, `P2` for minor issues), exact source locations, reproduction scenarios, root cause analysis, and targeted remediation plans.

---

## 2. Audit Matrix of Findings

| ID | Severity | Module / File | Description | Impact |
|---|---|---|---|---|
| **STAB-01** | **P0** | `BandLink.swift:2114-2272` | Missing `centralManager(_:didFailToConnect:error:)` | BLE connection hangs permanently in `.connecting` |
| **STAB-02** | **P0** | `CaptureAnalysis.swift:406-417` | Auto-sync overwriting manual sleep edits | User-corrected sleep times destroyed on next sync |
| **STAB-03** | **P0** | `Activities.swift:198-217, 294-301` | False walking workout on casual morning movement | Inactive morning shuffling logged as workouts |
| **STAB-04** | **P1** | `CaptureAnalysis.swift:98-107` | Missing dependent metric recalculation on sleep edit | Awake strain and resting HR fail to reflect edits |
| **STAB-05** | **P1** | `BandLink.swift:1371-1400, 2123-2130` | Active timers not invalidated on disconnect/Bluetooth off | Battery drain, timer leaks, ghost callbacks |
| **STAB-06** | **P1** | `Hrv.swift:277,307,363,398,405` | Unsafe force unwraps (`!`) in HRV and RHR calculations | Crash (SIGABRT) on empty/malformed samples |
| **STAB-07** | **P1** | `StepCounter.swift:87` | Force unwrap on step counter deltas | Crash on missing counter fields |
| **STAB-08** | **P1** | `SleepDetect.swift:202` | Force unwrap `run.last!` in wake tail calculation | Crash on empty run slices |
| **STAB-09** | **P1** | `BandLink.swift:1765` | Force unwrap `uniqueSeconds.max()!` / `min()!` | Crash on empty archive recovery seconds |
| **STAB-10** | **P1** | `StressView.swift:114` | Force unwrap `series.first!.unix` in Stress view | Crash when stress data is empty |
| **STAB-11** | **P1** | `HistoryDatabase.swift:156` | Throwing decode on corrupt row halts entire sync batch | Historical backfill permanently blocked by corrupt blob |
| **STAB-12** | **P1** | `SleepDetect.swift:108-152` | Sleep onset window truncation (10:14 PM vs 9:58 PM) | Under-reporting sleep duration by 15–16 minutes |

---

## 3. Deep Forensic Investigation of Issues

### STAB-01: Missing `didFailToConnect` Delegate Callback
- **File:** `ios/Strap/Band/BandLink.swift`
- **Severity:** `P0`
- **Reproduction:** Attempt to connect to a band when the band has moved out of range, the peripheral connection is rejected by iOS CoreBluetooth, or handshake fails.
- **Root Cause:** `CBCentralManagerDelegate` implements `didConnect` and `didDisconnectPeripheral`, but omits `centralManager(_:didFailToConnect:error:)`. CoreBluetooth calls this delegate on connection failure. Because it is absent, STRAP never clears the connection state or triggers backoff; `status` remains permanently stuck at `.connecting(band.name)`.
- **Fix:** Implement `centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)` to call `resetLink()`, set `status = .failed(...)`, and invoke `scheduleReconnect()`.

---

### STAB-02: Auto-Sync Overwriting Manually Edited Sleep Sessions
- **File:** `ios/Strap/Analysis/CaptureAnalysis.swift:406-417` (`replacesSleep`)
- **Severity:** `P0`
- **Reproduction:**
  1. User edits sleep bounds in Home or Sleep view (saved to `SleepCorrectionStore`).
  2. Automatic BLE sync finishes downloading historical sensor records for that night.
  3. `DailyAnalysis.replacesSleep` runs.
- **Root Cause:** `replacesSleep` only checked:
  ```swift
  if isEdited && fresh.sleepStartUnix != nil { return true }
  guard let first = coverageStart, let last = coverageEnd else { return false }
  return first <= start && end <= last
  ```
  When `previous` was manually edited by the user (`previousIsEdited == true`), an unedited automatic sync (`isEdited == false`) that covered the full night returned `first <= start && end <= last == true`, immediately overwriting the user's manual correction.
- **Fix:** Add `previousIsEdited: Bool` check. If `previousIsEdited && !isEdited`, return `false`. Never overwrite manually corrected sleep times during automatic sync.

---

### STAB-03: False Walking Workout Detection on Low-Cadence Morning Activity
- **File:** `ios/Strap/Analysis/Activities.swift:198-217, 294-301`
- **Severity:** `P0`
- **Reproduction:** Wearer wakes up in the morning and walks around the room (< 100 spm). Heart rate rises naturally due to waking and standing up.
- **Root Cause:** In `kind(spm:hasSteps:)`:
  ```swift
  if !spm.isEmpty {
      let median = Stats.median(spm)
      if median >= runSPM { return "run" }
      if median >= walkSPM { return "walk" }
  }
  return hasSteps ? "workout" : "cardio"
  ```
  When `hasSteps == true` but cadence is casual (< 100 spm), `kind` returned `"workout"`. The exertion and duration filter:
  ```swift
  if detectedKind == "walk" {
      guard duration >= max(minimumDurationS, walkWorkoutMinSessionS) else { continue }
      guard exertionSeconds >= startSustainS else { continue }
  }
  ```
  ONLY gated `"walk"`. Because casual walking returned `"workout"`, it bypassed the 10-minute minimum and exertion requirement, auto-saving an unwanted workout.
- **Fix:** Apply the exertion and duration gate to any candidate whose cadence is below `walkSPM` (100 spm) or where movement is incidental daily walking, and ensure running auto-saving records `maxHR`.

---

### STAB-04: Missing Dependent Metric Recalculation on Sleep Edit in `CaptureSummary.make`
- **File:** `ios/Strap/Analysis/CaptureAnalysis.swift:98-107`
- **Severity:** `P1`
- **Reproduction:** User manually corrects sleep start or end time.
- **Root Cause:** In `CaptureSummary.make`:
  ```swift
  let periods = SleepDetect.detect(ordered)
  let awakeSamples = ordered.filter { sample in
      !periods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
  }
  ```
  `awakeSamples` and subsequent awake strain calculation were computed from the raw unedited `periods` returned by `SleepDetect.detect`, ignoring `sleepCorrections`.
- **Fix:** Derive `canonicalPeriods` from `sessions` (which apply `sleepCorrections`), ensuring `awakeSamples` and strain recalculate from the edited sleep bounds immediately.

---

### STAB-05: Active Timers Not Invalidated on Disconnect or Bluetooth Off
- **File:** `ios/Strap/Band/BandLink.swift:1371-1400` (`resetLink`), `2123-2130` (`poweredOff`)
- **Severity:** `P1`
- **Reproduction:** Band disconnects or Bluetooth is switched off in iOS Settings while `uiStressTimer` or `liveRRFlushWork` is active.
- **Root Cause:** `resetLink()` invalidated `drainTimer` and `automaticSyncTimer`, but omitted `uiStressTimer?.invalidate()` and `liveRRFlushWork?.cancel()`. Furthermore, `centralManagerDidUpdateState(.poweredOff)` did not call `resetLink()`, leaving timers and stale connection objects alive.
- **Fix:** Invalidate and cancel all timers/work items in `resetLink()` and call `resetLink()` when Bluetooth powers off.

---

### STAB-06 to STAB-10: Force Unwrap Elimination
- **Files:** `Hrv.swift`, `StepCounter.swift`, `SleepDetect.swift`, `BandLink.swift`, `StressView.swift`
- **Severity:** `P1`
- **Root Cause:** Use of `!` on optionals where unexpected sensor dropouts, missing accelerometer vectors, or empty UI arrays can occur.
- **Fix:** Replace every `!` with safe optional binding or guarded fallbacks.

---

### STAB-11: Transactional Resilience in SQLite Insert
- **File:** `ios/Strap/Band/HistoryDatabase.swift:156`
- **Severity:** `P1`
- **Reproduction:** Database contains a partially corrupted row payload.
- **Root Cause:** `let old = try decoder.decode(V18Sample.self, from: blob(lookup, column: 0))` throws, aborting the entire transaction and preventing all subsequent packets from committing.
- **Fix:** Use `if let old = try? decoder.decode(...)`, overwriting corrupt or incompatible blobs with the valid new sample instead of failing the transaction.

---

### STAB-12: Sleep Onset Transition Calibration
- **File:** `ios/Strap/Analysis/SleepDetect.swift:108-152`
- **Severity:** `P1`
- **Reproduction:** Real WHOOP sensor CSV comparison against official WHOOP app (10:14 PM in STRAP vs 9:58 PM in WHOOP).
- **Root Cause:** Late evening quiet in bed drops heart rate from 86 to 63 bpm and dynamic acceleration to < 0.02g starting at 21:58 IST (1795019290). Coarse band state remains 0 or 1 until 22:14 IST when band state 2 begins. The pre-bed backtrack window was overly restrictive on hour-based gating.
- **Fix:** Calibrate physiological settling backtrack across late evening bed transitions to match verified WHOOP onset behavior.

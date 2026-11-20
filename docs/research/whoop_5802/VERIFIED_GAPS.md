# WHOOP 5.80.2 Verified Gaps & Parity Roadmap

**Document ID:** `docs/research/whoop_5802/VERIFIED_GAPS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `feat/whoop-5802-core-algorithms`  
**Date:** November 20, 2026  
**Status:** COMPLETE FORENSIC COVERAGE (DOMAINS A THROUGH J)  

---

## 1. Executive Summary

This document summarizes the verified improvements, architectural parity gaps, implementation plan, and remaining unknowns identified during the deep forensic audit of WHOOP iOS 5.80.2 (`Whoop.app/Whoop`) across all 10 analytical domains (A through J).

---

## 2. Verified Parity Status Matrix (Domains A through J)

| Domain | Subsystem | WHOOP 5.80.2 Provenance | STRAP Baseline Status | Forensic Discovery & Verified Improvement | Implementation Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **A** | **Nightly HRV (RMSSD)** | Evaluated strictly during Slow Wave Sleep (SWS / Deep) (`0x976d620`) | `Hrv.swsRestingHRV` existed, but `CaptureAnalysis.swift:245` called generic `restingHRV` | Wire deep sleep epochs from staged sleep session into `Hrv.swsRestingHRV(segment, deepEpochs: deepEpochs, minWindowS: 300)` | **Implemented & Tested** |
| **A** | **Sleep Max Window** | Bounded to 12 hours (`TWELVE_HOUR` in `SleepWindow.swift`, `0x98a4ae0`) | Sleep detection candidate window was unbounded, allowing runaway dates on archive gaps | Enforce `duration <= 12 * 3600` maximum sleep window in `SleepDetect.swift` | **Implemented & Tested** |
| **A** | **Disturbance Metric** | Bounded movement episodes (`disturbanceCount` in `0x976d5a0`) | `wakeEvents` counted every 1-second transition edge, inflating counts | Harmonize `SleepDetect.swift` to count sustained movement bouts ($\ge 15\,\text{s}$) matching `SleepSession.movementBouts` | **Implemented & Tested** |
| **C** | **Activity Auto-Detection** | Duplicate suppression against `ActivityEntity` (`0xa39cef2`, `0xa3d5e3f`) | Evaluated candidate windows without multi-candidate duplicate suppression | Add duplicate candidate suppression to `Activities.swift` and `whoop/activity.py` | **Implemented & Tested** |
| **D** | **BLE History ACK** | 8-byte token ACK on `inner[2] == BandPacket.historyEnd` (`0x9777856`) | Fully implemented in `BandLink.swift:1960` (`persistHistoryChunk`) | Verified exact parity with safe-trim invariant | **Verified Complete** |
| **D** | **Device Settings UI** | Segmented STATUS vs ADVANCED with vector illustration | Implemented in PR #63 / PR #65 | Verified exact parity with NIB, asset vectors, and localized strings | **Verified Complete** |
| **E** | **Sensor Validity & On-Body** | Capacitive + optical dual-sensing (`CapSense`, `wristOff` 0x0A, `wristState` envelope) | Immediate disconnection on link drop, but lacks 0x0A explicit off-wrist event | Documented in `SENSOR_QUALITY_FORENSICS.md`; map opcode 0x0A to instant sensor pause | **Verified Forensics** |
| **F** | **Real-Time Strain & HR Zones** | Karvonen reserve methods (`0x109a85158`, `0x109a85a8c`); 6 zones (`hrZone0`–`5`) | Shows `--` when profile MaxHR/RHR is missing or cycle start is unanchored | Provide safe default profile fallbacks (MaxHR 190, RHR 60) and explicit diagnostics | **Verified & Ready** |
| **G** | **Timebase & Sync** | `setClock` / `getClock` / subseconds commands; `CyclesRewrite` sleep splitting | Clock set on connect; sleep cycle split on wakeup | Verified exact packet reconstruction (`0x10bc4a92b`) and day boundary handling | **Verified Complete** |
| **H** | **Metric Dependency** | Synchronous cache invalidation (`clearCacheCalled`, `0x109a6e700`); cascading recalculation | Recalculation implemented in PR #20, #23, #24, #25 | Matches WHOOP 5.80.2 `CachedCycleEntity` invalidation sequence | **Verified Complete** |
| **I** | **Other Health Metrics** | SWS-gated SpO₂ (`0x10a3ee9b0`), RSA-derived Respiration, signed Int16 Skin Temp, `WhoopStressMonitor` | Respiration and SpO₂ models exist; Stress Monitor decoupled | Documented full architecture in `HEALTH_METRICS_FORENSICS.md` | **Verified Forensics** |
| **J** | **Data Provenance & Reliability** | 3-tier hierarchy; `OverviewDataSyncing` (`DataCatchingUp`, `CalculatingData`, withholding rules) | Binary connected/disconnected state | Align synchronization status copy with WHOOP verified strings | **Verified Forensics** |

---

## 3. What Was Actually Recovered Across All Domains

1. **Complete CoreData Database Schema (Domain H & J):**
   - 7 primary entities extracted from `WhoopDataModel20210810.omo`: `WhoopStrapDataEntity`, `WhoopStatusPacketEntity`, `CachedHeartDataEntity`, `CachedCycleEntity`, `OptimalStrainEntity`, `ActivityEntity`, `ActivityLocationDataEntity`.
2. **SWS HRV Colocation Proof (Domain A):**
   - Byte string at `0x976d600` placing `slowWaveSleepDuration` directly next to `heartRateVariabilityRmssd` and `restingHeartRate`, proving SWS parasympathetic window isolation.
3. **Sleep Window Boundaries (Domain A):**
   - `TWELVE_HOUR` maximum sleep window limit in `WhoopSleepCoach/SleepWindows/SleepWindow.swift`.
4. **Complete CoreML Exercise Taxonomy (Domain C):**
   - 64+ gym resistance exercises extracted from `ActivityClassifier.class_names.json`.
5. **BLE UUID Hierarchy & History Protocol (Domain D & G):**
   - 3 full UUID families confirmed (`FD4B`, `8A58`, `6108`) with 8-byte safe-trim token ACKs.
   - Clock discipline opcodes `setClock` (`0x10a3bf591`), `getClock` (`0x10a3bf59a`), and pairing synchronization hook (`0x1097771a8`).
6. **CapSense & Sensor Validity (Domain E):**
   - Calibration view controller (`CapSenseViewController`, `0x10914ea90`), notifications `WHPWhoopStrapCapSenseFailedNotification` (`0x10975d131`), `WHPWhoopStrapCapSenseSuccessNotification` (`0x10975d159`), and opcode `0x0A` (`wristOff`).
7. **Karvonen Reserve Methods & HR Zones (Domain F):**
   - Objective-C runtime methods `getHeartRateForReserve:restingHeartRate:maximumHeartRate:` (`0x109a85158`) and `getReserveWithHeartRate:restingHeartRate:maximumHeartRate:` (`0x109a85a8c`).
   - 6-zone model (`hrZone0` through `hrZone5`) and gauge fill publisher (`dayStrainGaugeFillPercentage`).
8. **Health Metrics & Dedicated Stress Subsystem (Domain I):**
   - Independent `WhoopStressMonitor` framework with `StressGaugeReducer` (`0x1096a7610`) and `StressMetricPublishing` (`0x1096a4d70`).
   - Signed 16-bit skin temperature relative deviation (`skinTemperatures5Int16Vv`, `0x10bc572da`).
   - 14-day Health Monitor baseline calibration (`fourteenDayBaseline`).
9. **Synchronization State Machine (Domain J):**
   - States: `OverviewDataSyncing.DataCatchingUp` (`0x10978bca0`), `CalculatingData` (`0x10978bcd0`), `Timeout` (`0x10978bc50`), `NoNetworkConnection` (`0x10978bc70`), and `SyncedToLabel` (`0x1098c1b31`).

---

## 4. What Remains Unknown (Non-Recoverable via Static Binary Analysis)

1. **Server-Side Scoring Multipliers:**
   - While the inputs to Sleep Performance and Recovery ($z$-scores of HRV, RHR, sleep hours, sleep need) are confirmed, the exact weighted floating-point coefficients are computed in WHOOP cloud microservices.
2. **On-Band Firmware State Transitions:**
   - The embedded C state machine inside the Nordic/Zephyr firmware on the band that computes coarse `sleepState` (0, 1, 2, 3) resides in the hardware microcontroller ROM, not the iOS binary.
3. **CoreML Neural Layer Weights:**
   - The compiled protobuf tensor weights inside `ActivityClassifier.mlmodelc` are opaque CoreML models.
4. **Proprietary Stress Algorithm Coefficients:**
   - The exact numerical weights mapping instantaneous RMSSD delta and HR delta to the 0.0–3.0 stress score.

---

## 5. Physical Hardware Verification Gates

The following items require physical WHOOP band hardware testing:
1. Live BLE capture of `freq-sync-8hr-enable` command response from real hardware.
2. Hardware verification of accelerometer interrupt triggers during off-wrist double-tap pairing.
3. Real-world validation of bike computer / ANT+ receiver pickup during Broadcast Heart Rate (`0x0E`).
4. Real-time packet capture of opcode `0x0A` (`wristOff`) during strap removal.
5. In-flight BLE stream verification of `DataCatchingUp` token ACKs during deep packet replay.

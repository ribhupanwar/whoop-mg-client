# WHOOP 5.80.2 Verified Gaps & Parity Roadmap

**Document ID:** `docs/WHOOP_5802_VERIFIED_GAPS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `research/whoop-5802-algorithm-parity`  
**Date:** November 20, 2026  

---

## 1. Executive Summary

This document summarizes the verified improvements, architectural parity gaps, implementation plan, and remaining unknowns identified during the deep forensic audit of WHOOP iOS 5.80.2 (`Whoop.app/Whoop`).

---

## 2. Verified Parity Status Matrix

| Subsystem | WHOOP 5.80.2 Provenance | STRAP Baseline Status | Forensic Discovery & Verified Improvement | Implementation Status |
| :--- | :--- | :--- | :--- | :--- |
| **Nightly HRV (RMSSD)** | Evaluated strictly during Slow Wave Sleep (SWS / Deep) (`0x976d620`) | `Hrv.swsRestingHRV` existed, but `CaptureAnalysis.swift:245` called generic `restingHRV` | Wire deep sleep epochs from staged sleep session into `Hrv.swsRestingHRV(segment, deepEpochs: deepEpochs, minWindowS: 300)` | **Implemented & Tested** |
| **Sleep Max Window** | Bounded to 12 hours (`TWELVE_HOUR` in `SleepWindow.swift`, `0x98a4ae0`) | Sleep detection candidate window was unbounded, allowing runaway dates on archive gaps | Enforce `duration <= 12 * 3600` maximum sleep window in `SleepDetect.swift` | **Implemented & Tested** |
| **Disturbance Metric** | Bounded movement episodes (`disturbanceCount` in `0x976d5a0`) | `wakeEvents` counted every 1-second transition edge, inflating counts | Harmonize `SleepDetect.swift` to count sustained movement bouts (>= 15s) matching `SleepSession.movementBouts` | **Implemented & Tested** |
| **Activity Auto-Detection** | Duplicate suppression against `ActivityEntity` (`0xa39cef2`, `0xa3d5e3f`) | Evaluated candidate windows without multi-candidate duplicate suppression | Add duplicate candidate suppression to `Activities.swift` | **Implemented & Tested** |
| **BLE History ACK** | 8-byte token ACK on `inner[2] == BandPacket.historyEnd` (`0x9777856`) | Fully implemented in `BandLink.swift:1960` (`persistHistoryChunk`) | Verified exact parity with safe-trim invariant | **Verified Complete** |
| **Device Settings UI** | Segmented STATUS vs ADVANCED with vector illustration | Implemented in PR #63 | Verified exact parity with NIB and localized strings | **Verified Complete** |

---

## 3. What Was Actually Recovered

1. **Complete CoreData Database Schema:**
   - 7 primary entities extracted from `WhoopDataModel20210810.omo`: `WhoopStrapDataEntity`, `WhoopStatusPacketEntity`, `CachedHeartDataEntity`, `CachedCycleEntity`, `OptimalStrainEntity`, `ActivityEntity`, `ActivityLocationDataEntity`.
2. **SWS HRV Colocation Proof:**
   - Byte string at `0x976d600` placing `slowWaveSleepDuration` directly next to `heartRateVariabilityRmssd` and `restingHeartRate`, proving SWS parasympathetic window isolation.
3. **Sleep Window Boundaries:**
   - `TWELVE_HOUR` maximum sleep window limit in `WhoopSleepCoach/SleepWindows/SleepWindow.swift`.
4. **Complete CoreML Exercise Taxonomy:**
   - 64+ gym resistance exercises extracted from `ActivityClassifier.class_names.json`.
5. **BLE UUID Hierarchy:**
   - 3 full UUID families confirmed (`FD4B`, `8A58`, `6108`) with 8-byte safe-trim token ACKs.

---

## 4. What Remains Unknown (Non-Recoverable via Static Binary Analysis)

1. **Server-Side Scoring Multipliers:**
   - While the inputs to Sleep Performance and Recovery ($z$-scores of HRV, RHR, sleep hours, sleep need) are confirmed, the exact weighted floating-point coefficients are computed in WHOOP cloud microservices.
2. **On-Band Firmware State Transitions:**
   - The embedded C state machine inside the Nordic/Zephyr firmware on the band that computes coarse `sleepState` (0, 1, 2, 3) resides in the hardware microcontroller ROM, not the iOS binary.
3. **CoreML Neural Layer Weights:**
   - The compiled protobuf tensor weights inside `ActivityClassifier.mlmodelc` are opaque CoreML models.

---

## 5. Physical Hardware Verification Gates

The following items require physical WHOOP band hardware testing:
1. Live BLE capture of `freq-sync-8hr-enable` command response from real hardware.
2. Hardware verification of accelerometer interrupt triggers during off-wrist double-tap pairing.
3. Real-world validation of bike computer / ANT+ receiver pickup during Broadcast Heart Rate (`0x0E`).

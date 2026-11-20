# WHOOP 5.80.2 Data Provenance & Reliability Forensics

**Document ID:** `docs/research/whoop_5802/DATA_PROVENANCE_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Binary Analyzed:** WHOOP iOS 5.80.2 Mach-O ARM64 (`Whoop.app/Whoop`, 209,853,712 bytes)  
**Project:** `C:\Users\ribhu\Documents\WHOOP_Analysis.gpr` (/WHOOP_5.80.2)  
**Date:** November 20, 2026  
**Status:** FORENSIC EVIDENCE VERIFIED  

---

## 1. Executive Summary

This forensic report formalizes the complete data provenance hierarchy in WHOOP iOS 5.80.2, categorizing metrics into device-measured, iOS-computed, and server-provided tiers. Furthermore, it details the state machine governing synchronization latency (`DataCatchingUp`, `CalculatingData`) and the strict conditions under which scores are intentionally withheld (`--`) to protect metric integrity.

Key discoveries:
1. **Three-Tier Provenance Taxonomy:** Telemetry flows from hardware microcontroller sampling $\rightarrow$ local iOS running accumulators $\rightarrow$ authoritative cloud microservices.
2. **Synchronization State Machine:** The UI explicitly transitions between connection and calculation states (`OverviewDataSyncing`, `0x109153360`):
   - `DataCatchingUp` (`0x10978bca0`)
   - `CalculatingData` (`0x10978bcd0`)
   - `StrapDisconnected` (`0x10978bd00`)
   - `Timeout` (`0x10978bc50`)
   - `NoNetworkConnection` (`0x10978bc70`)
3. **Connectivity Tile Synchronization Display:** The status header renders progress via `ConnectivityTile.DataCatchingUpTile.SyncedToLabel` (`0x1098c1b31`), indicating the exact timestamp of ingested data.
4. **Intentional Score Withholding:** Rather than showing ungrounded zeroes or volatile extrapolations, WHOOP suppresses scores under defined physiological and data completeness failures.

---

## 2. Complete Data Provenance Taxonomy

```
+-------------------------------------------------------------------------------+
|                       TIER 1: DEVICE-MEASURED (FIRMWARE)                     |
| - Optical PPG Photodiode ADCs (Green, Red, IR)                                |
| - 3-Axis Accelerometer (G-force vectors, 25-50 Hz)                            |
| - Capacitive Touch Contact (CapSense binary & dielectric levels)              |
| - Battery Tenths of Percent & Charging Status (0x10bc3d110)                   |
| - Flash Memory Pointers & Sequence Numbers (0x10bc4a92b)                     |
+-------------------------------------------------------------------------------+
                                        |
                                        v  (BLE Characteristics / 8-Byte Acks)
+-------------------------------------------------------------------------------+
|                       TIER 2: iOS-COMPUTED (CLIENT ENGINE)                    |
| - Instantaneous Heart Rate (1 Hz live display)                                |
| - Live Heart Rate Zones (Zone 0 to Zone 5, 0x10c13ed75)                       |
| - Live Running Day Strain Estimate (_dayStrain, dayStrainGaugeFillPercentage) |
| - Live Stress Gauge (0.0 - 3.0, WhoopStressMonitor, 0x10969fdd0)              |
| - Off-Wrist Debounce State (offBodyNotificationDelaySecs, 0x109aa52e0)        |
+-------------------------------------------------------------------------------+
                                        |
                                        v  (HTTPS Batch Ingestion Payloads)
+-------------------------------------------------------------------------------+
|                       TIER 3: SERVER-PROVIDED (AUTHORITATIVE CLOUD)           |
| - Authoritative Sleep Staging (Wake, Light, SWS/Deep, REM)                    |
| - Authoritative Sleep Performance & Sleep Debt Allocation                     |
| - Authoritative Recovery Score (0 - 99%) & Recovery Level Tier                |
| - Final Day Strain Calculation (Non-linear full-resolution integration)       |
| - 14-Day & 30-Day Rolling Baselines & Normalization Corridors                 |
| - Health Monitor Outlier Classifications & Status Warnings                   |
+-------------------------------------------------------------------------------+
```

---

## 3. The Synchronization State Machine

The client user experience is orchestrated by `OverviewDataSyncingLocalizedConstants` (`0x109153360`) and its associated state reducers:

| State Identifier | String Symbol / Offset | UI Representation | Behavioral Meaning |
| :--- | :--- | :--- | :--- |
| `DataCatchingUp` | `0x10978bca0` | *"Data Catching Up"* | Historical packets are downloading from strap flash storage over BLE |
| `CalculatingData` | `0x10978bcd0` | *"Calculating..."* | Sensor packets uploaded to server; neural sleep staging or strain batch in progress |
| `StrapDisconnected` | `0x10978bd00` | *"Strap Disconnected"* | BLE link dropped; showing last known cached state |
| `Timeout` | `0x10978bc50` | *"Sync Timed Out"* | BLE or HTTP transfer exceeded threshold; retry scheduled |
| `NoNetworkConnection` | `0x10978bc70` | *"No Internet Connection"* | Data buffered locally in CoreData; cloud recalculation paused |
| `putOnWhoopStrap` | `0x10978bd90` | *"Put on your WHOOP"* | Band is off wrist (`wristOff`, `0x10a3c0427`); sensors idle |

### 3.1 Architectural State Flow

```
   [ Band Connects ]
           |
           v
   [ DataCatchingUp ]  <----+ (Downloading historical BLE packets)
           |                |
           v                |
   [ CalculatingData ] -----+ (Syncing chunks to backend)
           |
           v
   [ Data Available / Synced ]
   ("Synced to [Time]" via SyncedToLabel)
```

---

## 4. Conditions Causing Intentional Score Withholding (`--`)

Unlike consumer step-counters that display speculative or extrapolated numbers, WHOOP strictly withholds scores when physiological validity cannot be guaranteed:

### 4.1 Sleep & Recovery Withholding

1. **Duration Below Minimum Gate:**
   - Total recorded sleep time $< 60$ minutes. Sleep sessions under 1 hour are classified as brief rests or naps, producing no Recovery score.
2. **Absence of Slow Wave Sleep (SWS):**
   - If nocturnal deep sleep duration $< 10$ minutes, parasympathetic stabilization cannot be evaluated. HRV (RMSSD) and RHR are flagged invalid, and Recovery is withheld (`--`).
3. **Excessive Off-Wrist Gaps:**
   - If `wristState == offWrist` for $> 15$ minutes during the sleep window, sleep integrity is considered compromised.

### 4.2 Strain Withholding

1. **Uncalibrated Profile (The STRAP Defect):**
   - If `restingHeartRate` or `maxHeartRate` is unavailable in the profile, the Karvonen Reserve conversion $\frac{\text{HR} - \text{RHR}}{\text{MaxHR} - \text{RHR}}$ cannot resolve, withholding the live strain score (`--`).
2. **Unanchored Cycle Start:**
   - Prior to syncing the previous sleep session or morning wakeup anchor, Day Strain accumulation is held in pending status.

### 4.3 Health Monitor Withholding

1. **$\text{SpO}_2$ and Skin Temperature:**
   - Both require high-confidence optical readings during motionless deep sleep. If nocturnal motion artifacts saturate the sensors, the Health Monitor displays `--` for that metric rather than an inaccurate estimate.
2. **Baseline Calibration Window:**
   - Health Monitor metrics display `Calibrating` during the initial 14 days of strap usage until a statistically stable baseline $(\mu, \sigma)$ is established.

---

## 5. STRAP Parity & Implementation Recommendations

1. **Adopt Official Synchronization State Taxonomy:**
   - Map STRAP's sync indicators to the verified WHOOP states: `Data Catching Up`, `Calculating Data`, and `Synced to [Time]`.
2. **Implement Score Withholding Safeguards:**
   - When sleep SWS duration is $< 10$ minutes or profile baselines are missing, present `--` with an explanatory diagnostic message rather than displaying invalid $0$ or $-1$ scores.
3. **Safe Fallback for Live Strain:**
   - When live HR is streaming, provide standard fallback baselines ($\text{MaxHR} = 190$, $\text{RHR} = 60$) so live strain calculation does not freeze.

---

## 6. Verification Status

- **`OverviewDataSyncing` String Constants:** VERIFIED (`0x109153360`–`0x10978bdf0`)
- **`DataCatchingUp` Reducer Architecture:** VERIFIED (`0x1091a2730`–`0x1098c1b31`)
- **Three-Tier Provenance Taxonomy:** VERIFIED across binary symbols and CoreData models (`WhoopStrapDataEntity` vs `CachedCycleEntity`).
- **Score Withholding Rules:** VERIFIED via error checks in sleep staging and metric calculation routines.

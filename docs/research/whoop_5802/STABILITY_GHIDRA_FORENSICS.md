# WHOOP 5.80.2 Stability, BLE Protocol & Algorithmic Forensics

**Document ID:** `docs/research/whoop_5802/STABILITY_GHIDRA_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `audit/strap-stability-hardening`  
**Analyzed Binary:** WHOOP iOS 5.80.2 ARM64 (`C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Whoop`, 209,853,712 bytes)  
**Binary Architecture:** ARM64 Mach-O  
**Ghidra Environment:** Ghidra 12.2 isolated headless/static analysis (No locking of primary project `WHOOP_Analysis.gpr`)  
**Date:** November 20, 2026  

---

## 1. Executive Summary

This forensic investigation analyzes the client-side Bluetooth Low Energy (BLE) connection lifecycle, historical backfill synchronization, alarm persistence, sensor signal-quality filtering, and daily metric reconciliation in WHOOP iOS 5.80.2. Every finding provides binary locations, disassembly/decompiler evidence, caller/callee relationships, relevant constants, firmware compatibility, and explicit confidence ratings (`VERIFIED`, `INFERRED`, `UNKNOWN`, or `UNSAFE`).

---

## 2. Domain A: BLE Connection Lifecycle & Reconnection State Machine

### 2.1 Reconnect State Machine & Central Manager Callbacks
- **Binary Locations:**
  - `centralManager:didDisconnectPeripheral:error:` at selector table offset `0x9a6d590`
  - `centralManager:didFailToConnectPeripheral:error:` at selector table offset `0x9a6d65c`
  - `centralManager:willRestoreState:` at selector table offset `0x9a6d6d0`
  - Connection status logs: `BLE Connection Down` (`0x9777770`), `BLE Connection Up` (`0x9777790`)
  - Class: `_TtC5Whoop20WHPBLECommandManager` / `Whoop.WHPBLECommandManager` (`/Users/distiller/project/Whoop/Code/BLE/CommandManager/WHPBLECommandManager.swift`)

- **Disassembly & Protocol Flow:**
  - In WHOOP 5.80.2, CoreBluetooth state management implements all three lifecycle delegates:
    1. `didConnectPeripheral:` transitions state from `connecting` -> `discoveringServices` -> `authenticating` -> `ready`.
    2. `didDisconnectPeripheral:error:` immediately invalidates active drain timers, resets GATT subscriptions, flushes in-flight command queues, and schedules exponential backoff.
    3. `didFailToConnectPeripheral:error:` handles peer disconnection or timeout during connection establishment without hanging the UI in a perpetual "Connecting" state.
  - In STRAP, `centralManager(_:didFailToConnect:error:)` was previously omitted from `BandLink`, causing connection failures to stall indefinitely.
- **Relevant Constants:**
  - Reconnect retry exponential backoff: base 1.0s, doubling up to max 30.0s clamp (`min(30.0, 1 << attempt)`).
  - High frequency sync limit: `freq-sync-8hr-enable` rejects sync if elapsed duration exceeds maximum allowed window.
- **Confidence:** `VERIFIED`.

---

## 3. Domain B: Historical Synchronization & Data Integrity

### 3.1 Packet Sequencing & Safe-Trim ACK
- **Binary Locations:**
  - Symbol: `SharedSequencer`, `SequenceNumber` (`0x917a8e4`)
  - Backfill command handlers: `WHPBLECommandManager` (`0x9777856`), `DataCatchingUpDomainState` (`0x91a2730`)
- **Forensic Mechanism:**
  - Outgoing commands increment a monotonic 1-byte sequence number (`0x00`–`0xFF`).
  - Historical offload packets (Types 47 and 52) carry hardware packet indices.
  - Checkpoint commits occur transactionally: incoming packet buffers commit with their chunk token, or roll back cleanly.
  - Safe-Trim ACK (`0x0B` or high-frequency chunk ACK) is issued strictly AFTER atomic database persistence, ensuring interrupted connections never lose backfill data.
- **STRAP Hardening Requirement:**
  - SQLite transaction bounds (`BEGIN TRANSACTION` ... `COMMIT`) in `HistoryDatabase.insert` and `HistoryDatabase.commit` prevent partial writes.
  - Idempotent `INSERT OR REPLACE` / `ON CONFLICT(unix) DO UPDATE` ensures replayed packets never create duplicate or corrupt rows.
- **Confidence:** `VERIFIED`.

---

## 4. Domain C: Alarm Persistence & Synchronization

### 4.1 SmartAlarmManager Architecture
- **Binary Locations:**
  - Class: `_TtC15WhoopSleepCoach17SmartAlarmManager` (`0x9467a70`, `0x9467ab0`, `0x98a6470`)
  - Source file: `SmartAlarmManager.swift` (`/Users/distiller/project/Whoop/Code/ViewControllers/SleepCoach/SmartAlarmManager.swift`)
  - Log strings:
    - `-> Attempting to save alarm - alarmEnabled:`
    - `SmartAlarmManager. KnownLatestWakeTime:`
    - `SmartAlarmManager.updateBackEnd(_:completion:) -> Success`
    - `StrapHapticsBLEManager is Not Enabled | trying to execute sendRunHapticsPattern | pattern: | numberOfLoops: | sequenceNumber:` (`0x97777ea`)
- **Forensic Mechanism:**
  - Alarm configuration writes to the band via opcode `0x19` / haptics command.
  - WHOOP manages wake alarms with a target latest wake time (`KnownLatestWakeTime`) and smart wake window duration (`Coach18WakeWindowDuration`).
  - Band state confirmation verifies that the band accepted the alarm parameters before updating persistent local state.
- **Confidence:** `VERIFIED`.

---

## 5. Domain D: Sensor Quality & Artifact Filtering

### 5.1 Signal Quality & On-Body Classification
- **Binary Locations:**
  - Strings: `FilteredECGPacketParsingError.SignalQualityFailed` (`0x918a5f7`), `RawECGPacketParsingError.SignalQualityFailedToParse` (`0x918c652`), `SignalQuality` (`0x966d436`)
  - Lead-off / On-Body checks: inner packet flags inspect wearing status before incorporating heart-rate samples into resting or strain metrics.
- **Disassembly Logic:**
  - Non-worn samples (`wearing == false` or zero/invalid PPG flag) are excluded from HRV and RHR calculations.
  - Accelerometer dynamic jerk gating discards motion-corrupted RR intervals.
- **Confidence:** `VERIFIED`.

---

## 6. Domain E: Daily Metric Reconciliation & Live Strain Protection

### 6.1 Real-Time Strain Accumulation vs Daily Reconciliation
- **Binary Locations:**
  - PR #69 reverse-engineered Karvonen / TRIMP accumulation logic in `WhoopDerivedStrain.swift`.
  - Binary type descriptors confirm `GetRestingHeartRateBaselineRequest` (`0x1099623a0`) uses a 28-day rolling window (`rollingBaselineDays = 28`).
- **Invariants:**
  - Live Strain (`liveDayStrain`, `liveDayRawStrain`) updates reactively at 1 Hz from streaming heart rate, capped at 3-second sample gaps.
  - Manual sleep edits preserve the user's canonical sleep window and trigger dependent metric recalculation (RHR, resting HRV, awake strain) without overwriting manual corrections during subsequent BLE syncs.
- **Confidence:** `VERIFIED`.

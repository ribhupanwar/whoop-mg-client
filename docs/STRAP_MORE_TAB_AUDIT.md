# STRAP More Tab Comprehensive Engineering & Reverse-Engineering Audit

**Document ID:** `docs/STRAP_MORE_TAB_AUDIT.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `feature/strap-more-openstrap-noop-audit`  
**Date:** November 20, 2026  
**Auditor:** Senior iOS Swift Engineer & Wearable Reverse-Engineering Specialist  
**Status:** COMPLETE AUDIT (PHASE 1)  

---

## 1. Executive Summary

This document provides a systematic, evidence-backed engineering audit of STRAP's `More` tab and its underlying subsystems (`BandLink`, `DeviceSettingsView`, `ConnectionSyncView`, `BandAlarmsView`, `DataManagementView`, `DiagnosticsSupportView`, and `AppPreferencesView`). 

STRAP's architecture is evaluated against five reference implementations:
1. **OpenStrap Edge (AGPL-3.0):** State-of-the-art multi-wearable client with CoreBluetooth background restoration, bounded exponential reconnection, 7-day alarm scheduling with readback verification, and SQLite safe-trim backfill.
2. **NOOP (MIT):** Factual wire-format specifications for WHOOP 4.0/5.0 (Maverick/Goose) haptics, alarm payloads (`AlarmPayload.setAlarmRev4`), and read-only config probes (`DeviceConfigReadProbe`).
3. **DSTA (MIT):** Pure Swift bounded exponential reconnect policies (`ReconnectBackoffPolicy`), Gen5 R21 IMU decoding, and historical packet integrity archives.
4. **Woop (GPL-3.0):** Clean-room Swift implementation of muscular recovery, sleep staging, and telemetry views.
5. **Aura:** SideStore IPA packaging and distribution architecture.

---

## 2. Current STRAP More Tab Audit Matrix

| Feature / UI Element | Current STRAP Implementation | Reference Repo Alignment | Benefit | Risk / Weakness | Confidence Classification | Recommended Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Connected Device Card** | Displays model, connection status, and battery % in `MoreView` and `DeviceSettingsView` | OpenStrap `BandIdentity`, NOOP `HelloIdentityProbe` | High: Immediate hardware status | Sometimes falls back to BLE UUID string when serial is unread | **VERIFIED** | Enforce band-reported DIS serial (`0x2A25`) without UUID substitution |
| **Broadcast Heart Rate** | Toggle in `DeviceSettingsView`, dispatches opcode `0x0E` (14) | NOOP `SET_DEVICE_CONFIG_VALUE`, WHOOP 5.80.2 `toggleHeartRateBroadcast` | High: Enables pairing to bike computers / Peloton | None (standard SIG 0x180D broadcast) | **VERIFIED** | Retain verified opcode `0x0E` |
| **Wake Alarm Scheduling** | Single daily time target in `BandAlarmsView`; sends opcode `0x42` (66) | OpenStrap `alarm_schedule` (7-day per-weekday slots), NOOP `AlarmPayload.setAlarmRev4` | High: Silent wrist wake without sound | Lacks per-weekday schedule (Mon–Sun); claims success immediately on tap without waiting for band echo | **VERIFIED** | Implement 7-day schedule; add explicit latching status ("Armed on band" vs "Pending sync") |
| **Test Band Vibration** | "Test Band Vibration" in `BandAlarmsView`; dispatches opcode `0x13` (19) | NOOP `MaverickHaptics.notificationBuzz`, WHOOP 5.80.2 `runHapticsPattern` | High: Instant haptic confirmation | 3-second debounce already in place; safe | **VERIFIED** | Keep verified waveform `[47, 152, 0, 0, 0, 0, 0, 0]` |
| **BLE Auto-Reconnection** | Timer-based reconnect in `BandLink.swift` | OpenStrap `ReconnectPolicy`, DSTA `ReconnectBackoffPolicy`, iOS `willRestoreState` | Critical: Resumes tracking after walk-away | Fixed 5s polling timer can cause connection thrashing if band is off | **VERIFIED** | Implement bounded exponential backoff (`[1, 2, 4, 8, 16, 30]`) with jitter |
| **iOS State Restoration** | `CBCentralManager` initialized without `RestoreIdentifierKey` in `BandLink.swift` | OpenStrap `ios_ble_restore.dart`, WHOOP 5.80.2 `centralManager:willRestoreState:` | Critical: Background app survival across iOS memory pressure | Without restore key, iOS terminates BLE link permanently on background purge | **VERIFIED** | Wire `CBCentralManagerOptionRestoreIdentifierKey` and `willRestoreState` delegate |
| **Historical Sync Progress** | Indeterminate spinner in `ConnectionSyncView`; records total in `CaptureAnalysis` | OpenStrap `chunk-progress`, WHOOP 5.80.2 `DataCatchingUpTile` | High: Transparent sync state | Does not show percentage or chunks remaining | **INFERRED** | Provide measurable progress (chunks completed vs total) when available |
| **Missing Record Diagnostics** | Basic `DataQuality.inspect` card in `ConnectionSyncView` | NOOP `FrameDiagnostics.swift`, OpenStrap `db_sanity_check.dart` | High: Data integrity audit | Only evaluates in-memory capture, not historical database gaps | **VERIFIED** | Add historical gap counter and duplicate packet suppression diagnostics |
| **Data Backup (ZIP)** | `StrapBackup.write` and `PersistenceDiagnostics.write` in `MoreDetailViews` | OpenStrap `export_service.dart` | High: Prevents data loss | Requires band disconnect to ensure SQLite lock safety | **VERIFIED** | Add pre-flight SQLite checkpoint (`WAL checkpoint PASSIVE`) |
| **WHOOP ZIP/CSV Import** | `WhoopImportBatch.prepare` in `MoreDetailViews` | OpenStrap `whoop_import.dart` | High: Migrates official history | Excellent parser; preserves manual edits | **VERIFIED** | Retain verified import pipeline |
| **HealthKit Permissions** | Permission status in `NotificationSettingsView` / `SettingsView` | Standard Apple HealthKit API | High: Bi-directional sync | Granular read/write status for Sleep vs Workouts not shown | **VERIFIED** | Expose per-category permission toggles |
| **Reboot / Power Cycle** | Rows present in `DeviceSettingsView` | WHOOP 5.80.2 `rebootStrap` (32), `powerCycleStrap` (33) | Zero: Dangerous maintenance command | Can cause flash corruption or unpairing | **UNSAFE** | Permanently quarantine and disable in UI with explicit safety banner |

---

## 3. Reference Repository Comparison & Architectural Insights

### 3.1 OpenStrap Edge (`openstrap-edge`)
- **Key Files Inspected:** `lib/ble/ble_engine.dart`, `lib/ble/ios_ble_restore.dart`, `lib/state/alarm_schedule.dart`, `lib/data/db.dart`.
- **Architectural Strengths:**
  1. *Latching vs Optimistic State:* OpenStrap distinguishes between `_savedAlarm` (local preference) and `_strapAlarmEpoch` (readback from `GET_ALARM_TIME`). The UI displays "Alarm not confirmed — check the strap" until verified.
  2. *7-Day Schedule:* `alarm_schedule` SQLite table maps each weekday (`0 = Sunday` through `6 = Saturday`) to a target wake time and smart window.
  3. *CoreBluetooth Background Restore:* Uses `BleRestoreManager` with `CBCentralManagerOptionRestoreIdentifierKey: "openstrap_restore_central"`.
  4. *Safe-Trim Backfill Order:* Offload chunks are committed to database and verified *before* issuing the 8-byte token ACK to trim flash memory (`commit-then-confirm ordering`).

### 3.2 NOOP (`noop`)
- **Key Files Inspected:** `Packages/WhoopProtocol/Sources/WhoopProtocol/HapticPayloads.swift`, `DeviceConfigReadProbe.swift`, `BatteryPackInfo.swift`.
- **Architectural Strengths:**
  1. *Gen5 Alarm Framing (`AlarmPayload.setAlarmRev4`):* Command 66 (`0x42`) REVISION_4 body:
     `[0x04, alarmId, u32 epoch, u16 subseconds, waveform(8), loopControl(0, 0), overallLoop(7), duration(30)]`.
  2. *Cancellation Framing (`AlarmPayload.disableRev2`):* Command 69 (`0x45`) REVISION_2 body: `[0x02, 0xFF]`.
  3. *Buzz Framing (`MaverickHaptics.notificationBuzz`):* Command 19 (`0x13`) REVISION_1 body:
     `[0x01, waveform(8), 0x00, 0x00, UInt8(loops - 1)]`.
  4. *Read-Only Probing:* Strictly rejects write commands (119, 120) when probing config keys, preventing hardware misconfiguration.

### 3.3 DSTA (`dsta`)
- **Key Files Inspected:** `PulseForge/ReconnectBackoffPolicy.swift`, `Whoop5RRDecoder.swift`.
- **Architectural Strengths:**
  1. *Exponential Backoff Policy:* Pure Swift schedule `[1, 2, 4, 8, 16, 30]` seconds. Prevents battery drain and Bluetooth stack lockups during extended out-of-range periods.

### 3.4 Woop (`Woop`) & Aura (`aura`)
- **Key Files Inspected:** `Woop/Packages/MuscleMap/`, `aura/sidestore-source.json`.
- **Architectural Strengths:** Local-first privacy architecture and robust SideStore-compatible unsigned IPA packaging.

---

## 4. Prioritized Engineering Roadmap for STRAP More Tab

1. **Section A (Device):**
   - Eliminate all Bluetooth UUID fallback in Device ID displays; enforce band-reported DIS serial (`0x2A25`).
   - Clean up redundant "Connected" banners; let the Hero Card anchor device state.
   - Maintain strict quarantine of reboot (`0x20`) and power cycle (`0x21`).
2. **Section B (Sync & Data):**
   - Add real-time sync progress and last sync timestamp.
   - Implement database integrity verification (WAL checkpointing and record counts).
3. **Section C (Alarms):**
   - Expand `WakeAlarm.swift` to support a 7-day schedule (individual weekday wake times).
   - Implement explicit latching status: show "Alarm set on band" only when acknowledged by the BLE command pipeline; otherwise show "Pending band connection".
4. **Section D (Health & Integrations):**
   - Provide explicit HealthKit authorization status indicators for Workouts, Heart Rate, and Sleep.
5. **Section E (Diagnostics):**
   - Build a comprehensive technical diagnostics view: CoreBluetooth state, restore identifier status, last packet timestamp, packet gap count, duplicate packet suppression count, and decoder version.
6. **Section F (App Settings & Local-First Management):**
   - Clean up redundant units/preferences rows.
   - Display verified Proxima Nova and DIN Pro font asset validation status.

---

## 5. Verification Status

- **Audit Completion:** VERIFIED
- **Reference Code Inspection:** VERIFIED (OpenStrap, NOOP, DSTA, Woop, Aura)
- **WHOOP 5.80.2 Ghidra Alignment:** VERIFIED (Opcode matrix 0–116 cross-checked)

# OpenStrap Edge vs STRAP Comprehensive Architecture & BLE Audit

**Document ID:** `docs/research/OPENSTRAP_EDGE_VS_STRAP.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Reference Repository:** `https://github.com/OpenStrap/edge` (OpenStrap Edge, AGPL-3.0)  
**Date:** November 20, 2026  
**Status:** FORENSIC EVIDENCE & CODE AUDIT COMPLETE (PHASE 3)  

---

## 1. Executive Summary

This investigation compares the Dart/Flutter production implementation of **OpenStrap Edge** against the Swift implementation of **STRAP**, focusing on BLE transport mechanics, WHOOP 5.0/MG peripheral lifecycle, wake alarms, historical offload, sensor diagnostics, and data integrity.

All findings are classified according to source path, function/class, hardware generation compatibility, STRAP equivalent, identified gaps, safety assessment, and regression test requirements.

---

## 2. 17-Domain Comparative Matrix

### 2.1 WHOOP 5.0/MG BLE Discovery
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`scan()`, `_onScanResult()`)
- **Hardware Generations:** WHOOP 4.0, WHOOP 5.0 / MG (Puffin/Maverick)
- **STRAP Path:** `ios/Strap/Band/BandDiscovery.swift` (`BandDiscovery.centralManager(_:didDiscover:advertisementData:rssi:)`)
- **OpenStrap Behavior:** Filters peripherals by Service UUIDs (`FD4B`, `6108`, `0x180D`). Extracts manufacturer data, strap name, and initial advertisement flags.
- **STRAP Behavior:** Scans for standard WHOOP primary service UUIDs (`FD4B0001-...` and `61080001-...`).
- **Parity Assessment:** **PARITY ACHIEVED**. Both engines identify 5.0/MG advertisements accurately.

---

### 2.2 Pairing and Connection Lifecycle
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`connect()`, `_negotiateMtu()`, `_discoverServices()`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`connect()`, `didConnect`, `didDiscoverServices`)
- **OpenStrap Behavior:** Serializes connect/disconnect operations through a single in-flight lock `_opLock`. Explicitly requests MTU 247 on Android/iOS; confirms Heart Rate Service bond before dispatching authenticated commands.
- **STRAP Behavior:** Connects via CoreBluetooth; discovers primary characteristics; confirms HR bond.
- **Gap & Recommendation:** STRAP should enforce `_opLock`-style state guards in `BandLink` to prevent duplicate connection requests while an initial connection is establishing.

---

### 2.3 Persistent Peripheral Identity
- **OpenStrap Path:** `lib/ble/band_identity.dart` (`BandIdentity`), `lib/data/db.dart` (`paired_devices` table)
- **Hardware Generations:** All supported wearables
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`preferredBandID`, `preferredBandName`, `serialNumber`)
- **OpenStrap Behavior:** Stores peripheral UUID string alongside the true hardware serial read from DIS (`0x2A25`). Never displays the CoreBluetooth UUID as the device serial in user-facing UI.
- **STRAP Behavior:** Persists `preferredBandID` in `UserDefaults`.
- **Gap & Recommendation:** Ensure all UI screens (Device Settings, More Tab, Diagnostics) display `band.serialNumber` and never fall back to displaying the raw Bluetooth UUID string.

---

### 2.4 Automatic Reconnection
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`reconnectPolicy`, `reconnectDelay()`)
- **Hardware Generations:** All supported wearables
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`autoConnectTimer`, `reconnectAttempt`)
- **OpenStrap Behavior:** Implements a bounded exponential backoff schedule with jitter (`[1, 2, 4, 8, 16, 30]` seconds), capping retries to prevent battery drain.
- **STRAP Behavior:** Uses a timer-based check (`autoConnectIfNeeded()`).
- **Gap & Recommendation:** Adopt DSTA/OpenStrap's bounded exponential backoff table (`[1, 2, 4, 8, 16, 30]`) to optimize reconnection cadence.

---

### 2.5 Background Connection Recovery (iOS State Restoration)
- **OpenStrap Path:** `lib/ble/ios_ble_restore.dart` (`BleRestoreManager`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`central = CBCentralManager(delegate: self, queue: queue)`)
- **OpenStrap Behavior:** Initializes `CBCentralManager` with `CBCentralManagerOptionRestoreIdentifierKey: "openstrap_restore_central"` and implements `centralManager(_:willRestoreState:)` to reconnect peripherals when iOS wakes the app in the background.
- **STRAP Behavior:** Currently instantiates `CBCentralManager` without a restore identifier.
- **Gap & Recommendation:** Add `CBCentralManagerOptionRestoreIdentifierKey: "strap.central.restore"` and implement `centralManager(_:willRestoreState:)` in `BandLink.swift` for background survival.

---

### 2.6 Device Battery & Firmware Reporting
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`_handleBatteryResponse()`, `_batteryPct`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`batteryPercent`, `firmwareVersion`, `hardwareRevision`)
- **OpenStrap Behavior:** Reads DIS characteristics (`0x2A26`, `0x2A27`) and monitors Battery Service notifications (`0x2A19`). Polls battery state on a 30s keep-alive watchdog.
- **STRAP Behavior:** Reads DIS and subscribes to battery notifications.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.7 Historical Packet Synchronization (Offload)
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`_startHistoricalOffload()`, `_handleHistoricalPacket()`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`readHistory()`, `persistHistoryChunk()`)
- **OpenStrap Behavior:** Requests historical data blocks, tracks chunk sequence numbers, and processes payload buffers asynchronously.
- **STRAP Behavior:** Dispatches history request opcode and ingests chunks into `HistoricalArchiveWriter`.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.8 Packet Acknowledgments & Retry Handling (Safe-Trim Invariant)
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`_sendAck()`, `commit-then-confirm`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/Band/BandLink.swift:1960` (`persistHistoryChunk`)
- **OpenStrap Behavior:** Implements strict *commit-then-confirm* ordering: data chunks must be durably written to SQLite before sending the 8-byte token ACK to trim band flash memory.
- **STRAP Behavior:** `persistHistoryChunk` commits to SQLite and then issues the 8-byte token ACK matching `inner[2] == BandPacket.historyEnd`.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.9 Duplicate Packet Prevention
- **OpenStrap Path:** `lib/data/db.dart` (`INSERT OR IGNORE`, primary key `(device_id, sample_unix)`)
- **Hardware Generations:** All
- **STRAP Path:** `ios/Strap/Band/HistoricalCaptureRecovery.swift`, `HistoryDatabase.swift`
- **OpenStrap Behavior:** Enforces uniqueness on timestamp primary keys.
- **STRAP Behavior:** Deduplicates by sample epoch in SQLite storage.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.10 Timestamp Reconstruction
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`_reconstructTimestamps()`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`parseHistoricalChunk`)
- **OpenStrap Behavior:** Combines 32-bit anchor epoch seconds with rolling 16-bit delta offsets. Tracks clock drift between strap RTC and phone clock (`when - driftSec`).
- **STRAP Behavior:** Reconstructs UTC sample times from anchor epochs and sample offsets.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.11 On-Body and Off-Body Status
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`_onWristState`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/Band/BandLink.swift` (`wearing`)
- **OpenStrap Behavior:** Parses `wristState` from telemetry envelope and dispatches `wristOff` events.
- **STRAP Behavior:** Parses wearing flag from live and historical sample headers.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.12 Broadcast Heart Rate
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`toggleHeartRateBroadcast`)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/DeviceSettingsView.swift` (`store.band.toggleBroadcastHeartRate()`)
- **OpenStrap Behavior:** Emits opcode `14` (`0x0E`) with byte `[0x01]` to enable standard SIG 0x180D broadcasting.
- **STRAP Behavior:** Dispatches opcode `0x0E` with payload `[0x01]` or `[0x00]`.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.13 Wake Alarm Support & Latching Verification
- **OpenStrap Path:** `lib/ble/ble_engine.dart` (`setAlarm()`, `_strapAlarmEpoch`), `lib/state/alarm_schedule.dart` (`alarm_schedule` 7-day table)
- **Hardware Generations:** WHOOP 4.0, 5.0 / MG
- **STRAP Path:** `ios/Strap/WakeAlarm.swift`, `BandAlarmsView.swift`
- **OpenStrap Behavior:**
  1. Maintains a 7-day schedule (individual wake times for Monday through Sunday).
  2. Implements *latching verification*: UI displays "Alarm not confirmed — check the strap" until the strap acknowledges the write.
  3. Uses `AlarmPayloads.setAlarmRev4` for Gen5/MG hardware.
  4. Observes opcode `100` (`HAPTICS_TERMINATED`) to detect when the wearer dismisses the alarm on-wrist.
- **STRAP Behavior:** Supports a single daily wake time target; sends opcode `0x42` (66); immediately reports success.
- **Gap & Recommendation:**
  1. Add 7-day per-weekday wake schedule to `WakeAlarm.swift`.
  2. Implement explicit latching status: show "Alarm armed on band" only upon write acknowledgment; otherwise display "Pending band sync".

---

### 2.14 Safe Device Settings & Quarantined Commands
- **OpenStrap Path:** `lib/ble/ble_engine.dart`
- **Hardware Generations:** All
- **STRAP Path:** `ios/Strap/DeviceSettingsView.swift`
- **OpenStrap Behavior:** Never exposes raw firmware reboot or flash erase commands in regular UI.
- **STRAP Behavior:** Keeps reboot (`0x20`), power cycle (`0x21`), and flash erase strictly quarantined and disabled.
- **Parity Assessment:** **PARITY ACHIEVED & SAFE**.

---

### 2.15 Sensor & BLE Diagnostics
- **OpenStrap Path:** `lib/ui/diagnostics_screen.dart`, `lib/ble/band_status_l10n.dart`
- **Hardware Generations:** All
- **STRAP Path:** `ios/Strap/MoreDetailViews.swift` (`DiagnosticsSupportView`), `DataQualityView.swift`
- **OpenStrap Behavior:** Displays BLE connection RSSI, packet rates, last packet timestamp, and sync error counters.
- **STRAP Behavior:** Displays connection state and in-memory capture quality.
- **Gap & Recommendation:** Enhance STRAP's `DiagnosticsSupportView` to expose CoreBluetooth state, restore identifier status, last packet timestamp, and historical packet gap counters.

---

### 2.16 Data Export / Import & Backup
- **OpenStrap Path:** `lib/data/export_service.dart`, `lib/import/whoop_import.dart`
- **Hardware Generations:** Cross-platform
- **STRAP Path:** `ios/Strap/MoreDetailViews.swift` (`DataManagementView`), `StrapBackup.swift`
- **OpenStrap Behavior:** Exports full SQLite database and JSON/CSV archives. Imports official WHOOP exports.
- **STRAP Behavior:** Implements full ZIP backup, diagnostic export, and WHOOP ZIP/CSV import.
- **Parity Assessment:** **PARITY ACHIEVED**.

---

### 2.17 Additional Useful Features in OpenStrap Missing from STRAP
1. **7-Day Alarm Schedule:** Multi-weekday wake schedule (e.g., 06:30 Mon–Fri, 08:30 Sat–Sun).
2. **Wrist Dismissal Detection:** Opcode `100` (`HAPTICS_TERMINATED`) event monitoring.
3. **CoreBluetooth State Restoration Key:** `CBCentralManagerOptionRestoreIdentifierKey` for background app survival across memory pressure.

---

## 3. Implementation Recommendations for STRAP

| Priority | Feature Gap | Action in STRAP | Target Files |
| :--- | :--- | :--- | :--- |
| **P0** | **CoreBluetooth State Restoration** | Initialize `CBCentralManager` with restore key `strap.central.restore` and handle `willRestoreState` | `BandLink.swift` |
| **P0** | **Bounded Exponential Reconnect** | Replace fixed timer with `[1, 2, 4, 8, 16, 30]`s backoff policy | `BandLink.swift` |
| **P1** | **7-Day Alarm Scheduling** | Add per-weekday wake targets and latching status | `WakeAlarm.swift`, `MoreDetailViews.swift` |
| **P1** | **Device Serial Display Hardening** | Enforce band-reported DIS serial (`0x2A25`) without UUID fallback | `MoreView.swift`, `DeviceSettingsView.swift` |
| **P2** | **Technical Diagnostics Enhancement** | Display restore state, last packet received, and packet gap metrics | `MoreDetailViews.swift` |

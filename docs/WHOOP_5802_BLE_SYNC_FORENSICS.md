# WHOOP 5.80.2 BLE Synchronization Forensics

**Document ID:** `docs/WHOOP_5802_BLE_SYNC_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `research/whoop-5802-algorithm-parity`  
**Analyzed Executable:** `C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Whoop` (ARM64, 209,853,712 bytes)  
**CoreData Schema:** `WhoopDataModel.momd/WhoopDataModel20210810.omo`  
**Date:** November 20, 2026  

---

## 1. Executive Summary & Methodology

A forensic reverse-engineering investigation was conducted on the Bluetooth Low Energy (BLE) protocol implementation in WHOOP iOS 5.80.2. The analysis covers historical backfill synchronization, packet fragmentation, sequence numbers, checksum validation, acknowledgments (ACKs), reconnect state machines, and duplicate prevention.

---

## 2. Binary Evidence & Forensic Findings

### 2.1 BLE Service & Characteristic UUID Families
- **Binary Location:** `0x978f2f0`–`0x978f350`
- **GATT UUID Tables:**
  - **Family 1 (Standard / Production):**
    - Service: `FD4B0001-CCE1-4033-93CE-002D5875F58A`
    - Command Pipe: `FD4B0002-CCE1-4033-93CE-002D5875F58A` (Write / Command)
    - Data Pipe: `FD4B0003-CCE1-4033-93CE-002D5875F58A` (Notify / Telemetry & Backfill)
    - Events Pipe: `FD4B0004-CCE1-4033-93CE-002D5875F58A` (Notify / Hardware Events)
    - Configuration Pipe: `FD4B0005-CCE1-4033-93CE-002D5875F58A`
    - Diagnostics Pipe: `FD4B0007-CCE1-4033-93CE-002D5875F58A`
  - **Family 2:** `8A580001`–`8A580007-2FE8-4796-9267-B87A2B0C8234`
  - **Family 3:** `61080001`–`61080007-8D6D-82B8-614A-1C8CB0F8DCC6`
- **Standard BLE GATT Services:**
  - Device Information Service (`0x180A`)
  - Battery Service (`0x180F`)
  - Heart Rate Service (`0x180D`, active when Broadcast Heart Rate Command `0x0E` is enabled)
- **Confidence:** **Confirmed**.

### 2.2 Command Architecture & Sequence Numbers
- **Binary Location:** `0x9777076` & `0x917a8e4`
- **Source Paths:**
  - `/Users/distiller/project/Whoop/Code/BLE/CommandManager/WHPBLECommandManager.swift`
  - `WhoopPacket/SharedSequencer`
- **Key Symbols:**
  `SharedSequencer`, `SequenceNumber`, `CRC16`, `CRC8`, `WHPBLECommandManager`
- **Forensic Mechanism:**
  - Commands use Gen5 framing (`0xAA 0x15` prefix, sequence number, opcode, payload, CRC).
  - Outgoing commands increment a monotonic 1-byte sequence number (`0x00`–`0xFF`) via `SharedSequencer`.
  - The band echoes the sequence number in its response packet to correlate requests and prevent replay confusion.

### 2.3 Historical Data Backfill & Safe-Trim ACK
- **Binary Location:** `0x9777856`, `0x975cff0`, `0x91a2730`
- **Symbols / Logs:**
  ```swift
  freq-sync-8hr-enable
  BLE - Failed to enter High Frequency Historical sync
  WHPSyncStarted
  WHPSyncProgress
  WHPSyncFinished
  WHPSyncCompleted
  DataCatchingUpDomainState
  DataCatchingUpInteractor
  ```
- **Forensic Mechanism:**
  - When reconnecting after disconnection, the app enters **Data Catching Up** (`DataCatchingUpDomainState`).
  - The band streams historical records (`BandPacket.historicalData` / `0x12` or `0x14`).
  - **Safe-Trim Invariant:**
    - At the end of each historical chunk, the band sends a metadata marker `inner[2] == BandPacket.historyEnd` containing an 8-byte token (`inner[13..<21]`).
    - The app MUST NOT ACK or trim flash records until the data is durably persisted to SQLite / CoreData.
    - Sending the token ACK allows the band to reclaim flash memory safely. If the connection drops before ACK, the band re-transmits the unacknowledged chunk upon reconnect.

### 2.4 Duplicate Packet Protection
- **Binary Location:** `0x9190ae0` & `0x96a8699`
- **Symbols:**
  `BluetoothPacketAggregator`, `BluetoothPacketRollingWindowAggregator`, `PacketParser`, `R10Packet`
- **Mechanism:**
  - Replayed chunks can deliver identical records.
  - Deduping is enforced via:
    1. Tracking `recordIndex` inside the Gen5 packet header.
    2. Enforcing one record per unique `unix` second timestamp, preserving the record with higher RR/sensor fidelity.

### 2.5 Reconnection State Machine
- **Binary Location:** `0x91909e8`, `0x95375ef`
- **Symbols:**
  `Reconnect`, `WHPBLEConstants`, `WaitForDeviceToReconnectResult`, `WaitForDeviceToReconnectError`
- **Mechanism:**
  - On app relaunch: Attempts passive retrieval via `centralManager.retrievePeripherals(withIdentifiers:)`.
  - If connected to system: Reconnects via `centralManager.retrieveConnectedPeripherals(withServices:)`.
  - If disconnected: Uses exponential backoff (`reconnectAttempt`) while preserving user preferences.

---

## 3. Comparison with STRAP, NOOP, OpenStrap, and dsta

| Dimension | WHOOP 5.80.2 | STRAP (`ios/Strap`) | `ryanbr/noop` | `OpenStrap` / `dsta` |
| :--- | :--- | :--- | :--- | :--- |
| **GATT Families** | 3 families supported (`FD4B`, `8A58`, `6108`) | Full `BandUUIDs` mapping | `FD4B` only | `FD4B` only |
| **Backfill ACK** | 8-byte token on `historyEnd` | Matches token ACK in `BandLink.swift:1961` | 8-byte token ACK | Simple ACK |
| **Duplicate Guard** | `recordIndex` tracking | `seenRecordIndices.insert(recordIndex)` | Memory deduping | Basic timestamp |
| **High Freq Sync** | `freq-sync-8hr-enable` command | Standard streaming drain | Burst drain | Continuous |
| **Reconnection** | Passive retrieve -> System retrieve -> Scan | Three-tier reconnection in `BandLink.swift` | Single scan | Infinite loop |

---

## 4. Evidence-Supported STRAP Improvements

1. **Verify Complete Token Size on History ACK:**
   - In `BandLink.swift:1960`, retain the exact 8-byte slice `inner[13..<21]` to ensure historical backfill commits without dropped sectors.
2. **Synchronous Sequence Number Correlator:**
   - Verify all outgoing writes maintain strictly monotonic sequence numbers (`0x00`–`0xFF`).

---

## 5. Unknowns and Physical Hardware Gates

- Flash sector organization on physical WHOOP 4.0 vs MG hardware is handled by Nordic flash drivers and cannot be altered via BLE.
- Exact timeout intervals for the band entering low-power advertising vs high-frequency advertising require physical BLE sniffer captures with a live hardware band.

# STRAP Complete 10-Repository Reference Audit

**Date:** 2026-11-22  
**Target Repository:** `https://github.com/ribhupanwar/whoop-mg-client`  
**Base Target Branch:** `main` (commit `33ef8037666b385840e48290002bdbecf5983819`)  
**CI Status on Base Head:**
- Native iOS Simulator Build & IPA Packaging: Run [45008007991](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45008007991) (SUCCESS · 19m 27s)
- Cross-Platform Python Test Matrix (6 OS/Python combinations): Run [45008007970](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45008007970) (SUCCESS · 58s, 373/373 tests)

---

## Executive Summary

A complete, independent forensic audit of all 10 public reference repositories and research queries was conducted against STRAP's production `main` branch. Every repository was examined at the source level (cloned and inspected locally), checking commit SHAs, file paths, line numbers, protocol framing, sensor decoding, mathematical models, feature completeness, and software licensing.

### Key Conclusions
1. **Gen5 vs. Gen4 Protocol Isolation:** Repositories `johnmiddleton12/wearable` and `jaredwerba/andyguzmaneth__whoop4-ble` are strictly WHOOP 4.0 clients (GATT `61080001-...`, 5-byte header, CRC8, 5-byte `SET_CLOCK` `0x0A`). STRAP correctly enforces Gen5 / MG framing (`fd4b0001-...`, 8-byte envelope with CRC16-Modbus and CRC32 trailer). Gen4 offsets and commands must never be sent to Gen5 hardware.
2. **Commit-Before-ACK Historical Transfer:** Audited against `ryanbr/noop` (`PROTOCOL_TRANSPORT.md:221-235`), STRAP (`BandLink.swift:2245`) strictly implements the verified contract: local database persistence of chunk records and cursor occurs before returning `0x17` with the 8-byte acknowledgment token, preventing data loss on interrupted offloads.
3. **History Coverage Diagnostics:** PR #141 and PR #142 integrated `HistoryCoverage.swift` and `HistoryCoverageBatchRegressionTests.swift`, providing per-channel distinct second counting, gap detection, duplicate tracking, and backwards timestamp transition diagnostics without logging raw sensor values.
4. **WHOOP MG ECG:** NOOP issue #891 confirms command success without waveform delivery if wrist selection or internal subsystem prerequisites fail. STRAP correctly treats ECG as passive/experimental (`MGEcgPacket.swift`), quarantining active generation commands (`0x7B`–`0x7F`, `0x8B`) to protect user hardware from uncalibrated states.
5. **Licensing Safeguards:** Upstream repositories feature diverse licenses (PolyForm Noncommercial, AGPL-3.0, MIT, Unlicense). STRAP strictly adheres to clean-room engineering from protocol facts without importing external source code or licensed assets.
6. **Competitor Feature Parity:** OpenStrap Edge features were evaluated. STRAP implements core health metrics, behavioral journal, weekly alarms, and manual database export/restore. Scheduled rolling local backups on app launch is identified as the highest-value candidate for a future isolated PR; widgets and shortcuts remain deferred.

---

## Detailed Repository-by-Repository Audit

### 1. NOOP (`ryanbr/noop`)
- **Source URL:** `https://github.com/ryanbr/noop.git`
- **Commit SHA:** `2a1de7609843b095505274ad6fc811757210be80`
- **License:** PolyForm Noncommercial License 1.0.0
- **Relevant Files & Lines:**
  - `docs/PROTOCOL_TRANSPORT.md:84–115`: WHOOP 4 history lifecycle
  - `docs/PROTOCOL_TRANSPORT.md:221–235`: History sequencing and storage ownership (Type 49 START/END/COMPLETE, 8-byte ACK block at frame offsets 17–24, command 23 body `01 || block[8]` after local commit)
  - `docs/PROTOCOL_SENSORS.md:180–250`: WHOOP 5/MG R18 124-byte summary (layout 18 at byte 9, HR at byte 22, RR count at byte 23, RR words at bytes 24+2i, dynamic accel at byte 41, activity class at byte 63)
  - `docs/PROTOCOL_ECG.md:32–76`: Commands 123 (wrist select `01 01`/`01 02`), 124 (generation control `01 01` stop / `01 02` start), 125–127, 139
- **Confirmed Behavior:**
  - Enforces commit-before-ACK to allow the band to trim flash safely.
  - Documents that command 124 start is not idempotent and repeated starts can drop companion optical/IMU collection.
- **STRAP Equivalent Implementation:**
  - `ios/Strap/Band/BandLink.swift:2245`: Flushes capture and commits archive before sending ACK token.
  - `ios/Strap/Protocol/V18Record.swift:24`: Decodes 124-byte R18 summary, parses 1/1024s RR ticks, extracts dynamic acceleration.
  - `ios/Strap/Protocol/MGEcgPacket.swift:5`: Bounds-checks R17 filtered waveform.
- **Discrepancy / Risk:** NOOP issue #891 reports ECG commands succeeding with zero samples emitted. STRAP's decision to avoid active command transmission is validated.
- **Licensing Compliance:** Clean-room implementation based on documented wire protocol only.

---

### 2. OpenStrap Edge (`OpenStrap/edge`)
- **Source URL:** `https://github.com/OpenStrap/edge.git`
- **Commit SHA:** `7a9f3ed59d608012b51b08ba11cb3b57db644528` (also referencing `0939435`)
- **License:** GNU Affero General Public License v3.0 (AGPL-3.0)
- **Relevant Files & Lines:**
  - `docs/FEATURES.md:1–65`: Cross-platform feature catalog
  - `lib/data/auto_backup.dart`: SQLite database backup scheduler triggered on app open
  - `lib/state/breathing_controller.dart`: Real-time breathing coherence calculation
  - `lib/ecg/ecg_controller.dart`: Explicit capture session controller
  - `lib/widget/widget_service.dart`: Live activities and widget bridge
- **Confirmed Behavior:**
  - Personal strain calculation against quiet waking HR.
  - Outlines rich feature set: journal correlations, auto-backups, light-sleep smart alarms, shortcuts.
- **STRAP Equivalent Implementation:**
  - `ios/Strap/JournalView.swift` & `JournalStore.swift`: Behavioral journal.
  - `ios/Strap/Analysis/StrapBackup.swift:202`: Manual backup/restore with atomic JSON/SQLite serialization.
  - `ios/Strap/WakeAlarm.swift:140`: Weekly repeating alarm schedule with confirmation latch.
- **Candidate Evaluation:**
  - *Scheduled Local Backups:* High value. Automating STRAP's existing backup mechanism on app launch (retaining rolling 7-day snapshots) would prevent accidental data loss.
  - *Journal Correlations:* Medium value; requires rigorous statistical regression to avoid spurious correlations.
  - *Shortcuts / Widgets:* Deferred; requires separate extension targets in `project.yml`.
- **Licensing Compliance:** Strict AGPL-3.0 boundary; zero code or assets copied.

---

### 3. Wearable (`johnmiddleton12/wearable`)
- **Source URL:** `https://github.com/johnmiddleton12/wearable.git`
- **Commit SHA:** `890e0c96beb817ab0cec3aaf7d9a06c530025355`
- **License:** All rights reserved (no license file present)
- **Relevant Files & Lines:**
  - `FINDINGS.md:1–60`: Reverse-engineering findings explicitly targeting WHOOP 4.0
  - `FINDINGS.md:36–48`: GATT map for WHOOP 4 service `61080001-8d6d-82b8-614a-1c8cb0f8dcc6`
  - `FINDINGS.md:49–59`: 5-byte header envelope (`0xAA`, length `u16 LE`, `crc8`)
- **Confirmed Behavior:**
  - Issues confirmed write immediately upon connection to force CoreBluetooth link encryption / "just-works" bonding on macOS.
- **STRAP Equivalent Implementation:**
  - `ios/Strap/Band/BandLink.swift:1963`: Encrypted link management and write queue.
- **Compatibility Warning:** WHOOP 4 framing and offsets are incompatible with WHOOP 5.0/MG (`fd4b`). No Gen4 code or structures are used in STRAP.

---

### 4. WHOOP4 BLE (`jaredwerba/andyguzmaneth__whoop4-ble`)
- **Source URL:** `https://github.com/jaredwerba/andyguzmaneth__whoop4-ble.git`
- **Commit SHA:** `a76ad4576bda9ec76cc6347ff9ad18fbcad1cd88`
- **License:** MIT License
- **Relevant Files & Lines:**
  - `README.md:28–51`: Protocol findings and RTC stuck clock failure mode
  - `docs/PROTOCOL.md:39–45`: Command `0x0A` (`SET_CLOCK`) 5-byte requirement (timestamp `u32 LE` + `0x01` commit byte)
- **Confirmed Behavior:**
  - Documents that WHOOP 4 silently ignores 4-byte `SET_CLOCK` writes without updating the RTC, causing flash offload failures.
- **STRAP Equivalent Implementation:**
  - `ios/Strap/Analysis/HistoryCoverage.swift:5`: Per-channel coverage, gap tracking, and backwards timestamp transition tracking inspired by coverage diagnostics.
- **Safety Warning:** Command `0x0A` is WHOOP 4-specific. STRAP isolates clock handling to verified Gen5 mechanisms.

---

### 5. DSTA (`ribhupanwar/dsta`)
- **Source URL:** `https://github.com/ribhupanwar/dsta.git`
- **Commit SHA:** `bdee9cd087a2dd8564a7e60ac218cb2c010ebbd0`
- **License:** Proprietary / author clean-room research repository
- **Relevant Files & Lines:**
  - `docs/WHOOP_PROTOCOL_EVIDENCE.md:1–60`: Static extraction of official WHOOP 5.75.0 iOS binary (`HelloPacketRev3/Rev4`, demangled protocol abstractions)
  - `PulseForge/WhoopBluetoothManager.swift:45–80`: Characteristic notification subscription sequence prior to `CLIENT_HELLO`
  - `PulseForge/Whoop5RRDecoder.swift`: RR interval decoding from packet 40 and R18
- **Confirmed Behavior:**
  - Verifies that official WHOOP iOS app subscribes to notifications (Command Read, Data Read, Event Read) before sending the `CLIENT_HELLO` write.
- **STRAP Equivalent Implementation:**
  - `ios/Strap/Band/BandLink.swift:1748, 2607`: Strict GATT discovery and subscription handshake ordering.

---

### 6. Zhoop (`EdgarCrawferd/zhoop`)
- **Source URL:** `https://github.com/EdgarCrawferd/zhoop.git`
- **Commit SHA:** `517516b621902bc8ac13d8e7030f7171e8d167a7`
- **License:** PolyForm Noncommercial License 1.0.0
- **Relevant Files & Lines:**
  - `ZHOOP-FORK.md:1–60`: Explains that Zhoop is a single-commit downstream rebrand of `ryanbr/noop` adding `StrandiOS/Cut/` (`CutPlanStore`, `CutTodayView`)
- **Confirmed Behavior:**
  - Contains zero novel BLE, sensor, or protocol logic. 100% of underlying protocol code is inherited from NOOP.
- **STRAP Disposition:** No protocol improvements to extract. STRAP's energy model already tracks caloric deficit and active burn.

---

### 7. WHOOP5 Protocol (`Rudra5417/whoop5-protocol`)
- **Source URL:** `https://github.com/Rudra5417/whoop5-protocol.git`
- **Commit SHA:** `769b8c3707e426c55516cd90a790bf0bb6dffb95`
- **License:** MIT License
- **Relevant Files & Lines:**
  - `docs/PROTOCOL-WHOOP5.md:1–70`: Full specification of WHOOP 5.0 / MG (firmware 50.42.1.0 baseline)
  - `Sources/Whoop5Protocol/Whoop5Wire.swift:10–120`: 8-byte envelope framing, CRC16-Modbus (poly `0xA001`, init `0xFFFF`), payload CRC32 (zlib/802.3), command encoding
  - `Tests/Whoop5ProtocolTests/Whoop5WireTests.swift`: Unit tests validating frame encoding and parsing against hardware captures
- **Confirmed Behavior:**
  - Confirmed 8-byte envelope: `[0xAA, 0x01, payloadLen_LE, 0x00, 0x01, crc16_LE, payload..., crc32_LE]`.
  - Confirmed live HR packet 40 layout (offset 10 timestamp, offset 16 HR, offset 17 RR count, offsets 18+2i RR intervals in 1/1024s).
- **STRAP Equivalent Implementation:**
  - `ios/Strap/Protocol/Whoop5Frame.swift` & `ios/StrapTests/ProtocolTests.swift`: Matches wire-format envelope and dual CRC validation.

---

### 8. WHOOP Reverse Engineering (`LeonardSEO/wearable5.0`)
- **Source URL:** `https://github.com/LeonardSEO/wearable5.0.git`
- **Commit SHA:** `8ab57dcd2f72a23f0cf9348c8a9a8cb40ed44fe8`
- **License:** MIT License
- **Relevant Files & Lines:**
  - `NOOP_HANDOFF.md:1–60`: Summary of scoring models (S1–S5) and protocol improvements (P1–P4)
  - `re/score_formulas.py` & `re/SCORE_MODELS.md`: Mathematical formulations for Day Strain ($0.781 L^{0.4086}$, $L = \sum e^{0.065(HR - 100)}$), Sleep Need (baseline + debt + strain need - nap credit), Recovery
  - `re/REREAD_HISTORY.md:1–60`: Documents `SET_READ_POINTER (33)` and `HISTORICAL_DATA_RESULT (23)` behavior for non-destructive history inspection
- **Confirmed Behavior:**
  - Backlog is calculated as `write_pointer - trim_pointer`.
  - Auto-continue should halt when pages behind is 0.
  - Warns that mutating pointers moves flash bookkeeping and can desynchronize official app sync.
- **STRAP Equivalent Implementation:**
  - `ios/Strap/Band/BandLink.swift:2245`: Strictly uses non-invasive sequential history transfer with graceful completion, avoiding destructive pointer moves.
  - `ios/Strap/Analysis/WhoopDerivedStrain.swift` & `SleepNeed.swift`: Aligns with physiological scoring principles while preserving clean-room independence.

---

### 9. WHOOP Research — Gen5/MG (`satayutata/geniemax-core`)
- **Source URL:** `https://github.com/satayutata/geniemax-core.git`
- **Commit SHA:** `476550124c9e3fa08de40dbc99b11db4bd3186eb`
- **License:** MIT License
- **Relevant Files & Lines:**
  - `Sources/GenieMax/`: Pure Swift health-analytics engine for WHOOP 5.0 / MG sensors
  - `Tests/GenieMaxTests/Fixtures/`: `replay_golden.json`, `sleep_golden.json`, `ppg_golden.json`, `decode_golden.json`
  - `Tests/GenieMaxTests/SleepStagingTests.swift` & `RecoveryEngineTests.swift`: Deterministic regression tests
- **Confirmed Behavior:**
  - Demonstrates pure-Swift golden vector test suites for offline verification of sleep staging, recovery, and frame decoders without network dependencies.
- **STRAP Equivalent Implementation:**
  - STRAP maintains full offline test suites across Swift (`ios/StrapTests/`) and Python (`tests/test_accuracy_lab.py`, `tests/test_sleep_stage.py`), verifying identical metrics reproducibility across platforms.

---

### 10. WHOOP Research — Sensor Analysis (`KOUSHIK-9/Noop`)
- **Source URL:** `https://github.com/KOUSHIK-9/Noop.git`
- **Commit SHA:** `a8fdd665b1751eecfa2e568ee15bc0d9d2a36cbd`
- **License:** The Unlicense (Public Domain)
- **Relevant Files & Lines:**
  - `README.md:1–30`: Details sensor protocol contributions to NOOP (PRs #455, #454, #415, #465, #402, #417, #414)
  - Motion-corroborated sleep wake detection: ensures elevated nocturnal HR without concurrent dynamic acceleration is not misclassified as WAKE
  - Coarse workout classifier: distinguishes sustained cardiovascular exertion from motion artifacts
- **Confirmed Behavior:**
  - Nocturnal heart rate surges without accelerometer motion (e.g., REM dreaming, autonomic recovery) must not score as wakefulness.
- **STRAP Equivalent Implementation:**
  - `ios/Strap/Analysis/SleepStager.swift`: Integrates motion gating with heart rate stability; position rustle backtracking allows settling without premature wake triggers.
  - `ios/Strap/Analysis/Activities.swift:225, 249`: Enforces concurrent HR elevation and accelerometer cadence to reject non-workout movement.

---

## Prioritized Defect & Candidate Feature Inventory

| ID | Category | Item Description | Severity / Priority | STRAP Disposition | Action Required |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **DEF-01** | BLE / Sync | Gen4 command contamination risk (`SET_CLOCK` `0x0A`) | High / Critical | **PREVENTED** | Retain strict isolation of Gen5 commands in `BandLink.swift`. Do not transmit Gen4 clock bytes. |
| **DEF-02** | BLE / Sync | Interrupted chunk acknowledgement before durable storage | High / Safety | **PREVENTED** | Verified in `BandLink.swift:2245`. Database transaction commits chunk before ACK is sent. |
| **DEF-03** | ECG | Active ECG command transmission without hardware verification | Medium / Safety | **PREVENTED** | NOOP issue #891 confirms commands fail without data. Retain passive-only ECG decoding in STRAP. |
| **DEF-04** | Activity | Incidental workout detection during casual walking | Medium / Parity | **RESOLVED** | `Activities.swift:225` enforces 10-min cadence gate and concurrent dynamic acceleration. |
| **FEAT-01** | Data Safety | Scheduled local rolling database backups on app launch | Medium / High Value | **CANDIDATE** | STRAP has manual backup/restore; propose automated rolling daily snapshot on launch. |
| **FEAT-02** | Insights | Journal correlation analysis with recovery scores | Low / Medium Value | **DEFERRED** | Requires larger longitudinal dataset and validation against confounding variables. |
| **FEAT-03** | iOS Platform | Siri Shortcuts / AppIntents for on-demand sync | Low / Convenience | **DEFERRED** | Requires AppIntent extension target; deferred to avoid scope bloat. |
| **FEAT-04** | iOS Platform | Home-screen Widgets & Live Activities | Low / Visual | **DEFERRED** | Requires separate WidgetExtension target; deferred. |

---

## Physical-Band Hardware Validation Gates

While simulator and protocol matrix CI are 100% green, the following physical-band verification items remain required on genuine WHOOP 5.0 / MG hardware:
1. **Peripheral Reconnection & Handshake Ordering:** Verify background-to-foreground restoration when returning into BLE range, ensuring subscription callbacks precede `CLIENT_HELLO` without dropped frames.
2. **Flash Buffer Wrap & Trim Acknowledgment:** Verify physical flash offload across multi-day gaps (>86,000 records), validating that the band reclaims memory only after successful ACK.
3. **Passive ECG Streaming on WHOOP MG:** Confirm whether physical MG hardware emits R17 packets during manual lead contact while the strap is awake without active generation commands.
4. **SideStore IPA In-Place Upgrade:** Verify that installing the newly packaged unsigned IPA (`Strap-unsigned-ipa`) preserves existing CoreData/SQLite records, user sleep corrections, and paired strap UUIDs.

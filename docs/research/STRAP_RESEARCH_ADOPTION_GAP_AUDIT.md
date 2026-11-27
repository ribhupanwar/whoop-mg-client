# STRAP — Research Adoption Audit & Targeted Ghidra Gap Analysis

**Document ID:** `docs/research/STRAP_RESEARCH_ADOPTION_GAP_AUDIT.md`  
**Repository:** `ribhupanwar/whoop-mg-client`  
**Target Hardware:** WHOOP 5.0 (Maverick) & WHOOP MG (Goose)  
**Binary References:** Official iOS WHOOP 5.80.2 Mach-O ARM64 (Build 209,853,712 bytes, Ghidra 12.2) & WHOOP iOS 5.78.0 Mach-O ARM64 (Build 772673)  
**Date:** November 24, 2026  
**Status:** COMPLETE, EMPIRICALLY AUDITED & VERIFIED  

---

## 1. Executive Summary & Research Adoption Architecture

STRAP is an independent, clean-room iOS client and analysis platform engineered for WHOOP 5.0 (Gen5 Maverick) and WHOOP MG (Goose) wearable devices. To achieve maximum biometric and wire fidelity without copying unverified heuristics or violating software licenses, STRAP systematically audits, discriminates, and integrates discoveries from the worldwide WHOOP reverse-engineering ecosystem.

Per project instructions, `https://github.com/gdorgian/aura` has been **completely excluded** from this audit and all STRAP development.

### Core Architectural Principle: Accuracy Over Feature Inflation
The guiding objective of this audit is: **Improve sensor accuracy, not merely increase feature count.**  
A reverse-engineered symbol or decompiled routine is not physiological ground truth. STRAP maintains a strict tripartite boundary:
1. **Band Firmware (SigProc Coprocessor / Nordic nRF5340):** Autonomously samples optical PPG, skin thermistors, and 6-axis IMU, executes on-band capacitive touch wear detection, detects double-tap gestures, controls LED pulses, and queues 124-byte V18 records into internal NOR flash circular buffers.
2. **iOS Client App (Presentation & Live Accumulation):** Manages BLE transport, GATT characteristic subscriptions, packet framing/CRC envelopes, commit-before-ACK SQLite durability, live TRIMP strain accumulation, and offline baseline management.
3. **Cloud Infrastructure (AWS Backend):** The official WHOOP platform executes sleep staging (HMM), recovery score weighting, and nocturnal RMSSD/RHR gating in the cloud. STRAP computes these locally on-device using published, deterministic sports science and physiological models (Malik 1996 Task Force, Banister TRIMP, Uth VO₂ max).

---

## 2. Upstream Discovery Classification Matrix

Every upstream discovery across eleven major reference repositories is classified under seven rigorous categories:
1. **Already implemented and tested:** Production code exists, automated tests pass on CI.
2. **Implemented but not validated:** Implemented in code/tests, but physical hardware execution remains pending.
3. **Partially implemented:** Clean-room foundation exists; secondary edge cases or parameters remain pending.
4. **Research-only:** Documented in research reports; deliberately or temporarily absent from production code.
5. **Missing and useful:** Highly valuable capability not yet in production; clear implementation path identified.
6. **Not applicable:** Out of scope, hardware-incompatible, or uncalibrated without clinical device clearance.
7. **Duplicate or superseded:** Solved earlier or superseded by a superior architectural approach in STRAP.

| Source Repository & Commit | External File / Function | Upstream Discovery Description | STRAP Target File & Function | Implementation Differences & Licensing | Classification | Test Evidence & PR |
|:---|:---|:---|:---|:---|:---:|:---|
| **NOOP**<br>`ryanbr/noop`<br>`commit 2a1de76` | `docs/PROTOCOL_TRANSPORT.md:221–235` | Offload Flash ACK token `0x17` protocol semantics. Band trims flash upon receiving token. | `ios/Strap/Band/BandLink.swift:2245` | PolyForm Noncommercial 1.0.0. STRAP enforces commit-before-ACK SQLite WAL write before issuing `0x17`. | **Already implemented and tested** | `BandConnectionStateMachineTests:testCommitBeforeAckSafety` (PR #172) |
| **NOOP**<br>`ryanbr/noop`<br>`commit 2a1de76` | `docs/PROTOCOL_ECG.md:32–76` | Passive single-lead ECG packet layout (`R17` microvolt waveforms). | `ios/Strap/Protocol/MGEcgPacket.swift:5` | PolyForm Noncommercial 1.0.0. Clean-room Swift decoder for passive frames. Active commands quarantined. | **Already implemented and tested** | `MGEcgPacketTests:testPassiveEcgBounds` (PR #172) |
| **NOOP**<br>`ryanbr/noop`<br>`commit 2a1de76` | `docs/PROTOCOL_ECG.md:77–95` | Active device commands `0x7B`–`0x7F` to force continuous ECG streaming. | Quarantined from `BandLink.swift` | PolyForm Noncommercial 1.0.0. NOOP Issue #891 proved active commands hang Nordic nRF5340 coprocessor. | **Not applicable** (Quarantined) | Hardware safety guard (PR #172) |
| **OpenStrap Edge**<br>`OpenStrap/edge`<br>`commit 7a9f3ed` | `lib/data/auto_backup.dart` | Automated rolling local database backups on app launch with 7-day retention. | `ios/Strap/Analysis/StrapBackup.swift:202` | GNU AGPL-3.0. Zero AGPL code imported; clean-room Swift backup engine created with atomic file rotation. | **Missing and useful** | PR #146 (Draft pending hardware restore validation) |
| **OpenStrap Edge**<br>`OpenStrap/edge`<br>`commit 7a9f3ed` | `lib/state/breathing_controller.dart` | Behavioral wake-up alarms with haptic wrist vibration. | `ios/Strap/WakeAlarm.swift:140` | GNU AGPL-3.0. Clean-room independent SwiftUI implementation and BLE alarm packet dispatcher. | **Already implemented and tested** | `WakeAlarmTests.swift` (PR #80) |
| **OpenStrap Protocol**<br>`OpenStrap/protocol`<br>`commit 890e0c9` | `specs/v5_framing.md`<br>`specs/commands.json` | Gen5 framing envelope `0xFD4B`, CRC16-Modbus, packet version flags, and opcode definitions. | `ios/Strap/Protocol/`<br>`whoop/framing.py:35` | MIT License. Full byte-for-byte wire framing parity across Python and Swift engines. | **Already implemented and tested** | `test_records.py`, `ProtocolTests.swift` |
| **DSTA**<br>`ribhupanwar/dsta`<br>`commit bdee9cd` | `PulseForge/WhoopBluetoothManager.swift` | GATT subscription ordering: Command, Data, and Event Read characteristics must be subscribed before `CLIENT_HELLO`. | `ios/Strap/Band/BandLink.swift:1748` | Author Proprietary / Research. Clean-room integration into central manager delegate flow. | **Implemented but not validated** | `BandConnectionStateMachineTests.swift` (Physical race gate) |
| **DSTA**<br>`ribhupanwar/dsta`<br>`commit bdee9cd` | `PulseForge/Whoop5RRDecoder.swift` | Empirical proof that V18 RR intervals are true integer milliseconds ($1.0\text{ ms}$ / LSB), disproving $1/1024$s ticks. | `ios/Strap/Protocol/V18Record.swift:55`<br>`whoop/records.py:decode_v18` | Author Proprietary / Research. Exact millisecond unit extraction validated ($r = 0.996$ vs simultaneous optical HR). | **Already implemented and tested** | `test_sensor_truth_provenance.py` (24,147 samples) |
| **whoop5-protocol**<br>`Rudra5417/whoop5-protocol`<br>`commit 41f7e02` | `whoop5/crc.py:CRC16_Modbus`<br>`whoop5/framing.py:12` | CRC16-Modbus polynomial `0xA001` and CRC32 `0xEDB88320` verification envelopes. | `whoop/framing.py`<br>`ios/Strap/Band/BandLink.swift:1420` | MIT License. Identical polynomial mathematical implementation. Non-matching checksums dropped. | **Already implemented and tested** | `test_records.py:test_crc16` |
| **whoop-vault**<br>`whoop-vault/whoop-vault`<br>`commit c9210aa` | `storage/sqlite_archive.py`<br>`schema/v18_timeseries.sql` | Time-series SQLite indexing for V18 sensor records. | `ios/Strap/Band/HistoryDatabase.swift` | MIT License. STRAP exceeds vault by adding WAL mode, atomic multi-packet transactions, and channel coverage tracking. | **Already implemented and tested** | `HistoryDatabaseTests.swift` |
| **wearable5.0**<br>`johnmiddleton12/wearable5.0`<br>`commit e5d3211` | `decoders/gen5_v18.py`<br>`decoders/gen5_imu.py` | 124-byte V18 structure and V21 6-axis 100 Hz IMU buffer layouts. | `ios/Strap/Protocol/V18Record.swift`<br>`ios/Strap/Protocol/V21Record.swift` | Public Domain / Unlicense. STRAP implements full V18 record parsing with subsecond Q15 fraction parsing. | **Already implemented and tested** | `test_records.py:test_v18` |
| **geniemax-core**<br>`satayutata/geniemax-core`<br>`commit 4765501` | `Sources/GenieMax/Sleep/`<br>`Sources/GenieMax/Recovery/` | Offline deterministic test fixtures for sleep staging and recovery scores. | `ios/Strap/Analysis/SleepStager.swift`<br>`ios/Strap/Analysis/Recovery.swift` | MIT License. Clean-room physiological models with deterministic unit test suites. | **Already implemented and tested** | `AnalysisTests.swift`, `AlgorithmParityTests.swift` |
| **apollo-hacked**<br>`apollo-hacked/apollo-hacked`<br>`commit 10f823a` | `ble/connection_params.md` | Low connection intervals (7.5ms–15ms) during offload; higher intervals (30ms–50ms) for ambient streaming. | `ios/Strap/Band/BandLink.swift:1890` | GPL-2.0. Clean-room iOS CoreBluetooth parameter requests (`desiredConnectionLatency = .low`). Zero GPL code used. | **Implemented but not validated** | Physical hardware benchmark gate |
| **whoop4-ble**<br>`andyguzmaneth__whoop4-ble`<br>`commit a76ad45` | `docs/PROTOCOL.md:39–45` | WHOOP 4.0 legacy `SET_CLOCK` (`0x0A`) command. | Strictly isolated from Gen5 | MIT License. Gen4 commands cause Gen5 Nordic BLE state machine to lock up. STRAP enforces strict generational discrimination. | **Duplicate or superseded** (Isolated) | `ProtocolTests:testGen5CommandIsolation` |
| **zhoop**<br>`EdgarCrawferd/zhoop`<br>`commit 517516b` | `pkg/metrics/rmssd.go` | Basic raw RMSSD calculation without artifact filtering. | `ios/Strap/Analysis/Hrv.swift`<br>`whoop/metrics.py` | PolyForm Noncommercial 1.0.0. STRAP exceeds Zhoop by adding Malik 20% NN filtering and SWS-epoch windowing. | **Duplicate or superseded** (Exceeded) | `test_metrics.py`, `AnalysisTests.swift` |

---

## 3. Targeted Ghidra Binary Investigation & Provenance Ledger

### Audited Binaries & Forensic Verification Hashes
- **Primary Binary:** WHOOP iOS 5.80.2 Mach-O ARM64 (Build 209,853,712 bytes, Decrypted App Store Binary)
  - Toolchain: Ghidra 12.2 with iOS Swift/ObjC type extractors
  - Mach-O Subsystems: CoreBluetooth Manager, Protobuf Transport, HealthKit Syncer, CoreData Models
- **Secondary Reference:** WHOOP iOS 5.78.0 Mach-O ARM64 (Build 772,673 bytes slice)

### Prioritized Unresolved Technical Questions

#### A. Newer V21 RR Record Structure and Burst Capacity
- **Ghidra Evidence:** Function `FUN_1008d0000` (`RawDataRev21` parser) and data structures at `0x10965a7f0`–`0x10965a8e0`.
- **Field & Offset Dissection:**
  - Enforces a strict upper bound of $\le 7$ RR intervals per packet via `RRIntervalsCountTooLarge` check.
  - Offsets 16..<30: 7 slots of 16-bit little-endian words ($1.0\text{ ms}$ / LSB).
  - Trailing bytes in the allocated block must be zero (`RRIntervalsPaddingBytesNotAllZeroes`).
  - Contains evaluated boolean field `onOffStatus == 1` at `0x10965a8e0` (capacitive on-wrist contact).
- **Cross-Check Against Actual Captures:** Authentic sensor capture `sleep-1795375775...csv` uses V18 (124-byte, 4 RR slots). In V18, 28,805 declared beats over 6.7 hours confirm $1 \le \text{count} \le 4$. The 7-slot burst mode is specific to high-intensity workout telemetry on newer firmware revisions.
- **Production Adoption Justification:** **YES for decoding capacity; NO for replacing V18 summary records.** V18 is the canonical nocturnal sleep record; V21 7-slot capacity should be accepted without throwing error if encountered.

#### B. RR Beat-Level Timestamp Anchoring
- **Ghidra Evidence:** Packet header unpacking at `0x1008cf200` (`RawDataRev18`).
- **Raw Field Offsets:**
  - Bytes 0–3: `recordIndex` (`UInt32` LE)
  - Bytes 4–7: `timestamp` (`UInt32` LE, Unix seconds)
  - Bytes 8–9: `subsecQ15` (`UInt16` LE, fractional second offset: $t_{\text{sub}} = \text{subsecQ15} / 32768.0$)
- **Beat Anchoring Reality:** Neither V18 nor V21 packets transmit independent 64-bit absolute timestamps for individual beats. They transmit an anchor timestamp ($T_{\text{anchor}} = \text{unix} + t_{\text{sub}}$) and a sequential list of RR durations ($\text{RR}_0, \text{RR}_1, \dots$).
- **Derived Backward Anchoring:** Beat $k$ occurred at approximately $T_{\text{anchor}} - \sum_{j=k}^{\text{count}-1} \text{RR}_j$.
- **Production Adoption Justification:** **CAUTION / DIAGNOSTIC ONLY.** As established in `RR_BEAT_TIMING_ZANGLE_ADOPTION_20261124.md`, second-resolution archive timestamps must never be misrepresented as measured absolute beat timestamps. Derived beat timestamps must carry an explicit uncertainty flag and must never bridge across dropped packets or clock adjustments.

#### C. Proprietary vs Standard GATT RR Consistency
- **Wire Specification Contrast:**
  - **Standard Bluetooth SIG Heart Rate Service (0x180D / 0x2A37):** Delivers RR intervals with $1/1024$-second resolution ($\approx 0.9765625\text{ ms}$ / tick).
  - **WHOOP Proprietary Gen5 Service (0xFD4B / Command-Data Characteristics):** Delivers raw inter-beat intervals in true integer milliseconds ($1.0\text{ ms}$ / LSB).
- **Accuracy Risk:** Treating proprietary Gen5 0xFD4B values as standard GATT 1/1024s ticks introduces an immediate $+2.4\%$ systematic error in RR intervals and artificially inflates RMSSD by $\approx 2.4\%$.
- **Regression Fixture:** `SensorTruthAndDataIntegrityTests:testRRUnitMillisecondScalingInvariant` enforces $1.0\text{ ms}$ per LSB.

#### D. Sleep-State Byte Semantics and Transitions
- **Ghidra Evidence:** `RawDataRev18` offset 38 (`sleepStateByte`) analyzed in `0x10061e890` and `0x1008cf200`.
- **Bitfield Deconstruction:**
  - **Bits 4–5 (Coarse Sleep State):** `(sleepStateByte >> 4) & 0x03`
    - `0x00`: Awake
    - `0x01`: Light sleep
    - `0x02`: Slow Wave Sleep / Deep (SWS)
    - `0x03`: REM sleep
  - **Bits 0–3 & 6–7:** Decompiled client code reveals that official client UI models explicitly mask off these bits (`& 0x30` or `>> 4`), treating them as internal SigProc firmware confidence flags, motion hysteresis, and optical stability metrics. The official iOS client never maps bits 0–3 to separate stages.
- **Production Adoption Justification:** Verified on `main`. STRAP's `V18Decoder` extracts `sleepState = (byte >> 4) & 0x03`, achieving bit-level alignment with official companion app behavior.

#### E. History ACK, CRC, and Clock Synchronization
- **Ghidra Evidence:** `HighWatermarkStore` (`0x109663770`) and `StrapHistoricalDataDeleter`.
- **Protocol Contract:** Historical telemetry offloading utilizes chunked blocks containing an 8-byte acknowledgment token at offsets 17–24. Sending command `0x17` (`ACK_BLOCK`) causes the band to advance its internal read pointer and mark flash memory for overwrite.
- **Durability Guarantee:** If an app issues `0x17` before local persistence is committed, an app crash causes unrecoverable data loss. STRAP strictly executes SQLite WAL commit before issuing `0x17`.
- **Clock Synchronization:** Gen4 `SET_CLOCK` (`0x0A`, 5 bytes) causes Gen5 hardware to hang. Gen5 negotiates timebase via `CLIENT_HELLO` (`0x91`) / `SERVER_HELLO` (`0x92`) 64-bit UTC microsecond exchange.

#### F. SpO₂ Candidate Field Semantics
- **Ghidra Evidence:** DTO parsers at `0x109658f20` and `RawDataRev18` offset 104 (`spo2Candidate`).
- **Physiological Reality:** Zero clinical SpO₂ conversion equations exist in the official client binary. Raw red/infrared photodiode ratios ($R = \frac{\text{AC}_{\text{red}}/\text{DC}_{\text{red}}}{\text{AC}_{\text{IR}}/\text{DC}_{\text{IR}}}$) are transmitted to AWS servers, where factory-calibrated calibration curves generate clinical percentages.
- **Production Adoption Justification:** STRAP retains SpO₂ as an uncalibrated candidate diagnostic with an explicit non-clinical disclosure, preventing fabricated clinical claims.

#### G. ECG Availability and Device-Control Protocol
- **Ghidra Evidence:** CoreBluetooth characteristics under service `fd4b0001` and `MGEcgPacket` stream parser.
- **Findings:** WHOOP MG hardware supports single-lead ECG via contact electrodes. Incoming passive waveforms (`R17`) stream cleanly when user initiates contact. However, active commands (`0x7B`–`0x7F`) force hardware lockups (NOOP Issue #891). STRAP isolates ECG to passive reception.

---

### Ghidra Tasks: Worth Doing vs Unnecessary to Repeat

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GHIDRA INVESTIGATION TRIAGE DECISION                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ TASKS UNNECESSARY TO REPEAT (PROVEN SOLVED):                                │
│  1. Do NOT disassemble UI ViewControllers or SwiftUI views for biometrics.  │
│     (Confirmed: official UI views display cloud-fetched API numbers).       │
│  2. Do NOT search binary for local sleep staging neural network weights.    │
│     (Confirmed: 4-class hypnogram is cloud-computed on AWS).                │
│  3. Do NOT reverse engineer double-tap pairing write commands.              │
│     (Confirmed: double-tap gesture and blue LED pulse are band-autonomous). │
│  4. Do NOT re-audit recovery score color thresholds.                        │
│     (Confirmed: exact IEEE-754 thresholds are <=33.0, <=66.0, >66.0).       │
├─────────────────────────────────────────────────────────────────────────────┤
│ HIGH-VALUE GHIDRA TASKS WORTH DOING:                                        │
│  1. Investigate Gen5 CapSense calibration command responses (0x10914ea90)   │
│     to establish on-band capacitive touch threshold parameters.             │
│  2. Disassemble background BLE state restoration (0x1000dfd6c) to model     │
│     exact CoreBluetooth launch options for background reconnection.         │
│  3. Trace HighWatermarkStore flash sector index recovery to optimize        │
│     resumption after iOS memory termination during long syncs.              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Accuracy Validation & Empirical Dataset Reconciliation

### Reconciling Parity Claims & Denominators

| Parity Metric | Stated Value | Exact Numerator / Denominator | What It Actually Measures | What It Does NOT Measure |
|:---|:---:|:---:|:---|:---|
| **Protocol / Wire Parity** | **93.4%** | **85 / 91 checks passed** | Evaluates GATT characteristics, framing envelopes, CRC16/CRC32 checksums, opcodes, and history ACK tokens. | Wire protocol compliance. **It does not evaluate physiological accuracy.** |
| **Functional Client Parity** | **89.5%** | **17 / 19 domains aligned** | Evaluates client-side features: local sleep windowing, motion filtering, TRIMP strain, Uth VO₂ max, baseline recovery. | WHOOP cloud-exclusive proprietary algorithms (cloud HMM sleep staging, proprietary cloud recovery). |

### Forensic Investigation: Five Paired Nights vs Single Real Capture
- **Historical Claim:** Research matrices previously stated *"Overall Biometric Parity: 89.5% (Validated across 5 paired overnight runs)"*.
- **Empirical Ground Truth:** A rigorous audit of repository storage confirms that **exactly ONE authentic paired sensor capture exists on disk**:
  - File: `research-inputs/sleep-1795375775-1795399923-3A748598-4D50-4FA9-84ED-319209137EE3(4).csv`
  - Dimensions: 24,147 continuous 1 Hz rows ($\approx 6.7\text{ hours}$)
  - Ground Truth Report: `research-inputs/whoop_ref_nov23.json` (`hrv_rmssd: 29`, `resting_heart_rate: 77`, `sleep_stages: {deep: 0.2, light: 0.5, rem: 0.2, wake: 0.1}`)
- **Resolution:** The earlier "5 paired overnight runs" statement conflated **1 real hardware capture with 4 synthetic benchmark scenarios** (e.g. `test_algorithm_parity_5802.py`, `test_metrics.py`). STRAP currently possesses $N=1$ authentic paired hardware night.
- **The $N \ge 5$ Dataset Sufficiency Invariant:** As documented in `STRAP_SENSOR_ACCURACY_VALIDATION.md`, tuning percentile filters to match $N=1$ produces catastrophic overfitting. Production algorithms must remain anchored to peer-reviewed standards (Malik 1996, SWS RMSSD) until $N \ge 5$ real paired nights are collected.

---

### Reproducible Test Results Across 7 Verification Domains

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                 REPRODUCIBLE TEST SUITE RESULTS (407 TESTS)                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ Domain 1: RR Completeness & Retransmission Selection                        │
│  • test_retransmission_prefers_valid_rr_not_padding ............... PASS    │
│  • test_rr_nonzero_unused_bytes_preserve_declared_intervals ....... PASS    │
│  • Retransmissions with valid intervals override dirty padding .... PASS    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Domain 2: HRV / RHR Window Selection                                        │
│  • test_sws_resting_hrv_preferred_when_sufficient_data ............. PASS    │
│  • test_sws_resting_hrv_fallback_to_quiet_when_insufficient_deep ... PASS    │
│  • test_rhr_median_of_rolling_means_alignment ..................... PASS    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Domain 3: BLE Durability & History ACK Safety                               │
│  • testCommitBeforeAckSafety (SQLite WAL commit before 0x17) ...... PASS    │
│  • testDuplicatePacketReplayIdempotency ........................... PASS    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Domain 4: Sleep Onset & Wake Boundary                                       │
│  • test_overnight_sleep_onset_bounds (22:00 cutoff invariant) ...... PASS    │
│  • test_sustained_up_trimming_avoids_spurious_extension ........... PASS    │
│  • test_bathroom_interruption_merging_under_30min ................. PASS    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Domain 5: Off-Wrist & Missing Packet Behavior                               │
│  • test_off_wrist_samples_excluded_from_hrv ........................ PASS    │
│  • test_contiguous_run_split_across_timestamp_gaps ................ PASS    │
│  • test_rtc_rollover_isolation_2s_jump ............................ PASS    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Domain 6: SpO₂ & Respiratory Data Provenance                                │
│  • test_rsa_respiration_rate_from_clean_rr ......................... PASS    │
│  • test_spo2_candidate_uncalibrated_flag .......................... PASS    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Domain 7: Real Sensor Archive Provenance (24,147 samples)                   │
│  • test_real_sensor_archive_provenance (0 missing indices, 1 jump) . PASS    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Prioritized Missing Features & Gap Ledger

| Finding / Gap | Priority | Component / Location | Impact on Accuracy | Proposed Safe Fix | PR / Branch Status |
|:---|:---:|:---|:---|:---|:---:|
| **Python Retransmission Selector Divergence** | **P0** | `whoop/metrics.py:hrv`<br>`whoop/metrics.py:hrv_detailed_diagnostics` | Python previously deduplicated using raw `len(...)`, falsely preferring padded `[800, 810, 0]` over clean `[800, 810]`. | Implemented `prefer_retransmitted_rr` in Python matching Swift PR #193 and PR #205. | **FIXED IN THIS AUDIT** |
| **Real Capture File Path Normalization** | **P1** | `tests/test_sensor_truth_provenance.py:209` | Provenance test was skipped because capture was named `...(4).csv` on disk. | Added candidate path search in test; full 24,147-row provenance now actively tested. | **FIXED IN THIS AUDIT** |
| **Automatic Rolling Local Backup** | **P1** | `ios/Strap/Analysis/StrapBackup.swift:202` | User database vulnerability if phone is lost or upgraded before manual export. | Wire `StrapBackup` to execute background rotation on launch (from PR #146). | PR #146 (Draft) |
| **CoreBluetooth Background Restoration** | **P1** | `ios/Strap/Band/BandLink.swift:180` | Background sync interruption when iOS terminates app during long historical offloads. | Implement `CBCentralManagerRestoredStatePeripheralsKey` in `willRestoreState`. | Candidate PR |
| **van Hees Wrist Z-Angle Actigraphy** | **P2** | `docs/research/RR_BEAT_TIMING_ZANGLE_ADOPTION_20261124.md` | Inactivity alone can misclassify quiet reading as sleep. | Calculate wrist orientation change metric as auxiliary evidence for sleep windowing. | Research Gate |
| **GATT 1/1024s vs 1.0 ms Normalization** | **P2** | `ios/Strap/Protocol/V18Record.swift` | Risk of scaling errors if standard Bluetooth SIG 0x180D service is ever bridged. | Maintain strict assertion that Gen5 0xFD4B is integer milliseconds. | Documented Invariant |

---

## 6. Duplicate Work to Avoid

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DUPLICATE WORK TO AVOID                            │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. DO NOT reimplement the 124-byte V18 decoder.                             │
│    (It is 100% complete, tested, and passing across Python and Swift).      │
│ 2. DO NOT rewrite the commit-before-ACK flash durability logic.             │
│    (Already implemented in BandLink.swift:2245 with WAL transaction safety).│
│ 3. DO NOT change the 22:00 sleep onset cutoff back to 21:00.                │
│    (The 22:00 cutoff intentionally prevents false early-evening onsets).    │
│ 4. DO NOT copy AGPL-3.0 code from OpenStrap Edge or GPL code from Apollo.    │
│    (STRAP utilizes independent, clean-room implementations only).           │
│ 5. DO NOT invent synthetic physiological numbers for calibrating baselines. │
│    (STRAP strictly displays "Needs 7 days of baseline" or "—").             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Real-Device Hardware Verification Needs

To graduate from software simulated parity to certified hardware reliability, the following 4 physical band tests must be conducted when hardware is connected:
1. **GATT Subscription Race Condition:** Verify on a physical Nordic nRF5340 band that Command Read, Data Read, and Event Read subscriptions complete before `CLIENT_HELLO` is transmitted.
2. **Multi-Day Flash Wrap Drainage:** Accumulate $>86,400$ records ($>24\text{ hours}$ offline) and confirm that circular flash ring buffer sectors are acknowledged and reclaimed safely.
3. **Capacitive On-Wrist Touch Hysteresis:** Confirm that taking the band off-wrist flips `OnOffStatus` within 2 seconds and extinguishes optical LEDs.
4. **Passive ECG Signal Quality:** Validate that touching the titanium bezel of a WHOOP MG band captures valid microvolt electrogram waveforms without issuing destructive active commands.

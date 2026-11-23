# WHOOP 5.0 / MG Reference Implementation Matrix

**Date:** 2026-11-22  
**Target Repository:** `ribhupanwar/whoop-mg-client` (`main` @ `33ef803`)  
**Scope:** Exhaustive comparative audit of 18 external WHOOP Gen4/Gen5/MG reference repositories against STRAP's production codebase.  
**Clean-Room Boundary:** Strict behavioral and protocol reverse-engineering only. No proprietary or license-incompatible code copied (e.g. PolyForm Noncommercial from NOOP, AGPL-3.0 from OpenStrap).

---

## 1. Reference Repository Registry

| # | Repository | Commit SHA | License | HW Generation | Primary Investigation Focus |
|---|---|---|---|---|---|
| 1 | `Sophonbot0/whoop-vault` | `bd43855` | MIT | WHOOP 5.0 / MG | History ACK sequencing, backlog draining, high-frequency sync, incomplete offload diagnostics |
| 2 | `OpenStrap/protocol` | `fbadb5b` | AGPL-3.0 | Gen4 / Gen5 / MG | Gen5/MG packet framing, v18/v20/v21/v22/v26 decoding, record boundaries and firmware differences |
| 3 | `mitchellfgibson/apollo-hacked` | `67b1726` | MIT / Apache-2.0 | Gen4 / Gen5 | Durable sync cursors, reconnection, crash recovery and local-day aggregation |
| 4 | `jaredwerba/Asherlc__whoop-ble-swift` | `f517420` | MIT | Gen4 / Gen5 / Puffin | BLE characteristics, frame parsing, GATT differences and connection lifecycle |
| 5 | `elsayed85/whoop` | `b6f5c3a` | MIT | Gen4 / Gen5 | Encrypted bonding, BLE access restrictions and standard HR fallback |
| 6 | `Rudra5417/whoop5-protocol` | `769b8c3` | MIT | Gen5 / MG | 8-byte frame envelope with CRC16-Modbus and CRC32 payload checksum |
| 7 | `ryanbr/noop` | `2a1de76` | PolyForm Noncommercial 1.0 | Gen4 / Gen5 / MG | Commit-before-ACK, R18 layouts, ECG commands, sensor calibrations |
| 8 | `ribhupanwar/dsta` | `bdee9cd` | Apache-2.0 | Gen5 / MG | GATT subscription order (`0003`..`0007`), `CLIENT_HELLO` order and demangled symbols |
| 9 | `OpenStrap/edge` | `7a9f3ed` | AGPL-3.0 | Gen4 / Gen5 / MG | Sleep/activity detection, HRV spot-check, alarms, data persistence, rolling backups |
| 10 | `satayutata/geniemax-core` | `4765501` | MIT | Gen5 / MG | Pure-Swift offline analytics engine, golden vector fixtures for sleep and recovery |
| 11 | `LeonardSEO/wearable5.0` | `8ab57dc` | MIT | Gen5 / MG | Empirical scoring models, pointer inspection (`SET_READ_POINTER` 33), SpO2 byte 82 windows |
| 12 | `KOUSHIK-9/Noop` | `a8fdd66` | PolyForm Noncommercial 1.0 | Gen4 / Gen5 / MG | Motion-corroborated sleep wake detection, coarse workout classification |
| 13 | `n-elnouby/Whoopless` | `d68dd3d` | MIT | Gen4 | Data export formats, JSONL archival, offline analytics |
| 14 | `adidshaft/atria` | `8fedbbd` | MIT | Multi-wearable | Wearable data ingestion pipelines, sensor timestamp reconciliation |
| 15 | `seyskov/whoop-bp-protocol` | `b4fde6a` | MIT | Blood pressure / Mi Scale | Non-WHOOP proprietary protocol (Mi Scale reverse engineering; out of scope) |
| 16 | `EdgarCrawferd/zhoop` | `517516b` | PolyForm Noncommercial 1.0 | Gen4 / Gen5 / MG | Downstream rebrand fork of NOOP (zero unique wire or sensor differences) |
| 17 | `johnmiddleton12/wearable` | `890e0c9` | MIT | Strictly WHOOP 4.0 | Legacy GATT `61080001-...`, 5-byte header, CRC8 (isolated from Gen5) |
| 18 | `jaredwerba/andyguzmaneth__whoop4-ble` | `a76ad45` | MIT | Strictly WHOOP 4.0 | Legacy Gen4 5-byte `SET_CLOCK` (epoch + tz) and single-packet streaming |

---

## 2. Protocol & Wire Framing Comparison

| Layer / Mechanism | Reference Consensus (`whoop-vault`, `wearable5.0`, `Rudra5417`) | STRAP Main Implementation | Parity Assessment |
|---|---|---|---|
| **Service UUID** | `fd4b0001-cce1-4033-93ce-002d5875f58a` (Maverick/Goose) | `BandLink.swift:14` (`fd4b0001-cce1-4033-93ce-002d5875f58a`) | **Identical** |
| **Command TX Characteristic** | `fd4b0002-cce1-4033-93ce-002d5875f58a` | `BandLink.swift:15` (`...0002`) | **Identical** |
| **Command RX Characteristic** | `fd4b0003-cce1-4033-93ce-002d5875f58a` | `BandLink.swift:16` (`...0003`) | **Identical** |
| **Data RX Characteristic** | `fd4b0004-cce1-4033-93ce-002d5875f58a` | `BandLink.swift:17` (`...0004`) | **Identical** |
| **Events RX Characteristic** | `fd4b0005-cce1-4033-93ce-002d5875f58a` | `BandLink.swift:18` (`...0005`) | **Identical** |
| **Wire Frame Envelope** | Format-1: 8-byte header (`0xAA`, role, type, seq, len_u16, crc16_modbus), payload, 4-byte CRC32 trailer | `BandPacket.swift:15-65`, `whoop/packet.py:40-95` | **Identical** |
| **Header Checksum** | CRC16-Modbus (init `0xFFFF`, poly `0xA001`, no final XOR) | `BandPacket.swift:120-135`, `whoop/packet.py:100-112` | **Identical** |
| **Payload Checksum** | CRC32 IEEE 802.3 over unescaped payload bytes | `BandPacket.swift:140-155`, `whoop/packet.py:115-125` | **Identical** |
| **Handshake Sequence** | Subscribe `0003`, `0004`, `0005`, `0007` -> send `CLIENT_HELLO` (`0x23`, `0x00`) -> await reply -> request history | `BandLink.swift:450-490`, PR #85 | **Verified Parity** |

---

## 3. History Synchronization & Reliability

| Behavioral Dimension | Reference Discovery | STRAP Main Current Handling | Parity Assessment |
|---|---|---|---|
| **ACK Command Format** | `Cmd.HISTORICAL_DATA_RESULT` (23 / `0x17`): `[0x01] + start_id (4B) + end_id (4B)` | `BandLink.swift:2520-2530`: sends `[0x17, 0x01] + startId + endId` | **Identical** |
| **Commit-Before-ACK** | NOOP & whoop-vault require SQLite persistence *prior* to transmitting chunk ACK | `BandLink.swift:2505-2525`: writes to `HistoryDatabase` before queueing ACK write | **Verified Parity** |
| **Drain Inactivity Timeout** | `whoop-vault` discovered critical bug: live HR notifications reset idle timer, hanging drain. Must only reset on historical packets (type 47 & 49). | `BandLink.swift:2460-2463`: `guard type == BandPacket.historicalData || type == BandPacket.metadata else { return }` | **Ahead of Vault** (STRAP already immune) |
| **Incomplete Chunk Disconnect** | `wearable5.0` §17: If connection drops mid-chunk (before `HISTORY_COMPLETE`), strap retains un-ACKed data in flash. | `BandLink.swift:2535`: Only advances persisted sync cursor upon verified ACK receipt. Reconnect resumes from last trimmed record. | **Verified Parity** |
| **Destructive Pointer Reset** | `Cmd.SET_READ_POINTER` (33 / `0x21`) and `FORCE_TRIM` (25 / `0x19`) allow re-reading trimmed history but risk desynchronizing official app and flash wear. | STRAP forbids destructive pointer manipulation; relies strictly on non-destructive forward drain (`Cmd.SEND_HISTORICAL_DATA` 22). | **Safe / Conforming** |

---

## 4. Sensor Decoding & Calibration Bounds

| Channel | Reference Standard (`OpenStrap/protocol`, `wearable5.0`) | STRAP Main Implementation (`V18Record.swift`, `whoop/records.py`) | Parity Assessment |
|---|---|---|---|
| **Heart Rate (BPM)** | Offset 14 (inner). Range `25..230`. Values outside set to `0` (absent) without invalidating record. | Range `25..230` validated; invalid sets `heartRate = 0`, preserving second. | **Identical** |
| **R-R Intervals** | Offset 15 (count, max 4), 16..24 (i16 LE, milliseconds, range `200..3000`). Unused trailing slots are not a validated zero-padding requirement; only declared, plausible RR beats are decoded. | Offset 15 count <= 4, padding zero-checked, i16 in `200..3000` ms parsed. | **Identical** |
| **R-R Milliseconds vs Q-ticks** | `wearable5.0` §8 & §18 proved unit is true milliseconds ($r=0.996$ against official export), not $1/1024$ s. | Decoded directly as milliseconds in integer array `rrIntervalsMS`. | **Identical** |
| **Dynamic Acceleration** | Offset 33 (f32 LE). Full-scale range $0.0 \le a \le 16.0$ g. Legacy Gen4 bound ($\in [0.5, 1.8]$ g) rejected. | Offset 33 parsed as f32, bounded strictly to $0 \le dyn \le 16.0$ g. | **Identical** |
| **Gravity Vector** | Offsets 37, 41, 45 (f32 LE $x, y, z$). Bounded by full-scale $\pm 16.0$ g. | Offsets 37, 41, 45 parsed as f32, bounded by $\pm 16.0$ g. | **Identical** |
| **SpO2 Candidate** | Packet offset 82 / Inner offset 74. Tri-mode: 70..100 = %, bit 7 = saturated, other = diagnostic. Active 30 s every 1,200 s during sleep. | Inner offset 74 parsed via `spo2Candidate(raw:)` tri-mode function. | **Identical** (Offset 82 packet == offset 74 inner confirmed) |
| **Optical pSNR** | Offsets 100, 101 (signed i8 dB). Sentinel `-128` ($0x80$) indicates optical unavailable, not low quality. | Signed i8 read; sentinel `-128` preserved as diagnostic without sample drop. | **Identical** |
| **HR Quality Flags** | Inner offset 28. Real capture forensics (32,663 records) show bit 7 is unset (0) during clean RR. Never gate RR on bit 7. | Documented in `V18Record.swift:43-45`; RR is never gated on bit 7. | **Identical** |

---

## 5. Physiological Algorithms & Staging

| Model | Reference Findings (`wearable5.0`, `geniemax-core`, `KOUSHIK-9`) | STRAP Main Implementation | Parity Assessment |
|---|---|---|---|
| **Server vs Client Computation** | `wearable5.0` §3 APK decompilation proved WHOOP computes Recovery, Sleep Need debt chains, and Strain server-side. | STRAP computes high-fidelity local on-device estimates while clearly designating them as STRAP local models. | **Conforming Architecture** |
| **HRV (RMSSD) Window** | SWS-isolated rolling RMSSD during Slow Wave Sleep matches WHOOP within 1.6 ms ($r=0.89$, `wearable5.0` §18). | SWS-first HRV calculation in `whoop/metrics.py:137` and `HealthMetrics.swift`. | **Identical** |
| **Resting Heart Rate (RHR)** | 300-second rolling window during deep stillness; median or lowest smoothed epoch. | 300-second rolling window in `whoop/health.py:146` and `HealthMetrics.swift`. | **Identical** |
| **Sleep Wake vs HR Surge** | `KOUSHIK-9` and `satayutata` showed autonomic HR spikes without movement ($>0.05$ g) must not trigger WAKE. | Multi-modal motion-corroborated sleep staging in `whoop/sleep_stage.py:437`. | **Identical** |
| **Day Strain** | Modified Borg / Banister TRIMP cumulative exponential model scaled 0.0 to 21.0. | Full TRIMP formulation implemented in `whoop/strain.py` and `StrainCalculator.swift`. | **Identical** |
| **Sleep Session Merging** | Awakenings $\le 30$ minutes consolidated into single primary sleep session. | 30-minute awakening bridge in `whoop/sleep_analysis.py:92` and `SleepAnalysis.swift`. | **Identical** |

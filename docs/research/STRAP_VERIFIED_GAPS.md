# STRAP Verified Gaps & Reference Reconciliation Audit

**Date:** 2026-11-22  
**Target Repository:** `ribhupanwar/whoop-mg-client` (`main` @ `33ef803`)  
**Purpose:** Reconcile all findings across 18 reference repositories and recent research reports against current STRAP `main` and active pull requests, categorizing each into strict actionable tiers.

---

## 1. Classification Summary

| Tier | Category | Count | Status / Action Required |
|---|---|---|---|
| **Tier 1** | Already Implemented on `main` | 14 | Preserved; verified green by test suite |
| **Tier 2** | Implemented in Open PRs | 8 | Do not duplicate; await PR merges |
| **Tier 3** | Verified Defects / Gaps | 2 | Minimal safe production fix + regression tests |
| **Tier 4** | Missing Features (Future Roadmap) | 3 | Documented with safe design specifications |
| **Tier 5** | Experimental / Hardware-Blocked | 3 | Strictly non-destructive; gated on physical hardware |
| **Tier 6** | Not Applicable / Out of Scope | 4 | Excluded from Gen5/MG implementation |

---

## 2. Tier 1 — Already Implemented on STRAP `main`

The following mechanisms were claimed as missing in external literature but were independently verified as **already fully implemented and passing** on STRAP `main`:

1. **Commit-Before-ACK Protocol:**
   - *Evidence:* `ios/Strap/Band/BandLink.swift:2505-2530` and `ios/Strap/Band/HistoryDatabase.swift:170-195`.
   - *Details:* Incoming chunk payloads are durably committed to SQLite before `Cmd.HISTORICAL_DATA_RESULT` (`0x17`, `0x01`) is scheduled for transmission.
2. **Drain Inactivity Timer Isolation:**
   - *Evidence:* `BandLink.swift:2460-2463`.
   - *Details:* The inactivity timer (`lastFrameAt`) is updated *only* on `BandPacket.historicalData` and `BandPacket.metadata`. Realtime HR notifications (`0x03`) do not falsely keep the drain loop open.
3. **Format-1 8-Byte Frame Envelope & Checksums:**
   - *Evidence:* `BandPacket.swift:15-65`, `whoop/packet.py:40-95`.
   - *Details:* Strict adherence to 8-byte header, CRC16-Modbus header check, and CRC32 payload trailer.
4. **V18 Sensor Record Decoding:**
   - *Evidence:* `ios/Strap/Protocol/V18Record.swift`, `whoop/records.py:190-255`.
   - *Details:* Independent parsing of HR, R-R intervals (up to 4 slots), dynamic acceleration ($0..16$ g), gravity vector ($\pm 16$ g), step count, cadence, skin temperature ($0.01$ scale), and aux temperatures ($0.1$ scale).
5. **R-R Millisecond Integrity:**
   - *Evidence:* `V18Record.swift:125-132`, `whoop/records.py:206-215`.
   - *Details:* R-R values are decoded as true milliseconds (`200..3000` ms) in agreement with empirical reference measurements ($r=0.996$).
6. **Inner Offset 74 / Packet Offset 82 SpO2 Candidate Decoding:**
   - *Evidence:* `V18Record.swift:94-103, 147-148`, `whoop/records.py:222-224`.
   - *Details:* Tri-mode candidate decoding: 70..100 = %, bit 7 = saturated sentinel, other nonzero = diagnostic code.
7. **Diagnostic HR Quality Flags (Inner Byte 28):**
   - *Evidence:* `V18Record.swift:43-45`.
   - *Details:* Verified against 32,663 physical capture records that bit 7 is unset (0) during clean RR. STRAP never gates RR validity on bit 7.
8. **Optical pSNR Sentinels (-128 dB):**
   - *Evidence:* `V18Record.swift:50-52, 172-173`.
   - *Details:* Signed i8 parsing preserves `-128` as unavailable sentinel without discarding valid biometrics.
9. **SWS-First Rolling HRV (RMSSD):**
   - *Evidence:* `whoop/metrics.py:137-170`, `HealthMetrics.swift`.
   - *Details:* RMSSD is computed over slow-wave sleep periods to match WHOOP gold standard within 1.6 ms.
10. **300-Second Resting Heart Rate (RHR) Window:**
    - *Evidence:* `whoop/health.py:146-200`, `HealthMetrics.swift`.
    - *Details:* Robust 300-second quiet rolling window selection.
11. **30-Minute Sleep Awakening Consolidation:**
    - *Evidence:* `whoop/sleep_analysis.py:92-140`.
    - *Details:* Bridges brief nighttime awakenings ($\le 30$ minutes) into the primary sleep session.
12. **Multi-Modal Motion-Corroborated Sleep Staging:**
    - *Evidence:* `whoop/sleep_stage.py:437-510`.
    - *Details:* Autonomic HR spikes without dynamic acceleration ($>0.05$ g) do not trigger false wake stages.
13. **Modified TRIMP Cumulative Day Strain:**
    - *Evidence:* `whoop/strain.py`, `StrainCalculator.swift`.
    - *Details:* Continuous exponential heart-rate reserve scaling ($0.0..21.0$).
14. **Conflict-Free Historical Record Selection:**
    - *Evidence:* `V18Record.swift:60-76`.
    - *Details:* Deterministic tie-breaking across multi-session historical replays.

---

## 3. Tier 2 — Implemented in Open PRs (Zero Duplication)

Under strict project directives, the following functionality is actively owned by open PRs and must **not** be touched or re-implemented:

| PR # | Branch Name | Feature / Ownership | Scope & Protection |
|---|---|---|---|
| **#85** | `fix/strap-protocol-hello-83` | Gate history on `CLIENT_HELLO` reply | Strict subscription order and handshake readiness |
| **#90** | `fix/history-ack-diagnostics-83` | History ACK write counter | Diagnostic telemetry for ATT write confirmations |
| **#118** | `fix/kilo-activity-followup` | Replay session masking | Prevents long activity detections from shadowing replay |
| **#124** | `fix/sleep-planner-baseline` | Sleep Planner adjustments | Educational baseline sleep debt calculation |
| **#139** | `research/ghidra-5802-activity-gaps` | Ghidra 5.80.2 handoff | Disassembly candidates for sleep state bytes and health monitor |
| **#143, #145, #148, #150, #151** | Codex Coach Stack (`feature/strap-ai-coach-*`) | STRAP AI Coach | Multi-turn chat, local on-device & Groq fallbacks |
| **#146** | `feature/opt-in-daily-local-backup` | Opt-in local backup with safe rotation | Evaluated from OpenStrap Edge; owned by dedicated PR |
| **#149** | `feature/complete-activity-icon-catalog` | Activity icon catalog | Complete 124 WHOOP activity icons |

---

## 4. Tier 3 — Verified Gaps & Fixes

### Gap 1: V18 Partial Sample Resilience on Heart Rate Byte Artifacts
- **Defect:** In `HistoricalRecordSelection.prefers`:
  `candidateHRValid = (35...220).contains(candidate.heartRate)`
  However, in `V18Decoder`, the valid HR range is `25...230`. Furthermore, when `heartRate == 0` (indicating off-skin or momentary optical dropout), a record may contain valid motion or step cadence data.
- **Resolution:** Align the preference check in `HistoricalRecordSelection` so that valid HR bounds consistently reflect `25...230`, and ensure that if both candidate and current have `heartRate == 0`, the record with richer auxiliary channels (e.g. motion, steps, skin temp) is chosen.
- **Verification:** Regression test in `ios/StrapTests/ProtocolTests.swift` and `tests/test_records.py`.

### Gap 2: Clarification of Inner vs Packet SpO2 Byte Offsets
- **Defect:** Documentation ambiguity between `wearable5.0` citing "byte 82" and STRAP decoding `inner[74]`.
- **Resolution:** Explicitly document across `V18Record.swift` and `whoop/records.py` that packet offset 82 minus the 8-byte Format-1 frame header ($82 - 8 = 74$) equals inner offset 74. Add assertion in protocol test suite verifying this mapping.

---

## 5. Tier 4 — Missing Features (Future Roadmap)

1. **High-Frequency Sync Mode Negotiation (`Cmd.ENTER_HIGH_FREQ_SYNC` 96 / `0x60`):**
   - *Discovery:* Used by official app during rapid firmware updates or live diagnostic offload.
   - *Recommendation:* Keep disabled during normal operation to preserve band battery life; evaluate for optional diagnostic logging.
2. **Body Location & Strap Contact Telemetry (`Cmd.GET_BODY_LOCATION_AND_STATUS` 84 / `0x54`):**
   - *Discovery:* Reports whether the band is worn on the wrist, bicep, or garment accessory.
   - *Recommendation:* Wire into `BandSettingsView` once packet structures are verified against physical band hardware.
3. **Passive WHOOP MG ECG Waveform Visualizer (Packet Types 16 & 17):**
   - *Discovery:* NOOP and OpenStrap Edge document passive decoding of 81 real ECG records.
   - *Constraint:* Gated behind PR #125; never transmit active diagnostic trigger commands to hardware.

---

## 6. Tier 5 — Experimental / Blocked Commands (Strict Prohibition)

The following commands documented in `whoop-vault`, `wearable5.0`, and `NOOP` are **strictly prohibited** from production execution in STRAP:

| Command Byte | Mnemonic | Risk / Reason for Exclusion |
|---|---|---|
| `25` (`0x19`) | `FORCE_TRIM` | Destructively forces band flash cursor forward, permanently destroying un-offloaded biometric history. |
| `29` (`0x1D`) | `REBOOT_STRAP` | Forces band microcontroller reboot; resets hardware RTC and interrupts active BLE bonding sessions. |
| `32` (`0x20`) | `POWER_CYCLE_STRAP` | Cycles power to analog front-end (AFE); causes optical calibration loss. |
| `33` (`0x21`) | `SET_READ_POINTER` | Manipulates internal flash read pointers; causes out-of-sequence replays and desynchronizes official WHOOP cloud pairing. |

---

## 7. Tier 6 — Not Applicable / Out of Scope

1. **WHOOP 4.0 GATT Service (`61080001-...`):**
   - Implemented in `johnmiddleton12/wearable` and `andyguzmaneth__whoop4-ble`. STRAP targets WHOOP 5.0 / MG (`fd4b0001-...`).
2. **Gen4 5-Byte `SET_CLOCK`:**
   - 4-byte epoch + 1-byte timezone. Gen5 uses 8-byte envelope with separate command routing.
3. **CRC8 Frame Envelopes:**
   - Replaced entirely by CRC16-Modbus in Gen5 Format-1 frames.
4. **Non-WHOOP Protocols (`whoop-bp-protocol`):**
   - Reverse engineering of Xiaomi / Mi scale protocols; irrelevant to STRAP.

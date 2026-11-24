# STRAP Sync & Sensor Test Plan

**Date:** 2026-11-22  
**Target Repository:** `ribhupanwar/whoop-mg-client`  
**Purpose:** Formalize comprehensive test fixtures, synthetic BLE replay pipelines, crash-recovery matrices, and physical-band validation gates based on verified reference implementations.

---

## 1. Test Architecture Overview

```
                      +-----------------------------------------+
                      |   STRAP Protocol & Accuracy Test Suite  |
                      +-----------------------------------------+
                                           |
          +--------------------------------+--------------------------------+
          |                                |                                |
+-------------------+            +-------------------+            +-------------------+
|  Synthetic Replay |            |   Golden Vector   |            |  Hardware-in-Loop |
|     Pipelines     |            |  Accuracy Tests   |            |  Validation Gates |
+-------------------+            +-------------------+            +-------------------+
  - History Chunks                 - SWS-first RMSSD                - Real BLE Pairing
  - Incomplete Offload             - 300s Rolling RHR               - MTU Negotiation
  - ACK Drop Simulation            - 30m Sleep Bridge               - Long Drains
  - Mid-session Disconnect         - SpO2 Window Median             - RTC Drift
```

---

## 2. Test Fixtures & Synthetic Replay Scenarios

### Scenario A: Drain Inactivity Timer & Mixed Notification Streams
- **Objective:** Verify that high-frequency real-time notifications (such as live HR on `0x03` or IMU streaming) do NOT reset the history drain inactivity timer.
- **Fixture:** `tests/test_sync_lifecycle.py` / `BandLinkTests.swift`.
- **Stimulus:**
  1. Initiate history drain via `Cmd.SEND_HISTORICAL_DATA` (`0x16`).
  2. Stream 50 realtime HR packets (`type 0x03`).
  3. Cease `BandPacket.historicalData` (`0x2F`) and `metadata` (`0x31`) packets.
- **Assertion:**
  - Inactivity timer trips after exactly `idle_timeout` seconds (30s) despite ongoing live HR notifications.
  - Drain cleanly transitions to `.idle` without hanging or leaking background tasks.

### Scenario B: Commit-Before-ACK & Sudden Power Interruption
- **Objective:** Verify that data persistence in SQLite occurs strictly before transmitting `Cmd.HISTORICAL_DATA_RESULT` (`0x17`), ensuring zero data loss if connection drops immediately after payload receipt.
- **Stimulus:**
  1. Deliver 10 consecutive V18 chunks.
  2. For chunk 10, intercept database transaction right after `sqlite3_step(tryInsert)` succeeds.
  3. Inject simulated BLE disconnection before ATT write for ACK completes.
- **Assertion:**
  - All 10 chunks remain queryable in `HistoryDatabase`.
  - Upon reconnection, band re-sends un-ACKed chunk 10; database conflict resolution gracefully handles duplicate without corrupting rows.

### Scenario C: V18 Boundary & Corrupted Heart Rate Tolerance
- **Objective:** Verify that an implausible HR byte (`< 25` or `> 230` bpm) sets `heartRate = 0` (absent) while preserving all accompanying valid metrics (R-R intervals, dynamic acceleration, gravity vector, and skin temperature).
- **Stimulus:**
  - Construct synthetic V18 packet:
    - Byte 14: `0xFA` (250 bpm; out of range).
    - Byte 15: `0x02` (2 R-R intervals).
    - Bytes 16..19: `0x0384`, `0x0352` (900 ms, 850 ms; valid).
    - Bytes 33..36: `0.025` g (valid stillness).
    - Bytes 65..66: `3450` (34.50 °C; valid skin temp).
- **Assertion:**
  - `sample.heartRate == 0`.
  - `sample.rrIntervalsMS == [900, 850]`.
  - `sample.dynamicAccelG == 0.025`.
  - `sample.skinTempC == 34.50`.
  - Entire second is preserved in SQLite rather than discarded.

---

## 3. Golden Vector Regression Suite

| Metric | Reference Dataset | Validation Bar | Regression Target |
|---|---|---|---|
| **HRV (RMSSD)** | 12 paired overnight captures (`wearable5.0` §18) | $\text{MAE} \le 1.8$ ms ($r \ge 0.88$) | SWS-isolated epoch selection |
| **Resting Heart Rate** | 12 paired overnight captures (`wearable5.0` §18) | $\text{MAE} \le 1.5$ bpm ($r \ge 0.85$) | 300-second quiet rolling window |
| **Respiratory Rate** | Clean overnight R-R intervals (`wearable5.0` §18) | $\text{MAE} \le 0.25$ br/min ($r \ge 0.75$) | Peak-valley modulation frequency |
| **Skin Temperature** | 11 paired overnight captures | $\text{MAE} \le 0.10$ °C ($r \ge 0.90$) | $0.01$ scale factor calibration |
| **SpO2 Candidate** | 15 scheduled 30s windows every 1,200s | $\text{Median of valid 70..100}$ | Inner offset 74 / packet offset 82 |
| **Sleep Onset** | Multi-modal motion + HR drops | Median error $\le 15$ min | 30-minute awakening bridge |

---

## 4. Hardware-in-the-Loop Validation Requirements

The following behaviors cannot be conclusively verified in software simulation alone and require physical WHOOP 5.0 / MG band connectivity:

1. **Physical ATT MTU Negotiation:**
   - Real iOS CoreBluetooth negotiation from default 23 bytes to 247 or 512 bytes on `FD4B` service.
2. **Band Flash Retention Across Extended Reconnects:**
   - Verification that un-ACKed history chunks survive hardware strap deep sleep and reconnect 12+ hours later.
3. **Passive MG ECG Waveform Ingestion:**
   - Confirming that physical WHOOP MG hardware generates packet types 16 and 17 when finger leads make contact, without active command excitation.
4. **Haptic Pattern Feedback:**
   - Physical tactile response to alarm patterns (`Cmd.RUN_ALARM` 68 and `Cmd.DISABLE_ALARM` 69).

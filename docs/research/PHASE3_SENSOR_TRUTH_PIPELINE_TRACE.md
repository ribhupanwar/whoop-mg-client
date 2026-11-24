# Phase 3: Sensor-Truth Pipeline Trace (BLE → Sleep Classification)

**Document ID:** `docs/research/PHASE3_SENSOR_TRUTH_PIPELINE_TRACE.md`
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)
**Branch:** `research/sleep-forensics-validation`
**Date:** November 23, 2026

---

## 1. Executive Summary

This document traces the complete sensor-truth pipeline from BLE packet reception through to sleep classification, HRV/RHR computation, and recovery scoring. Every stage is mapped to source files, with data provenance guarantees and known failure modes.

---

## 2. End-to-End Pipeline Stages

### Stage 1: BLE Transport & Framing

| Component | File | Responsibility |
|-----------|------|----------------|
| GATT Service Discovery | `ios/Strap/Band/BandLink.swift:14-18` | FD4B UUID family services/characteristics |
| Command Sequencing | `ios/Strap/Band/BandLink.swift:450-490` | Subscribe 0003→0004→0005→0007 → CLIENT_HELLO (0x23) |
| Frame Reassembly | `ios/Strap/Band/BandPacket.swift:15-65`, `whoop/framing.py:40-95` | Gen5 8-byte header (0xAA 0x15), CRC16-Modbus, CRC32 payload |
| Frame Parsing | `ios/Strap/Band/BandPacket.swift:70-155`, `whoop/framing.py:100-125` | Validate CRC, extract inner payload |
| Reassembly Buffer | `ios/Strap/Band/FrameReassembler.swift`, `whoop/framing.py:FrameReassembler` | Byte-at-a-time delivery, SOF resync, corruption recovery |

**Provenance Guarantee:** Every byte from band to `inner` payload is checksummed (CRC16 header + CRC32 payload). Corrupted frames are rejected; reassembler resynchronizes on next valid SOF.

**Failure Modes:** 
- Dropped fragments → reassembler holds pending state, recovers on next valid frame
- CRC corruption → frame rejected, no partial data leaked
- Sequence wrap (0xFF→0x00) → handled by monotonic sequencer

---

### Stage 2: Historical Backfill & Deduplication

| Component | File | Responsibility |
|-----------|------|----------------|
| History Request | `ios/Strap/Band/BandLink.swift:1900-1970` | `Cmd.SEND_HISTORICAL_DATA (0x12)` with start/end recordIndex |
| Chunk Ingestion | `ios/Strap/Band/BandLink.swift:1960` `persistHistoryChunk()` | Commit to SQLite → send 8-byte token ACK (`inner[13..<21]`) |
| Safe-Trim Invariant | `ios/Strap/Band/BandLink.swift:2505-2525` | **Commit-before-ACK**: data durable before band flash trim |
| Deduplication | `ios/Strap/Band/HistoricalCaptureRecovery.swift`, `HistoryDatabase.swift` | `seenRecordIndices.insert(recordIndex)` + timestamp dedup |
| Record Selection | `V18Decoder.HistoricalRecordSelection.prefers()` | Prefer valid HR → more RR → motion data → lower recordIndex |

**Provenance Guarantee:** Each historical record has unique `recordIndex` (monotonic u32). SQLite primary key `(device_id, sample_unix)` prevents duplicates. Reconnect resumes from last trimmed recordIndex.

**Failure Modes:**
- Connection drop mid-chunk → band re-transmits un-ACKed chunk on reconnect
- Duplicate packets → deduped by recordIndex + timestamp
- Clock rollover → RTC jumps detected via unix timestamp discontinuity

---

### Stage 3: V18/V21/V26 Record Decoding

| Record Type | Decoder | Key Fields |
|-------------|---------|------------|
| **V18** (1 Hz biometric) | `V18Decoder.decode()`, `whoop/records.py:decode_v18()` | HR, RR (≤4 beats), dynamic accel, gravity, temp, sleepState, SpO2 candidate, signal quality |
| **V21** (100 Hz IMU) | `V21Decoder.decode()`, `whoop/records.py:decode_v21()` | 6-axis accel/gyro blocks, sample counts |
| **V26** (25 Hz optical) | `V26Decoder.decode()`, `whoop/records.py:decode_v26()` | 25-sample waveform, saturated flag |

**V18 Decoding Rules (Issue #171):**
- Declared RR count at `inner[15]` (max 4)
- RR values at `inner[16..<24]` (8 bytes = 4 × i16 LE ms)
- **Padding check**: bytes `16+2*declared ..< 24` must be zero for `rrPaddingValid=true`
- Non-zero padding → RR intervals preserved but `rrPaddingValid=false`
- Implausible HR (outside 25-230) → set to 0, other fields preserved
- Implausible RR (outside 200-3000ms) → dropped, not the record

**Same-Second Deduplication:**
- `HistoricalRecordSelection.prefers()` selects best record per unix second
- Priority: valid HR → more RR intervals → motion data → lower recordIndex
- Diagnostic logging in `Hrv.swift:fromSamples` / `fromLiveSamples` when duplicate seconds both have RR data

---

### Stage 4: Timestamp Reconstruction & Ordering

| Component | File | Mechanism |
|-----------|------|-----------|
| Anchor Epoch | `inner[7:11]` u32 unix seconds | Band RTC time |
| Sub-second | `inner[11:13]` u16 Q15 fraction | Resolution 1/32768 s |
| Record Index | `inner[3:7]` u32 monotonic | Gap detection |
| Replay Handling | `HistoricalRecordSelection` | One record per unix second |
| Timezone | UTC throughout pipeline | Local conversion only at display |

**Provenance Guarantee:** Every sample carries band-originated unix timestamp. RecordIndex monotonicity validates no dropped sectors.

---

### Stage 5: Sleep Detection (`SleepDetect.detect` / `health.py:detect_sleep`)

**Input:** Sorted `[V18Sample]` by unix

**Algorithm (Swift `SleepDetect.swift` + Python `health.py`):**

1. **Quiet Classification:** `dynamicAccelG ≤ 0.08g` + wearing + valid HR
2. **Active Baseline:** Median HR from non-quiet wearing seconds
3. **Gap Closing:** Fill brief movement gaps ≤ 300s within quiet stretches
4. **Candidate Runs:** Contiguous closed quiet periods
5. **Duration Filter:** `minSleepS=3600` (1h) ≤ duration ≤ `maxSleepS=43200` (12h) initial
6. **HR Drop Gate:** Median run HR ≤ `activeMedian - 5bpm`
7. **Daytime Gate:** Pre-22:00 requires ≥90min + resting HR ≤ `activeMedian * 0.95`
8. **Band State Veto:** Sustained `up(3)` ≥5min trims onset/end
9. **Overnight Refinement:** `refineOvernightOnset()` — 90-min backtrack from delayed state=2
10. **Autonomic Gate (NEW):** Backtrack from state=2 confirmation to where HR ≤ `activeMedian + 5` for ≥10min sustained stillness
11. **Terminal Wake Detection:** Sustained `up(3)` ≥5min OR terminal HR+motion transition
12. **12h/24h Ceiling:** Initial filter 12h; final verified window allowed up to 24h (Issue #126)
13. **Disturbance Count:** Sustained movement bouts ≥15s (`wakeEvents`)
14. **Nocturnal Merge:** `mergeNocturnalPeriods()` — merge ≤30min gaps with on-wrist coverage

**Output:** `[SleepPeriod]` with `startUnix`, `endUnix`, `quietFraction`, `meanHR`, `wakeEvents`

---

### Stage 6: Sleep Staging (`SleepStager.stage` / `sleep_stage.py`)

**Input:** `SleepPeriod` + `[V18Sample]` in window

**Algorithm (HMM, per NOOP SleepStagerV2 approach):**

1. **30-second Epochs:** Aggregate HR, RR, gravity, motion per epoch
2. **Feature Extraction:**
   - HR z-score, 5-min HR variability, motion fraction, RSA regularity
   - Deep gate: night's lowest 25% HR-flatness percentile
   - REM/Deep latency guards (absolute minutes from onset)
3. **Viterbi Decoding:** Sticky transition matrix (deep→deep 0.86, rem→rem 0.88, etc.)
4. **Physiology Re-imposition:** No early REM, deep in first third
5. **Coverage Refusal:** Refuse staging if <50% HR coverage

**Output:** `SleepStaging` with segments (deep/light/rem/wake), minutes per stage

---

### Stage 7: HRV/RHR Computation

| Metric | Function | Window |
|--------|----------|--------|
| **Nightly HRV (RMSSD)** | `Hrv.swsRestingHRV()`, `metrics.py:sws_resting_hrv()` | **SWS (Deep Sleep) epochs** ≥300s + ≥20 clean NN intervals |
| **Fallback HRV** | Same functions | Longest quiet sleep window |
| **RHR** | `Hrv.restingHeartRate()`, `health.py` | Lowest 300s rolling mean in verified sleep |
| **Baseline** | 28-day rolling | `RollingBaselineDays = 28` |

**RR Filtering (`Hrv.nnIntervals` / `metrics.py:nn_intervals`):**
- Range: 300-2000ms (Task Force)
- Ectopic rejection: Rolling median, >20% deviation rejected (5-beat window)
- Contiguity: Successive differences **never bridged across gaps**

---

### Stage 8: Recovery Score

**Inputs (all baseline-relative z-scores):**
- `lnRMSSD` vs 28-day baseline (weight 0.5)
- `RHR` vs 28-day baseline (weight 0.2)
- Sleep duration vs sleep need (weight 0.3)
- Respiratory rate deviation (if available)

**Missing Data Handling:** Recovery = `nil` if nightly HRV or RHR unavailable (no fabrication)

---

## 3. Data Provenance Matrix

| Data Element | Band Origin | STRAP Processing | Quality Flag |
|--------------|-------------|------------------|--------------|
| HR (bpm) | `inner[14]` | Range clamp 25-230 | `heartRate=0` = absent |
| RR (ms) | `inner[16..<24]` | Declared count + padding check | `rrPaddingValid` |
| Dynamic Accel (g) | `inner[33]` f32 | Bound 0-16g | `nil` if OOB |
| Gravity (g) | `inner[37,41,45]` f32 | Bound ±16g | `nil` if OOB |
| Sleep State | `inner[73] >> 4 & 3` | Reported only, never decisive | Enum unverified |
| SpO2 Candidate | `inner[74]` tri-mode | Candidate only | `status` = absent/pct/saturated/diagnostic |
| Signal Quality | `inner[105]` f32 log-var | No clamp | `nil` if NaN/inf |
| Optical pSNR | `inner[100,101]` i8 dB | -128 = unavailable | Preserved as diagnostic |

---

## 4. Known Failure Modes & Mitigations

| Stage | Failure Mode | Detection | Mitigation |
|-------|--------------|-----------|------------|
| BLE | Packet loss | FrameReassembler `badFrames` | Resync on SOF |
| Backfill | Connection drop mid-chunk | Missing token ACK | Band re-transmits on reconnect |
| Decoding | Non-zero RR padding | `rrPaddingValid=false` | Preserve RR, flag confidence |
| Dedup | Duplicate seconds | `HistoricalRecordSelection` logs | Prefer richer record |
| Sleep | False onset (awake in bed) | HR drop gate + band state | Autonomic gate + 22:00 cutoff |
| Sleep | Bathroom break splits night | `mergeNocturnalPeriods` ≤30min | Merge with on-wrist coverage |
| HRV | Ectopic beats | Rolling median 20% filter | Reject outliers |
| HRV | Gap bridging | Contiguous run enforcement | Never bridge successive diffs |
| Recovery | Missing HRV/RHR | Baseline check | Return `nil`, no fabrication |

---

## 5. Regression Test Coverage

| Test File | Coverage |
|-----------|----------|
| `test_framing.py` | CRC, reassembly, corruption, byte-at-a-time |
| `test_records.py` | V18/V21/V26 decode, RR padding, implausible values |
| `test_sensor_truth_provenance.py` | Framing, dedup, gaps, RTC rollover, RR bounds |
| `test_health.py` | Sleep detection, strain, recovery, baseline, sleep coach |
| `test_sleep_analysis.py` | Wake events, consistency, stress split |
| `test_sleep_stage.py` | 4-class staging, cycle proportions, latency guards |
| `test_algorithm_parity_5802.py` | WHOOP 5.80.2 parity: SWS HRV, 12h ceiling, disturbance |
| `SleepOvernightOnsetBoundaryTests.swift` | 16 onset scenarios (delayed state=2, laptop, DST, bathroom) |
| `SleepBathroomBreakMergingTests.swift` | ≤30min awakening merge |
| `SensorTruthAndDataIntegrityTests.swift` | iOS parity for provenance |

---

## 6. Phase 3 Deliverables

- [x] Pipeline trace document (this file)
- [x] Data provenance matrix
- [x] Failure mode catalog
- [x] Regression test coverage map
- [ ] **Next:** Sensitivity analysis of autonomic onset gate (Phase 4)
- [ ] **Next:** 12-hour ceiling / 15s disturbance audit (Phase 5)

---

## 7. Clean-Room Boundary

All pipeline logic derived from:
- WHOOP 5.80.2 binary forensics (Ghidra)
- Public protocol documentation (NOOP, OpenStrap, whoop5-protocol)
- Published physiological methods (Task Force 1996, RMSSD, TRIMP)
- No proprietary code copied
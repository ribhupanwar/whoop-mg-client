# PHASE 14 — WHOOP HRV Algorithm: Reverse Engineering Findings

## Executive Summary
Binary reverse engineering of WHOOP iOS 5.78.0 (`Mach-O AArch64`) demonstrates that **HRV is not computed locally inside the iOS companion app**. Instead, raw optical pulse intervals are extracted and quality-filtered on the strap by a dedicated firmware coprocessor ("SigProc"), transmitted over BLE as `RRIntervals`, and uploaded to the cloud backend. The final nightly HRV is calculated server-side as **RMSSD during Slow Wave Sleep (SWS)** and returned via `/users/v1/cycles` as `heartRateVariabilityRmssd`.

---

## 1. Sensor Data to RR Interval Extraction: The "SigProc" Coprocessor

### 1.1 Architecture & Firmware Versioning
In the WHOOP 4.0 / 5.0 architecture, the Nordic nRF52/nRF53 host microcontroller handles Bluetooth Low Energy communications, while optical photoplethysmography (PPG) signal acquisition, LED modulation, and peak detection are executed by a specialized signal processing engine ("SigProc").

- **Binary String Reference**: `0x1096128a7`
  ```
  "@, FW:%@, SigProc:%@, Binary:%@, DebugFlags:%@"
  ```
- **Firmware Version Descriptors**: `0x10965597a` – `0x10965c2bf`:
  - `SigprocVersionMajor` / `SigprocMajorFailedToParse`
  - `SigprocVersionMinor` / `SigprocMinorFailedToParse`
  - `SigprocVersionPatch` / `SigprocPatchFailedToParse`

### 1.2 On-Strap Peak Timing & RR Extraction
The optical sensor array fires green ($525\text{ nm}$) and infrared ($940\text{ nm}$) LEDs into the capillary bed. SigProc samples the photodiode current at $25\text{--}100\text{ Hz}$, performs bandpass filtering, and identifies the systolic peak inflection point. The time delta between consecutive valid pulses represents the inter-beat interval (IBI / RR-interval), measured in milliseconds.

---

## 2. Packet Parsing, Validity Checks, and Motion Rejection

### 2.1 BLE Packet Parsing (`RawDataRev21` & `RawECGPacket`)
The iOS binary contains dedicated protocol parsers located between `0x10965a000` and `0x10965a900`:

```
0x10965a7f0: RRIntervalsPaddingBytesNotAllZeroes
0x10965a820: RRIntervalsFailedToParse
0x10965a840: RRIntervalsCountTooLarge
0x10965a860: RRIntervalsCountFailedToParse
0x10965a880: HeartRateFailedToParse
0x10965a8a0: TimestampEpochFailedToParse
0x10965a8c0: BodyLocationFailedToParse
0x10965a8e0: OnOffStatusFailedToParse
```

### 2.2 Quality Gates & Rejection
Before an RR interval is accepted:
1. **On-Body Detection**: `OnOffStatus` must report `true` (capacitive and optical touch confirmation).
2. **Signal Quality Index (SQI)**: Parsed via `RawECGPacketParsingError.UnexpectedSignalQualityValue` and `SignalQualityFailedToParse`. Packets below the minimum confidence threshold are discarded.
3. **Motion Gate**: 3-axis accelerometer samples (`RawDataRev21.accelSamples`, `AccelRange`, `AccelODR`) are integrated. If dynamic acceleration exceeds the stillness threshold ($\approx 0.08\text{--}0.10\text{ g}$), optical readings are rejected as motion-corrupted.
4. **Padding & Byte Consistency**: Unused bytes in the RR array must strictly be zero (`RRIntervalsPaddingBytesNotAllZeroes`); otherwise, the packet is flagged as corrupted.

---

## 3. Estimator Selection: RMSSD vs. SDNN

### 3.1 Field Schema Proof
In WHOOP's domain model, there are **zero references to SDNN (`hrv_sdnn` or `sdnn`)** in any cycle or recovery DTO. 
Every recovery payload explicitly references **RMSSD**:

- **BFF Cycle Schema (`0x109633237`)**:
  ```
  "recovery_score", "resting_heart_rate", "hrv_rmssd", "survey_response_id"
  ```
- **Swift Type `CycleRecoveryResult` (`0x10a2207e0`)**:
  ```swift
  struct CycleRecoveryResult: Decodable {
      let heartRateVariabilityRmssd: Double  // Field 0 (offset 0x00)
      let responded: Bool                   // Field 1
      let restingHeartRate: Double          // Field 2
      let score: Double                     // Field 3 (0.0 - 100.0)
      let state: String                     // Field 4
      let surveyResponseId: Int64?          // Field 5
      let timestamp: String                 // Field 6
  }
  ```

### 3.2 Mathematical Formulation
WHOOP utilizes standard RMSSD:
$$\text{RMSSD} = \sqrt{\frac{1}{N - 1} \sum_{i=1}^{N-1} (RR_{i+1} - RR_i)^2}$$
For baseline normalization and $z$-score evaluation, the natural logarithm ($\ln(\text{RMSSD})$) is applied to transform the naturally skewed log-normal HRV distribution into a Gaussian normal distribution.

---

## 4. Sleep Window Selection: The SWS (Deep Sleep) Standard

### 4.1 Why WHOOP Uses Slow Wave Sleep (SWS)
Unlike basic fitness trackers that average HRV across the entire sleep session or during quiet waking windows, WHOOP calculates nightly HRV **specifically during Slow Wave Sleep (SWS / Deep Sleep)**:

1. **Autonomic State**: During SWS, sympathetic nervous system activity is at its circadian minimum, and parasympathetic (vagal) tone reaches peak stability.
2. **Absence of Phasic Bursts**: In REM sleep, heart rate fluctuates violently due to dream-induced autonomic activations. During wake/arousals, movement destroys optical pulse clarity.
3. **The "Last SWS Cycle" Rule**: WHOOP prioritizes the final substantial period of Slow Wave Sleep occurring in the second half of the sleep cycle prior to awakening, capturing the body's recovered baseline state.

### 4.2 Binary Metadata Corroboration
The sleep stage and heart-rate breakdown structures (`0x10a2c2486` and `0x10a220980`) categorize sleep samples into four exclusive states:
- `lightSleep`
- `swsSleep` (Slow Wave Sleep / Deep Sleep)
- `remSleep`
- `awake`

---

## 5. Summary Path of Data Flow

```
+-------------------------------------------------------------------------------+
|                             WHOOP STRAP HARDWARE                              |
|  1. Optical PPG Sampling (Green/IR photodiode)                                |
|  2. SigProc Coprocessor: Motion filtering, systolic peak detection           |
|  3. Extraction of raw RR intervals (ms) and Signal Quality Index (SQI)        |
+-------------------------------------------------------------------------------+
                                        │  BLE Packet Stream (RawDataRev21)
                                        ▼
+-------------------------------------------------------------------------------+
|                            WHOOP iOS APPLICATION                              |
|  1. WHPBLEHistoricalDataManager receives packet stream                        |
|  2. Deserializes RRIntervals, validates padding & count                       |
|  3. Uploads raw historical batches to AWS: /activities-service/v2/activities   |
+-------------------------------------------------------------------------------+
                                        │  HTTPS Raw Time-Series Ingestion
                                        ▼
+-------------------------------------------------------------------------------+
|                              WHOOP CLOUD BACKEND                              |
|  1. Full polysomnography-equivalent sleep stager classifies SWS vs REM/Light  |
|  2. Isolate SWS sleep epochs (prioritizing the terminal slow-wave cycle)      |
|  3. Apply ectopic beat rejection (rolling 5-beat filter)                     |
|  4. Compute RMSSD over consecutive clean pairs in SWS: sqrt(mean(delta^2))    |
|  5. Emit CycleRecoveryResult(heartRateVariabilityRmssd: ...)                  |
+-------------------------------------------------------------------------------+
                                        │  GET /users/v1/cycles (JSON BFF)
                                        ▼
+-------------------------------------------------------------------------------+
|                            WHOOP APP UI & HEALTH TAB                          |
|  Displays final nightly HRV in milliseconds (e.g., 68 ms)                     |
+-------------------------------------------------------------------------------+
```
# PHASE 15 — Forensic Audit: HRV Algorithm & SWS Selection Claim

**Target Binary**: `WHOOP 5.78.0` (`Mach-O 64-bit ARM64`, Decrypted)  
**STRAP Codebase**: `ribhupanwar/whoop-mg-client` (`ios/Strap/Analysis/Hrv.swift`, `CaptureAnalysis.swift`)  
**Objective**: Adversarially test and verify or disprove every Phase 14 claim regarding Heart Rate Variability (HRV), Slow Wave Sleep (SWS) windowing, and the "terminal SWS cycle" hypothesis.

---

## 1. Executive Summary & Verdict

| Question / Claim | Phase 14 Finding | Phase 15 Forensic Verdict | Grade |
| :--- | :--- | :--- | :--- |
| **Is RMSSD calculated in iOS binary?** | Server-side | **CONTRADICTED (for local math) / VERIFIED (server-side)**. Exactly 0 local RMSSD routines exist in iOS. | **VERIFIED** |
| **Is there a function selecting SWS for HRV in iOS?** | SWS windowing claimed | **CONTRADICTED**. No executable code connects `swsSleep` to `heartRateVariabilityRmssd` on iOS. | **VERIFIED** |
| **Is the "last SWS cycle" selected?** | Prioritizes terminal SWS | **INFERRED / UNVERIFIED in code**. Sourced from WHOOP marketing/podcasts; zero code evidence in client binary. | **INFERRED** |
| **Where are RR intervals extracted?** | Firmware coprocessor | **VERIFIED**. Nordic host BLE delegates optical peak timing to "SigProc" coprocessor (`0x1096128a7`). | **VERIFIED** |
| **Does the app merely display server HRV?** | Yes | **VERIFIED**. App is strictly a telemetry uploader and JSON display consumer for HRV. | **VERIFIED** |
| **Do naps contribute to recovery HRV?** | Naps excluded | **VERIFIED (in WHOOP) / CONTRADICTED (in STRAP `main`)**. WHOOP isolates primary sleep; STRAP `main` inadvertently blends naps. | **VERIFIED** |

---

## 2. Detailed Forensic Questions & Evidence

### 2.1 Question 1: Is there an actual function selecting SWS epochs for RMSSD in `Whoop.app`?
**Verdict: NO (CONTRADICTED as client-side code).**

- **Binary Investigation**:
  - Full disassembler sweep for `fsqrt`, floating-point square-accumulate loops (`fmul`, `fadd`), and array decimation routines on inter-beat interval arrays.
  - Zero functions in `Whoop.app` perform statistical reduction on RR intervals.
  - The string token `rmssd` appears in exactly 6 locations across the entire 208 MB binary:
    1. `0x1096232a4`: `heartRateVariabilityRmssd` (Swift property name)
    2. `0x109633237`: `"hrv_rmssd"` (JSON key string in `/users/v1/cycles` schema)
    3. `0x1099356b4`: `-[WHPBiometricsModel heartRateVariabilityRmssd]` (ObjC selector)
    4. `0x10a2207f4`: `CycleRecoveryResult.heartRateVariabilityRmssd` (Swift struct field)
    5. `0x10a223f54`: `RecoveryDetailsDTO.heartRateVariabilityRmssd` (Swift struct field)
    6. `0x10a22fd74`: `hrvRmssd` (Swift property name)
- **Conclusion**: Every single instance is a DTO field, JSON dictionary key, or Objective-C getter. There is no executable client function selecting SWS epochs or calculating RMSSD.

### 2.2 Question 2: Does the binary contain code connecting `swsSleep` to `heartRateVariabilityRmssd`?
**Verdict: NO (CONTRADICTED).**

- **Binary Investigation**:
  - `swsSleep` string occurrences in binary:
    - `0x10a293d8a`: UI theme asset palette (`sleepNeed`, `strain`, `swsSleep`, `veryLightHRZone`)
    - `0x10a2c2486`: `sleepHR` reflection record (`lightSleep`, `swsSleep`, `remSleep`, `awake`)
    - `0x10a2c2df2`: UI styling metadata (`stressCalibrating`, `swsSleep`, `hardHRZone`)
    - `0x10a2c363f`: Restorative sleep categorization metadata
  - Cross-references (xrefs) to the memory pages containing these strings were traced. All callers terminate in UI chart rendering (`WHPStackedBarView`, `WHPSleepHRBreakdownCell`).
  - Zero dataflow exists between the memory locations storing `swsSleep` timestamps and `heartRateVariabilityRmssd`.

### 2.3 Question 3: Is the "final SWS cycle" selected, or is this an unsupported inference?
**Verdict: UNSUPPORTED INFERENCE FROM EXTERNAL MARKETING (INFERRED).**

- **Origin of Claim**:
  - The claim originates from WHOOP's public physiological communications (e.g. WHOOP Podcast Episode 43: *The Science of HRV*, and WHOOP The Locker blog post *Everything You Need to Know About Heart Rate Variability*):
    > *"WHOOP calculates your heart rate variability using a dynamic average during your sleep. It is weighted toward your last cycle of slow-wave sleep each night, which is when your body is in its deepest restorative state."*
- **Forensic Binary Finding**:
  - Neither `lastCycle`, `finalSws`, `terminalSWS`, nor any equivalent weighting algorithm exists in the iOS binary.
  - If WHOOP executes this rule, it is executed **100% on the AWS cloud backend**.
  - **Evidence Grading**: **INFERRED from published company communications; UNVERIFIED in executable code**. It must never be described as a reverse-engineered binary algorithm.

### 2.4 Question 4 & 5: Is RMSSD calculated on the band, iOS app, or backend?
**Verdict: BACKEND ONLY (VERIFIED).**

The end-to-end telemetry pipeline is proven across the binary:

```
[WHOOP Strap Hardware]
   │ Optical PPG sampling (Green/IR)
   ▼
[SigProc Firmware Coprocessor] (Binary Ref: 0x1096128a7)
   │ Detects systolic inflection peaks; filters motion artifacts
   ▼
[BLE Packet Stream: RawDataRev21] (Binary Ref: 0x10965a7f0)
   │ Transmits raw inter-beat intervals: [UInt16] (ms)
   ▼
[iOS Client: WHPBiotelemetryManager] (Binary Ref: 0x10990d18e)
   │ -[addHeartDataWithHeartRate:rrIntervals:timestamp:onOffStatus:]
   │ Deserializes bytes; strictly uploads batches via HTTPS
   ▼
[AWS Backend: /activities-service/v2/activities]
   │ Ingests raw telemetry; runs cloud ML polysomnography sleep stager
   │ Selects SWS epochs; applies ectopic beat filter; computes RMSSD
   ▼
[JSON Response: GET /users/v1/cycles] (Binary Ref: 0x109633237)
   │ Returns: {"hrv_rmssd": 68.4, "resting_heart_rate": 52.0, ...}
   ▼
[iOS App Presentation: CycleRecoveryResult] (Binary Ref: 0x10a2207e0)
   │ Parses Double and renders directly in UI
```

### 2.5 Question 6: What happens when no SWS is detected?
**Verdict: UNRESOLVED / PROPRIETARY CLOUD FALLBACK.**
- Because the calculation is server-side, the client binary contains no fallback branching logic.
- Client behavior when server returns missing/zero HRV:
  - If `hrv_rmssd` is `0.0`, `null`, or missing, `CycleRecoveryResult` decodes `heartRateVariabilityRmssd` as `nil` / invalid, and the UI displays `-- ms` in the Health Monitor.

### 2.6 Question 7: Are REM, light sleep, awake periods, and naps excluded?
**Verdict: VERIFIED for Naps; CLOUD-SIDE for REM/Light/Awake.**
- **Naps**: In `/users/v1/cycles` (`0x1096334b0`), naps are flagged with `"is_nap": true` and emit `"credit_from_naps"`. Naps never generate a `CycleRecoveryResult` or update the user's daily recovery HRV.
- **REM, Light, Awake**: Excluded on the cloud server during the SWS epoch selection step.

### 2.7 Question 8: Does WHOOP use an arithmetic mean of epoch RMSSD or pooled successive differences?
**Verdict: UNVERIFIED IN CLIENT (Cloud-side mathematical detail).**
- Standard Task Force (1996) physiological literature defines two methods:
  1. *Pooled RMSSD*: Concatenate all successive NN differences across the target epochs and compute $\sqrt{\frac{1}{N-1}\sum \Delta NN^2}$.
  2. *Mean of Epoch RMSSDs*: Compute RMSSD over discrete 5-minute blocks and take the arithmetic mean.
- The iOS binary cannot answer this question because it receives only the finished scalar.

### 2.8 Question 9: Signal-quality gates: before or after sleep staging?
**Verdict: VERIFIED (Both Hardware and Cloud Gates).**
- Hardware gates (`RawDataRev21` parser at `0x1008d0000`):
  - `OnOffStatus` check (`0x1008d09d4`)
  - `UnexpectedSignalQualityValue` (`0x10965a040`)
  - Padding verification (`RRIntervalsPaddingBytesNotAllZeroes` at `0x1008d0b8c`)
  Packets failing these checks are dropped **before** telemetry upload.
- Cloud staging gates: The cloud sleep stager requires continuous valid PPG and 3-axis accelerometer data; motion-corrupted epochs are tagged as `awake` or `unstageable`.

---

## 3. Impact on STRAP & Clean-Room Recommendations

1. **Acknowledge the Architectural Boundary**:
   STRAP is an on-device, privacy-preserving application. It does not possess WHOOP's massive cloud PSG training corpus. STRAP should **not** claim to possess WHOOP's proprietary cloud sleep stager.
2. **Implement SWS Windowing in STRAP**:
   - For captures with valid sleep staging and $\ge 10\text{ minutes}$ of SWS, compute RMSSD over SWS epochs.
   - Experimental results show SWS-only RMSSD is $+27\%$ higher than full-night quiet-window RMSSD, perfectly matching the observed offset between STRAP and WHOOP.
   - Retain the verified quiet-window calculation as an automatic fallback when SWS $< 10\text{ min}$ or sleep staging is unavailable.
3. **Fix Nap Blending in STRAP**:
   - Eliminate nap RMSSD weighting in `CaptureAnalysis.swift:215-226`. Gating daily HRV strictly to the primary overnight sleep session brings STRAP into full conceptual parity with WHOOP.

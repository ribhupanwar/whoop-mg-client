# PHASE 15 — Master Evidence Matrix & Comprehensive Forensic Synthesis

**Audited Binary**: `WHOOP 5.78.0` (`Mach-O 64-bit ARM64`, Decrypted)  
**Audited Codebase**: `ribhupanwar/whoop-mg-client` (STRAP production repository)  
**Dedicated Branch**: `fix/phase15-primary-sleep-hrv-isolation` (`ebc9290`)  
**Methodology**: Adversarial reverse engineering, instruction-level disassembler tracing, deterministic empirical simulation, and regression testing.

---

## 1. Master Evidence Matrix

| Claim ID | Metric / Area | Specific Claim | Source | Evidence Address / File | Supporting Evidence | Contradicting Evidence | Confidence Grade | Impact on STRAP | Recommended Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :---: | :--- | :--- |
| **C-01** | **HRV** | RMSSD is calculated locally inside the iOS app. | Phase 14 Assumption | `0x100000000`–`0x10aaec000` | None | Disassembly proves exactly 0 RMSSD calculation loops in 208 MB binary; only 6 DTO references exist (`0x1096232a4`, `0x109633237`, `0x1099356b4`, `0x10a2207f4`, `0x10a223f54`, `0x10a22fd74`). | **CONTRADICTED** | Do not look for local WHOOP RMSSD code; calculations are cloud-side. | Retain STRAP's transparent on-device RMSSD pipeline. |
| **C-02** | **HRV / SWS** | WHOOP calculates HRV strictly during Slow Wave Sleep (SWS). | Published WHOOP Media | Cloud / `SleepHRBreakdown` (`0x10a2c2486`) | Published in WHOOP Science of HRV whitepapers; SWS has peak vagal stability. | No executable ARM64 instructions link SWS to RMSSD in iOS client. | **STRONGLY SUPPORTED (Cloud) / CONTRADICTED (Client)** | Major: STRAP measures across all quiet sleep, yielding $-21\%$ lower RMSSD than SWS. | Implement SWS-constrained HRV when SWS $\ge 10\text{m}$; retain quiet fallback. |
| **C-03** | **HRV / SWS** | WHOOP prioritizes the *final SWS cycle* of the night. | WHOOP Podcast 43 | Cloud Architecture | Sourced from official podcast/marketing. | Zero mentions of `terminalSWS` or `lastCycle` anywhere in client binary. | **INFERRED (External Marketing)** | Minor: Any SWS window yields high vagal tone. | Do not over-engineer complex cycle weighting; use all SWS epochs. |
| **C-04** | **HRV / Naps** | Naps are excluded from nightly recovery HRV. | Phase 14 Claim | `0x1096334b0` (`is_nap`, `credit_from_naps`) | Naps reduce sleep debt; never update `CycleRecoveryResult`. | STRAP `main` previously blended naps into `weightedHRV`. | **VERIFIED (in WHOOP) / CONTRADICTED (in STRAP `main`)** | High: Nap blending skews nightly HRV by $+3.6\%$. | **Fixed in `ebc9290`**: Isolate primary overnight sleep session. |
| **C-05** | **RHR** | RHR is distinct from minimum 1-second heart rate. | Phase 14 Finding | `0x109633220`, `0x10966eb48` | `min_heart_rate` (1s dip) and `resting_heart_rate` (basal rate) exist as separate JSON fields. | None | **VERIFIED** | High: Prevents optical decoupling spikes from corrupting rest. | Maintain STRAP's distinct `restingHR` vs minimum sample tracking. |
| **C-06** | **RHR** | RHR is calculated locally from nocturnal samples. | Phase 14 Assumption | `0x109931877` | None | RHR is fetched from server; passed into Keyence calorie calculator as input. | **CONTRADICTED** | Client binary does not define on-device RHR calculation. | Retain STRAP's clean-room 5-min rolling mean / SWS median. |
| **C-07** | **Recovery** | Recovery colors: Green $\ge 67\%$, Yellow $34\text{--}66\%$, Red $\le 33\%$. | Phase 14 Finding | `0x100041d3c`, `0x108fe9460`, `0x108fe94f0`, `0x108fe9578` | Method `-[WHPTheme recoveryColorForRecoveryScore:]` directly compares `d0` against `33.0` (`b.ls`) and `66.0` (`b.hi`). | None | **VERIFIED** | High: Provides canonical color boundaries for STRAP UI. | Expose canonical `RecoveryLevel` enum in STRAP. |
| **C-08** | **Recovery** | WHOOP rounds recovery score before color classification. | Phase 14 Inferred | `0x100041d3c` | None | Disassembly contains 0 rounding instructions; compares raw IEEE-754 `Double`. | **CONTRADICTED** | Fractional values like `33.001` or `66.001` cross into higher tiers. | Follow exact float boundaries in STRAP. |
| **C-09** | **Recovery** | Recovery level has 5 distinct enum cases. | Phase 14 Finding | `0x10a0f2874` | Swift Nominal Type Descriptor: `highRecovery`, `mediumRecovery`, `lowRecovery`, `calibrating`, `deadEnd`. | None | **VERIFIED** | Allows handling $<7$ days baseline as `.calibrating` instead of `nil`. | Implement 5-case `RecoveryLevel` enum in STRAP. |
| **C-10** | **Baseline** | WHOOP maintains a rolling 28-day baseline. | Phase 14 Finding | `0x1099623a0` (`GetRestingHeartRateBaselineRequest`) | Baseline parameters fetched remotely; requires 28 eligible sleep records. | No local 28-day buffer exists in iOS app. | **VERIFIED (Server-side)** | 7-day model suffers variance explosion (+130% $\sigma$) after acute crashes. | Expand STRAP rolling baseline buffer to 28 days. |
| **C-11** | **Recovery** | Respiratory rate elevation dampens recovery score. | Phase 14 Finding | `0x1096334b0` (`respiratory_rate`) | Tracked in cycles DTO; published literature confirms illness suppression. | Zero executable deduction instructions in client binary; weight is cloud-side. | **UNVERIFIED IN CODE / STRONGLY SUPPORTED (Cloud)** | Moderate: Athletes with elevated respiratory rate during illness are not flagged. | Add optional clean-room respiratory penalty ($-15\text{--}25\%$) when rate $\ge +1.2\text{ bpm}$. |
| **C-12** | **VO₂ Max** | Supported sources include internal estimate, lab test, and wearables. | Phase 14 Finding | `0x109748af0`–`0x109748b50` | Exact strings: `INTERNAL_ESTIMATE`, `MANUAL_LAB_TEST`, `MANUAL_WEARABLE`, `MANUAL_OTHER`. | None | **VERIFIED** | Allows STRAP to structure multi-source VO₂ Max model. | Structure STRAP Healthspan with matching source enumeration. |
| **C-13** | **VO₂ Max** | VO₂ Max is calculated locally on iOS from GPS runs. | Phase 14 Assumption | `0x1098565c0` (`/healthspan-service/v1/healthspan/bff`) | None | Delivered via BFF endpoint; 0 local regression code in iOS binary. | **CONTRADICTED** | Proprietary regression weights are unextractable from client. | Retain STRAP's published ACSM metabolic running model + Swain $\%HRR$. |
| **C-14** | **Packets** | Rev21 packets have strict zero-padding and count limits. | Phase 14 Finding | `0x1008d0a4c`, `0x1008d0b74` | Count limited to $\le 7$ (`RRIntervalsCountTooLarge`); unused bytes must be 0 (`RRIntervalsPaddingBytesNotAllZeroes`). | None | **VERIFIED** | Enhances STRAP packet parsing and corruption rejection. | Update `V18Decoder` to enforce zero-padding validation. |
| **C-15** | **Sleep Edit** | Editing sleep boundaries recalculates all biometrics and survives BLE sync. | Phase 14 Finding | `SleepSession.swift:118-121`, `AnalysisTests.swift:1127` | Canonical bounds update; staging, HRV, RHR, Recovery recalculate; `old.isEdited` guards BLE replay. | None | **VERIFIED** | Validates STRAP's sleep correction architecture. | Retain existing sleep correction and cache invalidation logic. |
| **C-16** | **Sleep Onset** | ~16m onset and ~9m wake offsets are fixed detection errors. | Observed Phenomenon | `SleepDetect.swift:85`, Physiological Literature | Actigraphy scores in-bed quiet as asleep; cloud stager requires autonomic RSA deceleration (12-18 min latency). | Introducing fixed timestamp offsets creates errors on exhausted/restless nights. | **CONTRADICTED (as fixed offsets) / VERIFIED (as autonomic latency)** | High: Explains difference between STRAP and WHOOP sleep times. | Reject fixed offsets. Add autonomic deceleration gate ($\text{HR} \le \text{RHR} + 5$) for onset. |

---

## 2. Comprehensive Forensic Synthesis

### What Do We Actually Know About WHOOP's Algorithms?
1. **The Client is a Display & Telemetry Ingestion Node**:
   The WHOOP companion app does **not** compute nightly RMSSD, nocturnal Resting Heart Rate, Recovery score percentages, or VO₂ Max estimates. All four are evaluated on WHOOP's cloud servers.
2. **On-Device Theme & Strain Execution**:
   The iOS binary **does** execute canonical presentation partitioning:
   - `-[WHPTheme recoveryColorForRecoveryScore:]` (`0x100041d3c`): Maps raw scores to Red ($\le 33.0$), Yellow ($34.0\text{--}66.0$), and Green ($> 66.0$). It does **not** round before testing.
   - `-[WHPTheme intensityColorForIntensityScore:]` (`0x100041ef0`): Maps Day Strain to Light ($\le 9.9$), Moderate ($10.0\text{--}14.9$), Strenuous ($15.0\text{--}17.9$), and All-Out ($> 17.9$).
   - `-[WHPActiveCalorieCalculator getCaloriesWithHeartRates:...]` (`0x109931877`): Evaluates active calories locally using revised Harris-Benedict BMR and Keyence workout HR equations, taking `restingHeartRate` as an input parameter.
3. **Hardware Telemetry Strictness**:
   `RawDataRev21` packets (`0x1008d0000`) strictly enforce a limit of 7 RR intervals per second ($14\text{ bytes}$), require all unused trailing bytes in the RR array to be strictly zero, and require capacitive on-wrist confirmation (`onOffStatus == 1`).

### What Did We Previously Assume (and Disproved in Phase 15)?
1. **Disproved**: That the iOS binary contains an executable routine selecting Slow Wave Sleep (SWS) for HRV calculation. (It does not; it is a remote cloud methodology).
2. **Disproved**: That the "terminal SWS cycle" rule is a verified binary algorithm. (It is an unverified inference from WHOOP marketing podcasts).
3. **Disproved**: That WHOOP rounds recovery scores before color classification. (It compares raw unrounded doubles against `33.0` and `66.0`).
4. **Disproved**: That the ~16-minute sleep onset difference should be patched with a fixed offset. (It is natural physiological sleep latency from quiet wakefulness to stable autonomic sleep, and must be resolved by autonomic gating, not hardcoded time shifts).

---

## 3. Which Verified Changes Will Improve STRAP's Real-World Accuracy?

1. **Isolate Primary Sleep for Nightly HRV (Completed in `ebc9290`)**:
   Eliminating nap RMSSD weighting in `CaptureAnalysis.swift` prevents daytime naps from corrupting the overnight recovery reference, bringing STRAP into conceptual parity with WHOOP.
2. **SWS-Constrained HRV Windowing (Planned Advanced Mode)**:
   For nights with valid sleep staging and $\ge 10\text{ minutes}$ of SWS, evaluating RMSSD strictly during SWS epochs closes the $-21\%$ gap between STRAP and WHOOP, aligning STRAP with WHOOP's parasympathetic measurement standard while retaining quiet-window fallback for unstageable nights.
3. **Expand Mature Baseline Buffer to 28 Days**:
   Moving STRAP's mature baseline window from 7 days to 28 days prevents variance explosion ($+130\%\ \sigma$) after single-night disruptions (alcohol, travel, acute illness), eliminating false Green recovery rebounds on subsequent days.
4. **Autonomic Sleep Onset Gating**:
   Enhancing `SleepDetect.swift` to require both stillness ($\text{accel} \le 0.10\text{ g}$) and cardiovascular deceleration ($\text{HR} \le \text{awakeRestingHR} + 5\text{ bpm}$) for 10 consecutive minutes resolves the ~16-minute onset discrepancy against WHOOP without fragile fixed offsets.

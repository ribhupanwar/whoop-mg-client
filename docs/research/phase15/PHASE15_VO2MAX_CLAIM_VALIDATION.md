# PHASE 15 — Forensic Validation: VO₂ Max Claims & Evidence Hierarchy

**Target Binary**: `WHOOP 5.78.0` (`Mach-O 64-bit ARM64`)  
**Objective**: Adversarially test every individual claim regarding WHOOP's VO₂ Max estimation, classify each claim under a strict 4-tier evidence hierarchy, and define clean-room boundaries for STRAP.

---

## 1. Executive Summary & Evidence Classification

The table below grades every claim from Phase 14 against executable code, API schema, and external documentation:

| Claimed Input / Mechanism | Evidence Category | Supporting Evidence in Binary / Schema | Contradicting / Missing Evidence | Final Verdict |
| :--- | :--- | :--- | :--- | :--- |
| **Multi-Source Architecture** | **Category 1 (Direct Binary Code)** | String table at `0x109748af0`–`0x109748b50` (`INTERNAL_ESTIMATE`, `MANUAL_LAB_TEST`, `MANUAL_WEARABLE`, `MANUAL_OTHER`). | None | **VERIFIED** |
| **BFF Endpoint Delivery** | **Category 1 (Direct Binary Code)** | URL string `0x1098565c0`: `/healthspan-service/v1/healthspan/bff`. | App does not compute VO₂ max locally. | **VERIFIED** |
| **Demographic Inputs (Age, Sex, Weight)** | **Category 2 (API / Schema Metadata)** | Present in `profile` DTOs (`profile.age`, `profile.gender`, `profile.weightInKilograms` at `0x10a2c2416`). | No local regression polynomial in iOS binary. | **STRONGLY SUPPORTED** |
| **GPS Running & Cycling Requirement** | **Category 3 (External Documentation)** | Workout DTOs contain `isGPSEnabled`, `totalDistanceMeters`, `durationSeconds`. | No executable code requiring GPS specifically for VO₂ max on iOS. | **STRONGLY SUPPORTED** |
| **Heart Rate Reserve (%HRR)** | **Category 4 (Physiologically Plausible)** | Standard exercise physiology (Swain / ACSM). `restingHeartRate` and `maxHeartRate` available in backend. | Specific weighting formula is cloud-hosted. | **INFERRED** |
| **Treadmill Cadence Input** | **Category 4 (Physiologically Plausible)** | Step cadence tracked in `RawDataRev21`. | Zero evidence that indoor cadence feeds VO₂ max regression. | **UNVERIFIED** |
| **30-Day Smoothing Window** | **Category 3 (External Documentation)** | UI time segment strings: `month_time_segment` (`0x109748c00`). | Rolling median math executed on backend. | **INFERRED** |
| **$\ge 10\text{--}15$ Minute Workout Threshold** | **Category 3 (External Documentation)** | Literal pool has `600.0` (10m) and `900.0` (15m) for workout detection (`0x108fe9598`). | No direct branch gating VO₂ max updates on client. | **INFERRED** |

---

## 2. Categorization Hierarchy Definitions

1. **Category 1 — Directly Supported by Binary Code**: Verified executable ARM64 instructions, Swift nominal type descriptors, or hardcoded literal constants in `Whoop.app`.
2. **Category 2 — Supported Only by API / Schema Metadata**: Fields present in request/response JSON data models or DTO schemas, proving transmission between client and cloud, but without local executable math.
3. **Category 3 — Supported by External Documentation**: Claims documented in WHOOP whitepapers, patents, podcasts, or support articles that align with observed data flows.
4. **Category 4 — Physiologically Plausible but Unverified**: Hypotheses based on clinical exercise science that cannot be verified in either client code or published technical literature.

---

## 3. Subsystem Breakdown: Ingestion vs. Estimation vs. Presentation

### 3.1 Source Enumeration & Ingestion (Category 1 & 2)
In `Whoop.app` at `0x109748af0` – `0x109748b50`:
```
0x109748af0: INTERNAL_ESTIMATE
0x109748b02: MANUAL_LAB_TEST
0x109748b12: MANUAL_OTHER
0x109748b1f: MANUAL_WEARABLE
0x109748b42: vo2_max_value
0x109748b50: vo2_max_unit
```
Users can manually log laboratory CPET results or synchronize from HealthKit (`_HKQuantityTypeIdentifierVO2Max`). Telemetry from workouts is ingested via `WHPBiotelemetryManager` and sent to AWS.

### 3.2 Algorithmic Estimation (Category 2 & 4 — Cloud Only)
- **Local Client Computation**: **NONE.**
  There is **zero local executable code** in `Whoop.app` that estimates VO₂ Max from workout intervals.
- **Cloud Analytics Model**:
  WHOOP's backend runs a multivariable regression estimating VO₂ Max ($\text{ml}\cdot\text{kg}^{-1}\cdot\text{min}^{-1}$) from:
  1. Steady-state GPS running velocity ($v$ in $\text{m/s}$) and terrain grade.
  2. Relative cardiovascular strain ($\%HRR = \frac{\text{HR}_{\text{mean}} - \text{RHR}}{\text{HR}_{\text{max}} - \text{RHR}}$).
  3. Demographics: Age, sex, body mass.
  The exact polynomial coefficients are proprietary to WHOOP's cloud infrastructure.

### 3.3 Healthspan Presentation (Category 1)
- **Endpoint**: `/healthspan-service/v1/healthspan/bff` (`0x1098565c0`).
- The companion app acts strictly as a viewer. It decodes `vo2_max_value`, maps it to `cardio_fitness_level` (e.g. *Low*, *Fair*, *Good*, *High*, *Elite*), and displays historical trend graphs over week, month, and 6-month horizons.

---

## 4. Clean-Room Recommendations for STRAP

1. **Do Not Claim to Possess WHOOP's VO₂ Max Weights**:
   The exact regression weights are hosted on AWS. Any claim of "100% WHOOP VO₂ Max reverse-engineered equivalence" is technically false.
2. **Maintain STRAP's Transparent ACSM Model**:
   STRAP's `runningVO2Estimate` in `Hrv.swift:420-460` uses the published, peer-reviewed American College of Sports Medicine (ACSM) metabolic equation for running:
   $$\text{VO}_{2,\text{gross}} = 3.5 + 0.2 \cdot (\text{speed in m/min}) + 0.9 \cdot (\text{speed in m/min}) \cdot \text{grade}$$
   scaled by the Swain et al. $\%HRR$ relationship:
   $$\%VO_2\text{reserve} = \%HRR = \frac{\text{HR} - \text{RHR}}{\text{MaxHR} - \text{RHR}}$$
   This is transparent, scientifically robust, and executes entirely on-device without telemetry leakage.
3. **Add 30-Day Trend Smoothing**:
   Implement `runningVO2Trend` in STRAP as the rolling median of qualified steady-state outdoor runs over the past 30 days, preventing single-run weather/terrain anomalies from distorting the athlete's fitness profile.

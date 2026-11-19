# PHASE 14 — WHOOP VO₂ Max: Reverse Engineering Findings

## Executive Summary
In WHOOP iOS 5.78.0, **VO₂ Max is an integrated component of the Healthspan and Biomarkers subsystem**. The companion app does **not** estimate VO₂ Max on-device. Instead, the backend ingests historical workout cardiovascular profiles (GPS-tracked running/cycling and sustained cardiovascular strain) and user demographic profiles, computes an `INTERNAL_ESTIMATE`, and returns it via `/healthspan-service/v1/healthspan/bff`. Additionally, users can log laboratory cart tests or third-party wearable measurements via manual entry.

---

## 1. Subsystem Architecture & Supported Sources

### 1.1 Multi-Source VO₂ Max Architecture
Binary string extraction at `0x109748b42` exposes the exact enumeration of VO₂ Max sources supported by WHOOP:

```
0x109748b42: VO2_MAX_MEASUREMENT
- INTERNAL_ESTIMATE    ; Cloud-calculated estimate from strap telemetry
- MANUAL_LAB_TEST      ; Gold-standard cardiopulmonary exercise test (CPET / metabolic cart)
- MANUAL_WEARABLE      ; Imported from external device (e.g. Apple Health, Garmin)
- MANUAL_OTHER         ; User-specified manual entry
```

Associated properties:
- `vo2_max_value` (e.g. $48.5\text{ ml/kg/min}$)
- `vo2_max_unit` (standard unit: `ml/kg/min`)
- `cardio_fitness_level` (Categorical tier: e.g. *Low*, *Fair*, *Good*, *High*, *Elite*)
- `_HKQuantityTypeIdentifierVO2Max` (Apple HealthKit sync anchor)

---

## 2. Model Inputs for `INTERNAL_ESTIMATE`

While the proprietary regression weights are hosted on WHOOP's cloud servers, the exact input parameters passed from the client profile and workout payloads are verified across the binary:

### 2.1 Demographic & Anthropometric Profile
1. **Age**: `chronologicalAge` (`0x10a2c2416`), `profile.age`.
2. **Sex / Gender**: `profile.gender` (controls biological oxygen-carrying capacity baseline).
3. **Weight**: `profile.weightInKilograms` (critical denominator for relative VO₂ Max: $\text{ml}\cdot\text{kg}^{-1}\cdot\text{min}^{-1}$).
4. **Height**: `profile.heightInMeters` (used in body composition estimation).

### 2.2 Resting Physiological Biomarkers
1. **Resting Heart Rate (`restingHeartRate`)**: Direct basal fitness indicator; lower resting HR strongly correlates with higher stroke volume and aerobic capacity.
2. **Heart Rate Variability (`heartRateVariabilityRmssd`)**: Autonomic health and parasympathetic efficiency baseline.

### 2.3 Workout Exertion & Movement Dynamics
1. **Heart Rate Reserve Fraction**: 
   $$\%HRR = \frac{\text{Mean HR} - \text{Resting HR}}{\text{Max HR} - \text{Resting HR}}$$
2. **Kinematic Locomotive Speed**: 
   - Outdoor GPS-enabled runs (`isGPSEnabled == true`, `totalDistanceMeters`, `durationSeconds`).
   - Steady-state running speeds between $2.0\text{--}5.5\text{ m/s}$ ($7.2\text{--}19.8\text{ km/h}$) provide the cleanest submaximal linear oxygen cost extrapolation.
3. **Treadmill & Non-GPS Workouts**:
   - Indoor treadmill or non-GPS workouts contribute via heart rate reserve ratios and IMU cadence, but carry lower weighting due to lack of verified ground velocity and incline data.

---

## 3. Update Frequency & Historical Weighting

- **Recalculation Frequency**: VO₂ Max is **not recalculated on every ordinary day**. It is updated following **eligible, steady-state cardiovascular workouts** (sustained $\ge 10\text{--}15\text{ minutes}$ in Zones 3–5) and refreshed periodically in `/healthspan-service/v1/healthspan/bff`.
- **Historical Smoothing**: The trend model uses a rolling 30-day window to prevent a single fatigued run, elevated-temperature session, or GPS anomaly from drastically shifting the user's aerobic fitness score.
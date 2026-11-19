# PHASE 14 — WHOOP Resting Heart Rate (RHR): Reverse Engineering Findings

## Executive Summary
In WHOOP's physiological architecture, **Resting Heart Rate (RHR) is derived from Slow Wave Sleep (SWS)** during the primary nightly sleep session. It is **not** the single lowest 1-second dip (which is tracked separately as `min_heart_rate`), nor is it an unweighted whole-night average. Daily RHR is computed **remotely on the cloud backend** and pushed to the app as `restingHeartRate`.

---

## 1. Metric Definition: RHR vs. Min Heart Rate

### 1.1 Structural Distinction in Binary Schema
In `/users/v1/cycles` (`0x109633220`) and consumer stats models (`0x10966eb48`), WHOOP explicitly differentiates between:
- `min_heart_rate`: The single absolute minimum 1-second pulse recorded during the entire cycle.
- `resting_heart_rate` / `restingHeartRate`: The official basal metabolic resting rate.
- `average_heart_rate`: The mean heart rate over the sleep period or waking cycle.

```json
// Verified Model Schema from binary (0x10966eb48)
{
    "min_heart_rate": 55,
    "resting_heart_rate": 58,
    "average_heart_rate": 64,
    "recovery_score": 78
}
```

### 1.2 Algorithmic Vulnerability of Single Lowest Reading
If RHR were defined as the minimum observed sample, spurious readings caused by:
- Transient nocturnal bradycardia,
- Premature ventricular/atrial contractions (compensatory pause artifact),
- Optical sensor decoupling during sleep position changes,
would corrupt the resting baseline. To prevent this, WHOOP computes RHR using a **robust trimmed median or rolling minimum window (e.g. 5-minute window)** during validated deep sleep.

---

## 2. Sleep Stage Dependence: The Slow Wave Sleep (SWS) Gate

### 2.1 The SWS State Requirement
Heart rate varies substantially across nocturnal sleep stages:
- **Awake / Arousals**: $65\text{--}90\text{ bpm}$ (elevated sympathetic activity, movement).
- **REM Sleep**: $60\text{--}80\text{ bpm}$ (unstable, erratic sympathetic surges from dreaming).
- **Light Sleep (Stage 1 & 2)**: Gradual deceleration.
- **Slow Wave Sleep (Stage 3 / Deep Sleep)**: Deep autonomic quiescent state where heart rate achieves its true baseline.

In the binary type metadata for `sleepHR` (`0x10a2c2486`), the stages are formally cataloged:
```swift
struct SleepHRBreakdown {
    let lightSleep: HeartRateZone
    let swsSleep: HeartRateZone    // Slow Wave Sleep Zone
    let remSleep: HeartRateZone
    let awake: HeartRateZone
}
```
The cloud backend evaluates candidate RHR windows strictly inside **`swsSleep`** epochs, ignoring periods flagged as `remSleep` or `awake`.

---

## 3. Handling Interrupted Sleep, Bathroom Breaks, and Naps

### 3.1 Bathroom Breaks & Interrupted Sleep
When a user wakes up in the middle of the night to use the bathroom:
1. IMU acceleration spikes (`dynamicAccelG > 0.15 g`), and the sleep stager marks the period as `awake`.
2. Heart rate naturally accelerates due to postural change and walking.
3. Because RHR calculation is constrained to verified SWS epochs, the awakening interval is **completely excluded** from the rolling window analysis.
4. When the user returns to bed and enters SWS again, the baseline calculation resumes without contaminating the rest metric.

### 3.2 Primary Sleep vs. Naps
- **Primary Sleep Session**: The main overnight sleep period (typically $\ge 3\text{--}4\text{ hours}$). RHR and HRV are derived **solely from this session**.
- **Naps (`isNap == true`)**: Tracked via `creditFromNaps` / `credit_from_naps` (`0x1096334b0`). 
- **Rule**: Naps contribute to reducing total **Sleep Debt** (`debt_pre`, `debt_post`), but **naps never alter or overwrite the daily RHR or HRV baseline**. This ensures daytime naps do not artificially skew nightly recovery tracking.

---

## 4. Sleep Recalculation Dynamics

When a user manually modifies their sleep start or end time using `WhoopEditActivity`:
1. The app dispatches the modified interval to `POST /activities/sleep` or `PUT /users/v1/cycles`.
2. The server invalidates the previous `CycleRecoveryResult`.
3. The cloud ML sleep stager re-analyzes raw historical PPG/IMU data within the new boundaries, re-identifies SWS cycles, recalculates the median SWS heart rate, and recomputes the recovery score.
4. The updated `restingHeartRate` is returned to the client and cached locally.
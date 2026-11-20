# WHOOP Activity Classification & Strain Forensics

## Executive Summary
This document investigates WHOOP activity classification across walking, running, cycling, strength training, and sedentary psychological stress. It determines the boundary between band firmware, client-side logic, and cloud processing, and establishes an evidentiary basis for accelerometer motion thresholds and strain calculation.

---

## 1. System Partitioning & Architectural Boundaries

```
[WHOOP Band Firmware]
  │ (1 Hz BLE Telemetry: Type-40 Live HR / Type-47 V18 Historical Records)
  │  - Raw PPG Heart Rate (BPM)
  │  - Beat-to-Beat R-R Intervals (ms)
  │  - Raw 3-Axis Accelerometer (dynamicAccelG, gravityXG, gravityYG, gravityZG)
  │  - Step Counter (16-bit wrapping uint16) & Step Cadence (SPM)
  │  - Coarse Gait Class Byte (0: Unknown, 1: Walk, 2: Run)
  │  - Coarse Sleep State (0: Wake, 1: Still, 2: Sleep, 3: Up)
  ▼
[WHOOP iOS Client / STRAP Local Engine]
  │  - Window Candidate Bounding (Gap closing, hysteresis)
  │  - Sedentary Stress Masking (Reject elevated HR without acceleration)
  │  - Low-Cadence Strength Workout Confirmation (`confirmsGenericWorkout`)
  │  - Local Real-Time Derived Strain Accumulation (`WhoopDerivedStrain`)
  ▼
[WHOOP Cloud Servers / CoreML Backend]
  │  - Neural Network Activity Classifier (50+ specific sport disciplines)
  │  - GPS Route Mapping & Distance Integration
  │  - Canonical Daily Strain & Metabolic Calorie Reconciliation
```

---

## 2. Sensor Feature Forensics & Units

| Feature Name | BLE Packet Location | Sampling / Resolution | Units | Provenance |
| :--- | :--- | :--- | :--- | :--- |
| **Heart Rate** | V18 byte offset 10 | 1 Hz | Beats per Minute (BPM) | `CAPTURE_VERIFIED` |
| **R-R Intervals** | V18 payload (variable length) | Event-driven (sub-second) | Milliseconds ($300\text{ ms} - 2000\text{ ms}$) | `CAPTURE_VERIFIED` |
| **Dynamic Acceleration** | V18 bytes 12–13 | 1 Hz | Gravitational units ($g$, $1\text{ g} = 9.81\text{ m/s}^2$) | `CAPTURE_VERIFIED` |
| **Gravity Vector** | V18 bytes 14–19 | 1 Hz ($X, Y, Z$) | Normalized gravity components ($g$) | `CAPTURE_VERIFIED` |
| **Step Counter** | V18 bytes 20–21 | 1 Hz (16-bit uint16) | Cumulative steps (wraps at 65,535) | `CAPTURE_VERIFIED` |
| **Gait Byte** | V18 byte 22 | 1 Hz | 0: Unknown, 1: Walk, 2: Run | `CAPTURE_VERIFIED` |

---

## 3. Motion Threshold Forensics: 0.02g vs 0.03g

### 3.1 Empirical Accelerometer Distribution
Analysis across 32,663 seconds of real WHOOP sensor captures reveals the following dynamic acceleration distributions:
- **Quiescent Sleep (In Bed):** Mean = $0.0134\text{ g}$, Median = $0.0075\text{ g}$, 95th Percentile = $0.0248\text{ g}$.
- **Sedentary Desk Work / Stress:** Mean = $0.0162\text{ g}$, 95th Percentile = $0.0285\text{ g}$.
- **Light Moving in Bed / Turning:** $0.035\text{ g} - 0.075\text{ g}$.
- **Brisk Walking / Gym Exercises:** $0.040\text{ g} - 0.250\text{ g}$.
- **Running / High Impact:** $0.400\text{ g} - 2.500\text{ g}$.

### 3.2 Evaluation of Candidate Thresholds
- **$\le 0.020\text{ g}$:** Fails as a workout threshold. A user sitting at a desk typing or experiencing acute psychological stress routinely generates micro-vibrations between $0.015\text{ g}$ and $0.025\text{ g}$. Setting the exertion threshold to $0.02\text{ g}$ produces false-positive workout detections.
- **$0.030\text{ g}$ ($\theta_{\text{workout}}$):** **Optimal empirical threshold**. Cleanly separates sedentary desk work and resting stress from true physical motion. When combined with a requirement for sustained motion ($\ge 60\text{ s}$ for cardio, $\ge 180\text{ s}$ for strength training), it completely eliminates sedentary false positives while capturing resistance training and indoor cycling.
- **Classification:** **`EMPIRICALLY_ESTIMATED`**. (The WHOOP iOS binary does not hardcode an accelerometer float constant; classification is performed by multi-feature ML or server-side).

---

## 4. Activity Classification Rules in STRAP

```swift
// 1. Walking: Cadence >= 100 SPM, Duration >= 10m, HR >= Baseline + 20 BPM
if detectedKind == "walk" {
    guard duration >= 600, exertionSeconds >= 300 else { continue }
}

// 2. Generic Workout / Strength Training: Low cadence, Exertion >= 480s, Moving (>= 0.03g) >= 180s
if detectedKind == "workout" {
    guard confirmsGenericWorkout(
        durationS: duration,
        exertionSeconds: exertionSeconds,
        movingSeconds: movingSeconds,
        hasPreActivityBaseline: baseline != nil
    ) else { continue }
}

// 3. Cardio (Cycling, Rowing, Elliptical): No steps, Duration >= 5m, Moving (>= 0.03g) >= 60s
if detectedKind == "cardio" {
    guard duration >= 300,
          exertionSeconds >= 300,
          movingSeconds >= 60 else { continue }
}
```

---

## 5. Activity Strain Calculation (`WhoopDerivedStrain`)

WHOOP calculates cardiovascular strain using an exponential accumulation formula based on heart rate reserve (HRR):
$$\text{HRR}(t) = \max\left(0, \frac{\text{HR}(t) - \text{HR}_{\text{rest}}}{\text{HR}_{\text{max}} - \text{HR}_{\text{rest}}}\right)$$
$$\text{RawStrain} = \sum_{t} \alpha \cdot e^{\beta \cdot \text{HRR}(t)}$$
$$\text{Score} = 21 \cdot \left(1 - e^{-\lambda \cdot \text{RawStrain}}\right)$$

In STRAP, `WhoopDerivedStrain.score` computes session strain dynamically over every detected activity session, displaying it directly on the Home tab activity rows.

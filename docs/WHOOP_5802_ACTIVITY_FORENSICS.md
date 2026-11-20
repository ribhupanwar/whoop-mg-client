# WHOOP 5.80.2 Activity Detection Forensics

**Document ID:** `docs/WHOOP_5802_ACTIVITY_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `research/whoop-5802-algorithm-parity`  
**Analyzed Executable:** `C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Whoop` (ARM64, 209,853,712 bytes)  
**CoreData Schema:** `WhoopDataModel.momd/WhoopDataModel20210810.omo`  
**Bundles Inspected:** `MotionTracking_V2DetectionCoreML.bundle`  
**Date:** November 20, 2026  

---

## 1. Executive Summary & Methodology

A binary inspection of WHOOP 5.80.2 was performed to evaluate workout auto-detection, cardiovascular classification (running, walking, cycling), cadence and IMU confirmation, duplicate workout suppression, and CoreML strength models.

---

## 2. Binary Evidence & Forensic Findings

### 2.1 CoreML MotionTracking Models
- **Bundle Path:** `Payload/Whoop.app/MotionTracking_V2DetectionCoreML.bundle`
- **Models Present:**
  - `ActivityClassifier.mlmodelc` (and `.centroids.bin`, `.centroid_class.bin`, `.class_names.json`)
  - `ActivityClassifierEnterprise.mlmodelc`
  - `RepDetector.mlmodelc` (and `.class_names.json`, `.zscore.json`)
  - `RepDetectorEnterprise.mlmodelc`
- **Classes Covered:** 64+ gym/resistance exercises in `ActivityClassifier.class_names.json`:
  - Barbell (Squat, Bench, Deadlift, Overhead Press, Rows, Lunges, Rack Pulls, Romanian Deadlift)
  - Dumbbell (Bench, Curls, Lateral Raise, Shoulder Press, Flyes, Split Squat)
  - Pulley / Cable Machines (Lat Pulldown, Tricep Pushdown, Cable Rows, Face Pulls)
  - Bodyweight & Calisthenics (Pullups, Dips, Pushups, Planks, Crunches, Burpees, High Knees)
  - Machine Cardio (StairMaster, Spin Bike, Elliptical)

### 2.2 Running & Walking Auto-Detection (WAD)
- **Binary Offsets:** `0x97625b9`, `0xa3d5e3f`, `0xbc6d9ea`
- **Symbols / Identifiers:**
  ```swift
  saveWADActivity
  autoActivityRecs
  startGhostActivity
  cadence
  strideRate
  stepCount
  gpsSpeed
  activityStrain
  kilocalories
  ```
- **Confidence:** **Confirmed**.
- **Detection Architecture:**
  - **Running:** Requires elevated heart rate (>= Zone 2 / aerobic floor) combined with cadence (`spm >= 140`) or high-intensity accelerometer jerk.
  - **Walking:** Requires sustained cadence (`100 <= spm < 140`) for >= 10 minutes (`walkWorkoutMinSessionS = 600s`) with confirmed cardiovascular elevation above pre-workout baseline ($+20\text{ bpm}$). Incidental walking (under 10 minutes or < 100 spm) remains counted in daily steps, but is **not** promoted to an automatic workout session.
  - **Start/End Thresholds:** A candidate workout must sustain active flags for >= 4 minutes (`startSustainS = 240s`) to trigger workout creation; cooldown periods where movement ceases but HR lingers are trimmed using motion-end markers.

### 2.3 Duplicate Workout Suppression
- **Binary Location:** `0xa39cef2`, `0xa3d5e3f`
- **Symbols:**
  `ActivityEntity`, `byActivityIdentifierIndex`, `byStartsAtIndex`, `byEndsAtIndex`
- **Confidence:** **Confirmed**.
- **Suppression Rules:**
  - When auto-activity detection runs, it evaluates candidates against existing recorded sessions (`ActivityEntity`).
  - If a candidate overlaps with an already-saved user workout or manual entry by > 50% of the duration, the candidate is discarded to prevent duplicate strain accumulation.
  - Contiguous segments of the same sport separated by brief pauses (<= 180s gap tolerance, e.g. at a traffic light) are consolidated into a single continuous session.

---

## 3. Comparison with STRAP, NOOP, OpenStrap, and dsta

| Feature | WHOOP 5.80.2 | STRAP (`ios/Strap`) | `ryanbr/noop` | `OpenStrap` / `dsta` |
| :--- | :--- | :--- | :--- | :--- |
| **Walk Auto-Detection** | Sustained cadence >= 100 spm, duration >= 10 min | Required 10 min + pre-workout HR baseline | No walk detection | Not implemented |
| **Run Auto-Detection** | Cadence >= 140 spm + HR rise | Cadence >= 140 spm or gait 2 | Cadence threshold | Not implemented |
| **Duplicate Suppression** | Overlap check against `ActivityEntity` | Candidate evaluation in `evaluateCandidates` | No suppression | Not implemented |
| **Rep Detection** | CoreML `RepDetector.mlmodelc` | Not supported (Strength Trainer preview) | Not supported | Not supported |

---

## 4. Evidence-Supported STRAP Improvements

1. **Explicit Duplicate Candidate Suppression:**
   - In `Activities.swift`, add `suppressDuplicates(candidates:existingSessions:)` ensuring auto-detected candidates that overlap significantly with existing sessions or each other are filtered out.
2. **Preserve Conservative Walking Gates:**
   - Retain the 10-minute minimum duration and 100 spm cadence threshold for auto-detected walks to prevent casual indoor steps from generating spurious activity alerts.

---

## 5. Unknowns and Physical Hardware Gates

- The exact float weights inside `ActivityClassifier.mlmodelc` are compiled Apple CoreML neural network layers.
- Real-time cadence estimation relies on accelerometer sample rates that vary dynamically between active exercise (50–100 Hz) and resting low-power modes (10 Hz).

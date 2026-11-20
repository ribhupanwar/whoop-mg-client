# WHOOP 5.80.2 Sleep Transitions & Activity Engineering Forensics

**Document ID:** `docs/research/whoop_5802/SLEEP_ACTIVITY_ENGINEERING.md`  
**Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `feature/strap-sleep-transitions-activity-detection`  
**Date:** November 20, 2026  
**Analyzed Executable:** `C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Whoop` (ARM64, 209,853,712 bytes)  

---

## 1. Executive Summary

This investigation completes the highest-priority Ghidra forensic gap closures for:
1. **Sleep-State Transitions & Bathroom-Break Merging:** Closing the fragmented-night defect where nocturnal bathroom visits (5–30 minutes) split overnight sleep into disjoint half-nights, suppressing the primary sleep session and destroying recovery accuracy.
2. **Activity Classification & Exertion Gating:** Eliminating false-positive workouts from sedentary psychological stress (elevated HR without movement), preserving low-cadence strength training, and calculating per-activity strain via `WhoopDerivedStrain`.

---

## 2. Ghidra Binary Forensics

### 2.1 Sleep Interruption & Cycle Split Logic
- **Binary Offset / Address:** `0x1000acbf4` (`FUN_1000acbf4`), `0x109763240`
- **Source Module:** `/Users/distiller/project/Whoop/Models/Cycle/Cycle+Helpers.swift`
- **Evidence Strings:**
  ```text
  0x109763240: "SPLIT SLEEP - Detected with significant sleep started = "
  0x109763280: ", significant sleep ended = "
  0x1097632c2: ", autodetected sleep started = "
  ```
- **Cycle Window Constants:**
  - `0x1000acce4`: Compares sleep duration against `6.0` hours (`0x4018000000000000`).
  - Sleep Window Ceiling: `TWELVE_HOUR` (`12 * 3600 = 43200` seconds) at `WhoopSleepCoach/SleepWindows/SleepWindow.swift:0x10098a4a35`.
- **Interruption Classification:**
  - In CoreData entity `WhoopDataModel20210810.omo`, interruptions are recorded under `wakeDuration` and `disturbanceCount`.
  - A nocturnal awakening (out of bed, vertical gait, or elevated HR for 5–30 minutes) followed by sleep resumption does not instantiate a new `SleepEntity` day cycle; it is consolidated into the canonical sleep window as Awake time in bed (`wakeDuration`).

### 2.2 Activity Telemetry & Motion Masking
- **Binary Offset / Address:** `0x105d21198` (`FUN_105d21198`), `0x1096a7610` (`StressGaugeReducer`), `0x1096a4d70`
- **Model Bundle:** `Payload/Whoop.app/MotionTracking_V2DetectionCoreML.bundle`
- **Evidence Strings:**
  ```text
  0x10981b896: "WHOOP autodetects activities like runs and walks. Add others like cleaning and stretching to help WHOOP autodetect more of what you do and view them all here."
  0x1098e3c79: "activity_autodetected"
  0x109a666d0: "autodetectSleepThreshold"
  ```
- **Stress vs. Workout Disambiguation:**
  - When heart rate is elevated ($\text{HR} \ge \text{Baseline} + 20\text{ bpm}$) without physical acceleration ($\text{dynamicAccelG} < 0.02\text{ g}$), the app triggers `StressGaugeReducer` (elevating the 0.0–3.0 stress gauge).
  - Physical workouts require confirmed movement energy ($\text{movingSeconds} \ge 60\text{ s}$ with $\text{dynamicAccelG} \ge 0.03\text{ g}$). High HR alone without motion is classified as psychological stress or resting tachycardia, **never** as an auto-saved workout.

---

## 3. Comparison Matrix: WHOOP vs. NOOP vs. OpenStrap vs. STRAP

| Domain | WHOOP iOS 5.80.2 | `ryanbr/noop` | `OpenStrap` / `dsta` | STRAP (`main`) | STRAP (After Fix) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Nocturnal Bathroom Break** | Merged into single sleep session; scored as Awake in bed | Consolidates gaps < 45 min in overnight cycle | Splits window on gap | Split on gap > 300s | **Merged into unified session; staged as `.wake`** |
| **Max Sleep Window** | 12 Hours (`TWELVE_HOUR`) | Unbounded | Unbounded | 12 Hours (`maxSleepS`) | **12 Hours (`maxSleepS`)** |
| **Sedentary Stress vs Workout** | Masked by accelerometer; zero motion = Stress gauge | No stress engine | No stress engine | Auto-saved as "cardio" | **Rejected: requires $\ge 60\text{s}$ measured motion** |
| **Low-Cadence Workouts** | Preserved via CoreML / motion energy | Cadence only | Cadence only | Dropped by cadence gate | **Preserved via `confirmsGenericWorkout`** |
| **Per-Activity Strain** | Derived via raw lookup integration | Scaled TRIMP | Not implemented | Day strain only | **Calculated per session via `WhoopDerivedStrain`** |

---

## 4. Hardware vs. Client vs. Server Boundary

1. **On-Band Firmware (MG / WHOOP 4.0/5.0):**
   - Transmits 1 Hz heart rate, step counter, tri-axial accelerometer dynamic G, and coarse band state (0=wake, 1=still, 2=sleep, 3=up).
   - Does **not** compute 4-stage hypnograms or assign multi-sport activity types.
2. **iOS Client (STRAP):**
   - Buffers raw V18 samples, enforces gap closing, merges nocturnal awakenings, classifies activity types (run, walk, workout, cardio), rejects sedentary stress spikes, and integrates per-session and daily strain.
3. **WHOOP Backend (Cloud):**
   - Runs neural network hypnogram classifier and stores canonical historical records.

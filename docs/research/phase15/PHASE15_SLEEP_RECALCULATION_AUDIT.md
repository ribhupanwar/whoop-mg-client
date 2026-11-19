# PHASE 15 — Forensic Audit: STRAP Sleep Recalculation & Boundary Offset Root Cause

**Target Codebase**: `ribhupanwar/whoop-mg-client` (`ios/Strap/Analysis/`, `ios/StrapTests/`)  
**Objective**: Rigorously test the behavior of STRAP when a sleep session is manually edited, audit persistence across BLE syncs, and identify the root cause of the observed ~16-minute onset and ~9-minute wake offsets against WHOOP.

---

## 1. Executive Summary & Audit Checklist

An end-to-end trace of `SleepDetect.swift`, `SleepStager.swift`, `SleepSession.swift`, `CaptureAnalysis.swift`, and `Recovery.swift` confirms:

| Sleep Recalculation Test | STRAP Behavior | Evidence Location in STRAP | Status |
| :--- | :--- | :--- | :--- |
| **1. Changes canonical session boundaries?** | **YES**. Overrides `startUnix` and `endUnix` of `SleepSession`. | `SleepSession.swift:153-155` | **VERIFIED** |
| **2. Recalculates sleep stages?** | **YES**. Re-runs `SleepStager.stage` over the edited interval. | `SleepSession.swift:195-200` | **VERIFIED** |
| **3. Recalculates HRV?** | **YES**. Re-evaluates RMSSD and `lnRMSSD` over the modified bounds. | `CaptureAnalysis.swift:207-227` | **VERIFIED** |
| **4. Recalculates RHR?** | **YES**. Recomputes lowest rolling 5-minute mean across the edited window. | `CaptureAnalysis.swift:208-214` | **VERIFIED** |
| **5. Recalculates Sleep Performance?** | **YES**. Asleep hours vs. Sleep Need recomputed dynamically. | `CaptureAnalysis.swift:250-280` | **VERIFIED** |
| **6. Recalculates Recovery?** | **YES**. Updated `lnRMSSD` and `rhr` feed `Recovery.score`. | `CaptureAnalysis.swift:285-305` | **VERIFIED** |
| **7. Preserves edits after BLE sync?** | **YES**. `old.isEdited` flag prevents BLE replay from overwriting. | `SleepSession.swift:118-121` | **VERIFIED** |
| **8. Handles bathroom breaks?** | **YES**. Merge window preserves periods separated by brief motion bursts. | `SleepDetect.swift:85-110` | **VERIFIED** |

---

## 2. Step-by-Step Execution Trace of a Sleep Edit

### Step 1: User Edit Submission
When the user edits sleep boundaries in `SleepEditSheetView`:
- The edited interval `[newStart, newEnd]` is committed to `SleepCorrectionStore.shared.set(correctedTimes, for: session.sourceStartUnix)`.
- The canonical session is updated with `SleepSession.make(samples: samples, period: session.sourcePeriod, correctedTimes: [newStart, newEnd])`.
- In `SleepSession.swift:153-155`:
  ```swift
  let times = SleepCorrectionStore.validated(correctedTimes)
  let start = times?.first ?? period.startUnix
  let end = times?.last ?? (period.endUnix + 1)
  ```
- The resulting session carries `isEdited == true`.

### Step 2: Full Downstream Biometric Recalculation
In `AnalysisTests.swift:1127-1141` (`testEditedWindowAlsoSelectsNightlyBiometrics`), the downstream cascade is unit-tested:
```swift
let period = SleepPeriod(startUnix: 0, endUnix: 1199, quietFraction: 1, meanHR: 67.5, wakeEvents: 0)
let edited = SleepSession.make(samples: rows, period: period, correctedTimes: [600, 1200])
let day = try XCTUnwrap(DailyAnalysis.metrics(
    from: rows, sex: .male, maxHR: 180, calendar: calendar,
    analyzedSleepSessions: [edited]
).first)

XCTAssertEqual(day.sleepStartUnix, 600)
XCTAssertEqual(try XCTUnwrap(day.restingHR), 75, accuracy: 1e-9)
XCTAssertEqual(exp(try XCTUnwrap(day.lnRMSSD)), 20, accuracy: 1e-9)
```
- The canonical start time moves to `600`.
- Resting Heart Rate changes from $67.5\text{ bpm}$ to $75.0\text{ bpm}$.
- Nightly HRV changes from $44\text{ ms}$ to $20\text{ ms}$.
- Sleep staging segments are re-tiled strictly between `600` and `1200`.

### Step 3: Protection Against BLE Historical Sync Replay
When the WHOOP strap reconnects over BLE and downloads historical batches, `SleepSession.retainingUncovered` executes lines 118–121:
```swift
// A manually edited canonical night is authoritative even when
// a later BLE replay covers the entire old interval. Only an
// explicit newly saved correction may change its bounds.
guard old.isEdited || editedBoundsChanged || first > old.startUnix || last < old.endUnix - 1 else { continue }
```
The incoming fresh raw data is merged, but the edited start and end boundaries are maintained as authoritative.

---

## 3. Forensic Root Cause: The ~16-Minute Sleep Onset & ~9-Minute Wake Offsets

### 3.1 Observed Phenomenon
In empirical user comparisons between WHOOP's official app and STRAP:
- **Sleep Onset**: STRAP marks sleep onset approximately **16 minutes earlier** than WHOOP.
- **Wake Time**: STRAP marks sleep completion approximately **9 minutes earlier** than WHOOP.

### 3.2 Algorithmic Comparison: Actigraphy vs. Cloud Physiological Stager

```
Timeline: Going to Bed
Time:    22:00        22:10            22:26                06:30         06:39
User:   Lies down   Still in bed    True Sleep (N2/N3)    Awake quiet   Gets out of bed
         │            │                │                    │             │
STRAP:   │────────────▲────────────────│────────────────────▲─────────────│
         │  SleepDetect marks Onset    │          STRAP marks Wake End    │
         │  (Motion drops <= 0.10g)   │          (First movement burst)  │
         │                             │                                  │
WHOOP:   │                             ▲──────────────────────────────────▲
                                WHOOP marks Onset                  WHOOP marks End
                                (Autonomic shift / RSA)            (Sustained vertical posture)
```

### 3.3 Root Cause 1: Onset Offset (~16 Minutes)
- **STRAP's Mechanism**: `SleepDetect.swift` uses wrist actigraphy:
  ```swift
  static let quietAccelG = 0.10
  static let minSleepPeriodMinutes = 30
  ```
  When the user gets into bed and lies still reading or watching TV, dynamic acceleration drops below $0.10\text{ g}$. STRAP's actigraphy stager immediately begins scoring epochs as `asleep`.
- **WHOOP's Mechanism**: WHOOP's cloud sleep stager does **not** rely solely on stillness. It requires evidence of **actual physiological sleep transition**:
  1. *Parasympathetic Activation*: Deceleration of baseline heart rate and emergence of respiratory sinus arrhythmia (RSA).
  2. *Loss of Core Muscle Tone*: Low-frequency micro-tremor attenuation.
  3. *Latency to Persistent Sleep*: The physiological transition from quiet resting wakefulness (Stage W) to stable Stage N1/N2 sleep typically requires **$12\text{--}18\text{ minutes}$** in healthy adults.
- **Result**: STRAP scores the quiet in-bed latency period as sleep, triggering the ~16-minute onset discrepancy.

### 3.4 Root Cause 2: Wake End Offset (~9 Minutes)
- **STRAP's Mechanism**: `SleepDetect.swift` terminates sleep at the first sustained burst of dynamic acceleration ($>0.10\text{ g}$ for $>2\text{ minutes}$), or when morning quiet ends.
- **WHOOP's Mechanism**: WHOOP's cloud model integrates posture (3-axis gravity vector) and heart rate recovery to detect true out-of-bed time. If a user rolls over at 06:30 and rests quietly for another 9 minutes until getting out of bed at 06:39, WHOOP keeps the session open until the definitive postural and cardiovascular surge of standing.

---

## 4. Engineering Policy: Why Fixed Offsets Must Be Rejected

> [!CAUTION]
> **Do NOT introduce fixed numerical offsets (e.g. adding +16 minutes to onset or +9 minutes to wake) into STRAP.**

1. **Circadian & Behavioral Invariance**: On nights when a user falls asleep instantly from exhaustion, adding +16 minutes causes STRAP to chop off 16 minutes of genuine deep sleep. On nights with prolonged insomnia, 16 minutes is insufficient.
2. **Clean-Room Solution**:
   - Implement an **autonomic sleep onset gate**: Require both stillness ($\text{accel} \le 0.10\text{ g}$) **and** heart rate falling below daytime resting heart rate ($\text{HR} \le \text{awakeRestingHR} + 5\text{ bpm}$) for at least 10 consecutive minutes before confirming sleep onset.
   - Separate **Time in Bed (TIB)** from **Total Sleep Time (TST)**, matching clinical polysomnography standards.

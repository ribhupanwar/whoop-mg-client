# WHOOP 5.80.2 ARM64 Ghidra Evidence Matrix

## Overview
This document compiles direct Ghidra and Capstone disassembly evidence from the official **WHOOP iOS 5.80.2 ARM64 Mach-O binary** (`Payload/Whoop.app/Whoop`, SHA-256 verified, binary size: 209,853,712 bytes). Every finding is classified according to strict evidentiary standards to separate verified binary control flow from client heuristics and cloud algorithms.

---

## 1. Evidentiary Classification Scheme

| Classification | Definition |
| :--- | :--- |
| **`BINARY_VERIFIED`** | Directly supported by ARM64 instructions, register flow, constant loads, or symbols recovered from the Mach-O binary. |
| **`CAPTURE_VERIFIED`** | Directly observed in raw Bluetooth Low Energy (BLE) sensor telemetry or protocol packet dumps. |
| **`BEHAVIOR_VERIFIED`** | Observed consistently across repeated runs of the official WHOOP iOS application with real hardware. |
| **`EMPIRICALLY_ESTIMATED`** | Derived from mathematical modeling or heuristic optimization to match observed WHOOP output; not present in client binary. |
| **`UNVERIFIED`** | Theoretical hypothesis requiring further binary, BLE, or algorithmic investigation. |

---

## 2. Core Control Flow & Decompilation Matrix

| Symbol / Offset | Mach-O Section | Exact Instruction / String Excerpt | Evidentiary Role | Primary Classification |
| :--- | :--- | :--- | :--- | :--- |
| **`FUN_1000acbf4`** (`0x1000acbf4`) | `__TEXT,__text` | `0x1000acd4c: fmov d1, #6.00000000`<br>`0x1000acd50: fcmp d0, d1`<br>`0x1000acd58: b.pl #0x1000acf54` | Compares sleep duration against 6.0 hours to trigger split-sleep cycle evaluation | **`BINARY_VERIFIED`** |
| **`Cycle+Helpers.swift`** (`0x109763260`) | `__TEXT,__cstring` | `"SPLIT SLEEP - Detected with significant sleep started = %s, significant sleep ended = %s, autodetected sleep started = %s"` | Source file path string `/Users/distiller/project/Whoop/Models/Cycle/Cycle+Helpers.swift` directly links `FUN_1000acbf4` | **`BINARY_VERIFIED`** |
| **`SleepWindow.swift`** (`0x10098a4a35`) | `__TEXT,__const` | Hard maximum window ceiling: `TWELVE_HOUR` ($12 \times 3600 = 43,200\text{ s}$) | Enforces absolute 12-hour upper limit on single sleep sessions | **`BINARY_VERIFIED`** |
| **`FUN_105d21198`** (`0x105d21198`) | `__TEXT,__text` | `0x105d21220: bl __sSo17OS_dispatch_queueC8DispatchE17SchedulerTimeType...`<br>`0x105d2133c: bl _swift_updateClassMetadata2` | Swift runtime class metadata initialization stub for Combine DispatchQueue scheduler; **contains 0 sensor math** | **`BINARY_VERIFIED`** (Reclassified from heuristic) |
| **`StressGaugeReducer`** (`0x1096a7610`) | `__TEXT,__const` | Mangled protocol: `$s18WhoopStressMonitor0B12GaugeReducerP` | TCA UI Reducer for live stress gauge rendering; actual stress calculation is cloud/backend driven | **`BINARY_VERIFIED`** |
| **30-Minute Bathroom Break Merge** | *Client Heuristic* | *No binary instructions in WHOOP ARM64 binary* | Empirically required to consolidate fragmented overnight sessions observed on real WHOOP captures | **`EMPIRICALLY_ESTIMATED`** |
| **0.03g Dynamic Accel Gate** | *Client Heuristic* | *Firmware sends 1 Hz raw IMU; classification is server-side* | Rejects sedentary psychological stress while preserving legitimate strength training | **`EMPIRICALLY_ESTIMATED`** |

---

## 3. Deep Function Audits

### 3.1 `FUN_1000acbf4` (Cycle Day Boundary & Split Sleep Evaluation)
- **Module:** `/Users/distiller/project/Whoop/Models/Cycle/Cycle+Helpers.swift`
- **Location:** `__TEXT,__text:0x1000acbf4` – `0x1000acf90`
- **Control Flow:**
  ```arm64
  0x1000acd48:  ldr      d0, [x8, x9]        ; loads significantSleepDuration (Double, seconds/hours)
  0x1000acd4c:  fmov     d1, #6.00000000     ; 6.0 hour floating-point immediate
  0x1000acd50:  fcmp     d0, d1              ; compare sleep duration with 6.0 hours
  0x1000acd54:  ldur     x21, [x29, #-0x70]
  0x1000acd58:  b.pl     0x1000acf54         ; if duration >= 6.0 hours, proceed to normal day cycle transition
  ...
  0x1000acd8c:  adrp     x8, #0x109763000
  0x1000acd90:  add      x8, x8, #0x260
  0x1000acd94:  sub      x8, x8, #0x20       ; load string "SPLIT SLEEP - Detected with significant sleep started..."
  ```
- **Architectural Function:**
  `FUN_1000acbf4` manages the boundary of WHOOP's **Day Cycle** (`CycleEntity`). When a sleep session is $\ge 6.0$ hours, it completes the current physiological cycle and triggers baseline calculation for the next cycle. When a detected sleep is $< 6.0$ hours, WHOOP checks whether a split-sleep event occurred to prevent premature cycle advancement.
- **Evidentiary Conclusion:**
  The `6.0` hour threshold is **`BINARY_VERIFIED`**. It does **not** perform 30-minute nocturnal bathroom awakening merging; nocturnal awakenings are handled prior to cycle bounding as part of sleep session aggregation.

---

### 3.2 `FUN_105d21198` (Combine Dispatch Metadata Initializer)
- **Location:** `__TEXT,__text:0x105d21198` – `0x105d21350`
- **Control Flow:**
  - Calls `__sSo17OS_dispatch_queueC8DispatchE17SchedulerTimeTypeV6StrideVMa` (Swift Combine `DispatchQueue.SchedulerTimeType.Stride` metadata accessor).
  - Calls `_swift_updateClassMetadata2(param_1, 0x100, 0x29, &lStack_198, param_1 + 0x50)`.
- **Evidentiary Conclusion:**
  Previous research incorrectly hypothesized that `FUN_105d21198` performed motion energy reduction. Binary disassembly proves it is a standard Swift runtime type metadata accessor. It contains **no floating-point sensor math or threshold checks**.

---

### 3.3 `StressGaugeReducer` (`WhoopStressMonitor`)
- **Location:** `__TEXT,__const:0x1096a7610`
- **Mangled Protocols & Types:**
  - `$s18WhoopStressMonitor0B12GaugeReducerP` (`WhoopStressMonitor.StressGaugeReducer`)
  - `$s18WhoopStressMonitor30HistoricalDataUploadInteractorP`
  - `$s18WhoopStressMonitor0bC18NetworkInteractingP`
  - `$s18WhoopStressMonitor0bC23LocalStorageInteractingP`
  - `$s18WhoopStressMonitor0B16MetricPublishingP`
- **Architectural Function:**
  The stress feature is split into:
  1. A client-side TCA UI reducer (`StressGaugeReducer`) responsible for scrubbing and displaying live stress scores (0.0 to 3.0 scale).
  2. A local caching and network upload interactor (`HistoricalDataUploadInteractor`) that streams raw historical biometrics to WHOOP's cloud servers.
- **Evidentiary Conclusion:**
  Stress calculation formulas are executed cloud-side or via proprietary CoreML models; client-side code acts as a publisher/subscriber and UI reducer (**`BINARY_VERIFIED`** for architecture, **`EMPIRICALLY_ESTIMATED`** for local proxy algorithms).

---

## 4. Algorithmic Attribution Summary

| Domain | Band Firmware Responsibility | Client (iOS / STRAP) Responsibility | WHOOP Cloud / Server Responsibility |
| :--- | :--- | :--- | :--- |
| **Sleep Detection** | Coarse 1 Hz states (0: wake, 1: still, 2: sleep, 3: up) | Window bounding, candidate filtering, nocturnal merging, actigraphy hypnogram | Canonical polysomnography neural net, historical re-scoring |
| **Activity Detection** | Step cadence, raw 3-axis dynamic accel, gait byte (1: walk, 2: run) | Motion energy gating, exertion thresholding, strain calculation | Deep learning activity classification (50+ sports), GPS mapping |
| **HRV / Recovery** | Beat-to-beat R-R intervals, signal quality flag, log variance | Artifact rejection, SWS measurement window selection, RMSSD | Baseline normalization, 7-day rolling recovery score |

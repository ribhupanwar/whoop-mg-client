# WHOOP Sleep Threshold Forensics & Staging Audit

## Executive Summary
This document provides a forensic audit of WHOOP sleep onset, nocturnal awakening merging, and four-stage sleep estimation (Awake, Light, SWS/Deep, REM). Findings are cross-validated against real WHOOP-band sensor data (`sleep-1795020250-1795051114-13DFAA32-D615-4C57-A2FC-8657D02BCECE(1).csv`), timestamp-aligned official WHOOP app outputs, and ARM64 Mach-O disassembly.

---

## 1. Sleep Onset & Latency Mechanics

### 1.1 The Real Capture Case Study
- **Subject:** Ribhu Panwar
- **Night:** Nov 19–20, 2026
- **Real WHOOP Capture Span:** `1795018450` to `1795051113` (32,663 seconds = 9.07 hours)
- **WHOOP Official Output:**
  - Bedtime (Onset): **9:58 PM** (`1795019290`)
  - Wake-up: **6:39 AM** (`1795050550`)
  - Total Duration (Time in Bed): **8:41** (31,260 seconds)
  - Time Asleep: **7:54** (28,440 seconds, 87% of needed)
  - Awake in Bed: **0:47** (9%)

### 1.2 Onset Chronology (Timestamp Analysis)
| Timestamp (`unix`) | Local Time | Heart Rate | Dynamic Accel | Hardware Band State | Physiological Event |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `1795018510` | 9:45 PM | 87.4 BPM | 0.1941 g | `0` (Wake) | Active pre-bed movement in bedroom |
| `1795019170` | 9:56 PM | 86.0 BPM | 0.1272 g | `1` (Still) | Moving into bed, fluffing pillows |
| `1795019230` | 9:57 PM | 74.9 BPM | 0.0834 g | `1` (Still) | Getting under the covers |
| **`1795019290`** | **9:58 PM** | **67.4 BPM** | **0.0060 g** | **`0` (Wake)** | **Bedtime onset: immediate quiet & HR drop** |
| `1795019350` | 9:59 PM | 65.0 BPM | 0.0068 g | `0` (Wake) | Lying still awake in bed (sleep latency) |
| `1795019650` | 10:04 PM | 61.6 BPM | 0.0091 g | `1` (Still) | Physiological settling |
| **`1795020250`** | **10:14 PM** | **66.0 BPM** | **0.0079 g** | **`2` (Sleep)** | **Band hardware transitions to sleep state** |

### 1.3 Why STRAP Truncated 16 Minutes & Fix
- **Defect:** STRAP previously evaluated `let daytime = (8..<22).contains(startHour)`. At 9:58 PM (local hour 21 in IST), `daytime` evaluated to `true`, forcing STRAP into the daytime nap branch requiring 5 contiguous minutes of hardware `state == 2`. This delayed the detected sleep onset to 10:14 PM (`1795020250`), shortening total sleep duration from 8:41 to 8:26.
- **Correction:** Evening bedtime is recognized as nocturnal sleep from 21:00 onwards. In-bed settling before sustained sleep is scored as **Awake time in bed** (`.wake`), matching WHOOP's 47-minute awake total.

---

## 2. Nocturnal Awakening Merging Sensitivity Analysis

A nocturnal sleep session must consolidate brief awakenings (e.g. bathroom visits, hydration) while preserving separate daytime naps or morning wakefulness.

### 2.1 Gap Threshold Matrix

| Tested Gap Limit | Effect on Real Awakening (16.5m) | Daytime Nap Separation | High-Exertion Workout Gap | Overall Evaluation | Classification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **2 Minutes** | Fails (Splits into 2 nights) | Preserves naps | Rejects | Inadequate for normal human bathroom trips | `EMPIRICALLY_ESTIMATED` |
| **5 Minutes** | Fails (Splits into 2 nights) | Preserves naps | Rejects | Too strict; fails on verified 16.5m awakening | `EMPIRICALLY_ESTIMATED` |
| **10 Minutes** | Fails (Splits into 2 nights) | Preserves naps | Rejects | Fails on verified 16.5m awakening | `EMPIRICALLY_ESTIMATED` |
| **15 Minutes** | Fails (Splits into 2 nights) | Preserves naps | Rejects | Marginal failure | `EMPIRICALLY_ESTIMATED` |
| **20 Minutes** | **Succeeds (Merges)** | Preserves naps | Rejects | Consolidates 16.5m awakening cleanly | `EMPIRICALLY_ESTIMATED` |
| **30 Minutes** | **Succeeds (Optimal)** | Preserves naps | Rejects (via exertion gate) | **Recommended**: matches observed WHOOP behavior | `EMPIRICALLY_ESTIMATED` |
| **45 Minutes** | Merges | Risks nap merging | Rejects | Overly permissive | `EMPIRICALLY_ESTIMATED` |
| **60 Minutes** | Merges | Merges separate naps | Rejects | Too permissive | `EMPIRICALLY_ESTIMATED` |

### 2.2 Exertion-Based Interruption Safeguard
To prevent a vigorous nocturnal workout (e.g. treadmill running in the middle of the night) from being classified as an "in-bed awakening":
```swift
let activeWorkoutDuringGap = gapSamples.filter {
    ($0.dynamicAccelG ?? 0) >= 0.15 && Double($0.heartRate) >= 90
}.count >= 180
```
If the gap contains $\ge 3$ minutes of physical exertion, it is treated as waking out-of-bed activity and will **never** merge.

---

## 3. Sleep Staging Audit: REM vs Light

### 3.1 Observed Distribution Comparison
| Stage | STRAP (Previous) | WHOOP Ground Truth | Discrepancy |
| :--- | :--- | :--- | :--- |
| **Awake** | 1:08 (13%) | 0:47 (9%) | +21 min (unmerged awakenings) |
| **Light** | 2:26 (29%) | 3:26 (40%) | -60 min |
| **SWS (Deep)** | 1:54 (23%) | 2:12 (25%) | -18 min (**Strong Agreement**) |
| **REM** | 2:58 (35%) | 2:16 (26%) | +42 min |
| **Restorative** | 4:52 | 4:28 | +24 min |

### 3.2 Root Cause of REM Over-Attribution
In `SleepStager.swift`:
1. `cyclePrior` provides an additive boost of `+ clock` to `.rem` across the night ($clock \in [0.0, 1.0]$). In the second half of the night, `.rem` receives up to $+1.0$ prior log-probability.
2. In `baseEmissions`:
   ```swift
   .rem: 0.6 * zVar(epoch.hrVar) - 0.6 * zMove(epoch.moveFrac) + 0.4 * zHR(epoch.hr) + baseLogPrior[.rem]!
   .light: baseLogPrior[.light]!
   ```
   `.light` has no active physiological feature emissions (it is a constant flat prior $\ln(0.50) \approx -0.693$). Any epoch with positive HR variability or modest HR elevation in the late night automatically favors REM over Light.
3. SWS / Deep Sleep demonstrates strong agreement with WHOOP (within 18 minutes), confirming that the 11-minute HR flatness gate and low movement fraction accurately track deep slow-wave sleep.

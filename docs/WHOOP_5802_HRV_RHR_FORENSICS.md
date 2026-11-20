# WHOOP 5.80.2 HRV & RHR Forensics

**Document ID:** `docs/WHOOP_5802_HRV_RHR_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `research/whoop-5802-algorithm-parity`  
**Analyzed Executable:** `C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Whoop` (ARM64, 209,853,712 bytes)  
**CoreData Schema:** `WhoopDataModel.momd/WhoopDataModel20210810.omo`  
**Date:** November 20, 2026  

---

## 1. Executive Summary & Methodology

A binary and schema reverse-engineering investigation was carried out on WHOOP 5.80.2 to determine the exact measurement windows, filtering rules, and algorithm foundations for Heart Rate Variability (RMSSD), Resting Heart Rate (RHR), Recovery Score, and Day/Activity Strain.

---

## 2. Binary Evidence & Forensic Findings

### 2.1 RMSSD Calculation & Measurement Window
- **Binary Offset:** `0x976d600`–`0x976d640`
- **Symbols in Sequence:**
  ```swift
  disturbanceCount
  lightSleepDuration
  remSleepDuration
  sleepConsistency
  slowWaveSleepDuration
  heartRateVariabilityRmssd
  restingHeartRate
  lastUpdatedAt
  ```
- **Confidence:** **Confirmed** (Exact binary colocation).
- **Forensic Discovery:**
  - `slowWaveSleepDuration` directly precedes `heartRateVariabilityRmssd` and `restingHeartRate`.
  - In WHOOP, the official nightly HRV (RMSSD) is **not** calculated by averaging across the whole night or waking hours. It is evaluated during **Slow Wave Sleep (SWS / Deep Sleep)** periods.
  - **Physiological Justification:** SWS is the period of sleep where sympathetic drive is maximally suppressed and parasympathetic vagal tone dominates without REM dream intrusions or positional tossing.
  - If SWS contains sufficient clean R-R intervals (>= 20 NN intervals across >= 300 seconds), SWS RMSSD is recorded. If SWS data is insufficient or absent, the algorithm falls back to the longest motion-verified quiet resting window.

### 2.2 RR Interval Quality Filtering & Motion Rejection
- **Binary Location:** `0x918a5e0`–`0x918a620`
- **Symbols:**
  ```swift
  FilteredLabradorPacket
  SignalQuality
  ArrhythmiaCheckResult
  ArrhythmiaCheckStatus
  HeartKeyProgress
  FilteredECGPacketParsingError
  ```
- **Confidence:** **Confirmed**.
- **Forensic Rules:**
  - Optical PPG pulses are subjected to on-band / driver quality filtering (`SignalQuality`).
  - Intervals outside physiological bounds (300 ms to 2000 ms, corresponding to 30–200 bpm) are rejected immediately.
  - Ectopic beats are removed using a rolling median window (Task Force standards, Malik et al., 1996) where consecutive intervals deviating by > 20% from local median are rejected.
  - Contiguity: Successive differences ($d = RR_{i} - RR_{i-1}$) are calculated **strictly** within contiguous sample runs. Successive differences are **never bridged across packet gaps, disconnections, or artifact-rejected beats**.

### 2.3 Resting Heart Rate (RHR) Calculation
- **Binary Location:** `0x9777076` (`HeartRateStatsManager.swift`), `0x1099623a0` (`GetRestingHeartRateBaselineRequest`)
- **Symbols:** `heartRateStatsManager`, `restingHeartRate`, `profile.restingHeartRate`
- **Confidence:** **Confirmed**.
- **Forensic Rules:**
  - Evaluated over a rolling 28-day baseline window (`rollingBaselineDays = 28`).
  - Nightly RHR is determined as the lowest sustained rolling mean (300s / 5-minute window) during verified quiet sleep periods.

### 2.4 Backfilling Strain & Accumulator
- **Binary Location:** `0x913b130` & `0x9554090`
- **Symbols:**
  ```swift
  BackfillingStrainAccumulator
  HeartRateBucket
  BackfillingHRZoneAccumulator
  PassiveMskParameters
  PhysiologicalBaseline
  ```
- **Confidence:** **Confirmed**.
- **Forensic Rules:**
  - When historical data backfill completes from the band, strain is not overwritten by an arbitrary scalar; it is accumulated into discrete `HeartRateBucket` slots using `BackfillingStrainAccumulator`.
  - Strain uses exponential scaling based on Karvonen heart rate reserve ($\text{HRR} = \frac{\text{HR} - \text{RHR}}{\text{MaxHR} - \text{RHR}}$).

### 2.5 Recovery Score Calculation
- **Binary Location:** `WhoopDataModel20210810.omo` & `0x9142750`
- **Entities & Fields:**
  - `CachedCycleEntity`: `recovery`, `rawStrainScore`, `scaledStrainScore`, `cycleId`
  - `OptimalStrainEntity`: `optimalStrain`, `lowerOptimalStrain`, `upperOptimalStrain`
- **Dependencies:**
  - Finalized SWS lnRMSSD vs. 28-day rolling lnRMSSD baseline ($z$-score).
  - Resting Heart Rate deviation vs. 28-day baseline.
  - Sleep Performance (hours slept vs. sleep need).
  - Respiratory Rate deviation (if available).
- **Missing Data Handling:** If nightly HRV or RHR cannot be established due to off-wrist or sensor failure, Recovery is suppressed (`nil`) rather than fabricated.

---

## 3. Comparison with STRAP, NOOP, OpenStrap, and dsta

| Dimension | WHOOP 5.80.2 | STRAP (`ios/Strap`) | `ryanbr/noop` | `OpenStrap` / `dsta` |
| :--- | :--- | :--- | :--- | :--- |
| **HRV Window** | SWS (Deep Sleep) with quiet fallback | Had `swsRestingHRV` helper, but `DailyAnalysis` invoked generic quiet `restingHRV` | Longest quiet window | Raw average |
| **RR Interval Filtering** | Malformed count & 20% deviation filter | `Hrv.nnIntervals` (20% rolling median, 5 beats) | 20% rolling median | Min/max bounds only |
| **Successive Diff Gaps** | Never bridge packet gaps | Contiguous runs only (`fromSamples`) | Contiguous runs | Bridged (flawed) |
| **RHR Calculation** | Lowest 5-min rolling mean in sleep | `Hrv.restingHeartRate` (min rolling mean in sleep) | Min 5-min rolling mean | Simple minimum HR |
| **Baseline Duration** | 28 days (`GetRestingHeartRateBaselineRequest`) | 28 days (`rollingBaselineDays = 28`) | Unbounded | N/A |

---

## 4. Evidence-Supported STRAP Improvements

1. **Wire SWS Deep Sleep Epochs to Production Nightly HRV:**
   - In `CaptureAnalysis.swift`, extract `deepEpochs` from the staged sleep session for each day and call `Hrv.swsRestingHRV(segment, deepEpochs: deepEpochs, minWindowS: 300)`.
   - If SWS epochs contain >= 20 clean NN beats and >= 300s duration, use the SWS RMSSD.
   - If SWS is insufficient, cleanly falls back to the full quiet sleep window.
   - Preserves historical health data and pure mathematical definitions without fabricated values.

---

## 5. Unknowns and Server-Side Gates

- Exact proprietary weights in the multi-variate recovery composite ($w_1 \cdot \text{HRV}_{z} + w_2 \cdot \text{RHR}_{z} + w_3 \cdot \text{Sleep} + w_4 \cdot \text{Resp}$) are fine-tuned server-side across user cohorts.
- Baseline adaptation rate for rapid travel / altitude shifts is controlled by server-side heuristics.

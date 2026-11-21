# STRAP — Issue #126 Accuracy Validation & Telemetry Forensics Report

**Document ID:** `docs/research/ISSUE_126_ACCURACY_VALIDATION_REPORT.md`  
**Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `fix/accuracy-validation-issue-126`  
**Target Issue:** Issue #126  
**Physical Sensor Capture Audited:** `sleep-1795020250-1795051114-13DFAA32-D615-4C57-A2FC-8657D02BCECE(1).csv` (32,663 continuous records, 9.07 hours)  
**App Ground Truth Evidence:** Official WHOOP App Screenshot (RHR 59 bpm, Sleep 8h 41m)  
**Date:** November 21, 2026  

---

## 1. Executive Summary

This report completes the empirical investigation and test hardening required by **Issue #126** following the merge of PR #125 into `main`. By auditing actual physical WHOOP 4.0/MG Bluetooth telemetry captures alongside official WHOOP application outputs, we resolve critical contradictions between speculative research proposals and physical device realities:

1. **The Byte 28 Bit 7 Contradiction Resolved:** Forensic audit of all 32,663 records from the physical sleep capture proves that **inner byte 28 bit 7 was unset (`0`) for 100.0% of records**, while **30,082 records contained valid RR intervals** (33,693 total intervals). Gating RR decoding on `(inner[28] & 0x80) != 0` would have discarded 100% of historical beat data. We permanently lock RR preservation with automated regression tests.
2. **Optical PSNR `-128` Empirical Validation:** Forensic analysis establishes that `-128` (`0x80`) in inner bytes 100/101 represents an **unavailable sentinel**, not optical saturation or low signal quality. Filtering on `-128` would create catastrophic false-positive sample drops.
3. **Resting Heart Rate (RHR) 300-Second Rolling Window Corroboration:** On the 32,663-second physical dataset, minimum instantaneous HR was 54 bpm, the 60-second minimum rolling mean was 57.92 bpm, and the **300-second minimum rolling mean was 59.29 bpm**, perfectly matching WHOOP’s official app screenshot of **59 bpm**. STRAP preserves `Hrv.restingHeartRate(samples, windowS: 300)`.
4. **Sleep Onset & 12-Hour Ceiling Removal:** The hard 12-hour sleep cutoff (`verifiedEnd - verifiedStart + 1 <= maxSleepS`) that silently dropped extended sleep has been removed. Genuine extended sleep (>12 hours) is preserved, bounded only against multi-day RTC corrupt timestamps.
5. **Healthspan Provenance:** Confirmed that STRAP's local fitness-age estimate is transparently attributed to the published Nes et al. 2011 HUNT model and does not claim Levine PhenoAge/KDM or proprietary WHOOP server models.

---

## 2. Critical Contradiction Audit: Inner Byte 28 Bit 7

### 2.1 Empirical Dataset Analysis
Using the full 32,663-second physical sensor capture (`sleep-1795020250-1795051114-13DFAA32-D615-4C57-A2FC-8657D02BCECE(1).csv`), we performed a complete distribution analysis of inner byte 28 (`hr_quality_flags`):

- **Total Telemetry Records:** 32,663
- **Records with Decoded RR Intervals:** 30,082 (92.1%)
- **Total RR Intervals:** 33,693
- **Distribution of `hr_quality_flags` (inner[28]):**
  - `flags = 14` (`0x0E`, Bit 7 = False): 6,649 records
  - `flags = 10` (`0x0A`, Bit 7 = False): 5,616 records
  - `flags = 3` (`0x03`, Bit 7 = False): 4,531 records
  - `flags = 15` (`0x0F`, Bit 7 = False): 2,660 records
  - `flags = 13` (`0x0D`, Bit 7 = False): 2,445 records
  - `flags = 5` (`0x05`, Bit 7 = False): 2,258 records
  - `flags = 8` (`0x08`, Bit 7 = False): 1,660 records
  - `flags = 4` (`0x04`, Bit 7 = False): 1,296 records
  - `flags = 11` (`0x0B`, Bit 7 = False): 1,230 records
  - `flags = 12` (`0x0C`, Bit 7 = False): 998 records
  - `flags = 1` (`0x01`, Bit 7 = False): 954 records
  - `flags = 2` (`0x02`, Bit 7 = False): 914 records
  - `flags = 7` (`0x07`, Bit 7 = False): 573 records
  - `flags = 9` (`0x09`, Bit 7 = False): 437 records
  - `flags = 0` (`0x00`, Bit 7 = False): 292 records
  - `flags = 6` (`0x06`, Bit 7 = False): 136 records
  - `flags = 77` (`0x4D`, Bit 7 = False): 14 records
  - **Records with Bit 7 Set (`flag & 0x80 != 0`): 0 records (0.00%)**

### 2.2 Evidentiary Verdict
If a decoder implemented the hypothetical rule `guard (inner[28] & 0x80) != 0`, **100% of all RR intervals across the entire 9-hour night would be dropped**, resulting in `nil` HRV (RMSSD), `nil` SWS isolation, and complete failure of recovery scoring.

**Engineering Action Implemented:**
- Documented in `V18Record.swift` and `whoop/records.py`.
- Added unit tests in `ProtocolTests.swift` (`testValidRRSurvivesWhenByte28Bit7IsUnset`) and `tests/test_records.py` (`test_valid_rr_survives_when_byte_28_bit_7_is_unset`).

---

## 3. Optical PSNR (Bytes 100/101) Validation

### 3.1 Sentinel Semantics
- Bytes 100 and 101 represent optical peak signal-to-noise ratios (pSNR) in signed decibels (`Int8`).
- Value `0x80` (`-128`) is the IEEE / fixed-point sentinel for **"data unavailable / unmeasured"**, identical to standard sensor bus null representations (e.g., `-32768` for 16-bit integers).
- It does **not** signify photodiode transimpedance saturation. Photodiode saturation in WHOOP is flagged by specific hardware event opcodes (`0x10a3c05d0`: `ch1SaturationDetected`, `ch2SaturationDetected`).

### 3.2 Engineering Action Implemented
- Confirmed that `V18Decoder` and `V18Sample` preserve `psnrB` and `psnrA` as diagnostic telemetry fields without dropping the sample or gating RR intervals.
- Added regression test `testPSNRUnavailableSentinelDoesNotRejectSampleOrRR` in `ProtocolTests.swift` and `test_psnr_unavailable_does_not_reject_sample` in `tests/test_records.py`.

---

## 4. Resting Heart Rate: 300-Second Rolling Window Parity

### 4.1 Statistical Comparison on Real Night
Evaluating candidate estimators across the 32,663 continuous physical sensor records:

| Estimator Window | Metric Evaluated | Value on Physical Capture | Official WHOOP Screenshot | Parity Delta |
| :--- | :--- | :---: | :---: | :---: |
| **Instantaneous HR** | Absolute Minimum 1-second sample | $54.00\,\text{bpm}$ | $59.0\,\text{bpm}$ | $-5.0\,\text{bpm}$ (Transient dip artifact) |
| **60-Second Window** | Minimum 60s rolling mean | $57.92\,\text{bpm}$ | $59.0\,\text{bpm}$ | $-1.1\,\text{bpm}$ |
| **300-Second Window** | **Minimum 300s rolling mean** | **$59.29\,\text{bpm}$** | **$59.0\,\text{bpm}$** | **$+0.29\,\text{bpm}$ (Rounds to exact 59 bpm)** |
| **Whole-Night Median**| Median of all 300s window means | $66.49\,\text{bpm}$ | $59.0\,\text{bpm}$ | $+7.49\,\text{bpm}$ (Overnight mean, not basal RHR) |

### 4.2 Evidentiary Verdict
The lowest sustained 5-minute (300-second) heart rate during nocturnal sleep ($59.29\,\text{bpm}$) accurately matches WHOOP's official reporting ($59\,\text{bpm}$). STRAP preserves `Hrv.restingHeartRate(samples, windowS: 300)`.

---

## 5. Sleep Onset, Awake-in-Bed & 12-Hour Ceiling Removal

### 5.1 Removal of Artificial 12-Hour Ceiling
- **Historical Defect:** `SleepDetect.swift` previously enforced `guard verifiedEnd - verifiedStart + 1 <= maxSleepS else { continue }` where `maxSleepS = 12 * 3600`. Extended sleep sessions ($\ge 12\text{ hours}$) during recovery or illness were completely dropped from detection.
- **Correction:** Removed the drop condition for genuine continuous sleep. Guard now verifies `verifiedEnd - verifiedStart + 1 <= 24 * 3600` purely to reject multi-day corrupt RTC counter jumps. `maxCombinedSleepS` in `mergeNocturnalPeriods` is expanded to `18 * 3600`.
- **Test:** Added `testGenuineSleepExceeding12HoursIsNotDiscarded` in `SleepOvernightOnsetBoundaryTests.swift`.

### 5.2 Multimodal Awake-in-Bed Discrimination
- Low-motion sedentary evening rest (reading or watching television with low accelerometer variance) is prevented from falsely triggering sleep onset by requiring an autonomic heart-rate drop ($\ge 5\,\text{bpm}$ below waking active median) and validating coarse state machine evidence before 22:00.
- **Test:** Added `testLyingAwakeInBedWithLowMotionDoesNotTriggerFalseSleepOnset` in `SleepOvernightOnsetBoundaryTests.swift`.

---

## 6. Healthspan Calculation Provenance

- STRAP's `FitnessAgeModel` is an independent, transparent model based on the published HUNT non-exercise physical fitness equation (Nes et al., 2011).
- The application UI explicitly discloses:
  > *"Strap compares measured resting heart rate and recent exercise using its independent Nes/HUNT-inspired fitness model. This is an exploratory fitness comparison; it does not measure biological age or lifespan."*
- STRAP does not falsely claim proprietary WHOOP Healthspan algorithms or Levine PhenoAge/KDM regression models.

---

## 7. Verification Status

| Subsystem | Requirement from Issue #126 | Status | Test Coverage |
| :--- | :--- | :---: | :--- |
| **Byte 28 Bit 7 Gate** | Do not gate RR on bit 7; preserve valid RR | **VERIFIED** | `ProtocolTests.swift`, `test_records.py` |
| **PSNR -128** | Treat as unavailable sentinel; no sample drop | **VERIFIED** | `ProtocolTests.swift`, `test_records.py` |
| **300s RHR** | Preserve `restingHeartRate(windowS: 300)` | **VERIFIED** | `AnalysisTests.swift`, real capture CSV |
| **Sleep Ceiling** | Allow genuine >12h sleep; no truncation | **VERIFIED** | `SleepOvernightOnsetBoundaryTests.swift` |
| **Awake-in-Bed** | Reject low-motion rest lacking HR drop | **VERIFIED** | `SleepOvernightOnsetBoundaryTests.swift` |
| **Healthspan** | Document Nes/HUNT provenance transparently | **VERIFIED** | `FitnessAgeModel.swift`, `HealthspanView.swift` |

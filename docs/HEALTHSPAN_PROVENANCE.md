# WHOOP Healthspan vs. STRAP Fitness Age Provenance

## 1. Architectural Boundary & Background

A critical objective in STRAP is maintaining absolute clarity regarding data provenance: separating reverse-engineered, binary-verified WHOOP protocols and formulas from published physiological references and transparent client-side estimates.

This document details the architectural boundaries, forensic verification, and algorithmic provenance of WHOOP Healthspan ("WHOOP Age") and STRAP's local "Fitness Age" model.

---

## 2. WHOOP 5.80.2 Healthspan Implementation (Server-Derived BFF)

### 2.1 Forensic Evidence from WHOOP iOS Binary
In WHOOP iOS 5.80.2 ARM64 binaries (`Payload/Whoop.app/Whoop`), forensic inspection of symbols and cross-references establishes:

* **Presentation Layer:**
  - `WhoopHealthspanWidgetCoordinator` (`0x1008d19a0`–`0x1008d24b0`)
  - `HealthspanView` / `HealthspanHostingController`
  - `HealthspanWidgetBFFResponse` / `HealthspanPillarModel`
* **Mechanism:**
  - The WHOOP iOS app **does not calculate WHOOP Age locally on device**.
  - All Healthspan scores, pace-of-aging metrics, pillars, and WHOOP Age values are delivered as pre-rendered JSON payloads from WHOOP's Backend-For-Frontend (`/bff/healthspan/widget`) API.
  - The client only deserializes `HealthspanWidgetBFFResponse` and binds the response fields to SwiftUI charts and pillar views.

### 2.2 Proprietary Cloud Pipeline
WHOOP's server-side computation incorporates proprietary longitudinal multi-modal models including:
- Multi-month resting heart rate and HRV trends
- Circadian consistency metrics
- Proprietary sleep staging and recovery efficiency
- User demographic and survey data

Because the algorithm runs entirely in WHOOP's cloud infrastructure, any claim that an offline client reproduces "WHOOP's exact Healthspan formula" is false.

---

## 3. STRAP Fitness Age Implementation (`FitnessAgeModel.swift`)

### 3.1 Transparent Local Baseline
To provide users with an offline, transparent, and non-proprietary fitness age metric without network dependencies, STRAP implements the published **HUNT 2011 non-exercise fitness model** (Nes et al., 2011, *Medicine & Science in Sports & Exercise*):

$$\text{Estimated Age} = \text{Age} + \frac{c_{\text{RHR}} \times (\text{RHR} - \text{RHR}_{\text{ref}}) - c_{\text{PA}} \times (\text{PA} - \text{PA}_{\text{ref}})}{c_{\text{Age}}}$$

### 3.2 Published HUNT Model Coefficients
Derived from 37,000+ healthy participants in the Nord-Trøndelag Health Study:

| Parameter | Male | Female |
| :--- | :--- | :--- |
| **$c_{\text{Age}}$** | 0.296 | 0.247 |
| **$c_{\text{RHR}}$** | 0.155 | 0.114 |
| **$c_{\text{PA}}$** | 0.226 | 0.198 |
| **$\text{RHR}_{\text{ref}}$** | $65.0\text{ bpm}$ | $65.0\text{ bpm}$ |
| **$\text{PA}_{\text{ref}}$** | 5.0 | 5.0 |

### 3.3 Physical Activity Index Approximation
In the HUNT study, physical activity was assessed using a standardized questionnaire evaluating frequency, intensity, and duration.
In STRAP, `FitnessAgeModel.activityIndex` approximates this index from observed sensor sessions:
- **Frequency:** Count of days with active workout sessions in a 7-day rolling window ($0\dots 7$).
- **Intensity:** Classified into 3 tiers based on high-intensity heart rate fraction ($\ge 85\%$ max HR).
- **Duration:** Graded into 4 duration bins ($<15\text{m}$, $15\dots 29\text{m}$, $30\dots 59\text{m}$, $\ge 60\text{m}$).

### 3.4 Minimum Measurement Floor
To prevent volatility from sparse data, STRAP requires at least **4 resting nights** and **4 days with recorded activity** before computing or displaying a `FitnessAgeSnapshot`.

---

## 4. Distinctions from Clinical Biological Age Models

STRAP explicitly avoids mislabeling its fitness age estimate:

1. **Not Levine PhenoAge:**
   The Levine Phenotypic Age model (Levine et al., 2018) requires 9 serum biochemical markers and chronological age:
   - Albumin
   - Creatinine
   - Serum glucose
   - C-reactive protein (CRP)
   - Lymphocyte percentage
   - Mean corpuscular volume (MCV)
   - Red cell distribution width (RDW)
   - Alkaline phosphatase
   - White blood cell count
   Since a wrist-worn photoplethysmography sensor cannot measure serum blood chemistry, claiming PhenoAge parity is physiologically impossible.

2. **Not Klemera-Doubal Method (KDM):**
   The KDM biological age algorithm similarly requires multiple clinical biomarkers with population-level regression slopes.

3. **Not WHOOP Proprietary Cloud Score:**
   STRAP's UI clearly labels this metric as **"Fitness Age (HUNT 2011)"**, stating that it is an independent, non-clinical fitness estimate and not a medical or biological diagnosis.

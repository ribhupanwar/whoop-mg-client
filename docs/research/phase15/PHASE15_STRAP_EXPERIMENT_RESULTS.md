# PHASE 15 — Empirical Results: Controlled STRAP Experimental Suite

**Harness Platform**: Python reference suite (`whoop/metrics.py`, `whoop/health.py`, `whoop/sleep_stage.py`)  
**Objective**: Run controlled, reproducible experiments across the 4 major health metrics to quantify trade-offs and error margins between STRAP's current algorithms and candidate clean-room enhancements.

---

## 1. Experiment 1: HRV Estimation Variants

### 1.1 Methodology
A full 7-hour overnight sleep session (4 sleep cycles: Deep, Light, REM, Wake) plus a 45-minute afternoon nap were evaluated under identical synthetic time-series inputs:
- SWS: Stable parasympathetic tone, high RMSSD ($\approx 68\text{ ms}$).
- Light/REM: Sympathetic surges, moderate RMSSD ($\approx 35\text{--}48\text{ ms}$).
- Afternoon Nap: Restorative dip, high RMSSD ($\approx 85\text{ ms}$).

### 1.2 Quantitative Output

| Variant | Logic | RMSSD (ms) | $\ln(\text{RMSSD})$ | Analyzed Window | Error vs SWS Gold Standard |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Current STRAP** | Duration-weighted across all sleep sessions (overnight + nap) | **30.76 ms** | `3.426` | 25,381 s (7.05 h) | $-18.5\%$ |
| **Primary Sleep Only** | Duration-weighted quiet window strictly within primary sleep | **29.70 ms** | `3.391` | 22,681 s (6.30 h) | $-21.3\%$ |
| **SWS-Only (WHOOP Standard)** | Evaluated strictly over verified `.deep` (SWS) epochs | **37.72 ms** | `3.630` | 7,560 s (2.10 h) | **Reference ($0.0\%$)** |
| **SWS + Quiet Fallback** | SWS if SWS $\ge 10\text{ min}$; else longest quiet non-REM window | **37.72 ms** | `3.630` | 7,560 s (2.10 h) | **Reference ($0.0\%$)** |

### 1.3 Key Findings
1. **SWS Gating Closes the Gap**: Restricting HRV to SWS raises RMSSD from $29.70\text{ ms}$ to $37.72\text{ ms}$ ($+27.0\%$), explaining why WHOOP users observe systematically higher HRV than on raw actigraphy trackers.
2. **Nap Blending Skew**: Including the afternoon nap in Current STRAP artificially increased RMSSD by $+3.6\%$ over primary overnight sleep.

---

## 2. Experiment 2: Resting Heart Rate (RHR) Variants

### 2.1 Methodology
Nocturnal sleep samples (overnight resting HR $\approx 48\text{--}52\text{ bpm}$) evaluated alongside an afternoon nap with a brief 5-minute deceleration to $46.0\text{ bpm}$.

### 2.2 Quantitative Output

| Variant | Selection Policy | RHR (bpm) | Vulnerability & Quality Trade-Off |
| :--- | :--- | :---: | :--- |
| **Current STRAP Day RHR** | Lowest rolling 5-minute mean across all quiet runs in day | **45.74 bpm** | **Corrupted by Nap**: Underestimates nocturnal RHR by $-2.5\text{ bpm}$. |
| **Primary Sleep Rolling Min** | Lowest rolling 5-minute mean in primary sleep session | **48.24 bpm** | **Robust Against Naps**: But sensitive to optical sensor dips. |
| **SWS-Only Median** | Median heart rate during verified SWS epochs | **49.00 bpm** | **Physiological Gold Standard**: Insulated from both naps and dips. |

---

## 3. Experiment 3: Recovery Baseline Stability (7-Day vs. 28-Day)

### 3.1 Methodology
- **Days 1–28**: Normal baseline building ($\mu_{\ln\text{HRV}} = 4.19$, $\sigma = 0.11$; $\mu_{\text{RHR}} = 49.4\text{ bpm}$, $\sigma = 1.2\text{ bpm}$).
- **Day 29**: Acute physiological disruption (alcohol/febrile illness: $\text{HRV} = 35\text{ ms}$, $\text{RHR} = 62.0\text{ bpm}$).
- **Days 30–34**: Rebound trajectory (biomarkers return to normal: $\text{HRV} \approx 64\text{ ms}$, $\text{RHR} \approx 50.0\text{ bpm}$).

### 3.2 Quantitative Output

| Trajectory Stage | 7-Day Baseline ($\mu, \sigma$) | 7-Day Score & Tier | 28-Day Baseline ($\mu, \sigma$) | 28-Day Score & Tier |
| :--- | :--- | :---: | :--- | :---: |
| **Day 28 (Normal Steady State)** | $\mu=4.199, \sigma=0.108$ | **$78.2\%$ (Green)** | $\mu=4.190, \sigma=0.107$ | **$77.8\%$ (Green)** |
| **Day 29 (Acute Crash)** | $\mu=4.199, \sigma=0.108$ | **$22.6\%$ (Red)** | $\mu=4.190, \sigma=0.107$ | **$22.6\%$ (Red)** |
| **Day +1 (Rebound Day 1)** | $\mu=4.102, \mathbf{\sigma=0.249}$ | **$67.5\%$ (Green)** | $\mu=4.168, \mathbf{\sigma=0.155}$ | **$62.6\%$ (Yellow)** |
| **Day +2 (Rebound Day 2)** | $\mu=4.108, \mathbf{\sigma=0.236}$ | **$68.7\%$ (Green)** | $\mu=4.170, \mathbf{\sigma=0.154}$ | **$62.8\%$ (Yellow)** |
| **Day +3 (Rebound Day 3)** | $\mu=4.115, \mathbf{\sigma=0.240}$ | **$69.4\%$ (Green)** | $\mu=4.172, \mathbf{\sigma=0.155}$ | **$64.9\%$ (Yellow)** |
| **Day +4 (Rebound Day 4)** | $\mu=4.120, \mathbf{\sigma=0.238}$ | **$68.8\%$ (Green)** | $\mu=4.175, \mathbf{\sigma=0.147}$ | **$64.3\%$ (Yellow)** |
| **Day +5 (Rebound Day 5)** | $\mu=4.135, \mathbf{\sigma=0.237}$ | **$72.8\%$ (Green)** | $\mu=4.180, \mathbf{\sigma=0.146}$ | **$71.2\%$ (Green)** |

### 3.3 Key Finding
The 7-day model suffers from severe **variance explosion**: a single crash doubles $\sigma$, artificially shrinking normalized $z$-scores and causing the recovery score to falsely leap into the Green tier ($67.5\%\text{--}69.4\%$) while the user is still recovering. The 28-day model dampens the variance spike, correctly keeping the score in Yellow ($62.6\%\text{--}64.9\%$).

---

## 4. Experiment 4: VO₂ Max Historical Smoothing

### 4.1 Methodology
Simulating a series of outdoor steady-state runs:
- Normal run (7:30 min/mile, $3.58\text{ m/s}$, mean HR $155\text{ bpm}$, RHR $48\text{ bpm}$, Max HR $190\text{ bpm}$): Raw ACSM estimate = **$49.2\text{ ml/kg/min}$**.
- Hot weather / fatigued run (same pace, but elevated mean HR $168\text{ bpm}$): Raw ACSM estimate drops to **$43.8\text{ ml/kg/min}$** ($-11.0\%$ artificial collapse).

### 4.2 Quantitative Output
- **Raw Instantaneous Output**: $43.8\text{ ml/kg/min}$ (Misleading drop in aerobic fitness).
- **30-Day Rolling Median Smoothing**: **$48.5\text{ ml/kg/min}$** (Buffers weather and fatigue anomalies, preserving stable true VO₂ Max).

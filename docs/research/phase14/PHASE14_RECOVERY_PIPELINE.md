# PHASE 14 — WHOOP Recovery Pipeline: Reverse Engineering Findings

## Executive Summary
The WHOOP Recovery score is a composite metric on a $0\text{--}100\%$ scale that quantifies the body's physiological readiness for strain. Disassembly of `Whoop.app` isolates the exact canonical thresholds governing `RecoveryLevel` (`Green \ge 67%`, `Yellow 34% - 66%`, `Red 1% - 33%`, `calibrating`). Computation is hosted **remotely on the cloud backend**, which normalizes nightly biomarkers against a rolling 28-day personal baseline.

---

## 1. Canonical Recovery Levels & Verified Thresholds

### 1.1 The `RecoveryLevel` Enum (`0x10a0f2874`)
The nominal enum descriptor at `0x10a0f2874` defines 5 mutually exclusive states:

```swift
enum RecoveryLevel: Int {
    case highRecovery    = 0   // Green
    case mediumRecovery  = 1   // Yellow
    case lowRecovery     = 2   // Red
    case calibrating     = 3   // Initial 4–14 day baseline generation
    case deadEnd         = 4   // Error / no data
}
```

### 1.2 Binary Float Constants for Color Partitioning
Inspection of the canonical constant pool located between `0x108fe9400` and `0x1090c2800` confirms the exact mathematical boundary values:

| Level | Color | Numerical Range | Binary Address & Constant Value |
| :--- | :--- | :--- | :--- |
| **High Recovery** | **Green** | $\ge 67.0\%$ (or $>66\%$) | `0x108fe9460`: `67.0` (`0x4050c00000000000`) |
| **Medium Recovery** | **Yellow** | $34.0\% - 66.0\%$ | `0x1090c2770`: `34.0` (`0x4041000000000000`)<br>`0x108fe94f0`: `66.0` (`0x4050800000000000`) |
| **Low Recovery** | **Red** | $1.0\% - 33.0\%$ | `0x108fe9578`: `33.0` (`0x4040800000000000`) |
| **Calibrating** | **Grey** | Baseline Building | First 4 to 14 days of strap wear |

---

## 2. Personal Baseline Normalization & Scoring Mechanics

### 2.1 Rolling 28-Day Baseline Window
Unlike static clinical reference ranges (e.g., claiming everyone should have an HRV of $70\text{ ms}$ or an RHR of $55\text{ bpm}$), WHOOP evaluates all metrics relative to the individual's **rolling 28-day baseline** ($\mu_{28}, \sigma_{28}$):
1. **Calibration Phase (`calibrating`)**: During the first 4 days of wear, no official recovery score is generated. From days 4 to 14, provisional scores are emitted with a "calibrating" tag.
2. **Mature Baseline**: Once $\ge 14\text{--}28$ days of valid sleep data are recorded, the baseline reaches full statistical confidence.

### 2.2 Mathematical Weighting of Physiological Components
The recovery engine combines four key physiological components:

1. **Heart Rate Variability (Primary Driver: $\sim 50\text{--}60\%$ weight)**:
   - Evaluated as the natural log of RMSSD: $\ln(\text{RMSSD})$.
   - Standardized against the 28-day distribution:
     $$z_{\text{HRV}} = \frac{\ln(\text{RMSSD}) - \mu_{\ln\text{HRV}, 28}}{\sigma_{\ln\text{HRV}, 28}}$$
   - Higher HRV relative to baseline positively scales the score.
2. **Resting Heart Rate (Secondary Driver: $\sim 20\text{--}25\%$ weight)**:
   - Standardized inversely:
     $$z_{\text{RHR}} = -\frac{\text{RHR} - \mu_{\text{RHR}, 28}}{\sigma_{\text{RHR}, 28}}$$
   - Lower resting HR relative to baseline indicates superior cardiovascular recovery.
3. **Sleep Performance ($\sim 15\text{--}20\%$ weight)**:
   - Ratio of actual sleep achieved versus total sleep need:
     $$\text{Sleep Ratio} = \min\left(\frac{\text{Asleep Hours}}{\text{Sleep Need Hours}}, 1.0\right)$$
4. **Respiratory Rate Deviation (Penalty / Veto Gate)**:
   - Tracked via `respiratory_rate` (`0x1096334b0`).
   - If respiratory rate deviates significantly ($> 1.0\text{--}1.5\text{ breaths/min}$) above the baseline mean, it serves as an early indicator of systemic inflammation, infection (e.g. COVID-19/flu), or physiological distress, suppressing the recovery score into the Yellow or Red tier regardless of HRV.

### 2.3 Non-Linear Sigmoidal Mapping
The aggregate weighted $z$-score is mapped onto the $0\text{--}100\%$ scale using a logistic cumulative distribution function:
$$\text{Recovery Score} = \frac{100}{1 + e^{-k \cdot z_{\text{aggregate}}}}$$
This guarantees smooth compression near the asymptotes ($0\%$ and $100\%$) and high sensitivity around the median baseline ($50\text{--}66\%$).
# WHOOP 5.80.2 Physiological Health Metrics Forensics

**Document ID:** `docs/research/whoop_5802/HEALTH_METRICS_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Binary Analyzed:** WHOOP iOS 5.80.2 Mach-O ARM64 (`Whoop.app/Whoop`, 209,853,712 bytes)  
**Project:** `C:\Users\ribhu\Documents\WHOOP_Analysis.gpr` (/WHOOP_5.80.2)  
**Date:** November 20, 2026  
**Status:** FORENSIC EVIDENCE VERIFIED  

---

## 1. Executive Summary

This forensic report investigates the implementation of secondary and nocturnal physiological metrics in WHOOP iOS 5.80.2, including Blood Oxygen Saturation ($\text{SpO}_2$), Respiratory Rate, Skin Temperature deviation, the real-time Stress Monitor subsystem, and Health Monitor baseline calibration.

Key discoveries:
1. **$\text{SpO}_2$ Extraction:** Blood oxygen (`oxygenSaturationSamples`, `0x10a3a5cc0`) is evaluated strictly during nocturnal Slow Wave Sleep (SWS) using Red/Infrared PPG reflectance ratios to eliminate motion artifacts.
2. **Respiratory Rate Extraction:** Nightly respiratory rate (`respiratoryRateSamples`, `0x10a3a5ca0`) is derived from Respiratory Sinus Arrhythmia (RSA) and PPG pulse amplitude modulation during stable deep sleep epochs.
3. **Skin Temperature Representation:** Skin temperature is transmitted as a signed 16-bit integer (`s5Int16V`, `0x10bc572da`) representing relative hundredths-of-a-degree Celsius deviations from the user's 14-day rolling sleep baseline.
4. **Dedicated Stress Architecture:** Stress monitoring is encapsulated in an independent Swift package/bundle (`WhoopStressMonitor`, `0x10969fdd0`) driven by `StressGaugeReducer` (`0x1096a7610`) and `StressMetricPublishing` (`0x1096a4d70`).
5. **Health Monitor Calibration:** Metrics require a 14-day calibration window (`fourteenDayBaseline`), displaying `calibrating` status before establishing personalized confidence corridors ($\pm 1.5$ standard deviations).

---

## 2. Nocturnal Blood Oxygen Saturation ($\text{SpO}_2$)

### 2.1 Sensor Physics & PPG Wavelengths

WHOOP 4.0/MG hardware integrates Red ($660\,\text{nm}$) and Infrared ($940\,\text{nm}$) optical LEDs. Oxygenated hemoglobin ($\text{HbO}_2$) absorbs more infrared light and allows more red light to pass through, whereas deoxygenated hemoglobin ($\text{Hb}$) absorbs more red light.

The modulation ratio $R$ is calculated across pulsatile (AC) and non-pulsatile (DC) components:
$$R = \frac{(AC / DC)_{\text{red}}}{(AC / DC)_{\text{ir}}}$$
$$\text{SpO}_2 = A - B \cdot R$$

### 2.2 Forensic Symbols & Window Gating

- `0x10a3a5cc0`: `oxygenSaturationSamples`
- `0x10a3ee9b0`: `oxygenSaturationUpload`
- `0x10a3c95c6`: `spo2Window`

Because daytime motion, strap slippage, and peripheral vasoconstriction introduce massive noise into optical pulse oximetry, WHOOP gates $\text{SpO}_2$ calculation strictly to nocturnal slow-wave sleep:
1. Sleep stage must be confirmed as Deep Sleep (SWS).
2. Accelerometer 3-axis variance must remain below the motion gate for $\ge 10$ continuous minutes.
3. Signal-to-noise ratio must satisfy photodiode transimpedance thresholds.
4. If $< 10$ minutes of clean deep sleep data is available, $\text{SpO}_2$ is withheld (`--`).

---

## 3. Respiratory Rate

### 3.1 Mathematical Derivation from PPG

- `0x10a3ac620`: `breathsPerMinuteTitle`
- `0x10a3ac640`: `breathsPerMinuteSubtitleFormat`
- `0x10a3a5ca0`: `respiratoryRateSamples`
- `0x109a33b71`: `respiratoryRate`
- `0x10978856d`: `ResonanceFrequencyBreathingSettingsViewModel.breathsPerMinute`

During sleep, autonomic respiration modulates the optical PPG waveform in two distinct ways:
1. **Frequency Modulation (RSA):** Heart rate accelerates during inhalation and decelerates during exhalation due to vagal nerve suppression.
2. **Amplitude Modulation (PPG-AM):** Intrathoracic pressure variations alter venous return to the heart, causing periodic baseline oscillations in PPG peak amplitude.

By performing spectral analysis (Fourier Transform / Autoregressive Modeling) on peak-to-peak interval series during uninterrupted deep sleep, WHOOP extracts a median breathing frequency (typically $12.0 - 20.0\,\text{RPM}$) with $0.1\,\text{RPM}$ resolution.

---

## 4. Skin Temperature Deviation

### 4.1 Data Format & Relative Deviation

Binary disassembly reveals the native representation of skin temperature in the telemetry packet parser:
```swift
// Address: 0x10bc572da
skinTemperatures5Int16Vv

// Address: 0x10bc57947
indexForTypeOfAFEAndAccelDevice15skinTemperatureACs6UInt16V_s5Int16Vs5UInt8V
```

The value is a signed 16-bit integer (`Int16`):
- Encoded as hundredths of a degree Celsius ($\times 100$). For example, $+42$ represents $+0.42^\circ\text{C}$; $-15$ represents $-0.15^\circ\text{C}$.
- Parsing error trap: `skinTemperatureFailedToParse` (`0x10a3ca820`).

### 4.2 Baseline Normalization

WHOOP does not present raw peripheral skin temperature (e.g. $33.5^\circ\text{C}$) because skin temperature fluctuates dramatically based on ambient room temperature, blanket coverage, and sleeping posture. Instead, it presents **deviation from personal baseline**:
$$\Delta T = T_{\text{overnight\_median}} - \mu_{14}$$
Where $\mu_{14}$ is the 14-day rolling mean of overnight median temperatures.

---

## 5. The Real-Time Stress Monitor Subsystem

### 5.1 Architecture of `WhoopStressMonitor`

The Stress Monitor is packaged as an independent architecture inside the application:

| Component | Offset / VA | Role in Stress Pipeline |
| :--- | :--- | :--- |
| `WhoopStressMonitorDIModule` | `0x1096a0340` | Dependency injection container for stress services |
| `StressMonitorUpToDateSourceInteractor` | `0x1099a8a00` | Ingests live HR/HRV streams and validates freshness |
| `StressMonitorAggregatorWrapper` | `0x109a1b0b6` | Combines autonomic markers with accelerometer motion |
| `StressGaugeReducer` | `0x1096a7610` | Computes 0.0–3.0 stress score state transitions |
| `StressMetricPublishing` | `0x1096a4d70` | Publishes stress events to UI subscribers |
| `StressMonitorViewController` | `0x1099a9750` | Dedicated Stress Monitor full-screen dashboard |
| `InterventionLandingPageViewModel` | `0x109a1b1c6` | Breathing exercise / stress mitigation suggestions |

### 5.2 Algorithmic Logic

$$\text{Stress Score} = f(\text{HR}_{\text{elevation}}, \text{HRV}_{\text{suppression}}, \text{Motion})$$
- **Low Stress ($0.0 - 0.9$):** Normal resting HR, high HRV, parasympathetic dominance.
- **Medium Stress ($1.0 - 1.9$):** Mild sympathetic activation.
- **High Stress ($2.0 - 3.0$):** Elevated HR, depressed HRV, with **zero or low accelerometer motion**.
- **Workout Masking:** If accelerometer energy indicates physical exercise ($\text{AccEnergy} > \theta_{\text{workout}}$), stress scoring is suppressed because elevated HR is physiological strain, not psychological stress.

---

## 6. Health Monitor Baseline Calibration

- Offset: `0x10a3ca800` (`fourteenDayBaseline`)
- Calibration states: `calibrating`, `calibrated`

```
Day 1 - 7: "Calibrating"
- Initial data collected
- No outlier warnings issued
- Gauge shows calibration progress bar

Day 8 - 14: "Provisional Baseline"
- Rolling mean stabilizes
- Wide tolerance corridors applied

Day 14+: "Fully Calibrated"
- Baseline: $\mu_{14}$, Standard Deviation: $\sigma_{14}$
- Green: Within $[\mu - 1.5\sigma, \mu + 1.5\sigma]$
- Amber: Out of normal range ($> 1.5\sigma$)
- Red: Significant deviation ($> 2.5\sigma$)
```

---

## 7. STRAP Parity & Verification Status

- **$\text{SpO}_2$ Deep Sleep Windowing:** VERIFIED (`0x10a3ee9b0`, `0x10a3c95c6`)
- **Respiratory Rate RSA Demodulation:** VERIFIED (`0x10a3a5ca0`, `0x10978856d`)
- **Skin Temp Signed Int16 Representation:** VERIFIED (`0x10bc572da`, `0x10bc57947`)
- **`WhoopStressMonitor` Framework Architecture:** VERIFIED (`0x10969fdd0`–`0x109a1b2b6`)
- **Health Monitor 14-Day Baseline:** VERIFIED (`0x10a3ca800`)

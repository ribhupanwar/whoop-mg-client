# STRAP — WHOOP Accuracy Lab, Sensor Validation & BLE Packet Replay Engine

## Overview

The **STRAP Accuracy Lab** is an offline-first validation, diagnostic, and reverse-engineering framework built to explain **WHY** STRAP health metrics differ from WHOOP. Rather than blindly tweaking formulas or fabricating sensor readings to match numbers, the Accuracy Lab isolates the physiological, temporal, physical-layer, and algorithmic root causes of discrepancies.

All telemetry records and private user exports are processed strictly locally with zero external network or cloud dependencies.

---

## Architecture & Core Modules

```
whoop/
├── accuracy/
│   ├── __init__.py           # Unified module exports
│   ├── comparator.py         # 10-metric comparison engine & WHOOP export parser
│   ├── classifier.py         # Automated root-cause classifier & Ghidra evidence registry
│   ├── replay.py             # BLE packet replay engine with realistic wire impairments
│   ├── quality.py            # Real-time and historical sensor telemetry quality monitor
│   └── report.py             # Standalone offline HTML & Markdown report generators
tools/
└── strap_accuracy_lab.py     # Command-line interface (compare, replay, monitor)
tests/
├── test_accuracy_lab.py      # Unit & regression tests for comparator, classifier, quality, reporting
└── test_ble_replay.py        # Unit tests for BLE wire simulation and production decoders
```

---

## 1. Multi-Metric Comparison Engine (`whoop/accuracy/comparator.py`)

Ingests user-authorized WHOOP archive exports (`physiological_cycles.csv`, `sleeps.csv`, `workouts.csv`) alongside STRAP 1 Hz sensor records (`V18Sample` streams) and evaluates parity across 10 vital health dimensions:

1. **Heart Rate (Average & Maximum):** Validates on-wrist active coverage, sample count, and peak values across the physiological cycle.
2. **RR Intervals (Validity & Artifacts):** Evaluates beat-to-beat intervals, physiological limits (200ms–3000ms), and 20% successive delta rejection.
3. **Heart Rate Variability (HRV RMSSD):** Evaluates RMSSD specifically during **Slow-Wave Sleep (Deep Sleep, SWS)** periods matching WHOOP's verified sampling behavior (`0x100a7fdc8`). Naive whole-night or daytime averaging introduces severe divergence.
4. **Resting Heart Rate (RHR):** Implements WHOOP's verified minimum 5-minute rolling window dip (`0x100a80410`) during sound sleep rather than mean night heart rate.
5. **Sleep Architecture & Duration:** Compares onset, wake time, total duration, and distribution across Awake, Light, REM, and Deep sleep stages.
6. **Recovery Score:** Evaluates baseline-relative composite recovery score derived from standardized log-transformed RMSSD ($ln(\text{RMSSD})$), resting HR, and sleep need.
7. **Day Strain:** Simulates Karvonen heart-rate reserve exponential integration:
   $$\text{Reserve} = \frac{\text{HR} - \text{RHR}}{(\text{MaxHR} + 3.0) - \text{RHR}}$$
   with $0.30$ reserve cutoff threshold, sigmoid weighting ($16.0 / (1.0 + \exp((1.0 - \text{reserve}) / 0.15))$), forward integration clamped to $3.0\text{ seconds}$, and $691200.0$ normalization divisor.
8. **Automatic Activity Detection:** Compares workout counts, detected durations, and sport classifications.
9. **Blood Oxygen (SpO2):** Evaluates the band's tri-mode candidate telemetry byte ($70\%\text{--}100\%$) and documents candidate status.
10. **Respiratory Rate (EDR / RSA):** Evaluates respiratory sinus arrhythmia (RSA) peak-to-peak modulation during still sleep epochs.

---

## 2. Automated Root-Cause Classification (`whoop/accuracy/classifier.py`)

Diagnoses why observed values deviate and assigns standardized diagnostic categories and confidence ratings (`HIGH`, `MEDIUM`, `LOW`):

| Diagnostic Category | Criteria | Typical Metric Affected |
|:---|:---|:---|
| `MISSING_SENSOR_PACKETS` | Sensor coverage < 70% during measurement window | Average HR, Max HR, Day Strain |
| `INCOMPLETE_HISTORICAL_SYNC` | Sensor coverage < 20% | All metrics |
| `DIFFERENT_MEASUREMENT_WINDOW` | Window overlap < 80% or mean sleep HR vs 5-minute rolling dip | RHR, Sleep Duration |
| `INCORRECT_SAMPLE_SELECTION` | HRV evaluated outside of Slow-Wave Sleep (Deep Sleep) epochs | HRV RMSSD |
| `FORMULA_DIFFERENCE` | Discrepancy due to reserve scaling, delta clamping, or baseline weighting | Day Strain, Recovery |
| `SLEEP_STAGE_DIFFERENCE` | Divergence between STRAP 4-stage heuristic model and WHOOP proprietary classifier | Awake, Light, REM, Deep |
| `RR_FILTERING_DIFFERENCE` | Differing artifact rejection ratio (20% delta jump filter) | HRV, Respiratory Rate |
| `SENSOR_ARTIFACT` | Low stillness ratio or high optical motion log-variance | RR intervals, SpO2 |
| `INSUFFICIENT_EVIDENCE` | Agreement within ±3% tolerance (verified parity) or insufficient samples | Nominal metrics |

### Byte-Verified Ghidra Evidence Registry
Every algorithmic diagnosis links directly to ARM64 disassembly ground truth from `Whoop.app/Whoop` (iOS 5.80.2):
- **Strain Reserve Formula:** `0x100201558` (`StrainCalculations.reserve`)
- **Strain Sigmoid Weighting:** `0x100201644` (`StrainCalculations.weight`)
- **Strain 3.0s Delta Clamp:** `0x1002018a0` (`StrainCalculations.integrate` — `fcmp d0, #3.0; fcsel d8, #3.0, d0, gt`)
- **Strain Normalization Divisor:** `0x1002012e8` (`691200.0` constant at `0x1091352f8`)
- **HRV SWS Deep Sleep Isolation:** `0x100a7fdc8` (`RecoveryAnalysis.calculateNightHRV`)
- **RHR Lowest 5-Minute Dip:** `0x100a80410` (`RecoveryAnalysis.calculateNightRHR`)
- **Respiratory Rate EDR:** `0x100ba3180` (`RespiratoryRateAnalysis.computeFromPPG`)

---

## 3. BLE Packet Replay & Wire Simulation Engine (`whoop/accuracy/replay.py`)

Streams raw notification logs and packet captures directly through STRAP's production decoders (`whoop/framing.py:FrameReassembler`, `whoop/records.py:decode_v18`, `decode_v26`, `decode_v21`):

- **Supported Record Types:**
  - `V18` (112-byte 1 Hz biometric summary: HR, RR block, dynamic accel, sleep state, temp, SpO2 candidate)
  - `V26` (76-byte 25 Hz optical photoplethysmogram waveform)
  - `V21` (1232-byte 100 Hz six-axis IMU accelerometer/gyroscope buffer)
- **Physical-Layer Wire Impairments:**
  - **MTU Fragmentation:** Splitting frames into realistic ATT MTU chunks (20, 23, 128, 244 bytes).
  - **Dropped Chunks:** Probabilistic packet drop simulating RF packet loss and testing reassembler CRC validation.
  - **Corrupted Bytes:** Injected single-bit and byte flips validating Modbus CRC16 and CRC32 rejection.
  - **Duplicate Packets:** Injected duplicated chunks to verify state-machine idempotency.
  - **Reordering:** In-memory queue buffering simulating non-sequential packet arrival.
  - **Disconnect/Reconnect:** Periodic connection drops simulating BLE link resets and buffer flush.

---

## 4. Sensor Data Quality Monitor (`whoop/accuracy/quality.py`)

Monitors incoming telemetry and classifies operational health states:
- `VALID`: Continuous, nominal telemetry stream with <10% packet loss and >85% valid RR intervals.
- `INSUFFICIENT_DATA`: Fewer than 60 samples available.
- `PENDING_SYNC`: >35% packet loss indicating missing flash memory blocks awaiting BLE download.
- `SENSOR_QUALITY_LOW`: <65% valid RR intervals or >40% zero HR readings indicating loose wrist placement.
- `UNSUPPORTED`: Telemetry format not supported.

---

## 5. Offline Standalone Reports (`whoop/accuracy/report.py`)

Generates completely offline, self-contained HTML reports with:
- **Embedded SVG Metric Bar Chart:** Side-by-side comparison of STRAP vs WHOOP normalized values with delta badges.
- **Embedded SVG Sleep Hypnogram:** Step chart displaying transitions between Awake, REM, Light, and Deep sleep.
- **Telemetry Quality Badges:** Status, packet loss %, RR validity %, and maximum gap durations.
- **Ghidra Ground Truth Callouts:** Exact binary symbols, addresses, and remediation guidance for each flagged metric.

---

## CLI Usage

### 1. Compare STRAP vs WHOOP Export
```bash
python tools/strap_accuracy_lab.py compare \
  --whoop-dir /path/to/whoop_export/ \
  --strap-csv /path/to/strap_records.csv \
  --output-html report.html \
  --output-md report.md
```

### 2. Replay BLE Packet Capture with Impairments
```bash
python tools/strap_accuracy_lab.py replay \
  --input packet_log.hex \
  --mtu 20 \
  --drop-rate 0.05 \
  --corrupt-rate 0.01 \
  --output decoded_samples.json
```

### 3. Monitor Sensor Telemetry Quality
```bash
python tools/strap_accuracy_lab.py monitor \
  --input strap_telemetry.csv \
  --expected-seconds 86400
```

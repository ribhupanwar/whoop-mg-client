# PHASE 14 — STRAP vs. WHOOP Gap Analysis & Clean-Room Recommendations

## 1. Metric-by-Metric Comparison Matrix

| Metric | WHOOP Evidence | STRAP Current Implementation (`main`) | Confirmed Gap | Recommended Fix for STRAP |
| :--- | :--- | :--- | :--- | :--- |
| **HRV Window Selection** | Extracted strictly during **Slow Wave Sleep (SWS / Deep Sleep)**, prioritizing the terminal SWS cycle. | `Hrv.restingHRV(samples, minWindowS: 300)` selects the **longest continuous quiet run ($\text{accel} \le 0.10\text{g}$)** during the night. | Quiet immobility occurs during light sleep and REM. Measuring HRV during REM or light sleep introduces non-SWS autonomic noise and inflates/deflates RMSSD. | Constrain `restingHRV` to samples staged as **`.deep` (SWS)** in `SleepStager.swift`. If SWS duration $< 10\text{ min}$, fall back to longest quiet non-REM sleep. |
| **Resting Heart Rate (RHR)** | Basal heart rate during **Slow Wave Sleep (SWS)**; distinct from single lowest dip (`min_heart_rate`). | `Hrv.restingHeartRate(samples, policy: .overnightPrimarySleep)` takes the minimum rolling 5-minute average across quiet runs. | STRAP computes minimum rolling mean across any quiet window, which can land in light sleep or a transient bradycardic dip. | Calculate RHR as the **median heart rate during SWS epochs** of the primary sleep session. |
| **Naps vs. Primary Sleep** | Naps contribute **only to sleep debt reduction** (`credit_from_naps`). Naps **never alter** nightly HRV or RHR. | In `CaptureAnalysis.swift:215-226`, multiple sleep sessions are merged by weighting RMSSD by window length. | Blending daytime nap HRV with overnight sleep HRV corrupts the morning recovery score. | In `CaptureAnalysis.swift`, isolate the **Primary Sleep Session** (longest overnight sleep) for HRV, RHR, and Recovery scoring; use naps exclusively for sleep debt calculations. |
| **Recovery Color Thresholds** | **Green**: $\ge 67.0\%$ (`0x108fe9460`)<br>**Yellow**: $34.0\% - 66.0\%$ (`0x108fe94f0`)<br>**Red**: $\le 33.0\%$ (`0x108fe9578`) | Unspecified in `Recovery.swift` (scores returned as a continuous 0–100 number; UI handles coloring). | Lack of explicit color classification enum matching WHOOP's canonical boundaries. | Add `RecoveryLevel` enum with exact thresholds: Green ($\ge 67\%$), Yellow ($34\text{--}66\%$), Red ($\le 33\%$), and Calibrating ($< 7\text{ days}$). |
| **Baseline Normalization Window** | **Rolling 28-day window** ($\mu_{28}, \sigma_{28}$) with a 4–14 day calibration ramp. | `Recovery.minBaselineDays = 7`, using rolling mean and SD over available history. | 7 days is too short and creates volatile day-to-day recovery swings from single outlier nights. | Increase rolling baseline window to **28 days** (with minimum 7 days to emit first score, 14 days for stable baseline). |
| **VO₂ Max Running Estimator** | Regresses steady-state cardiovascular workouts + anthropometrics cloud-side; supports `INTERNAL_ESTIMATE` & `MANUAL_LAB_TEST`. | `Hrv.runningVO2Estimate` uses ACSM oxygen cost + HR reserve ratio proxy; `Hrv.vo2Max` uses Uth non-exercise formula. | STRAP's running estimate is a sound clean-room approximation, but lacks smoothing with historical demographic baselines. | Retain `runningVO2Estimate` for outdoor steady-state runs ($\ge 6\text{ min}$, flat grade), smoothed via `runningVO2Trend` across a 30-day median window. |
| **Respiratory Rate Impact on Recovery** | Significant elevation ($> 1\text{--}1.5\text{ breaths/min}$ above baseline) suppresses Recovery as an illness penalty. | `Recovery.score` takes HRV, RHR, and Sleep Need. Respiratory rate is **not** included in the recovery score. | An athlete with high HRV during early illness who exhibits elevated respiratory rate does not have their score suppressed. | Add a respiratory rate check in `Recovery.score`: if nocturnal respiratory rate exceeds personal baseline by $\ge 1.2\text{ bpm}$, apply a damping penalty (e.g., $-15\text{--}25\%$). |

---

## 2. Implementation Roadmap for STRAP

### Priority 1: Align HRV & RHR Window to SWS (`CaptureAnalysis.swift`)
Modify sleep session processing so that rather than scanning raw quiet acceleration:
```swift
// Target Clean-Room Architecture for STRAP
let swsSamples = primarySleepSession.staging.epochs
    .filter { $0.stage == .deep }
    .flatMap { $0.samples }

let nightlyHRV = Hrv.fromSamples(swsSamples)
let nightlyRHR = Stats.median(swsSamples.map { Double($0.heartRate) })
```

### Priority 2: Exclude Naps from Baseline Updates (`CaptureAnalysis.swift`)
Ensure only the primary overnight sleep session (`isNap == false`) updates `Baseline.lnRMSSDMean` and `Baseline.rhrMean`.

### Priority 3: Formalize `RecoveryLevel` Enum (`Recovery.swift`)
Implement the verified boundary constants:
```swift
enum RecoveryLevel: String, Codable {
    case green  // score >= 67
    case yellow // 34 <= score && score <= 66
    case red    // score <= 33
    case calibrating // baseline < 7 days
    
    init(score: Double?, baselineDays: Int) {
        guard let score, baselineDays >= 7 else {
            self = .calibrating
            return
        }
        if score >= 67.0 { self = .green }
        else if score >= 34.0 { self = .yellow }
        else { self = .red }
    }
}
```
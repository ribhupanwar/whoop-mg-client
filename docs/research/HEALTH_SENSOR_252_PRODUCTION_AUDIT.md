# Issue #252 — production path audit

Inspected `ios/Strap/Analysis/HealthMonitor.swift`, `NightTemperature.swift`, `StressWindows.swift` on main, plus OpenStrap/edge proposal, STRAP optical audit, DSTA and Woop research. No sensor calibration or hardware fix is claimed.

## Skin temperature
`NightTemperature.measure` requires a valid sleep session, wearing=true, HR 35–220, `dynamicAccelG` present and <= resting threshold, `skinTempC` 20–43, and >=300 qualifying samples. `HealthMonitor.measurement` separately requires reliable sleep, >=300 seconds, and exact `v18-offset65-candidate` source. Trace per-gate drop counts before loosening safety checks. Woop warns absolute °C and deviation ±°C must never be averaged as one series.

## SpO2
`HealthMonitor.measurement` currently accepts `day.oxygenCandidatePct` between 70 and 100 and presents a numerical candidate. OpenStrap/edge proposal explicitly calls v18 inner[74] opaque/unvalidated; the 93% screenshot must not be represented as a calibrated measurement. Investigate source lineage and show provenance; no invented conversion or firmware writes.

## Stress
`StressWindows.share` and `series` bucket RR into five-minute intervals but do not enforce any minimum number of unique seconds or beat coverage per bucket. `scoredSeconds` assigns **300 seconds to every scored bucket**, even when a bucket contains only a few RR beats. This can materially overstate 24h low-stress time. Fix with a validated coverage threshold, consistent share/series implementation and deterministic sparse-coverage regression fixtures; distinguish missing data from genuinely low stress. Compare Woop Baevsky stress as a distinct non-clinical measure, not a direct WHOOP 0–3 conversion.

## Release gates
Add source-backed tests and sensor replay evidence, verify exact-head iOS and protocol CI, review before merge. Existing 6/7-night baseline alone cannot create missing skin-temperature sensor readings.

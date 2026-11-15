# WHOOP Health Monitor sample-response findings (2026-11-15)

These are **observations from user-inspected bundled sample JSON files**, not verified live API responses or recovered calculation algorithms. No proprietary sample payload is included.

## Observed response fields

Each element in `health_monitor_metrics` uses:
- `metric`: e.g. RESPIRATORY_RATE, BLOOD_OXYGEN, RHR, HRV, SKIN_TEMPERATURE_CELSIUS, SKIN_TEMPERATURE_FAHRENHEIT
- `range_calibrating`: boolean
- `current_value`: nullable number
- `current_deviation`: nullable number
- `ranges`: nullable array of `range_type` and lower/upper endpoints with boundary types
- `alert_type`, `alert_status`: nullable strings

## Observed fixtures and distinctions

- `wellness_dashboard_response.json`: populated measurements and typical ranges, `range_calibrating=false`.
- `wellness_dashboard_response_calibrating.json`: all metrics have `range_calibrating=true`; values, deviations, ranges and alerts are null.
- `wellness_dashboard_response_empty.json`: all metrics have `range_calibrating=false`; values, deviations, ranges and alerts are null.
- `wellness_dashboard_response_notemp_noblood.json`: SpO2 and skin temperature entries are null while respiratory rate, RHR and HRV remain populated; each metric has its own availability.

An especially important counterexample: respiratory rate 16.5 with the same typical range 14.5–17.6 is marked `NEAR` in the populated fixture and `WITHIN` in the partial-data fixture. **Do not infer alert_status solely from range endpoints.**

## Proposed STRAP behavior (not implemented by this note)

1. Model each metric independently with nullable values and ranges; never map missing values to zero.
2. Represent `calibrating` (flag true), `unavailable` (flag false and no current value), and `available` (numeric value) distinctly.
3. Preserve supplied alert status rather than deriving WHOOP-equivalent alert semantics from a simple in-range test.
4. Do not hide populated metrics when other sensors are unavailable.
5. Distinguish Celsius/Fahrenheit presentations of the same skin-temperature measurement rather than double-counting them.
6. Add fixture-based tests for fully populated, calibrating, empty, and partial-data states.

## Not established by these files

Actual HRV/RHR calculation, baseline period, calibration duration, health thresholds, alert algorithm, and whether computations are on-device or server-side remain unknown.

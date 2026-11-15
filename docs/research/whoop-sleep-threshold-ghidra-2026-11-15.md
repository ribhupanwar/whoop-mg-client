# WHOOP auto-detected sleep threshold: Ghidra findings (2026-11-15)

## Scope and evidence
Reverse-engineering observations supplied by device owner from WHOOP ARM64 binary. This is behavioral interoperability research, not a port of proprietary code.

- `WHPApp::isDetectedSleepOverThreshold` at `0x10004dbcc`.
- `ConfigService.autodetectSleepThreshold` at `0x100998fac` returns a Double with fallback `1.0` when the config lookup fails.
- Config map appears to be JSON persisted under `Config-Service` in UserDefaults. Actual configured value is not established.
- At `0x10004dc2c` threshold is returned in `d0` and saved to `d8`; `fcvtzs x2,d8` at `0x10004dc88` truncates it to signed integer.
- `0x108a15ee0` selector is `whp_dateBySubtractingHours:`, called on the `[NSDate date]` object, producing a cutoff `now - Int(thresholdHours)` hours.
- `0x108a16040` selector is `whp_isEarlierThanDate:`, called on that cutoff, with `sleepAutoDetectStartedAt` as argument. Its Boolean result is inverted.
- `0x1089d6ee0` is `cycleObject`; `0x108a0e1a0` is `startsAt`; `0x108a15dc0` is `whp_convertDayDateFromGMT:`; `0x1089e8260` is `isInCurrentCycle`. That Boolean result is inverted.
- App state flag at offset `0x141` is required; detection start at offset `0x170` must be nonnull.

## Conceptual behavior (not source code)
```
if sleepAutoDetectStartedAt == nil: return false
cutoff = NSDate.date - Int(config.autodetectSleepThreshold) hours
cycleDay = NSDate.whp_convertDayDateFromGMT(app.cycleObject.startsAt)
return app.flag_0x141 && !cycleDay.isInCurrentCycle &&
       !cutoff.whp_isEarlierThanDate(sleepAutoDetectStartedAt)
```
The inferred comparison means `sleepAutoDetectStartedAt <= cutoff` (subject to the selector's actual semantics). Exact role of `flag_0x141`, config overrides, and broader sleep start/end detection remain unverified.

## STRAP comparison (main)
`ios/Strap/Analysis/SleepDetect.swift` uses `minSleepS = 3600`, a 90-minute floor for daytime candidates, actigraphy + HR-drop gates, and evening sustained band-state evidence. This is a *candidate-window detector*, not the same layer as WHOOP's app-level threshold/cycle gating. Do not substitute one for the other or assume WHOOP's fallback value is its active configuration.

## Recommended implementation constraints
1. Preserve the existing physiological and sparse-data gates; do not replace them with a time-only rule.
2. If a distinct app-level auto-detection confirmation gate is introduced, keep it separate from `SleepDetect.detect` and explicitly model detection-start timestamp, configurable threshold hours, and cycle membership.
3. Add tests for nil detection start, threshold boundary, fractional truncation, current-cycle inversion, disabled flag, midnight/GMT boundaries, and backfilled archives before enabling the gate.
4. Keep manual sleep correction as canonical for downstream duration/recovery and invalidate stale analysis; do not overwrite edits with archive replays.

No production behavior change is justified by this evidence alone.

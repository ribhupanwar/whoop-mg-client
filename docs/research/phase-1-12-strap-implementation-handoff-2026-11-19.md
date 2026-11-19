# STRAP Phase 1–12 engineering handoff (2026-11-19)

Status: **research triaged, implementation NOT complete**. This handoff does not certify device accuracy or a successful IPA build.

## Baseline from current main
- `ios/Strap/Analysis/Activities.swift` already has an offline auto-activity detector: verified step-counter deltas or HR elevation, a 5–15 minute HR baseline, 4-minute evidence sustain, 5-minute minimum session, 180-second gap tolerance, and step-rate run/walk labels. The gait byte is explicitly unverified. **Do not silently replace these constants with WHOOP marketing text.**
- `ios/Strap/Analysis/SleepDetect.swift` already has onset/wake guards, short-gap bridging and a conservative band-state policy. Regression-test any change against bathroom awakenings and quiet awake tails.
- `ios/Strap/ActivityStore.swift` already has a broad `ActivityKind` catalog, SF Symbols fallbacks and corruption-aware persistence. Do not reimplement or delete it.
- HRV/RHR, SpO2, temperature, VO2 max, recovery and strain already exist. Work is alignment and source-quality validation, not introducing fake values.
- Preserve licensed Proxima Nova and DIN Pro fonts, all existing user records and the backup/restore workflow.

## Evidence from WHOOP iOS binary analysis (Phases 1–12)
1. A sleep-processing event and historical-data processing window are separate from the final sleep result. The `processNowSleepOffsetFix` flag conditionally selects a Date offset of **-11 seconds** for a processing interval, **not** a sleep onset/end adjustment. Do not copy it into local sleep boundaries without measured evidence.
2. Sleep DTOs expose `during.lower/upper`, awake/light/REM/SWS durations, provisional state and auto-detection/source metadata. The binary report did not demonstrate a complete concrete merge-lock branch, so manual-edit precedence is a **STRAP design requirement**, not proven exact WHOOP code.
3. WHOOP official 2026 release notes state the minimum workout auto-detection duration was **lowered from 15 to 10 minutes in January 2026** (https://www.whoop.com/us/en/thelocker/2026-whats-new/). WHOOP's activity guide describes HR + motion patterns and delayed processing after HR returns to baseline (https://support.whoop.com/s/article/Automatic-and-Manual-Activity-Detection). Historical 15-minute/strain-8 rules are outdated and must NOT be hard-coded as current universal requirements. These public statements still do **not** reveal executable per-sport thresholds, exact pause tolerances or a universal Zone 2 gate.
4. Activity catalog includes running (0), cycling (1), walking (52), weightlifting (47), etc., with icon URL metadata. External icon availability/licensing and exact WHOOP pixel sizes are not established.
5. Workout result models include start/end, sport, average/max HR, strain, energy, zones and GPS. Unknown values must remain unavailable.
6. Reported proprietary recovery/strain formulas, SWS-only HRV/RHR, universal cloud classification, 3–5 minute pause tolerance, and exact cadence ranges are **unverified hypotheses**. Do not implement them as WHOOP facts.
7. Firmware sampling/flash changes are out of scope: STRAP is a BLE reader of existing WHOOP hardware.

## Safe implementation order / acceptance criteria
### A. Sleep manual-edit preservation
- Inspect existing persisted edit/reconciliation paths; prevent subsequent automatic detection/replay from overwriting a user-confirmed start/end.
- Preserve original sensor history and user-edit provenance. Verify relaunch, reconnect, repeated archive replay, short bathroom gaps and no-data intervals.
- Invalidate/recompute dependent sleep score, stage chart, recovery only where data supports calculation; otherwise show unavailable.

### B. Automatic activity detection
- **New official evidence (2026):** minimum WHOOP workout auto-detection duration changed to 10 minutes. Compare STRAP's existing 5-minute minimum against a 10-minute **candidate mode** using captured reference workouts; avoid global switch until sensitivity, false positives and short valid sessions are tested.
- Investigate actual WHOOP start/end state transitions and activity classification using read-only Ghidra; no claim that a binary or backend classifier has been recovered. Evaluate post-HR-baseline processing delay separately from physiological end timestamp.
- Keep existing 5-minute detector behavior until controlled comparisons support a change. Add opt-in/configurable duration experiments (10/15 min) separately from classification.
- Validate running/walking from measured step-counter motion and HR, never unverified gait byte alone. Test false sedentary walks, HR-only exertion, gaps, clock jumps, off-wrist and sparse/duplicated historical samples.
- Add new sports only with reliable evidence; label uncertain workouts as generic rather than inventing cycling/swimming/weights.
- Manual/GPS sessions take precedence over overlapping auto candidates. Preserve deletion tombstones and no duplicate replay.

### C. UI / metric alignment
- Audit actual activity icon coverage, detail screen HR chart, zone duration, calories, GPS, strain and source; keep unavailable metrics explicit.
- Compare WHOOP and STRAP screenshots on the same iPhone for ring outer diameter, stroke, digit and percent baseline, label tracking, battery icon and sport detail cards. Preserve licensed fonts.
- Validate HRV/RHR against identical nighttime windows; validate SpO2/temperature/VO2max/recovery/strain only with real sensor/reference data.

### Gate before merging behavioral code
- Focused Swift regression tests, native iOS Actions build and IPA packaging must pass on the exact commit.
- Physical iPhone verification remains required for sleep accuracy, automatic workout classification, band BLE and pixel-perfect UI.
- Never merge stale PR #46 wholesale. Prefer small, auditable changes.

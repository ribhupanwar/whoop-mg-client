# Phase 1–12 implementation matrix — 2026-11-19

Evidence legend: VERIFIED = independently observed code/test or documented public behavior; INFERRED = plausible interpretation; UNKNOWN = not established. Status legend: TODO / IN PROGRESS / CODE DONE / CI VERIFIED / DEVICE VERIFY / BLOCKED. A green CI run never proves real-device metric parity.

| Phase / workstream | Evidence | Status | Evidence / remaining gate |
|---|---|---|---|
| 1–3 Activity detection duration and start/end | VERIFIED (STRAP code), INFERRED (WHOOP internals) | DEVICE VERIFY | Optional 10-min comparator, 5-min default, 4-min sustain, pause/cooldown regression; 16-bit wrap-safe step evidence in `e3982ec`, test `47734a4`. Latest native iOS CI pending. Real paired walk/run capture needed. |
| 4 Activity sport labels, duplicate/replay | VERIFIED (STRAP code); UNKNOWN (WHOOP classifier) | DEVICE VERIFY | Step-based walk/run; generic HR-only cardio; tombstones. Validate against real runs and sync replay. |
| 5–6 Sleep onset, wake and bathroom gaps | VERIFIED (STRAP code), INFERRED (band-state semantics) | DEVICE VERIFY | Backtrack requires measured HR/motion; no fixed 15-minute subtraction. Same-night CSV comparison and manual corrections needed. |
| 7 Sleep manual edits/recalculation | VERIFIED (partial code/tests), UNKNOWN (all device paths) | DEVICE VERIFY | Reinstall/replay and score recomputation need same-device tests. |
| 8 RR, HRV and RHR | VERIFIED (existing estimators), UNKNOWN (WHOOP parity) | BLOCKED | Need CRC-checked timestamped RR and matched WHOOP sleep window. |
| 9 SpO2, respiratory, temperature, VO2 | INFERRED / UNKNOWN mapping | BLOCKED | Independent overnight and workout evidence; abstain on missing data. |
| 10 Recovery, strain, calories | VERIFIED (isolated experimental math), UNKNOWN (WHOOP parity) | DEVICE VERIFY | Recovered calorie model not production; strain lookup exists; matched HR traces and active/total semantics needed. |
| 11 UI rings, battery, typography | VERIFIED (existing components and CI), UNKNOWN (pixel parity) | DEVICE VERIFY | Same-device WHOOP/STRAP screenshot measurements; preserve fonts. |
| 12 Backup/export/restore and release | VERIFIED (code/tests), UNKNOWN (device restore) | DEVICE VERIFY | Backup and GPX/FIT paths exist; physical restore, decoder interoperability and latest IPA verification pending. |

## 2026-11-19 ring correction CI gate
- **VERIFIED (code and CI):** `284c16a` Home ring geometry/typography change passed [native iOS/IPA 44527555893](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44527555893) and [tests 44527555948](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44527555948).
- **DEVICE VERIFY:** screenshot geometry, accessible touch targets, battery icon, font rendering and true physiological parity on target iPhone. Prior forensic report's pixel-match assertions are not physical-device acceptance evidence.
- **UNKNOWN:** Strain/Health/Stress differences from WHOOP screenshots require matching source history and baseline evidence; never replace unavailable values with mock data.

## Current bounded change
- `e3982ec`: activity motion uses `StepCounter.delta` to handle real 16-bit wrap and reset semantics rather than raw signed subtraction. No persisted schemas, historical data, sensor units or fonts changed.
- `47734a4`: regression covers a 660-second measured walk spanning a 16-bit counter wrap.
- **CODE DONE; CI verification pending** on the latest main revision. Do not mark device accuracy complete.

## 2026-11-19 activity false-positive gate verification
- **CODE DONE / CI VERIFIED (protocol tests):** `0bb016a8` requires detected walking to last at least 600 seconds and include at least 240 measured-motion samples with HR above the established personal baseline threshold; `a8671a3` adds brisk-walk and casual-walk regressions. [Tests run 44502230437](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44502230437) passed for `a8671a3`.
- **DEVICE VERIFY / native CI pending:** [iOS run 44502230521](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44502230521) was in progress at review. Walking HR thresholds are conservative STRAP heuristics, not verified WHOOP thresholds. Verify false positives, low-HR genuine walks, sparse offload and long pauses on paired real-device captures. Running and HR-only cardio keep their previous gates.
- **UNKNOWN / follow-up:** A measured-step session classified as generic `workout` when step-rate median is below `walkSPM` can bypass the walk-specific HR gate; classification should be audited with fixtures before changing generic workout behavior. No persistence schema or historical records changed.

## 2026-11-19 Phase 18 Humans compile gate
- **VERIFIED / CODE DONE; CI pending:** iOS run [44519508836](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44519508836) failed on nonexistent `DayMetrics.recovery`; `08687ce` derives leaderboard recovery from recorded inputs and prior-day baseline using existing `Recovery.score`. Follow-up [44520900712](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44520900712) failed because `BandLink.needHours` is private; `3a2f253` uses existing public `store.settings.sleepNeedHours`. Native CI for the latter revision was queued at review. Humans display, navigation, and pixel parity remain **DEVICE VERIFY**. No synthetic recovery values or persisted-schema changes.

## 2026-11-19 activity duration comparator regression
- **VERIFIED (code inspection):** Existing default is five minutes for measured running; optional ten-minute comparator is explicitly opt-in. Walking has its independent ten-minute plus elevated-HR gate. WHOOP's public ten-minute guidance does not establish identical detection thresholds.
- **CODE DONE / CI VERIFY:** `4dac623e` adds a focused 6-minute measured-run regression (default retained, comparator excluded) and an 11-minute comparator acceptance test. No production behavior, saved records or schemas changed. Native test workflow pending on the exact revision.
- **DEVICE VERIFY:** compare same-device real 6-minute and 11-minute runs with WHOOP and STRAP; test pauses and late HR cooldown before changing defaults.

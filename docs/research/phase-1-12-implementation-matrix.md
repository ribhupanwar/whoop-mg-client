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

## Current bounded change
- `e3982ec`: activity motion uses `StepCounter.delta` to handle real 16-bit wrap and reset semantics rather than raw signed subtraction. No persisted schemas, historical data, sensor units or fonts changed.
- `47734a4`: regression covers a 660-second measured walk spanning a 16-bit counter wrap.
- **CODE DONE; CI verification pending** on the latest main revision. Do not mark device accuracy complete.

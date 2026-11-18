# STRAP WHOOP-inspired UI engineering backlog

Status legend: **DONE (code)** = committed implementation, **VERIFY** = requires CI/device screenshot, **TODO** = not implemented, **BLOCKED** = missing evidence or environment.

## Design foundation
- [x] **DONE (code)** Licensed Proxima Nova/DIN Pro font resolver present in `ios/Strap/Components.swift` (existing implementation).
- [x] **DONE (code)** Initial charcoal theme in `ios/Strap/Theme.swift` (commit `a408c3b`).
- [x] **DONE (code)** Home/screen canvas gradient top changed from `#121518` to blue-charcoal `#253038`, retaining bottom `#121518` (commit `35eebc9`).
- [ ] **VERIFY** Compare canvas gradient and contrast against the user's WHOOP/STRAP side-by-side Home screenshots on device; exact color match is not yet established.
- [ ] **TODO** Calibrate Home metric card surface/gradient, bottom navigation translucency, sleep/strain ring tracks, and Daily Outlook purple-to-teal gradient from screenshots; do not alter metric-dependent Recovery zone colors to force a visual match.
- [x] **DONE (code)** Navigation heading kerning (commit `f22d5d7`).
- [ ] **VERIFY** Exact type hierarchy, text tracking, line height, card spacing and contrast against current WHOOP screenshots.
- [ ] **TODO** Automated screenshot baselines and regression comparison.

## Navigation and Home
- [x] **DONE (code)** Bottom navigation styling (commit `3d402e7`).
- [x] **DONE (code)** Custom tab VoiceOver labels, selected-state announcements and hints (commit `e50d9e1`).
- [x] **DONE (code)** Daily Insights accessibility hint and stable UI-test identifier (commit `ee1393d`).
- [ ] **VERIFY** Tab sizes, selected states, safe area, VoiceOver and tap targets on device.
- [x] **DONE (verified CI)** Earlier run `44093504026` failed `TabResponsivenessTests` because `app.buttons["tab.home"]` was not found; the custom tab accessibility change (`bfed00f`) was subsequently covered by successful consolidated UI tests in run `44120344273`. Physical-device VoiceOver and tap-target checks remain **VERIFY**.
- [x] **DONE (code)** Missing-tab UI test now attaches the full accessibility hierarchy and launch screenshot on failure for actionable CI diagnosis (commit `f505c64`).
- [x] **DONE (verified CI)** Tab responsiveness regression passed as part of the three UI tests in consolidated run `44120344273` at revision `20b7ad5`; physical-device tap targets/VoiceOver remain **VERIFY**.
- [ ] **TODO** Recovery/Strain/Sleep hero gauges and detail views screenshot alignment.
- [ ] **TODO** Today activity card ordering, duplication, swipe actions and visual match.
- [ ] **TODO** Trends: 7-day, 30-day and longer baseline views, only with real available data.

## Health Monitor
- [x] **DONE (code)** HR panel typography and validated-unavailable skin-temperature placeholder (commit `2f02a7e`).
- [x] **DONE (code)** Health Monitor HR chart grid changed to more visible blue-grey `#667D88` at 17% opacity (commit `58671c6`).
- [x] **DONE (code)** Removed redundant Connected banner above live HR chart to match reference (commit `31070f7`); BLE connection logic unchanged.
- [ ] **VERIFY** Health Monitor chart grid/background colors against supplied screenshot on actual iPhone.
- [ ] **TODO** Match Health Monitor chart height, line placement, typography, and metric tile surface colors to supplied reference without changing real BPM or sensor-derived measurements.
- [ ] **VERIFY** HR chart geometry, metric cards and status contrast on device.
- [ ] **TODO** Accurate range/status visualizations; never invent SpO2, respiratory rate or skin temperature.

## Sleep, alarm and recovery
- [x] **DONE (code)** Alarm wake-time DIN Pro formatting (commit `9ee0ec0`).
- [x] **DONE (code)** Sleep HR chart valid time-window filtering (commit `f081f76`); regression test added (`606a6a0`).
- [ ] **VERIFY** Terminal band-up wake boundary regression tests (299s remains, 300s trims) added in `SleepWakeTailBoundaryTests.swift` (commit `72b0490`); native CI and real-device sleep-end validation pending.
- [ ] **TODO** Sleep stage hypnogram screenshot alignment and validated detection/staging.
- [ ] **TODO** Verify edited sleep start/end persistence and recomputation of sleep performance/recovery.
- [ ] **TODO** Alarm weekly schedule layout and actual band behavior.
- [ ] **TODO** Recovery baseline/insight presentation with real measurements.

## Train, Plan, More
- [ ] **TODO** Workout cards, HR zones, pace typography and activity actions.
- [ ] **TODO** Sleep Coach/strain target layouts.
- [ ] **TODO** Profile, device, Settings and empty/loading/error states.

## BLE decoding, RR and sensor fidelity
- [x] **DONE (code)** Added synthetic Type-40 RR boundary, malformed-count and truncated-packet regression tests in `ios/StrapTests/LiveHeartRateStateTests.swift` (commit `8d03fa3`); no production decoder offsets or historical data were changed.
- [x] **DONE (code)** Batch 1: added synthetic Type-40 tests for zero/invalid RR, malformed count, historical packet exclusion and invalid live HR (commit `9d47d8f`); no sensor decoding offsets or saved data changed.
- [x] **DONE (verified CI)** Protocol test matrix on `main` at `b991e13` succeeded on rerun attempt 2: all six Python 3.11/3.13 jobs across macOS, Windows and Ubuntu passed ([run 44141804851](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44141804851)). Synthetic RR safety tests are covered; real-device RR accuracy remains **BLOCKED** below.
- [x] **DONE (verified CI)** Native iOS workflow at production revision `9d47d8f` succeeded ([run 44141781672](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44141781672)); later `b991e13` is a checklist-only commit, not a production code change.
- [ ] **BLOCKED** Validate Type-40 RR units/offsets and V18 RR decoding against timestamped, CRC-checked WHOOP 5.0/MG BLE capture with independent beat reference; synthetic tests alone do not establish HRV accuracy.
- [ ] **TODO** Investigate RR buffering/deduplication and HRV/RHR calculation against actual captured beat intervals, preserving missing data rather than inventing beats.
- [ ] **VERIFY** V20/V21/V26 record handling against real-device fixtures before using these records for scored metrics. Do not send persistent Gen5 R22 configuration writes automatically; OpenStrap warns some settings may be irreversible.
- [ ] **BLOCKED** Validate V18 sleep-state bits and SpO2 candidate mapping against independent overnight references before using them as authoritative sleep stages or clinical SpO2.

## Verification and safety
- [x] **DONE (verified CI)** Consolidated native Actions run [44120344273](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44120344273) succeeded for tested revision `20b7ad5c60d46464beabd315a6ce087a48888769`: 511 unit tests, 3 UI tests, simulator/device archive and IPA packaging (evidence in `docs/WHOOP_CALORIE_IMPLEMENTATION_VALIDATION.md`; workflow job conclusion independently checked).
- [x] **DONE (verified PR CI, not merged)** Draft PR #46 branch `codex/master-progress-20261117` at `5a48da5` passed native iOS simulator tests, GPX/FIT validation, IPA packaging, font and HealthKit checks ([iOS run 44177160708](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44177160708)); six-platform Python protocol matrix also passed ([run 44177160390](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44177160390)). These results validate the PR branch only, not `main` or real-device data fidelity. PR #46 remains **VERIFY** for isolated persistence review and device tests before any merge.
- [ ] **VERIFY** Obtain a successful native iOS Actions build at the exact latest `main` HEAD (the successful run `44141781672` tested `9d47d8f`; later `b991e13` changed documentation only). New code merges require a new native run.
- [ ] **VERIFY** Install latest IPA and compare screenshots on target iPhone.
- [ ] **TODO** Add accessible screenshot/layout tests and font checks.
- [ ] **TODO** Validate export/backup before reinstall/uninstall; never delete historical records.
- [ ] **TODO** Audit and resolve remaining sleep/HRV/RHR/activity/persistence bugs separately from visual styling.

## Working rules
1. Inspect source and reference material; prioritize highest-impact unverified items.
2. Implement small, reviewable changes; add focused tests; commit verified code to `main`.
3. Update this checklist after each verified change. Never mark a task complete merely because code was pushed.
4. Keep licensed fonts; do not copy proprietary assets or claim clean-room clones are official WHOOP source.
5. Do not fabricate health data or alter persisted records destructively.
6. If CI or physical-device verification is unavailable, leave the item as **VERIFY** or **BLOCKED**, not completed.

Sources: user-supplied WHOOP design notes, official WHOOP brand guidance, NOOP design-language reference, OpenStrap, and `ribhupanwar/dsta`. Palette and layout require screenshot verification; third-party design values are not official universal tokens.

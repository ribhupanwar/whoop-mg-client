# STRAP WHOOP-inspired UI engineering backlog

Status legend: **DONE (code)** = committed implementation, **VERIFY** = requires CI/device screenshot, **TODO** = not implemented, **BLOCKED** = missing evidence or environment.

## Design foundation
- [x] **DONE (code)** Licensed Proxima Nova/DIN Pro font resolver present in `ios/Strap/Components.swift` (existing implementation).
- [x] **DONE (code)** Charcoal theme alignment in `ios/Strap/Theme.swift` (commit `a408c3b`).
- [x] **DONE (code)** Navigation heading kerning (commit `f22d5d7`).
- [ ] **VERIFY** Exact type hierarchy, text tracking, line height, card spacing and contrast against current WHOOP screenshots.
- [ ] **TODO** Automated screenshot baselines and regression comparison.

## Navigation and Home
- [x] **DONE (code)** Bottom navigation styling (commit `3d402e7`).
- [x] **DONE (code)** Custom tab VoiceOver labels, selected-state announcements and hints (commit `e50d9e1`).
- [x] **DONE (code)** Daily Insights accessibility hint and stable UI-test identifier (commit `ee1393d`).
- [ ] **VERIFY** Tab sizes, selected states, safe area, VoiceOver and tap targets on device.
- [ ] **VERIFY** CI regression: run `44093504026` failed `TabResponsivenessTests` because `app.buttons["tab.home"]` was not found; removed `.accessibilityElement(children: .ignore)` from custom tab Button in commit `bfed00f`; rerun required.
- [ ] **TODO** Recovery/Strain/Sleep hero gauges and detail views screenshot alignment.
- [ ] **TODO** Today activity card ordering, duplication, swipe actions and visual match.
- [ ] **TODO** Trends: 7-day, 30-day and longer baseline views, only with real available data.

## Health Monitor
- [x] **DONE (code)** HR panel typography and validated-unavailable skin-temperature placeholder (commit `2f02a7e`).
- [x] **DONE (code)** Removed redundant Connected banner above live HR chart to match reference (commit `31070f7`); BLE connection logic unchanged.
- [ ] **VERIFY** HR chart geometry, metric cards and status contrast on device.
- [ ] **TODO** Accurate range/status visualizations; never invent SpO2, respiratory rate or skin temperature.

## Sleep, alarm and recovery
- [x] **DONE (code)** Alarm wake-time DIN Pro formatting (commit `9ee0ec0`).
- [x] **DONE (code)** Sleep HR chart valid time-window filtering (commit `f081f76`); regression test added (`606a6a0`).
- [ ] **TODO** Sleep stage hypnogram screenshot alignment and validated detection/staging.
- [ ] **TODO** Verify edited sleep start/end persistence and recomputation of sleep performance/recovery.
- [ ] **TODO** Alarm weekly schedule layout and actual band behavior.
- [ ] **TODO** Recovery baseline/insight presentation with real measurements.

## Train, Plan, More
- [ ] **TODO** Workout cards, HR zones, pace typography and activity actions.
- [ ] **TODO** Sleep Coach/strain target layouts.
- [ ] **TODO** Profile, device, Settings and empty/loading/error states.

## Verification and safety
- [ ] **VERIFY** GitHub Actions successful iOS build for latest main commit. GitHub commit combined-status endpoint returned no statuses; that is **not** evidence of a passing build.
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

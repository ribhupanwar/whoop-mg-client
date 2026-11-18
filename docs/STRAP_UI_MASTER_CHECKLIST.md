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
- [ ] **VERIFY** Home Sleep/Recovery/Strain ring labels now avoid clipping with minimum scaling and expose a single accessible button label with actual or unavailable score (commits `f1c8904`, `69e894f`); native CI and device VoiceOver/tap tests pending. Full hero gauges and detail-view screenshot alignment still **TODO**.
- [ ] **TODO** Today activity card ordering, duplication, swipe actions and visual match.
- [ ] **TODO** Trends: 7-day, 30-day and longer baseline views, only with real available data.

## Health Monitor
- [x] **DONE (code)** HR panel typography and validated-unavailable skin-temperature placeholder (commit `2f02a7e`).
- [x] **DONE (code)** Health Monitor HR chart grid changed to more visible blue-grey `#667D88` at 17% opacity (commit `58671c6`).
- [x] **DONE (code)** Removed redundant Connected banner above live HR chart to match reference (commit `31070f7`); BLE connection logic unchanged.
- [ ] **VERIFY** Health Monitor chart grid/background colors against supplied screenshot on actual iPhone.
- [ ] **VERIFY** Health Monitor HR chart now draws observed HR variation instead of a synthetic flat trace, with endpoint marker aligned to the last plotted observation (commits `90eb17a`, `abcc8f9`); native iOS CI [44225569658](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44225569658) passed for `abcc8f9`; screenshot comparison pending. Chart height, typography and metric tile colors still **TODO**.
- [ ] **VERIFY** Live HR trace now excludes historical/offline readings and rejects implausible/nonfinite BPM, with focused `HealthChartReadingsTests.swift` tests (commits `8674802`, `3536f74`); native iOS CI [44228173313](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44228173313) passed; device screenshot comparison pending.
- [ ] **VERIFY** HR chart geometry, metric cards and status contrast on device.
- [ ] **TODO** Accurate range/status visualizations; never invent SpO2, respiratory rate or skin temperature.

## Sleep, alarm and recovery
- [x] **DONE (code)** Alarm wake-time DIN Pro formatting (commit `9ee0ec0`).
- [x] **DONE (code)** Sleep HR chart valid time-window filtering (commit `f081f76`); regression test added (`606a6a0`).
- [x] **DONE (verified CI)** Terminal band-up wake boundary regression tests (299s remains, 300s trims) in `SleepWakeTailBoundaryTests.swift` at `72b0490`; native iOS build/test/IPA workflow [44218990787](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44218990787) succeeded on this code revision. Real-device sleep-end accuracy remains **VERIFY**.
- [ ] **VERIFY** Synthetic regressions for terminal state=0 suffix after sustained wake and short bathroom awakening followed by sleep added in `SleepWakeTailBoundaryTests.swift` (commit `996fa59`); native iOS CI [44221683794](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44221683794) passed; timestamped device captures remain pending. Synthetic boundary tests do not establish physical-device accuracy.
- [ ] **VERIFY** Sleep Consistency detail now plots five fixed calendar-day positions, preserves missing nights as gaps, uses 8 PM–noon axis and displays selected night's actual bed/wake clock times (commit `8ae972f`); native CI and iPhone screenshot pending. STRAP's local median-based score differs from WHOOP's proprietary algorithm; do not force 59%.\n- [ ] **VERIFY** Sleep Efficiency timeline now rejects empty/out-of-window staging segments and has explicit accessible asleep/awake/unclassified labels (commits `971c0cb`, `6e9179f`); native iOS CI [44233070396](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44233070396) passed at `6e9179f`; device comparison pending. Awake/asleep staging accuracy and 6:15 vs 6:36 difference remain **TODO** pending same-night sensor evidence.\n- [ ] **TODO** Sleep stage hypnogram screenshot alignment and validated detection/staging.
- [ ] **VERIFY** Offline manual sleep wake-edit persistence and stale-score abstention regression added in `SleepSessionTests.swift` (commit `6e31694`); CI and real-device edit/recovery refresh remain pending. Do not mark complete until restored sensor coverage recalculates metrics correctly.
- [ ] **TODO** Alarm weekly schedule layout and actual band behavior.
- [ ] **TODO** Recovery baseline/insight presentation with real measurements.

- [ ] **VERIFY** Sleep diagnostic CSV stage-gap boundary: `SleepDiagnostics.csv` now requires `sample.unix < segment.endUnix` before assigning a stage, preventing a preceding segment from being carried across unclassified gaps (fix `db27c5b`, regression `dac26ec`). Native iOS CI runs [44241664595](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44241664595) and [44241664510](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44241664510) were pending at review. This is export labeling only, not a validated sleep detector fix.

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
- [ ] **VERIFY** Native iOS run `44218990787` passed at sleep boundary test revision `72b0490`; new regression commit `996fa59` requires its own native CI result. Physical-device install remains pending.
- [ ] **VERIFY** Install latest IPA and compare screenshots on target iPhone.
- [ ] **TODO** Add accessible screenshot/layout tests and font checks.
- [ ] **TODO** Validate export/backup before reinstall/uninstall; never delete historical records.
- [ ] **TODO** Audit and resolve remaining sleep/HRV/RHR/activity/persistence bugs separately from visual styling.

- [x] **DONE (verified CI)** IPA delivery hardening: optional standalone HealthKit entitlement artifact no longer fails an otherwise valid iOS build when GitHub CreateArtifact times out; primary `Strap-unsigned-ipa` artifact now bundles IPA and signing entitlement plist and requires both files (commit `e7e625b`). Native iOS workflow [44245566066](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44245566066) succeeded and published `Strap-unsigned-ipa` (3,181,815 bytes) plus standalone entitlement artifact. Physical-device signing and installation remain VERIFY.
- [x] **DONE (verified CI)** iOS run [44241664510](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44241664510) succeeded on rerun after GitHub ArtifactService/CreateArtifact timed out on first attempt; no Swift compiler or HealthKit entitlement error caused that failure.

- [x] **DONE (verified CI)** Sleep diagnostic export guards lookback timestamp subtraction against integer underflow (commit `67db5db`); near-epoch observed-row regression (commit `33a8d00`). Native iOS [44252856121](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44252856121) passed; real-device sleep timing remains separate.
- [ ] **VERIFY** Sleep diagnostic CSV now rejects invalid/reversed edited sleep bounds with `noNight` instead of exporting misleading records (commit `d4bad2b`), with regression test (commit `e68de8c`); native iOS CI pending.

- [x] **DONE (merged)** Codex PR [#47](https://github.com/ribhupanwar/whoop-mg-client/pull/47) merged 2026-11-17: isolated WHOOP calorie research, implementation and deterministic tests (`WhoopRecoveredCalories.swift`, `WhoopRecoveredCaloriesTests.swift`). This does not establish WHOOP-equivalent calorie accuracy on a device.
- [ ] **BLOCKED (merge conflicts)** Codex draft PR [#46](https://github.com/ribhupanwar/whoop-mg-client/pull/46) is open, 73 changed files, GitHub `mergeable=false` / `mergeable_state=dirty` against updated `main`. Review and port safe changes by feature (activity history, exports/backup, RR archives, alarms), preserving newer main code and historical data. Do not bulk merge or mark its features DONE until conflicts, tests and persistence semantics are verified.

- [ ] **VERIFY (Batch 1 / PR #46 selective port)** `WhoopSourceDates.swift` source-calendar policy was copied from draft PR #46 to `main` (commit `3adcb52`) with isolated direct regression tests (commit `17087b6`). No import/export call sites are wired yet; native iOS CI [44256303192](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44256303192) and tests [44256303088](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44256303088) pending. Do not mark WHOOP import/export complete or merge PR #46 wholesale.

- [ ] **VERIFY (Batch 1 / activity swipe)** Copied PR #46's non-destructive `ActivityDeleteReveal.swift` (commit `f6c5a22`) and `ActivitySwipeIntentTests.swift` (commit `8e7afc1`) to `main`. Gesture reveals a Delete button only; no delete on drag. Not yet wired into Today activity cards, so user-visible swipe/delete remains TODO. Native CI pending; do not claim feature complete.

- [ ] **VERIFY (Batch 1 / activity swipe wired)** Today timed and manual activity rows now use non-destructive swipe-to-reveal Delete alongside existing long-press context menu (`HomeView.swift`, commit `97fb197`). Gesture tests are in `ActivitySwipeIntentTests.swift`. iOS CI and device verification pending; verify both gesture and persisted deletion before DONE.

- [ ] **VERIFY (Batch 2 / sleep edit persistence)** Saved sleep correction alias lookup now uses overflow-safe source timestamp distance, avoiding crashes for extreme corrupt/legacy keys while retaining unrelated saved overrides (`SleepSession.swift`, commit `e321c35`); focused `SleepSessionTests.swift` regression (`2783fbe`). Native CI and device tests pending. This does not resolve sleep onset/staging or Recovery parity.

- [ ] **VERIFY (Batch 3 / live RR replay)** `Hrv.fromLiveSamples` now deduplicates same-second live samples before contiguous-run analysis, preferring more RR intervals (`df6e1df`), with duplicate replay / stronger record regression tests (`b09887e`). CI and real WHOOP capture comparison pending; this does not validate RR units, morning HRV/RHR parity, SpO₂ or respiration.

- [ ] **VERIFY (Batch 4 / Home compact score typography)** Aligned Home trio ring DIN numeric center from 25pt override to shared 18pt compact ring scale (`f1d139d`); verify screenshot against WHOOP before marking pixel-accurate. No licensed fonts changed.

- [ ] **VERIFY (Health accuracy / respiration replay)** `Respiration.beatSegments` now deduplicates replayed seconds, preferring more complete RR records (`a5063bf`); synthetic regression tests (`6415254`) cover continuity and beat counts. Native CI and WHOOP capture comparison pending. No claim of validated breathing-rate parity.

## Working rules
1. Inspect source and reference material; prioritize highest-impact unverified items.
2. Implement small, reviewable changes; add focused tests; commit verified code to `main`.
3. Update this checklist after each verified change. Never mark a task complete merely because code was pushed.
4. Keep licensed fonts; do not copy proprietary assets or claim clean-room clones are official WHOOP source.
5. Do not fabricate health data or alter persisted records destructively.
6. If CI or physical-device verification is unavailable, leave the item as **VERIFY** or **BLOCKED**, not completed.

Sources: user-supplied WHOOP design notes, official WHOOP brand guidance, NOOP design-language reference, OpenStrap, and `ribhupanwar/dsta`. Palette and layout require screenshot verification; third-party design values are not official universal tokens.

- [ ] **VERIFY** Sleep onset 13–15 minute systematic delay: diagnostic CSV now includes up to 30 minutes of actually retained pre-onset records (commits `f03100d`, `8ece896`, `b18dd11`), with a focused coverage/bounds regression test. Python protocol CI [44234619240](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44234619240) passed at checklist revision `22d386c`; native iOS CI [44234603246](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44234603246) **passed** at `b18dd11` (simulator build, tests, IPA packaging, fonts and HealthKit checks). Physical-device onset comparison remains pending. The detector already anchors pre-midnight candidates to the first 300-second contiguous band state=2 run; do not assume that is the root cause without observed pre-onset records. Compare the exported pre-onset timestamps/states against WHOOP before changing detection thresholds. Never backdate sleep without evidence.

- [ ] **BLOCKED (Ghidra sleep attribution)** Read-only callback trace `0x10721612c` → `0x1071e51dc` → generic Combine `Future` helper `0x10077e108` is documented in `docs/research/ghidra-findings-index-2026-11-15.md` (commit `b6bfa4b`). No sleep classifier or threshold was verified; inspect closure `0x10077e1cc` and establish ownership before any algorithm change. Research documentation only, not a code fix.

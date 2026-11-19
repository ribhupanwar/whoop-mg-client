# STRAP Remaining Work — Execution Batches (2026-11-18)

> Execution order for the remaining backlog. A batch is complete only after code review, focused tests, native iOS build, and device/data verification where required. Do not bulk-merge draft PR #46 or stale overlapping PRs. Preserve historical records, licensed fonts, and missing-data semantics.

## Batch 0 — Build gate (current)
- [x] **DONE (verified CI, 2026-11-18):** Compiler failures from [iOS run 44301004058](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44301004058) were addressed in `19e2334` (literal newline) and `f5253a3` (Swift key path/string escape), with further compiler fixes included in current `main` at `1da8a875`. Native iOS [run 44312264803](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44312264803) and tests [run 44312264814](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44312264814) both succeeded for `1da8a875`. Physical-device behavior remains **VERIFY**.
- [x] **DONE (verified CI)** Native iOS workflow for `454e0d5` succeeded ([run 44272815069](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44272815069)); matching tests workflow succeeded ([run 44272815052](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44272815052)). Later native iOS workflow for `9e73dfa` also succeeded ([run 44278555357](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44278555357)); tests on `9e73dfa` were cancelled, while the subsequent checklist-only `1182edb` tests workflow succeeded ([run 44278575375](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44278575375)). Physical-device verification remains **VERIFY**.
- [ ] **VERIFY (ongoing build gate):** Fix exact compiler/signing/package failures if future native runs fail; successful CI on `1da8a875` does not validate later revisions or device behavior.

- [x] **DONE (verified 2026-11-18):** Native iOS build, simulator tests and IPA packaging succeeded for `7a354408`: [iOS run 44289784088](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44289784088), [tests run 44289784107](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44289784107). The `Strap-unsigned-ipa` artifact (ID `14421547125`) and signing-entitlement artifact (ID `14422245658`) are present. This is an ad-hoc signed IPA requiring authorized SideStore/device re-signing; successful CI does not establish physical-device correctness.\n\n## Batch 1 — Reconcile Codex PR #46 safely
- [ ] **PORTED TO MAIN (2026-11-18):** GPX/FIT export writer and focused tests copied selectively from PR #46; `GPSRunView` now exposes ShareLink export actions. CI validation pending; FIT output still requires independent third-party decoder/device validation. No synthetic HR/elevation/calories are added.
- [ ] Re-audit each changed file against current `main`; classify already-present, safe-to-port, conflicting, and obsolete.
- [ ] Integrate activity history/revisions and delete persistence without duplicate actions.
- [ ] Integrate GPX/FIT export and validate generated files.
- [ ] Integrate backup/export and prove restore round-trip before relying on it.
- [ ] Integrate RR archive without changing raw samples or fabricating beats.
- [ ] Integrate weekly alarm schedule; verify band vibration behavior separately.
- [ ] Keep PR #46 open until all remaining deltas are accounted for; never bulk merge.

- [ ] **VERIFY (GPS export duration guard, 2026-11-19):** `dd4c54c` rejects recorded moving time exceeding workout elapsed time before GPX/FIT generation; `0c3ada9` adds focused invalid/valid export regression. Native iOS CI [44333682628](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44333682628) succeeded on `0c3ada9`; later consolidated iOS [44341257763](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44341257763) and protocol tests [44341257852](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44341257852) succeeded on `ae7fbdc`, and tests [44356133442](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44356133442) succeeded on checklist-only `0ce1c534`. Thus code/CI is verified; independent FIT decoder and iPhone interoperability remain VERIFY. Existing GPS records are never rewritten.\n\n## Batch 2 — Sleep detection and staging
- [ ] Use timestamped WHOOP/STRAP same-night captures and diagnostic CSV pre-onset records to investigate onset delay; change detector thresholds only when evidence supports it.
- [ ] Validate bathroom awakenings, short wake gaps, sustained wake tails, lying-awake false positives, and sleep end-time stability.
- [ ] Validate stage boundaries and hypnogram against reference nights; preserve unknown/unclassified gaps.
- [ ] Verify manual start/end edits restage from retained sensor data and persist after relaunch.
- [ ] Verify Sleep Performance, Sleep Consistency, Efficiency and Recovery-dependent outputs recalculate from corrected bounds, or abstain when coverage is insufficient.

- [ ] **VERIFY (CI/device, 2026-11-19):** `ff208072` preserves physiologically quiet post-bathroom band-up tails instead of forcing wake stages. Native iOS run [44452935076](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44452935076) failed one stale assertion in `SleepBandStateIndependenceTests` (530 unit tests, 1 failure; three UI tests passed), while protocol run [44452935075](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44452935075) passed. `2c0ad63` updates the regression to distinguish a quiet latched five-minute up hint from five minutes of corroborated dynamic wrist motion. Native CI for this test correction and real-device wake/stage accuracy remain VERIFY; do not claim sleep accuracy is fixed.\n
## Batch 3 — Health and sensor accuracy
- [ ] Validate Type-40 and V18 RR units/offsets against timestamped CRC-checked WHOOP BLE captures and an independent beat reference.
- [ ] Validate V20/V21/V26 record handling using real fixtures; no automatic persistent R22 writes.
- [ ] Compare morning HRV/RHR and live HRV against the same WHOOP window; deduplicate replay while preserving raw archive.
- [ ] Validate Strain/calories and activity HR summaries against reference workouts.
- [ ] Validate SpO2 and respiratory-rate source mapping against independent overnight references; show unavailable rather than inferred values.

## Batch 4 — WHOOP UI fidelity
- [ ] **VERIFY (device screenshot, 2026-11-19):** Latest ring diameter correction `ebf13f7` removes the extra half-stroke padding from `RingView`, so its `size` frame is not inadvertently expanded by padding. Native iOS [run 44461395186](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44461395186) and protocol [run 44461395108](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44461395108) succeeded for the exact `ebf13f7` main revision. Code/CI are verified, but 104pt outer-circle geometry, digit sizes, labels and color parity still require same-device WHOOP/STRAP screenshot measurement. Preserve licensed fonts and actual score colors; no physiological metrics changed.\n\n
- [ ] Compare supplied same-screen WHOOP/STRAP screenshots on the target iPhone.
- [ ] Tune Home cards, rings, gradients, typography, spacing, navigation, Health charts, sleep-stage timeline and detail screens.
- [ ] Preserve licensed Proxima Nova/DIN Pro files and metric-derived zone colors.
- [ ] Add screenshot/layout/accessibility regression tests; verify VoiceOver and tap targets.

- [ ] **VERIFY (Batch 4 screenshot audit, 2026-11-18):** Compared same-night STRAP/WHOOP Home and sleep detail screenshots. Home rings show different *measured* values (STRAP sleep 91%, recovery 67%, strain 0.0; WHOOP sleep 78%, recovery 69%, strain 0.1); do not change zone colors to disguise measurement discrepancies. STRAP shows Health Monitor 'baseline pending' and Stress 'unavailable' versus WHOOP 5/5 and Low; this is a data/baseline issue, not a cosmetic fix. WHOOP's Home places My Day after a large notice and uses a 4-item navigation bar; STRAP currently displays a different Home layout/navigation. Sleep-stage totals differ (STRAP Deep 1:05, REM 2:20; WHOOP Deep 1:59, REM 1:43), requiring sensor/model validation before graphical tuning. Existing canvas, licensed fonts, accessibility tabs, and chart fixes remain preserved. Next: measured device screenshot baselines for header/rings, Health cards, activity card and bottom nav; verify target product tab requirements before changing navigation. No duplicate implementation or arbitrary health-value/color overrides.\n
## Batch 5 — Data safety and daily workflows
- [ ] **VERIFY (device, 2026-11-19):** `29bdc858` guards live HR activity save/delete against unreadable or wrong-type `strap.live.sessions.v1` archives, preserving original bytes rather than replacing history with an empty list. `60bca617` adds focused corrupted JSON/wrong-type regression tests. Native iOS workflow [44419001281](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44419001281) succeeded on `60bca617`; subsequent full protocol matrix [44419016515](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44419016515) succeeded on checklist-only `82408d9`. The earlier tests workflow [44419001217](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44419001217) was cancelled due to overlapping pushes, not an established test failure. Physical-device save/delete/relaunch persistence remains VERIFY; no persisted schema changes.

- [ ] **VERIFY (device, 2026-11-19):** `47fc011` prevents activity deletion or replay from overwriting unreadable detected-session/tombstone archives; `1d6a9fb` adds two corruption-preservation regression tests. Native iOS CI [44388909873](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44388909873) succeeded on `1d6a9fb`, validating code/build/tests, but physical-device delete/replay remains VERIFY. Protocol matrix [44388925906](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44388925906) still concluded cancelled on attempt 2 (macOS Python 3.11 cancelled; other five jobs passed). Subsequent `main` revision `0efb909` passed the complete six-job protocol matrix in [run 44399091512](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44399091512) on 2026-11-18 UTC. This validates automated protocol tests, not device deletion/replay. No persisted schema changes.\n
- [x] **DONE (existing code/tests)** Full-backup export and fresh-container restore, repeated import, rollback, interrupted restore, checksum validation and existing-raw-second/manual-correction preservation are already covered in `StrapBackup.swift` and `StrapBackupTests.swift`. Do not rebuild these paths.
- [ ] **VERIFY (device)** Confirm a backup generated by the current installed IPA can be imported after uninstall/reinstall; a simulator test is not proof of iPhone restore success. Preserve a second external copy before uninstall.
- [ ] **VERIFY (coverage)** Confirm actual export/restore inclusion of sleep, activities, raw RR, GPS, alarms and manual corrections, including file-by-file inventory; existing synthetic tests cover some but not necessarily every subsystem.
- [ ] Verify activity duplicate prevention, swipe/long-press deletion, GPS history and GPX/FIT exports on device; preserve already-implemented actions.
- [ ] Verify weekly alarm schedules and physical band vibration on hardware.
- [ ] Verify empty/loading/error/offline states and profile/device settings.
- [ ] **VERIFY (device, 2026-11-19; CI passed):** Backup ZIP path normalization tightened in `2272381`: reject empty components, `.`/`..`, backslashes and control characters before extraction; regression assertions added in `93c33cc`. Native iOS workflow [44470763516](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44470763516) succeeded on `93c33cc`; protocol tests workflow [44470778171](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44470778171) succeeded on checklist-only `29d1492`. Existing 2 GB extraction cap, manifest checksum validation and staging cleanup remain intact. Physical-device restore and adversarial archive coverage remain VERIFY. No persisted schema or existing data changed.
- [ ] **VERIFY (CI/device, 2026-11-19):** ZIP restore directory-entry preflight now rejects unsupported roots, traversal, empty components, control characters, and capture-file-shaped directories before extraction (code commits `d3d1544`, `c062599`; focused regression `5736c80`). No backup schema, historical data or licensed fonts changed. Native iOS CI and adversarial archive/device restore remain VERIFY; this is not proof of complete ZIP hardening.
- [ ] **SECURITY (remaining audit)** Verify compressed ZIP entry metadata edge cases, decompression limits and restore staging cleanup with adversarial archives; do not modify historical data while investigating.

## Batch 6 — Release acceptance
- [ ] **PR reconciliation (audited 2026-11-18):** 22 open PRs remain. Draft #46 is 30 commits ahead / 83 behind main, 73 changed files; #37 is 2 ahead / 264 behind, 7 files; #35 is 79 ahead / 281 behind, 59 files. Their overlapping work requires file-by-file review, not bulk merge or blind closure.
- [x] **Automated tests (current audit commit's parent):** tests run [44285013778](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44285013778) passed on `51dbb647`. Earlier native iOS run [44278555357](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44278555357) passed on `9e73dfa` only; not proof that the latest main packages successfully.
- [ ] Run full tests and native IPA workflow on final main commit; verify artifact availability, signing and fonts/entitlements.
- [ ] Install IPA on target iPhone; verify BLE reconnect, sleep edit/relaunch, activity delete, export/restore and screenshots.
- [ ] Do not mark release complete while Sleep/Health accuracy and device acceptance are unresolved.

---

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

- [ ] **VERIFY (Sleep alias overflow / makeAll)** Legacy or corrupted `Int.min`/`Int.max` correction keys previously reached unchecked `abs(source - period.startUnix)` in `SleepSession.makeAll`. Replaced with overflow-safe shared source distance (`2c17238`) and regression (`262a83c`); CI/device verification pending. No historical overrides removed.

- [ ] **VERIFY (Batch 2 / sustained mid-night wake)** Real 2026-11-18 sensor CSV has a 16-minute V18 band-state=3 interval (04:31–04:47 local) while the estimated hypnogram still labels portions deep/light. Added a conservative stager override: only well-covered (>=80%) contiguous state=3 runs of >=5 minutes are labelled wake; 2–4 minute bathroom/movement intervals do not force wake. Commits `0a1dbe2`, tests `227f129` and `256353a`. CI and comparison with actual wearer/reference sleep diary pending; this is a heuristic, not PSG truth.

- [ ] **VERIFY (pre-sleep diagnostic archive source, 2026-11-18)** Export UI already passed 30-minute lookback, but `BandLink.exportSleepDiagnostics()` previously supplied only the recent in-memory analysis window, yielding CSV starting at detected onset. Commit `9e73dfa` now reads the exact [onset - 30 min, sleep end] range from durable SQLite via `archiveWriter.samples`, merges with retained samples, then exports without altering detected sleep bounds. Verify on-device that CSV contains earlier rows when archive has them; if absent, investigate BLE offload/history availability rather than backdating sleep.

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

## 2026-11-18 execution update — selective PR #46 port (VERIFY, not DONE)
- [x] **CODE PORTED:** GPX/FIT route export writer, export tests and saved-GPS-run ShareLink UI are on main (`a26a8bc`, `c9c159a`, `4164cbf`); generated FIT still needs independent decoder/device validation. No synthetic HR, elevation or calories are added.
- [x] **CODE PORTED:** Manual activity revision archive before edit/delete, strict decoding that refuses to overwrite corrupt history, missing-only recovery, merge/undo with originals retained, history/revision preview and recovery entry points (`c0b23a8`, `660465a`, `01b6d67`, `41cd67e`, `a541f90`, `b125894`).
- [x] **CODE PORTED:** Activity edit sheet preserves existing identity/date and does not dismiss on failed persistence (`d09fd52`, corrected initialization/persistence in `63da9ba`).
- [ ] **VERIFY / CI:** Current main commit `63da9ba` is under native iOS and automated test workflows: [iOS run 44301004058](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44301004058), [tests run 44301004034](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44301004034). Prior test run `44300795448` passed before the final edit-sheet correction; do not treat it as verification of `63da9ba`.
- [ ] **VERIFY / DEVICE:** Install the resulting IPA and test add/edit/delete, corrupt-store fail-safe, restore missing entry, merge/undo, and GPX/FIT export on the target iPhone.
- [ ] **NOT YET PORTED:** RR raw archive integration and weekly alarm schedule from PR #46 remain pending; inspect current main and port only if not already present. Band vibration requires hardware verification.

## 2026-11-18 latest main CI verification (ae7fbdc)
- [x] **DONE (verified CI):** Native iOS workflow [44341257763](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44341257763) rerun completed successfully: simulator build, unit tests, IPA archive/package, bundled licensed fonts, HealthKit entitlement checks, and artifact uploads all succeeded. This verifies the `ae7fbdc` production revision including 104pt Home ring layout and sleep-stage display rounding; it does not establish visual pixel parity or sleep physiology accuracy.
- [x] **DONE (verified CI):** Protocol workflow [44341257852](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44341257852) completed successfully in all six OS/Python matrix jobs.
- [ ] **VERIFY (device):** Compare Home ring geometry and sleep-stage display against WHOOP screenshots on target iPhone. Sleep onset discrepancy, sensor stage classification, HRV/RHR accuracy, manual edit recalculation, and restore after reinstall remain unverified.
- [ ] **VERIFY (interoperability):** Validate GPX/FIT exports with an independent FIT decoder and actual workout records; successful build is not external file compatibility proof.

- [ ] **VERIFY (sleep wake corroboration, 2026-11-19):** Recent sleep detector changes `08994457` (measured dynamic acceleration), `baee7502` (sustained HR elevation), `a8cf6f1b` (sticky transition guard) and focused boundary tolerance regression `77aadf85` are present on `main`. Native iOS workflow [44448858902](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44448858902) and protocol tests [44448858972](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44448858972) both succeeded for `77aadf85`. Earlier intermediate iOS runs [44442879390](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44442879390) and [44446246179](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/44446246179) failed; latest passing run supersedes their build gate, but device sleep timing, false-positive awake detection, stages and recovery recalculation remain VERIFY/BLOCKED pending same-night sensor reference. No physiological accuracy claim from synthetic tests.

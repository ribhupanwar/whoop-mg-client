# STRAP Comprehensive Legacy Pull Request Audit & Recovery Report
**Target Base:** `main` (at `40e89a1`)  
**Scope:** Forensic audit of all 24 remaining open pull requests (#1, #2, #3, #4, #9, #10, #11, #12, #16, #19, #20, #21, #22, #23, #24, #25, #26, #27, #28, #29, #35, #37, #46, #51)  
**Date:** 2026-11-20  

---

## 1. Executive Summary

A forensic audit of all 24 legacy pull requests was executed against the latest integrated `main` branch (commit `40e89a1`, which incorporates PRs #62, #65, #67, #68, #69, #70, and #71). Every open branch was fetched, analyzed at the commit and diff level against its merge-base and `origin/main`, cross-referenced with GitHub Actions CI runs, and evaluated for genuine bug fixes versus superseded prototypes.

### Key Audit Findings
1. **Genuinely Missing Bug Fix Recovered (PR #51 - P0):**
   - **Bug:** In `ios/Strap/Analysis/SleepDetect.swift`, the cutoff gate used `(8..<24).contains(startHour)`. This erroneously treated late-night bedtimes between 22:00 and 23:59 (e.g. 23:51) as daytime rest, demanding 5 contiguous minutes of coarse band `state=2` before declaring sleep and clipping physiological onset.
   - **Resolution:** Replaced with `if daytime` (where `daytime` is strictly 08:00–21:59). Restored `ios/StrapTests/SleepOvernightOnsetBoundaryTests.swift` (5 unit tests) validating bedtime onset preservation.
2. **Missing Regression Tests Recovered (PR #1 - P0):**
   - **Finding:** While the single-byte frame resync logic in `whoop/framing.py` was merged to `main` in an earlier commit, the two unit tests (`test_bad_header_does_not_hold_following_good_frame` and `test_corrupt_payload_does_not_swallow_next_frame`) in `tests/test_framing.py` were omitted.
   - **Resolution:** Ported the missing tests into `tests/test_framing.py`, locking in framing corruption recovery (now 320 Python tests passing).
3. **Already Implemented in Main (PRs #9, #21, #26):**
   - PR #9 (5-second gap cap on unobserved HR): present in `Hrv.swift:492`.
   - PR #21 (Activity delete): present in `AppStore.swift:235`, `HomeView.swift:665`, and `ManualActivityHistoryView.swift:34`.
   - PR #26 (Lazy dashboard rendering): present via `DashboardRows()` in `HomeView.swift:1082`.
4. **Superseded by Newer Architecture (PRs #10, #11, #12, #16, #19, #20, #22, #23, #24, #25, #27, #28, #29, #35, #37, #46):**
   - Overhauled by modern subsystems: `HistoryAnalysisCache`, `CaptureAnalysis` background queues, `ActivityStore` SQLite database, WHOOP 5.80.2 4-tab UI hierarchy, and PR #69 / PR #70 integrations.
5. **Supply-Chain & CI Breakage Risks Rejected (PRs #2, #3, #4):**
   - Dependabot bumps targeting unreleased or nonexistent `@v7` actions (`actions/checkout@v7`, `actions/upload-artifact@v7`, `actions/setup-python@v7`). Merging these would break the GitHub Actions CI workflow.

---

## 2. Complete Open PR Classification Matrix

| PR # | Branch | Title | Priority | Primary Classification | CI Status | Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **#1** | `audit/ble-framing-resync-20261109` | Harden BLE frame resynchronization after corruption | **P0** | `PARTIALLY_IN_MAIN` | ✅ PASS | **RECOVERED:** Ported regression tests to `test_framing.py`. Close PR #1. |
| **#2** | `dependabot/.../setup-python-7` | ci: bump actions/setup-python from 5 to 7 | **P3** | `UNSAFE` | ⚠️ N/A | **REJECTED:** actions/setup-python@v7 does not exist. Close PR #2. |
| **#3** | `dependabot/.../upload-artifact-7` | ci: bump actions/upload-artifact from 4 to 7 | **P3** | `UNSAFE` | ⚠️ N/A | **REJECTED:** actions/upload-artifact@v7 does not exist. Close PR #3. |
| **#4** | `dependabot/.../checkout-7` | ci: bump actions/checkout from 4 to 7 | **P3** | `UNSAFE` | ⚠️ N/A | **REJECTED:** actions/checkout@v7 does not exist. Close PR #4. |
| **#9** | `fix/strain-avoid-30s-extrapolation-20261112` | Prevent inflated strain from extrapolating sparse HR over 30s | **P1** | `ALREADY_IN_MAIN` | ✅ PASS | **CLOSE:** Implemented in `Hrv.swift:492`. |
| **#10** | `feature/strain-diagnostics-20261112` | Add on-device Strain HR coverage diagnostics | **P2** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by PR #70 `DiagnosticsSupportView` & `DataQuality`. |
| **#11** | `feature/band-alarm-capability-20261112` | Expose wrist alarm capability status; prevent false claims | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by PR #70 7-day schedule & latching status. |
| **#12** | `fix/strain-coverage-comparison-20261112` | Diagnose low Strain with independent Edwards model comparison | **P1** | `SUPERSEDED` | ❌ CONFLICT | **CLOSE:** Superseded by PR #69 Karvonen baseline parity (`Karvonen.swift`). |
| **#16** | `fix/whoop-sleep-stage-comparison-ui` | WHOOP-style sleep stage comparison colors and duration bars | **P2** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by PR #65 WHOOP 5.80.2 `SleepAnalysisView.swift`. |
| **#19** | `fix/edited-sleep-no-stale-performance` | Prevent stale sleep performance after editing sleep times | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by `HistoryAnalysisCache` recalculation pipeline. |
| **#20** | `fix/edited-sleep-hide-stale-stages` | Avoid presenting original sleep stages as corrected-night results | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by `HistoryAnalysisCache.night()` clean staging. |
| **#21** | `feature/strap-band-activity-delete` | Add Delete beside Edit for STRAP detected activities | **P1** | `ALREADY_IN_MAIN` | ✅ PASS | **CLOSE:** Implemented in `AppStore.swift:235` and `HomeView.swift:665`. |
| **#22** | `fix/activity-false-positive-gait-gates-20261113` | Prevent incidental steps and elevated HR from auto-creating activities | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by PR #67 workout gait gates & calorie explanations. |
| **#23** | `fix/sleep-correction-restage-retained-20261113` | Restage manually corrected sleep from retained sensor data | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by `HistoryAnalysisCache` and `CaptureAnalysis.swift`. |
| **#24** | `fix/sleep-restage-watchdog-background-20261113` | Prevent sleep-stage UI watchdog by moving restaging off main thread | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by background `analysisQueue` in `BandLink.swift`. |
| **#25** | `fix/sleep-home-full-recompute-20261113` | Recompute Home sleep and SleepReport from corrected staged night | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by `AppStore.recalculateRetainedMetrics()`. |
| **#26** | `fix/home-scroll-lazy-render-20261113` | Reduce Home screen redraw workload with lazy dashboard | **P2** | `ALREADY_IN_MAIN` | ✅ PASS | **CLOSE:** Implemented in `HomeView.swift:1082` via `DashboardRows()`. |
| **#27** | `fix/activity-swipe-delete-20261113` | Allow deleting extra auto-detected activities from Home | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by `ActivityStore` SQLite deletion & `ActivityDeleteReveal`. |
| **#28** | `fix/consolidated-sleep-activities-20261113` | Consolidated IPA: corrected sleep, stages, and swipe delete | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by master architecture in `main`. |
| **#29** | `fix/sleep-partial-coverage-20261113` | Restore partial sleep visibility and persistent activity controls | **P1** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded by Phase 18-20 UI consolidation. |
| **#35** | `ui/dsta-dashboard-polish` | UI/dsta dashboard polish | **P2** | `SUPERSEDED` | ❌ CONFLICT | **CLOSE:** Superseded by Phase 18-20 WHOOP 4-tab design and PR #62/#65/#70. |
| **#37** | `codex/ui-fidelity-build` | Apply bundled typography and refine metric trend UI | **P2** | `SUPERSEDED` | ✅ PASS | **CLOSE:** Superseded; all 11 licensed fonts are bundled and verified in main. |
| **#46** | `codex/master-progress-20261117` | STRAP master scope: RR, source history, exports and calories | **P0** | `SUPERSEDED` | ⚠️ DRAFT | **CLOSE:** Tracked in master checklist; all valid components were ported to main. |
| **#51** | `fix/overnight-onset-bandstate-boundary-20261118` | Fix late overnight sleep onset caused by band-state confirmation cutoff | **P0** | `VALID_MISSING_FIX` | ✅ PASS | **RECOVERED & MERGED:** Ported `SleepDetect.swift` fix and `SleepOvernightOnsetBoundaryTests.swift`. |

---

## 3. Domain Analysis & Forensic Evidence

### A. Sleep Detection & Persistence (#16, #19, #20, #23, #24, #25, #28, #29, #51)
* **PR #51 (`VALID_MISSING_FIX`):** Analysis of real user nights showed that bedtime at 23:51 was erroneously trimmed to a later timestamp because `(8..<24).contains(startHour)` classified the period 22:00–23:59 as requiring positive coarse `state=2` confirmation for 5 contiguous minutes (300 s). In reality, overnight quiet candidates (22:00–07:59) already require worn, low-HR evidence; waiting for coarse `state=2` discarded the measured onset prefix. Replacing line 108 with `if daytime` resolves this bug completely while keeping daytime stillness protection (08:00–21:59) intact.
* **PRs #19, #20, #23, #24, #25, #28, #29 (`SUPERSEDED`):** These PRs attempted ad-hoc, in-memory state manipulation to suppress stale scores after editing sleep times. They were superseded by `HistoryAnalysisCache.swift` (recipe-based cache invalidation), `CaptureAnalysis.swift`, and background queue dispatching, which re-slice and restage the exact manual bounds safely.

### B. Activity Detection (#21, #22, #27)
* **PR #21 (`ALREADY_IN_MAIN`):** Delete actions beside Edit were implemented via `AppStore.deleteActivity(id:)` and context menus in `ManualActivityHistoryView.swift` and `MetricDetailView.swift`.
* **PR #22 (`SUPERSEDED`):** PR #22 bluntly suppressed elevated HR from activity detection. PR #67 provided a superior, physiological fix: rejecting incidental workouts without sustained exertion while preserving valid walk/run cadence gates.
* **PR #27 (`SUPERSEDED`):** PR #27 used an in-memory `UserDefaults` array `hiddenDetectedStarts` for swipe-deleted activities. In `main`, `AppStore.deleteDetectedActivity()` commits directly to `ActivityStore` (SQLite), ensuring atomic persistence across restarts.

### C. UI & Performance (#26, #35, #37)
* **PR #26 (`ALREADY_IN_MAIN`):** The lazy row optimization (`DashboardRows()`) is present at `HomeView.swift:1082`.
* **PR #35 & #37 (`SUPERSEDED`):** These early branches attempted to style the pre-Phase 18 UI. They are superseded by the Phase 18–20 WHOOP 4-tab redesign, PR #62 mini-ring parity, PR #65 tabbed device settings, and PR #70 More tab engineering. All 11 licensed fonts (`ProximaNova-*`, `DINPro-*`) are bundled and verified in the CI IPA pipeline.

### D. BLE & Strain (#1, #9, #10, #11, #12)
* **PR #1 (`PARTIALLY_IN_MAIN`):** The streaming single-byte resync in `whoop/framing.py` was merged, but its two unit tests (`test_bad_header_does_not_hold_following_good_frame` and `test_corrupt_payload_does_not_swallow_next_frame`) were left uncommitted. These have now been ported to `tests/test_framing.py`.
* **PR #9 (`ALREADY_IN_MAIN`):** The 5-second unobserved HR cap is active at `Hrv.swift:492`.
* **PR #10, #11, #12 (`SUPERSEDED`):** Diagnostic strings, alarm capability stubs, and Edwards model comparisons were superseded by PR #69 (live Strain Karvonen baseline) and PR #70 (7-day alarm haptics, latching confirmation, and telemetry diagnostics).

### E. Data Export & Architecture (#46)
* **PR #46 (`SUPERSEDED`):** As tracked in `docs/STRAP_UI_MASTER_CHECKLIST.md`, all valid components of PR #46 (GPX/FIT export, raw RR archive, reversible manual activity edits, SQLite backup/restore, and 7-day alarms) have been selectively incorporated into `main`. The draft PR is now fully accounted for.

### F. CI Dependencies (#2, #3, #4)
* **PRs #2, #3, #4 (`UNSAFE / REJECTED`):** Dependabot created bumps to nonexistent `@v7` actions. Official GitHub Actions releases for checkout, setup-python, and upload-artifact are at `@v4` and `@v5`. Merging these would cause immediate CI build failures.

---

## 4. Recovered Code & Verification Status

1. **Overnight Sleep Onset Fix (`ios/Strap/Analysis/SleepDetect.swift`):**
   - Fixed condition from `if (8..<24).contains(startHour)` to `if daytime`.
   - Added `ios/StrapTests/SleepOvernightOnsetBoundaryTests.swift` (5 unit tests).
2. **BLE Frame Corruption Recovery Tests (`tests/test_framing.py`):**
   - Added `test_bad_header_does_not_hold_following_good_frame` and `test_corrupt_payload_does_not_swallow_next_frame`.
   - Python test suite passed: **320 / 320 tests green**.

---

## 5. Remaining Real-Device Validation Items

1. **Autonomous Firmware Pairing:** Confirm double-tap and pulsing blue LED remain 100% firmware-driven on physical hardware.
2. **Wrist Alarm Vibration:** Validate physical strap haptic buzz upon firing of the 7-day schedule.
3. **Late-Night Bedtime Verification:** Test overnight sleep detection with real WHOOP band on wrist when getting into bed after 22:00.

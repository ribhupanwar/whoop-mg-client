# STRAP Multi-PR Reconciliation Audit & Strategy
**Target Branch:** `main` (commit `650fce7` with PR #69 merged)  
**PR Scope:** PR #62, PR #65, PR #67, PR #68, PR #70  
**Date:** 2026-11-20  

---

## 1. Executive Summary & Inventory

This document defines the reconciliation, conflict matrix, and safe integration plan for merging five parallel PRs into `origin/main`. PR #69 (`feat(forensics): WHOOP 5.80.2 Domains E-J deep forensics and live strain Karvonen baseline parity`) is already merged into `main` at `650fce7`.

### PR Inventory

| PR # | Branch | Title | Files Changed | CI Status |
| :--- | :--- | :--- | :--- | :--- |
| **#67** | `fix/activity-false-workout-calories-profile` | fix(activity/calories): guard incidental workouts and explain missing energy inputs | 3 files (+59, -1) | ✅ PASS (build-test-ipa, protocol-tests, CodeRabbit) |
| **#62** | `fix/home-ring-compact-parity-58` | fix(home): align sticky mini-ring colors and scores with hero rings (#58) | 1 file (+15, -4) | ✅ PASS (build-test-ipa, protocol-tests) |
| **#65** | `research/whoop-5802-device-parity` | feat(device): WHOOP 5.80.2 Ghidra reverse engineering, device settings parity, and regulatory labels | 11 files (+2128, -299) | ✅ PASS (build-test-ipa, protocol-tests, CodeRabbit) |
| **#68** | `fix/device-settings-actions-strain-live-20261120` | fix(device): wire unpair, serial ID and official regulatory actions | 1 file (+36, -13) | ✅ PASS (build-test-ipa, protocol-tests) |
| **#70** | `feature/strap-more-openstrap-noop-audit` | feat(more): complete More tab engineering, OpenStrap Edge audit, 7-day alarms & reconnect policy | 13 files (+1987, -151) | ⚠️ PENDING/FAIL (run 44700944167 had Swift compilation errors in MoreDetailViews.swift) |

---

## 2. Overlap & Conflict Matrix

| Target File | PRs Touching File | Functional Overlap | Conflict Risk & Resolution Strategy |
| :--- | :--- | :--- | :--- |
| `ios/Strap/HomeView.swift` | **PR #62**, **PR #68**, **PR #69 (main)** | - PR #62 updates `compactRingRow` (sticky header mini-rings palette/progress).<br>- PR #68 updates `HomeBandDeviceSettingsView` (unpair, serial, regulatory).<br>- PR #69 updated hero ring strain labels. | **LOW / AUTOMATIC RESOLUTION:** The edits occur in separate subviews/line ranges. Git merges cleanly; ensure both mini-ring palette and device settings unpair sheet are preserved. |
| `ios/Strap/Band/BandLink.swift` | **PR #70**, **PR #69 (main)** | - PR #69 added Karvonen live strain resting HR baseline fallback.<br>- PR #70 added `ReconnectBackoffPolicy`, packet diagnostic counters, and wake alarm latching confirmations. | **LOW / RESOLVED:** Merged into shared `BandLink.swift`. Additionally make `hrBondConfirmed` accessible (`@Published private(set) var hrBondConfirmed`) for `DiagnosticsSupportView`. |
| `ios/Strap/DeviceSettingsView.swift` | **PR #65**, **PR #68** (via HomeView sheet), **PR #70** (via MoreView row) | - PR #65 created tabbed STATUS and ADVANCED settings with battery health, maintenance, and `RegulatoryLabelsView`.<br>- PR #68 enabled unpair and official regulatory link.<br>- PR #70 wired MoreView to `DeviceSettingsView` with serial number subtitle. | **MEDIUM / ALIGNED:** Reconcile so `DeviceSettingsView` uses real serial number, official regulatory information, and safe unpairing while maintaining prohibited BLE command quarantine. |
| `docs/research/whoop_5802/` | **PR #65**, **PR #69 (main)**, **PR #70** | - PR #69 added Domains E-J forensic markdown reports.<br>- PR #65 added `strings_5802.json` and `symbols_5802.json`.<br>- PR #70 added `MORE_TAB_GHIDRA_FORENSICS.md` and `more_tab_binary_matches.json`. | **ZERO:** All filenames are distinct within `docs/research/whoop_5802/`. |
| `ios/Strap/Analysis/Activities.swift` & `ios/StrapTests/ActivityTests.swift` | **PR #67** | - Guard incidental low-cadence workouts without sustained exertion.<br>- Profile explanation for missing calorie inputs. | **ZERO:** Isolated exclusively to PR #67. |
| `ios/Strap/SleepAnalysisView.swift` & `SleepStageDisplayTests.swift` | **PR #65** | - Sleep detail screen WHOOP screenshot fidelity, typical range overlays. | **ZERO:** Isolated exclusively to PR #65. |
| `ios/Strap/WakeAlarm.swift` & `ReconnectBackoffPolicy.swift` | **PR #70** | - 7-day schedule, band latching status, reconnect backoff. | **ZERO:** Isolated exclusively to PR #70. |

---

## 3. CodeRabbit Findings & Fixes Required

1. **`ios/Strap/ImportHistoryView.swift` (PR #70):**
   - *Finding:* DatePickers should include hour and minute components (`.displayedComponents: [.date, .hourAndMinute]`) so users can adjust exact timestamps used by `AppleHealthImport.run`.
   - *Finding:* Clarify text description to state that Apple Health records are stored and count is displayed, without claiming they alter band measurements or RMSSD Recovery inputs.
   - *Resolution:* Addressed during PR #70 integration.

2. **`ios/Strap/MoreDetailViews.swift` (PR #70):**
   - *Finding:* `HistoryProgress.Stage` has no `.title` property (`enum Stage: String { case preparing, nights, days, finishing }`). Use `.rawValue.capitalized`.
   - *Finding:* `hrBondConfirmed` in `BandLink` was `private var hrBondConfirmed = false`. Change to `@Published private(set) var hrBondConfirmed = false`.
   - *Finding:* Unused variable warning in `if alarmOn, let next = nextWake` -> change to `_ = nextWake`.
   - *Resolution:* Fixed during PR #70 integration.

3. **`ios/Strap/DeviceSettingsView.swift` (PR #65):**
   - *Finding:* Firmware check placeholder should be marked informational or disabled to prevent claiming a firmware check succeeded when not supported.
   - *Resolution:* Preserved with clear informational messaging that custom firmware updates are restricted to official signed binaries to prevent bricking.

---

## 4. Reconciled Merge Order

1. **Step 1: Merge PR #67 (`fix/activity-false-workout-calories-profile`)** — Isolated algorithm & test fixes; zero conflicts with main.
2. **Step 2: Merge PR #62 (`fix/home-ring-compact-parity-58`)** — Mini-ring color & score alignment in `HomeView.swift`.
3. **Step 3: Merge PR #65 (`research/whoop-5802-device-parity`)** — Tabbed `DeviceSettingsView`, `RegulatoryLabelsView`, and sleep analysis improvements.
4. **Step 4: Merge PR #68 (`fix/device-settings-actions-strain-live-20261120`)** — Reconcile device settings unpair and serial number in `HomeView.swift`.
5. **Step 5: Merge PR #70 (`feature/strap-more-openstrap-noop-audit`)** — Integrate More tab, 7-day alarms, reconnect backoff policy, and apply the fixes for `MoreDetailViews.swift` & `ImportHistoryView.swift`.
6. **Step 6: Run Full Combined Verification** — Unit tests, Python tests, IPA build checks.
7. **Step 7: Merge Reconciled Branch into `main`**.

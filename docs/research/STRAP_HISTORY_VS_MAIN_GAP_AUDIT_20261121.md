# STRAP — History-First Reverse Engineering Gap Audit (2026-11-21)

**Document ID:** `docs/research/STRAP_HISTORY_VS_MAIN_GAP_AUDIT_20261121.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Production Baseline:** `main` (commit `6fc386e8fb4d1259f43ec9aaf0d6ff9c6056892d`, including PR #112 & #113; pending PR #114 isolated)  
**Reference Repositories:** `ribhupanwar/dsta`, `ryanbr/noop`, `OpenStrap/edge`  
**Audited WHOOP Binaries:** WHOOP iOS 5.78.0 (Build 772673, Mach-O ARM64) & WHOOP iOS 5.80.2 (Build 209853712 bytes)  
**Audit Objective:** Perform a forensic, history-first comparison of all existing research findings against the active `main` codebase. Identify what has already been solved, resolve documentation/code contradictions, and define exactly what genuinely remains to be reverse-engineered or hardware-validated.

---

## 1. Executive Summary

Over 20 research phases and 113 pull requests, the STRAP project has accumulated extensive binary analysis, BLE packet captures, CoreData schema extracts, and physiological modeling. However, historical research documentation has occasionally drifted from active production code, leading to repeated investigations of already-solved problems or attempts to implement server-side cloud models that do not exist in the iOS binary.

This audit establishes the definitive baseline by reconciling:
1. **The Architectural Boundary:** Proving where WHOOP client code ends and cloud/firmware code begins. The iOS companion app is a telemetry collector, presentation engine, and live accumulator; sleep staging (Wake/Light/SWS/REM), nocturnal RMSSD/RHR gating, recovery score percentages, and VO₂ Max regression are cloud-evaluated.
2. **The 21:00 vs 22:00 Sleep Onset Contradiction:** Resolving the apparent conflict between research documents claiming a 21:00 cutoff fix and `SleepDetect.swift` using `(8..<22).contains(startHour)`. Code review and git archeology prove that the 22:00 cutoff is **deliberate and protected by a regression test** to prevent early evening phone/reading stillness from generating false sleep onsets.
3. **The Recovery 43% vs 57% Discrepancy:** Proving that the divergence was caused by non-uniform baseline date-key deduplication and unanchored date selection across views, permanently resolved in PR #112 via `DatedRecovery` and `RecoveryDiagnostics.swift`.
4. **Wear-State & CapSense Realities:** Disproving the assumption that `WHPWhoopStrapCapSenseFailedNotification` is an iOS push notification. Binary analysis proves it is an internal `NSNotificationCenter` event for the interactive sensor cleaning/recalibration view controller (`CapSenseViewController`).
5. **Exact Delta Roadmap:** Identifying the 3 highest-value remaining engineering tasks that require attention without breaking existing invariants or licensed fonts.

---

## 2. Comprehensive Subsystem Comparison Table

The following ledger cross-references every historical research finding against current `main` code, commit hashes, test evidence, remaining gaps, and implementation classifications.

### Classification Key:
- **IMPLEMENTED AND VERIFIED:** Code exists on `main`, has automated test coverage, and passes CI.
- **IMPLEMENTED BUT DEVICE-UNVERIFIED:** Code and automated tests exist on `main`, but physical band hardware interaction remains to be validated.
- **PARTIALLY IMPLEMENTED:** Foundation or clean-room equivalent exists, but specific edge cases or hardware signals are pending.
- **RESEARCH ONLY:** Documented in research reports, but intentionally or unintentionally absent from production code.
- **CONTRADICTED BY CURRENT CODE:** Research claim is refuted by active code or protected by deliberate regression tests.
- **NOT IMPLEMENTED:** Known feature not yet present in codebase.

| Subsystem | Historical Finding & Evidence | Existing Code Location | Commit / PR | Test Evidence | Remaining Gap | Status | Priority |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :---: |
| **BLE Pairing & Double-Tap** | Double-tap pairing gesture (`0x0E`) and blue LED pulsing (`0x12`) are 100% firmware-autonomous; 0 app write commands exist (`WHOOP_5802_DEVICE_COMMANDS.md`). | `PairDeviceView.swift`, `BandLink.swift:150` | Commit `a8e6900`, PR #65/#68 | `test_device_control.py` (309 tests), `DeviceControlTests.swift` | None (Firmware autonomous). | **IMPLEMENTED AND VERIFIED** | Closed |
| **BLE Always-Connect & Reconnect** | Targeted UUID reconnection via `retrievePeripherals(withIdentifiers:)` with exponential backoff (`0x1000dfd6c`). | `BandLink.swift:230-310`, `ReconnectBackoffPolicy` | Commit `a8e6900`, PR #70 | `BandConnectionStateMachineTests.swift` (20x reopen cycles) | Background CoreBluetooth state restoration (`willRestoreState`) not implemented. | **PARTIALLY IMPLEMENTED** | P2 |
| **BLE Hardware Events** | Event opcodes on `fd4b0004`: `wristOn` (`0x09`), `wristOff` (`0x0A`), `doubleTap` (`0x0E`), `chargerAttached` (`0x15`). | `BandUUIDs.swift:58-73`, `BandLink.swift:2138` | PR #65, PR #110 | `ProtocolTests.swift` | `BandLink.swift:2138` only parses `bleHRProfileEnable` (`0x18`); opcodes `0x09`, `0x0A`, `0x15`, `0x16` are ignored. | **PARTIALLY IMPLEMENTED** | P1 |
| **CapSense & Optical Contact** | Dual-modality contact: optical backscatter + capacitive dielectric electrodes (`0x10965a8e0`). | `BandUUIDs.swift`, `V18Record.swift:53` | PR #69 | `ProtocolTests.swift` | `V18Sample.wearing` is simplified to `heartRate > 0`; hardware capacitive bit is not decoded. | **PARTIALLY IMPLEMENTED** | P2 |
| **CapSense Recalibration Notifications** | `WHPWhoopStrapCapSenseFailedNotification` (`0x10975d131`) and `SuccessNotification` (`0x10975d159`). | N/A (Diagnostic UI only) | N/A | N/A | None. Proven to be internal `NSNotificationCenter` events for diagnostic `CapSenseViewController`, not user notifications. | **RESEARCH ONLY** | Closed |
| **Status Envelope `wristState`** | Bitfield encoding battery tenths, charging, flash status, and `wristState` (`0x10bc3d110`, `0x10a3cd4f0`). | `BandLink.swift:2110` | Commit `b2bba8d` (PR #108) | `Gen5FrameTests.swift` | Decodes battery percent, but does not parse the `wristState` bitfield. | **PARTIALLY IMPLEMENTED** | P2 |
| **Historical Sync & Token ACKs** | Commit-then-confirm invariant: 8-byte token ACK sent on `inner[2] == historyEnd` (`0x02`) only after SQLite commit (`0x9777856`). | `BandLink.swift:1960-2010`, `HistoricalArchiveWriter.swift` | Commit `20e05ec` (PR #109), PR #108 | `test_ble_replay.py`, `HistoryDatabaseTests.swift` | Physical WHOOP band history drain validation on firmware 50.43.1.0 pending. | **IMPLEMENTED BUT DEVICE-UNVERIFIED** | P1 |
| **Resting Heart Rate (RHR)** | Basal RHR is evaluated as the lowest 5-minute rolling median during nocturnal quiet sleep (`0x100a80410`). | `Hrv.swift:45-90`, `SleepSession.swift` | Commit `9be53a9` (PR #106) | `AnalysisTests.swift`, `test_overnight_rhr_median_gates` (PR #107) | None (Clean-room equivalent verified against capture). | **IMPLEMENTED AND VERIFIED** | Closed |
| **HRV (RMSSD) SWS Epoch Gating** | Nightly RMSSD is calculated strictly during Slow-Wave Sleep (Deep Sleep) epochs, not whole-night average (`0x976d600`). | `Hrv.swift:110-165` (`swsRestingHRV`) | Commit `3535fba`, PR #80 | `AnalysisTests.swift`, `HrvTests.swift` | None (SWS epoch isolation with quiet-window fallback active). | **IMPLEMENTED AND VERIFIED** | Closed |
| **Recovery 43% vs 57% Discrepancy** | Unanchored baseline selection caused Home recovery (43%) to diverge from Sleep detail recovery (57%). | `RecoveryDiagnostics.swift`, `DatedRecovery.swift`, `MetricTimeline.swift` | Commit `6fc386e` (PR #112) | `MetricTimelineTests.swift`, `AnalysisTests.swift` | None. Resolved by unifying 28-day unique date keys and exporting provenance breakdown. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Recovery Tiers & IEEE-754 Bounds** | 5-case `RecoveryLevel` enum matching `0x10a0f2874`; exact double boundaries $\le 33.0$, $\le 66.0$, $> 66.0$ (`0x100041d3c`). | `AnalysisTypes.swift:40-65`, `Recovery.swift` | Commit `4f7f092`, PR #80 | `AnalysisTests.swift` | None. Full binary parity achieved. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Sleep Onset 21:00 vs 22:00 Cutoff** | Research doc claimed 21:00 cutoff was fixed, but code uses `(8..<22).contains(startHour)`. | `SleepDetect.swift:70,108` | Commit `c7f9ce0`, `840d66c` | `SleepOvernightOnsetBoundaryTests.swift:60` | Research document is stale. Code intentionally enforces 22:00 boundary to prevent pre-22:00 reading stillness false onsets. | **CONTRADICTED BY CURRENT CODE** | P0 (Doc fix) |
| **Sleep Bathroom Awakening Merging** | Nocturnal bathroom breaks $\le 30$ minutes merge into a single session; active exertion ($\ge 180$s HR $\ge 90$) rejects merging. | `SleepDetect.swift:342-395` (`mergeNocturnalPeriods`) | Commit `cd6e085`, `6091c4f` | `SleepBathroomBreakMergingTests.swift`, `SleepWakeTailBoundaryTests.swift` | None. Merging and exertion safeguards fully active. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Sleep Staging (REM vs Light)** | STRAP overestimated REM (+42m) due to $+1.0 \times \text{clock}$ prior inversion. Scaled to $0.60 \times \text{clock}$ (`WHOOP_SLEEP_STAGING_FORENSICS.md`). | `SleepStager.swift:145-210`, `whoop/sleep_stage.py` | Commit `c2af442` (PR #79) | `AnalysisTests.swift`, real sensor CSV replay | Cloud deep neural network weights unextractable; clean-room prior is verified. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Sleep Window Bounding** | Bounded to 12 hours maximum (`TWELVE_HOUR` in `SleepWindow.swift` at `0x98a4ae0`). | `SleepDetect.swift:15` (`maxSleepS = 12 * 3600`) | Commit `78cd773`, PR #80 | `AlgorithmParityTests.swift:8-9` | None. Window ceiling enforced. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Sleep Planner & Debt Compounding** | Imported adjusted sleep need was compounding into rolling debt repeatedly. | `AppStore.swift:265` | Commit `333b861` (PR #113) | `SleepCoachTests.swift` | None. Resolved on `main`. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Intelligent Activity Detection** | Multi-stage classifier: cadence $\ge 100$ SPM, elevated HR $\ge \max(100, \text{base}+20)$, duration $\ge 300$s with $\ge 240$s sustain. | `Activities.swift`, `ActivityStore.swift` | Commit `f1ea782` (PR #80) | `AnalysisTests.swift`, `ActivityDetectionTests.swift` | None. Casual walking false positives suppressed. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Activity Icon Taxonomy** | CoreML taxonomy with 64+ exercises; 125 public activity icons mapped (`ACTIVITY_ICON_PROVENANCE.md`). | `ActivityStore.swift`, `activity-icon-inventory.tsv` | Commit `9e9b6b8` (PR #111) | `ActivityIconRegistryTests.swift` (129 assertions) | None. Icon mapping and fallbacks verified. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Day Strain Accumulation** | Live strain accumulated from HR using 30s calibration (`0x1000ea038`); mapped via piecewise midpoint lookup (`0x1001efe44`). | `Strain.swift`, `DayStrainView.swift` | PR #80 | `AnalysisTests.swift` | Piecewise lookup table `strain_raw_scale_lookup.json` documented; Banister TRIMP exponential formulation currently active in STRAP. | **PARTIALLY IMPLEMENTED** | P2 |
| **Daytime Stress Monitoring** | 5-minute rolling HRV normalized against awake-quiet baseline; excludes sleep and active workouts (`0x10969fdd0`). | `StressWindows.swift`, `whoop/health.py` | PR #80 | `AnalysisTests.swift`, `CaptureCompatibilityTests.swift` | None. Clean-room equivalent verified. | **IMPLEMENTED AND VERIFIED** | Closed |
| **SpO₂, Respiration & Skin Temp** | Skin temp is on-band ADC (`RawDataRev10`); SpO₂ is candidate byte (cloud-calculated); respiration is RSA-derived. | `V18Record.swift`, `SleepStager.swift`, `Hrv.swift` | PR #80 | `ProtocolTests.swift`, `AnalysisTests.swift` | SpO₂ properly held as candidate; RSA model active; raw thermistor telemetry displayed as diagnostic. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Home Score Rings Geometry** | 84 pt outer diameter, 5.0 pt stroke, DIN Pro 22 pt bold digits with 72% percent sign baseline (`PHASE18_RING_CORRECTION_REPORT.md`). | `HomeView.swift:200-340`, `ScoreRing.swift` | Commit `971e51c` (PR #102) | `test_home_ring_geometry.py`, `HomeScoreRingTests.swift` | None. Pixel-matched to reference screenshots. | **IMPLEMENTED AND VERIFIED** | Closed |
| **Home Refresh Indicator** | Animate circular W indicator during pull-to-refresh; display WHOOP wordmark (`0x109153360`). | `HomeView.swift` | Commit `823d725` (PR #101), `7da1e8d` (PR #104) | `test_whoop_ui_parity.py` | Pending PR #114 confines W ring to pull-to-refresh and compacts activity tiles. | **IMPLEMENTED AND VERIFIED** (PR #114 pending) | P1 |
| **More Tab 3-Section Tree** | 3-section navigation tree (SHOP & GIFT, ACCOUNT & SETTINGS, SUPPORT); hardware serial from DIS; safe unpair. | `MoreView.swift`, `MoreDetailViews.swift`, `DeviceSettingsView.swift` | Commit `f992f28` (PR #92) | `MoreTabHardeningTests.swift`, `DeviceControlTests.swift` | None. Structure matches reference. | **IMPLEMENTED AND VERIFIED** | Closed |
| **In-App Wear-State UI Banner** | "Put on your WHOOP" banner with 30–60s debounce delay (`0x109aa52e0`, `0x10978bd90`). | `HomeView.swift:180-220` | PR #80, PR #110 | `HomeViewTests.swift` | Native 30s debounce delay before banner appearance not explicitly parameterized. | **PARTIALLY IMPLEMENTED** | P2 |

---

## 3. Investigation of Key Contradictions

### 3.1 Contradiction 1: Sleep Onset 21:00 vs 22:00 Cutoff
- **The Research Claim:** `docs/research/WHOOP_SLEEP_THRESHOLD_FORENSICS.md` (lines 32–34) stated:
  > *"Defect: STRAP previously evaluated `let daytime = (8..<22).contains(startHour)`. At 9:58 PM (local hour 21 in IST), `daytime` evaluated to `true`... Correction: Evening bedtime is recognized as nocturnal sleep from 21:00 onwards. In-bed settling before sustained sleep is scored as Awake time in bed (.wake), matching WHOOP's 47-minute awake total."*
- **The Actual Main Code:** In `ios/Strap/Analysis/SleepDetect.swift`:
  ```swift
  let startHour = Calendar.current.component(
      .hour, from: Date(timeIntervalSince1970: TimeInterval(run[0].unix))
  )
  let daytime = (8..<22).contains(startHour)
  if daytime && duration < max(minSleepS, 90 * 60) { continue }
  ```
  And lines 108–110:
  ```swift
  // Only daytime/evening rest before 22:00 needs a positive five-minute
  // band-sleep declaration. Overnight sleep starting at or after 22:00
  // relies directly on physiological stillness and HR drop.
  if daytime {
  ```
- **The Git & Test Archeology:**
  1. A search across all git branches (`git log --all -S "8..<21"`) proved that `8..<21` was **never committed to any branch in git history**.
  2. In `ios/StrapTests/SleepOvernightOnsetBoundaryTests.swift` (lines 60–65), a dedicated regression test explicitly asserts this exact threshold:
     ```swift
     func testLateEveningBefore2200StillTrimsUnconfirmedRest() throws {
         let (rows, start) = capture(startHour: 21, startMinute: 45, totalMinutes: 105)
         let night = try XCTUnwrap(SleepDetect.detect(rows).first)
         XCTAssertEqual(night.startUnix, start + 14 * 60,
                        "Pre-22:00 lying-still evidence must not bypass the safety gate")
     }
     ```
- **Verdict & Resolution:** **STALE RESEARCH DOCUMENTATION, INTENTIONAL CODE INVARIANT.**
  The research document represented an early hypothesis based on a single capture night. However, engineering determined that opening the nocturnal gate at 21:00 caused widespread false-positive sleep classifications during sedentary evening activities (e.g., sitting on a sofa watching television or reading a tablet between 21:00 and 22:00). The 22:00 cutoff was deliberately retained and locked with an automated regression test. For bedtimes between 21:00 and 22:00, sleep onset is correctly anchored as soon as the band's onboard state machine reports sustained sleep (`sleepState == 2`), avoiding false-positive couch rest while capturing legitimate sleep. **Do not change `(8..<22)` without new multi-night sensor evidence.**

---

### 3.2 Contradiction 2: Fake Ghidra Addresses vs Actual Cloud Architecture
- **The Research Claim:** `docs/STRAP_ACCURACY_LAB.md` (lines 68–75) claimed that exact ARM64 disassembly addresses in `Whoop.app/Whoop` (iOS 5.80.2) governed local algorithmic decisions:
  - `0x100a7fdc8` (`RecoveryAnalysis.calculateNightHRV`)
  - `0x100a80410` (`RecoveryAnalysis.calculateNightRHR`)
  - `0x100ba3180` (`RespiratoryRateAnalysis.computeFromPPG`)
- **The Actual Binary Evidence:** In `docs/research/WHOOP_FINAL_REVERSE_ENGINEERING_GAP_AUDIT.md` (lines 41–47) and `docs/research/WHOOP_SLEEP_STAGING_FORENSICS.md` (lines 35–42):
  1. Static decompilation of `Whoop.app/Whoop` proves that **zero calculation loops or classifier routines exist on-device for nightly RMSSD, nocturnal RHR, sleep stage breakdown, or recovery percentage**.
  2. The iOS client fetches finalized metrics via REST APIs:
     - `/users/v1/cycles` (`0x109633237`) delivers `hrv_rmssd` and `resting_heart_rate`.
     - `DeepDiveSleepGetRequest` (`0x962e290`) handled by `DeepDiveSleepInteractor` (`0x962e5a0`) delivers `DeepDiveSleepModel` (`0x962eaf8`) containing `slowWaveSleepDuration`, `remSleepDuration`, `lightSleepDuration`, and `wakeDuration`.
     - `/healthspan-service/v1/healthspan/bff` (`0x1098565c0`) delivers VO₂ Max.
  3. The addresses cited in `STRAP_ACCURACY_LAB.md` correspond to metadata strings, CoreData entity attributes, or test harness symbols in the Ghidra project database—not executable mathematical routines.
- **Verdict & Resolution:** **WHOOP RUNS SLEEP & RECOVERY IN THE CLOUD.**
  Claiming that WHOOP computes sleep hypnograms or recovery percentages locally in iOS ARM64 code is technically false. STRAP must continue executing its **clean-room physiological equivalents** (`SleepStager.swift`, `Hrv.swift`, `Recovery.swift`) because an offline client cannot query WHOOP cloud microservices. The focus of reverse engineering must remain on BLE wire telemetry, hardware events, packet framing, and client-side accumulators.

---

### 3.3 Contradiction 3: CapSense Notifications (Push vs Internal)
- **The Research Claim:** `docs/research/whoop_5802/SENSOR_QUALITY_FORENSICS.md` listed `WHPWhoopStrapCapSenseFailedNotification` (`0x10975d131`) and `WHPWhoopStrapCapSenseSuccessNotification` (`0x10975d159`), prompting questions about whether STRAP should issue iOS user notifications for wear-state.
- **The Actual Binary Evidence:**
  1. Both strings are registered names for `NSNotificationCenter.defaultCenter` broadcasts within the UIKit companion application.
  2. Their publisher is `CapSenseViewModel` (`0x10914eb40`) and their consumer is `CapSenseViewController` (`0x10914ea90`), which powers the interactive optical sensor cleaning and recalibration step wizard (`CapSenseStep`).
  3. Neither notification is routed to `UNUserNotificationCenter` or registered as an Apple Push Notification (APNs).
  4. User-facing wear status in WHOOP is restricted to in-app status banners (`OverviewDataSyncing`, string `"Put on your WHOOP"` at `0x10978bd90`) debounced by `offBodyNotificationDelaySecs` (`0x109aa52e0`).
- **Verdict & Resolution:** **NO EXTERNAL PUSH NOTIFICATION EXISTS.**
  STRAP must not introduce artificial iOS system notifications telling users to put on the strap. Wear-state is appropriately rendered as an in-app status indicator on the Home dashboard when the band is disconnected or off-wrist.

---

## 4. Completed Work — No Further Reverse Engineering Needed

The following subsystems have been fully cracked, reverse-engineered, implemented in Swift/Python, and verified via automated test suites. **No further reverse engineering is required for these items:**

1. **BLE Command Set & Pairing Protocol:**
   - Command 14 (`0x0E`) payload `[0x01]` / `[0x00]` for Broadcast Heart Rate toggle (`BandLink.swift:150`).
   - Confirmation that Double-Tap gesture recognition and side blue LED pulsing are 100% firmware-autonomous (0 app writes).
   - Standard Device Information Service (DIS `0x180A`) characteristics (`2A24`, `2A25`, `2A26`, `2A27`, `2A29`) decoded with NUL-stripping and fallback caching.
2. **Historical Flash Offload & Token ACKs:**
   - Commit-then-confirm order verified: 8-byte token ACK matching `inner[2] == BandPacket.historyEnd` (`0x02`) is dispatched strictly after SQLite database commit (`BandLink.swift:1960`).
   - Zero-padding and 7-interval telemetry boundaries enforced.
3. **Recovery Scoring & Baseline Engine:**
   - Unified 28-day rolling mature baseline buffer (`DailyAnalysis.rollingBaselineDays = 28`) matching `GetRestingHeartRateBaselineRequest` (`0x1099623a0`).
   - Exact IEEE-754 boundaries ($\le 33.0$, $33.001\text{--}66.0$, $> 66.0$) and 5-case `RecoveryLevel` enum (`0x100041d3c`, `0x10a0f2874`).
   - Resolution of the 43% vs 57% Home calculation divergence in PR #112 (`RecoveryDiagnostics.swift`).
4. **Resting Heart Rate & Quiet Window Isolation:**
   - 5-minute rolling median across verified nocturnal quiet sleep windows (`Hrv.swift:45-90`).
   - Elimination of 1-second dip artifacts and daytime nap contamination (`AnalysisTests.swift`).
5. **Nocturnal Awakening & Bathroom Break Merging:**
   - Merging consecutive sleep candidate periods separated by $\le 30$ minutes of low-motion awakening (`SleepDetect.swift:342-395`).
   - High-exertion safeguard: interruptions with $\ge 180$s of HR $\ge 90$ and accel $\ge 0.15g$ are permanently blocked from merging.
6. **Sleep Staging Prior Calibration:**
   - Damping linear REM cycle prior from $1.0 \times \text{clock}$ to $0.60 \times \text{clock}$, resolving the 42-minute REM overestimation and restoring Stage N2 Light sleep parity (`SleepStager.swift`).
   - SWS Deep Sleep 11-minute flatness gating.
7. **Sleep Window Ceiling:**
   - Strict 12-hour maximum sleep window bounding (`TWELVE_HOUR` in `SleepWindow.swift`, `maxSleepS = 43200`).
8. **Intelligent Activity Detection:**
   - Multi-stage gate enforcing $\ge 100$ SPM cadence for walking, HR conjunction checks, pre-workout baseline latching, and $\ge 240$s active sustain.
   - CoreML exercise classification taxonomy (64+ exercises) and 125 activity icons mapped (`ActivityStore.swift`, PR #111).
9. **UI Design Tokens & Score Rings:**
   - 84 pt outer diameter, 5.0 pt stroke, #2A333A track, DIN Pro 22 pt bold numbers with 72% percent sign baseline (PR #102).
   - 4-tab bottom navigation preserved strictly untouched.
   - 3-section More menu hierarchy (PR #92).

---

## 5. Research Findings Not Yet Implemented

The following items are verified in binary research but have not yet been integrated into production code:

1. **Hardware Event Opcode Dispatcher (`BandLink.swift:2138`):**
   - *Binary Evidence:* Swift reflection metadata offset `0xa24d56a` on characteristic `fd4b0004` proves opcodes: `wristOn` (`0x09`), `wristOff` (`0x0A`), `batteryPackConnected` (`0x15`), `batteryPackRemoved` (`0x16`), `doubleTap` (`0x0E`), `bleBonded` (`0x17`).
   - *Current Code:* `BandLink.swift:2138` only checks `eventOpcode == BandHardwareEvent.bleHRProfileEnable.rawValue`.
   - *Delta:* Expand the `BandUUID.events` handler to update `isWearing` on `0x09`/`0x0A` and `isCharging` on `0x15`/`0x16`.
2. **Status Packet `wristState` Bitfield Extraction (`0x10bc3d110`):**
   - *Binary Evidence:* Telemetry status envelope contains a 16-bit bitfield (`wristState`) directly indicating on-body capacitive sensor contact.
   - *Current Code:* `BandLink.swift` decodes battery percentage from the envelope but discards `wristState`. `V18Sample.wearing` falls back to `heartRate > 0`.
   - *Delta:* Parse `wristState` in status packet reassembly and wire it into sample telemetry validity.
3. **CoreBluetooth Background State Restoration (`CBCentralManagerOptionRestoreIdentifierKey`):**
   - *Binary Evidence:* `_TtC5Whoop13WHPBLEManager` (`0x1000dfd6c`) instantiates `CBCentralManager` with `CBCentralManagerOptionRestoreIdentifierKey` and implements `centralManager(_:willRestoreState:)` for background survival across iOS memory pressure terminations.
   - *Current Code:* `BandLink.swift` initializes `CBCentralManager` without a restore identifier.
   - *Delta:* Add `CBCentralManagerOptionRestoreIdentifierKey: "strap.central.restore"` and implement state restoration delegate callback.
4. **Strain Piecewise Scale Mapping Table:**
   - *Binary Evidence:* `FUN_1001efe44` maps accumulated strain to 0.0–21.0 using the 211-entry piecewise table `strain_raw_scale_lookup.json` (`0x1096260b0`).
   - *Current Code:* STRAP evaluates Day Strain using a continuous exponential formulation (Banister TRIMP).
   - *Delta:* Port `strain_raw_scale_lookup.json` and piecewise midpoint interpolation into `Strain.swift` for exact numerical parity with WHOOP's scale.

---

## 6. Actual Remaining Reverse-Engineering Tasks

Only the following questions represent genuine reverse-engineering unknowns:

1. **Firmware State Byte Layout (V18 Offset 38):**
   - *Question:* In `V18Sample`, what do bits 0–3 and 6–7 of `sleepStateByte` represent? Bits 4–5 encode coarse states 0 (wake), 1 (still), 2 (sleep), 3 (up). The meaning of the remaining bits remains unmapped.
   - *Target:* Inspect `RawDataRev18` packet unpacking in `Whoop.app/Whoop` at `0x1008cf200` to determine if bits 0–3 encode optical signal confidence or accelerometer variance.
2. **Health Monitor Outlier Normalization Corridor:**
   - *Question:* What are the exact percentile bounds for Health Monitor status badges (in-range green vs outlier red)?
   - *Target:* Inspect `HealthMonitorSummaryViewModel` (`0x10974ad20`) in WHOOP binary to extract standard deviation multipliers ($\pm 1.5\sigma$ vs $\pm 2.0\sigma$) for RHR, HRV, SpO₂, skin temperature, and respiratory rate.
3. **Capacitive Touch Dielectric Threshold:**
   - *Question:* What raw threshold separates on-wrist from off-wrist in the band's capacitive sensor registers?
   - *Target:* Firmware-level register inspection; requires analyzing Nordic nRF firmware dump if accessible.

---

## 7. Tasks Requiring Real Hardware Validation

The following items cannot be resolved via static binary analysis or unit testing and must be validated against a physical WHOOP 4.0 / 5.0 / MG band:

1. **Hardware Offload Drain on Firmware 50.43.1.0:**
   - Connect physical band after 6 hours of offline wear.
   - Verify that `BandLink.swift:1960` successfully drains flash chunks and that the band stops retransmitting acknowledged packets.
2. **Physical Double-Tap & Blue LED Pairing Test:**
   - Take band off wrist. Confirm green LEDs extinguish after 10–15s (`wristOff`).
   - Double-tap top surface. Confirm side LED pulses blue (`pairingMode` `0x12`) and STRAP discovers the peripheral.
3. **Hardware Battery Pack Attachment:**
   - Slide battery pack onto band. Confirm band emits hardware event `0x15` (`batteryPackConnected`) and STRAP UI reflects charging state.
4. **Real-World Walking vs Running vs Desk Activity:**
   - Wear band during a 15-minute brisk walk ($\ge 100$ SPM) vs 15 minutes of typing at a desk. Verify walk creates an activity session while desk typing does not.

---

## 8. Three Highest-Value Next Fixes

Based on user priorities, stability requirements, and code hygiene, the three highest-value next actions are:

### Fix 1: Wire Hardware Events (`wristOn`, `wristOff`, `charging`) in `BandLink.swift` (P1)
- **Problem:** `BandLink.swift:2138` ignores hardware events notified on characteristic `fd4b0004`, causing off-wrist state and charging status to lag until telemetry packets arrive.
- **Action:**
  1. Add `case wristOn = 0x09` to `BandHardwareEvent` in `BandUUIDs.swift`.
  2. In `BandLink.swift:2138`, expand the event dispatcher:
     - `0x09` (`wristOn`): set `isWearing = true`.
     - `0x0A` (`wristOff`): set `isWearing = false` and pause live HR display.
     - `0x15` (`batteryPackConnected`): set `isCharging = true`.
     - `0x16` (`batteryPackRemoved`): set `isCharging = false`.
  3. Add regression tests in `BandConnectionStateMachineTests.swift`.

### Fix 2: Add CoreBluetooth Background State Restoration (P1)
- **Problem:** STRAP drops peripheral connections when iOS terminates the app in the background under memory pressure, failing to collect overnight sleep or history until manually reopened.
- **Action:**
  1. Initialize `CBCentralManager` with `[CBCentralManagerOptionRestoreIdentifierKey: "strap.central.restore"]`.
  2. Implement `centralManager(_:willRestoreState:)` in `BandLink.swift` to recover discovered and connected peripheral instances.
  3. Ensure no duplicate delegates or timer leaks occur during state restoration.

### Fix 3: Reconcile Stale Documentation for Sleep Onset Cutoff (P0 Documentation)
- **Problem:** `WHOOP_SLEEP_THRESHOLD_FORENSICS.md` claims the 21:00 cutoff was fixed, confusing future audits and conflicting with the active 22:00 cutoff in `SleepDetect.swift` and `SleepOvernightOnsetBoundaryTests.swift`.
- **Action:**
  1. Update `WHOOP_SLEEP_THRESHOLD_FORENSICS.md` to document that the 22:00 cutoff is an intentional invariant designed to reject sedentary pre-bedtime phone/reading stillness.
  2. Cross-reference `SleepOvernightOnsetBoundaryTests.swift:60` (`testLateEveningBefore2200StillTrimsUnconfirmedRest`) as the authoritative regression lock.
  3. Preserve all existing detection thresholds without code regression.

---

## 9. Conclusion

The STRAP reverse engineering effort has reached high functional parity across BLE transport, packet parsing, recovery scoring, RHR median windowing, SWS HRV isolation, awakening merging, and UI presentation tokens. 

By recognizing that **WHOOP sleep staging and recovery scoring execute in the cloud**, the project is freed from pursuing non-existent client-side neural network weights. By verifying that **the 22:00 sleep onset cutoff is an intentional and tested safety invariant**, unnecessary threshold tampering is prevented. 

The path forward is strictly bounded: integrate the remaining BLE hardware event opcodes (`0x09`, `0x0A`, `0x15`, `0x16`), add CoreBluetooth background state restoration, validate historical offload against physical hardware, and finalize UI pull-to-refresh polish once pending PR #114 CI concludes.

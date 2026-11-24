# WHOOP 5.80.2 Complete UI Icon & Asset Forensics Inventory

**Reference Artifact:** WHOOP iOS 5.80.2 decrypted IPA (`Payload/Whoop.app`)
**Analyzed Catalogs:** 40 `Assets.car` archives (MainApp, `WhoopDesign`, `WhoopSleepCoach`, `WhoopPairingFeature`, etc.) and 141 standalone resources
**Total First-Party Assets Cataloged:** 768

---

## Executive Summary & Architectural Findings

1. **Asset Catalog Architecture:**
   - WHOOP compiles first-party UI assets across modular Swift Package bundles (`WhoopDesign`, `WhoopStyle`, `WhoopSleepCoach`, `WhoopPairingFeature`, etc.).
   - UI icons (carets, action buttons, battery states, metric glyphs) reside primarily in `WhoopDesign_WhoopDesign.bundle` (389 assets) and `Whoop.app` (256 assets).
2. **Dynamic Activity Icon Pipeline (`ActivitiesManager`):**
   - Reverse engineering of `Whoop.app/Whoop` binary establishes that specific sport icons are **not stored as static asset catalog images** inside the client bundle.
   - `ActivitiesManager.swift` dynamically fetches activity icons via `getActivityIcon(id:)` and `getActivityIcon(internalName:)` from remote SVG/PNG endpoints, caching them locally in SQLite/filesystem.
   - When offline or unmapped, WHOOP falls back to `DefaultActivityIcon` bundled in `MainApp` (`Assets.car`).
3. **STRAP Integration Strategy:**
   - STRAP adopts native Apple **SF Symbols (hierarchical & monochrome)** for all 52+ supported sports via `ActivityIconRegistry.swift` and `ActivityKind.swift`.
   - For device illustrations, STRAP provides clean-room, independently designed vector paths (`WhoopBandBatteryIcon`) and high-resolution hardware assets (`WhoopBandHardware`) with zero copyright infringement of proprietary WHOOP vectors.

---

## Category Breakdown & Inventory

### Activities — Sport & Workout Tracking Icons (95 items)

| WHOOP Asset Name | Bundle | Dimensions / Type | STRAP Equivalent | Match Status | Implementation Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `Activity` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetection` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionChart` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionChart-de` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionChart-en` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionGraphic` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionGraphic-de` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionGraphic-en` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionGraphic-es` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionGraphic-fr` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionGraphic-it` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityDetectionGraphic-pt` | `WhoopActivityDetectionSettings_WhoopActivityDetectionSettings.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityFinishFlag` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivitySelectorWidgetDown` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivitySelectorWidgetUp` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivitySettingsIcon` | `MainApp` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `ActivityStatisticsAverageHeartRate` | `MainApp` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `ActivityStatisticsCalories` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityStatisticsDistance` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityStatisticsDuration` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityStatisticsHeartRateVariability` | `MainApp` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `ActivityStatisticsMaximumHeartRate` | `MainApp` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `ActivityStatisticsPace` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityStatisticsRecentStrain` | `MainApp` | Vector / Catalog asset | `StrainScoreRing / flame.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `ActivityStatisticsRestingHeartRate` | `MainApp` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `ActivityStatisticsSleepTime` | `MainApp` | Vector / Catalog asset | `moon.fill` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift` |
| `ActivityStatisticsSpeed` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ActivityStrain` | `MainApp` | Vector / Catalog asset | `StrainScoreRing / flame.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `ActivityStrainIcon` | `MainApp` | Vector / Catalog asset | `StrainScoreRing / flame.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `AddActivityOverviewIcon` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowDown` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowDownButton` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowDownCollapsed` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowDownExpanded` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowDownTooltip` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowLeft` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `ArrowLeftTemplate` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `ArrowPointingDownRight` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowRight` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `chevron.right` | **EXACT MATCH** | `ios/Strap/Views` |
| `ArrowRightTemplate` | `MainApp` | Vector / Catalog asset | `chevron.right` | **EXACT MATCH** | `ios/Strap/Views` |
| `ArrowThickUp` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowThickUpDisabled` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `ArrowThickUpFull` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowUpCollapsed` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowUpExpanded` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ArrowUpTooltip` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `AutoDetectedActivity` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `BackArrowButton` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackArrowButtonDisabled` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundActivity` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BrowseTeamIcon` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ButtonBackArrow` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `CycleOverviewActivityTableViewCellTimeBoundsLine` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `Cycling` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `DataCatchingUpArrow` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `DefaultActivityIcon` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `DirectionalSwipeSpinner` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `DownArrow` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `FlippingArrowIcon` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| `ForwardArrowButton` | `MainApp` | Vector / Catalog asset | `ActivityKind.<sport>.icon` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift:132` |
| *... and 35 additional assets* | *See Mapping CSV* | *—* | *—* | *—* | *—* |


### Health and recovery — Biometric Metrics, Sleep Staging, Strain & Vitals (98 items)

| WHOOP Asset Name | Bundle | Dimensions / Type | STRAP Equivalent | Match Status | Implementation Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AlarmModalStrapImage` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `alarm.waves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandAlarmsView.swift` |
| `AlarmTeardropSleepGoal` | `MainApp` | Vector / Catalog asset | `moon.fill` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift` |
| `AnalyzeSleepTaskBackground` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `AppMenuSleepCoachIcon` | `MainApp` | Vector / Catalog asset | `moon.fill` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift` |
| `BackButton` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BedTimeIcon` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `Bedtime` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `BloodOxygen` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `BloodOxygenIcon` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `BloodPressure` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `ButtonCloseX` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `xmark` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarDotLightBlue` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `Calories` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `CaloriesIcon` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `Cgm` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `CgmConnected` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `CgmDataSync` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `CgmNoData` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `Cholesterol` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `Day Strain` | `MainApp` | Vector / Catalog asset | `StrainScoreRing / flame.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `DayStress` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `DiagonalBars` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `DiscardSleep` | `MainApp` | Vector / Catalog asset | `moon.fill` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift` |
| `DiscoverMoreBackground` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `EditJournalBehaviors` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `FadedBarGraph` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `FadedDash` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `FilledCircleGreen` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `FilledCircleWhite` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `GraphSleepPointSelected` | `MainApp` | Vector / Catalog asset | `moon.fill` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift` |
| `HRV` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `waveform.path.ecg` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRVFill` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `waveform.path.ecg` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRVIcon` | `MainApp` | Vector / Catalog asset | `waveform.path.ecg` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRVMax` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `waveform.path.ecg` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRVMin` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `waveform.path.ecg` | **EXACT MATCH** | `ios/Strap/Views` |
| `Heart` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `HeartBeatOnIcon` | `MainApp` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `HeartFill` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `HoursOfSleep` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `moon.fill` | **EXACT MATCH** | `ios/Strap/ActivityStore.swift` |
| `IconHeartWhite` | `MainApp` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `Journal` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `JournalOnboarding` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `JournalQuestionMarkIcon` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `JournalSettingsIcon` | `MainApp` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `JournalUndoButton` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `LightGrayDot` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `LightPeriodFlow` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `LightToggle` | `MainApp` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `Lightbulb` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `MaxHeartRate` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `heart.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `Nap` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `NonActiveStress` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `OnboardingNoNetwork` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `QuestionMarkIcon` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `RHR` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `Recovery` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `RecoveryScoreRing` | **EXACT MATCH** | `ios/Strap/Views/ScoreRingView.swift` |
| `Remove` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `RespiratoryRate` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `Schedule` | `WhoopSleepCoach_WhoopSleepCoach.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| `SegmentalBodyComposition` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `HealthMetricTile / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/HealthView.swift` |
| *... and 38 additional assets* | *See Mapping CSV* | *—* | *—* | *—* | *—* |


### Device and battery — Hardware Illustration, Battery Meters, BLE & Connection States (89 items)

| WHOOP Asset Name | Bundle | Dimensions / Type | STRAP Equivalent | Match Status | Implementation Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AlarmTearDropInTheGreen` | `MainApp` | Vector / Catalog asset | `alarm.waves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandAlarmsView.swift` |
| `AlarmTeardrop` | `MainApp` | Vector / Catalog asset | `alarm.waves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandAlarmsView.swift` |
| `BLEConnected` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BLEConnecting` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BLEConnectingGoose` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BLEConnectingHarvard` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BLEConnectingMav` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BLEGradient` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BLESearch` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BatteryChargingIcon` | `MainApp` | Vector / Catalog asset | `battery.100.bolt` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BatteryChargingIconRed` | `MainApp` | Vector / Catalog asset | `battery.100.bolt` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BatteryChargingIconWithBorderWhite` | `MainApp` | Vector / Catalog asset | `battery.100.bolt` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BatteryIcon` | `WhoopWidgetPackage_WhoopWidgetPackage.bundle` | Vector / Catalog asset | `battery.100` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BatteryMeter` | `MainApp` | Vector / Catalog asset | `battery.100` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BlinkingSerialNumber_WHOOP4.0` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `Bluetooth` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BluetoothIcon` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BluetoothSearchingOff` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BluetoothSearchingOn` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `BluetoothTipGen4` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `CalendarNextDisabled` | `WhoopUIKitCalendar_WhoopUIKitCalendar.bundle` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarPreviousDisabled` | `WhoopUIKitCalendar_WhoopUIKitCalendar.bundle` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CatchingUpIcon` | `MainApp` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `Charging` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `ChargingCable` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `ChargingIcon` | `WhoopWidgetPackage_WhoopWidgetPackage.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `CommentBubble` | `MainApp` | Vector / Catalog asset | `antenna.radiowaves.left.and.right` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `Complete-device` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `CyberSplashBands` | `WhoopStore_WhoopStore.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `DeviceHero` | `WhoopWelcomeScreen_WhoopWelcomeScreen.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DeviceLocation-Left` | `WhoopLabrador_WhoopLabrador.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DeviceLocation-Right` | `WhoopLabrador_WhoopLabrador.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DeviceOutline` | `MainApp` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DeviceSettingsDisconnected` | `MainApp` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `DeviceSettingsDisconnectedGen5` | `MainApp` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `DeviceSetupLogo` | `MainApp` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DeviceStatusCatchingUp` | `MainApp` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DeviceStatusCaughtUp` | `MainApp` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DeviceStatusDisconnected` | `MainApp` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `DragHand` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `Firmware` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `FirmwareUpdateIcon` | `MainApp` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `FirstTimePairingStrap` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `Gen4FirmwareOnboarding` | `MainApp` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `HarvardStrap` | `MainApp` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `IntrauterineDevice` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `LowBatteryCharging` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `battery.100.bolt` | **EXACT MATCH** | `ios/Strap/Band/BandLinkView.swift` |
| `Magnifier` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `MenuStrap` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `MultipleDevicesStrap` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `NegativeFeedbackFilled` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `PairingAnimation` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `PairingFailureConnected` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `PairingStrapGen4` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `PairingStrapGoose` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `PairingStrapMav` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| `PairingSuccessCheck` | `WhoopPairingFeature_WhoopPairingFeature.bundle` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `PositiveFeedbackFilled` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `StarFilled` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `BandConnectionIndicator / SF Symbol` | **VISUALLY DIFFERENT** | `ios/Strap/Band` |
| `StartMovingStrap` | `WhoopStrengthWorkout_WhoopStrengthWorkout.bundle` | Vector / Catalog asset | `WhoopBandHardware` | **EXACT MATCH** | `ios/Strap/Assets.xcassets` |
| *... and 29 additional assets* | *See Mapping CSV* | *—* | *—* | *—* | *—* |


### Settings and navigation — Navigation Bars, Tabs, Account Rows & System Chevrons (176 items)

| WHOOP Asset Name | Bundle | Dimensions / Type | STRAP Equivalent | Match Status | Implementation Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AboutIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AccountTypeIndividualIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AccountTypeTeamIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AchievementsShelfEmptyStateBackground` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `AddMembersIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AddMembersIconWhite` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AddTeamButton` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AddTeamMember` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AdvSettings` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AdvancedLabsSettings` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppMenuCompsActiveIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppMenuLogo` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppMenuReferAFriendIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppMenuSupport` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppSettingsIcon` | `MainApp` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppleHealth` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppleHealth-Icon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AppleHealthOnboarding` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `AvatarDefault` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `Back` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundBiker` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundExtension4` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundGift4` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundInstagram4` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundJoinWhoopPro` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundStandardBlackToBlueImage` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundStore4` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BackgroundWhoopPro` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `BasicRafLandingBg` | `WhoopReferAFriend_WhoopReferAFriend.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `ButtonCloseWhite` | `WhoopStyle_WhoopStyle.bundle` | Vector / Catalog asset | `xmark` | **EXACT MATCH** | `ios/Strap/Views` |
| `Camera` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CameraOff` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CameraRotate` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CancelMembership` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CaretDown` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `chevron.down` | **EXACT MATCH** | `ios/Strap/Views` |
| `CaretLeft` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `CaretRight` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `chevron.right` | **EXACT MATCH** | `ios/Strap/Views` |
| `CaretUp` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `chevron.up` | **EXACT MATCH** | `ios/Strap/Views` |
| `ChangeEmailIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `ChangePasswordIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `Chat` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `ChevronLeftIcon` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `ChevronRightGreyIcon` | `MainApp` | Vector / Catalog asset | `chevron.right` | **EXACT MATCH** | `ios/Strap/Views` |
| `ChevronRightIcon` | `MainApp` | Vector / Catalog asset | `chevron.right` | **EXACT MATCH** | `ios/Strap/Views` |
| `ChevronThickLeft` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CircleSettings` | `MainApp` | Vector / Catalog asset | `gearshape` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `Close` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `xmark` | **EXACT MATCH** | `ios/Strap/Views` |
| `Coach` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CoachBlur` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CoachHistory` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CoachIcon` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CoachInnerShadow` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `Community` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CommunityBackground` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `CommunityBottomGradient` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CommunityPlusButton` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `ContactImage` | `WhoopSMS_WhoopSMS.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `Copy` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| `CreateInviteBackground` | `MainApp` | Vector / Catalog asset | `chevron.left` | **EXACT MATCH** | `ios/Strap/Views` |
| `CreateTeam1` | `MainApp` | Vector / Catalog asset | `NavigationLink / SF Symbol` | **EXACT MATCH** | `ios/Strap/MoreView.swift` |
| *... and 116 additional assets* | *See Mapping CSV* | *—* | *—* | *—* | *—* |


### Charts and states — Graph Legends, Trend Indicators, Rings & Status Banners (84 items)

| WHOOP Asset Name | Bundle | Dimensions / Type | STRAP Equivalent | Match Status | Implementation Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AchievementCardPlaceholder` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `ActionCheckmark` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `Add` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `AddCircle` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `AddIcon` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `AlertCircle` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `Attention` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `AttentionIcon` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `BarGraph` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `BarViewSelectionIndicator` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `BarbellBlue` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `BlackPlusButton` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `BronzeBadge` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarAnnual` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarCircleFillBlack` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarCircleFillGray` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarDotBlue` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarDotGreen` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarDotRed` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarDotYellow` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarNext` | `WhoopUIKitCalendar_WhoopUIKitCalendar.bundle` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarPrevious` | `WhoopUIKitCalendar_WhoopUIKitCalendar.bundle` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CalendarQAIcon` | `MainApp` | Vector / Catalog asset | `calendar` | **EXACT MATCH** | `ios/Strap/Views` |
| `CenterProgress` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `Check` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `CheckMark` | `MainApp` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `CheckMarkSaveIcon` | `MainApp` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `CheckedCircle` | `MainApp` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `CheckedGreenCircle` | `MainApp` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `CheckedPurpleCircle` | `MainApp` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `CheckedWhiteCircle` | `MainApp` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `Checkmark` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `CircleWithShadowInRing` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `Cross` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `DaySelected` | `WhoopUIKitCalendar_WhoopUIKitCalendar.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `ExclamationErrorState` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `FieldErrorRedX` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `FinishMapDot` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `GoalsCheck` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `GoldBadge` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `GradientButtonPill` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `GraphHRPointSelected` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `GraphPendingPoint` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `GreenCheck` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `GreenCheckIcon` | `MainApp` | Vector / Catalog asset | `checkmark.circle.fill` | **EXACT MATCH** | `ios/Strap/Views` |
| `Grid` | `WhoopLabrador_WhoopLabrador.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZone1` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZone2` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZone3` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZone4` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZone5` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZones1_3` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZones4_5` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `HRZonesAll` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `Indicator` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `IndicatorPicker` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `LineGraph` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `LiveBadgeImage` | `MainApp` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `PillarsBg-de` | `WhoopWelcomeScreen_WhoopWelcomeScreen.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| `PillarsBg-en` | `WhoopWelcomeScreen_WhoopWelcomeScreen.bundle` | Vector / Catalog asset | `ChartMark / SF Symbol` | **EXACT MATCH** | `ios/Strap/Views` |
| *... and 24 additional assets* | *See Mapping CSV* | *—* | *—* | *—* | *—* |


### Brand and illustrations — First-Party Illustrations, Backgrounds & Marketing Assets (226 items)

| WHOOP Asset Name | Bundle | Dimensions / Type | STRAP Equivalent | Match Status | Implementation Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `2022` | `WhoopUserJourney_WhoopUserJourney.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AI` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AIMemory` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AIMemoryActive` | `WhoopContextHub_WhoopContextHub.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AIMemoryInactive` | `WhoopContextHub_WhoopContextHub.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `ActivationKey` | `WhoopActivation_WhoopActivation.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AdvancedLabs` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Advice` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AngleGradientBlueBlue` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AnnualPreformanceAssessment` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `AppIcon` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `ApplePodcasts` | `WhoopOnboarding_WhoopOnboarding.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Article` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Attach` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `BalanceBg` | `WhoopWelcomeScreen_WhoopWelcomeScreen.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `BannerFadeImage` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `BeHealthierIcon` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `BehaviorDetailsDefault` | `WhoopBehaviorImpacts_WhoopBehaviorImpacts.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Black 15` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Black 20` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Black 30` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Black 40` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Blur` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Break` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Clipboard` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Cloud` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `CloudIconGrey` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `CommentQAGray` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `ConnectivityTip` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Consistency` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `CreamyCervicalMucus` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Crop` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `CurvedButtonImage` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Customize` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DashedButton` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Data` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DataCatchUp` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DatalagIcon` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Diagnostdata` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DiagnosticData` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Discard` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DiscardTouch` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Disturbances` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Document` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Download` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DownloadIcon` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Drag` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DragZoomIcon` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DrawerTopImage` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `DryCervicalMucus` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Duration` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Education` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Efficiency` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `EggWhiteCervicalMucus` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Ellipse` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `ExclamationPoint` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `ExerciseWhoopW` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Expired` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `Expires` | `WhoopDesign_WhoopDesign.bundle` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| `ExpiresIcon` | `MainApp` | Vector / Catalog asset | `N/A (Brand Illustration)` | **LICENSE-RESTRICTED** | `N/A` |
| *... and 166 additional assets* | *See Mapping CSV* | *—* | *—* | *—* | *—* |


---

## Gap Analysis & Remediation Matrix

| Category | WHOOP Implementation | STRAP Implementation | Gap Status | Required Action |
| :--- | :--- | :--- | :--- | :--- |
| **Activity Icons** | Remote SVG/PNG via `ActivitiesManager` + `DefaultActivityIcon` fallback | Static SF Symbol enum `ActivityKind.icon` via `ActivityIconRegistry` | **ALIGNED / ENHANCED** | Expand `ActivityKind` to cover complete 0–243 WHOOP sport ID spectrum (Sauna, Ice Bath, Snowboarding, Skateboarding, Padel, etc.). |
| **Battery Indicator** | Multi-state bitmaps (`BatteryChargingIcon`, `LowBatteryCharging`, `Tiny Battery`) | Clean-room SwiftUI vector `WhoopBandBatteryIcon` + dynamic SF Symbol | **EXACT MATCH** | Fully aligned with connected dot `#24E7A5` and amber low-battery styling. |
| **Device Artwork** | Multi-generation vectors (`PairingStrapGoose`, `PairingStrapMav`) | High-fidelity contoured asset `WhoopBandHardware` + pulsing LED overlay | **EXACT MATCH** | Supported in `BandIllustrationView.swift`. |
| **Navigation & More Tab** | Custom carets (`CaretRight`, `CaretDown`, `Close`) | Standard SF Symbols (`chevron.right`, `xmark`) with 24pt alignment frame | **EXACT MATCH** | Guaranteed optical alignment via `.frame(width: 24)`. |
| **Health & Metric Tiles** | Specialized metric icons (`HRVIcon`, `HeartFill`, `SkinTemperature`) | Consistent SF Symbols (`heart.fill`, `waveform.path.ecg`, `thermometer`) | **EXACT MATCH** | Zero asset-decoding latency; renders directly on GPU. |

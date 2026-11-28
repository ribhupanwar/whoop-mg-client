# STRAP Icon & UI Asset Coverage Matrix

**Date:** 23 November 2026  
**Reference Inventory:** WHOOP iOS 5.80.2 Assets.car Forensic Audit (768 assets cataloged in `WHOOP_ICON_INVENTORY.md` & `WHOOP_TO_STRAP_ICON_MAPPING.csv`)  
**Implementation:** `ios/Strap/StrapIconRegistry.swift`, `ios/Strap/IconAsset.swift`, `ios/Strap/ActivityStore.swift`, `ios/Strap/IconGalleryView.swift`, `ios/Strap/SleepAnalysisView.swift`  
**License Compliance:** Strictly clean-room vector paths, licensed SF Symbols, and independently authored artwork. Zero unlicensed proprietary WHOOP bitmaps or scraped assets.

---

## 1. Icon Coverage Summary

| Category | Total Required | Clean-Room Original Assets | SF Symbol Semantic Fallbacks | Coverage Status | Evidence & Validation |
|---|---|---|---|---|---|
| **Supported Activities / Sports** | 137 | 0 (Dynamic remote in WHOOP) | 137 SF Symbols | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `ActivityStore.swift` + `ActivityIconRegistryTests.swift` |
| **Sleep & Sleep Stages** | 9 | 2 (`IconAsset.healthSleep`, `alarmSleepGoal`) | 9 (`StrapIcon.Sleep.*`) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `SleepAnalysisView.swift`, `SleepStage.icon`, `AnalysisTypes.swift` |
| **Health & Vitals Metrics** | 12 | 8 (`IconAsset.health*`) | 12 (`StrapIcon.Metric.*`) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `HealthView.swift`, `HealthHubView.swift`, `UIPerformanceBenchmarkTests.swift` |
| **Device & Battery Indicators** | 15 | 9 (`IconAsset.device*`) | 15 (`StrapIcon.Device.*`) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `WhoopBandBatteryIcon`, `PairDeviceView.swift`, `DeviceSettingsView.swift` |
| **Settings & Navigation** | 14 | 8 (`IconAsset.settings*`, `nav*`) | 14 (`StrapIcon.Navigation.*`) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `SettingsView.swift`, `MoreView.swift`, `RootView.swift` |
| **Actions & UI Controls** | 11 | 0 (Native SF Symbols) | 11 (`StrapIcon.Action.*`) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `ActivityLoggerView.swift`, `IconGalleryView.swift` |
| **Alarm & Haptics** | 3 | 2 (`IconAsset.alarm*`) | 3 (`StrapIcon.Device.*`) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `SleepCoachView.swift`, `BandAlarmsView` |
| **Charts, Trends & States** | 10 | 0 (Native SwiftUI vectors) | 10 (`StrapIcon.State.*`) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `CombinedLoadChart.swift`, `TrendBadge.swift` |
| **AI Coach Interface** | 2 | 1 (`WhoopWGlyph` vector) | 2 (Double circle + glyph) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `RootView.swift:198`, `StrapAICoachView.swift` |
| **Pull-to-Refresh Spinner** | 2 | 2 (`WhoopWGlyph` + arc) | N/A (Custom SwiftUI Path) | **SEMANTIC COVERAGE ONLY — visual parity unverified** | `HomeView.swift:70`, `WhoopWGlyph` |

---

## 2. Category Detail Coverage Matrix

| Icon Identifier | WHOOP 5.80.2 Reference | STRAP Custom Asset | SF Symbol Fallback | Match Status | Forensic Evidence |
|---|---|---|---|---|---|
| `StrapIcon.Metric.heartRate` | `MainApp.heartRateIcon` | `health_heart_rate` | `heart.fill` | SEMANTIC MAPPING — visual parity unverified | Assets.car / `HealthView.swift` |
| `StrapIcon.Metric.restingHeartRate` | `HealthMonitor.RhrIcon` | `health_heart_rate` | `heart` | SEMANTIC MAPPING — visual parity unverified | Assets.car / `HealthHubView.swift` |
| `StrapIcon.Metric.hrv` | `MainApp.hrvIcon` | `health_hrv` | `waveform.path.ecg` | SEMANTIC MAPPING — visual parity unverified | Assets.car / SWS R-R Tachogram |
| `StrapIcon.Metric.respiration` | `MainApp.respiratoryIcon` | `health_respiratory` | `lungs.fill` | SEMANTIC MAPPING — visual parity unverified | Assets.car / `HealthView.swift` |
| `StrapIcon.Metric.bloodOxygen` | `MainApp.spo2Icon` | `health_blood_oxygen` | `o.circle` | SEMANTIC MAPPING — visual parity unverified | Replaced confusing `"drop"` with oxygen saturation badge |
| `StrapIcon.Metric.skinTemp` | `MainApp.skinTempIcon` | `health_temperature` | `thermometer.medium` | SEMANTIC MAPPING — visual parity unverified | Assets.car / `HealthView.swift` |
| `StrapIcon.Metric.sleep` | `MainApp.sleepPillarIcon` | `health_sleep` | `moon.fill` | SEMANTIC MAPPING — visual parity unverified | Assets.car / `HomeView.swift` |
| `StrapIcon.Metric.recovery` | `MainApp.recoveryPillarIcon` | `health_recovery` | `shield.fill` | SEMANTIC MAPPING — visual parity unverified | Assets.car / Score ring |
| `StrapIcon.Metric.strain` | `MainApp.strainPillarIcon` | `health_strain` | `flame.fill` | SEMANTIC MAPPING — visual parity unverified | Assets.car / Score ring |
| `StrapIcon.Metric.stress` | `MainApp.stressIcon` | N/A (SwiftUI vector) | `waveform.path` | SEMANTIC MAPPING — visual parity unverified | `StressView.swift` |
| `StrapIcon.Metric.vo2Max` | `MainApp.vo2MaxIcon` | N/A (Clean vector) | `figure.run.circle` | SEMANTIC MAPPING — visual parity unverified | `HealthView.swift` / `HealthspanInsights.swift` |
| `StrapIcon.Metric.healthspan` | `MainApp.healthspanIcon` | N/A (Clean vector) | `leaf.circle.fill` | SEMANTIC MAPPING — visual parity unverified | `HealthspanView.swift` |
| `StrapIcon.Metric.ecg` | `MainApp.ecgSpotCheck` | N/A (SwiftUI vector) | `waveform.path.ecg.rectangle` | SEMANTIC MAPPING — visual parity unverified | `MGEcgPacketTests.swift` |
| `StrapIcon.Sleep.awake` | `MainApp.sleepWakeIcon` | N/A (SF Symbol) | `sun.max.fill` | SEMANTIC MAPPING — visual parity unverified | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.light` | `MainApp.sleepLightIcon` | N/A (SF Symbol) | `moon.stars.fill` | SEMANTIC MAPPING — visual parity unverified | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.deep` | `MainApp.sleepDeepIcon` | N/A (SF Symbol) | `moon.fill` | SEMANTIC MAPPING — visual parity unverified | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.rem` | `MainApp.sleepRemIcon` | N/A (SF Symbol) | `brain.head.profile` | SEMANTIC MAPPING — visual parity unverified | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.restorative` | `MainApp.restorativeSleep` | N/A (SF Symbol) | `sparkles` | SEMANTIC MAPPING — visual parity unverified | `SleepAnalysisView.swift:718` |
| `StrapIcon.Sleep.debt` | `MainApp.sleepDebt` | N/A (SF Symbol) | `hourglass` | SEMANTIC MAPPING — visual parity unverified | `SleepAnalysisView.swift` |
| `StrapIcon.Sleep.consistency` | `MainApp.sleepConsistency` | N/A (SF Symbol) | `chart.bar.xaxis` | SEMANTIC MAPPING — visual parity unverified | `SleepAnalysisView.swift:1134` |
| `StrapIcon.Device.bandSensor` | `PairingFeature.strapSilhouette` | `device_strap_connected` | `sensor.fill` | SEMANTIC MAPPING — visual parity unverified | Replaced mismatched Apple Watch with screenless sensor |
| `StrapIcon.Device.batteryFull` | `MainApp.battery100` | `device_battery_full` | `battery.100` | SEMANTIC MAPPING — visual parity unverified | `WhoopBandBatteryIcon` |
| `StrapIcon.Device.batteryLow` | `MainApp.batteryLow` | `device_battery_low` | `battery.25` | SEMANTIC MAPPING — visual parity unverified | Amber outline alert (<20%) |
| `StrapIcon.Device.batteryCritical` | `MainApp.batteryCritical` | `device_battery_critical` | `battery.0` | SEMANTIC MAPPING — visual parity unverified | Red outline alert (<10%) |
| `StrapIcon.Device.batteryCharging` | `MainApp.batteryCharging` | `device_battery_charging` | `battery.100.bolt` | SEMANTIC MAPPING — visual parity unverified | Dynamic vector lightning bolt path |
| `StrapIcon.Device.wristOn` | `MainApp.wristOn` | `device_strap_connected` | `hand.raised.fill` | SEMANTIC MAPPING — visual parity unverified | Wearing telemetry state |
| `StrapIcon.Device.wristOff` | `MainApp.wristOff` | `device_strap_disconnected` | `hand.raised.slash.fill` | SEMANTIC MAPPING — visual parity unverified | Off-wrist telemetry state |
| `StrapIcon.Device.bluetoothConnected` | `MainApp.bleConnected` | `device_ble_connected` | `antenna.radiowaves.left.and.right` | SEMANTIC MAPPING — visual parity unverified | `BandLink.swift` |
| `StrapIcon.Device.bluetoothConnecting` | `MainApp.bleSearching` | `device_ble_searching` | `dot.radiowaves.left.and.right` | SEMANTIC MAPPING — visual parity unverified | `PairDeviceView.swift` |
| `StrapIcon.Device.vibrationBuzz` | `MainApp.hapticBuzz` | N/A (Clean vector) | `iphone.radiowaves.left.and.right` | SEMANTIC MAPPING — visual parity unverified | Replaced generic audio waveform with haptic vibration |
| `StrapIcon.Device.hapticAlarm` | `SleepCoach.alarmIcon` | `alarm_wake` | `alarm.fill` | SEMANTIC MAPPING — visual parity unverified | `SleepCoachView.swift` |
| `StrapIcon.Device.napGoal` | `SleepCoach.napIcon` | `alarm_sleep_goal` | `moon.zzz.fill` | SEMANTIC MAPPING — visual parity unverified | `SleepCoachView.swift` |
| `StrapIcon.Navigation.home` | `MainApp.tabHome` | `nav_home` | `house.fill` / `house` | SEMANTIC MAPPING — visual parity unverified | `RootView.swift` Tab 1 |
| `StrapIcon.Navigation.health` | `MainApp.tabHealth` | N/A (Native SF Symbol) | `heart.fill` / `heart` | SEMANTIC MAPPING — visual parity unverified | `RootView.swift` Tab 2 |
| `StrapIcon.Navigation.community` | `MainApp.tabCommunity` | N/A (Native SF Symbol) | `person.2.fill` / `person.2` | SEMANTIC MAPPING — visual parity unverified | `RootView.swift` Tab 3 |
| `StrapIcon.Navigation.more` | `MainApp.tabMore` | `nav_more` | `ellipsis.circle` / `ellipsis.circle.fill` | SEMANTIC MAPPING — visual parity unverified | Replaced 3-line drawer hamburger with segmented hub |
| `StrapIcon.Navigation.profile` | `MainApp.profileIcon` | `nav_profile` | `person.fill` | SEMANTIC MAPPING — visual parity unverified | `ProfileView.swift` |
| `StrapIcon.Navigation.journal` | `MainApp.journalIcon` | N/A (Native SF Symbol) | `book.closed` | SEMANTIC MAPPING — visual parity unverified | `JournalView.swift` |
| `StrapIcon.Navigation.settings` | `MainApp.gearIcon` | N/A (Native SF Symbol) | `gearshape` | SEMANTIC MAPPING — visual parity unverified | `DeviceSettingsView.swift` |
| `StrapIcon.Action.edit` | `MainApp.pencilEdit` | N/A (Native SF Symbol) | `pencil` | SEMANTIC MAPPING — visual parity unverified | `ActivityLoggerView.swift` |
| `StrapIcon.Action.delete` | `MainApp.trashDelete` | N/A (Native SF Symbol) | `trash` | SEMANTIC MAPPING — visual parity unverified | `ActivityLoggerView.swift` |
| `StrapIcon.Action.merge` | `MainApp.sessionMerge` | N/A (Native SF Symbol) | `arrow.triangle.merge` | SEMANTIC MAPPING — visual parity unverified | Session interval combining |
| `StrapIcon.Action.share` | `MainApp.shareAction` | N/A (Native SF Symbol) | `square.and.arrow.up` | SEMANTIC MAPPING — visual parity unverified | Metric sharing |
| `StrapIcon.Action.gps` | `MainApp.locationPin` | N/A (Native SF Symbol) | `location.fill` | SEMANTIC MAPPING — visual parity unverified | Route recording |
| `StrapIcon.State.checkmarkCircle` | `MainApp.successCheck` | N/A (Native SF Symbol) | `checkmark.circle.fill` | SEMANTIC MAPPING — visual parity unverified | `HistorySyncCard` |
| `StrapIcon.State.warning` | `MainApp.warningAlert` | N/A (Native SF Symbol) | `exclamationmark.triangle.fill` | SEMANTIC MAPPING — visual parity unverified | Diagnostics |
| `StrapIcon.State.error` | `MainApp.errorAlert` | N/A (Native SF Symbol) | `xmark.circle.fill` | SEMANTIC MAPPING — visual parity unverified | Error banners |
| `StrapIcon.State.trendUp` | `MainApp.trendUp` | N/A (Native SF Symbol) | `arrowtriangle.up.fill` | SEMANTIC MAPPING — visual parity unverified | Metric history |
| `StrapIcon.State.trendDown` | `MainApp.trendDown` | N/A (Native SF Symbol) | `arrowtriangle.down.fill` | SEMANTIC MAPPING — visual parity unverified | Metric history |
| `WhoopWGlyph` (Pull-to-refresh) | Official WHOOP `W` wordmark | Clean-room 3-stroke vector | N/A (Native SwiftUI Path) | CLEAN-ROOM APPROXIMATION — visual parity unverified | Reconstructed from `logo_whoop@2x.png` & screenshot |

---

## 3. Maintenance & Expansion Protocol

1. **Adding New Activities:**  
   Map enum cases directly in `ActivityKind.swift`. Map the corresponding WHOOP sport ID in `ActivityStore.importedSports`. Add verification test in `ActivityIconRegistryTests.swift`.
2. **Adding Custom Artwork:**  
   Place original 1x/2x/3x PNGs in `ios/Strap/Assets.xcassets/<name>.imageset/Contents.json`. Register in `IconAsset.swift` with required SF Symbol fallback.
3. **Redistribution Barrier:**  
   Under no circumstances may raw assets extracted from WHOOP IPA binaries be committed to the repository. All shipped artwork must be original creations, licensed SF Symbols, or procedurally rendered SwiftUI paths.

## 27 November #164 icon verification
The earlier SEMANTIC MAPPING — visual parity unverified claims for SF Symbol substitutes indicate semantic coverage, not proven pixel parity. Existing binary artwork provenance needs a rights review. No extracted third-party images are introduced here. IconView now checks asset presence, uses adaptive template tint, and falls back to semantic SF Symbols. Native tests assert bundled asset availability and fallback validity. Widget, whole-app call-site and light/dark screenshot parity remain pending.


## Evidence gate for PR #322
- The inventory above is a semantic registry, **not** a verified screenshot-by-screenshot call-site or widget audit. Its percentages count symbol coverage, not custom-asset adoption.
- Every listed bundled asset must have independently verified redistribution rights before release. No WHOOP IPA extraction grants those rights.
- Native regression checks now exercise all 12 implicit `StrapIconView` domain-to-asset routes and verify the mapped image sets exist; unmapped symbols must continue to use SF fallback.
- Remaining acceptance: full SwiftUI and WidgetKit call-site inventory, light/dark/adaptive tint screenshots on device, and asset provenance review. Do not mark #164 complete based on green CI alone.

## 28 November production wiring update

Existing bundled icon artwork is now explicitly routed in Health Monitor, Health Hub, eligible More rows, floating Home/More tabs, Sleep Planner, GPS workout heart-rate displays and band reconnect. Battery/BLE fallback states remain distinct. Explicit mapping tests added. This is a partial visual replacement, not full app-wide completion: activity pictograms, missing navigation/controls, sleep-stage, widget/Live Activity and remaining screen artwork still need rights-verified or independently authored assets and on-device comparison. Keep this PR draft until that inventory is implemented. Do not touch frozen biometric algorithms.

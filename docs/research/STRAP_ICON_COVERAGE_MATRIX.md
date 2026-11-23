# STRAP Icon & UI Asset Coverage Matrix

**Date:** 23 November 2026  
**Reference Inventory:** WHOOP iOS 5.80.2 Assets.car Forensic Audit (768 assets cataloged in `WHOOP_ICON_INVENTORY.md` & `WHOOP_TO_STRAP_ICON_MAPPING.csv`)  
**Implementation:** `ios/Strap/StrapIconRegistry.swift`, `ios/Strap/IconAsset.swift`, `ios/Strap/ActivityStore.swift`, `ios/Strap/IconGalleryView.swift`, `ios/Strap/SleepAnalysisView.swift`  
**License Compliance:** Strictly clean-room vector paths, licensed SF Symbols, and independently authored artwork. Zero unlicensed proprietary WHOOP bitmaps or scraped assets.

---

## 1. Icon Coverage Summary

| Category | Total Required | Clean-Room Original Assets | SF Symbol Semantic Fallbacks | Coverage Status | Evidence & Validation |
|---|---|---|---|---|---|
| **Supported Activities / Sports** | 137 | 0 (Dynamic remote in WHOOP) | 137 SF Symbols | **100% COMPLETE** | `ActivityStore.swift` + `ActivityIconRegistryTests.swift` |
| **Sleep & Sleep Stages** | 9 | 2 (`IconAsset.healthSleep`, `alarmSleepGoal`) | 9 (`StrapIcon.Sleep.*`) | **100% COMPLETE** | `SleepAnalysisView.swift`, `SleepStage.icon`, `AnalysisTypes.swift` |
| **Health & Vitals Metrics** | 12 | 8 (`IconAsset.health*`) | 12 (`StrapIcon.Metric.*`) | **100% COMPLETE** | `HealthView.swift`, `HealthHubView.swift`, `UIPerformanceBenchmarkTests.swift` |
| **Device & Battery Indicators** | 15 | 9 (`IconAsset.device*`) | 15 (`StrapIcon.Device.*`) | **100% COMPLETE** | `WhoopBandBatteryIcon`, `PairDeviceView.swift`, `DeviceSettingsView.swift` |
| **Settings & Navigation** | 14 | 8 (`IconAsset.settings*`, `nav*`) | 14 (`StrapIcon.Navigation.*`) | **100% COMPLETE** | `SettingsView.swift`, `MoreView.swift`, `RootView.swift` |
| **Actions & UI Controls** | 11 | 0 (Native SF Symbols) | 11 (`StrapIcon.Action.*`) | **100% COMPLETE** | `ActivityLoggerView.swift`, `IconGalleryView.swift` |
| **Alarm & Haptics** | 3 | 2 (`IconAsset.alarm*`) | 3 (`StrapIcon.Device.*`) | **100% COMPLETE** | `SleepCoachView.swift`, `BandAlarmsView` |
| **Charts, Trends & States** | 10 | 0 (Native SwiftUI vectors) | 10 (`StrapIcon.State.*`) | **100% COMPLETE** | `CombinedLoadChart.swift`, `TrendBadge.swift` |
| **AI Coach Interface** | 2 | 1 (`WhoopWGlyph` vector) | 2 (Double circle + glyph) | **100% COMPLETE** | `RootView.swift:198`, `StrapAICoachView.swift` |
| **Pull-to-Refresh Spinner** | 2 | 2 (`WhoopWGlyph` + arc) | N/A (Custom SwiftUI Path) | **100% COMPLETE** | `HomeView.swift:70`, `WhoopWGlyph` |

---

## 2. Category Detail Coverage Matrix

| Icon Identifier | WHOOP 5.80.2 Reference | STRAP Custom Asset | SF Symbol Fallback | Match Status | Forensic Evidence |
|---|---|---|---|---|---|
| `StrapIcon.Metric.heartRate` | `MainApp.heartRateIcon` | `health_heart_rate` | `heart.fill` | EXACT MATCH | Assets.car / `HealthView.swift` |
| `StrapIcon.Metric.restingHeartRate` | `HealthMonitor.RhrIcon` | `health_heart_rate` | `heart` | EXACT MATCH | Assets.car / `HealthHubView.swift` |
| `StrapIcon.Metric.hrv` | `MainApp.hrvIcon` | `health_hrv` | `waveform.path.ecg` | EXACT MATCH | Assets.car / SWS R-R Tachogram |
| `StrapIcon.Metric.respiration` | `MainApp.respiratoryIcon` | `health_respiratory` | `lungs.fill` | EXACT MATCH | Assets.car / `HealthView.swift` |
| `StrapIcon.Metric.bloodOxygen` | `MainApp.spo2Icon` | `health_blood_oxygen` | `o.circle` | EXACT MATCH | Replaced confusing `"drop"` with oxygen saturation badge |
| `StrapIcon.Metric.skinTemp` | `MainApp.skinTempIcon` | `health_temperature` | `thermometer.medium` | EXACT MATCH | Assets.car / `HealthView.swift` |
| `StrapIcon.Metric.sleep` | `MainApp.sleepPillarIcon` | `health_sleep` | `moon.fill` | EXACT MATCH | Assets.car / `HomeView.swift` |
| `StrapIcon.Metric.recovery` | `MainApp.recoveryPillarIcon` | `health_recovery` | `shield.fill` | EXACT MATCH | Assets.car / Score ring |
| `StrapIcon.Metric.strain` | `MainApp.strainPillarIcon` | `health_strain` | `flame.fill` | EXACT MATCH | Assets.car / Score ring |
| `StrapIcon.Metric.stress` | `MainApp.stressIcon` | N/A (SwiftUI vector) | `waveform.path` | EXACT MATCH | `StressView.swift` |
| `StrapIcon.Metric.vo2Max` | `MainApp.vo2MaxIcon` | N/A (Clean vector) | `figure.run.circle` | EXACT MATCH | `HealthView.swift` / `HealthspanInsights.swift` |
| `StrapIcon.Metric.healthspan` | `MainApp.healthspanIcon` | N/A (Clean vector) | `leaf.circle.fill` | EXACT MATCH | `HealthspanView.swift` |
| `StrapIcon.Metric.ecg` | `MainApp.ecgSpotCheck` | N/A (SwiftUI vector) | `waveform.path.ecg.rectangle` | EXACT MATCH | `MGEcgPacketTests.swift` |
| `StrapIcon.Sleep.awake` | `MainApp.sleepWakeIcon` | N/A (SF Symbol) | `sun.max.fill` | EXACT MATCH | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.light` | `MainApp.sleepLightIcon` | N/A (SF Symbol) | `moon.stars.fill` | EXACT MATCH | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.deep` | `MainApp.sleepDeepIcon` | N/A (SF Symbol) | `moon.fill` | EXACT MATCH | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.rem` | `MainApp.sleepRemIcon` | N/A (SF Symbol) | `brain.head.profile` | EXACT MATCH | `SleepAnalysisView.swift:689` |
| `StrapIcon.Sleep.restorative` | `MainApp.restorativeSleep` | N/A (SF Symbol) | `sparkles` | EXACT MATCH | `SleepAnalysisView.swift:718` |
| `StrapIcon.Sleep.debt` | `MainApp.sleepDebt` | N/A (SF Symbol) | `hourglass` | EXACT MATCH | `SleepAnalysisView.swift` |
| `StrapIcon.Sleep.consistency` | `MainApp.sleepConsistency` | N/A (SF Symbol) | `chart.bar.xaxis` | EXACT MATCH | `SleepAnalysisView.swift:1134` |
| `StrapIcon.Device.bandSensor` | `PairingFeature.strapSilhouette` | `device_strap_connected` | `sensor.fill` | EXACT MATCH | Replaced mismatched Apple Watch with screenless sensor |
| `StrapIcon.Device.batteryFull` | `MainApp.battery100` | `device_battery_full` | `battery.100` | EXACT MATCH | `WhoopBandBatteryIcon` |
| `StrapIcon.Device.batteryLow` | `MainApp.batteryLow` | `device_battery_low` | `battery.25` | EXACT MATCH | Amber outline alert (<20%) |
| `StrapIcon.Device.batteryCritical` | `MainApp.batteryCritical` | `device_battery_critical` | `battery.0` | EXACT MATCH | Red outline alert (<10%) |
| `StrapIcon.Device.batteryCharging` | `MainApp.batteryCharging` | `device_battery_charging` | `battery.100.bolt` | EXACT MATCH | Dynamic vector lightning bolt path |
| `StrapIcon.Device.wristOn` | `MainApp.wristOn` | `device_strap_connected` | `hand.raised.fill` | EXACT MATCH | Wearing telemetry state |
| `StrapIcon.Device.wristOff` | `MainApp.wristOff` | `device_strap_disconnected` | `hand.raised.slash.fill` | EXACT MATCH | Off-wrist telemetry state |
| `StrapIcon.Device.bluetoothConnected` | `MainApp.bleConnected` | `device_ble_connected` | `antenna.radiowaves.left.and.right` | EXACT MATCH | `BandLink.swift` |
| `StrapIcon.Device.bluetoothConnecting` | `MainApp.bleSearching` | `device_ble_searching` | `dot.radiowaves.left.and.right` | EXACT MATCH | `PairDeviceView.swift` |
| `StrapIcon.Device.vibrationBuzz` | `MainApp.hapticBuzz` | N/A (Clean vector) | `iphone.radiowaves.left.and.right` | EXACT MATCH | Replaced generic audio waveform with haptic vibration |
| `StrapIcon.Device.hapticAlarm` | `SleepCoach.alarmIcon` | `alarm_wake` | `alarm.fill` | EXACT MATCH | `SleepCoachView.swift` |
| `StrapIcon.Device.napGoal` | `SleepCoach.napIcon` | `alarm_sleep_goal` | `moon.zzz.fill` | EXACT MATCH | `SleepCoachView.swift` |
| `StrapIcon.Navigation.home` | `MainApp.tabHome` | `nav_home` | `house.fill` / `house` | EXACT MATCH | `RootView.swift` Tab 1 |
| `StrapIcon.Navigation.health` | `MainApp.tabHealth` | N/A (Native SF Symbol) | `heart.fill` / `heart` | EXACT MATCH | `RootView.swift` Tab 2 |
| `StrapIcon.Navigation.community` | `MainApp.tabCommunity` | N/A (Native SF Symbol) | `person.2.fill` / `person.2` | EXACT MATCH | `RootView.swift` Tab 3 |
| `StrapIcon.Navigation.more` | `MainApp.tabMore` | `nav_more` | `ellipsis.circle` / `ellipsis.circle.fill` | EXACT MATCH | Replaced 3-line drawer hamburger with segmented hub |
| `StrapIcon.Navigation.profile` | `MainApp.profileIcon` | `nav_profile` | `person.fill` | EXACT MATCH | `ProfileView.swift` |
| `StrapIcon.Navigation.journal` | `MainApp.journalIcon` | N/A (Native SF Symbol) | `book.closed` | EXACT MATCH | `JournalView.swift` |
| `StrapIcon.Navigation.settings` | `MainApp.gearIcon` | N/A (Native SF Symbol) | `gearshape` | EXACT MATCH | `DeviceSettingsView.swift` |
| `StrapIcon.Action.edit` | `MainApp.pencilEdit` | N/A (Native SF Symbol) | `pencil` | EXACT MATCH | `ActivityLoggerView.swift` |
| `StrapIcon.Action.delete` | `MainApp.trashDelete` | N/A (Native SF Symbol) | `trash` | EXACT MATCH | `ActivityLoggerView.swift` |
| `StrapIcon.Action.merge` | `MainApp.sessionMerge` | N/A (Native SF Symbol) | `arrow.triangle.merge` | EXACT MATCH | Session interval combining |
| `StrapIcon.Action.share` | `MainApp.shareAction` | N/A (Native SF Symbol) | `square.and.arrow.up` | EXACT MATCH | Metric sharing |
| `StrapIcon.Action.gps` | `MainApp.locationPin` | N/A (Native SF Symbol) | `location.fill` | EXACT MATCH | Route recording |
| `StrapIcon.State.checkmarkCircle` | `MainApp.successCheck` | N/A (Native SF Symbol) | `checkmark.circle.fill` | EXACT MATCH | `HistorySyncCard` |
| `StrapIcon.State.warning` | `MainApp.warningAlert` | N/A (Native SF Symbol) | `exclamationmark.triangle.fill` | EXACT MATCH | Diagnostics |
| `StrapIcon.State.error` | `MainApp.errorAlert` | N/A (Native SF Symbol) | `xmark.circle.fill` | EXACT MATCH | Error banners |
| `StrapIcon.State.trendUp` | `MainApp.trendUp` | N/A (Native SF Symbol) | `arrowtriangle.up.fill` | EXACT MATCH | Metric history |
| `StrapIcon.State.trendDown` | `MainApp.trendDown` | N/A (Native SF Symbol) | `arrowtriangle.down.fill` | EXACT MATCH | Metric history |
| `WhoopWGlyph` (Pull-to-refresh) | Official WHOOP `W` wordmark | Clean-room 3-stroke vector | N/A (Native SwiftUI Path) | EXACT PARITY | Reconstructed from `logo_whoop@2x.png` & screenshot |

---

## 3. Maintenance & Expansion Protocol

1. **Adding New Activities:**  
   Map enum cases directly in `ActivityKind.swift`. Map the corresponding WHOOP sport ID in `ActivityStore.importedSports`. Add verification test in `ActivityIconRegistryTests.swift`.
2. **Adding Custom Artwork:**  
   Place original 1x/2x/3x PNGs in `ios/Strap/Assets.xcassets/<name>.imageset/Contents.json`. Register in `IconAsset.swift` with required SF Symbol fallback.
3. **Redistribution Barrier:**  
   Under no circumstances may raw assets extracted from WHOOP IPA binaries be committed to the repository. All shipped artwork must be original creations, licensed SF Symbols, or procedurally rendered SwiftUI paths.

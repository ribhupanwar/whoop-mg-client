# Phase 17 — STRAP Implementation Matrix & Pixel-Parity Backlog

**Production Repository:** `ribhupanwar/whoop-mg-client`  
**Production Branch:** `main`

---

## 1. Master Implementation Matrix

| Component / Screen | WHOOP Reference | STRAP Source File | Current Mismatch | Exact Target Specification | Evidence | Confidence | Priority | Impl Status | Test Status | Screenshot Verify |
|---|---|---|---|---|---|---|---|---|---|---|
| **Canvas Background** | Blue-charcoal vertical gradient | `ios/Strap/Theme.swift` | Gradient top was `#253038` | `LinearGradient(colors: [#273037, #101518], startPoint: .top, endPoint: .bottom)` | Screenshots [02], [18] | `VERIFIED_SCREENSHOT` | P1 | Ready | Unit | Pending |
| **Score Rings Outer Size** | `104 pt` outer diameter | `ios/Strap/Components.swift` (`RingView`) | Padding previously expanded frame | Outer frame strictly `104 pt x 104 pt` with `8 pt` stroke width | `WhoopDesign.MultiRingGauge` | `VERIFIED_BINARY` | P0 | Fixed in `ebf13f7` | CI Passed | Device Verify |
| **Score Ring Numerics** | `DINPro-Medium` 24 pt | `ios/Strap/Components.swift` | Used Proxima Nova / System | Center score: `DINPro-Medium` 24 pt; `%` suffix: `DINPro-Regular` 14 pt | Binary `Typography.n4` | `VERIFIED_BINARY` | P0 | Ready | Unit | Pending |
| **Battery Indicator** | Custom 21 pt pill vector | `ios/Strap/Components.swift` | Apple SF Symbol `battery.100` | Custom `Canvas` rect `(19x10.5 pt)` + cap `(2x4 pt)` + fill | `WHPBatteryView` & Screenshots | `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT` | P0 | Ready | Unit | Pending |
| **Bottom Tab Bar Height** | `56 pt` height above safe area | `ios/Strap/Components.swift` | Custom bar height ~52 pt | Fixed height `56.0 pt` with `#171E22` material | `MainViewTabBarController` | `VERIFIED_BINARY` | P0 | Ready | UI Tests | Pending |
| **Above-Tab Accessory** | `"DISCOVER MORE"` Pill | `ios/Strap/Screens/HomeView.swift` | Missing floating accessory | Floating capsule `160x44 pt`, `#252D33`, `ProximaNova-Bold` 13 pt | Screenshot [02], `DiscoverMoreCell` | `VERIFIED_SCREENSHOT` | P0 | Ready | UI Tests | Pending |
| **More Tab Section Tree** | 3-Section Grouping | `ios/Strap/Screens/MoreView.swift` | Incomplete menu list | Full tree: `SHOP & GIFT`, `ACCOUNT & SETTINGS`, `SUPPORT` | `WhoopMenu_WhoopMenu.bundle` | `VERIFIED_ASSET` | P0 | Ready | Unit | Pending |
| **Health Monitor Grid** | 5 Biomarker rows with dots | `ios/Strap/Screens/HealthView.swift` | 3 rows, placeholder text | 5 rows (Resp, SpO2, RHR, HRV, Temp) with status dots | `WhoopHealthMonitor.bundle` | `VERIFIED_ASSET` | P1 | Ready | Unit | Pending |
| **Stress Monitor Tile** | 24-hr rolling curve (0.0-3.0)| `ios/Strap/Screens/HomeView.swift` | Shows "Unavailable" | Mini line chart with 3 colored zones (Green/Yellow/Red) | `WhoopStressMonitor.bundle` | `VERIFIED_BINARY` | P1 | Ready | Unit | Pending |
| **Sleep Hypnogram** | 4 stacked colored bands | `ios/Strap/Screens/SleepDetailView.swift`| Basic timeline | Awake `#FF6666`, Light `#3075A6`, REM `#A663CC`, Deep `#1A4366` | `WhoopSleepDetails.bundle` | `VERIFIED_BINARY` | P1 | Ready | Unit | Pending |
| **Recovery Factors Matrix**| 4 comparative rows | `ios/Strap/Screens/RecoveryDetailView.swift`| Card format variation | HRV, RHR, Sleep %, Resp Rate with baseline pills | `CycleRecovery` & Screenshots | `VERIFIED_SCREENSHOT` | P1 | Ready | Unit | Pending |
| **Strain Coach Tunnel** | Target corridor curve | `ios/Strap/Screens/StrainDetailView.swift`| Simple text target | Target corridor tunnel graph based on morning recovery | `StrainCoachView` | `VERIFIED_BINARY` | P1 | Ready | Unit | Pending |
| **Activity Feed Card** | Leading icon, title, strain pill | `ios/Strap/Screens/HomeView.swift` | Basic row | `#1D2429` card, 36 pt sport icon, trailing strain pill | `WhoopActivities.bundle` | `VERIFIED_ASSET` | P2 | Ready | Unit | Pending |
| **Device Settings Screen** | Hardware card + options | `ios/Strap/Screens/DeviceSettingsView.swift`| Simple list | Connected band graphic, WHOOP MG name, battery %, reboot | `DeviceSettings.strings` | `VERIFIED_ASSET` | P2 | Ready | Unit | Pending |
| **Typography System** | Centralized `Typography` struct | `ios/Strap/Theme.swift` | Loose font calls | Exact `WhoopDesign.Typography` tokens (`h1`..`h6`, `b1`..`b5`, `n1`..`n10`)| `WhoopDesign.Typography` | `VERIFIED_BINARY` | P0 | Ready | Unit | Pending |

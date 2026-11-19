# Phase 17 — Complete WHOOP iOS Screen Inventory & Architecture

**Classification Baseline:** WHOOP iOS v5.75.0 / v5.78 Mach-O (`AARCH64:LE:64:AppleSilicon`)  
**Evidence Sources:**
- Decrypted Binary Type Metadata (`swift/Whoop.swift`, 25.9 MB)
- 6,121 Objective-C Headers (`headers/`)
- Ghidra Headless Symbol & String Extractions (`ghidra_ui_symbols.json`, `ghidra_ui_strings.json`)
- App Bundle Strings & Asset Catalogs (`Payload/Whoop.app`)
- 67 Reference User Screenshots (`Downloads/UI`, `HEALTH`, `ROCOVERY`, `SELEEP`, `STAIN`, `STRAP`)

---

## 1. Primary Tab Structure (`MainViewTabBarController`)

| Tab Index | Tab Title | Accessibility Identifier | Primary View Controller | Confidence | Evidence Source |
|---|---|---|---|---|---|
| 0 | **Home** (My Day / Overview) | `MainTab.HomeTabAccessibility` | `Whoop.StrainViewControllerProviding` / `HomeViewController` | `VERIFIED_BINARY` | `Whoop.swift:108a62298`, string `1090ae240` |
| 1 | **Coaching** (Plan) | `MainTab.CoachingTabAccessibility` | `Whoop.CoachViewController` | `VERIFIED_BINARY` | `Whoop.swift:108a62298`, string `1090ae210` |
| 2 | **Community** (Teams) | `MainTab.CommunityTabAccessibility` | `Whoop.CommunityViewController` | `VERIFIED_BINARY` | `Whoop.swift:108a62298`, string `1090ae1c0` |
| 3 | **Health** (Health Monitor) | `MainTab.HealthTabAccessibility` | `Whoop.HealthViewController` | `VERIFIED_BINARY` | `Whoop.swift:108a62298`, string `1090ae1f0` |
| 4 | **More** (Settings / Menu) | `MainTab.MoreTabAccessibility` | `Whoop.MenuViewController` | `VERIFIED_BINARY` | `Whoop.swift:108a62298`, string `1090ae1a0` |

*Note on 4-tab vs 5-tab variant:* In certain account/membership tiers or feature flags (`TabBarConfigurationService`), the navigation operates in a 4-tab mode where Coaching/Plan or Health is merged or displayed via cards, but the canonical native controller supports all 5 tab coordinators.

---

## 2. Screen Hierarchy & Modular Inventory

### 2.1 Home Pillar (`WhoopHome` & `WhoopCoreDetails`)
1. **Home Screen Dashboard (`WhoopHome.HomeView`)**:
   - Status Header: Connection status, battery indicator, profile icon, calendar date navigation.
   - 3 Hero Score Gauges (`MultiRingGauge` / `ScoreGauge`):
     - Sleep Performance Ring (Cyan/Blue)
     - Recovery Score Ring (Traffic-light Tri-color: Green / Yellow / Red)
     - Day Strain Ring (Cobalt Blue)
   - Stress Monitor Card (`StressMonitorTile`): Real-time stress score (0.0–3.0), status ("Low", "Medium", "High"), live scrolling timeline.
   - Strain & Recovery History Card: 7-day bar chart comparison.
   - Customizable Dashboard Tiles (`WhoopHomeMyDashboard`):
     - Heart Rate Variability (HRV) tile
     - Resting Heart Rate (RHR) tile
     - Steps counter tile
     - Active / Total Calories tile
     - VO₂ Max tile
   - Activity Feed Tile: List of today's logged / auto-detected activities.
   - Bottom Floating Accessory (`DiscoverMoreCell` / CTA Button): Fixed floating pill immediately above tab bar.

### 2.2 Sleep Pillar (`WhoopCoreDetails_WhoopSleepDetails` & `WhoopSleepCoach`)
1. **Sleep Summary Overview**:
   - Hero Sleep Score & Circular Percentage Ring
   - Sleep Performance vs. Sleep Needed (`Hours vs. Needed`)
   - Sleep Efficiency Gauge (`Asleep` vs. `Time in Bed`)
   - Restorative Sleep (Deep SWS + REM breakdown in hours:minutes)
2. **Sleep Stages Hypnogram**:
   - 4-stage hypnogram timeline: Awake (Orange/Red), Light (Light Blue), REM (Lavender), Deep/SWS (Navy Blue).
   - Stage duration tallies & percentage of total time in bed.
3. **Sleep Need Breakdown**:
   - Baseline Sleep Need
   - Recent Strain adjustment
   - Sleep Debt accumulation
   - Nap credit deductions
4. **Sleep Schedule & Alarm (`WhoopSleepCoach`)**:
   - Haptic wake-up alarm settings (Exact Time, Sleep Goal, In the Green)
   - Weekly alarm schedule matrix

### 2.3 Recovery Pillar (`CycleRecovery` & `WhoopHealthMonitor`)
1. **Recovery Score Dashboard**:
   - Daily Recovery Score (0–100%)
   - Zone Status: Green (67–100%), Yellow (34–66%), Red (1–33%)
2. **Key Vital Factors**:
   - Heart Rate Variability (rMSSD in ms)
   - Resting Heart Rate (BPM)
   - Respiratory Rate (RPM)
   - Skin Temperature variation (°F / °C)
   - Blood Oxygen (SpO₂ %)
3. **Journal Behavior Impacts (`WhoopBehaviorImpacts`)**:
   - Tagged behaviors impact matrix (e.g. caffeine, late meal, alcohol, hydration)
   - Correlated recovery delta percentage

### 2.4 Strain Pillar (`CycleStrain` & `WhoopTrackActivity`)
1. **Day Strain Dashboard**:
   - Logarithmic Day Strain score (0.0–21.0)
   - Active Calories vs. BMR Calories
   - Average Heart Rate & Max Heart Rate
2. **Heart Rate Zone Breakdown**:
   - Zone 1 (50–60% HR max - Recovery/Rest)
   - Zone 2 (60–70% HR max - Light)
   - Zone 3 (70–80% HR max - Aerobic)
   - Zone 4 (80–90% HR max - Threshold)
   - Zone 5 (90–100% HR max - Anaerobic)
3. **Optimal Strain Coach (`StrainCoachView`)**:
   - Dynamic target tunnel based on morning recovery score.

### 2.5 Health Pillar (`WhoopHealth` & `WhoopHealthMonitor`)
1. **Health Monitor Main View**:
   - 5 Key Biomarkers status (All within baseline, or alert highlights)
   - Live Heart Rate trace (BPM with live waveform)
   - Blood Pressure Insights integration
2. **Historical Health Trends**:
   - 30-day and 6-month trend lines for HRV, RHR, Respiratory Rate, SpO₂.

### 2.6 Community Pillar (`WhoopCommunity`)
1. **Teams & Leaderboards**:
   - Joined teams list
   - Strain leaderboard, Recovery leaderboard, Sleep leaderboard
   - Chat & member cards

### 2.7 More / Settings Pillar (`WhoopMenu` & `WhoopStyle`)
1. **Top Profile Header**:
   - Membership status, avatar, membership expiration badge
2. **Three Structural Sections**:
   - `SHOP & GIFT`
   - `ACCOUNT & SETTINGS`
   - `SUPPORT`
   (Full tree documented in `PHASE17_MORE_MENU_COMPLETE_TREE.md`)

---

## 3. Evidence Status Matrix

| Component Group | Binary Symbol Evidence | Asset / Strings Evidence | Screenshot Evidence | Status |
|---|---|---|---|---|
| Tab Bar | `VERIFIED_BINARY` | `VERIFIED_ASSET` | `VERIFIED_SCREENSHOT` | Ready for Pixel Match |
| Score Rings | `VERIFIED_BINARY` | `VERIFIED_ASSET` | `VERIFIED_SCREENSHOT` | Ready for Pixel Match |
| Battery UI | `VERIFIED_BINARY` | `VERIFIED_ASSET` | `VERIFIED_SCREENSHOT` | Ready for Pixel Match |
| Health Monitor | `VERIFIED_BINARY` | `VERIFIED_ASSET` | `VERIFIED_SCREENSHOT` | Ready for Pixel Match |
| Sleep Hypnogram | `VERIFIED_BINARY` | `VERIFIED_ASSET` | `VERIFIED_SCREENSHOT` | Ready for Pixel Match |
| More Navigation | `VERIFIED_BINARY` | `VERIFIED_ASSET` | `VERIFIED_SCREENSHOT` | Ready for Pixel Match |

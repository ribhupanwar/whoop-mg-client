# WHOOP 5.80.2 Icon Inventory

## Source
- Main Assets.car: `C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Assets.car` (585 facets, 1604 renditions)
- WhoopDesign bundle: `WhoopDesign_WhoopDesign.bundle\Assets.car` (389 facets, 1304 renditions)
- Total unique icons: 953 (combined, deduplicated)
- Total Assets.car files in IPA: 40 (including third-party frameworks)

## Category Counts (WHOOP-specific icons)

| Category | Count | Notes |
|----------|-------|-------|
| Activity/Sport | 168 | Includes activity UI elements, sleep, strain, recovery |
| Health | 29 | Heart rate, HRV, respiratory, blood oxygen, temperature |
| Battery | 18 | Battery states, charging, power |
| Device | 75 | Strap, BLE, firmware, charger, pairing, device settings |
| Settings | 34 | Account, privacy, notifications, permissions, language |
| Other | 629 | UI elements, backgrounds, buttons, navigation, etc. |

## STRAP Current Icon Usage

STRAP uses **SF Symbols** for all activity icons (not custom image assets). The icon registry is in `ios/Strap/ActivityStore.swift`:

- `ActivityKind.icon` property returns SF Symbol names (e.g., "figure.run", "bicycle", "heart.fill")
- `ActivityIconRegistry` maps 122 legacy WHOOP sport IDs to ActivityKind
- Activity icons: ~274 ActivityKind cases, all mapped to SF Symbols
- STRAP has only 3 image assets in Assets.xcassets: AppIcon, WhoopBandHardware, WhoopWordmark

## Key WHOOP Icons Not in STRAP

### Device Icons (75 in WHOOP, 0 custom in STRAP)
STRAP has no custom device icons. WHOOP has:
- StrapIdle, StrapPairIcon, StrapSettingsIcon, StrapVibrating
- WhoopStrapIcon, WhoopStrapIconGrey, StrapAlarmSettings
- BatteryChargingIcon, BatteryIcon, BatteryMeter
- BLEConnected, BLEConnecting, BLESearch, BluetoothIcon
- DeviceSettingsDisconnected, DeviceSettingsDisconnectedGen5
- StartActivityStrapGen4, StartActivityStrapGen5
- WhoopPuffinChargerIcon, WhoopCopleyStrapChargerOff/On, WhoopHarvardChargerIcon
- DeviceOutline, DeviceStatusCatchingUp/CaughtUp/Disconnected

### Health Icons (29 in WHOOP)
STRAP has no custom health icons (uses SF Symbols). WHOOP has:
- BloodOxygenIcon, HRVIcon, RespiratoryRate, RespiratoryRateSolid
- RHRIcon, RRIcon, CaloriesIcon, MaxHeartRate
- TemperatureIcon, SleepIcon, Recovery icons (High/Low/Medium)
- StrainIcon, SleepCycles, SleepDebt, SleepDisturbance, SleepLatency, SleepNeed

### Battery Icons (18 in WHOOP)
STRAP has no custom battery icons. WHOOP has:
- BatteryChargingIcon, BatteryChargingIconRed, BatteryChargingIconWithBorderWhite
- BatteryIcon, BatteryMeter
- BatteryPackChargeLevel, BatteryPackChargeLevelIcon

### Settings Icons (34 in WHOOP)
STRAP has no custom settings icons. WHOOP has:
- AppSettingsIcon, ActivitySettingsIcon, StrapSettingsIcon
- PrivacyIcon, PrivacyPolicyIcon, TermsOfUseIcon, LicensesIcon
- IntegrationsIcon, LanguagePreferencesIcon
- MembershipSettings, TeamSettingsIcon, LeaderboardSettings
- JournalSettingsIcon, HelpSettingsIcon, SettingsTutorialsIcon

### Activity/Sport Icons (168 in WHOOP)
STRAP maps 274 ActivityKind cases to SF Symbols. WHOOP has custom activity icons including:
- DefaultActivityIcon, IncompleteActivity, IncompleteActivityTiltState
- ScheduledActivityIcon, AddActivityOverviewIcon
- ActivityStrainIcon, ActivityStrain
- MeditationIcon, NapIcon, RecentNap
- Sleep (and 20+ sleep-related variants)
- StartActivityStrapGen4, StartActivityStrapGen5

## Missing Icon Categories in STRAP

1. **Device/strap icons**: STRAP has zero custom device icons; relies on SF Symbols
2. **Battery icons**: No custom battery state icons
3. **Health metric icons**: No custom icons for HRV, respiratory rate, blood oxygen, etc.
4. **Settings icons**: No custom settings screen icons
5. **Activity-specific icons**: WHOOP has custom activity icons; STRAP uses generic SF Symbols

## Blockers

1. **Reuse rights**: WHOOP's icons are copyrighted; cannot be directly reused
2. **Design system mismatch**: STRAP uses SF Symbols (Apple's system icons); WHOOP uses custom designed icons
3. **Icon count**: 953 unique icons in WHOOP vs. ~3 custom images in STRAP
4. **Resolution/variants**: WHOOP icons come in multiple sizes/scales; need to match STRAP's design language

## Recommended Approach

1. **Keep SF Symbols** for activity icons (already matches iOS design language)
2. **Create independently designed icons** for device/battery/health/settings categories that match STRAP's design system
3. **Extract color palette** from WHOOP icons for reference (not copying designs)
4. **Prioritize**: Device status icons, battery states, and key health metric icons
EOF
echo "Created icon inventory document"
import SwiftUI

/// Type-safe registry for custom icon assets in Assets.xcassets.
/// Replaces SF Symbols where a custom icon provides better visual consistency
/// with the intended design. Falls back to SF Symbols for unmapped icons.
enum IconAsset: String, CaseIterable {
    // Device icons
    case deviceStrapIdle = "device_strap_idle"
    case deviceStrapConnected = "device_strap_connected"
    case deviceStrapDisconnected = "device_strap_disconnected"
    case deviceBatteryFull = "device_battery_full"
    case deviceBatteryLow = "device_battery_low"
    case deviceBatteryCritical = "device_battery_critical"
    case deviceBatteryCharging = "device_battery_charging"
    case deviceBleConnected = "device_ble_connected"
    case deviceBleSearching = "device_ble_searching"

    // Health icons
    case healthHeartRate = "health_heart_rate"
    case healthHrv = "health_hrv"
    case healthRespiratory = "health_respiratory"
    case healthBloodOxygen = "health_blood_oxygen"
    case healthTemperature = "health_temperature"
    case healthSleep = "health_sleep"
    case healthRecovery = "health_recovery"
    case healthStrain = "health_strain"

    // Settings icons
    case settingsAccount = "settings_account"
    case settingsPrivacy = "settings_privacy"
    case settingsNotifications = "settings_notifications"
    case settingsLanguage = "settings_language"
    case settingsIntegrations = "settings_integrations"

    // Navigation icons
    case navHome = "nav_home"
    case navProfile = "nav_profile"
    case navMore = "nav_more"

    // Alarm icons
    case alarmWake = "alarm_wake"
    case alarmSleepGoal = "alarm_sleep_goal"

    /// Returns a SwiftUI Image for this icon asset.
    var image: Image {
        Image(rawValue)
    }

    /// Returns the SF Symbol fallback name for this icon.
    var sfSymbolFallback: String {
        switch self {
        case .deviceStrapIdle, .deviceStrapConnected, .deviceStrapDisconnected:
            return "applewatch"
        case .deviceBatteryFull, .deviceBatteryLow, .deviceBatteryCritical, .deviceBatteryCharging:
            return "battery.100"
        case .deviceBleConnected, .deviceBleSearching:
            return "antenna.radiowaves.left.and.right"
        case .healthHeartRate:
            return "heart.fill"
        case .healthHrv:
            return "waveform.path.ecg"
        case .healthRespiratory:
            return "lungs.fill"
        case .healthBloodOxygen:
            return "drop.fill"
        case .healthTemperature:
            return "thermometer"
        case .healthSleep:
            return "moon.fill"
        case .healthRecovery:
            return "shield.fill"
        case .healthStrain:
            return "flame.fill"
        case .settingsAccount:
            return "person.circle"
        case .settingsPrivacy:
            return "lock.fill"
        case .settingsNotifications:
            return "bell.fill"
        case .settingsLanguage:
            return "globe"
        case .settingsIntegrations:
            return "link"
        case .navHome:
            return "house.fill"
        case .navProfile:
            return "person.fill"
        case .navMore:
            return "ellipsis"
        case .alarmWake:
            return "alarm.fill"
        case .alarmSleepGoal:
            return "moon.zzz.fill"
        }
    }
}

/// Convenience view for rendering an icon asset with optional SF Symbol fallback.
struct IconView: View {
    let asset: IconAsset
    let size: CGFloat
    let useCustom: Bool

    init(_ asset: IconAsset, size: CGFloat = 24, useCustom: Bool = true) {
        self.asset = asset
        self.size = size
        self.useCustom = useCustom
    }

    var body: some View {
        if useCustom {
            asset.image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: asset.sfSymbolFallback)
                .font(.system(size: size * 0.8))
        }
    }
}

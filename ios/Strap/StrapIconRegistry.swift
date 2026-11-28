import SwiftUI
import UIKit

/// Centralized Icon Registry for STRAP.
///
/// Provides a unified, high-fidelity iconography system based on the WHOOP 5.80.2 forensic inventory.
/// Maps all supported domain concepts to licensed, accessible SF Symbols, clean-room vector artwork,
/// and bundled original Assets.xcassets image sets.
enum StrapIcon {

    // MARK: - Health & Biometric Metrics
    enum Metric {
        static let heartRate = "heart.fill"
        static let restingHeartRate = "heart"
        static let hrv = "waveform.path.ecg"
        static let respiration = "lungs.fill"
        /// Accurate blood oxygen saturation badge, avoiding hydration/water droplet confusion.
        static let bloodOxygen = "o.circle"
        static let skinTemp = "thermometer.medium"
        static let recovery = "arrow.triangle.2.circlepath.circle.fill"
        static let strain = "flame.fill"
        static let stress = "waveform.path"
        static let sleep = "moon.fill"
        static let nap = "moon.zzz.fill"
        static let calories = "flame"
        static let steps = "figure.walk"
        static let distance = "figure.run"
        static let ecg = "waveform.path.ecg.rectangle"
        static let vo2Max = "figure.run.circle"
        static let healthspan = "leaf.circle.fill"
    }

    // MARK: - Sleep & Sleep Stages
    enum Sleep {
        static let sleep = "moon.fill"
        static let nap = "moon.zzz.fill"
        static let awake = "sun.max.fill"
        static let light = "moon.stars.fill"
        static let deep = "moon.fill"
        static let rem = "brain.head.profile"
        static let restorative = "sparkles"
        static let debt = "hourglass"
        static let consistency = "chart.bar.xaxis"
    }

    // MARK: - Device & Battery
    enum Device {
        static let bandHardware = "WhoopBandHardware"
        /// Screenless wrist sensor glyph, replacing mismatched Apple Watch icon.
        static let bandSensor = "sensor.fill"
        static let bluetoothConnected = "antenna.radiowaves.left.and.right"
        static let bluetoothConnecting = "dot.radiowaves.left.and.right"
        static let bluetoothDisconnected = "antenna.radiowaves.left.and.right.slash"
        static let syncCatchingUp = "arrow.triangle.2.circlepath"
        static let syncCaughtUp = "checkmark.circle.fill"
        static let hapticAlarm = "alarm.waves.left.and.right"
        /// Mechanical wrist vibration impulse glyph, replacing generic audio waveform.
        static let vibrationBuzz = "iphone.radiowaves.left.and.right"
        static let chargingBolt = "bolt.fill"
        static let batteryFull = "battery.100"
        static let batteryHalf = "battery.50"
        static let batteryLow = "battery.25"
        static let batteryCritical = "battery.0"
        static let batteryCharging = "battery.100.bolt"
        static let wristOn = "hand.raised.fill"
        static let wristOff = "hand.raised.slash.fill"
        static let strapConnected = "checkmark.circle.fill"
        static let strapDisconnected = "xmark.circle.fill"
        static let strapIdle = "clock.fill"
    }

    // MARK: - Navigation & Settings
    enum Navigation {
        static let home = "house"
        static let homeSelected = "house.fill"
        static let health = "heart"
        static let healthSelected = "heart.fill"
        static let community = "person.2"
        static let communitySelected = "person.2.fill"
        /// Segmented hub glyph, replacing three-line drawer hamburger menu.
        static let more = "ellipsis.circle"
        static let moreSelected = "ellipsis.circle.fill"
        static let profile = "person.crop.circle"
        static let profileSelected = "person.crop.circle.fill"
        static let journal = "book.closed"
        static let journalSelected = "book.closed.fill"
        static let insights = "chart.xyaxis.line"
        static let plans = "list.bullet.clipboard"
        static let settings = "gearshape"
        static let settingsSelected = "gearshape.fill"
        static let chevronRight = "chevron.right"
        static let chevronLeft = "chevron.left"
        static let chevronDown = "chevron.down"
        static let chevronUp = "chevron.up"
        static let close = "xmark"
        static let info = "info.circle"
        static let link = "link"
        static let externalDrive = "externaldrive"
        static let bell = "bell"
        static let diagnostics = "wrench.and.screwdriver"
        static let trash = "trash"
        static let pencil = "pencil"
        static let share = "square.and.arrow.up"
        static let calendar = "calendar"
        static let gallery = "square.grid.3x3.fill"
    }

    // MARK: - Activity & UI Controls
    enum Action {
        static let edit = "pencil"
        static let delete = "trash"
        static let merge = "arrow.triangle.merge"
        static let share = "square.and.arrow.up"
        static let calendar = "calendar"
        static let gps = "location.fill"
        static let play = "play.fill"
        static let pause = "pause.fill"
        static let stop = "stop.fill"
        static let add = "plus"
        static let minus = "minus"
        static let search = "magnifyingglass"
        static let filter = "line.3.horizontal.decrease.circle"
    }

    // MARK: - Charts & States
    enum State {
        static let checkmark = "checkmark"
        static let checkmarkCircle = "checkmark.circle.fill"
        static let warning = "exclamationmark.triangle.fill"
        static let error = "xmark.circle.fill"
        static let trendUp = "arrowtriangle.up.fill"
        static let trendDown = "arrowtriangle.down.fill"
        static let trendNeutral = "minus"
        static let flame = "flame.fill"
        static let locked = "lock.fill"
        static let unlocked = "lock.open.fill"
    }
}

/// Standardized STRAP Icon view with consistent frame, optical alignment, asset catalog support, and accessibility.
struct StrapIconView: View {
    let systemName: String
    var asset: IconAsset? = nil
    var size: CGFloat = 16
    var weight: Font.Weight = .medium
    var frameWidth: CGFloat = 24
    var color: Color = Color.appFG
    var accessibilityLabel: String? = nil

    init(
        _ systemName: String,
        asset: IconAsset? = nil,
        size: CGFloat = 16,
        weight: Font.Weight = .medium,
        frameWidth: CGFloat = 24,
        color: Color = Color.appFG,
        accessibilityLabel: String? = nil
    ) {
        self.systemName = systemName
        self.asset = asset
        self.size = size
        self.weight = weight
        self.frameWidth = frameWidth
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }

    init(
        asset: IconAsset,
        size: CGFloat = 16,
        weight: Font.Weight = .medium,
        frameWidth: CGFloat = 24,
        color: Color = Color.appFG,
        accessibilityLabel: String? = nil
    ) {
        self.systemName = asset.sfSymbolFallback
        self.asset = asset
        self.size = size
        self.weight = weight
        self.frameWidth = frameWidth
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }

    /// Reuse existing bundled artwork for unambiguous domain symbols.
    static func defaultAsset(for symbol: String) -> IconAsset? {
        switch symbol {
        case StrapIcon.Metric.heartRate: return .healthHeartRate
        case StrapIcon.Metric.hrv: return .healthHrv
        case StrapIcon.Metric.respiration: return .healthRespiratory
        case StrapIcon.Metric.bloodOxygen: return .healthBloodOxygen
        case StrapIcon.Metric.skinTemp: return .healthTemperature
        case StrapIcon.Metric.recovery: return .healthRecovery
        case StrapIcon.Metric.sleep: return .healthSleep
        case StrapIcon.Metric.strain: return .healthStrain
        case StrapIcon.Device.batteryFull: return .deviceBatteryFull
        case StrapIcon.Device.batteryLow: return .deviceBatteryLow
        case StrapIcon.Device.batteryCritical: return .deviceBatteryCritical
        case StrapIcon.Device.batteryCharging: return .deviceBatteryCharging
        default: return nil
        }
    }

    /// Explicit context at production call sites avoids ambiguous SF Symbol names.
    static func healthAsset(for vital: HealthVital) -> IconAsset {
        switch vital {
        case .respiration: return .healthRespiratory
        case .oxygen: return .healthBloodOxygen
        case .rhr: return .healthHeartRate
        case .hrv: return .healthHrv
        case .temperature: return .healthTemperature
        }
    }

    var body: some View {
        Group {
            if let asset = asset ?? Self.defaultAsset(for: systemName), UIImage(named: asset.rawValue) != nil {
                asset.image
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: size, weight: weight))
            }
        }
        .frame(width: frameWidth)
        .foregroundStyle(color)
        .accessibilityLabel(Text(accessibilityLabel ?? systemName))
    }
}

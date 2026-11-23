import SwiftUI

/// Centralized Icon Registry for STRAP.
///
/// Provides a unified, high-fidelity iconography system based on the WHOOP 5.80.2 forensic inventory.
/// Maps all supported domain concepts to licensed, accessible SF Symbols and clean-room vector artwork.
public enum StrapIcon {

    // MARK: - Health & Biometric Metrics
    public enum Metric {
        public static let heartRate = "heart.fill"
        public static let restingHeartRate = "heart"
        public static let hrv = "waveform.path.ecg"
        public static let respiration = "lungs.fill"
        /// Accurate blood oxygen saturation badge, avoiding hydration/water droplet confusion.
        public static let bloodOxygen = "o.circle"
        public static let skinTemp = "thermometer.medium"
        public static let recovery = "arrow.triangle.2.circlepath.circle.fill"
        public static let strain = "flame.fill"
        public static let stress = "waveform.path"
        public static let sleep = "moon.fill"
        public static let nap = "moon.zzz.fill"
        public static let calories = "flame"
        public static let steps = "figure.walk"
        public static let distance = "figure.run"
        public static let ecg = "waveform.path.ecg.rectangle"
    }

    // MARK: - Device & Battery
    public enum Device {
        public static let bandHardware = "WhoopBandHardware"
        /// Screenless wrist sensor glyph, replacing mismatched Apple Watch icon.
        public static let bandSensor = "sensor.fill"
        public static let bluetoothConnected = "antenna.radiowaves.left.and.right"
        public static let bluetoothConnecting = "dot.radiowaves.left.and.right"
        public static let bluetoothDisconnected = "antenna.radiowaves.left.and.right.slash"
        public static let syncCatchingUp = "arrow.triangle.2.circlepath"
        public static let syncCaughtUp = "checkmark.circle.fill"
        public static let hapticAlarm = "alarm.waves.left.and.right"
        /// Mechanical wrist vibration impulse glyph, replacing generic audio waveform.
        public static let vibrationBuzz = "iphone.radiowaves.left.and.right"
        public static let chargingBolt = "bolt.fill"
        public static let batteryFull = "battery.100"
        public static let batteryHalf = "battery.50"
        public static let batteryLow = "battery.25"
        public static let batteryCharging = "battery.100.bolt"
    }

    // MARK: - Navigation & Settings
    public enum Navigation {
        public static let home = "house"
        public static let homeSelected = "house.fill"
        public static let health = "heart"
        public static let healthSelected = "heart.fill"
        public static let community = "person.2"
        public static let communitySelected = "person.2.fill"
        /// Segmented hub glyph, replacing three-line drawer hamburger menu.
        public static let more = "ellipsis.circle"
        public static let moreSelected = "ellipsis.circle.fill"
        public static let settings = "gearshape"
        public static let chevronRight = "chevron.right"
        public static let chevronLeft = "chevron.left"
        public static let chevronDown = "chevron.down"
        public static let chevronUp = "chevron.up"
        public static let close = "xmark"
        public static let info = "info.circle"
        public static let link = "link"
        public static let externalDrive = "externaldrive"
        public static let bell = "bell"
        public static let diagnostics = "wrench.and.screwdriver"
        public static let trash = "trash"
        public static let pencil = "pencil"
        public static let share = "square.and.arrow.up"
        public static let calendar = "calendar"
        public static let gallery = "square.grid.3x3.fill"
    }

    // MARK: - Charts & States
    public enum State {
        public static let checkmark = "checkmark"
        public static let checkmarkCircle = "checkmark.circle.fill"
        public static let warning = "exclamationmark.triangle.fill"
        public static let error = "xmark.circle.fill"
        public static let trendUp = "arrowtriangle.up.fill"
        public static let trendDown = "arrowtriangle.down.fill"
        public static let trendNeutral = "minus"
        public static let flame = "flame.fill"
        public static let locked = "lock.fill"
        public static let unlocked = "lock.open.fill"
    }
}

/// Standardized STRAP Icon view with consistent frame, optical alignment, and accessibility.
public struct StrapIconView: View {
    public let systemName: String
    public var size: CGFloat = 16
    public var weight: Font.Weight = .medium
    public var frameWidth: CGFloat = 24
    public var color: Color = Color.appFG
    public var accessibilityLabel: String? = nil

    public init(
        _ systemName: String,
        size: CGFloat = 16,
        weight: Font.Weight = .medium,
        frameWidth: CGFloat = 24,
        color: Color = Color.appFG,
        accessibilityLabel: String? = nil
    ) {
        self.systemName = systemName
        self.size = size
        self.weight = weight
        self.frameWidth = frameWidth
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .frame(width: frameWidth)
            .foregroundStyle(color)
            .accessibilityLabel(Text(accessibilityLabel ?? systemName))
    }
}

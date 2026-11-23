import SwiftUI

/// Centralized Icon Registry for STRAP.
///
/// Provides a unified, high-fidelity iconography system based on the WHOOP 5.80.2 forensic inventory.
/// Maps all supported domain concepts to licensed, accessible SF Symbols and clean-room vector artwork.
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
        static let batteryCharging = "battery.100.bolt"
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
        static let settings = "gearshape"
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

/// Standardized STRAP Icon view with consistent frame, optical alignment, and accessibility.
struct StrapIconView: View {
    let systemName: String
    var size: CGFloat = 16
    var weight: Font.Weight = .medium
    var frameWidth: CGFloat = 24
    var color: Color = Color.appFG
    var accessibilityLabel: String? = nil

    init(
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

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .frame(width: frameWidth)
            .foregroundStyle(color)
            .accessibilityLabel(Text(accessibilityLabel ?? systemName))
    }
}

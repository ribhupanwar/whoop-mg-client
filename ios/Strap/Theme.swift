import SwiftUI

/// Dark surfaces and cyan accent cross-checked against the owner's dsta
/// dashboard reference. Stage and score colours retain their semantic roles.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }

    static let appBG = Color(red: 0.018, green: 0.035, blue: 0.065)
    static let appSurface = Color(red: 0.035, green: 0.075, blue: 0.12)
    static let appRaised = Color(red: 0.08, green: 0.16, blue: 0.23)
    static let appFG = Color(hex: 0xEEF1F5)
    static let appMuted = Color(red: 0.57, green: 0.68, blue: 0.77)
    static let appLine = Color(red: 0.12, green: 0.31, blue: 0.43).opacity(0.62)
    static let appAccent = Color(red: 0.12, green: 0.78, blue: 0.88)
    static let appGood = Color(hex: 0x4ADE80)
    static let appWarn = Color(hex: 0xE0A33A)
    static let appHigh = Color(hex: 0xFF6B5E)
    static let appSleep = Color(hex: 0x9DB4CC)
    static let appGoodChipBG = Color(hex: 0x16261B)
    static let appDemoFlagBG = Color(hex: 0x2A2114)
}
/// Shared geometry keeps cards and metric rows aligned across tabs.
enum AppLayout {
    static let screenInset: CGFloat = 18
    static let cardInset: CGFloat = 16
    static let cardRadius: CGFloat = 22
    static let cardSpacing: CGFloat = 14
    static let metricRadius: CGFloat = 16
}

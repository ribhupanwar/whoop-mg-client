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

    static let appCanvasTop = Color(hex: 0x243138)
    static let appBG = Color(hex: 0x11191D)
    static let appSurface = Color(hex: 0x2B3135)
    static let appRaised = Color(hex: 0x3D4448)
    static let appFG = Color(hex: 0xEEF1F5)
    static let appMuted = Color(hex: 0x9BA4AA)
    static let appLine = Color(hex: 0x596166).opacity(0.45)
    static let appAccent = Color(hex: 0x009FEE)
    static let appCustomizeStart = Color(red: 0.93, green: 0.39, blue: 0.86)
    static let appCustomizeEnd = Color(red: 0.65, green: 0.28, blue: 0.87)
    static let appGood = Color(hex: 0x4ADE80)
    static let appWarn = Color(hex: 0xE0A33A)
    static let appHigh = Color(hex: 0xFF6B5E)
    static let appSleep = Color(hex: 0x86AABE)
    static let appGoodChipBG = Color(hex: 0x16261B)
    static let appDemoFlagBG = Color(hex: 0x2A2114)
}
/// Shared geometry keeps cards and metric rows aligned across tabs.
enum AppLayout {
    static let screenInset: CGFloat = 14
    static let cardInset: CGFloat = 16
    static let cardRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 14
    static let metricRadius: CGFloat = 14
}

import SwiftUI

/// Dark palette ported from the approved original layout mockup.
/// No third-party assets or branding — these are our own colours.
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

    static let appBG = Color(hex: 0x0A0C0F)
    static let appSurface = Color(hex: 0x15181D)
    static let appRaised = Color(hex: 0x1D2128)
    static let appFG = Color(hex: 0xEEF1F5)
    static let appMuted = Color(hex: 0x8B95A3)
    static let appLine = Color(hex: 0x262B34)
    static let appAccent = Color(hex: 0x5AA2FF)
    static let appGood = Color(hex: 0x4ADE80)
    static let appWarn = Color(hex: 0xE0A33A)
    static let appHigh = Color(hex: 0xFF6B5E)
    static let appSleep = Color(hex: 0x9DB4CC)
    static let appGoodChipBG = Color(hex: 0x16261B)
    static let appDemoFlagBG = Color(hex: 0x2A2114)
}
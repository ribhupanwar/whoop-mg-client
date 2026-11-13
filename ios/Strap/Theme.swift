import SwiftUI

/// Charcoal surfaces and blue accents from the owner's screenshot reference.
/// Stage and score colours retain their semantic roles.
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

    static let appCanvasTop = Color(hex: 0x242A2F)
    static let appBG = Color(hex: 0x171B1E)
    static let appSurface = Color(hex: 0x2C3033)
    static let appRaised = Color(hex: 0x3C4145)
    static let appFG = Color(hex: 0xEEF1F5)
    static let appMuted = Color(hex: 0xA3A8AE)
    static let appLine = Color(hex: 0x596166).opacity(0.45)
    static let appAccent = Color(hex: 0x178ED9)
    static let appCustomizeStart = Color(red: 0.93, green: 0.39, blue: 0.86)
    static let appCustomizeEnd = Color(red: 0.65, green: 0.28, blue: 0.87)
    static let appGood = Color(hex: 0x18C998)
    static let appWarn = Color(hex: 0xFFB340)
    static let appHigh = Color(hex: 0xFF6B5E)
    static let appSleep = Color(hex: 0x82A6BD)
    static let appGoodChipBG = Color(hex: 0x16261B)
    static let appDemoFlagBG = Color(hex: 0x2A2114)
}
/// Shared geometry keeps cards and metric rows aligned across tabs.
enum AppLayout {
    static let screenInset: CGFloat = 16
    static let cardInset: CGFloat = 15
    static let cardRadius: CGFloat = 15
    static let cardSpacing: CGFloat = 12
    static let metricRadius: CGFloat = 13
}

/// Subtle gray card shading shared by every tab and detail page.
extension LinearGradient {
    static var appCard: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x32373B), .appSurface],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

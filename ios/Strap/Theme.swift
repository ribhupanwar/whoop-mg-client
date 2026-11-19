import SwiftUI

/// WHOOP-inspired charcoal surface tokens; keep independent STRAP artwork and licensed fonts.
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

    static let appCanvasTop = Color(hex: 0x273037)
    static let appBG = Color(hex: 0x101518)
    static let appSurface = Color(hex: 0x1D2429)
    static let appRaised = Color(hex: 0x252D33)
    static let appFG = Color(hex: 0xFFFFFF)
    static let appMuted = Color(hex: 0xA3ADB5)
    static let appLine = Color(hex: 0x333E46).opacity(0.40)
    static let appAccent = Color(hex: 0x0091FF)
    static let appCustomizeStart = Color(red: 0.93, green: 0.39, blue: 0.86)
    static let appCustomizeEnd = Color(red: 0.65, green: 0.28, blue: 0.87)
    static let appGood = Color(hex: 0x00E676)
    static let appWarn = Color(hex: 0xFFDE00)
    static let appHigh = Color(hex: 0xFF3B30)
    static let appSleep = Color(hex: 0x7EA3B9)
    static let appGoodChipBG = Color(hex: 0x16261B)
    static let appDemoFlagBG = Color(hex: 0x2A2114)
}
/// Shared geometry keeps cards and metric rows aligned across tabs.
enum AppLayout {
    static let screenInset: CGFloat = 16
    static let cardInset: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let cardSpacing: CGFloat = 14
    static let metricRadius: CGFloat = 15
}

/// Low-contrast charcoal card shading shared by every tab and detail page.
extension LinearGradient {
    static var appCard: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x252D33), Color(hex: 0x1D2429)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

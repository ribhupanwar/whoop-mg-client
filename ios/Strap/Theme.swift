import SwiftUI

/// WHOOP reference color tokens and typography bindings.
/// Palette sampled from 19 user-provided 2026-11-10 JPEG reference captures.
/// JPEG values are approximate rendered colors, not original source constants.
/// Health calculation logic is preserved independently.
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

    // Canvas & Surface Gradients
    static let appCanvasTop = Color(hex: 0x283138)          // Reference top-edge sample
    static let appCanvasMid = Color(hex: 0x191E22)          // Reference mid-canvas sample
    static let appBG = Color(hex: 0x0D1112)                 // Reference lower-edge sample
    static let appSurface = Color(hex: 0x1D2429)            // Dark card interior #1D2429
    static let appRaised = Color(hex: 0x252D33)             // Elevated card top #252D33
    static let appCardBorder = Color(hex: 0x303940)         // Subtle card stroke #303940
    static let appLine = Color(hex: 0x333E46).opacity(0.40) // Divider line
    static let appFG = Color(hex: 0xFFFFFF)                 // High-contrast white #FFFFFF
    static let appMuted = Color(hex: 0xA3ADB5)              // Secondary typography #A3ADB5

    // Hero Metric & Ring Stroke Tokens
    static let appSleep = Color(hex: 0x7CA1BB)              // Reference sleep blue
    static let appRecoveryGreen = Color(hex: 0x1AEC07)
    static let appRecoveryYellow = Color(hex: 0xFEDE00)
    static let appRecoveryRed = Color(hex: 0xFC0025)
    static let appGood = Color(hex: 0x00E676)               // Semantic good status (not recovery ring)
    static let appWarn = Color(hex: 0xFFDE00)               // Semantic caution status
    static let appHigh = Color(hex: 0xFF3B30)               // Semantic error status
    static let appAccent = Color(hex: 0x0193E8)             // Reference strain blue
    static let appRingTrack = Color(hex: 0x2A333A).opacity(0.85) // Unfilled ring track #2A333A @ 85%

    // Interactive & Badge Fill Tokens
    static let appGoodChipBG = Color(hex: 0x16261B)
    static let appDemoFlagBG = Color(hex: 0x2A2114)
    static let appButtonFill = Color(hex: 0x2A3339)         // Action pill buttons (+ ADD ACTIVITY)
    static let appNavBarBG = Color(hex: 0x171E22).opacity(0.92) // Translucent tab bar
    static let appCustomizeStart = Color(hex: 0xFF9E80)         // Reference peach-to-purple
    static let appCustomizeEnd = Color(hex: 0x8E24AA)
}

/// Shared geometry keeps cards and metric rows aligned across tabs.
enum AppLayout {
    static let screenInset: CGFloat = 16
    static let cardInset: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let cardSpacing: CGFloat = 14
    static let metricRadius: CGFloat = 15

    static let dashboardRowHeight: CGFloat = 60
    static let dashboardRowSpacing: CGFloat = 12
    static let dashboardRowRadius: CGFloat = 12

    // Ring Geometry Constants (WHOOP Reference Specification)
    static let heroRingDiameter: CGFloat = 84.0
    static let detailRingDiameter: CGFloat = 104.0
    static let ringStrokeWidth: CGFloat = 6.0
    static let ringGap: CGFloat = 8.0
    static let heroMetricFontSize: CGFloat = 26.0
    static let percentSignScale: CGFloat = 0.70
}

/// Low-contrast charcoal card shading shared by every tab and detail page.
extension LinearGradient {
    static var appCard: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x2D3238), Color(hex: 0x1C2023)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var dashboardCard: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x2E3539), Color(hex: 0x222629)],
                       startPoint: .top, endPoint: .bottom)
    }

    static var appCanvas: LinearGradient {
        LinearGradient(stops: [
            .init(color: .appCanvasTop, location: 0),
            .init(color: Color(hex: 0x242D32), location: 0.12),
            .init(color: Color(hex: 0x1E252B), location: 0.25),
            .init(color: Color(hex: 0x161B1F), location: 0.45),
            .init(color: Color(hex: 0x13181C), location: 0.55),
            .init(color: Color(hex: 0x101417), location: 0.85),
            .init(color: .appBG, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

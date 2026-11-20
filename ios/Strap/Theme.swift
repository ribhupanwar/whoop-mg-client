import SwiftUI

/// WHOOP reference color tokens and typography bindings.
/// Extracted and verified pixel-by-pixel against official WHOOP 5.80.2 application captures.
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
    static let appCanvasTop = Color(hex: 0x252E34)          // Header gradient top #252E34
    static let appCanvasMid = Color(hex: 0x161C20)          // Mid canvas #161C20
    static let appBG = Color(hex: 0x0E1316)                 // Base background #0E1316 / #101518
    static let appSurface = Color(hex: 0x1D2429)            // Dark card interior #1D2429
    static let appRaised = Color(hex: 0x252D33)             // Elevated card top #252D33
    static let appCardBorder = Color(hex: 0x303940)         // Subtle card stroke #303940
    static let appLine = Color(hex: 0x333E46).opacity(0.40) // Divider line
    static let appFG = Color(hex: 0xFFFFFF)                 // High-contrast white #FFFFFF
    static let appMuted = Color(hex: 0xA3ADB5)              // Secondary typography #A3ADB5

    // Hero Metric & Ring Stroke Tokens
    static let appSleep = Color(hex: 0x7EA3B9)              // Sleep ring light blue #7EA3B9
    static let appGood = Color(hex: 0x00E676)               // Green recovery (>=67%) #00E676 / #00F076
    static let appWarn = Color(hex: 0xFFDE00)               // Yellow recovery (34-66%) #FFDE00
    static let appHigh = Color(hex: 0xFF3B30)               // Red recovery (<34%) #FF3B30
    static let appAccent = Color(hex: 0x0091FF)             // Strain electric blue #0091FF
    static let appRingTrack = Color(hex: 0x2A333A).opacity(0.85) // Unfilled ring track #2A333A @ 85%

    // Interactive & Badge Fill Tokens
    static let appGoodChipBG = Color(hex: 0x16261B)
    static let appDemoFlagBG = Color(hex: 0x2A2114)
    static let appButtonFill = Color(hex: 0x2A3339)         // Action pill buttons (+ ADD ACTIVITY)
    static let appNavBarBG = Color(hex: 0x171E22).opacity(0.92) // Translucent tab bar
    static let appCustomizeStart = Color(red: 0.93, green: 0.39, blue: 0.86)
    static let appCustomizeEnd = Color(red: 0.65, green: 0.28, blue: 0.87)
}

/// Shared geometry keeps cards and metric rows aligned across tabs.
enum AppLayout {
    static let screenInset: CGFloat = 16
    static let cardInset: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let cardSpacing: CGFloat = 14
    static let metricRadius: CGFloat = 15

    // Ring Geometry Constants (WHOOP Reference Specification)
    static let heroRingDiameter: CGFloat = 60.0
    static let detailRingDiameter: CGFloat = 104.0
    static let ringStrokeWidth: CGFloat = 4.5
    static let ringGap: CGFloat = 18.0
    static let heroMetricFontSize: CGFloat = 21.0
    static let percentSignScale: CGFloat = 0.72
}

/// Low-contrast charcoal card shading shared by every tab and detail page.
extension LinearGradient {
    static var appCard: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x252D33), Color(hex: 0x1D2429)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var appCanvas: LinearGradient {
        LinearGradient(colors: [Color.appCanvasTop, Color.appCanvasMid, Color.appBG],
                       startPoint: .top, endPoint: .bottom)
    }
}

import SwiftUI
import UIKit

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

    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .light ? light : dark
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }

    // Canvas & Surface Gradients
    static let appCanvasTop = Color.adaptive(dark: 0x282F35, light: 0xE7EDF1)          // Reference top-edge sample
    static let appCanvasMid = Color.adaptive(dark: 0x191E22, light: 0xF0F3F5)          // Reference mid-canvas sample
    static let appBG = Color.adaptive(dark: 0x111518, light: 0xF7F8FA)                 // Reference lower-edge sample
    static let appSurface = Color.adaptive(dark: 0x252A2E, light: 0xFFFFFF)            // Dark card interior #1D2429
    static let appRaised = Color.adaptive(dark: 0x303438, light: 0xE8EDF0)             // Elevated card top #252D33
    static let appCardBorder = Color.adaptive(dark: 0x363C40, light: 0xCCD5DB)         // Subtle card stroke #303940
    static let appLine = Color.adaptive(dark: 0x333E46, light: 0xAAB8C2).opacity(0.40) // Divider line
    static let appFG = Color.adaptive(dark: 0xFFFFFF, light: 0x18242C)                 // High-contrast white #FFFFFF
    static let appMuted = Color.adaptive(dark: 0xA3ADB5, light: 0x52636D)              // Secondary typography #A3ADB5

    // Hero Metric & Ring Stroke Tokens
    static let appSleep = Color.adaptive(dark: 0x7CA1BB, light: 0x426C89)              // Reference sleep blue
    static let appRecoveryGreen = Color.adaptive(dark: 0x1AEC07, light: 0x168B13)
    static let appRecoveryYellow = Color.adaptive(dark: 0xFEDE00, light: 0x9B7600)
    static let appRecoveryRed = Color.adaptive(dark: 0xFC0025, light: 0xD00024)
    static let appGood = Color.adaptive(dark: 0x00E676, light: 0x007B48)               // Semantic good status (not recovery ring)
    static let appWarn = Color.adaptive(dark: 0xFFDE00, light: 0x856100)               // Semantic caution status
    static let appHigh = Color.adaptive(dark: 0xFF3B30, light: 0xBD251D)               // Semantic error status
    static let appAccent = Color.adaptive(dark: 0x0193E8, light: 0x006BA8)             // Reference strain blue
    static let appRingTrack = Color.adaptive(dark: 0x343C40, light: 0xCBD5DC).opacity(0.85) // Unfilled ring track #2A333A @ 85%

    // Interactive & Badge Fill Tokens
    static let appGoodChipBG = Color.adaptive(dark: 0x16261B, light: 0xDDF2E4)
    static let appDemoFlagBG = Color.adaptive(dark: 0x2A2114, light: 0xFFF0D8)
    static let appButtonFill = Color.adaptive(dark: 0x2A3339, light: 0xE2E8EC)         // Action pill buttons (+ ADD ACTIVITY)
    static let appNavBarBG = Color.adaptive(dark: 0x24292F, light: 0xE8EDF1).opacity(0.92) // Translucent tab bar
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
        LinearGradient(colors: [Color.adaptive(dark: 0x2D3236, light: 0xFFFFFF), Color.adaptive(dark: 0x252A2E, light: 0xF0F3F5)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var dashboardCard: LinearGradient {
        LinearGradient(colors: [Color.adaptive(dark: 0x32363A, light: 0xFFFFFF), Color.adaptive(dark: 0x2B2F32, light: 0xF0F3F5)],
                       startPoint: .top, endPoint: .bottom)
    }

    static var appCanvas: LinearGradient {
        LinearGradient(stops: [
            .init(color: .appCanvasTop, location: 0),
            .init(color: Color.adaptive(dark: 0x242D32, light: 0xEAF0F3), location: 0.12),
            .init(color: Color.adaptive(dark: 0x1E252B, light: 0xEDF1F4), location: 0.25),
            .init(color: Color.adaptive(dark: 0x161B1F, light: 0xF0F3F5), location: 0.45),
            .init(color: Color.adaptive(dark: 0x13181C, light: 0xF3F5F7), location: 0.55),
            .init(color: Color.adaptive(dark: 0x111518, light: 0xF6F8FA), location: 0.85),
            .init(color: .appBG, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

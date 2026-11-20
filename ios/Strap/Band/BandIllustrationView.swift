import SwiftUI

/// WHOOP MG Band Hardware View.
///
/// Presents the genuine, official closed-strap hardware image asset (from `onboarding_choose_strap_closed.png`)
/// with dynamic hardware LED state indicator:
/// - Pulsing blue during BLE discovery / pairing
/// - Solid green during live connection / streaming
/// - Amber / yellow when battery is low (< 20%)
/// - Soft ambient shadow and responsive scaling
struct BandIllustrationView: View {
    var status: BandStatus? = nil
    var isConnected: Bool = false
    var batteryPercent: Int? = nil

    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // LAYER 1: Ambient Drop Shadow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.50), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 100
                    )
                )
                .frame(width: 180, height: 210)
                .offset(y: 12)

            // LAYER 2: Genuine WHOOP Band Hardware Asset
            Image("WhoopBandHardware")
                .resizable()
                .scaledToFit()
                .accessibilityLabel("WHOOP MG band hardware")

            // LAYER 3: Dynamic Hardware LED State Overlay
            if let led = ledColor {
                Circle()
                    .fill(led)
                    .frame(width: 7, height: 7)
                    .shadow(color: led.opacity(0.9), radius: 5)
                    .opacity(isPairing ? (pulseAnimation ? 0.25 : 1.0) : 1.0)
                    .offset(x: -12, y: -26)
                    .onAppear {
                        if isPairing {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                pulseAnimation = true
                            }
                        }
                    }
            }
        }
    }

    private var isPairing: Bool {
        guard let status = status else { return false }
        switch status {
        case .connecting, .authenticating:
            return true
        default:
            return false
        }
    }

    private var ledColor: Color? {
        if isPairing {
            return Color(hex: 0x0091FF) // Physical pulsing blue pairing LED
        } else if isConnected {
            if let battery = batteryPercent, battery < 20 {
                return Color.appWarn // Amber low battery indicator
            }
            return Color.appGood // Solid green live streaming indicator
        }
        return nil
    }
}

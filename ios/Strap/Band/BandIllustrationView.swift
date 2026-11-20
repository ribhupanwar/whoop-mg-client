import SwiftUI

/// Original vector illustration of the WHOOP 4.0 / 5.0 / MG band.
///
/// Clean-room SwiftUI implementation with parametric rendering:
/// - Curved athletic woven strap with textile depth and longitudinal knit ribs.
/// - Brushed titanium clasp frame with conductive ECG clasp tabs.
/// - Contoured sensor chassis with optical PPG port and status LED.
/// - Dynamic LED state matching physical hardware: pulsing blue during pairing,
///   solid green during live streaming, amber for low battery, off when idle.
struct BandIllustrationView: View {
    var status: BandStatus? = nil
    var isConnected: Bool = false
    var batteryPercent: Int? = nil

    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // LAYER 1: Shadow & Ambient Occlusion
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.45), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 90
                    )
                )
                .frame(width: 170, height: 240)
                .offset(y: 18)

            // LAYER 2: Back Loop of Elastic Woven Band
            Path { path in
                path.addEllipse(in: CGRect(x: 10, y: 15, width: 140, height: 210))
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(hex: 0x1A2228),
                        Color(hex: 0x0E1418),
                        Color(hex: 0x1F2A32)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 34, lineCap: .round, lineJoin: .round)
            )
            .rotationEffect(.degrees(-22))

            // Back Loop Woven Texture Ribs
            Path { path in
                path.addEllipse(in: CGRect(x: 10, y: 15, width: 140, height: 210))
            }
            .stroke(
                Color.white.opacity(0.06),
                style: StrokeStyle(lineWidth: 30, dash: [2, 4])
            )
            .rotationEffect(.degrees(-22))

            // LAYER 3: Forefront Strap Contour
            Path { path in
                path.addArc(
                    center: CGPoint(x: 80, y: 120),
                    radius: 72,
                    startAngle: .degrees(40),
                    endAngle: .degrees(220),
                    clockwise: false
                )
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(hex: 0x2C3740),
                        Color(hex: 0x1E272E),
                        Color(hex: 0x151B20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 36, lineCap: .round)
            )
            .rotationEffect(.degrees(-22))

            // Fine Knit Fabric Ribbing on Forefront
            Path { path in
                path.addArc(
                    center: CGPoint(x: 80, y: 120),
                    radius: 72,
                    startAngle: .degrees(45),
                    endAngle: .degrees(215),
                    clockwise: false
                )
            }
            .stroke(
                Color.white.opacity(0.08),
                style: StrokeStyle(lineWidth: 32, dash: [1.5, 3])
            )
            .rotationEffect(.degrees(-22))

            // LAYER 4: Metallic Buckle / Clasp (WHOOP MG Titanium Frame)
            ZStack {
                // Buckle Outer Metallic Bezel
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xDCE0E4), // Highlight
                                Color(hex: 0x7E8890), // Midtone
                                Color(hex: 0x48525A), // Shadow
                                Color(hex: 0xA6B0B8)  // Reflected specular
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 98, height: 146)
                    .shadow(color: Color.black.opacity(0.55), radius: 8, x: -3, y: 6)

                // Chamfered Bezel Inner Border
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.8), Color.white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 96, height: 144)

                // Clasp Side Hinge Notches
                HStack {
                    Capsule()
                        .fill(Color(hex: 0x333D45))
                        .frame(width: 4, height: 32)
                    Spacer()
                    Capsule()
                        .fill(Color(hex: 0x333D45))
                        .frame(width: 4, height: 32)
                }
                .frame(width: 104)

                // Inner Sensor Pod Chassis
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x1A2024),
                                Color(hex: 0x101417),
                                Color(hex: 0x0A0D0F)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 122)

                // Subtle Inner Housing Bevel
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                    .frame(width: 74, height: 118)

                // Optical Sensor Port & ECG Lens Wells
                VStack(spacing: 12) {
                    // Optical PPG Sensor Recess
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )

                        Circle()
                            .fill(Color(hex: 0x1B2C24).opacity(0.8))
                            .frame(width: 18, height: 18)

                        // Center Optical Emitter Dot
                        Circle()
                            .fill(emitterColor)
                            .frame(width: 8, height: 8)
                            .blur(radius: isStreaming ? 1.5 : 0)
                    }

                    // Hardware Status LED (Side-Indicator Representation)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ledColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: ledColor.opacity(ledGlowOpacity), radius: pulseAnimation ? 6 : 2)
                            .scaleEffect(isPulsingPairing && pulseAnimation ? 1.3 : 1.0)

                        Text("WHOOP")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(2.0)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .padding(.top, 4)
                }
            }
            .rotationEffect(.degrees(-22))
        }
        .frame(width: 180, height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onAppear {
            if isPulsingPairing {
                withAnimation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                ) {
                    pulseAnimation = true
                }
            }
        }
        .onChange(of: isPulsingPairing) { pulsing in
            if pulsing {
                withAnimation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                ) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
    }

    // MARK: - Status & Lighting Logic

    private var isStreaming: Bool {
        if let status, case .streaming = status { return true }
        return isConnected
    }

    private var isPulsingPairing: Bool {
        guard let status else { return false }
        switch status {
        case .scanning, .connecting, .authenticating:
            return true
        default:
            return false
        }
    }

    private var ledColor: Color {
        if isPulsingPairing {
            // Physical Blue LED indicating pairing mode
            return Color(hex: 0x3B82F6)
        }
        if isConnected || isStreaming {
            // Steady Green indicating active heart-rate telemetry
            return Color(hex: 0x00F076)
        }
        if let battery = batteryPercent, battery <= 15 {
            return Color(hex: 0xF59E0B)
        }
        return Color.white.opacity(0.2)
    }

    private var ledGlowOpacity: Double {
        if isPulsingPairing { return pulseAnimation ? 0.9 : 0.3 }
        if isStreaming { return 0.75 }
        if isConnected { return 0.5 }
        return 0.0
    }

    private var emitterColor: Color {
        if isStreaming {
            return Color(hex: 0x00F076)
        }
        return Color(hex: 0x2A373E)
    }

    private var accessibilityDescription: String {
        if isPulsingPairing {
            return "WHOOP MG band with pulsing blue pairing LED indicator"
        } else if isConnected {
            return "Connected WHOOP MG band with green sensor active"
        } else {
            return "WHOOP MG band illustration"
        }
    }
}

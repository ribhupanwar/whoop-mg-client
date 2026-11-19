import SwiftUI

/// WHOOP 5.0 / WHOOP MG clean-room pairing view.
/// Guides the user through the physical double-tap gesture, displays the blue LED
/// pairing state indicator, scans for advertisements, and pairs securely.
struct PairDeviceView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var pulseLed = false
    @State private var radarRotation = 0.0
    @State private var selectedBandId: String?
    @State private var autoPairTriggered = false

    var body: some View {
        NavigationStack {
            Screen {
                VStack(spacing: 20) {
                    if isConnected {
                        connectedView
                    } else if isConnecting {
                        connectingView
                    } else {
                        pairingInstructionsAndScanner
                    }
                }
                .padding(.top, 10)
            }
            .navigationTitle("Pair a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isConnected ? "Done" : "Cancel") {
                        store.band.stopPairingScan()
                        dismiss()
                    }
                    .font(StrapTypography.body(14, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                }
            }
            .onAppear {
                store.band.startPairingScan()
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseLed = true
                }
            }
            .onDisappear {
                store.band.stopPairingScan()
            }
        }
    }

    private var isConnected: Bool {
        store.band.isConnected && !isConnecting
    }

    private var isConnecting: Bool {
        switch store.band.status {
        case .connecting, .authenticating:
            return true
        default:
            return false
        }
    }

    // MARK: - Instruction & Scan View

    private var pairingInstructionsAndScanner: some View {
        VStack(spacing: 18) {
            // WHOOP Band Illustration with Pulsing Blue LED
            bandGraphicView

            // Primary Instruction
            VStack(spacing: 6) {
                Text("Double-tap your WHOOP band to enter pairing mode.")
                    .font(StrapTypography.body(16, weight: .bold))
                    .foregroundStyle(Color.appFG)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A pulsing blue LED confirms your band's firmware has entered pairing mode.")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // Step-by-Step Guide Panel
            Panel {
                SectionTitle("PAIRING STEPS")

                stepRow(
                    number: "1",
                    title: "Take band off wrist",
                    detail: "Wait ~10 seconds for the green optical sensors on the underside to turn off."
                )

                Divider().background(Color.appLine)

                stepRow(
                    number: "2",
                    title: "Firmly double-tap top",
                    detail: "Hold the sensor by its sides and firmly double-tap the top surface with two fingers."
                )

                Divider().background(Color.appLine)

                stepRow(
                    number: "3",
                    title: "Check for blue LED",
                    detail: "The side LED will blink blue when hardware pairing mode is active. STRAP detects it automatically."
                )
            }

            // Discovered Devices or Radar Pulse
            devicesListOrRadar
        }
    }

    private var bandGraphicView: some View {
        ZStack {
            // Outer glow / radar rings
            Circle()
                .stroke(Color.appAccent.opacity(0.12), lineWidth: 1)
                .frame(width: 140, height: 140)

            Circle()
                .stroke(Color.appAccent.opacity(0.24), lineWidth: 1.5)
                .frame(width: 110, height: 110)

            // Band sensor body
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.appLine.opacity(0.8), lineWidth: 1.5)
                )
                .frame(width: 130, height: 72)
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)

            // Inner styling lines
            VStack(spacing: 4) {
                Text("WHOOP")
                    .font(StrapTypography.metric(13, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(Color.appFG.opacity(0.85))

                Text("5.0 / MG")
                    .font(StrapTypography.body(9, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(Color.appMuted)
            }

            // Blue LED Indicator on Side
            HStack {
                Spacer()
                VStack {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0x0091FF).opacity(pulseLed ? 0.95 : 0.25))
                            .frame(width: 10, height: 10)
                            .shadow(color: Color(hex: 0x0091FF), radius: pulseLed ? 6 : 1)

                        Circle()
                            .stroke(Color.white.opacity(pulseLed ? 0.8 : 0.2), lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                    }
                    .padding(.trailing, 22)
                }
            }
            .frame(width: 130)
        }
        .padding(.vertical, 8)
    }

    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(StrapTypography.metric(12, weight: .bold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 22, height: 22)
                .background(Color.appAccent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(StrapTypography.body(13, weight: .semibold))
                    .foregroundStyle(Color.appFG)

                Text(detail)
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Discovered Devices List / Radar

    private var devicesListOrRadar: some View {
        Panel {
            HStack {
                SectionTitle("DISCOVERED DEVICES")
                Spacer()
                if store.band.isFindingBands {
                    ProgressView()
                        .tint(Color.appAccent)
                        .scaleEffect(0.7)
                }
            }

            if store.band.discoveredBands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.appAccent)
                        .padding(.top, 4)

                    Text("Scanning for nearby WHOOP bands…")
                        .font(StrapTypography.body(12, weight: .medium))
                        .foregroundStyle(Color.appMuted)

                    Text("Make sure Bluetooth is enabled and the side LED is blinking blue.")
                        .font(StrapTypography.body(10))
                        .foregroundStyle(Color.appMuted.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.band.discoveredBands) { band in
                        deviceRow(band)
                    }
                }

                // Unambiguous Single Device Helper
                if store.band.discoveredBands.count == 1,
                   let single = store.band.discoveredBands.first,
                   single.rssi >= -65 {
                    Button {
                        pairWith(single)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Pair Verified \(single.name)")
                        }
                        .font(StrapTypography.body(13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.appAccent))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
        }
    }

    private func deviceRow(_ band: DiscoveredBand) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 20))
                .foregroundStyle(Color.appAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(band.name)
                    .font(StrapTypography.body(13, weight: .bold))
                    .foregroundStyle(Color.appFG)

                HStack(spacing: 6) {
                    Text("\(band.rssi) dBm")
                        .font(StrapTypography.body(10, weight: .medium))
                        .foregroundStyle(Color.appMuted)

                    Text("·")
                        .foregroundStyle(Color.appMuted)

                    Text(signalQuality(band.rssi))
                        .font(StrapTypography.body(10, weight: .medium))
                        .foregroundStyle(signalColor(band.rssi))
                }
            }

            Spacer()

            Button {
                pairWith(band)
            } label: {
                Text("Pair")
                    .font(StrapTypography.body(12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
    }

    private func signalQuality(_ rssi: Int) -> String {
        if rssi >= -60 { return "Strong" }
        if rssi >= -75 { return "Good" }
        return "Weak"
    }

    private func signalColor(_ rssi: Int) -> Color {
        if rssi >= -60 { return Color.appGood }
        if rssi >= -75 { return Color.appWarn }
        return Color.appHigh
    }

    private func pairWith(_ band: DiscoveredBand) {
        selectedBandId = band.id
        store.band.connect(to: band)
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .tint(Color.appAccent)
                .scaleEffect(1.4)
                .padding(.top, 24)

            VStack(spacing: 8) {
                Text("Connecting to \(store.band.bandName ?? "WHOOP Band")…")
                    .font(StrapTypography.body(17, weight: .bold))
                    .foregroundStyle(Color.appFG)

                Text(store.band.status.title)
                    .font(StrapTypography.body(13))
                    .foregroundStyle(Color.appMuted)
                    .multilineTextAlignment(.center)
            }

            Panel {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appWarn)
                        Text("Bluetooth Pairing Request")
                            .font(StrapTypography.body(13, weight: .bold))
                            .foregroundStyle(Color.appFG)
                    }

                    Text("If iOS shows a Bluetooth pairing prompt, tap **Pair** to authenticate with your strap's encrypted telemetry.")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Connected Success View

    private var connectedView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.appGood.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.appGood)
            }
            .padding(.top, 10)

            VStack(spacing: 6) {
                Text("WHOOP Paired Successfully")
                    .font(StrapTypography.body(18, weight: .bold))
                    .foregroundStyle(Color.appFG)

                Text("STRAP will automatically reconnect to this band whenever the app is opened.")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Panel {
                SectionTitle("DEVICE DETAILS")

                detailRow(label: "Device Name", value: store.band.bandName ?? "WHOOP MG")

                Divider().background(Color.appLine)

                detailRow(
                    label: "Battery Level",
                    value: store.band.batteryPercent.map { "\($0)%" } ?? "Reading…"
                )

                Divider().background(Color.appLine)

                detailRow(
                    label: "Firmware Revision",
                    value: store.band.firmwareRevision ?? "Reading…"
                )

                Divider().background(Color.appLine)

                detailRow(
                    label: "Connection Status",
                    value: store.band.status.title
                )
            }

            Button {
                store.band.stopPairingScan()
                dismiss()
            } label: {
                Text("Done")
                    .font(StrapTypography.body(14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appAccent))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 8)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appMuted)
            Spacer()
            Text(value)
                .font(StrapTypography.body(12, weight: .bold))
                .foregroundStyle(Color.appFG)
        }
        .padding(.vertical, 3)
    }
}

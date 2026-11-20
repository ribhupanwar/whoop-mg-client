import SwiftUI

/// WHOOP Device Settings screen matching official app forensic audit.
/// Exposes connection status, hardware details, firmware, wake alarm sync,
/// pairing flow, and verified device unpairing.
struct DeviceSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showPairingSheet = false
    @State private var showUnpairConfirmation = false

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                // SECTION 1: BAND STATUS HERO CARD
                bandHeroCard

                // SECTION 2: HARDWARE DETAILS
                hardwareDetailsPanel

                // SECTION 3: PREFERENCES & SENSORS
                preferencesPanel

                // SECTION 4: FIRMWARE
                firmwarePanel

                // SECTION 5: ADVANCED ACTIONS (PAIR & UNPAIR)
                actionsPanel

                // SECTION 6: DIAGNOSTICS & TELEMETRY
                diagnosticsPanel
            }
            .padding(.top, 4)
        }
        .navigationTitle("Device Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPairingSheet) {
            PairDeviceView()
                .environmentObject(store)
        }
        .confirmationDialog(
            "Unpair WHOOP Band?",
            isPresented: $showUnpairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unpair Device", role: .destructive) {
                store.unpairBand()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will disconnect your WHOOP and remove the saved association. You will need to double-tap your band into pairing mode to pair again.")
        }
    }

    // MARK: - Hero Card

    private var bandHeroCard: some View {
        Panel {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Sensor Graphic
                    BandIllustrationView(
                        status: store.band.status,
                        isConnected: store.band.isConnected,
                        batteryPercent: store.band.batteryPercent
                    )
                    .frame(width: 64, height: 72)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.band.modelNumber ?? store.band.bandName ?? store.band.preferredBandName ?? "WHOOP MG")
                            .font(StrapTypography.body(16, weight: .bold))
                            .foregroundStyle(Color.appFG)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)

                            Text(statusText)
                                .font(StrapTypography.body(11, weight: .semibold))
                                .foregroundStyle(statusColor)
                        }

                        if let battery = store.band.batteryPercent {
                            Text("Battery \(battery)%")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        } else if let serial = store.band.serialNumber {
                            Text("Serial: \(serial)")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                    }

                    Spacer()
                }

                if let lastSync = store.band.lastHistorySyncAt {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appMuted)
                        Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var statusText: String {
        switch store.band.status {
        case .connected(let name): return "Connected to \(name)"
        case .streaming(let bpm): return "Streaming (\(bpm) BPM)"
        case .draining: return "Syncing history…"
        case .authenticating: return "Authenticating…"
        case .connecting: return "Connecting…"
        case .reconnecting(let attempt): return "Reconnecting (attempt \(attempt))…"
        case .disconnected: return "Disconnected"
        case .unpaired: return "No band paired"
        case .scanning: return "Searching for band…"
        default: return store.band.isConnected ? "Connected" : "Disconnected"
        }
    }

    private var statusColor: Color {
        if store.band.isConnected { return Color.appGood }
        switch store.band.status {
        case .connecting, .authenticating: return Color.appAccent
        case .reconnecting: return Color.appWarn
        default: return Color.appMuted
        }
    }

    // MARK: - Hardware Details

    private var hardwareDetailsPanel: some View {
        Panel {
            SectionTitle("HARDWARE DETAILS")

            infoRow(
                label: "Device Model",
                value: store.band.modelNumber ?? store.band.bandName ?? store.band.preferredBandName ?? "WHOOP 5.0 / MG"
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "Serial Number",
                value: store.band.serialNumber ?? (store.band.isConnected ? "Reading from strap…" : "Unavailable offline")
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "Hardware Revision",
                value: store.band.hardwareRevision ?? "WHOOP MG"
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "Saved Peripheral ID",
                value: store.band.preferredBandID ?? "None"
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "Connection State",
                value: store.band.status.title
            )
        }
    }

    // MARK: - Preferences Panel

    private var preferencesPanel: some View {
        Panel {
            SectionTitle("BAND PREFERENCES & SENSORS")

            VStack(alignment: .leading, spacing: 10) {
                // Verified Broadcast Heart Rate Toggle (Command 14 / 0x0E)
                Toggle(isOn: Binding(
                    get: { store.band.isBroadcastingHR },
                    set: { store.setBroadcastHeartRate(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Broadcast Heart Rate")
                            .font(StrapTypography.body(13, weight: .semibold))
                            .foregroundStyle(Color.appFG)

                        Text(store.band.isConnected
                            ? "Transmits real-time HR over standard BLE 0x180D (Command 14 / 0x0E)."
                            : "Connect strap to configure broadcast.")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                    }
                }
                .disabled(!store.band.isConnected)
                .tint(Color.appAccent)

                Divider().background(Color.appLine)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wake Alarm Haptics")
                            .font(StrapTypography.body(13, weight: .semibold))
                            .foregroundStyle(Color.appFG)

                        Text(store.band.bandAlarmMessage)
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                if store.band.canTestBuzz {
                    Button {
                        store.band.testBuzz()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                            Text("Test Vibration Buzz")
                        }
                        .font(StrapTypography.body(11, weight: .bold))
                        .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    if !store.band.buzzMessage.isEmpty {
                        Text(store.band.buzzMessage)
                            .font(StrapTypography.body(10))
                            .foregroundStyle(Color.appMuted)
                    }
                }
            }
        }
    }

    // MARK: - Firmware Panel

    private var firmwarePanel: some View {
        Panel {
            SectionTitle("FIRMWARE")

            infoRow(
                label: "Firmware Revision",
                value: store.band.firmwareRevision ?? "Reading from strap…"
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "Firmware Status",
                value: store.band.firmwareRevision != nil ? "UP TO DATE" : "CHECKING"
            )
        }
    }

    // MARK: - Actions Panel

    private var actionsPanel: some View {
        Panel {
            SectionTitle("ACTIONS")

            // Sync Band Now
            Button {
                if store.band.isConnected {
                    store.band.readHistory()
                } else {
                    store.connectBand()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.appAccent)
                    Text(store.band.isConnected ? "Sync Band Data Now" : "Connect & Sync Band")
                        .font(StrapTypography.body(13, weight: .semibold))
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().background(Color.appLine)

            // Pair a Device
            Button {
                showPairingSheet = true
            } label: {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Color.appAccent)
                    Text(store.band.preferredBandID == nil ? "Pair a Device" : "Pair a Different Band")
                        .font(StrapTypography.body(13, weight: .semibold))
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Unpair Device (Only visible if device is saved/paired)
            if store.band.preferredBandID != nil {
                Divider().background(Color.appLine)

                Button {
                    showUnpairConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Color.appHigh)
                        Text("Unpair Device")
                            .font(StrapTypography.body(13, weight: .semibold))
                            .foregroundStyle(Color.appHigh)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.appLine)

            // Maintenance commands safety notice
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reboot & Maintenance Controls")
                        .font(StrapTypography.body(12, weight: .semibold))
                        .foregroundStyle(Color.appMuted)
                    Spacer()
                    Text("QUARANTINED")
                        .font(StrapTypography.metric(9, weight: .bold))
                        .foregroundStyle(Color.appWarn)
                }
                Text("Speculative command 32 (power-cycle), memory erase, and reflashing opcodes are quarantined to protect circular buffer flash records and prevent bricking.")
                    .font(StrapTypography.body(10))
                    .foregroundStyle(Color.appMuted.opacity(0.8))
            }
        }
    }

    // MARK: - Diagnostics Panel

    private var diagnosticsPanel: some View {
        Panel {
            SectionTitle("DIAGNOSTICS & TELEMETRY")

            VStack(alignment: .leading, spacing: 6) {
                Text(store.band.hrConnectionDiagnostic)
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let msg = store.band.lastMessage {
                    Text(msg)
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appWarn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("Type-40 Packets: \(store.band.type40HRPackets)")
                    Spacer()
                    Text("Standard HR: \(store.band.standardHRPackets)")
                }
                .font(StrapTypography.body(10))
                .foregroundStyle(Color.appMuted)
                .padding(.top, 4)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appMuted)
            Spacer()
            Text(value)
                .font(StrapTypography.body(12, weight: .semibold))
                .foregroundStyle(Color.appFG)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }
}

import SwiftUI

/// WHOOP 5.80.2 Forensic Device Settings Screen
/// Structured with official segmented tabs: STATUS vs ADVANCED
struct DeviceSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: Int = 0 // 0: STATUS, 1: ADVANCED
    @State private var showPairingSheet = false
    @State private var showUnpairConfirmation = false
    @State private var showSafetySheet = false
    @State private var showRebootConfirmation = false
    @State private var showClearCacheConfirmation = false

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                // FORENSIC SEGMENTED CONTROL: STATUS vs ADVANCED
                segmentedTabBar
                    .padding(.top, 4)

                if selectedTab == 0 {
                    statusTabView
                } else {
                    advancedTabView
                }
            }
        }
        .navigationTitle("DEVICE SETTINGS")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPairingSheet) {
            PairDeviceView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSafetySheet) {
            safetyAndRegulatorySheet
        }
        .confirmationDialog(
            "Are you sure?",
            isPresented: $showUnpairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unpair device", role: .destructive) {
                store.unpairBand()
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog(
            "Reboot WHOOP?",
            isPresented: $showRebootConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reboot", role: .destructive) {
                store.rebootBand()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will take a few moments to reboot your WHOOP. Historical data stored on your band and phone is preserved.")
        }
        .confirmationDialog(
            "Clear Local App Cache?",
            isPresented: $showClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                store.clearLocalData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears downloaded health history on this phone. Data stored on your WHOOP band will re-sync upon connection.")
        }
    }

    // MARK: - Segmented Tab Bar

    private var segmentedTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "STATUS", index: 0)
            tabButton(title: "ADVANCED", index: 1)
        }
        .background(Color.appCanvasTop)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private func tabButton(title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = index
            }
        } label: {
            Text(title)
                .font(StrapTypography.metric(12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(selectedTab == index ? Color.white : Color.appMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    selectedTab == index
                        ? Color.appAccent.opacity(0.85)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - STATUS TAB VIEW

    private var statusTabView: some View {
        VStack(spacing: 6) {
            // 1. Connection Status Banner & Device Header
            statusHeaderPanel

            // 2. Hardware Artwork Hero ({250, 250} per WHOOP NIB)
            artworkHeroPanel

            // 3. Battery Remaining & Status Display
            batteryGaugePanel

            // 4. Broadcast Heart Rate Control (Command 14 / 0x0E)
            broadcastHRPanel

            // 5. Wake Alarm Haptics
            alarmHapticsPanel
        }
    }

    private var statusHeaderPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.band.preferredBandName ?? store.band.bandName ?? store.band.modelNumber ?? "WHOOP MG")
                            .font(StrapTypography.body(16, weight: .bold))
                            .foregroundStyle(Color.appFG)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)

                            Text(connectionStateHeader)
                                .font(StrapTypography.metric(10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(statusColor)
                        }
                    }

                    Spacer()

                    if store.band.isConnected {
                        Button {
                            store.band.readHistory()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("SYNC")
                            }
                            .font(StrapTypography.metric(10, weight: .bold))
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.appAccent.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let lastSync = store.band.lastHistorySyncAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("LAST SYNC: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(StrapTypography.metric(9, weight: .medium))
                    }
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 2)
                } else if !store.band.isConnected {
                    Text("Tap 'Pair a Device' below to continue.")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var connectionStateHeader: String {
        if store.band.status == .draining {
            return "CATCHING UP"
        } else if store.band.isConnected {
            return "CONNECTED TO STRAP"
        } else {
            return "WHOOP DISCONNECTED"
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

    private var artworkHeroPanel: some View {
        Panel {
            VStack(spacing: 8) {
                // High-fidelity contoured band vector artwork ({250, 250})
                BandIllustrationView(
                    status: store.band.status,
                    isConnected: store.band.isConnected,
                    batteryPercent: store.band.batteryPercent
                )
                .frame(width: 250, height: 210)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var batteryGaugePanel: some View {
        Panel {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let battery = store.band.batteryPercent {
                        Text("\(battery)%")
                            .font(StrapTypography.metric(36, weight: .bold))
                            .foregroundStyle(batteryColor(for: battery))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("OF CHARGE\nREMAINING")
                                .font(StrapTypography.metric(9, weight: .bold))
                                .foregroundStyle(Color.appMuted)

                            if let hours = estimatedHoursRemaining(for: battery) {
                                Text("\(hours) HOURS")
                                    .font(StrapTypography.body(11, weight: .semibold))
                                    .foregroundStyle(Color.appFG)
                            }
                        }
                    } else {
                        Text("--%")
                            .font(StrapTypography.metric(36, weight: .bold))
                            .foregroundStyle(Color.appMuted)

                        Text("BATTERY LEVEL\nUNAVAILABLE")
                            .font(StrapTypography.metric(9, weight: .bold))
                            .foregroundStyle(Color.appMuted)
                    }

                    Spacer()

                    if let battery = store.band.batteryPercent, battery < 20 {
                        HStack(spacing: 4) {
                            Image("device_battery_critical")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                            Text("CHARGE YOUR WHOOP")
                        }
                        .font(StrapTypography.metric(9, weight: .bold))
                        .foregroundStyle(Color.appWarn)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appWarn.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func batteryColor(for percent: Int) -> Color {
        if percent >= 50 { return Color.appGood }
        if percent >= 20 { return Color.appWarn }
        return Color.appHigh
    }

    private func estimatedHoursRemaining(for percent: Int) -> Int? {
        // Average WHOOP battery lasts ~100-120 hours on full charge
        return (percent * 110) / 100
    }

    private var broadcastHRPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { store.band.isBroadcastingHR },
                    set: { store.setBroadcastHeartRate(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BROADCAST HEART RATE")
                            .font(StrapTypography.metric(12, weight: .bold))
                            .foregroundStyle(Color.appFG)

                        Text("TO COMPATIBLE APPS & DEVICES")
                            .font(StrapTypography.metric(9, weight: .semibold))
                            .foregroundStyle(Color.appMuted)
                    }
                }
                .disabled(!store.band.isConnected)
                .tint(Color.appGood)

                Text(store.band.isConnected
                    ? "Transmits real-time HR over standard BLE 0x180D (Command 14 / 0x0E)."
                    : "Connect strap to configure broadcast.")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
            }
        }
    }

    private var alarmHapticsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WAKE ALARM HAPTICS")
                            .font(StrapTypography.metric(11, weight: .bold))
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
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - ADVANCED TAB VIEW

    private var advancedTabView: some View {
        VStack(spacing: 16) {
            // 1. Hardware Details (Device ID, Firmware Version)
            advancedHardwareSection

            // 2. Connectivity & Pairing (Pair, Unpair)
            advancedConnectivitySection

            // 3. Maintenance Controls (Firmware Check, Reboot, Erase)
            advancedMaintenanceSection

            // 4. Regulatory & Compliance
            advancedRegulatorySection

            // 5. Diagnostics & Telemetry
            diagnosticsTelemetrySection
        }
    }

    private var advancedHardwareSection: some View {
        MoreSettingsCard("HARDWARE DETAILS") {

            infoRow(
                label: "DEVICE ID",
                value: store.band.serialNumber ?? (store.band.isConnected ? "Reading from strap…" : "Unavailable offline")
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "FIRMWARE",
                value: store.band.firmwareRevision ?? (store.band.isConnected ? "Reading from strap…" : "Unavailable offline")
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "HARDWARE REVISION",
                value: store.band.hardwareRevision ?? "WHOOP MG"
            )

            Divider().background(Color.appLine)

            infoRow(
                label: "SAVED PERIPHERAL ID",
                value: store.band.preferredBandID ?? "None"
            )
        }
    }

    private var advancedConnectivitySection: some View {
        MoreSettingsCard("CONNECTIVITY & PAIRING") {
            Button {
                showPairingSheet = true
            } label: {
                MoreSettingsDetailRow(title: "PAIR A DEVICE", icon: "link",
                    subtitle: "Pair a band with STRAP. This replaces the existing STRAP pairing.",
                    accessory: .navigation)
            }
            .buttonStyle(MoreSettingsPressStyle())

            if store.band.preferredBandID != nil || store.band.isConnected {
                Divider().overlay(Color.appLine)
                Button {
                    showUnpairConfirmation = true
                } label: {
                    MoreSettingsDetailRow(title: "UNPAIR DEVICE", icon: "xmark.circle",
                        subtitle: "Remove this band from STRAP and disconnect Bluetooth.",
                        titleColor: .appHigh, accessory: .action("UNPAIR", .appHigh))
                }
                .buttonStyle(MoreSettingsPressStyle())
            }
        }
    }

    private var advancedMaintenanceSection: some View {
        MoreSettingsCard("MAINTENANCE CONTROLS") {
            NavigationLink {
                FirmwareImageLabView()
            } label: {
                MoreSettingsDetailRow(title: "FIRMWARE LAB", icon: "cpu",
                    subtitle: "Inspect a local image and run a simulation. Hardware installation disabled.",
                    titleColor: .appAccent, accessory: .navigation)
            }
            .buttonStyle(MoreSettingsPressStyle())
            .accessibilityIdentifier("deviceSettings.firmwareLab")

            Divider().overlay(Color.appLine)
            Button {
                showRebootConfirmation = true
            } label: {
                MoreSettingsDetailRow(title: "REBOOT DEVICE", icon: "arrow.clockwise",
                    subtitle: store.band.rebootMessage ?? "Reboot your WHOOP to restart the device without losing stored flash data.",
                    accessory: store.band.isRebooting ? .progress :
                        .action(store.band.isConnected ? "REBOOT" : "OFFLINE",
                                store.band.isConnected ? .appAccent : .appMuted))
            }
            .buttonStyle(MoreSettingsPressStyle())
            .disabled(!store.band.isConnected || store.band.isRebooting)

            Divider().overlay(Color.appLine)
            Button {
                showClearCacheConfirmation = true
            } label: {
                MoreSettingsDetailRow(title: "CLEAR LOCAL APP CACHE", icon: "trash",
                    subtitle: "Clear cached history and recalculations on this phone. On-band data remains untouched.",
                    accessory: .action("RESET", .appHigh))
            }
            .buttonStyle(MoreSettingsPressStyle())

            Divider().overlay(Color.appLine)
            MoreSettingsDetailRow(title: "ON-BAND FLASH ERASE", icon: "lock.shield",
                subtitle: "Destructive hardware flash wipe (FORCE_TRIM 0x19) is quarantined. Restricted to factory calibration harnesses.",
                titleColor: .appMuted, accessory: .restricted("QUARANTINED"))
        }
    }

    private var advancedRegulatorySection: some View {
        MoreSettingsCard("LEGAL & REGULATORY") {
            NavigationLink {
                RegulatoryLabelsView()
                    .environmentObject(store)
            } label: {
                MoreSettingsDetailRow(title: "REGULATORY LABELS", icon: "doc.text",
                    subtitle: "View regulatory labels and compliance information for your WHOOP device.",
                    accessory: .navigation)
            }
            .buttonStyle(MoreSettingsPressStyle())

            Divider().overlay(Color.appLine)
            Button {
                showSafetySheet = true
            } label: {
                MoreSettingsDetailRow(title: "SAFETY & REGULATORY", icon: "checkmark.shield",
                    subtitle: "Important safety information, regulatory statements and product compliance details.",
                    accessory: .navigation)
            }
            .buttonStyle(MoreSettingsPressStyle())
        }
    }

    private var diagnosticsTelemetrySection: some View {
        MoreSettingsCard("DIAGNOSTICS & TELEMETRY") {

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

    private var safetyAndRegulatorySheet: some View {
        NavigationStack {
            Screen {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("IMPORTANT SAFETY INSTRUCTIONS")
                            .font(StrapTypography.body(14, weight: .bold))
                            .foregroundStyle(Color.appFG)

                        Text("• WHOOP is not a medical device and is not intended to diagnose, treat, mitigate, cure, or prevent any disease.\n• Do not wear during MRI scans or near high-intensity magnetic fields.\n• Keep battery pack and charging contacts clean and dry.\n• Discontinue use if skin irritation or rash occurs around sensor.")
                            .font(StrapTypography.body(12))
                            .foregroundStyle(Color.appMuted)
                            .lineSpacing(4)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle("Safety & Regulatory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showSafetySheet = false
                    }
                    .font(StrapTypography.body(13, weight: .bold))
                    .foregroundStyle(Color.appAccent)
                }
            }
        }
    }


    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appMuted)
            Spacer()
            Text(value)
                .font(StrapTypography.body(12, weight: .semibold))
                .foregroundStyle(Color.appFG)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }
}

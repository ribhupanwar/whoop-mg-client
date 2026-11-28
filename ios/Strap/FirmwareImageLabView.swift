import SwiftUI
import UniformTypeIdentifiers

/// Read-only laboratory. No actual firmware write is available.
struct FirmwareImageLabView: View {
    @EnvironmentObject private var store: AppStore
    @State private var picking = false
    @State private var loading = false
    @State private var image: FirmwareImageInspection?
    @State private var error: String?
    @State private var simulationResult: String?

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 20) {
                MoreSettingsCard("DEVICE INFORMATION") {
                    VStack(alignment: .leading, spacing: 12) {
                        informationRow("Firmware", value: store.band.firmwareRevision ?? "Unavailable")
                        Divider().overlay(Color.appLine)
                        informationRow("Model", value: store.band.modelNumber ?? "Unavailable")
                        Divider().overlay(Color.appLine)
                        informationRow("Battery", value: store.band.batteryPercent.map { "\($0)%" } ?? "Unavailable")
                    }
                    Hint("These values may be cached. No online update or compatibility check is performed.")
                }
                MoreSettingsCard("LOCAL IMAGE INSPECTION") {
                    Hint("Experimental read-only laboratory. Incorrect firmware can permanently damage a device. This screen cannot write to the band.")
                    Button {
                        picking = true
                    } label: {
                        MoreSettingsDetailRow(title: "CHOOSE LOCAL IMAGE",
                            subtitle: "Select a firmware file for local inspection.",
                            titleColor: .appAccent, accessory: loading ? .progress : .action("CHOOSE", .appAccent))
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                    .disabled(loading)
                    .accessibilityIdentifier("firmwareLab.chooseImage")
                    if let image {
                        Divider().overlay(Color.appLine)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(image.name)
                                .font(StrapTypography.body(14, weight: .bold))
                                .foregroundStyle(Color.appFG)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(image.byteCount) bytes · \(image.chunkCount) planned chunks")
                                .font(StrapTypography.body(11.5))
                                .foregroundStyle(Color.appMuted)
                            Text("SHA-256")
                                .font(StrapTypography.body(11, weight: .bold))
                                .foregroundStyle(Color.appMuted)
                            Text(image.sha256)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.appFG)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Hint("Fingerprint only. Signature, hardware target and downgrade compatibility are unverified.")
                        }
                        .padding(.vertical, 12)
                        Divider().overlay(Color.appLine)
                        Button {
                            simulate(image)
                        } label: {
                            MoreSettingsDetailRow(title: "RUN LOCAL SIMULATION",
                                subtitle: "Simulate staging locally. No data is written to the band.",
                                titleColor: .appAccent, accessory: .action("RUN", .appAccent))
                        }
                        .buttonStyle(MoreSettingsPressStyle())
                    }
                    if let error {
                        Text(error)
                            .font(StrapTypography.body(11.5))
                            .foregroundStyle(Color.appWarn)
                            .padding(.top, 8)
                    }
                    if let simulationResult {
                        Text(simulationResult)
                            .font(StrapTypography.body(11.5))
                            .foregroundStyle(Color.appMuted)
                            .padding(.top, 8)
                    }
                }
                MoreSettingsCard("HARDWARE INSTALLATION") {
                    MoreSettingsDetailRow(title: "INSTALL FIRMWARE",
                        subtitle: "No firmware bytes or commands are sent. Trusted signed firmware, model compatibility, independent transport validation and spare-device testing are required.",
                        titleColor: .appMuted, accessory: .restricted("DISABLED"))
                }
            }
        }
        .navigationTitle("FIRMWARE LAB")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            image = nil
            simulationResult = nil
            error = nil
            switch result {
            case .failure(let failure):
                error = failure.localizedDescription
            case .success(let urls):
                guard let url = urls.first else { return }
                loading = true
                Task { @MainActor in
                    do {
                        image = try await Task.detached(priority: .utility) {
                            try FirmwareImageInspection.inspect(url)
                        }.value
                    } catch let failure {
                        error = failure.localizedDescription
                    }
                    loading = false
                }
            }
        }
    }

    private func informationRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title.uppercased())
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(StrapTypography.body(12, weight: .semibold))
                .foregroundStyle(Color.appFG)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func simulate(_ image: FirmwareImageInspection) {
        var run = FirmwareDryRun(image: image)
        guard run.start(simulatedBattery: 100, simulatedReady: true) else { return }
        while run.acknowledgedBytes < image.byteCount {
            let offset = run.acknowledgedBytes
            let count = min(FirmwareImageInspection.plannedChunkBytes, image.byteCount - offset)
            guard run.acknowledgeChunk(offset: offset, count: count, accepted: true) else {
                simulationResult = "Local simulation failed."
                return
            }
        }
        run.verify(simulatedAcceptance: true)
        simulationResult = run.phase == .verified
            ? "Synthetic staging completed. No real verification or installation occurred."
            : "Local simulation failed."
    }
}

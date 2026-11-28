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
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("DEVICE INFORMATION")
                    Text("Reported firmware: " + (store.band.firmwareRevision ?? "Unavailable"))
                    Text("Reported model: " + (store.band.modelNumber ?? "Unavailable"))
                    Text("Reported battery: " + (store.band.batteryPercent.map { "\($0)%" } ?? "Unavailable"))
                    Hint("These values may be cached. No online update or compatibility check is performed.")
                }
                Panel {
                    SectionTitle("LOCAL IMAGE INSPECTION")
                    Hint("Experimental read-only laboratory. Incorrect firmware can permanently damage a device. This screen cannot write to the band.")
                    Button("Choose local image") { picking = true }
                        .disabled(loading)
                    if loading { ProgressView() }
                    if let image {
                        Text(image.name).font(.headline)
                        Text("\(image.byteCount) bytes · \(image.chunkCount) planned chunks")
                        Text("SHA-256").font(.caption.bold())
                        Text(image.sha256).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Hint("Fingerprint only. Signature, hardware target and downgrade compatibility are unverified.")
                        Button("Run local simulation") { simulate(image) }
                    }
                    if let error { Text(error).foregroundStyle(Color.appWarn) }
                    if let simulationResult {
                        Text(simulationResult).foregroundStyle(Color.appMuted)
                    }
                }
                Panel {
                    SectionTitle("HARDWARE INSTALLATION")
                    Text("DISABLED").font(.headline).foregroundStyle(Color.appWarn)
                    Hint("No firmware bytes or commands are sent. Trusted signed firmware, model compatibility, independent transport validation and spare-device testing are required.")
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

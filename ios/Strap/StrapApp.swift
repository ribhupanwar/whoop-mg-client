import SwiftUI

/// Strap — original clean-room UI for a personal band client.
/// CoreBluetooth capture and live heart rate are wired through `BandLink`.
@main
struct StrapApp: App {
    private let restoreIssue: String?
    init() {
        do {
            let fm = FileManager.default
            try StrapBackup.activatePending(
                support: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                documents: fm.urls(for: .documentDirectory, in: .userDomainMask)[0])
            restoreIssue = nil
        } catch { restoreIssue = error.localizedDescription }
        // Resolve/register the bundled Proxima Nova and DIN Pro files before
        // SwiftUI creates text and native UIKit controls for the first screen.
        StrapTypography.configureUIKitAppearance()
        if restoreIssue == nil { OSDiagnosticArchive.shared.start() }
    }

    var body: some Scene {
        WindowGroup {
            if let restoreIssue {
                VStack(spacing: 16) {
                    Text("Restore paused").font(.title)
                    Text(restoreIssue)
                    Text("Original records are preserved. Restart STRAP to retry before live data writers start.")
                }.padding()
            } else {
                RootView()
            }
        }
    }
}

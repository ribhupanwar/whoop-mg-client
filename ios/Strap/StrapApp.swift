import SwiftUI

/// Strap — original clean-room UI for a personal band client.
/// CoreBluetooth capture and live heart rate are wired through `BandLink`.
@main
struct StrapApp: App {
    init() {
        // Resolve/register the bundled Proxima Nova and DIN Pro files before
        // SwiftUI creates text and native UIKit controls for the first screen.
        StrapTypography.configureUIKitAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

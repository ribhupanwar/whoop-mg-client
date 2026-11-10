import SwiftUI

/// Strap — original clean-room UI for a personal band client.
/// CoreBluetooth capture and live heart rate are wired through `BandLink`.
@main
struct StrapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
import SwiftUI

/// Strap — original clean-room UI for a personal band client.
/// UI preview build: no CoreBluetooth yet; the Info.plist is already BLE-ready.
@main
struct StrapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
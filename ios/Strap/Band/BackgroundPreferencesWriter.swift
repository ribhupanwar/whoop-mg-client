import Foundation

/// Preserve write ordering while keeping JSON encoding and preferences I/O
/// off the Bluetooth/UI queue. Encoding failures keep the last valid value.
final class BackgroundPreferencesWriter {
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "strap.preferences.snapshots", qos: .userInitiated)
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func write<Value: Encodable>(_ value: Value, forKey key: String, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            let saved: Bool
            do {
                let data = try JSONEncoder().encode(value)
                if SleepRecoveryVault.keys.contains(key), let previous = self.defaults.data(forKey: key), previous != data {
                    try SleepRecoveryVault.preserve(previous, key: key)
                }
                self.defaults.set(data, forKey: key)
                saved = true
            } catch { saved = false }
            if let completion { DispatchQueue.main.async { completion(saved) } }
        }
    }
    func remove(forKey key: String) {
        queue.async {
            do {
                if SleepRecoveryVault.keys.contains(key), let previous = self.defaults.data(forKey: key) {
                    try SleepRecoveryVault.preserve(previous, key: key)
                }
                self.defaults.removeObject(forKey: key)
            } catch { /* Keep the original if evidence could not be preserved. */ }
        }
    }

    func flush(completion: @escaping () -> Void) {
        queue.async { DispatchQueue.main.async(execute: completion) }
    }
}

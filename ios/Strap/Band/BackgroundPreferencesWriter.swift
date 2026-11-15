import Foundation

/// Preserve write ordering while keeping JSON encoding and preferences I/O
/// off the Bluetooth/UI queue. Encoding failures keep the last valid value.
final class BackgroundPreferencesWriter {
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "strap.preferences.snapshots", qos: .utility)
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func write<Value: Encodable>(_ value: Value, forKey key: String, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            let saved: Bool
            do {
                let data = try JSONEncoder().encode(value)
                self.defaults.set(data, forKey: key)
                saved = true
            } catch { saved = false }
            if let completion { DispatchQueue.main.async { completion(saved) } }
        }
    }
    func remove(forKey key: String) {
        queue.async { self.defaults.removeObject(forKey: key) }
    }

    func flush(completion: @escaping () -> Void) {
        queue.async { DispatchQueue.main.async(execute: completion) }
    }
}

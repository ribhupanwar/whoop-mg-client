import Foundation

final class BLEDiagnosticLog {
    static let shared = BLEDiagnosticLog()
    private let queue = DispatchQueue(label: "ble.diag", qos: .utility)
    private let maxBytes = 1_000_000
    private let url: URL
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        url = docs.appendingPathComponent("ble-diagnostics.log")
    }
    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.url.path) {
                    if let handle = try? FileHandle(forWritingTo: self.url) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.url)
                }
                self.trimIfNeeded()
            }
        }
    }
    private func trimIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.intValue > maxBytes else { return }
        if let data = try? Data(contentsOf: url) {
            let tail = data.suffix(maxBytes / 2)
            try? tail.write(to: url)
        }
    }
    func exportURL() -> URL { url }
    func redact(_ value: String) -> String {
        value.count <= 4 ? "****" : String(value.prefix(2)) + "..." + String(value.suffix(2))
    }
}

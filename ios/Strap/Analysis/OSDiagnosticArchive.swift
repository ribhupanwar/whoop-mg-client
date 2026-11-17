import Foundation
import MetricKit

/// Retains only actual OS-delivered payloads locally. No network upload,
/// simulated crash report or claim that an empty archive means no failures.
final class OSDiagnosticArchive: NSObject, MXMetricManagerSubscriber {
    static let shared = OSDiagnosticArchive()
    private let queue = DispatchQueue(label: "strap.os-diagnostics", qos: .utility)
    private var registered = false
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures/os-diagnostics", isDirectory: true)
    }
    func start() {
        guard !registered else { return }
        registered = true
        MXMetricManager.shared.add(self)
    }
    func didReceive(_ payloads: [MXMetricPayload]) {
        retain(payloads.map { $0.jsonRepresentation() }, kind: "metrics")
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        retain(payloads.map { $0.jsonRepresentation() }, kind: "diagnostics")
    }
    private func retain(_ payloads: [Data], kind: String) {
        queue.async {
            for payload in payloads {
                do { try Self.preserve(payload, kind: kind) }
                catch { NSLog("STRAP OS diagnostic archive failed: %@", error.localizedDescription) }
            }
        }
    }
    /// Content-addressed original JSON; repeat OS delivery is idempotent.
    /// Caller serializes writes. Existing differing bytes are never replaced.
    static func preserve(_ data: Data, kind: String, directory: URL = directory) throws {
        guard ["metrics", "diagnostics"].contains(kind),
              (try JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw PersistenceDiagnostics.Failure(message: "Invalid OS diagnostic JSON; no archive replaced.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(kind + "-" + PersistenceDiagnostics.digest(data) + ".json")
        if fm.fileExists(atPath: file.path) {
            guard try Data(contentsOf: file) == data else {
                throw PersistenceDiagnostics.Failure(message: "OS diagnostic archive conflict; existing evidence preserved.")
            }
            return
        }
        try data.write(to: file, options: .atomic)
    }
}

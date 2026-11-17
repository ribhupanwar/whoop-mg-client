import Foundation

/// Append-only evidence of replaced sleep caches, including undecodable bytes.
/// Hash naming makes replay idempotent. Never pruned automatically.
enum SleepRecoveryVault {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sleep-recovery", isDirectory: true)
    }
    static let keys: Set<String> = ["strap.capture.summary.v1", "strap.sleep.analysis.v1", "strap.days.v1"]
    static func preserve(_ data: Data, key: String, directory: URL = directory) throws {
        guard keys.contains(key) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(key + "-" + PersistenceDiagnostics.digest(data) + ".json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
    }
    struct Candidate: Identifiable {
        let session: SleepSession
        let provenance: String
        var id: String { provenance + ":\(session.sourceStartUnix):\(session.startUnix):\(session.endUnix)" }
    }
    static func candidates(defaults: UserDefaults = .standard, directory: URL = directory) throws -> [Candidate] {
        var sources: [(String, Data)] = []
        if let data = defaults.data(forKey: "strap.capture.summary.v1") {
            sources.append(("Saved capture summary", data))
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix("strap.capture.summary.v1-") {
                sources.append((url.lastPathComponent, try Data(contentsOf: url)))
            }
        }
        return sources.flatMap { source -> [Candidate] in
            guard let summary = try? JSONDecoder().decode(CaptureSummary.self, from: source.1) else { return [] }
            return (summary.sleepSessions ?? []).filter { $0.endUnix > $0.startUnix }.map {
                Candidate(session: $0, provenance: source.0)
            }
        }.sorted { $0.session.endUnix > $1.session.endUnix }
    }
}

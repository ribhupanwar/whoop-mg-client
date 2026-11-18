import Foundation

/// Immutable original notification. A bounded analysis window must not impose
/// a retention limit on durable beat history. Legacy records keep unknown
/// subsecond receipt time nil instead of inventing precision.
struct LiveRRRecord: Codable, Equatable, Identifiable {
    let id: String
    let source: String
    let receivedAtUnix: Double?
    let sample: LiveSample

    static func received(_ sample: LiveSample, source: String, at date: Date = Date()) -> LiveRRRecord {
        LiveRRRecord(id: UUID().uuidString, source: source, receivedAtUnix: date.timeIntervalSince1970, sample: sample)
    }
    static func legacy(_ sample: LiveSample) throws -> LiveRRRecord {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = PersistenceDiagnostics.digest(try encoder.encode(sample))
        return LiveRRRecord(id: "legacy:" + digest, source: "retained-live-RR-preferences",
                            receivedAtUnix: nil, sample: sample)
    }
}

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


/// Connection-local, source-separated input evidence for a future live
/// stress consumer. Receipt seconds are not band beat identities. Do not
/// merge sources, restore old buffers, or infer motion/awake state.
struct LiveRRSourceWindows: Equatable {
    struct Coverage: Equatable {
        let source: String
        let observedSeconds: Int
        let validBeats: Int
        let beatDurationSeconds: Double
        let latestUnix: Int
        let spanSeconds: Int
        let longestContiguousSeconds: Int
    }

    static let horizonSeconds = 300
    private var bySource: [String: [Int: LiveSample]] = [:]

    mutating func ingest(_ row: LiveRRRecord) {
        // Only the known live transports; legacy/import is not live.
        guard row.source == "WHOOP Type-40" || row.source == "Bluetooth 2A37",
              row.receivedAtUnix != nil, !row.sample.rrIntervalsMS.isEmpty else { return }
        let sample = row.sample
        var rows = bySource[row.source, default: [:]]
        if let newest = rows.keys.max(), sample.unix < newest - Self.horizonSeconds + 1 { return }
        if let previous = rows[sample.unix],
           !Hrv.preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) { return }
        rows[sample.unix] = sample
        let newest = max(sample.unix, rows.keys.max() ?? sample.unix)
        rows = rows.filter { $0.key >= newest - Self.horizonSeconds + 1 }
        bySource[row.source] = rows
    }

    func coverage(at nowUnix: Int) -> [Coverage] {
        bySource.keys.sorted().compactMap { source in
            guard let rows = bySource[source] else { return nil }
            let ordered = rows.values.filter {
                $0.unix <= nowUnix && $0.unix >= nowUnix - Self.horizonSeconds + 1 &&
                $0.rrIntervalsMS.contains { (300...2000).contains($0) }
            }.sorted { $0.unix < $1.unix }
            guard let first = ordered.first, let last = ordered.last else { return nil }
            var longest = 0
            var current = 0
            var previous: Int?
            var beats = 0
            var duration = 0.0
            for sample in ordered {
                current = previous.map { sample.unix == $0 + 1 } == true ? current + 1 : 1
                longest = max(longest, current)
                previous = sample.unix
                for rr in sample.rrIntervalsMS where (300...2000).contains(rr) {
                    beats += 1
                    duration += Double(rr) / 1000
                }
            }
            return Coverage(source: source, observedSeconds: ordered.count, validBeats: beats,
                            beatDurationSeconds: duration, latestUnix: last.unix,
                            spanSeconds: last.unix - first.unix + 1, longestContiguousSeconds: longest)
        }
    }
}

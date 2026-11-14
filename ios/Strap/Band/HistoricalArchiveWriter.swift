import Foundation

/// Owns decoded history on a serial worker. Completion always arrives on main.
/// Raw capture files remain the durable, pre-ACK recovery source.
final class HistoricalArchiveWriter {
    private let url: URL
    private let queue = DispatchQueue(label: "strap.history.archive", qos: .utility)
    private var retained: [V18Sample]?
    private var pending: [Int: V18Sample] = [:]

    init(url: URL) { self.url = url }

    func merge(_ incoming: [V18Sample], completion: @escaping (Result<[V18Sample], Error>) -> Void) {
        queue.async {
            // A failed write must survive the next drain replacing its capture
            // buffer. Retry these records with every subsequent merge.
            self.pending = HistoricalCaptureRecovery.merged(Array(self.pending.values) + incoming)
            let result: Result<[V18Sample], Error> = Result {
                let previous: [V18Sample]
                if let retained = self.retained {
                    previous = retained
                } else if FileManager.default.fileExists(atPath: self.url.path) {
                    let data = try Data(contentsOf: self.url)
                    do {
                        previous = try JSONDecoder().decode([V18Sample].self, from: data)
                    } catch is DecodingError {
                        // Keep the broken file before rebuilding from durable
                        // raw captures. Read/access and backup errors still fail.
                        let backup = self.url.deletingPathExtension()
                            .appendingPathExtension("invalid-\(UUID().uuidString).json")
                        try FileManager.default.copyItem(at: self.url, to: backup)
                        previous = []
                    }
                } else {
                    previous = []
                }
                let records = HistoricalCaptureRecovery.merged(previous + Array(self.pending.values))
                let ordered = records.values.sorted { $0.unix < $1.unix }
                let cutoff = (ordered.last?.unix ?? 0) - 72 * 3600
                let merged = ordered.filter { $0.unix >= cutoff }
                try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try JSONEncoder().encode(merged).write(to: self.url, options: .atomic)
                self.retained = merged
                self.pending.removeAll()
                return merged
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

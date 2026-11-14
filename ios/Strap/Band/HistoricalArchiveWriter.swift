import Foundation

/// Owns decoded history on a serial worker. Completion always arrives on main.
/// Raw capture files remain the durable, pre-ACK recovery source.
final class HistoricalArchiveWriter {
    private let url: URL
    private let queue = DispatchQueue(label: "strap.history.archive", qos: .utility)
    private var retained: [V18Sample]?

    init(url: URL) { self.url = url }

    func merge(_ incoming: [V18Sample], completion: @escaping (Result<[V18Sample], Error>) -> Void) {
        queue.async {
            let result: Result<[V18Sample], Error> = Result {
                let previous: [V18Sample]
                if let retained = self.retained {
                    previous = retained
                } else if FileManager.default.fileExists(atPath: self.url.path) {
                    previous = try JSONDecoder().decode([V18Sample].self, from: Data(contentsOf: self.url))
                } else {
                    previous = []
                }
                let records = HistoricalCaptureRecovery.merged(previous + incoming)
                let ordered = records.values.sorted { $0.unix < $1.unix }
                let cutoff = (ordered.last?.unix ?? 0) - 72 * 3600
                let merged = ordered.filter { $0.unix >= cutoff }
                try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try JSONEncoder().encode(merged).write(to: self.url, options: .atomic)
                self.retained = merged
                return merged
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

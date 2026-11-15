import Foundation

/// Serial SQLite transactions; callbacks always arrive on main. Raw captures
/// remain a second pre-ACK recovery source. No whole-archive JSON rewrites.
final class HistoricalArchiveWriter {
    let databaseURL: URL
    private let legacyURL: URL
    private let queue = DispatchQueue(label: "strap.history.archive", qos: .utility)
    private var database: HistoryDatabase?
    private var pending: [Int: V18Sample] = [:]

    init(url: URL) {
        legacyURL = url
        databaseURL = url.deletingPathExtension().appendingPathExtension("sqlite")
    }

    func merge(_ incoming: [V18Sample], completion: @escaping (Result<[V18Sample], Error>) -> Void) {
        queue.async {
            let result = Result {
                _ = try self.commit(incoming, token: nil)
                return try self.open().recentSamples()
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// A chunk commit does not load the analysis window or launch new analysis.
    func persistChunk(_ incoming: [V18Sample], token: String,
                      completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            let result = Result { try self.commit(incoming, token: token) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func open() throws -> HistoryDatabase {
        if let database { return database }
        let opened = try HistoryDatabase(url: databaseURL)
        try opened.migrateLegacyJSON(at: legacyURL)
        database = opened
        return opened
    }

    private func commit(_ incoming: [V18Sample], token: String?) throws -> Int {
        for sample in incoming {
            if let old = pending[sample.unix], !HistoricalRecordSelection.prefers(sample, over: old) { continue }
            pending[sample.unix] = sample
        }
        let changed = try open().commit(Array(pending.values), token: token)
        pending.removeAll(keepingCapacity: true)
        return changed
    }
}

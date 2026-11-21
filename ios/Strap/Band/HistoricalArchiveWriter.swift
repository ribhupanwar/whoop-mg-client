import Foundation

/// Serial SQLite transactions; callbacks always arrive on main. Raw captures
/// remain a second pre-ACK recovery source. No whole-archive JSON rewrites.
final class HistoricalArchiveWriter {
    let databaseURL: URL
    private let legacyURL: URL
    private let queue = DispatchQueue(label: "strap.history.archive", qos: .userInitiated)
    private var database: HistoryDatabase?
    private var pending: [Int: V18Sample] = [:]
    private var pendingLiveRR: [String: LiveRRRecord] = [:]
    private var liveRRCount: Int?
    private var pendingLegacyLiveRR: [LiveSample]?

    init(url: URL) {
        legacyURL = url
        databaseURL = url.deletingPathExtension().appendingPathExtension("sqlite")
    }

    func merge(_ incoming: [V18Sample], completion: @escaping (Result<[V18Sample], Error>) -> Void) {
        mergeReportingProgress(incoming) { result in
            completion(result.map { $0.samples })
        }
    }

    func mergeReportingProgress(_ incoming: [V18Sample],
                                completion: @escaping (Result<(samples: [V18Sample], progress: HistoryDatabase.CommitProgress), Error>) -> Void) {
        queue.async {
            let result = Result {
                let progress = try self.commit(incoming, token: nil)
                return (samples: try self.open().recentSamples(), progress: progress)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// A chunk commit does not load the analysis window or launch new analysis.
    func persistChunk(_ incoming: [V18Sample], token: String,
                      completion: @escaping (Result<Int, Error>) -> Void) {
        persistChunkReportingProgress(incoming, token: token) { completion($0.map(\.changed)) }
    }

    func persistChunkReportingProgress(_ incoming: [V18Sample], token: String,
                                       completion: @escaping (Result<HistoryDatabase.CommitProgress, Error>) -> Void) {
        queue.async {
            let result = Result { try self.commit(incoming, token: token) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func samples(from start: Int, through end: Int,
                 completion: @escaping (Result<[V18Sample], Error>) -> Void) {
        queue.async {
            let result = Result { try self.open().samples(from: start, through: end) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func persistLiveRR(_ records: [LiveRRRecord], completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            let result = Result { try self.commitLiveRR(records) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func importLegacyLiveRR(_ samples: [LiveSample], completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            self.pendingLegacyLiveRR = samples
            let result = Result { try self.commitLiveRR([]) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func flush(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            let result = Result {
                _ = try self.commit([], token: nil)
                return try self.commitLiveRR([])
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    private func commitLiveRR(_ records: [LiveRRRecord]) throws -> Int {
        for record in records { pendingLiveRR[record.id] = record }
        do {
            let opened = try open()
            if let legacy = pendingLegacyLiveRR {
                liveRRCount = try opened.migrateLegacyLiveRR(legacy)
                pendingLegacyLiveRR = nil
            }
            let inserted = try opened.commitLiveRR(Array(pendingLiveRR.values))
            pendingLiveRR.removeAll(keepingCapacity: true)
            let count = try liveRRCount.map { $0 + inserted } ?? opened.liveRRCount()
            liveRRCount = count
            return count
        } catch {
            database = nil; liveRRCount = nil
            throw error
        }
    }

    private func open() throws -> HistoryDatabase {
        if let database { return database }
        let opened = try HistoryDatabase(url: databaseURL)
        try opened.migrateLegacyJSON(at: legacyURL)
        database = opened
        return opened
    }

    private func commit(_ incoming: [V18Sample], token: String?) throws -> HistoryDatabase.CommitProgress {
        for sample in incoming {
            if let old = pending[sample.unix], !HistoricalRecordSelection.prefers(sample, over: old) { continue }
            pending[sample.unix] = sample
        }
        do {
            let progress = try open().commitReportingProgress(Array(pending.values), token: token)
            pending.removeAll(keepingCapacity: true)
            return progress
        } catch {
            // Reopen after a storage failure: don't reuse a connection whose
            // rollback may itself have failed. Pending rows survive the retry;
            // the existing database, WAL and legacy archive stay intact.
            database = nil
            throw error
        }
    }
}

import CryptoKit
import Foundation

/// Durable work checkpoints. A fingerprint covers the exact input, settings and
/// recipe version; a completed unit is reusable across app termination/relaunch.
/// Owned exclusively by the history analysis worker, on a separate connection.
final class HistoryAnalysisCache {
    // Bump whenever a cached sleep/day calculation changes its meaning.
    static let recipe = 4

    // PR #106 changed the daily RHR statistic from minimum to median.
    // Keep staged-night checkpoints reusable while refreshing daily metrics.
    static func dailyKey(_ dateKey: String) -> String { "day-accuracy-v3:\(dateKey)" }
    struct Ticket { let key: String; let fingerprint: String }
    private let database: HistoryDatabase
    private let encoder = JSONEncoder()
    private(set) var lastError: String?

    init(url: URL) throws {
        database = try HistoryDatabase(url: url)
        encoder.outputFormatting = [.sortedKeys]
    }

    func ticket<T: Encodable>(key: String, samples: [V18Sample], context: T) -> Ticket? {
        do {
            var hash = SHA256()
            hash.update(data: try encoder.encode(context))
            // Bound scratch memory to one record, not an entire encoded night.
            for sample in samples { hash.update(data: try encoder.encode(sample)) }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            return Ticket(key: "recipe:\(Self.recipe):\(key)", fingerprint: digest)
        } catch { lastError = error.localizedDescription; return nil }
    }

    func load<T: Decodable>(_ type: T.Type, ticket: Ticket?) -> T? {
        guard let ticket else { return nil }
        do { return try database.cached(type, key: ticket.key, fingerprint: ticket.fingerprint) }
        catch { lastError = error.localizedDescription; return nil }
    }

    func save<T: Encodable>(_ value: T, ticket: Ticket?) {
        guard let ticket else { return }
        do { try database.cache(value, key: ticket.key, fingerprint: ticket.fingerprint) }
        catch { lastError = error.localizedDescription }
    }

    func night(samples: [V18Sample], period: SleepPeriod, correctedTimes: [Int]?) -> (SleepSession, Bool) {
        struct Context: Codable {
            let algorithm: Int
            let sourceStart: Int
            let sourceEnd: Int
            let times: [Int]?
        }
        let times = SleepCorrectionStore.validated(correctedTimes)
        let start = times?.first ?? period.startUnix
        let end = times?.last ?? (period.endUnix + 1)
        let rows = samples.filter { start <= $0.unix && $0.unix < end }
        let context = Context(algorithm: SleepSession.algorithmVersion,
                              sourceStart: period.startUnix, sourceEnd: period.endUnix, times: times)
        let ticket = ticket(key: "night:\(period.startUnix)", samples: rows, context: context)
        if let saved = load(SleepSession.self, ticket: ticket) { return (saved, true) }
        let fresh = SleepSession.make(samples: rows, period: period, correctedTimes: times)
        save(fresh, ticket: ticket)
        return (fresh, false)
    }
}

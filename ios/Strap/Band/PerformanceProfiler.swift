#if DEBUG
import Foundation
import os.signpost

/// Aggregate timing for the durable history commit, visible in Instruments.
enum PerformanceProfiler {
    private static let log = OSLog(subsystem: "com.strap.app", category: .pointsOfInterest)

    static func measureHistoryCommit<T>(_ operation: () throws -> T) rethrows -> T {
        guard log.signpostsEnabled else { return try operation() }
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "History Commit", signpostID: id)
        defer { os_signpost(.end, log: log, name: "History Commit", signpostID: id) }
        return try operation()
    }
}
#endif

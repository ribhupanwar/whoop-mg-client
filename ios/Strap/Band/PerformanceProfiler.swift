import Foundation
import os.signpost

/// Lightweight, production-safe performance profiler for STRAP.
/// Uses os_signpost for Instruments integration and in-memory histograms for CI baselines.
final class PerformanceProfiler {
    static let shared = PerformanceProfiler()

    private let log = OSLog(subsystem: "com.strap.app", category: .pointsOfInterest)
    private let queue = DispatchQueue(label: "strap.performance.profiler", qos: .utility)

    // In-memory metrics for CI baseline reporting
    private var blePacketThroughput: [TimeInterval] = []
    private var bleDuplicateCounts: [Int] = []
    private var bleAckRetryCounts: [Int] = []
    private var bleReconnectCounts: [Int] = []
    private var bleMemorySamples: [UInt64] = []

    private var sqliteTransactionCounts: [Int] = []
    private var sqliteBatchSizes: [Int] = []
    private var sqliteCommitLatencies: [TimeInterval] = []
    private var sqliteContentionEvents: [Int] = []

    private var cpuSamples: [Double] = []
    private var memorySamples: [UInt64] = []

    private var swiftUIRefreshCounts: [Int] = []
    private var chartRenderTimes: [TimeInterval] = []

    private var notificationProcessingTimes: [TimeInterval] = []
    private var backgroundTransitionTimes: [TimeInterval] = []

    private init() {}

    // MARK: - BLE History Sync Profiling

    func recordBLEPacketReceived() {
        queue.async {
            self.blePacketThroughput.append(Date().timeIntervalSinceReferenceDate)
            if self.blePacketThroughput.count > 10000 { self.blePacketThroughput.removeFirst(5000) }
        }
    }

    func recordBLEDuplicateDetected(count: Int) {
        queue.async { self.bleDuplicateCounts.append(count) }
    }

    func recordBLEAckRetry(count: Int) {
        queue.async { self.bleAckRetryCounts.append(count) }
    }

    func recordBLEResconnect(count: Int) {
        queue.async { self.bleReconnectCounts.append(count) }
    }

    func recordBLEMemoryUsage(_ bytes: UInt64) {
        queue.async {
            self.bleMemorySamples.append(bytes)
            if self.bleMemorySamples.count > 1000 { self.bleMemorySamples.removeFirst(500) }
        }
    }

    // MARK: - SQLite Write Profiling

    func recordSQLiteTransaction(batchSize: Int, latency: TimeInterval, contentionCount: Int = 0) {
        queue.async {
            self.sqliteTransactionCounts.append(1)
            self.sqliteBatchSizes.append(batchSize)
            self.sqliteCommitLatencies.append(latency)
            self.sqliteContentionEvents.append(contentionCount)
            if self.sqliteTransactionCounts.count > 10000 {
                self.sqliteTransactionCounts.removeFirst(5000)
                self.sqliteBatchSizes.removeFirst(5000)
                self.sqliteCommitLatencies.removeFirst(5000)
                self.sqliteContentionEvents.removeFirst(5000)
            }
        }
    }

    // MARK: - CPU/Memory Profiling

    func recordCPUSample(_ percent: Double) {
        queue.async {
            self.cpuSamples.append(percent)
            if self.cpuSamples.count > 1000 { self.cpuSamples.removeFirst(500) }
        }
    }

    func recordMemorySample(_ bytes: UInt64) {
        queue.async {
            self.memorySamples.append(bytes)
            if self.memorySamples.count > 1000 { self.memorySamples.removeFirst(500) }
        }
    }

    // MARK: - SwiftUI Profiling

    func recordSwiftUIRefresh(count: Int) {
        queue.async { self.swiftUIRefreshCounts.append(count) }
    }

    func recordChartRenderTime(_ duration: TimeInterval) {
        queue.async { self.chartRenderTimes.append(duration) }
    }

    // MARK: - Notification/Background Profiling

    func recordNotificationProcessingTime(_ duration: TimeInterval) {
        queue.async { self.notificationProcessingTimes.append(duration) }
    }

    func recordBackgroundTransitionTime(_ duration: TimeInterval) {
        queue.async { self.backgroundTransitionTimes.append(duration) }
    }

    // MARK: - os_signpost Integration for Instruments

    func beginBLEPacketInterval(name: String) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "BLE Packet", signpostID: id, "%{public}s", name)
        return id
    }

    func endBLEPacketInterval(name: String, id: OSSignpostID) {
        os_signpost(.end, log: log, name: "BLE Packet", signpostID: id, "%{public}s", name)
    }

    func beginSQLiteTransaction() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "SQLite Transaction", signpostID: id)
        return id
    }

    func endSQLiteTransaction(id: OSSignpostID, batchSize: Int, latencyMs: Double) {
        os_signpost(.end, log: log, name: "SQLite Transaction", signpostID: id, "batchSize=%d latencyMs=%.2f", batchSize, latencyMs)
    }

    func beginHistoryDrain() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "History Drain", signpostID: id)
        return id
    }

    func endHistoryDrain(id: OSSignpostID, totalFrames: Int, totalSamples: Int, durationSec: Double) {
        os_signpost(.end, log: log, name: "History Drain", signpostID: id, "frames=%d samples=%d duration=%.2fs", totalFrames, totalSamples, durationSec)
    }

    // MARK: - Baseline Reporting

    struct ProfilerBaselines {
        let blePacketsPerSecond: Double
        let bleDuplicateRate: Double
        let bleAckRetryRate: Double
        let bleReconnectRate: Double
        let blePeakMemoryMB: Double
        let sqliteTransactionsPerSecond: Double
        let sqliteAvgBatchSize: Double
        let sqliteAvgCommitLatencyMs: Double
        let sqliteContentionRate: Double
        let cpuAvgPercent: Double
        let cpuPeakPercent: Double
        let memoryAvgMB: Double
        let memoryPeakMB: Double
        let swiftUIAvgRefreshesPerSecond: Double
        let chartAvgRenderTimeMs: Double
        let notificationAvgProcessingTimeMs: Double
        let backgroundAvgTransitionTimeMs: Double
    }

    func captureBaselines() -> ProfilerBaselines {
        return queue.sync {
            let now = Date().timeIntervalSinceReferenceDate

            // BLE throughput: packets in last 60 seconds
            let recentPackets = blePacketThroughput.filter { now - $0 <= 60 }
            let blePacketsPerSecond = Double(recentPackets.count) / 60.0

            let totalDuplicates = bleDuplicateCounts.reduce(0, +)
            let totalPackets = blePacketThroughput.count
            let bleDuplicateRate = totalPackets > 0 ? Double(totalDuplicates) / Double(totalPackets) : 0

            let totalRetries = bleAckRetryCounts.reduce(0, +)
            let bleAckRetryRate = totalPackets > 0 ? Double(totalRetries) / Double(totalPackets) : 0

            let totalReconnects = bleReconnectCounts.reduce(0, +)
            let bleReconnectRate = totalPackets > 0 ? Double(totalReconnects) / Double(totalPackets) : 0

            let blePeakMemoryMB = Double(bleMemorySamples.max() ?? 0) / (1024 * 1024)

            // SQLite
            let txCount = sqliteTransactionCounts.count
            let sqliteTransactionsPerSecond = txCount > 0 ? Double(txCount) / 60.0 : 0 // assuming 60s window
            let sqliteAvgBatchSize = sqliteBatchSizes.isEmpty ? 0 : Double(sqliteBatchSizes.reduce(0, +)) / Double(sqliteBatchSizes.count)
            let sqliteAvgCommitLatencyMs = sqliteCommitLatencies.isEmpty ? 0 : (sqliteCommitLatencies.reduce(0, +) / Double(sqliteCommitLatencies.count)) * 1000
            let totalContention = sqliteContentionEvents.reduce(0, +)
            let sqliteContentionRate = txCount > 0 ? Double(totalContention) / Double(txCount) : 0

            // CPU/Memory
            let cpuAvgPercent = cpuSamples.isEmpty ? 0 : cpuSamples.reduce(0, +) / Double(cpuSamples.count)
            let cpuPeakPercent = cpuSamples.max() ?? 0
            let memoryAvgMB = memorySamples.isEmpty ? 0 : Double(memorySamples.reduce(0, +)) / Double(memorySamples.count) / (1024 * 1024)
            let memoryPeakMB = Double(memorySamples.max() ?? 0) / (1024 * 1024)

            // SwiftUI
            let swiftUIAvgRefreshesPerSecond = swiftUIRefreshCounts.isEmpty ? 0 : Double(swiftUIRefreshCounts.reduce(0, +)) / Double(swiftUIRefreshCounts.count) / 60.0
            let chartAvgRenderTimeMs = chartRenderTimes.isEmpty ? 0 : (chartRenderTimes.reduce(0, +) / Double(chartRenderTimes.count)) * 1000

            // Notifications/Background
            let notificationAvgProcessingTimeMs = notificationProcessingTimes.isEmpty ? 0 : (notificationProcessingTimes.reduce(0, +) / Double(notificationProcessingTimes.count)) * 1000
            let backgroundAvgTransitionTimeMs = backgroundTransitionTimes.isEmpty ? 0 : (backgroundTransitionTimes.reduce(0, +) / Double(backgroundTransitionTimes.count)) * 1000

            return ProfilerBaselines(
                blePacketsPerSecond: blePacketsPerSecond,
                bleDuplicateRate: bleDuplicateRate,
                bleAckRetryRate: bleAckRetryRate,
                bleReconnectRate: bleReconnectRate,
                blePeakMemoryMB: blePeakMemoryMB,
                sqliteTransactionsPerSecond: sqliteTransactionsPerSecond,
                sqliteAvgBatchSize: sqliteAvgBatchSize,
                sqliteAvgCommitLatencyMs: sqliteAvgCommitLatencyMs,
                sqliteContentionRate: sqliteContentionRate,
                cpuAvgPercent: cpuAvgPercent,
                cpuPeakPercent: cpuPeakPercent,
                memoryAvgMB: memoryAvgMB,
                memoryPeakMB: memoryPeakMB,
                swiftUIAvgRefreshesPerSecond: swiftUIAvgRefreshesPerSecond,
                chartAvgRenderTimeMs: chartAvgRenderTimeMs,
                notificationAvgProcessingTimeMs: notificationAvgProcessingTimeMs,
                backgroundAvgTransitionTimeMs: backgroundAvgTransitionTimeMs
            )
        }
    }

    func printBaselines() {
        let b = captureBaselines()
        print("""
        ===== STRAP Performance Baselines =====
        BLE History Sync:
          Packets/sec:          \(String(format: "%.1f", b.blePacketsPerSecond))
          Duplicate rate:       \(String(format: "%.3f", b.bleDuplicateRate))
          ACK retry rate:       \(String(format: "%.3f", b.bleAckRetryRate))
          Reconnect rate:       \(String(format: "%.3f", b.bleReconnectRate))
          Peak memory (MB):     \(String(format: "%.1f", b.blePeakMemoryMB))
        SQLite Writes:
          Transactions/sec:     \(String(format: "%.1f", b.sqliteTransactionsPerSecond))
          Avg batch size:       \(String(format: "%.1f", b.sqliteAvgBatchSize))
          Avg commit latency:   \(String(format: "%.2f", b.sqliteAvgCommitLatencyMs)) ms
          Contention rate:      \(String(format: "%.3f", b.sqliteContentionRate))
        CPU/Memory:
          Avg CPU %:            \(String(format: "%.1f", b.cpuAvgPercent))
          Peak CPU %:           \(String(format: "%.1f", b.cpuPeakPercent))
          Avg memory (MB):      \(String(format: "%.1f", b.memoryAvgMB))
          Peak memory (MB):     \(String(format: "%.1f", b.memoryPeakMB))
        SwiftUI:
          Avg refreshes/sec:    \(String(format: "%.2f", b.swiftUIAvgRefreshesPerSecond))
          Chart render (ms):    \(String(format: "%.2f", b.chartAvgRenderTimeMs))
        Notifications/Background:
          Notification proc:    \(String(format: "%.2f", b.notificationAvgProcessingTimeMs)) ms
          Background transition: \(String(format: "%.2f", b.backgroundAvgTransitionTimeMs)) ms
        ========================================
        """)
    }

    func reset() {
        queue.async {
            self.blePacketThroughput.removeAll()
            self.bleDuplicateCounts.removeAll()
            self.bleAckRetryCounts.removeAll()
            self.bleReconnectCounts.removeAll()
            self.bleMemorySamples.removeAll()
            self.sqliteTransactionCounts.removeAll()
            self.sqliteBatchSizes.removeAll()
            self.sqliteCommitLatencies.removeAll()
            self.sqliteContentionEvents.removeAll()
            self.cpuSamples.removeAll()
            self.memorySamples.removeAll()
            self.swiftUIRefreshCounts.removeAll()
            self.chartRenderTimes.removeAll()
            self.notificationProcessingTimes.removeAll()
            self.backgroundTransitionTimes.removeAll()
        }
    }
}
import XCTest
@testable import Strap

final class PerformanceProfilerTests: XCTestCase {

    func testProfilerReset() {
        let profiler = PerformanceProfiler.shared
        profiler.reset()

        // Record some metrics
        profiler.recordBLEPacketReceived()
        profiler.recordBLEPacketReceived()
        profiler.recordBLEDuplicateDetected(count: 1)
        profiler.recordBLEAckRetry(count: 1)
        profiler.recordBLEMemoryUsage(10 * 1024 * 1024)

        profiler.recordSQLiteTransaction(batchSize: 100, latency: 0.005, contentionCount: 0)

        profiler.recordCPUSample(25.0)
        profiler.recordMemorySample(50 * 1024 * 1024)

        profiler.recordSwiftUIRefresh(count: 10)
        profiler.recordChartRenderTime(0.016)

        profiler.recordNotificationProcessingTime(0.001)
        profiler.recordBackgroundTransitionTime(0.050)

        let baselines = profiler.captureBaselines()

        XCTAssertGreaterThan(baselines.blePacketsPerSecond, 0)
        XCTAssertEqual(baselines.bleDuplicateRate, 0.5, accuracy: 0.1) // 1 duplicate / 2 packets
        XCTAssertEqual(baselines.bleAckRetryRate, 0.5, accuracy: 0.1)
        XCTAssertEqual(baselines.blePeakMemoryMB, 10.0, accuracy: 0.1)
        XCTAssertEqual(baselines.sqliteAvgBatchSize, 100.0, accuracy: 1.0)
        XCTAssertEqual(baselines.sqliteAvgCommitLatencyMs, 5.0, accuracy: 1.0)
        XCTAssertEqual(baselines.cpuAvgPercent, 25.0, accuracy: 1.0)
        XCTAssertEqual(baselines.memoryAvgMB, 50.0, accuracy: 1.0)
        XCTAssertEqual(baselines.swiftUIAvgRefreshesPerSecond, 10.0 / 60.0, accuracy: 0.1)
        XCTAssertEqual(baselines.chartAvgRenderTimeMs, 16.0, accuracy: 1.0)
        XCTAssertEqual(baselines.notificationAvgProcessingTimeMs, 1.0, accuracy: 0.5)
        XCTAssertEqual(baselines.backgroundAvgTransitionTimeMs, 50.0, accuracy: 5.0)

        // Reset and verify cleared
        profiler.reset()
        let clearedBaselines = profiler.captureBaselines()
        XCTAssertEqual(clearedBaselines.blePacketsPerSecond, 0)
        XCTAssertEqual(clearedBaselines.bleDuplicateRate, 0)
    }

    func testOSSignpostIDs() {
        let profiler = PerformanceProfiler.shared

        let id1 = profiler.beginBLEPacketInterval(name: "Test Packet")
        profiler.endBLEPacketInterval(name: "Test Packet", id: id1)

        let id2 = profiler.beginSQLiteTransaction()
        profiler.endSQLiteTransaction(id: id2, batchSize: 50, latencyMs: 2.5)

        let id3 = profiler.beginHistoryDrain()
        profiler.endHistoryDrain(id: id3, totalFrames: 100, totalSamples: 5000, durationSec: 1.5)

        // Should not crash
        XCTAssert(true)
    }

    func testProfilerBaselinesPrint() {
        let profiler = PerformanceProfiler.shared
        profiler.reset()

        // Add some data
        for _ in 0..<100 {
            profiler.recordBLEPacketReceived()
        }
        profiler.recordBLEMemoryUsage(25 * 1024 * 1024)

        // This should print without crashing
        profiler.printBaselines()
    }
}
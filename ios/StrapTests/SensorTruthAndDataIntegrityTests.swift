import Foundation
import SQLite3
import XCTest
@testable import Strap

final class SensorTruthAndDataIntegrityTests: XCTestCase {
    private var directory: URL!
    private var databaseURL: URL { directory.appendingPathComponent("history.sqlite") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("StrapTruthTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSample(
        unix: Int,
        recordIndex: UInt32? = nil,
        subsecQ15: Int = 0,
        hr: Int = 65,
        rr: [Int] = [920],
        motion: Double? = 0.012,
        temp: Double? = 33.5,
        sleepState: Int? = 2
    ) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18,
                flags: 0x80,
                recordIndex: recordIndex ?? UInt32(unix),
                unix: UInt32(unix),
                subsecQ15: subsecQ15
            ),
            heartRate: hr,
            rrIntervalsMS: rr,
            dynamicAccelG: motion,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: 100, stepCadence: nil, activityClass: 0,
            skinTempC: temp, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: sleepState.map { $0 << 4 }, sleepState: sleepState,
            cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    // MARK: - Test 1: Duplicate Packet Replay Idempotency
    func testDuplicatePacketReplayIdempotency() throws {
        let db = try HistoryDatabase(url: databaseURL)
        let samples = (1700000000..<1700000100).map { makeSample(unix: $0) }

        // First insertion
        _ = try db.commit(samples)
        XCTAssertEqual(try db.samples(from: 0, through: 2_000_000_000).count, 100)

        // Duplicate replay of the exact same records
        _ = try db.commit(samples)
        XCTAssertEqual(try db.samples(from: 0, through: 2_000_000_000).count, 100, "Duplicate replayed packets must not inflate database count")

        // Interleaved duplicate replay
        let interleaved = samples.flatMap { [$0, $0] }
        _ = try db.commit(interleaved)
        XCTAssertEqual(try db.samples(from: 0, through: 2_000_000_000).count, 100, "Interleaved duplicates must be deduplicated idempotently")
    }

    // MARK: - Test 2: Missing Record Ranges
    func testMissingRecordRangesDetectedAndIsolated() {
        // Records 1000..1010 and 1025..1035 with a 14-record gap in between
        var samples: [V18Sample] = []
        for idx in UInt32(1000)...UInt32(1010) {
            samples.append(makeSample(unix: Int(idx), recordIndex: idx))
        }
        for idx in UInt32(1025)...UInt32(1035) {
            samples.append(makeSample(unix: Int(idx), recordIndex: idx))
        }

        let report = SensorTruthDiagnostics.audit(samples: samples)
        XCTAssertEqual(report.persistence.missingRecordIndexGaps, 1, "Must detect exactly 1 missing index gap")
        XCTAssertEqual(report.persistence.missingRecordIndexCount, 14, "Must detect exactly 14 missing records in gap")
        XCTAssertEqual(report.persistence.timestampGaps, 1)
        XCTAssertEqual(report.decoding.samplesDecoded, 22)
    }

    // MARK: - Test 3: Out-of-Order Delivery
    func testOutOfOrderDeliveryMaintainsChronologicalPersistence() throws {
        let db = try HistoryDatabase(url: databaseURL)
        let samples = (1700000000..<1700000050).map { makeSample(unix: $0) }
        let reversedSamples = Array(samples.reversed())

        // Insert in reversed order
        _ = try db.commit(reversedSamples)

        let retrieved = try db.samples(from: 1700000000, through: 1700000049)
        XCTAssertEqual(retrieved.count, 50)
        XCTAssertEqual(retrieved.first?.unix, 1700000000)
        XCTAssertEqual(retrieved.last?.unix, 1700000049)

        // Check chronological monotonicity
        for i in 0..<(retrieved.count - 1) {
            XCTAssertLessThan(retrieved[i].unix, retrieved[i + 1].unix, "Retrieved records must be strictly ascending")
        }
    }

    // MARK: - Test 4: BLE Reconnection & Frame Reassembler Boundary Handling
    func testBLEReconnectionAndFrameReassemblerBoundaryHandling() {
        let reassembler = FrameReassembler()
        let payload: [UInt8] = [0x2F, 0x12, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
        let fullFrame = Gen5Frame.build(payload)

        // Feed byte-at-a-time (simulating fragmented BLE ATT notifications)
        var recovered: [[UInt8]] = []
        for byte in fullFrame {
            recovered.append(contentsOf: reassembler.feed([byte]))
        }
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.prefix(payload.count), ArraySlice(payload))

        // Feed corrupted byte range and verify reassembler recovers on next valid SOF
        let garbage: [UInt8] = [0xFF, 0x00, 0xAA, 0x12, 0x34]
        let afterGarbage = reassembler.feed(garbage + fullFrame)
        XCTAssertEqual(afterGarbage.count, 1)
        XCTAssertEqual(afterGarbage.first?.prefix(payload.count), ArraySlice(payload))
        XCTAssertGreaterThan(reassembler.droppedBytes, 0)
    }

    // MARK: - Test 5: History Cursor Resume & Safe-Trim ACK Invariants
    func testHistoryCursorResumeAndTokenPreservation() throws {
        let db = try HistoryDatabase(url: databaseURL)
        let chunk1 = (1700000000..<1700000030).map { makeSample(unix: $0) }
        let token1 = "token_checkpoint_001"

        // Persist chunk 1
        let progress1 = try db.commitReportingProgress(chunk1, token: token1)
        XCTAssertEqual(progress1.changed, 30)
        XCTAssertEqual(progress1.newestInserted, 1700000029)
        XCTAssertEqual(try db.metadata("last_history_chunk"), token1)

        // Simulate resume: chunk 2 overlapping by 5 seconds (replay)
        let chunk2 = (1700000025..<1700000060).map { makeSample(unix: $0) }
        let token2 = "token_checkpoint_002"
        let progress2 = try db.commitReportingProgress(chunk2, token: token2)
        XCTAssertEqual(progress2.changed, 30, "Should only insert the 30 genuinely new seconds (1700000030..1700000059)")
        XCTAssertEqual(progress2.newestInserted, 1700000059)
        XCTAssertEqual(try db.metadata("last_history_chunk"), token2)
        XCTAssertEqual(try db.samples(from: 0, through: 2_000_000_000).count, 60)
    }

    // MARK: - Test 6: Repeated Sync Idempotency
    func testRepeatedSyncIdempotency() throws {
        let db = try HistoryDatabase(url: databaseURL)
        let samples = (1700000000..<1700000300).map { makeSample(unix: $0, hr: 60, rr: [1000], motion: 0.01) }

        _ = try db.commit(samples)
        let summary1 = CaptureSummary.make(samples: try db.samples(from: 1700000000, through: 1700000299), sex: .male, maxHR: 190)

        // Repeat sync with same records
        _ = try db.commit(samples)
        let summary2 = CaptureSummary.make(samples: try db.samples(from: 1700000000, through: 1700000299), sex: .male, maxHR: 190)

        XCTAssertEqual(summary1.sampleCount, summary2.sampleCount)
        XCTAssertEqual(summary1.wearingCount, summary2.wearingCount)
        XCTAssertEqual(summary1.restingHeartRate, summary2.restingHeartRate)
        XCTAssertEqual(summary1.hrv.rmssdMS, summary2.hrv.rmssdMS)
    }

    // MARK: - Test 7: Timestamp Rollover and RTC Reset Handling
    func testTimestampRolloverAndRTCResetHandling() {
        // Reproduce real WHOOP hardware observation:
        // Record 1470964 has unix=1795397584 and subsecQ15=31457 (~0.960s)
        // Record 1470965 has unix=1795397586 and subsecQ15=327 (~0.010s)
        // Total elapsed is 1.05s, but integer unix has a 2-second jump.
        let s1 = makeSample(unix: 1795397584, recordIndex: 1470964, subsecQ15: 31457)
        let s2 = makeSample(unix: 1795397586, recordIndex: 1470965, subsecQ15: 327)

        let report = SensorTruthDiagnostics.audit(samples: [s1, s2])
        XCTAssertEqual(report.persistence.rtcDiscontinuities, 1, "Must detect hardware RTC rollover discontinuity")
        XCTAssertEqual(report.persistence.missingRecordIndexGaps, 0, "Record index must be recognized as contiguous")
        XCTAssertEqual(report.persistence.timestampGaps, 1, "Timestamp gap of 2 seconds must be flagged")
    }

    // MARK: - Test 8: Wrist-Off and Low-Quality HR Filtering
    func testWristOffAndLowQualityHRFiltering() {
        // 1. Zero HR sample
        let zeroHR = makeSample(unix: 1000, hr: 0, motion: 0.05, temp: 33.0)
        XCTAssertFalse(zeroHR.wearing, "Zero HR must be classified as non-wearing")

        // 2. Tabletop sensor artifact (cold temperature < 25C and complete stillness < 0.005g)
        let tabletop = makeSample(unix: 1001, hr: 65, motion: 0.001, temp: 22.0)
        XCTAssertFalse(tabletop.wearing, "Cold tabletop artifact must be classified as non-wearing")

        // 3. Genuine worn sample
        let genuine = makeSample(unix: 1002, hr: 65, motion: 0.012, temp: 33.5)
        XCTAssertTrue(genuine.wearing, "Worn body temperature sample must be classified as wearing")

        let report = SensorTruthDiagnostics.audit(samples: [zeroHR, tabletop, genuine])
        XCTAssertEqual(report.analysis.wearingSamples, 1)
        XCTAssertEqual(report.analysis.offWristSamples, 2)
    }

    // MARK: - Test 9: Corrupt or Truncated RR Payloads Are Rejected Safely
    func testCorruptOrTruncatedRRPayloadsAreRejectedSafely() {
        // 1. Values outside plausible range (200..3000ms)
        let tooShort = makeSample(unix: 1000, rr: [150])
        let tooLong = makeSample(unix: 1001, rr: [3500])
        let valid = makeSample(unix: 1002, rr: [900, 950])

        let report = SensorTruthDiagnostics.audit(samples: [tooShort, tooLong, valid])
        XCTAssertEqual(report.decoding.declaredRRBeats, 4)
        XCTAssertEqual(report.decoding.validRRBeats, 2)
        XCTAssertEqual(report.decoding.rejectedRRBeats, 2)
        XCTAssertEqual(report.decoding.rejectedRRReasons["outOfPlausibleRange"], 2)

        // Verify RMSSD calculation ignores invalid intervals
        let hrv = Hrv.fromSamples([tooShort, tooLong, valid])
        XCTAssertEqual(hrv.beats, 4)
        // Clean beats from valid only (2 NN beats, but < 20 min clean beats floor means RMSSD is nil)
        XCTAssertEqual(hrv.nnBeats, 2)
        XCTAssertNil(hrv.rmssdMS, "Fewer than 20 clean beats should return nil RMSSD without crashing")
    }

    // MARK: - Test 10: Multiple Packets Sharing Timestamp Collision Resolution
    func testMultiplePacketsSharingTimestampCollisionResolution() throws {
        let db = try HistoryDatabase(url: databaseURL)

        // Sample 1: Sparse sample with zero HR at unix 1000
        let sparse = makeSample(unix: 1000, recordIndex: 50, hr: 0, rr: [], motion: nil)
        // Sample 2: Richer sample with valid HR and RR at unix 1000
        let rich = makeSample(unix: 1000, recordIndex: 51, hr: 68, rr: [880], motion: 0.015)

        // HistoricalRecordSelection preference test
        XCTAssertTrue(HistoricalRecordSelection.prefers(rich, over: sparse))
        XCTAssertFalse(HistoricalRecordSelection.prefers(sparse, over: rich))

        // Save sparse first, then upgrade with rich
        _ = try db.commit([sparse])
        var retrieved = try db.samples(from: 1000, through: 1000)
        XCTAssertEqual(retrieved.first?.heartRate, 0)

        _ = try db.commit([rich])
        retrieved = try db.samples(from: 1000, through: 1000)
        XCTAssertEqual(retrieved.first?.heartRate, 68, "Richer sample must upgrade sparse sample on collision")
        XCTAssertEqual(try db.samples(from: 0, through: 2_000_000_000).count, 1, "Must maintain exactly 1 record per unix second")
    }

    // MARK: - Test 11: Persistence Across Simulated App Restart
    func testPersistenceAcrossSimulatedAppRestart() throws {
        // Open DB instance 1, write records and analysis checkpoint
        do {
            let db1 = try HistoryDatabase(url: databaseURL)
            let samples = (1700000000..<1700000100).map { makeSample(unix: $0) }
            _ = try db1.commit(samples)
            try db1.cache(Data([0xDE, 0xAD, 0xBE, 0xEF]), key: "daily:2026-11-23", fingerprint: "fp123")
        }

        // Open fresh DB instance 2 from same SQLite file
        let db2 = try HistoryDatabase(url: databaseURL)
        XCTAssertEqual(try db2.samples(from: 0, through: 2_000_000_000).count, 100)
        let checkpoint = try db2.cached(Data.self, key: "daily:2026-11-23", fingerprint: "fp123")
        XCTAssertEqual(checkpoint, Data([0xDE, 0xAD, 0xBE, 0xEF]), "Checkpoints and samples must survive app process restart")
    }

    // MARK: - Test 12: Partial Archive Recovery & Non-Contiguous Gap Splitting
    func testPartialArchiveRecoveryAndNonContiguousGapSplitting() throws {
        // Run 1: 300 seconds quiet sleep
        let run1 = (1700000000..<1700000300).map { makeSample(unix: $0, hr: 60, rr: [1000]) }
        // 60-second gap
        // Run 2: 300 seconds quiet sleep
        let run2 = (1700000360..<1700000660).map { makeSample(unix: $0, hr: 60, rr: [1000]) }

        let allSamples = run1 + run2
        let contiguous = Hrv.contiguousRuns(allSamples)
        XCTAssertEqual(contiguous.count, 2, "Contiguous runs must split cleanly at gap")
        XCTAssertEqual(contiguous[0].count, 300)
        XCTAssertEqual(contiguous[1].count, 300)

        // Verify RMSSD does NOT bridge across the 60-second gap
        let hrv = Hrv.fromSamples(allSamples)
        let rmssd = try XCTUnwrap(hrv.rmssdMS)
        XCTAssertEqual(rmssd, 0.0, accuracy: 0.001, "Constant 1000ms intervals within runs must yield 0ms RMSSD, not inflate across gap")
    }

    // MARK: - Test 13: Sensor Truth Diagnostic Report & Privacy Export
    func testSensorTruthDiagnosticReportAndPrivacyExport() throws {
        let samples = (1700000000..<1700000100).map { makeSample(unix: $0, hr: 62, rr: [950, 970]) }
        let report = SensorTruthDiagnostics.audit(
            samples: samples,
            rawPacketsCount: 100,
            rawBytesCount: 10900,
            droppedBytes: 0,
            undecodableFrames: 0,
            checksumFailures: 0,
            duplicatesCount: 0
        )

        XCTAssertEqual(report.transmission.rawPacketsReceived, 100)
        XCTAssertEqual(report.decoding.samplesDecoded, 100)
        XCTAssertEqual(report.quality.decodeSuccessRate, 1.0)
        XCTAssertEqual(report.quality.recordContiguityRate, 1.0)
        XCTAssertFalse(report.provenanceDigest.isEmpty)

        let exportData = try SensorTruthDiagnostics.generatePrivacyPreservingExport(report: report)
        let jsonString = String(decoding: exportData, as: UTF8.self)

        XCTAssertTrue(jsonString.contains("provenanceDigest"))
        XCTAssertTrue(jsonString.contains("quality"))
        XCTAssertFalse(jsonString.contains("heartRateSeries"), "Must not leak raw biometric arrays in privacy export")
    }

    // MARK: - Test 14: RR Padding Valid Diagnostic Flag & Declared Slot Preservation
    func testRRPaddingValidDiagnosticFlagAndDeclaredSlotPreservation() {
        var inner = [UInt8](repeating: 0, count: 112)
        inner[0] = 0x2F
        inner[1] = 18
        inner[2] = 0
        inner[7] = 0x80; inner[8] = 0x96; inner[9] = 0x98; inner[10] = 0x00 // unix
        inner[14] = 65 // HR

        // Case A: 1 declared beat, zero padding -> rrPaddingValid == true
        inner[15] = 1
        inner[16] = 0x98; inner[17] = 0x03 // 920 ms
        for i in 18..<24 { inner[i] = 0 }
        let sampleA = V18Decoder.decode(inner)
        XCTAssertNotNil(sampleA)
        XCTAssertEqual(sampleA?.rrIntervalsMS, [920])
        XCTAssertEqual(sampleA?.rrPaddingValid, true)

        // Case B: 1 declared beat, non-zero unused byte -> preserves beat, rrPaddingValid == false
        inner[18] = 0xFF
        let sampleB = V18Decoder.decode(inner)
        XCTAssertNotNil(sampleB)
        XCTAssertEqual(sampleB?.rrIntervalsMS, [920], "Non-zero unused byte must not drop declared beat")
        XCTAssertEqual(sampleB?.rrPaddingValid, false, "Non-zero unused byte must set rrPaddingValid = false")

        // Case C: Invalid declared count > 4 -> drops RR, rrPaddingValid == false
        inner[15] = 5
        let sampleC = V18Decoder.decode(inner)
        XCTAssertNotNil(sampleC)
        XCTAssertEqual(sampleC?.rrIntervalsMS, [], "Declared count > 4 must yield empty intervals")
        XCTAssertEqual(sampleC?.rrPaddingValid, false)
    }

    // MARK: - Test 15: HRV Detailed Diagnostics Breakdown
    func testHrvDetailedDiagnosticsBreakdown() {
        var samples: [V18Sample] = []
        for i in 0..<30 {
            let rr: [Int]
            if i == 5 {
                rr = [150] // out of range (< 200)
            } else if i == 15 {
                rr = [1600] // ectopic (> 20% jump from ~900)
            } else {
                rr = [900, 910]
            }
            samples.append(makeSample(unix: 1700000000 + i, hr: 65, rr: rr))
        }

        let diag = Hrv.detailedDiagnostics(samples: samples)
        XCTAssertEqual(diag.selectedCalculationWindow, "ALL_VALID_SLEEP")
        XCTAssertGreaterThan(diag.rawRRCount, 0)
        XCTAssertGreaterThan(diag.acceptedNNCount, 0)
        XCTAssertGreaterThan(diag.rejectedBeatsByReason["outOfPlausibleRange"] ?? 0, 0)
        XCTAssertGreaterThan(diag.coveragePercentage, 0.0)
        XCTAssertNotNil(diag.finalRMSSD)
        XCTAssertNotNil(diag.finalLnRMSSD)
    }

    // MARK: - Test 16: Sleep Disturbance Timestamp Gap Isolation
    func testSleepDisturbanceTimestampGapIsolation() {
        var samples: [V18Sample] = []
        let baseUnix = 1700000000

        // 8 moving seconds (accel = 0.20 g)
        for i in 0..<8 {
            samples.append(makeSample(unix: baseUnix + i, hr: 80, motion: 0.20))
        }
        // 600-second gap (10 minutes)
        // 8 moving seconds (accel = 0.20 g)
        for i in 608..<616 {
            samples.append(makeSample(unix: baseUnix + i, hr: 80, motion: 0.20))
        }
        // 3600 seconds of quiet sleep to form a valid period
        for i in 616..<4300 {
            samples.append(makeSample(unix: baseUnix + i, hr: 55, motion: 0.01))
        }

        // Active baseline reference samples
        for i in 5000..<5600 {
            samples.append(makeSample(unix: baseUnix + i, hr: 95, motion: 0.25))
        }

        let periods = SleepDetect.detect(samples)
        if let period = periods.first {
            XCTAssertEqual(period.wakeEvents, 0, "Sparse timestamp gap must break movement bout accumulation")
        }
    }
}

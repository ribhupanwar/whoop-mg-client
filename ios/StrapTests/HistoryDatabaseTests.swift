import Foundation
import SQLite3
import XCTest
@testable import Strap

private func historySample(_ unix: Int, hr: Int = 60, rr: [Int] = [900], temp: Double? = 33,
                           motion: Double? = 0.01) -> V18Sample {
    V18Sample(
        header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
        heartRate: hr, rrIntervalsMS: rr, dynamicAccelG: motion,
        gravityXG: 0, gravityYG: 0, gravityZG: 1,
        stepCounter: 10, stepCadence: nil, activityClass: 0,
        skinTempC: temp, tempAux1C: nil, tempAux2C: nil,
        sleepStateByte: nil, sleepState: 2, cardiacFlags: nil, hrQualityFlags: 5,
        spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
        signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
    )
}

final class HistoryDatabaseTests: XCTestCase {
    func testNightTemperatureRequiresMeasuredCoverageAndDoesNotCountReplays() {
        let rows = (1000..<1300).map { historySample($0) }
        let session = SleepSession.make(samples: rows, period: SleepPeriod(startUnix: 1000, endUnix: 1299,
            quietFraction: 1, meanHR: 60, wakeEvents: 0))
        let measurement = NightTemperature.measure(rows + rows + [historySample(999, temp: 40)], session: session)
        XCTAssertEqual(measurement.seconds, 300)
        XCTAssertEqual(measurement.celsius, 33)
        XCTAssertNil(NightTemperature.measure(Array(rows.dropLast()), session: session).celsius)
        let bad = (1000..<1300).map { historySample($0, temp: .nan, motion: nil) }
        XCTAssertNil(NightTemperature.measure(bad, session: session).celsius)
        let negativeMotion = (1000..<1300).map { historySample($0, motion: -0.01) }
        XCTAssertNil(NightTemperature.measure(negativeMotion, session: session).celsius)
        XCTAssertEqual(NightTemperature.measure(bad, session: session).seconds, 0)
    }
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("history.sqlite") }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testLegacyMigrationIsLosslessAndDoesNotRepeatAfterReopen() throws {
        let legacy = directory.appendingPathComponent("history.json")
        let rows = [historySample(1000, rr: [900, 900]), historySample(999)]
        let original = try JSONEncoder().encode(rows)
        try original.write(to: legacy)
        do {
            let database = try HistoryDatabase(url: url)
            try database.migrateLegacyJSON(at: legacy)
            XCTAssertEqual(try database.samples(from: 0, through: 2000), Array(rows.reversed()))
            XCTAssertEqual(try database.commit([historySample(1001)], token: "chunk-a"), 1)
        }
        let reopened = try HistoryDatabase(url: url)
        try reopened.migrateLegacyJSON(at: legacy)
        XCTAssertEqual(try reopened.samples(from: 0, through: 2000).count, 3)
        XCTAssertEqual(try reopened.metadata("last_history_chunk"), "chunk-a")
        XCTAssertEqual(try Data(contentsOf: legacy), original, "Keep the old file for recovery")
    }

    func testRawHistorySurvivesBeyondBoundedAnalysisWindow() throws {
        let database = try HistoryDatabase(url: url)
        let rows = [historySample(1000), historySample(1000 + 10 * 86400)]
        try database.commit(rows)
        XCTAssertEqual(try database.recentSamples(), [rows[1]])
        XCTAssertEqual(try database.samples(from: 0, through: 1000), [rows[0]])
        let reopened = try HistoryDatabase(url: url)
        XCTAssertEqual(try reopened.samples(from: 0, through: 2_000_000), rows)
    }

    func testReplayedChunksAreIdempotentAndKeepBetterPackets() throws {
        let database = try HistoryDatabase(url: url)
        let original = historySample(1000)
        let invalid = historySample(1000, hr: 0, rr: [800, 900, 1000])
        let richer = historySample(1000, rr: [900, 910])
        XCTAssertEqual(try database.commit([original], token: "a"), 1)
        XCTAssertEqual(try database.commit([original, invalid], token: "a"), 0)
        XCTAssertEqual(try database.commit([richer], token: "b"), 1)
        XCTAssertEqual(try database.commit([original, richer], token: "b"), 0)
        XCTAssertEqual(try database.recentSamples(), [richer])
    }

    func testPersistedContinuationFrontierIgnoresDuplicatesAndRowUpgrades() throws {
        let database = try HistoryDatabase(url: url)
        let first = historySample(1_000)
        XCTAssertEqual(try database.commitReportingProgress([first], token: "first").newestInserted, 1_000)
        XCTAssertNil(try database.commitReportingProgress([first], token: "replay").newestInserted)
        let upgrade = try database.commitReportingProgress([historySample(1_000, rr: [900, 920])], token: "upgrade")
        XCTAssertEqual(upgrade.changed, 1)
        XCTAssertNil(upgrade.newestInserted)
        let tail = try database.commitReportingProgress([first, historySample(1_100)], token: "tail")
        XCTAssertEqual(tail.newestInserted, 1_100)
        XCTAssertEqual(try database.metadata("last_history_chunk"), "tail")
    }

    func testFailedChunkRollsBackRowsAndCursorTogether() throws {
        let database = try HistoryDatabase(url: url)
        var probe: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &probe), SQLITE_OK)
        defer { sqlite3_close(probe) }
        let sql = "CREATE TRIGGER reject_fixture BEFORE INSERT ON history_sample WHEN NEW.unix=1001 BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END"
        XCTAssertEqual(sqlite3_exec(probe, sql, nil, nil, nil), SQLITE_OK)
        let rows = [historySample(1000), historySample(1001)]
        XCTAssertThrowsError(try database.commit(rows, token: "not-durable"))
        XCTAssertTrue(try database.recentSamples().isEmpty)
        XCTAssertNil(try database.metadata("last_history_chunk"))
        XCTAssertEqual(sqlite3_exec(probe, "DROP TRIGGER reject_fixture", nil, nil, nil), SQLITE_OK)
        try database.commit(rows, token: "durable")
        XCTAssertEqual(try database.recentSamples(), rows)
        XCTAssertEqual(try database.metadata("last_history_chunk"), "durable")
    }

    func testFragmentedHistoryReplayReopensAndCompletesFourDailyMetrics() throws {
        let start = 1_800_000_000
        let dates = (0..<4).map { start + $0 * 86_400 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func replay(day: Int) -> [V18Sample] {
            let decoder = FrameReassembler()
            return (0..<360).flatMap { offset -> [V18Sample] in
                let unix = UInt32(dates[day] + offset)
                var inner = [UInt8](repeating: 0, count: 112)
                inner[0] = 0x2F
                inner[1] = 18
                for byte in 0..<4 {
                    // The record index starts over on each simulated transfer.
                    inner[3 + byte] = UInt8(truncatingIfNeeded: offset >> (8 * byte))
                    inner[7 + byte] = UInt8(truncatingIfNeeded: unix >> (8 * byte))
                }
                inner[14] = 60
                let frame = Gen5Frame.build(inner)
                let prefix = decoder.feed(Array(frame.prefix(19)))
                return (prefix + decoder.feed(Array(frame.dropFirst(19)))).compactMap(V18Decoder.decode)
            }
        }

        let cache = try HistoryAnalysisCache(url: url)
        do {
            let database = try HistoryDatabase(url: url)
            for day in [1, 0] {
                XCTAssertEqual(try database.commit(replay(day: day), token: "first-\(day)"), 360)
            }
            _ = DailyAnalysis.metrics(from: try database.samples(from: start, through: dates[3] + 359),
                                      sex: .male, maxHR: 190, calendar: calendar,
                                      analyzedSleepSessions: [], analysisCache: cache)
        }

        let reopened = try HistoryDatabase(url: url)
        XCTAssertEqual(try reopened.metadata("last_history_chunk"), "first-0")
        XCTAssertEqual(try reopened.commit(replay(day: 1), token: "replay-1"), 0)
        for day in [3, 2] {
            XCTAssertEqual(try reopened.commit(replay(day: day), token: "second-\(day)"), 360)
        }
        let rows = try reopened.samples(from: start, through: dates[3] + 359)
        XCTAssertEqual(rows.count, 1_440)

        var progress: [Int] = []
        var reuse: [Bool] = []
        let cancelled = DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 190, calendar: calendar,
                                              analyzedSleepSessions: [], analysisCache: cache,
                                              shouldContinue: { progress.count < 3 }) {
            completed, _, reused in
            progress.append(completed)
            reuse.append(reused)
        }
        XCTAssertEqual(cancelled.count, 3)
        XCTAssertEqual(progress, [1, 2, 3])
        XCTAssertEqual(reuse, [true, true, false])
        progress = []
        reuse = []
        let result = DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 190, calendar: calendar,
                                           analyzedSleepSessions: [], analysisCache: cache) {
            completed, total, reused in
            XCTAssertEqual(total, 4)
            progress.append(completed)
            reuse.append(reused)
        }
        XCTAssertEqual(progress, [1, 2, 3, 4])
        XCTAssertEqual(reuse, [true, true, true, false])
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(try reopened.commit(replay(day: 3), token: "replay-3"), 0)
        XCTAssertEqual(DailyAnalysis.metrics(
            from: try reopened.samples(from: start, through: dates[3] + 359),
            sex: .male, maxHR: 190, calendar: calendar, analyzedSleepSessions: [], analysisCache: cache
        ), result)
    }

    func testAnalysisResumesCompletedNightAndInvalidatesChangedInput() throws {
        let start = 1_800_000_000
        let period = SleepPeriod(startUnix: start, endUnix: start + 3599,
                                 quietFraction: 0.9, meanHR: 60, wakeEvents: 0)
        let rows = (start..<(start + 3600)).map { historySample($0) }
        let first: SleepSession
        do {
            let cache = try HistoryAnalysisCache(url: url)
            let result = cache.night(samples: rows, period: period, correctedTimes: nil)
            XCTAssertFalse(result.1)
            first = result.0
        }
        let resumed = try HistoryAnalysisCache(url: url)
        let repeated = resumed.night(samples: rows, period: period, correctedTimes: nil)
        XCTAssertTrue(repeated.1)
        XCTAssertEqual(repeated.0, first)
        var corrected = rows
        corrected[30] = historySample(start + 30, hr: 70, rr: [900, 910])
        XCTAssertFalse(resumed.night(samples: corrected, period: period, correctedTimes: nil).1)
        let times = [start + 60, start + 3500]
        let edited = resumed.night(samples: corrected, period: period, correctedTimes: times)
        XCTAssertFalse(edited.1)
        XCTAssertEqual(edited.0.startUnix, times[0])
        XCTAssertEqual(edited.0.endUnix, times[1])
        XCTAssertTrue(resumed.night(samples: corrected, period: period, correctedTimes: times).1)
    }

    func testDailyCheckpointReusesWorkAndInvalidatesSettingsAndLateData() throws {
        let start = 1_800_000_000
        let rows = (start..<(start + 600)).map { historySample($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cache = try HistoryAnalysisCache(url: url)
        var reuse: [Bool] = []
        let first = DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 190,
                                          calendar: calendar, analyzedSleepSessions: [], analysisCache: cache) {
            _, _, reused in reuse.append(reused)
        }
        XCTAssertEqual(reuse, [false])
        reuse = []
        let resumed = try HistoryAnalysisCache(url: url)
        let second = DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 190,
                                           calendar: calendar, analyzedSleepSessions: [], analysisCache: resumed) {
            _, _, reused in reuse.append(reused)
        }
        XCTAssertEqual(second, first)
        XCTAssertEqual(reuse, [true])
        reuse = []
        _ = DailyAnalysis.metrics(from: rows, sex: .female, maxHR: 190,
                                  calendar: calendar, analyzedSleepSessions: [], analysisCache: resumed) {
            _, _, reused in reuse.append(reused)
        }
        XCTAssertEqual(reuse, [false])
        reuse = []
        _ = DailyAnalysis.metrics(from: rows + [historySample(start + 601)], sex: .female, maxHR: 190,
                                  calendar: calendar, analyzedSleepSessions: [], analysisCache: resumed) {
            _, _, reused in reuse.append(reused)
        }
        XCTAssertEqual(reuse, [false])
    }

    func testDailyRHRRecipeDoesNotReusePreMedianCheckpoint() throws {
        let cache = try HistoryAnalysisCache(url: url)
        let date = "2026-11-21"
        let old = try XCTUnwrap(cache.ticket(key: "day:\(date)", samples: [], context: date))
        let new = try XCTUnwrap(cache.ticket(key: HistoryAnalysisCache.dailyKey(date), samples: [], context: date))
        XCTAssertEqual(old.fingerprint, new.fingerprint)
        cache.save([59.0], ticket: old)
        XCTAssertNil(cache.load([Double].self, ticket: new))
        cache.save([67.0], ticket: new)
        let reopened = try HistoryAnalysisCache(url: url)
        XCTAssertEqual(reopened.load([Double].self, ticket: new), [67.0])
        XCTAssertEqual(reopened.load([Double].self, ticket: old), [59.0])
    }

    func testAnalysisCacheRequiresMatchingFingerprint() throws {
        let database = try HistoryDatabase(url: url)
        try database.cache([1, 2, 3], key: "test", fingerprint: "input-a")
        XCTAssertEqual(try database.cached([Int].self, key: "test", fingerprint: "input-a"), [1, 2, 3])
        XCTAssertNil(try database.cached([Int].self, key: "test", fingerprint: "input-b"))
    }

    func testNightEndingTodayIncludesPreviousDaysPacketsInDailyFingerprint() throws {
        let midnight = (1_800_000_000 / 86400) * 86400
        let rows = ((midnight - 300)..<(midnight + 300)).map { historySample($0) }
        let period = SleepPeriod(startUnix: midnight - 300, endUnix: midnight + 299,
                                 quietFraction: 1, meanHR: 60, wakeEvents: 0)
        let session = SleepSession.make(samples: rows, period: period)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cache = try HistoryAnalysisCache(url: url)
        _ = DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 190,
                                  calendar: calendar, analyzedSleepSessions: [session], analysisCache: cache)
        var changed = rows
        changed[0] = historySample(midnight - 300, hr: 70, rr: [850, 900])
        var reuse: [Bool] = []
        _ = DailyAnalysis.metrics(from: changed, sex: .male, maxHR: 190,
                                  calendar: calendar, analyzedSleepSessions: [session], analysisCache: cache) {
            _, _, reused in reuse.append(reused)
        }
        XCTAssertEqual(reuse, [false, false], "Today's overnight HRV depends on yesterday's part of the night")
    }

    func testChunkWriterCommitsBeforeCompletionAndSurvivesReopen() throws {
        let writer = HistoricalArchiveWriter(url: directory.appendingPathComponent("old.json"))
        let done = expectation(description: "Chunk is durable before an ACK can be sent")
        writer.persistChunk([historySample(1000)], token: "first") { result in
            do {
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(try result.get(), 1)
                let reopened = try HistoryDatabase(url: writer.databaseURL)
                XCTAssertEqual(try reopened.metadata("last_history_chunk"), "first")
                XCTAssertEqual(try reopened.recentSamples(), [historySample(1000)])
                writer.persistChunk([historySample(1000), historySample(1001)], token: "second") { result in
                    do {
                        XCTAssertEqual(try result.get(), 1)
                        let database = try HistoryDatabase(url: writer.databaseURL)
                        XCTAssertEqual(try database.metadata("last_history_chunk"), "second")
                        XCTAssertEqual(try database.recentSamples().count, 2)
                    } catch { XCTFail("Second chunk was not durable: \(error)") }
                    done.fulfill()
                }
            } catch { XCTFail("First chunk was not durable: \(error)"); done.fulfill() }
        }
        wait(for: [done], timeout: 10)
    }

    func testInterruptedOffloadResumesWithReplayAndFillsMissingSecond() throws {
        let url = directory.appendingPathComponent("old.json")

        func persist(_ rows: [V18Sample], token: String, using writer: HistoricalArchiveWriter) throws -> Int {
            let done = expectation(description: "History chunk \(token) committed")
            var outcome: Result<Int, Error>?
            writer.persistChunk(rows, token: token) { result in
                outcome = result
                done.fulfill()
            }
            wait(for: [done], timeout: 10)
            return try XCTUnwrap(outcome).get()
        }

        let first = historySample(1000)
        let missing = historySample(1001)
        let later = historySample(1002)
        do {
            let writer = HistoricalArchiveWriter(url: url)
            XCTAssertEqual(try persist([first, later], token: "before-disconnect", using: writer), 2)
        }

        // A reconnect can replay already committed rows along with missing data.
        let resumed = HistoricalArchiveWriter(url: url)
        let database = try HistoryDatabase(url: resumed.databaseURL)
        XCTAssertEqual(try database.metadata("last_history_chunk"), "before-disconnect")
        XCTAssertEqual(try persist([first, missing, later, later], token: "after-reconnect", using: resumed), 1)
        XCTAssertEqual(try database.recentSamples(), [first, missing, later])
        XCTAssertEqual(try database.metadata("last_history_chunk"), "after-reconnect")
    }

    func testFailedWriterRetainsPendingRowsForRetry() throws {
        let writer = HistoricalArchiveWriter(url: directory.appendingPathComponent("old.json"))
        // A directory at the database path makes sqlite_open fail without
        // depending on platform-specific file permissions or disk exhaustion.
        try FileManager.default.createDirectory(at: writer.databaseURL, withIntermediateDirectories: true)
        let done = expectation(description: "Failed write can be retried without another BLE drain")
        writer.persistChunk([historySample(1000)], token: "failed") { result in
            if case .success = result { XCTFail("Fixture must fail the initial write") }
            do {
                try FileManager.default.removeItem(at: writer.databaseURL)
                writer.merge([]) { result in
                    switch result {
                    case .success(let rows):
                        XCTAssertEqual(rows, [historySample(1000)])
                    case .failure(let error):
                        XCTFail("Retry lost pending rows: \(error)")
                    }
                    done.fulfill()
                }
            } catch { XCTFail("Could not repair test path: \(error)"); done.fulfill() }
        }
        wait(for: [done], timeout: 10)
    }

    func testFailedTransactionRetriesAllPendingChunksWithoutAdvancingCursor() throws {
        let writer = HistoricalArchiveWriter(url: directory.appendingPathComponent("old.json"))
        func commit(_ rows: [V18Sample], token: String) throws -> Int {
            let done = expectation(description: "durable chunk completion")
            var outcome: Result<Int, Error>?
            writer.persistChunk(rows, token: token) { outcome = $0; done.fulfill() }
            wait(for: [done], timeout: 20)
            return try XCTUnwrap(outcome).get()
        }
        XCTAssertEqual(try commit([historySample(1000)], token: "initial"), 1)
        var probe: OpaquePointer?
        XCTAssertEqual(sqlite3_open(writer.databaseURL.path, &probe), SQLITE_OK)
        defer { sqlite3_close(probe) }
        let sql = "CREATE TRIGGER reject_retry BEFORE INSERT ON history_sample WHEN NEW.unix=1001 BEGIN SELECT RAISE(ABORT, 'fixture transaction failure'); END"
        XCTAssertEqual(sqlite3_exec(probe, sql, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try commit([historySample(1001)], token: "failed-a"))
        XCTAssertThrowsError(try commit([historySample(1002)], token: "failed-b"))
        let stored = try HistoryDatabase(url: writer.databaseURL)
        XCTAssertEqual(try stored.metadata("last_history_chunk"), "initial")
        XCTAssertEqual(try stored.recentSamples(), [historySample(1000)])
        XCTAssertEqual(sqlite3_exec(probe, "DROP TRIGGER reject_retry", nil, nil, nil), SQLITE_OK)
        let retried = expectation(description: "empty retry recovers every pending chunk")
        writer.merge([]) { result in
            do {
                let rows = try result.get()
                XCTAssertEqual(rows, [historySample(1000), historySample(1001), historySample(1002)])
            } catch { XCTFail("Retry failed: \(error)") }
            retried.fulfill()
        }
        wait(for: [retried], timeout: 20)
        XCTAssertEqual(try commit([historySample(1001), historySample(1002)], token: "replayed"), 0)
        XCTAssertEqual(try stored.metadata("last_history_chunk"), "replayed")
    }
}

extension HistoryDatabaseTests {
    func testInvalidLegacyFileDoesNotMarkMigrationCompleteAndCanBeRetried() throws {
        let legacy = directory.appendingPathComponent("history.json")
        let damaged = Data("{interrupted-json".utf8)
        try damaged.write(to: legacy)
        do {
            let database = try HistoryDatabase(url: url)
            try database.migrateLegacyJSON(at: legacy)
            XCTAssertNil(try database.metadata("legacy_json_imported"))
            XCTAssertEqual(try Data(contentsOf: legacy), damaged)
            try database.commit([historySample(2000)])
        }
        let repaired = [historySample(1000)]
        try JSONEncoder().encode(repaired).write(to: legacy)
        let reopened = try HistoryDatabase(url: url)
        try reopened.migrateLegacyJSON(at: legacy)
        XCTAssertEqual(try reopened.samples(from: 0, through: 3000), repaired + [historySample(2000)])
        XCTAssertEqual(try reopened.metadata("legacy_json_imported"), "1")
    }
}


extension HistoryDatabaseTests {
    func testRawSensorAndLiveRRRestoreShareOneRollbackBoundary() throws {
        let database = try HistoryDatabase(url: url)
        let original = historySample(1000)
        try database.commit([original])
        let rr = LiveRRRecord(id: "rollback-fixture", source: "synthetic", receivedAtUnix: 1001.25,
            sample: LiveSample(unix: 1001, heartRate: 60, rrIntervalsMS: [1000]))
        enum Injected: Error { case unavailableDisk }
        XCTAssertThrowsError(try database.restoreMissing(token: "combined-failure",
            stream: { accept in try accept([historySample(1001)]) },
            liveRRStream: { accept in try accept([rr]) }, accompanyingWrites: { throw Injected.unavailableDisk }))
        XCTAssertEqual(try database.samples(from: 0, through: 2000), [original])
        XCTAssertEqual(try database.liveRRCount(), 0)
        XCTAssertNil(try database.metadata("restore:combined-failure"))
    }
}

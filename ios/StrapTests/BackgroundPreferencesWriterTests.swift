import XCTest
@testable import Strap

final class BackgroundPreferencesWriterTests: XCTestCase {
    private struct WorkerOnly: Encodable {
        let value: Int
        func encode(to encoder: Encoder) throws {
            XCTAssertFalse(Thread.isMainThread, "Snapshot encoding must never block a tab tap")
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }
    func testEncodingRunsOffMainAndLatestSnapshotWins() throws {
        let name = "SnapshotWriterTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let writer = BackgroundPreferencesWriter(defaults: defaults)
        for value in 0..<100 { writer.write(WorkerOnly(value: value), forKey: "snapshot") }
        let done = expectation(description: "All ordered snapshots saved")
        writer.flush {
            XCTAssertTrue(Thread.isMainThread)
            do {
                let data = try XCTUnwrap(defaults.data(forKey: "snapshot"))
                XCTAssertEqual(try JSONDecoder().decode(Int.self, from: data), 99)
            } catch { XCTFail("Invalid snapshot: \(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }
    func testRemovalCannotBeUndoneByAnOlderQueuedWrite() throws {
        let name = "SnapshotWriterTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let writer = BackgroundPreferencesWriter(defaults: defaults)
        writer.write(WorkerOnly(value: 1), forKey: "snapshot")
        writer.remove(forKey: "snapshot")
        let done = expectation(description: "Removal follows pending write")
        writer.flush { XCTAssertNil(defaults.data(forKey: "snapshot")); done.fulfill() }
        wait(for: [done], timeout: 10)
    }
}

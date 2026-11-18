import XCTest
@testable import Strap

final class GPSRunHistoryTests: XCTestCase {
    func testPersistsDistanceSplitsRouteAndDeletion() {
        let suite = "gps-run-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = GPSRunHistory(defaults: defaults)
        let run = GPSRunRecord(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 2800),
            movingSeconds: 1800, distanceMeters: 5000,
            splitSeconds: [360, 355, 365, 360, 360],
            route: [GPSRunPoint(latitude: 28.5, longitude: 77.2,
                                unix: 1000, accuracyMeters: 8)]
        )
        history.save(run)
        XCTAssertEqual(GPSRunHistory(defaults: defaults).all(), [run])
        XCTAssertEqual(history.all().first?.paceSecondsPerKM, 360)
        history.save(run)
        XCTAssertEqual(history.all().count, 1)
        history.delete(id: run.id)
        XCTAssertTrue(history.all().isEmpty)
    }

    func testUnreadableCurrentArchiveIsNeverOverwrittenByLegacyOrNewWrites() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let suite = "gps-corrupt-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = GPSRunHistory(defaults: defaults, directory: root)
        let run = GPSRunRecord(id: UUID(), startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 1100), movingSeconds: 100,
            distanceMeters: 200, splitSeconds: [], route: [])
        defaults.set(try JSONEncoder().encode([run]), forKey: "strap.gps.runs.v1")
        let archive = root.appendingPathComponent("Strap/gps-runs-v2.json")
        try fm.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = Data("invalid-current-archive".utf8)
        try damaged.write(to: archive)
        XCTAssertTrue(history.all().isEmpty)
        XCTAssertFalse(history.save(run))
        XCTAssertFalse(history.delete(id: run.id))
        XCTAssertEqual(try Data(contentsOf: archive), damaged)
        XCTAssertNotNil(defaults.data(forKey: "strap.gps.runs.v1"))
    }

    func testShortOrZeroDistanceHasNoPace() {
        let run = GPSRunRecord(id: UUID(), startedAt: Date(), endedAt: Date(),
                               movingSeconds: 100, distanceMeters: 0,
                               splitSeconds: [], route: [])
        XCTAssertNil(run.paceSecondsPerKM)
    }
}

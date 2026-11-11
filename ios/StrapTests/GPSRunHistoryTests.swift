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

    func testShortOrZeroDistanceHasNoPace() {
        let run = GPSRunRecord(id: UUID(), startedAt: Date(), endedAt: Date(),
                               movingSeconds: 100, distanceMeters: 0,
                               splitSeconds: [], route: [])
        XCTAssertNil(run.paceSecondsPerKM)
    }
}

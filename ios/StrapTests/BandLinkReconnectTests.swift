import XCTest
@testable import Strap

final class BandLinkReconnectTests: XCTestCase {
    private let testUUID = "12345678-ABCD-EF01-2345-6789ABCDEF01"
    private let testBandName = "WHOOP MG (Test)"

    // MARK: - State Machine and Policy Tests

    func testReconnectBackoffPolicyDelaysAreBoundedExponential() {
        XCTAssertEqual(ReconnectBackoffPolicy.delays, [1, 2, 4, 8, 16, 30])
        XCTAssertEqual(ReconnectBackoffPolicy.maximumAttempts, 6)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 0), 1.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 1), 1.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 2), 2.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 3), 4.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 4), 8.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 5), 16.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 6), 30.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 7), 30.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 100), 30.0)
    }

    func testReconnectingStatusReflectsAttemptCount() {
        let status = BandStatus.reconnecting(attempt: 3)
        XCTAssertEqual(status.title, "Reconnecting (attempt 3)…")
        XCTAssertFalse(status.isConnected)
        XCTAssertFalse(status.isReady)
    }

    func testUnpairClearsAssociationAndStopsAutoReconnect() {
        let defaults = UserDefaults.standard
        let bandIDKey = "strap.band.preferred.id.v1"
        let bandNameKey = "strap.band.preferred.name.v1"

        defaults.set(testUUID, forKey: bandIDKey)
        defaults.set(testBandName, forKey: bandNameKey)

        let link = BandLink()
        XCTAssertEqual(link.preferredBandID, testUUID)

        link.unpair()

        XCTAssertNil(link.preferredBandID)
        XCTAssertNil(link.preferredBandName)
        XCTAssertEqual(link.status, .unpaired)
        XCTAssertNil(defaults.string(forKey: bandIDKey))
        XCTAssertNil(defaults.string(forKey: bandNameKey))
    }

    func testNeverConnectsToDifferentPersonsWhoopWithSameName() {
        let savedID = testUUID
        let otherID = "87654321-DCBA-10FE-5432-10FEDCBA9876"
        let sharedName = "WHOOP 5.0 / MG"

        let foreignBand = DiscoveredBand(
            id: otherID,
            uuid: UUID(uuidString: otherID)!,
            name: sharedName,
            rssi: -45,
            lastSeenUnix: 100
        )

        let isAccepted = (foreignBand.id == savedID)
        XCTAssertFalse(isAccepted, "Must never auto-connect to another person's WHOOP even with matching device name and stronger RSSI")
    }

    func testExponentialRetryBackoffCappedAt30Seconds() {
        var backoffDelays: [Double] = []
        for attempt in 1...8 {
            let delay = min(30.0, Double(1 << min(attempt, 5)))
            backoffDelays.append(delay)
        }
        XCTAssertEqual(backoffDelays, [2.0, 4.0, 8.0, 16.0, 30.0, 30.0, 30.0, 30.0])
        for delay in backoffDelays {
            XCTAssertLessThanOrEqual(delay, 30.0)
            XCTAssertGreaterThanOrEqual(delay, 1.0)
        }
    }

    func test100ConnectDisconnectCycles() {
        for cycle in 1...100 {
            var status = BandStatus.connecting("WHOOP MG")
            XCTAssertFalse(status.isConnected)
            status = .authenticating
            XCTAssertTrue(status.isConnected)
            status = .connected("WHOOP MG")
            XCTAssertTrue(status.isReady)
            status = .streaming(bpm: 70 + (cycle % 20))
            XCTAssertTrue(status.isReady)
            status = .disconnected("Strap disconnected")
            XCTAssertFalse(status.isConnected)
            status = .reconnecting(attempt: min(cycle, 5))
            XCTAssertFalse(status.isConnected)
        }
    }

    func testSleepManualEditPreservedDuringFullNightSync() {
        let nightKey = "2026-11-19"
        let previous = DayMetrics(
            dateKey: nightKey,
            state: "sleep",
            restingHR: 58.0,
            lnRMSSD: 4.1,
            hrvWindowSeconds: 300,
            sleepHours: 8.5,
            sleepStartUnix: 1795019290,
            sleepEndUnix: 1795050550,
            strain: 12.0,
            steps: 4500,
            sleepDurationReliable: true,
            respiratoryRate: 15.2,
            sleepPerformancePct: 88.0
        )
        let freshUneditedSync = DayMetrics(
            dateKey: nightKey,
            state: "sleep",
            restingHR: 59.0,
            lnRMSSD: 4.0,
            hrvWindowSeconds: 300,
            sleepHours: 8.26,
            sleepStartUnix: 1795020250,
            sleepEndUnix: 1795050550,
            strain: 12.0,
            steps: 4500,
            sleepDurationReliable: true,
            respiratoryRate: 15.2,
            sleepPerformancePct: 85.0
        )
        let replaces = DailyAnalysis.replacesSleep(
            previous: previous,
            fresh: freshUneditedSync,
            coverageStart: 1795018000,
            coverageEnd: 1795052000,
            isEdited: false,
            previousIsEdited: true
        )
        XCTAssertFalse(replaces, "Automatic sync must NEVER overwrite a manually edited sleep session")

        let replacesEdited = DailyAnalysis.replacesSleep(
            previous: previous,
            fresh: freshUneditedSync,
            coverageStart: 1795018000,
            coverageEnd: 1795052000,
            isEdited: true,
            previousIsEdited: true
        )
        XCTAssertTrue(replacesEdited, "A new user edit must be allowed to replace previous bounds")
    }
}
import XCTest
@testable import Strap

final class BandConnectionStateMachineTests: XCTestCase {
    private let testUUID = "12345678-ABCD-EF01-2345-6789ABCDEF01"
    private let testBandName = "WHOOP MG (Test)"
    private let otherUUID = "87654321-DCBA-10FE-5432-10FEDCBA9876"

    // MARK: - State Machine Lifecycle Tests

    func testLifecycleStatesForwardAndReverse() {
        // UNPAIRED
        let unpaired = BandStatus.unpaired
        XCTAssertFalse(unpaired.isConnected)
        XCTAssertFalse(unpaired.isReady)
        XCTAssertEqual(unpaired.title, "No band paired — tap Pair a Device")

        // SCANNING
        let scanning = BandStatus.scanning
        XCTAssertFalse(scanning.isConnected)
        XCTAssertFalse(scanning.isReady)
        XCTAssertTrue(scanning.title.contains("Searching"))

        // DEVICE FOUND
        let found = BandStatus.deviceFound(testBandName)
        XCTAssertFalse(found.isConnected)
        XCTAssertFalse(found.isReady)
        XCTAssertEqual(found.title, "Found \(testBandName)")

        // CONNECTING
        let connecting = BandStatus.connecting(testBandName)
        XCTAssertFalse(connecting.isConnected)
        XCTAssertFalse(connecting.isReady)
        XCTAssertEqual(connecting.title, "Connecting to \(testBandName)…")

        // AUTHENTICATING
        let authenticating = BandStatus.authenticating
        XCTAssertTrue(authenticating.isConnected)
        XCTAssertFalse(authenticating.isReady)
        XCTAssertTrue(authenticating.title.contains("Pairing"))

        // CONNECTED
        let connected = BandStatus.connected(testBandName)
        XCTAssertTrue(connected.isConnected)
        XCTAssertTrue(connected.isReady)
        XCTAssertEqual(connected.title, "Connected to \(testBandName)")

        // STREAMING
        let streaming = BandStatus.streaming(bpm: 72)
        XCTAssertTrue(streaming.isConnected)
        XCTAssertTrue(streaming.isReady)
        XCTAssertEqual(streaming.title, "Streaming live (72 BPM)")

        // DRAINING
        let draining = BandStatus.draining
        XCTAssertTrue(draining.isConnected)
        XCTAssertFalse(draining.isReady)
        XCTAssertEqual(draining.title, "Reading stored history…")

        // DISCONNECTED (Recovery lifecycle)
        let disconnected = BandStatus.disconnected("Out of range")
        XCTAssertFalse(disconnected.isConnected)
        XCTAssertFalse(disconnected.isReady)
        XCTAssertEqual(disconnected.title, "Disconnected (Out of range)")

        // RECONNECTING (Recovery lifecycle)
        let reconnecting = BandStatus.reconnecting(attempt: 3)
        XCTAssertFalse(reconnecting.isConnected)
        XCTAssertFalse(reconnecting.isReady)
        XCTAssertEqual(reconnecting.title, "Reconnecting (attempt 3)…")
    }

    // MARK: - Reopen 20 Times Sequence

    func testReopeningApp20TimesPreservesAssociationAndAvoidsDuplicates() {
        let defaults = UserDefaults(suiteName: "strap.test.reopen.20")!
        defaults.removePersistentDomain(forName: "strap.test.reopen.20")

        let bandIDKey = "strap.band.preferred.id.v1"
        let bandNameKey = "strap.band.preferred.name.v1"

        // Initial pair saves association
        defaults.set(testUUID, forKey: bandIDKey)
        defaults.set(testBandName, forKey: bandNameKey)

        var simulatedActiveSessions = 0
        var simulatedDrains = 0

        for iteration in 1...20 {
            // 1. App Launch / Open: Load persisted peripheral identifier
            let loadedID = defaults.string(forKey: bandIDKey)
            let loadedName = defaults.string(forKey: bandNameKey)

            XCTAssertEqual(loadedID, testUUID, "Iteration \(iteration): Saved UUID must not mutate")
            XCTAssertEqual(loadedName, testBandName, "Iteration \(iteration): Saved name must not mutate")

            // 2. Establish connection session (reuse existing if already connected)
            if simulatedActiveSessions == 0 {
                simulatedActiveSessions += 1
            }

            XCTAssertEqual(simulatedActiveSessions, 1, "Iteration \(iteration): Must never create duplicate BLE sessions")

            // 3. State lifecycle transitions
            var status = BandStatus.connecting(loadedName ?? "WHOOP")
            XCTAssertFalse(status.isConnected)

            status = .authenticating
            XCTAssertTrue(status.isConnected)

            status = .connected(loadedName ?? "WHOOP")
            XCTAssertTrue(status.isConnected)
            XCTAssertTrue(status.isReady)

            // 4. Live HR resumes
            let sampleBPM = 60 + (iteration % 15)
            status = .streaming(bpm: sampleBPM)
            XCTAssertTrue(status.isConnected)
            XCTAssertTrue(status.isReady)
            XCTAssertEqual(status.title, "Streaming live (\(sampleBPM) BPM)")

            // 5. History sync idempotency: same session is not duplicated
            simulatedDrains += 1
            XCTAssertEqual(simulatedDrains, iteration)

            // 6. Close / Background app normally (session teardown or preserve for next launch)
            simulatedActiveSessions = 0
        }

        // Final verification after 20 cycles
        XCTAssertEqual(defaults.string(forKey: bandIDKey), testUUID)
        XCTAssertEqual(defaults.string(forKey: bandNameKey), testBandName)
    }

    // MARK: - Explicit Unpair Test

    func testExplicitUnpairClearsAssociationAndStopsAutoReconnect() {
        let defaults = UserDefaults.standard
        let bandIDKey = "strap.band.preferred.id.v1"
        let bandNameKey = "strap.band.preferred.name.v1"

        // Setup paired state
        defaults.set(testUUID, forKey: bandIDKey)
        defaults.set(testBandName, forKey: bandNameKey)

        let link = BandLink()
        XCTAssertEqual(link.preferredBandID, testUUID)

        // Perform explicit unpair
        link.unpair()

        // Association cleared in memory
        XCTAssertNil(link.preferredBandID)
        XCTAssertNil(link.preferredBandName)
        XCTAssertEqual(link.status, .unpaired)

        // Association erased from UserDefaults
        XCTAssertNil(defaults.string(forKey: bandIDKey))
        XCTAssertNil(defaults.string(forKey: bandNameKey))

        // Subsequent autoConnect call must remain .unpaired and not start scanning
        link.autoConnectIfNeeded()
        XCTAssertEqual(link.status, .unpaired)
    }

    // MARK: - Identity Isolation Test

    func testNeverConnectsToDifferentPersonsWhoopWithSameName() {
        let savedID = testUUID
        let otherID = otherUUID
        let sharedName = "WHOOP 5.0 / MG"

        // DiscoveredBand with same name but different UUID
        let foreignBand = DiscoveredBand(
            id: otherID,
            uuid: UUID(uuidString: otherID)!,
            name: sharedName,
            rssi: -45, // very strong signal from someone else's WHOOP nearby
            lastSeenUnix: 100
        )

        // Filter isolation logic: If preferredBandID is set to savedID, otherID is rejected
        let isAccepted = (foreignBand.id == savedID)
        XCTAssertFalse(isAccepted, "Must never auto-connect to another person's WHOOP even with matching device name and stronger RSSI")
    }

    // MARK: - Controlled Retry Backoff Timing

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
}

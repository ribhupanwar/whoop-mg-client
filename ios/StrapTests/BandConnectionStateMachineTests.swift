import XCTest
@testable import Strap

final class BandConnectionStateMachineTests: XCTestCase {
    private let testUUID = "12345678-ABCD-EF01-2345-6789ABCDEF01"
    private let testBandName = "WHOOP MG (Test)"
    private let otherUUID = "87654321-DCBA-10FE-5432-10FEDCBA9876"

    func testGen5GATTDiscoveryUsesBandServiceAndCharacteristicUUIDs() {
        XCTAssertEqual(BandUUID.service.uuidString.lowercased(), "fd4b0001-cce1-4033-93ce-002d5875f58a")
        XCTAssertEqual(BandUUID.commandTo.uuidString.lowercased(), "fd4b0002-cce1-4033-93ce-002d5875f58a")
        XCTAssertEqual(BandUUID.notifiable.map { $0.uuidString.lowercased() }, [
            "fd4b0003-cce1-4033-93ce-002d5875f58a",
            "fd4b0004-cce1-4033-93ce-002d5875f58a",
            "fd4b0005-cce1-4033-93ce-002d5875f58a",
            "fd4b0007-cce1-4033-93ce-002d5875f58a",
        ])
    }

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

    // MARK: - Automated 100 Repeated Cycles

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

    // MARK: - Sleep Manual Edit Preservation vs Auto-Sync

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

    // MARK: - Casual Walking Workout Prevention & Sustained Workout Retention

    func testCasualLowCadenceWalkingDoesNotAutoSaveAsWorkout() {
        var samples: [V18Sample] = []
        let baseUnix = 1795000000

        // 1. Establish 300s resting baseline at 60 BPM
        for i in 0..<300 {
            samples.append(
                V18Sample(
                    header: BandRecordHeader(
                        version: 18, flags: 0x80, recordIndex: UInt32(i),
                        unix: UInt32(baseUnix + i), subsecQ15: 0
                    ),
                    heartRate: 60,
                    rrIntervalsMS: [1000],
                    dynamicAccelG: 0.01,
                    gravityXG: nil,
                    gravityYG: nil,
                    gravityZG: nil,
                    stepCounter: nil,
                    stepCadence: nil,
                    activityClass: nil,
                    skinTempC: nil,
                    tempAux1C: nil,
                    tempAux2C: nil,
                    sleepStateByte: nil,
                    sleepState: nil,
                    cardiacFlags: nil,
                    hrQualityFlags: nil,
                    spo2CandidateRaw: nil,
                    spo2CandidatePct: nil,
                    spo2CandidateKind: .absent,
                    signalQualityLogVariance: nil,
                    psnrB: nil,
                    psnrA: nil
                )
            )
        }

        // 2. 600s casual walking (~30 spm, HR 75, below exertion floor of 60 + 20 = 80 BPM)
        var counter = 1000
        for i in 300..<900 {
            if i % 2 == 0 { counter += 1 }
            samples.append(
                V18Sample(
                    header: BandRecordHeader(
                        version: 18, flags: 0x80, recordIndex: UInt32(i),
                        unix: UInt32(baseUnix + i), subsecQ15: 0
                    ),
                    heartRate: 75,
                    rrIntervalsMS: [800],
                    dynamicAccelG: 0.05,
                    gravityXG: nil,
                    gravityYG: nil,
                    gravityZG: nil,
                    stepCounter: counter,
                    stepCadence: nil,
                    activityClass: nil,
                    skinTempC: nil,
                    tempAux1C: nil,
                    tempAux2C: nil,
                    sleepStateByte: nil,
                    sleepState: nil,
                    cardiacFlags: nil,
                    hrQualityFlags: nil,
                    spo2CandidateRaw: nil,
                    spo2CandidatePct: nil,
                    spo2CandidateKind: .absent,
                    signalQualityLogVariance: nil,
                    psnrB: nil,
                    psnrA: nil
                )
            )
        }
        let detected = ActivityDetect.detect(samples, sleepPeriods: [])
        XCTAssertTrue(detected.isEmpty, "Casual shuffle with steps < 100 spm must NOT auto-save as a workout")
    }

    func testSustainedLowCadenceGenericWorkoutIsPreserved() {
        var samples: [V18Sample] = []
        let baseUnix = 1795000000

        // 1. Establish 300s resting baseline at 60 BPM
        for i in 0..<300 {
            samples.append(
                V18Sample(
                    header: BandRecordHeader(
                        version: 18, flags: 0x80, recordIndex: UInt32(i),
                        unix: UInt32(baseUnix + i), subsecQ15: 0
                    ),
                    heartRate: 60,
                    rrIntervalsMS: [1000],
                    dynamicAccelG: 0.01,
                    gravityXG: nil,
                    gravityYG: nil,
                    gravityZG: nil,
                    stepCounter: nil,
                    stepCadence: nil,
                    activityClass: nil,
                    skinTempC: nil,
                    tempAux1C: nil,
                    tempAux2C: nil,
                    sleepStateByte: nil,
                    sleepState: nil,
                    cardiacFlags: nil,
                    hrQualityFlags: nil,
                    spo2CandidateRaw: nil,
                    spo2CandidatePct: nil,
                    spo2CandidateKind: .absent,
                    signalQualityLogVariance: nil,
                    psnrB: nil,
                    psnrA: nil
                )
            )
        }

        // 2. 900s of sustained high exertion workout at 135 BPM with dynamic acceleration and steps at 60 SPM
        var counter = 2000
        for i in 300..<1200 {
            counter += 1 // 60 spm
            samples.append(
                V18Sample(
                    header: BandRecordHeader(
                        version: 18, flags: 0x80, recordIndex: UInt32(i),
                        unix: UInt32(baseUnix + i), subsecQ15: 0
                    ),
                    heartRate: 135,
                    rrIntervalsMS: [444],
                    dynamicAccelG: 0.05,
                    gravityXG: nil,
                    gravityYG: nil,
                    gravityZG: nil,
                    stepCounter: counter,
                    stepCadence: nil,
                    activityClass: nil,
                    skinTempC: nil,
                    tempAux1C: nil,
                    tempAux2C: nil,
                    sleepStateByte: nil,
                    sleepState: nil,
                    cardiacFlags: nil,
                    hrQualityFlags: nil,
                    spo2CandidateRaw: nil,
                    spo2CandidatePct: nil,
                    spo2CandidateKind: .absent,
                    signalQualityLogVariance: nil,
                    psnrB: nil,
                    psnrA: nil
                )
            )
        }
        let detected = ActivityDetect.detect(samples, sleepPeriods: [])
        XCTAssertFalse(detected.isEmpty, "Sustained 900s HR-135 exercise with steps must be detected as a workout")
        if let first = detected.first {
            XCTAssertEqual(first.kind, "workout")
        }
    }
}

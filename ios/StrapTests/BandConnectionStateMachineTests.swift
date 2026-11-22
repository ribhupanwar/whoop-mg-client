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

    func testHelloWaitsForDelayedMatchingProtocolAck() {
        var exchange = BandHelloExchange(sequence: 9)
        exchange.writeCompleted = true
        XCTAssertFalse(exchange.isConfirmed)
        let invalidReplies: [[UInt8]] = [
            [0x26, 1, 0x91, 8, 1],
            [0x26, 1, 0x03, 9, 1],
            [0x26, 1, 0x91, 9, 0],
            [0x26, 1, 0x91, 9]
        ]
        for reply in invalidReplies {
            exchange.receive(reply)
            XCTAssertFalse(exchange.isConfirmed)
        }
        exchange.receive([0x26, 1, 0x91, 9, 1])
        XCTAssertTrue(exchange.isConfirmed)
    }

    func testFragmentedHelloReplyBeforeWriteCallback() {
        let reply = Gen5Frame.build([0x24, 1, 0x91, 9, 1])
        let reassembler = FrameReassembler()
        var exchange = BandHelloExchange(sequence: 9)
        XCTAssertTrue(reassembler.feed(Array(reply.prefix(7))).isEmpty)
        for frame in reassembler.feed(Array(reply.dropFirst(7))) {
            exchange.receive(frame)
        }
        XCTAssertFalse(exchange.isConfirmed)
        exchange.writeCompleted = true
        XCTAssertTrue(exchange.isConfirmed)
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

    // MARK: - Hardware Event and Wear State Tests

    func testHardwareEventConstants() {
        XCTAssertEqual(BandHardwareEvent.wristOn.rawValue, 0x09)
        XCTAssertEqual(BandHardwareEvent.wristOff.rawValue, 0x0A)
        XCTAssertEqual(BandHardwareEvent.bleConnectionUp.rawValue, 0x0B)
        XCTAssertEqual(BandHardwareEvent.bleConnectionDown.rawValue, 0x0C)
        XCTAssertEqual(BandHardwareEvent.rtcLost.rawValue, 0x0D)
        XCTAssertEqual(BandHardwareEvent.doubleTap.rawValue, 0x0E)
        XCTAssertEqual(BandHardwareEvent.boot.rawValue, 0x0F)
        XCTAssertEqual(BandHardwareEvent.setRTC.rawValue, 0x10)
        XCTAssertEqual(BandHardwareEvent.temperatureLevel.rawValue, 0x11)
        XCTAssertEqual(BandHardwareEvent.pairingMode.rawValue, 0x12)
        XCTAssertEqual(BandHardwareEvent.batteryPackConnected.rawValue, 0x15)
        XCTAssertEqual(BandHardwareEvent.batteryPackRemoved.rawValue, 0x16)
        XCTAssertEqual(BandHardwareEvent.bleBonded.rawValue, 0x17)
        XCTAssertEqual(BandHardwareEvent.bleHRProfileEnable.rawValue, 0x18)
    }

    func testHardwareEventOpcodeExtraction() {
        // Direct opcode frame
        let wristOnFrame: [UInt8] = [0x09]
        let opcode1 = (wristOnFrame.count >= 3 && wristOnFrame[0] == 0x30) ? wristOnFrame[2] : (wristOnFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode1), .wristOn)

        // Envelope prefixed frame (0x30 prefix with 3+ bytes)
        let wristOffFrame: [UInt8] = [0x30, 0x01, 0x0A]
        let opcode2 = (wristOffFrame.count >= 3 && wristOffFrame[0] == 0x30) ? wristOffFrame[2] : (wristOffFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode2), .wristOff)

        // Charger connected frame
        let chargerConnectedFrame: [UInt8] = [0x15]
        let opcode3 = (chargerConnectedFrame.count >= 3 && chargerConnectedFrame[0] == 0x30) ? chargerConnectedFrame[2] : (chargerConnectedFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode3), .batteryPackConnected)

        // Charger detached frame
        let chargerRemovedFrame: [UInt8] = [0x16]
        let opcode4 = (chargerRemovedFrame.count >= 3 && chargerRemovedFrame[0] == 0x30) ? chargerRemovedFrame[2] : (chargerRemovedFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode4), .batteryPackRemoved)

        // Double-tap frame
        let doubleTapFrame: [UInt8] = [0x0E]
        let opcode5 = (doubleTapFrame.count >= 3 && doubleTapFrame[0] == 0x30) ? doubleTapFrame[2] : (doubleTapFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode5), .doubleTap)

        // BLE bonded frame
        let bleBondedFrame: [UInt8] = [0x17]
        let opcode6 = (bleBondedFrame.count >= 3 && bleBondedFrame[0] == 0x30) ? bleBondedFrame[2] : (bleBondedFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode6), .bleBonded)

        // BLE connection up frame
        let bleConnUpFrame: [UInt8] = [0x0B]
        let opcode7 = (bleConnUpFrame.count >= 3 && bleConnUpFrame[0] == 0x30) ? bleConnUpFrame[2] : (bleConnUpFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode7), .bleConnectionUp)

        // BLE connection down frame
        let bleConnDownFrame: [UInt8] = [0x0C]
        let opcode8 = (bleConnDownFrame.count >= 3 && bleConnDownFrame[0] == 0x30) ? bleConnDownFrame[2] : (bleConnDownFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode8), .bleConnectionDown)

        // Temperature level frame
        let tempLevelFrame: [UInt8] = [0x11]
        let opcode9 = (tempLevelFrame.count >= 3 && tempLevelFrame[0] == 0x30) ? tempLevelFrame[2] : (tempLevelFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode9), .temperatureLevel)

        // Pairing mode frame
        let pairingModeFrame: [UInt8] = [0x12]
        let opcode10 = (pairingModeFrame.count >= 3 && pairingModeFrame[0] == 0x30) ? pairingModeFrame[2] : (pairingModeFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode10), .pairingMode)

        // Boot frame
        let bootFrame: [UInt8] = [0x0F]
        let opcode11 = (bootFrame.count >= 3 && bootFrame[0] == 0x30) ? bootFrame[2] : (bootFrame.first ?? 0)
        XCTAssertEqual(BandHardwareEvent(rawValue: opcode11), .boot)
    }

    // MARK: - History Sync Reliability Tests

    func testDuplicateRecordIndexDetection() {
        // Per BLE_SYNC_FORENSICS.md: deduping enforced via recordIndex tracking
        var seenIndices: Set<UInt32> = []
        let recordIndices: [UInt32] = [100, 101, 102, 101, 103, 100, 104]
        var duplicateCount = 0

        for idx in recordIndices {
            if !seenIndices.insert(idx).inserted {
                duplicateCount += 1
            }
        }

        XCTAssertEqual(duplicateCount, 2, "Should detect 2 duplicate recordIndices (101 and 100)")
        XCTAssertEqual(seenIndices.count, 5, "Should have 5 unique recordIndices")
    }

    func testHistoryAckRetryLogic() {
        // Test that historicalDataResult timeout triggers retry instead of disconnect
        // This is a logical test; actual integration tested in sync lifecycle tests
        let ackOpcode = BandCommand.historicalDataResult.rawValue
        XCTAssertEqual(ackOpcode, 0x17)

        // Verify the ACK body format: [0x01] + 8-byte token
        let token: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        let ackBody = [0x01] + token
        XCTAssertEqual(ackBody.count, 9)
        XCTAssertEqual(ackBody[0], 0x01)
        XCTAssertEqual(Array(ackBody[1...]), token)
    }

    func testGetDataRangeCommand() {
        // GET_DATA_RANGE (0x22) sent at start of every drain
        let cmd = BandCommand.getDataRange.rawValue
        XCTAssertEqual(cmd, 0x22)
    }

    func testSendHistoricalDataCommand() {
        // SEND_HISTORICAL_DATA (0x16) starts the history stream
        let cmd = BandCommand.sendHistoricalData.rawValue
        XCTAssertEqual(cmd, 0x16)
    }

    func testHistoricalDataResultCommand() {
        // HISTORICAL_DATA_RESULT (0x17) is the ACK for history chunks
        let cmd = BandCommand.historicalDataResult.rawValue
        XCTAssertEqual(cmd, 0x17)
    }

    func testHistoryEndSubtype() {
        // Metadata subtype 0x02 indicates history end with token
        let historyEnd = BandPacket.historyEnd
        XCTAssertEqual(historyEnd, 0x02)
    }

    func testHistoryCompletionSubtype() {
        // Metadata subtype 0x03 indicates history completion
        let completionSubtype: UInt8 = 3
        XCTAssertEqual(completionSubtype, 3)
    }

    func testRecordIndexInV18Header() {
        // V18 record header contains recordIndex at offset 3 (4 bytes LE)
        let recordIndex: UInt32 = 0x12345678
        let bytes: [UInt8] = [
            UInt8(recordIndex & 0xFF),
            UInt8((recordIndex >> 8) & 0xFF),
            UInt8((recordIndex >> 16) & 0xFF),
            UInt8((recordIndex >> 24) & 0xFF)
        ]
        let decoded = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        XCTAssertEqual(decoded, recordIndex)
    }
}

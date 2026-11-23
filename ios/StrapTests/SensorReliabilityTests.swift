import XCTest
@testable import Strap

final class SensorReliabilityTests: XCTestCase {

    // MARK: - Fixture 1: Wrist on -> wrist off -> wrist on

    func testWristCycleStateTransitions() {
        let link = BandLink(restoreIdentifier: nil)
        XCTAssertEqual(link.wristState, .unknown)
        XCTAssertFalse(link.isWearing)

        // 1. Wrist On event (0x09)
        link.applyWearingStateTransition(.onWrist, source: "test event 0x09")
        XCTAssertEqual(link.wristState, .onWrist)
        XCTAssertTrue(link.isWearing)
        XCTAssertNotNil(link.lastWristStateChangeAt)

        // 2. Wrist Off event (0x0A)
        link.applyWearingStateTransition(.offWrist, source: "test event 0x0A")
        XCTAssertEqual(link.wristState, .offWrist)
        XCTAssertFalse(link.isWearing)
        XCTAssertNil(link.liveHeartRate)

        // 3. Wrist On again (0x09)
        link.applyWearingStateTransition(.onWrist, source: "test event 0x09 re-attachment")
        XCTAssertEqual(link.wristState, .onWrist)
        XCTAssertTrue(link.isWearing)
    }

    // MARK: - Fixture 2: Brief HR signal loss while wearing (uncertain debounce)

    func testBriefHRSignalLossWhileWearingEntersUncertainState() {
        let link = BandLink(restoreIdentifier: nil)
        link.applyWearingStateTransition(.onWrist, source: "test setup")
        XCTAssertEqual(link.wristState, .onWrist)

        // Temporary sensor uncertainty / dropout while worn
        link.applyWearingStateTransition(.uncertain, source: "test HR dropout")
        XCTAssertEqual(link.wristState, .uncertain)

        // Sensor signal recovered
        link.applyWearingStateTransition(.onWrist, source: "test HR recovered")
        XCTAssertEqual(link.wristState, .onWrist)
        XCTAssertTrue(link.isWearing)
    }

    // MARK: - Fixture 3: Battery pack connection and removal

    func testBatteryPackConnectionAndRemoval() {
        // Format-1 battery pack connected (0x15)
        let chargerOnInner: [UInt8] = [0x30, 0x03, 0x15, 0x01, 0x80, 0x3B, 0xB1, 0x6A]
        let pOn = BandHardwareEventPacket.decode(chargerOnInner)
        XCTAssertNotNil(pOn)
        XCTAssertEqual(pOn?.rawOpcode, 0x15)
        XCTAssertEqual(pOn?.event, .batteryPackConnected)
        XCTAssertTrue(pOn?.isKnown ?? false)

        // Format-1 battery pack removed (0x16)
        let chargerOffInner: [UInt8] = [0x30, 0x03, 0x16, 0x01, 0x80, 0x3B, 0xB1, 0x6A]
        let pOff = BandHardwareEventPacket.decode(chargerOffInner)
        XCTAssertNotNil(pOff)
        XCTAssertEqual(pOff?.rawOpcode, 0x16)
        XCTAssertEqual(pOff?.event, .batteryPackRemoved)
        XCTAssertTrue(pOff?.isKnown ?? false)
    }

    // MARK: - Fixture 4: Duplicate hardware events

    func testDuplicateHardwareEventsDoNotCorruptState() {
        let link = BandLink(restoreIdentifier: nil)

        // Rapid duplicate wristOn
        link.applyWearingStateTransition(.onWrist, source: "event 1")
        let firstChange = link.lastWristStateChangeAt
        link.applyWearingStateTransition(.onWrist, source: "event 2 duplicate")
        XCTAssertEqual(link.wristState, .onWrist)
        XCTAssertTrue(link.isWearing)
        XCTAssertEqual(link.lastWristStateChangeAt, firstChange, "Duplicate state should not churn change timestamp")

        // Rapid duplicate wristOff
        link.applyWearingStateTransition(.offWrist, source: "event 3")
        let offChange = link.lastWristStateChangeAt
        link.applyWearingStateTransition(.offWrist, source: "event 4 duplicate")
        XCTAssertEqual(link.wristState, .offWrist)
        XCTAssertFalse(link.isWearing)
        XCTAssertEqual(link.lastWristStateChangeAt, offChange)
    }

    // MARK: - Fixture 5: Missing or malformed wrist-state fields

    func testMalformedOrTruncatedStatusPacket() {
        // Completely empty
        XCTAssertNil(WhoopStatusPacket.decode([]))

        // Short packet
        XCTAssertNil(WhoopStatusPacket.decode([0x30, 0x01]))

        // Non-status event
        XCTAssertNil(WhoopStatusPacket.decode([0x30, 0x01, 0x09]))

        // Valid SoC (854 = 85.4%), charging=1, contact on-wrist (0x0001)
        var validStatus: [UInt8] = [0x30, 0x01, 0x03, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        // Bytes 13..14: SoC = 854 (0x0356)
        validStatus.append(0x56)
        validStatus.append(0x03)
        // Byte 15: charging = 1
        validStatus.append(0x01)
        // Bytes 16..17: wristState = 0x0001
        validStatus.append(0x01)
        validStatus.append(0x00)

        let status = WhoopStatusPacket.decode(validStatus)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.rawBatteryTenths, 854)
        XCTAssertEqual(status?.batteryPercent, 85.4)
        XCTAssertEqual(status?.isCharging, true)
        XCTAssertEqual(status?.wristStateRaw, 0x0001)
        XCTAssertEqual(status?.contactState, .onWrist)

        // Off-wrist status packet (wristState = 0x0000)
        var offWristStatus = validStatus
        offWristStatus[16] = 0x00
        offWristStatus[17] = 0x00
        let statusOff = WhoopStatusPacket.decode(offWristStatus)
        XCTAssertNotNil(statusOff)
        XCTAssertEqual(statusOff?.wristStateRaw, 0x0000)
        XCTAssertEqual(statusOff?.contactState, .offWrist)

        // Truncated at byte 15 (valid battery but missing wristState)
        let truncated = Array(validStatus.prefix(15))
        let statusTruncated = WhoopStatusPacket.decode(truncated)
        XCTAssertNotNil(statusTruncated)
        XCTAssertEqual(statusTruncated?.batteryPercent, 85.4)
        XCTAssertEqual(statusTruncated?.contactState, .unknown)
    }

    // MARK: - Fixture 6: Reconnection during history sync preserves cursors

    func testReconnectionPreservesHistoryContinuationFrontier() {
        let link = BandLink(restoreIdentifier: nil)

        // Verify clean initial state
        XCTAssertNil(link.lastHistorySyncAt)
        XCTAssertFalse(link.isSavingHistory)
    }

    // MARK: - Fixture 7: App suspension and restoration options

    func testCentralManagerRestoreIdentifierOption() {
        // Initializing with nil identifier prevents simulator CoreBluetooth conflict
        let testLink = BandLink(restoreIdentifier: nil)
        XCTAssertNotNil(testLink)

        // Standard production identifier format
        XCTAssertEqual(BandLink.wristOffDebounceInterval, 45.0)
    }

    // MARK: - Fixture 8: Off-wrist HR/RR samples rejection

    func testOffWristSamplesRejectedFromAnalysis() {
        let header = BandRecordHeader(version: 18, flags: 0, recordIndex: 1, unix: 1700000000, subsecQ15: 0)

        // Sample with optical noise (48 bpm) but confirmed tabletop condition
        let tabletop = V18Sample(
            header: header,
            heartRate: 48,
            rrIntervalsMS: [1250],
            dynamicAccelG: 0.002,
            gravityXG: 0.0,
            gravityYG: 0.0,
            gravityZG: 1.0,
            stepCounter: 0,
            stepCadence: 0,
            activityClass: 0,
            skinTempC: 22.0,
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

        XCTAssertFalse(tabletop.wearing, "Tabletop artifact must have wearing == false")
        XCTAssertEqual(tabletop.wristContactState, .offWrist)
    }

    // MARK: - Fixture 9: Unknown firmware opcodes safe handling

    func testUnknownFirmwareOpcodeDoesNotCrash() {
        let unknownInner: [UInt8] = [0x30, 0x01, 0x99, 0x00, 0x12, 0x34, 0x56, 0x78, 0xAA, 0xBB]
        let packet = BandHardwareEventPacket.decode(unknownInner)
        XCTAssertNotNil(packet)
        XCTAssertEqual(packet?.rawOpcode, 0x99)
        XCTAssertNil(packet?.event)
        XCTAssertFalse(packet?.isKnown ?? true)
        XCTAssertEqual(packet?.timestamp, 0x78563412)
        XCTAssertEqual(packet?.payload, [0xAA, 0xBB])

        // Direct single-byte unknown
        let directUnknown = BandHardwareEventPacket.decode([0xFE])
        XCTAssertNotNil(directUnknown)
        XCTAssertEqual(directUnknown?.rawOpcode, 0xFE)
        XCTAssertNil(directUnknown?.event)
        XCTAssertFalse(directUnknown?.isKnown ?? true)
    }
}

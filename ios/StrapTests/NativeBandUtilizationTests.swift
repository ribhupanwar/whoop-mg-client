import XCTest
@testable import Strap

final class NativeBandUtilizationTests: XCTestCase {
    func testBandCommandResultDecodesSuccessAndFailure() {
        let ackBytes: [UInt8] = [0x24, 0x05, 0x16, 0x04, 0x01]
        let ack = BandCommandResult.decode(ackBytes)
        XCTAssertNotNil(ack)
        XCTAssertEqual(ack?.commandOpcode, 0x16)
        XCTAssertEqual(ack?.commandName, "SEND_HISTORICAL_DATA")
        XCTAssertTrue(ack?.isSuccess ?? false)

        let nackBytes: [UInt8] = [0x26, 0x09, 0x42, 0x08, 0x00]
        let nack = BandCommandResult.decode(nackBytes)
        XCTAssertNotNil(nack)
        XCTAssertEqual(nack?.commandOpcode, 0x42)
        XCTAssertEqual(nack?.commandName, "SET_ALARM")
        XCTAssertFalse(nack?.isSuccess ?? true)
    }

    func testWhoopStatusPacketDecodesWristContactBitfield() {
        // inner[0]=0x30, inner[2]=0x03, inner[13..14]=850 (85.0%), inner[15]=0x00, inner[16..17]=0x0007
        var inner = [UInt8](repeating: 0, count: 18)
        inner[0] = 0x30
        inner[2] = 0x03
        inner[13] = 0x52
        inner[14] = 0x03 // 850 tenths = 85.0%
        inner[15] = 0x00
        inner[16] = 0x07 // cap + optical + placement
        inner[17] = 0x00

        let packet = WhoopStatusPacket.decode(inner)
        XCTAssertEqual(packet?.batteryPercent, 85.0)
        XCTAssertEqual(packet?.isCharging, false)
        XCTAssertEqual(packet?.contactState, .onWrist)
        XCTAssertEqual(packet?.wristStateRaw, 0x0007)
    }

    func testNativeSensorSnapshotTreatsMinus128PSNRAsUnavailableAndEnforcesFreshness() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: 1, unix: UInt32(now.timeIntervalSince1970), subsecQ15: 0),
            heartRate: 68,
            stepCadence: 112,
            activityClass: 1,
            skinTempC: 31.4,
            signalQualityLogVariance: 0.42,
            psnrB: -128,
            psnrA: 14
        )
        let status = WhoopStatusPacket(
            rawBatteryTenths: 800,
            batteryPercent: 80.0,
            isCharging: false,
            wristStateRaw: 0x0007,
            contactState: .onWrist
        )
        let snapshot = NativeSensorSnapshot.build(
            latestSample: sample,
            statusPacket: status,
            statusObservedAt: now,
            fallbackWristState: .unknown
        )
        XCTAssertNotNil(snapshot)
        XCTAssertNil(snapshot?.psnrB, "-128 pSNR sentinel must be unavailable, not low quality")
        XCTAssertEqual(snapshot?.psnrA, 14)
        XCTAssertEqual(snapshot?.stepCadenceSPM, 112)
        XCTAssertEqual(snapshot?.capacitiveTouch, true)
        XCTAssertEqual(snapshot?.opticalReflectance, true)
        XCTAssertEqual(snapshot?.onBodyPlacement, true)
        XCTAssertTrue(snapshot?.isFresh(at: now.addingTimeInterval(300)) ?? false)
        XCTAssertFalse(snapshot?.isFresh(at: now.addingTimeInterval(900)) ?? true)
    }

    func testNativeSensorSnapshotPrefersNewerFallbackWristObservationOverStaleStatusPacket() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = t1.addingTimeInterval(30)
        let staleStatus = WhoopStatusPacket(
            rawBatteryTenths: 800,
            batteryPercent: 80.0,
            isCharging: false,
            wristStateRaw: 0x0007,
            contactState: .onWrist
        )
        let snapshot = NativeSensorSnapshot.build(
            latestSample: nil,
            statusPacket: staleStatus,
            statusObservedAt: t1,
            fallbackWristState: .offWrist,
            fallbackWristObservedAt: t2
        )
        XCTAssertEqual(snapshot?.wristContact, .offWrist)
        XCTAssertNil(snapshot?.wristStateRaw)
        XCTAssertEqual(snapshot?.observedAt, t2)
    }

    func testNativeCadenceRejectsOutOfRangeValues() {
        XCTAssertEqual(NativeSensorSnapshot.sanitizedCadence(0), 0)
        XCTAssertEqual(NativeSensorSnapshot.sanitizedCadence(180), 180)
        XCTAssertNil(NativeSensorSnapshot.sanitizedCadence(-1))
        XCTAssertNil(NativeSensorSnapshot.sanitizedCadence(255))
    }

    func testV18DecoderRejectsMinus5000SkinTemperatureSentinel() {
        var inner = [UInt8](repeating: 0, count: 110)
        inner[0] = 0x2F
        inner[1] = 18
        inner[2] = 0x80
        // unix = 1_700_000_000
        let unix: UInt32 = 1_700_000_000
        inner[7] = UInt8(unix & 0xFF)
        inner[8] = UInt8((unix >> 8) & 0xFF)
        inner[9] = UInt8((unix >> 16) & 0xFF)
        inner[10] = UInt8((unix >> 24) & 0xFF)
        inner[14] = 65 // HR
        // skinTemp at inner[65..66] = -5000 (0xEC78)
        let sentinel = UInt16(bitPattern: Int16(-5000))
        inner[65] = UInt8(sentinel & 0xFF)
        inner[66] = UInt8((sentinel >> 8) & 0xFF)

        let decoded = V18Decoder.decode(inner)
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.skinTempC, "-5000 (-50.00 C) sentinel must decode to nil")
    }

    func testBackgroundSyncSchedulerRequestConfiguration() {
        let request = BackgroundSyncScheduler.shared.makeRequest()
        XCTAssertEqual(request.identifier, BackgroundSyncScheduler.taskIdentifier)
        XCTAssertFalse(request.requiresNetworkConnectivity)
        XCTAssertFalse(request.requiresExternalPower)
    }
}

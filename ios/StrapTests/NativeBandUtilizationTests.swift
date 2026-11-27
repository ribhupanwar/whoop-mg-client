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

    func testFreshContactCannotRefreshHistoricalCadenceOrOpticalSample() throws {
        let measured = Date(timeIntervalSince1970: 1_700_000_000)
        let now = measured.addingTimeInterval(1200)
        let sample = V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: 1,
                                     unix: UInt32(measured.timeIntervalSince1970), subsecQ15: 0),
            heartRate: 140, stepCadence: 176, psnrA: 12)
        let snapshot = try XCTUnwrap(NativeSensorSnapshot.build(
            latestSample: sample, statusPacket: nil, statusObservedAt: nil,
            fallbackWristState: .onWrist, fallbackWristObservedAt: now))
        XCTAssertEqual(snapshot.sampleObservedAt, measured)
        XCTAssertEqual(snapshot.contactObservedAt, now)
        XCTAssertTrue(snapshot.isContactFresh(at: now))
        XCTAssertFalse(snapshot.isSampleFresh(at: now))
        XCTAssertNil(snapshot.recentStepCadence(at: now, connected: true))
        XCTAssertEqual(snapshot.recentStepCadence(at: measured.addingTimeInterval(15), connected: true), 176)
        XCTAssertNil(snapshot.recentStepCadence(at: measured.addingTimeInterval(16), connected: true))
        XCTAssertNil(snapshot.recentStepCadence(at: measured.addingTimeInterval(-1), connected: true))
        XCTAssertNil(snapshot.recentStepCadence(at: measured, connected: false))
        let offWrist = try XCTUnwrap(NativeSensorSnapshot.build(
            latestSample: sample, statusPacket: nil, statusObservedAt: nil,
            fallbackWristState: .offWrist, fallbackWristObservedAt: measured))
        XCTAssertNil(offWrist.recentStepCadence(at: measured, connected: true))
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

    func testNativeDeepTelemetryRoutesAllLayoutsWithoutInventingBiometrics() throws {
        func frame(_ version: UInt8, _ size: Int, unix: UInt8 = 100) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: size)
            bytes[0] = 0x2F
            bytes[1] = version
            bytes[7] = unix
            return bytes
        }
        var deep = NativeDeepTelemetry()
        let optical = frame(20, 2128)
        XCTAssertTrue(deep.ingest(optical))
        XCTAssertEqual(deep.optical?.bytes, 2115)
        XCTAssertTrue(deep.ingest(frame(20, 2128, unix: 90)))
        XCTAssertEqual(deep.optical?.unix, 100)
        XCTAssertEqual(deep.v20Frames, 2)

        var imu = frame(21, 1232)
        imu[16] = 2
        imu[622] = 1
        imu[21] = 0x10 // +1 g
        imu[23] = 0xF0 // -1 g
        imu[633] = 0x40 // +1000 dps
        XCTAssertTrue(deep.ingest(imu))
        let motion = try XCTUnwrap(deep.motion)
        XCTAssertEqual(motion.accelerationSamples, 2)
        XCTAssertEqual(motion.gyroSamples, 1)
        XCTAssertEqual(motion.centeredAccelerationRMSG, 1, accuracy: 0.000001)
        XCTAssertEqual(motion.angularVelocityRMSDPS, 1000, accuracy: 0.000001)
        var still = imu
        still[23] = 0x10
        XCTAssertTrue(deep.ingest(still))
        XCTAssertEqual(try XCTUnwrap(deep.motion).centeredAccelerationRMSG, 0, accuracy: 0.000001)

        var tagged = frame(22, 176)
        tagged[13] = 3
        XCTAssertTrue(deep.ingest(tagged))
        XCTAssertEqual(deep.tagged?.known, true)
        tagged[13] = 255
        XCTAssertTrue(deep.ingest(tagged))
        XCTAssertEqual(deep.tagged?.known, false)
        XCTAssertEqual(deep.unknownV22Frames, 1)

        var pip = frame(26, 76)
        pip[19] = 0xFF; pip[20] = 0xFF // -1 ADC delta
        XCTAssertTrue(deep.ingest(pip))
        XCTAssertEqual(deep.pip?.deltaCount, 24)
        XCTAssertEqual(try XCTUnwrap(deep.pip?.deltaRMSADC), sqrt(1.0 / 24), accuracy: 0.000001)
        for raw in [optical, imu, tagged, pip] {
            XCTAssertNil(V18Decoder.decode(raw))
        }
        XCTAssertFalse(deep.ingest(frame(18, 110)))
        XCTAssertFalse(deep.ingest(Array(imu.dropLast())))
        XCTAssertEqual(deep.imuFrames, 2)
        XCTAssertEqual(deep.v26Frames, 1)
    }

    func testDeepWaveformAndMotionFeatures() throws {
        var v26 = [UInt8](repeating: 0, count: 76)
        v26[0] = 0x2F; v26[1] = 26; v26[15] = 100
        v26[19] = 0xFF; v26[20] = 0x7F
        v26[21] = 0xFF; v26[22] = 0xFF
        let pip = try XCTUnwrap(Gen5V26Record.decode(v26)).reconstruction
        XCTAssertEqual(pip.codes.count, 25)
        XCTAssertEqual(Array(pip.codes.prefix(3)), [100, 32867, 32866])
        XCTAssertEqual(pip.firstAmbiguousIndex, 1)
        XCTAssertEqual(pip.outOfRangeCount, 0)
        v26[15] = 0xFF; v26[16] = 0xFF; v26[17] = 0x07
        XCTAssertGreaterThan(try XCTUnwrap(Gen5V26Record.decode(v26)).reconstruction.outOfRangeCount, 0)

        var v22 = [UInt8](repeating: 0, count: 176)
        v22[0] = 0x2F; v22[1] = 22; v22[13] = 9
        v22[27] = 0xFF; v22[28] = 0xFF // -1 from anchor zero
        v22[29] = 1 // wrap back to zero
        v22[31] = 0x00; v22[32] = 0x80 // negative rail
        v22[133] = 5
        let queued = try XCTUnwrap(Gen5V22Record.decode(v22)?.queuedOptical)
        XCTAssertEqual(queued.channel, 5)
        XCTAssertTrue(queued.isRetainedChannel)
        XCTAssertEqual(queued.sampleBits.count, 50)
        XCTAssertEqual(Array(queued.sampleBits.prefix(3)), [0, UInt32.max, 0])
        XCTAssertEqual(queued.firstAmbiguousIndex, 3)
        var deep = NativeDeepTelemetry()
        XCTAssertTrue(deep.ingest(v22))
        XCTAssertEqual(deep.tagged?.queuedChannel, 5)
        XCTAssertEqual(deep.tagged?.queuedSampleCount, 50)
        v22[14] = 1
        XCTAssertNil(Gen5V22Record.decode(v22)?.queuedOptical)

        let imu = Gen5IMUBuffer(version: 21, recordIndex: 0, unix: 100, rawSubsecond: 0,
                                accelerationG: [[1, 2, 1], [0, 0, 0], [0, 0, 0]],
                                angularVelocityDPS: [[3], [4], [0]])
        let features = try XCTUnwrap(imu.blockFeatures)
        XCTAssertEqual(features.magnitudeVariationG, sqrt(2.0 / 9), accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(features.adjacentMagnitudeChangeRMSG), 1, accuracy: 0.000001)
        XCTAssertEqual(features.meanAngularSpeedDPS, 5, accuracy: 0.000001)
    }

    func testBackgroundSyncSchedulerRequestConfiguration() {
        let request = BackgroundSyncScheduler.shared.makeRequest()
        XCTAssertEqual(request.identifier, BackgroundSyncScheduler.taskIdentifier)
        XCTAssertFalse(request.requiresNetworkConnectivity)
        XCTAssertFalse(request.requiresExternalPower)
    }
}

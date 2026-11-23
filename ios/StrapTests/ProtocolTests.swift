import XCTest
@testable import Strap

final class ProtocolTests: XCTestCase {

    // v18 record captured from the real MG, CRC-validated on arrival.
    private let realV18Hex = """
    2f1280f656e501af8bf16a707d005e00000000000000000002715408045e0000\
    c52ccaf1409a593f3dd723c33d5c8b5b3ff603780066060010000000003b014e\
    01080d400b010c060c0100000000000000000000000000000000000000000000\
    01008e578080000000fba96bbf000000
    """

    private func bytes(_ hex: String) -> [UInt8] {
        let clean = hex.filter { !$0.isWhitespace }
        var result: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else {
                XCTFail("bad hex at \(index)")
                return []
            }
            result.append(byte)
            index = next
        }
        return result
    }

    // MARK: - Checksums

    func testCRC32MatchesZlib() {
        XCTAssertEqual(BandChecksums.crc32(bytes("68656c6c6f")), 0x3610_A686)
    }

    func testCRC16ModbusKnownVector() {
        XCTAssertEqual(BandChecksums.crc16Modbus(bytes("313233343536373839")), 0x4B37)
    }

    // MARK: - Framing

    func testClientHelloMatchesHardwareVector() {
        // Byte-for-byte frame observed on a real gen5 band. Validates
        // crc16-modbus, crc32, header layout and padding at once.
        let inner: [UInt8] = [0x23, 0x01, 0x91, 0x01]
        let expected = bytes("aa0108000001e67123019101363e5c8d")
        XCTAssertEqual(Gen5Frame.build(inner), expected)
    }

    func testRoundTripAndHeaderLayout() {
        let inner: [UInt8] = [0x23, 0x00, 0x0B]
        let frame = Gen5Frame.build(inner)
        XCTAssertEqual(frame[0], 0xAA)
        XCTAssertEqual(frame[1], 0x01)
        XCTAssertEqual(Array(frame[4..<6]), [0x00, 0x01])
        XCTAssertEqual(Gen5Frame.parse(frame), Gen5Frame.padded(inner))
    }

    func testInboundMarkerIsAccepted() {
        var frame = Gen5Frame.build([0x30, 0x00, 0x01])
        frame[4] = 0x01
        frame[5] = 0x00
        let crc = BandChecksums.crc16Modbus(Array(frame[0..<6]))
        frame[6] = UInt8(crc & 0xFF)
        frame[7] = UInt8(crc >> 8)
        XCTAssertNotNil(Gen5Frame.parse(frame))
    }

    func testCorruptPayloadIsRejected() {
        var frame = Gen5Frame.build([0x28, 0x00, 0x01, 0x02, 0x03])
        frame[frame.count - 1] ^= 0xFF
        XCTAssertNil(Gen5Frame.parse(frame))
    }

    func testCorruptHeaderIsRejected() {
        var frame = Gen5Frame.build([0x28, 0x00, 0x01])
        frame[6] ^= 0xFF
        XCTAssertNil(Gen5Frame.parse(frame))
    }

    // MARK: - Reassembly

    func testByteAtATimeDelivery() {
        let inner: [UInt8] = [0x28, 0x07, 0x42] + [UInt8](repeating: 0xAA, count: 9)
        let frame = Gen5Frame.build(inner)
        let reassembler = FrameReassembler()
        var out: [[UInt8]] = []
        for byte in frame {
            out += reassembler.feed([byte])
        }
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first, Gen5Frame.padded(inner))
        XCTAssertEqual(reassembler.pending, 0)
    }

    func testSofBytesInsidePayloadDoNotResync() {
        let inner: [UInt8] = [0x2F, 0x01, 0x18] + [UInt8](repeating: 0xAA, count: 61)
        let frame = Gen5Frame.build(inner)
        for split in 1..<frame.count {
            let reassembler = FrameReassembler()
            var out = reassembler.feed(Array(frame[0..<split]))
            out += reassembler.feed(Array(frame[split...]))
            XCTAssertEqual(out.count, 1, "split \(split)")
            XCTAssertEqual(out.first, Gen5Frame.padded(inner), "split \(split)")
            XCTAssertEqual(reassembler.badFrames, 0, "split \(split)")
        }
    }

    func testCorruptLengthCannotStallFollowingValidFrame() {
        var corrupt = Gen5Frame.build([0x28, 0, 1])
        corrupt[2] = 0x00; corrupt[3] = 0xF0 // invalid CRC with a huge length
        let inner: [UInt8] = [0x2F, 18, 0, 1]
        let reassembler = FrameReassembler()
        XCTAssertEqual(reassembler.feed(corrupt + Gen5Frame.build(inner)), [inner])
        XCTAssertEqual(reassembler.pending, 0)
    }

    func testUnsupportedFormatWithValidChecksumsIsRejected() {
        let inner: [UInt8] = [0x2F, 18, 0, 1]
        let valid = Gen5Frame.build(inner)
        var unsupported = valid
        unsupported[1] = 2
        let checksum = BandChecksums.crc16Modbus(unsupported[0..<6])
        unsupported[6] = UInt8(truncatingIfNeeded: checksum)
        unsupported[7] = UInt8(checksum >> 8)

        XCTAssertNil(Gen5Frame.parse(unsupported))
        let reassembler = FrameReassembler()
        XCTAssertTrue(reassembler.feed(Array(unsupported.prefix(7))).isEmpty)
        XCTAssertEqual(reassembler.feed(Array(unsupported.dropFirst(7)) + valid), [inner])
        XCTAssertEqual(reassembler.pending, 0)
    }

    func testUnalignedLengthWithValidHeaderCRCDoesNotStallReassembly() {
        let inner: [UInt8] = [0x2F, 18, 0, 1]
        let valid = Gen5Frame.build(inner)
        var header = Array(valid.prefix(8))
        header[2] = 0x01
        header[3] = 0x10
        let checksum = BandChecksums.crc16Modbus(header[0..<6])
        header[6] = UInt8(truncatingIfNeeded: checksum)
        header[7] = UInt8(checksum >> 8)

        XCTAssertEqual(FrameReassembler().feed(header + valid), [inner])
    }

    func testDirectParseRequiresExactlyOneNonemptyFrame() {
        let valid = Gen5Frame.build([0x28, 0, 1])
        XCTAssertNil(Gen5Frame.parse(valid + valid))
        XCTAssertNil(Gen5Frame.parse(Gen5Frame.build([])))
    }

    func testDroppedPayloadDoesNotConsumeFollowingFrame() {
        let first = Gen5Frame.build([UInt8](repeating: 42, count: 112))
        let inner: [UInt8] = [0x2F, 18, 0, 1]
        let reassembler = FrameReassembler()
        let truncated = Array(first.prefix(30))
        let following = Gen5Frame.build(inner)
        let padding = [UInt8](repeating: 0, count: 112)
        XCTAssertEqual(reassembler.feed(truncated + following + padding), [inner])
    }

    func testMultipleFramesInOneChunk() {
        let first = Gen5Frame.build([0x28, 0x00, 0x01])
        let second = Gen5Frame.build([0x30, 0x00, 0x02])
        XCTAssertEqual(FrameReassembler().feed(first + second).count, 2)
    }

    func testLeadingGarbageIsDiscarded() {
        let frame = Gen5Frame.build([0x28, 0x00, 0x01])
        let reassembler = FrameReassembler()
        XCTAssertEqual(reassembler.feed([0x00, 0xFF, 0x13] + frame).count, 1)
        XCTAssertEqual(reassembler.droppedBytes, 3)
    }

    func testTruncatedFrameStaysPending() {
        let frame = Gen5Frame.build([0x28, 0x00, 0x01])
        let reassembler = FrameReassembler()
        XCTAssertTrue(reassembler.feed(Array(frame.dropLast(2))).isEmpty)
        XCTAssertGreaterThan(reassembler.pending, 0)
    }

    // MARK: - v18 decode

    func testRealRecordHeader() {
        let inner = bytes(realV18Hex)
        XCTAssertEqual(inner.count, 112)
        guard let sample = V18Decoder.decode(inner) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(sample.header.version, 18)
        XCTAssertEqual(sample.header.flags, 0x80)
        XCTAssertEqual(sample.header.recordIndex, 31_807_222)
        XCTAssertEqual(sample.header.unix, 1_794_214_831)
        XCTAssertEqual(sample.header.subsecQ15, 32_112)
        XCTAssertEqual(sample.header.ppgSampleRateHz, 25)
        XCTAssertEqual(sample.header.timestamp, 1_794_214_831 + 32_112 / 32_768.0, accuracy: 0.000_001)
    }

    func testRealRecordFields() {
        guard let sample = V18Decoder.decode(bytes(realV18Hex)) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(sample.heartRate, 94)
        XCTAssertTrue(sample.wearing)
        XCTAssertEqual(sample.rrIntervalsMS, [])
        XCTAssertEqual(sample.skinTempC ?? 0, 33.36, accuracy: 0.001)
        XCTAssertEqual(sample.tempAux1C ?? 0, 31.5, accuracy: 0.001)
        XCTAssertEqual(sample.tempAux2C ?? 0, 33.4, accuracy: 0.001)
        XCTAssertEqual(sample.stepCounter, 1014)
        XCTAssertEqual(sample.stepCadence, 120)
        XCTAssertEqual(sample.sleepStateByte, 1)
        XCTAssertEqual(sample.sleepState, 0)
        XCTAssertEqual(sample.signalQualityLogVariance ?? 0, -0.9206, accuracy: 0.0001)
        XCTAssertEqual(sample.gravityXG ?? 0, 0.0468, accuracy: 0.0005)
        XCTAssertEqual(sample.gravityYG ?? 0, 0.0952, accuracy: 0.0005)
        XCTAssertEqual(sample.gravityZG ?? 0, 0.8576, accuracy: 0.0005)
    }

    func testV18UnknownSleepByteBitsRemainOpaque() throws {
        var inner = bytes(realV18Hex)
        inner[73] = 0b0010_0000
        let state = try XCTUnwrap(V18Decoder.decode(inner)).sleepState
        inner[73] |= 0b1100_1111
        let sample = try XCTUnwrap(V18Decoder.decode(inner))
        XCTAssertEqual(sample.sleepState, state)
        XCTAssertEqual(sample.sleepStateByte, Int(inner[73]))
    }

    func testImplausibleHRZeroesOnlyHR() {
        var inner = bytes(realV18Hex)
        inner[14] = 250
        guard let sample = V18Decoder.decode(inner) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(sample.heartRate, 0)
        XCTAssertFalse(sample.wearing)
        XCTAssertEqual(sample.skinTempC ?? 0, 33.36, accuracy: 0.001)
        XCTAssertEqual(sample.stepCounter, 1014)
    }

    func testGen5V18UsesHardwareVerifiedHRAtInner14NotGenericInner17() {
        // Gen5 frame header is 8 bytes; absolute byte 22 = inner[14].
        // A generic record map using inner[17] must not override v18.
        var inner = bytes(realV18Hex)
        inner[14] = 81
        inner[17] = 120
        XCTAssertEqual(V18Decoder.decode(inner)?.heartRate, 81)
        let frame = Gen5Frame.build(inner)
        let parsed = Gen5Frame.parse(frame)
        XCTAssertEqual(parsed?[14], 81)
        XCTAssertEqual(frame[22], 81)
    }

    func testRRIntervalsClampToPlausibleRange() {
        var inner = bytes(realV18Hex)
        inner[15] = 2
        inner[16] = 0x20
        inner[17] = 0x03  // 800
        inner[18] = 0x34
        inner[19] = 0x03  // 820
        XCTAssertEqual(V18Decoder.decode(inner)?.rrIntervalsMS, [800, 820])

        inner[16] = 50
        inner[17] = 0  // below 200 ms
        XCTAssertEqual(V18Decoder.decode(inner)?.rrIntervalsMS, [820])
    }

    func testV18OpticalPSNRDecodesSignedValuesWithoutQualityAssumptions() {
        var inner = bytes(realV18Hex)
        inner[100] = 0x80 // -128 is the unavailable sentinel.
        inner[101] = 0xF6 // -10 dB, signed Int8.
        let sample = V18Decoder.decode(inner)
        XCTAssertEqual(sample?.psnrB, -128)
        XCTAssertEqual(sample?.psnrA, -10)
        // Optical diagnostics must not silently suppress a valid HR reading.
        XCTAssertEqual(sample?.heartRate, 94)
    }

    func testRRCountAboveFourIsIgnored() {
        var inner = bytes(realV18Hex)
        inner[15] = 9
        XCTAssertEqual(V18Decoder.decode(inner)?.rrIntervalsMS, [])
    }

    func testRRCountUpToFourIsAccepted() {
        var inner = bytes(realV18Hex)
        inner[15] = 4
        for i in 0..<4 {
            let val = 700 + i * 10
            inner[16 + 2 * i] = UInt8(val & 0xFF)
            inner[17 + 2 * i] = UInt8((val >> 8) & 0xFF)
        }
        // Padding bytes 20..<24 remain zero from realV18Hex
        let sample = V18Decoder.decode(inner)
        XCTAssertEqual(sample?.rrIntervalsMS, [700, 710, 720, 730])
        XCTAssertTrue(sample?.rrPaddingValid ?? false, "rrPaddingValid must be true when all padding bytes are zero")
    }

    func testRRNonZeroPaddingPreservesIntervalsButFlagsInvalid() {
        var inner = bytes(realV18Hex)
        inner[15] = 2
        inner[16] = 0x20
        inner[17] = 0x03  // 800
        inner[18] = 0x34
        inner[19] = 0x03  // 820
        inner[22] = 0xAA  // Non-zero padding byte in tail (bytes 20..<24)
        let sample = V18Decoder.decode(inner)
        XCTAssertEqual(sample?.rrIntervalsMS, [800, 820], "RR intervals preserved despite non-zero padding")
        XCTAssertFalse(sample?.rrPaddingValid ?? true, "rrPaddingValid must be false when padding contains non-zero bytes")
    }

    func testWrongVersionRejected() {
        var inner = bytes(realV18Hex)
        inner[1] = 20
        XCTAssertNil(V18Decoder.decode(inner))
    }

    func testTruncatedRecordRejected() {
        XCTAssertNil(V18Decoder.decode(Array(bytes(realV18Hex).prefix(60))))
    }

    func testOutOfRangeAccelDroppedOnly() {
        var inner = bytes(realV18Hex)
        let bits = Float(99.0).bitPattern
        inner[37] = UInt8(bits & 0xFF)
        inner[38] = UInt8((bits >> 8) & 0xFF)
        inner[39] = UInt8((bits >> 16) & 0xFF)
        inner[40] = UInt8((bits >> 24) & 0xFF)
        guard let sample = V18Decoder.decode(inner) else {
            return XCTFail("decode failed")
        }
        XCTAssertNil(sample.gravityXG)
        XCTAssertEqual(sample.heartRate, 94)
    }

    func testSleepStateIsOnlyBitsFourAndFive() {
        for (byte, expected) in [(0x00, 0), (0x10, 1), (0x20, 2), (0x30, 3), (0xFF, 3), (0xCF, 0)] {
            var inner = bytes(realV18Hex)
            inner[73] = UInt8(byte)
            let sample = V18Decoder.decode(inner)
            XCTAssertEqual(sample?.sleepStateByte, byte)
            XCTAssertEqual(sample?.sleepState, expected)
        }
    }

    func testSpo2CandidateTriMode() {
        XCTAssertEqual(V18Decoder.spo2Candidate(raw: 96).pct, 96)
        XCTAssertEqual(V18Decoder.spo2Candidate(raw: 96).kind, .pct)
        XCTAssertEqual(V18Decoder.spo2Candidate(raw: 0).kind, .absent)
        XCTAssertEqual(V18Decoder.spo2Candidate(raw: nil).kind, .absent)
        for sentinel in [0x80, 0xA0, 0xFF] {
            XCTAssertNil(V18Decoder.spo2Candidate(raw: sentinel).pct)
            XCTAssertEqual(V18Decoder.spo2Candidate(raw: sentinel).kind, .saturated)
        }
        for code in [1, 65, 69, 101, 127] {
            XCTAssertNil(V18Decoder.spo2Candidate(raw: code).pct)
            XCTAssertEqual(V18Decoder.spo2Candidate(raw: code).kind, .diagnostic)
        }
    }

    func testDecodeCarriesSpo2Candidate() {
        var inner = bytes(realV18Hex)
        inner[74] = 96
        let sample = V18Decoder.decode(inner)
        XCTAssertEqual(sample?.spo2CandidateRaw, 96)
        XCTAssertEqual(sample?.spo2CandidatePct, 96)
        XCTAssertEqual(sample?.spo2CandidateKind, Spo2CandidateKind.pct)
    }

    func testValidRRSurvivesWhenByte28Bit7IsUnset() {
        // Issue #126: In real physical WHOOP captures (32,663 records), byte 28 bit 7 is unset
        // for 100% of samples while 30,082 records contain valid RR data.
        // Valid RR intervals must NEVER be gated or discarded when inner[28] bit 7 is 0.
        var inner = bytes(realV18Hex)
        inner[28] = 0x0E // bit 7 unset (0x0E = 14, common historical capture value)
        inner[15] = 2
        let val1 = 818
        let val2 = 780
        inner[16] = UInt8(val1 & 0xFF)
        inner[17] = UInt8((val1 >> 8) & 0xFF)
        inner[18] = UInt8(val2 & 0xFF)
        inner[19] = UInt8((val2 >> 8) & 0xFF)
        inner[20] = 0; inner[21] = 0; inner[22] = 0; inner[23] = 0 // valid padding

        let sample = V18Decoder.decode(inner)
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.hrQualityFlags, 14)
        XCTAssertEqual(sample?.rrIntervalsMS, [818, 780], "Valid RR intervals must survive when byte 28 bit 7 is unset")
    }

    func testPSNRUnavailableSentinelDoesNotRejectSampleOrRR() {
        // Issue #126: psnrB / psnrA of -128 is an unavailable sentinel, not optical saturation.
        // It must be decoded as -128 without causing the sample or its RR intervals to be dropped.
        var inner = bytes(realV18Hex)
        inner[100] = 0x80 // -128
        inner[101] = 0x80 // -128
        inner[15] = 1
        inner[16] = 0x20; inner[17] = 0x03 // 800 ms
        inner[18] = 0; inner[19] = 0; inner[20] = 0; inner[21] = 0; inner[22] = 0; inner[23] = 0

        let sample = V18Decoder.decode(inner)
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.psnrB, -128)
        XCTAssertEqual(sample?.psnrA, -128)
        XCTAssertEqual(sample?.rrIntervalsMS, [800])
        XCTAssertEqual(sample?.heartRate, 94)
    }

    func testHistoricalRecordSelectionPrefersValidHR() {
        let baseHeader = BandRecordHeader(version: 18, flags: 0, recordIndex: 100, unix: 1700000000, subsecQ15: 0)
        let sampleBradycardia = V18Sample(
            header: baseHeader,
            heartRate: 28, // Valid HR within 25...230
            rrIntervalsMS: [],
            dynamicAccelG: nil,
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
        let sampleZeroHR = V18Sample(
            header: baseHeader,
            heartRate: 0, // Invalid/absent HR
            rrIntervalsMS: [800],
            dynamicAccelG: 0.05,
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

        // Valid resting bradycardia HR (28 bpm) is preferred over zero HR
        XCTAssertTrue(HistoricalRecordSelection.prefers(sampleBradycardia, over: sampleZeroHR))
        XCTAssertFalse(HistoricalRecordSelection.prefers(sampleZeroHR, over: sampleBradycardia))
    }
}

// MARK: - Standard heart-rate profile (0x2A37)

final class StandardHeartRateTests: XCTestCase {
    private func parse(_ bytes: [UInt8]) -> (heartRate: Int, rrMS: [Int])? {
        StandardHeartRate.parse(Data(bytes))
    }

    func testUInt8HeartRateAlone() {
        let reading = parse([0x00, 72])
        XCTAssertEqual(reading?.heartRate, 72)
        XCTAssertEqual(reading?.rrMS, [])
    }

    func testUInt16HeartRate() {
        // Flags bit0: HR is two bytes. 0x012C == 300.
        XCTAssertEqual(parse([0x01, 0x2C, 0x01])?.heartRate, 300)
    }

    func testUInt16FlagWithoutSecondByteRejected() {
        XCTAssertNil(parse([0x01, 0x2C]))
        XCTAssertNil(parse([0x00]))
        XCTAssertNil(parse([]))
    }

    func testEnergyExpendedIsSkipped() {
        // bit3: two bytes of energy expended between HR and R-R.
        XCTAssertEqual(parse([0x08, 65, 0x10, 0x00])?.heartRate, 65)
        XCTAssertEqual(parse([0x08, 65, 0x10, 0x00])?.rrMS, [])
    }

    func testRRIntervalsUse1024thSecond() {
        // 1024 raw units == exactly 1000 ms; 840 units == ~820 ms.
        let reading = parse([0x10, 60, 0x00, 0x04, 0x48, 0x03])
        XCTAssertEqual(reading?.heartRate, 60)
        XCTAssertEqual(reading?.rrMS, [1000, 820])
    }

    func testImplausibleRRIsDroppedNotTheReading() {
        // 100 units ≈ 98 ms and 4000 units ≈ 3906 ms sit outside 200…3000.
        let reading = parse([0x10, 58, 64, 0x00, 0xA0, 0x0F, 0x00, 0x04])
        XCTAssertEqual(reading?.heartRate, 58)
        XCTAssertEqual(reading?.rrMS, [1000])
    }

    func testOddTrailingByteIsIgnored() {
        XCTAssertEqual(parse([0x10, 60, 0x00, 0x04, 0x99])?.rrMS, [1000])
    }

    func testCombinedFlags() {
        // uint16 HR + energy expended + R-R.
        let reading = parse([0x19, 0x2C, 0x00, 0x20, 0x00, 0x00, 0x04])
        XCTAssertEqual(reading?.heartRate, 44)
        XCTAssertEqual(reading?.rrMS, [1000])
    }
}

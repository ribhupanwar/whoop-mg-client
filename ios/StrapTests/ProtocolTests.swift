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

    func testRRCountAboveFourIsIgnored() {
        var inner = bytes(realV18Hex)
        inner[15] = 9
        XCTAssertEqual(V18Decoder.decode(inner)?.rrIntervalsMS, [])
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
}

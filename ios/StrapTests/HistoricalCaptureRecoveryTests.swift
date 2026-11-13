import XCTest
@testable import Strap

final class HistoricalCaptureRecoveryTests: XCTestCase {
    private func row(hr: UInt8 = 67, rr: Int = 900, count: UInt8 = 1) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 112)
        bytes[0] = 0x2F; bytes[1] = 18
        bytes[7] = 100
        bytes[14] = hr; bytes[15] = count
        bytes[16] = UInt8(rr & 255); bytes[17] = UInt8(rr >> 8)
        bytes[18] = bytes[16]; bytes[19] = bytes[17]
        return try JSONSerialization.data(withJSONObject: ["frame": ["inner": bytes.map { String(format: "%02x", $0) }.joined()]])
    }

    func testRecoversSavedFramesAfterInterruptedSync() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var capture = Data("{\"chunk\":\"aa\"}\n".utf8)
        capture.append(try row()); capture.append(Data("\n{\"frame\":".utf8))
        try capture.write(to: directory.appendingPathComponent("capture.jsonl"))
        let recovered = HistoricalCaptureRecovery.read(directory: directory)
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.heartRate, 67)
        XCTAssertEqual(recovered.first?.rrIntervalsMS, [900])
    }

    func testRawNotificationChunksRecoverRecordsMissingFromOldFrameParser() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = try XCTUnwrap(HistoricalCaptureRecovery.decodeLine(row()))
        var inner = [UInt8](repeating: 0, count: 112)
        inner[0] = 0x2F; inner[1] = 18; inner[7] = 100; inner[14] = 67
        var corrupt = Gen5Frame.build([1, 2, 3, 4])
        corrupt[2] = 0; corrupt[3] = 0xF0
        let frame = corrupt + Gen5Frame.build(inner)
        var content = Data()
        for part in [Array(frame.prefix(25)), Array(frame.dropFirst(25))] {
            let line = try JSONSerialization.data(withJSONObject: [
                "uuid": "history", "chunk": part.map { String(format: "%02x", $0) }.joined()
            ])
            content.append(line); content.append(0x0A)
        }
        try content.write(to: directory.appendingPathComponent("raw.jsonl"))
        let recovered = HistoricalCaptureRecovery.read(directory: directory)
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.heartRate, sample.heartRate)
        XCTAssertEqual(recovered.first?.unix, sample.unix)
    }

    func testReplayNeverLetsInvalidHRReplaceValidHRWithMoreRR() throws {
        let valid = try XCTUnwrap(HistoricalCaptureRecovery.decodeLine(row()))
        let invalid = try XCTUnwrap(HistoricalCaptureRecovery.decodeLine(row(hr: 0, count: 2)))
        XCTAssertEqual(HistoricalCaptureRecovery.merged([valid, invalid])[100]?.heartRate, 67)
        XCTAssertEqual(HistoricalCaptureRecovery.merged([invalid, valid])[100]?.heartRate, 67)
    }

    func testMalformedRowsNeverInventSamples() {
        for text in ["{}", "{", "{\"frame\":{\"inner\":\"xyz\"}}", "{\"frame\":{\"inner\":\"2f12\"}}"] {
            XCTAssertNil(HistoricalCaptureRecovery.decodeLine(Data(text.utf8)))
        }
    }
}

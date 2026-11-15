import Foundation
import XCTest
@testable import Strap

final class CaptureWriterTests: XCTestCase {
    func testBulkCaptureIsDurableBeforeFlushCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try XCTUnwrap(CaptureWriter(directory: directory))
        let bytes = Array(UInt8.min...UInt8.max)
        for _ in 0..<2000 {
            writer.chunk(Data(bytes), uuid: "test")
            writer.frame(bytes, uuid: "test")
        }
        let saved = expectation(description: "All queued records synced before ACK")
        writer.flushToDisk { success in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(success)
            do {
                let lines = try Data(contentsOf: writer.url).split(separator: 0x0A)
                XCTAssertEqual(lines.count, 4000)
                for index in stride(from: 0, to: lines.count, by: 2) {
                    let chunk = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[index])) as? [String: Any])
                    let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[index + 1])) as? [String: Any])
                    let frame = try XCTUnwrap(row["frame"] as? [String: Any])
                    let hex = try XCTUnwrap(chunk["chunk"] as? String)
                    XCTAssertEqual(hex.count, 512)
                    XCTAssertTrue(hex.hasPrefix("00010203"))
                    XCTAssertTrue(hex.hasSuffix("fcfdfeff"))
                    XCTAssertEqual(frame["inner"] as? String, hex)
                    XCTAssertEqual(frame["len"] as? Int, 256)
                }
            } catch { XCTFail("Unreadable durable capture: \(error)") }
            saved.fulfill()
        }
        wait(for: [saved], timeout: 30)
        writer.close()
    }

    func testCloseDrainsQueuedRecordsAndRefusesFurtherACK() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try XCTUnwrap(CaptureWriter(directory: directory))
        for _ in 0..<100 { writer.chunk(Data([0, 255]), uuid: "test") }
        writer.close()
        let closed = expectation(description: "Closed capture cannot release a trim cursor")
        writer.flushToDisk { success in
            XCTAssertFalse(success)
            do {
                let data = try Data(contentsOf: writer.url)
                XCTAssertEqual(data.split(separator: 0x0A).count, 100)
            } catch { XCTFail("Close lost queued data: \(error)") }
            closed.fulfill()
        }
        wait(for: [closed], timeout: 10)
    }

    func testCaptureContinuesAfterCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try XCTUnwrap(CaptureWriter(directory: directory))
        writer.chunk(Data([1]), uuid: "test")
        let checkpoint = expectation(description: "Checkpoint preserves open writer")
        writer.flushToDisk { success in
            XCTAssertTrue(success)
            writer.chunk(Data([2]), uuid: "test")
            writer.flushToDisk { success in
                XCTAssertTrue(success)
                do {
                    let data = try Data(contentsOf: writer.url)
                    XCTAssertEqual(data.split(separator: 0x0A).count, 2)
                } catch { XCTFail("Checkpoint lost subsequent records: \(error)") }
                checkpoint.fulfill()
            }
        }
        wait(for: [checkpoint], timeout: 10)
        writer.close()
    }
}

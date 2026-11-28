import XCTest
@testable import Strap

final class FirmwareImageLabTests: XCTestCase {
    func testFingerprintAndBounds() throws {
        let image = try FirmwareImageInspection(name: "sample", data: Data("abc".utf8))
        XCTAssertEqual(image.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(image.chunkCount, 1)
        XCTAssertThrowsError(try FirmwareImageInspection(name: "empty", data: Data()))
        XCTAssertThrowsError(try FirmwareImageInspection(name: "oversize",
            data: Data(count: FirmwareImageInspection.maximumBytes + 1)))
    }

    func testLocalFileInspection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try FirmwareImageInspection.inspect(url).byteCount, 3)
    }

    func testSyntheticTransferAndUnknownCommitCannotRetry() throws {
        let image = try FirmwareImageInspection(name: "dummy", data: Data(count: 129))
        var run = FirmwareDryRun(image: image)
        XCTAssertFalse(run.start(simulatedBattery: nil, simulatedReady: true))
        XCTAssertFalse(run.start(simulatedBattery: 49, simulatedReady: true))
        XCTAssertFalse(run.start(simulatedBattery: 100, simulatedReady: false))
        XCTAssertTrue(run.start(simulatedBattery: 50, simulatedReady: true))
        run.commit(confirmed: true, reply: .accepted)
        XCTAssertEqual(run.phase, .staging)
        XCTAssertTrue(run.acknowledgeChunk(offset: 0, count: 128, accepted: true))
        XCTAssertTrue(run.acknowledgeChunk(offset: 128, count: 1, accepted: true))
        XCTAssertEqual(run.phase, .awaitingVerification)
        run.verify(simulatedAcceptance: true)
        run.commit(confirmed: false, reply: .accepted)
        XCTAssertEqual(run.phase, .verified)
        run.commit(confirmed: true, reply: .unknown)
        run.commit(confirmed: true, reply: .accepted)
        XCTAssertEqual(run.phase, .commitUnknown)
        XCTAssertFalse(run.start(simulatedBattery: 100, simulatedReady: true))
    }

    func testOutOfOrderAndCancelledTransferAreTerminal() throws {
        let image = try FirmwareImageInspection(name: "dummy", data: Data(count: 129))
        var run = FirmwareDryRun(image: image)
        XCTAssertTrue(run.start(simulatedBattery: 80, simulatedReady: true))
        XCTAssertFalse(run.acknowledgeChunk(offset: 1, count: 128, accepted: true))
        XCTAssertEqual(run.phase, .failed)
        var cancelled = FirmwareDryRun(image: image)
        XCTAssertTrue(cancelled.start(simulatedBattery: 80, simulatedReady: true))
        cancelled.cancel()
        XCTAssertEqual(cancelled.phase, .failed)
        XCTAssertFalse(cancelled.acknowledgeChunk(offset: 0, count: 128, accepted: true))
    }
}

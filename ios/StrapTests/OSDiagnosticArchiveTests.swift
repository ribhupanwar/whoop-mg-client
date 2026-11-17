import XCTest
@testable import Strap

final class OSDiagnosticArchiveTests: XCTestCase {
    func testOriginalOSJSONRepeatAndDistinctPayloadsArePreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = Data("{\"syntheticTest\":1}".utf8), two = Data("{\"syntheticTest\":2}".utf8)
        try OSDiagnosticArchive.preserve(one, kind: "diagnostics", directory: folder)
        try OSDiagnosticArchive.preserve(one, kind: "diagnostics", directory: folder)
        try OSDiagnosticArchive.preserve(two, kind: "metrics", directory: folder)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(try files.map { try Data(contentsOf: $0) }), Set([one, two]))
        XCTAssertThrowsError(try OSDiagnosticArchive.preserve(Data("broken".utf8), kind: "diagnostics", directory: folder))
        XCTAssertThrowsError(try OSDiagnosticArchive.preserve(one, kind: "../escape", directory: folder))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }
    func testConflictingExistingEvidenceIsNeverReplaced() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = Data("{\"syntheticTest\":1}".utf8), retained = Data("existing evidence".utf8)
        let file = folder.appendingPathComponent("metrics-" + PersistenceDiagnostics.digest(original) + ".json")
        try retained.write(to: file)
        XCTAssertThrowsError(try OSDiagnosticArchive.preserve(original, kind: "metrics", directory: folder))
        XCTAssertEqual(try Data(contentsOf: file), retained)
    }
}

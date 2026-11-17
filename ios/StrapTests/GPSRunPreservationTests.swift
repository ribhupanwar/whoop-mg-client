import XCTest
@testable import Strap

final class GPSRunPreservationTests: XCTestCase {
    private func run(id: UUID = UUID(), distance: Double = 100) -> GPSRunRecord {
        GPSRunRecord(id: id, startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
                     movingSeconds: 90, distanceMeters: distance, splitSeconds: [],
                     route: [.init(latitude: 0, longitude: 0, unix: 100, accuracyMeters: 5)])
    }
    func testGPSMigrationEditDeleteAndMissingOnlyRestoreRetainEveryOriginal() throws {
        let suite = "GPSPreserve-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = run(), legacy = try JSONEncoder().encode([original])
        defaults.set(legacy, forKey: "strap.gps.runs.v1")
        let history = GPSRunHistory(defaults: defaults, directory: folder)
        XCTAssertEqual(history.all(), [original]); XCTAssertEqual(defaults.data(forKey: "strap.gps.runs.v1"), legacy)
        let edited = run(id: original.id, distance: 200)
        XCTAssertTrue(history.save(edited)); XCTAssertFalse(try history.restoreMissing(original))
        XCTAssertEqual(history.all(), [edited])
        XCTAssertTrue(history.delete(id: original.id)); XCTAssertTrue(history.all().isEmpty)
        let originals = try FileManager.default.contentsOfDirectory(at: history.revisionDirectory, includingPropertiesForKeys: nil)
            .map { try JSONDecoder().decode([GPSRunRecord].self, from: Data(contentsOf: $0)) }
        XCTAssertTrue(originals.contains([original])); XCTAssertTrue(originals.contains([edited]))
        XCTAssertTrue(try history.restoreMissing(original)); XCTAssertEqual(history.all(), [original])
    }
    func testCorruptNewGPSFileCannotBeReplacedByLegacyOrNewRun() throws {
        let suite = "GPSBad-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Strap/gps-runs-v2.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data("unreadable current source".utf8); try bad.write(to: file)
        let legacy = try JSONEncoder().encode([run()]); defaults.set(legacy, forKey: "strap.gps.runs.v1")
        let history = GPSRunHistory(defaults: defaults, directory: folder), incoming = run()
        XCTAssertTrue(history.all().isEmpty); XCTAssertFalse(history.save(incoming)); XCTAssertFalse(history.delete(id: incoming.id))
        XCTAssertEqual(try Data(contentsOf: file), bad); XCTAssertEqual(defaults.data(forKey: "strap.gps.runs.v1"), legacy)
        let files = try FileManager.default.contentsOfDirectory(at: history.revisionDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(try files.map { try JSONDecoder().decode([GPSRunRecord].self, from: Data(contentsOf: $0)) }.contains([incoming]))
    }
}

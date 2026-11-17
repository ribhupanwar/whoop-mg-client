import XCTest
@testable import Strap

final class AppleHealthSourceImportTests: XCTestCase {
    func testRepeatUUIDIsByteIdempotentAndOriginalSourceWinsWithoutGuessMergingDifferentUUIDs() throws {
        let suite = "HealthSources-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        func row(_ id: UUID, source: String = "watch.original", value: Double = 40) -> AppleHealthImport.Record {
            .init(id: id, type: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", sourceBundle: source,
                  startUnix: 100, endUnix: 120, timezone: "UTC", values: ["value": value], unit: "ms SDNN")
        }
        XCTAssertEqual(try AppleHealthImport.merge([row(id)], defaults: defaults), 1)
        let before = defaults.data(forKey: AppleHealthImport.key)
        XCTAssertEqual(try AppleHealthImport.merge([row(id, source: "mirror", value: 99)], defaults: defaults), 0)
        XCTAssertEqual(defaults.data(forKey: AppleHealthImport.key), before)
        XCTAssertEqual(try AppleHealthImport.load(defaults: defaults).first?.sourceBundle, "watch.original")
        XCTAssertEqual(try AppleHealthImport.merge([row(UUID())], defaults: defaults), 1,
                       "A distinct UUID cannot be silently collapsed merely because time and value match")
        XCTAssertEqual(try AppleHealthImport.load(defaults: defaults).count, 2)
        XCTAssertEqual(try AppleHealthImport.load(defaults: defaults).first?.unit, "ms SDNN")
    }
    func testBadOriginalBytesOrUnencodableNewSampleNeverReplacesExistingStorage() throws {
        let suite = "HealthSourcesBad-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bad = Data("retained unreadable original".utf8)
        defaults.set(bad, forKey: AppleHealthImport.key)
        XCTAssertThrowsError(try AppleHealthImport.merge([], defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: AppleHealthImport.key), bad)
        defaults.removeObject(forKey: AppleHealthImport.key)
        let row = AppleHealthImport.Record(id: UUID(), type: "HR", sourceBundle: "synthetic", startUnix: 100,
                                          endUnix: 101, timezone: nil, values: ["value": .nan], unit: "bpm")
        XCTAssertThrowsError(try AppleHealthImport.merge([row], defaults: defaults))
        XCTAssertNil(defaults.data(forKey: AppleHealthImport.key))
    }
}

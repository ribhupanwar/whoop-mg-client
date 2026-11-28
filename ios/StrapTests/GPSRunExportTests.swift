import XCTest
import Foundation
@testable import Strap

final class GPSRunExportTests: XCTestCase {
    private var run: GPSRunRecord {
        GPSRunRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            startedAt: Date(timeIntervalSince1970: 1_762_000_000),
            endedAt: Date(timeIntervalSince1970: 1_762_000_030.5), movingSeconds: 20, distanceMeters: 111.2,
            splitSeconds: [], route: [
                GPSRunPoint(latitude: 0, longitude: 0, unix: 1_762_000_000.125, accuracyMeters: 2),
                GPSRunPoint(latitude: 0, longitude: 0.001, unix: 1_762_000_010.375, accuracyMeters: 3)])
    }
    func testGPXPreservesRecordedFixesAndExactOriginalTimeWithoutInterpolation() throws {
        let data = try GPSRunExport.render(run, format: .gpx, name: "A < B & C")
        let collector = GPXCollector()
        let parser = XMLParser(data: data); parser.shouldProcessNamespaces = true; parser.delegate = collector
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "")
        XCTAssertEqual(collector.coordinates.count, 2)
        XCTAssertEqual(collector.coordinates.map { Double($0.1) }, run.route.map { Optional($0.longitude) })
        XCTAssertEqual(collector.originalUnix, run.route.map(\.unix))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(xml.contains("A &lt; B &amp; C"))
        XCTAssertFalse(xml.contains("<ele>"))
        XCTAssertFalse(xml.contains("<heart"))
        XCTAssertFalse(xml.contains("calories"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.xml")
        attachment.name = "STRAP-synthetic-recorded-route.gpx"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testFITHasIndependentKnownCRCAndExportsFixtureForThirdPartyDecoder() throws {
        XCTAssertEqual(GPSRunExport.crc16(Data("123456789".utf8)), 0xBB3D, "Published CRC-16/ARC check vector")
        let bytes = try GPSRunExport.render(run, format: .fit)
        XCTAssertEqual(bytes[0], 14)
        XCTAssertEqual(String(data: bytes[8..<12], encoding: .ascii), ".FIT")
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.data")
        attachment.name = "STRAP-synthetic-recorded-route.fit"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testInvalidOrUnorderedCoordinatesNeverBecomeInventedRoutePoints() {
        var invalid = run
        invalid = GPSRunRecord(id: invalid.id, startedAt: invalid.startedAt, endedAt: invalid.endedAt,
            movingSeconds: invalid.movingSeconds, distanceMeters: invalid.distanceMeters, splitSeconds: [],
            route: [GPSRunPoint(latitude: .nan, longitude: 0, unix: 1_762_000_000, accuracyMeters: 2), run.route[1]])
        XCTAssertThrowsError(try GPSRunExport.render(invalid, format: .gpx))
        let reversed = GPSRunRecord(id: run.id, startedAt: run.startedAt, endedAt: run.endedAt,
            movingSeconds: run.movingSeconds, distanceMeters: run.distanceMeters, splitSeconds: [], route: Array(run.route.reversed()))
        XCTAssertThrowsError(try GPSRunExport.render(reversed, format: .fit))
    }
    func testExportRejectsMovingDurationLongerThanWorkoutWithoutChangingRecord() {
        let impossible = GPSRunRecord(id: run.id, startedAt: run.startedAt, endedAt: run.endedAt,
            movingSeconds: 31, distanceMeters: run.distanceMeters, splitSeconds: [],
            route: run.route)
        XCTAssertThrowsError(try GPSRunExport.render(impossible, format: .gpx))
        XCTAssertThrowsError(try GPSRunExport.render(impossible, format: .fit))
        XCTAssertNoThrow(try GPSRunExport.render(run, format: .gpx))
        XCTAssertNoThrow(try GPSRunExport.render(run, format: .fit))
    }
    func testFITRejectsEpochAndIntegerOverflowWhileGPXKeepsValidRawCoordinates() {
        let old = GPSRunRecord(id: run.id, startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
            movingSeconds: 80, distanceMeters: 100, splitSeconds: [], route: [
                GPSRunPoint(latitude: 0, longitude: 0, unix: 100, accuracyMeters: 2),
                GPSRunPoint(latitude: 0, longitude: 0.001, unix: 200, accuracyMeters: 2)])
        XCTAssertThrowsError(try GPSRunExport.render(old, format: .fit))
        XCTAssertNoThrow(try GPSRunExport.render(old, format: .gpx))
    }
}

private final class GPXCollector: NSObject, XMLParserDelegate {
    var coordinates: [(String, String)] = []
    var originalUnix: [Double] = []
    private var text = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        text = ""
        if elementName == "trkpt", let lat = attributeDict["lat"], let lon = attributeDict["lon"] { coordinates.append((lat, lon)) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "originalUnix", let value = Double(text) { originalUnix.append(value) }
        text = ""
    }
}


final class StravaTCXExportTests: XCTestCase {
    private func workout() -> WorkoutSession {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return WorkoutSession(id: UUID(), activityKind: "running", activityLabel: "Running",
            startedAt: start, endedAt: start.addingTimeInterval(60), phase: .saved,
            metrics: WorkoutMetrics(elapsedSeconds: 60, distanceMeters: 120, averageHeartRate: 135),
            route: [], hasGPS: false)
    }

    func testIndoorHRAndMissingGPS() throws {
        var w = workout()
        w.exportHeartRate = [.init(unix: w.startedAt.timeIntervalSince1970 + 1, bpm: 135)]
        let data = try StravaTCXExport.render(w)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(XMLParser(data: data).parse())
        XCTAssertTrue(xml.contains("Sport=\"Running\""))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>135</Value></HeartRateBpm>"))
        XCTAssertFalse(xml.contains("<Position>"))
        XCTAssertFalse(xml.contains("<Calories>"))
    }

    func testOldWorkoutWithoutTrackIsRejected() {
        XCTAssertThrowsError(try StravaTCXExport.render(workout()))
    }

    func testRouteAndExactTimestampHRDeduplicate() throws {
        var w = workout()
        let time = w.startedAt.timeIntervalSince1970 + 2
        w.route = [.init(latitude: 28.5, longitude: 77.2, unix: time, accuracyMeters: 5, heartRate: nil)]
        w.exportHeartRate = [.init(unix: time, bpm: 142), .init(unix: time, bpm: 142)]
        let xml = String(decoding: try StravaTCXExport.render(w), as: UTF8.self)
        XCTAssertTrue(xml.contains("<LatitudeDegrees>28.5</LatitudeDegrees>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>142</Value></HeartRateBpm>"))
        XCTAssertEqual(xml.components(separatedBy: "<Trackpoint>").count, 2)
    }

    func testLegacyWorkoutDecodesWithoutOptionalExportHeartRate() throws {
        let old = workout()
        let data = try JSONEncoder().encode(old)
        XCTAssertNil(try JSONDecoder().decode(WorkoutSession.self, from: data).exportHeartRate)
    }
}

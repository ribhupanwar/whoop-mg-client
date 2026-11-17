import Foundation

/// Independent GPX/FIT writer from measured GPSRunRecord fields. No route-time
/// interpolation and no fabricated HR, elevation, cadence or calories.
enum GPSRunExport {
    enum Format: String { case gpx, fit }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static let fitEpoch: Double = 631_065_600
    static func validate(_ run: GPSRunRecord) throws {
        guard run.route.count >= 2, run.route.count <= 1_000_000,
              run.startedAt.timeIntervalSince1970.isFinite, run.endedAt.timeIntervalSince1970.isFinite,
              run.endedAt > run.startedAt, run.movingSeconds >= 0,
              run.distanceMeters.isFinite, run.distanceMeters >= 0 else {
            throw Failure(message: "A recorded route with valid workout bounds is required.")
        }
        var previous: Double?
        for point in run.route {
            guard point.latitude.isFinite, (-90...90).contains(point.latitude),
                  point.longitude.isFinite, (-180...180).contains(point.longitude), point.unix.isFinite,
                  previous.map({ point.unix > $0 }) ?? true else {
                throw Failure(message: "Route has invalid coordinates or unordered timestamps; original record preserved.")
            }
            previous = point.unix
        }
    }
    static func render(_ run: GPSRunRecord, format: Format, name: String = "STRAP recorded run") throws -> Data {
        try validate(run)
        switch format {
        case .gpx: return gpx(run, name: name)
        case .fit: return try fit(run)
        }
    }
    static func write(_ run: GPSRunRecord, format: Format, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let data = try render(run, format: format)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("STRAP-run-\(run.id.uuidString)-\(UUID().uuidString).\(format.rawValue)")
        try data.write(to: url, options: .atomic)
        return url
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    private static func gpx(_ run: GPSRunRecord, name: String) -> Data {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"STRAP\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:strap=\"https://github.com/ribhupanwar/whoop-mg-client/gpx\">\n"
        xml += "<metadata><time>\(iso.string(from: run.startedAt))</time></metadata>\n"
        xml += "<trk><name>\(escape(name))</name><type>running</type><extensions><strap:sourceID>\(run.id.uuidString)</strap:sourceID></extensions><trkseg>\n"
        for point in run.route {
            xml += "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>\(iso.string(from: Date(timeIntervalSince1970: point.unix)))</time><extensions>"
            // Preserve the exact original Double alongside standard ISO time,
            // whose formatter representation may round submillisecond precision.
            xml += "<strap:originalUnix>\(point.unix)</strap:originalUnix>"
            if point.accuracyMeters.isFinite, point.accuracyMeters > 0 {
                xml += "<strap:horizontalAccuracyMeters>\(point.accuracyMeters)</strap:horizontalAccuracyMeters>"
            }
            xml += "</extensions></trkpt>\n"
        }
        xml += "</trkseg></trk></gpx>\n"
        return Data(xml.utf8)
    }
    private struct Field { let number: UInt8; let size: UInt8; let base: UInt8 }
    private static func append<T: FixedWidthInteger>(_ value: T, to bytes: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
    }
    private static func definition(_ local: UInt8, global: UInt16, fields: [Field], to data: inout Data) {
        data.append(0x40 | local); data.append(0); data.append(0)
        append(global, to: &data); data.append(UInt8(fields.count))
        for field in fields { data.append(contentsOf: [field.number, field.size, field.base]) }
    }
    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }
    private static func fitTime(_ unix: Double) throws -> UInt32 {
        let value = floor(unix - fitEpoch)
        guard value.isFinite, value >= 0, value < Double(UInt32.max) else { throw Failure(message: "Timestamp is outside FIT's supported epoch range.") }
        return UInt32(value)
    }
    private static func scaled(_ value: Double, factor: Double) throws -> UInt32 {
        let result = (value * factor).rounded()
        guard result.isFinite, result >= 0, result < Double(UInt32.max) else { throw Failure(message: "Recorded value exceeds FIT's field range.") }
        return UInt32(result)
    }
    private static func coordinate(_ degrees: Double) -> Int32 {
        let value = (degrees * 2_147_483_648 / 180).rounded()
        // The +180 meridian is the same location as -180. Avoid FIT's
        // reserved sint32 invalid sentinel at the positive endpoint.
        if value >= Double(Int32.max) { return Int32.min }
        return Int32(value)
    }
    private static func fit(_ run: GPSRunRecord) throws -> Data {
        let start = try fitTime(run.startedAt.timeIntervalSince1970)
        let end = try fitTime(run.endedAt.timeIntervalSince1970)
        let elapsed = try scaled(run.endedAt.timeIntervalSince(run.startedAt), factor: 1000)
        let moving = try scaled(Double(run.movingSeconds), factor: 1000)
        let distance = try scaled(run.distanceMeters, factor: 100)
        var body = Data()
        definition(0, global: 0, fields: [.init(number: 0, size: 1, base: 0), .init(number: 1, size: 2, base: 0x84), .init(number: 4, size: 4, base: 0x86)], to: &body)
        body.append(0); body.append(4); append(UInt16(255), to: &body); append(start, to: &body)
        definition(1, global: 20, fields: [.init(number: 253, size: 4, base: 0x86), .init(number: 0, size: 4, base: 0x85), .init(number: 1, size: 4, base: 0x85), .init(number: 48, size: 1, base: 0x02)], to: &body)
        for point in run.route {
            var seconds = try fitTime(point.unix)
            var fractional = Int(((point.unix - floor(point.unix)) * 128).rounded())
            if fractional == 128 {
                guard seconds < UInt32.max - 1 else { throw Failure(message: "FIT timestamp overflow.") }
                seconds += 1; fractional = 0
            }
            body.append(1); append(seconds, to: &body)
            append(coordinate(point.latitude), to: &body); append(coordinate(point.longitude), to: &body)
            body.append(UInt8(fractional))
        }
        let lap: [Field] = [.init(number: 253, size: 4, base: 0x86), .init(number: 2, size: 4, base: 0x86), .init(number: 7, size: 4, base: 0x86), .init(number: 8, size: 4, base: 0x86), .init(number: 9, size: 4, base: 0x86)]
        definition(2, global: 19, fields: lap, to: &body)
        body.append(2); for value in [end, start, elapsed, moving, distance] { append(value, to: &body) }
        definition(3, global: 18, fields: lap + [.init(number: 5, size: 1, base: 0)], to: &body)
        body.append(3); for value in [end, start, elapsed, moving, distance] { append(value, to: &body) }; body.append(1)
        definition(4, global: 34, fields: [.init(number: 253, size: 4, base: 0x86), .init(number: 0, size: 4, base: 0x86), .init(number: 1, size: 2, base: 0x84), .init(number: 2, size: 1, base: 0)], to: &body)
        body.append(4); append(end, to: &body); append(moving, to: &body); append(UInt16(1), to: &body); body.append(0)
        // Standard FIT 2.0 header, profile 21.171 (field definitions verified
        // against the independently generated fitdecode profile).
        var file = Data([14, 0x20]); append(UInt16(21171), to: &file); append(UInt32(body.count), to: &file)
        file.append(contentsOf: [0x2E, 0x46, 0x49, 0x54]); append(crc16(file), to: &file)
        file.append(body); append(crc16(file), to: &file)
        return file
    }
}

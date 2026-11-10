import Foundation

/// Writes the same JSONL the Python session driver writes, so a capture pulled
/// off the phone decodes with `decode.py` unchanged: raw notification chunks
/// plus one reassembled frame per record.
final class CaptureWriter {
    let url: URL

    private let handle: FileHandle
    private let started = Date()
    private let queue = DispatchQueue(label: "com.ribhupanwar.strap.capture")
    private var isClosed = false

    init?() {
        let manager = FileManager.default
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = documents.appendingPathComponent("captures", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent(
            "capture-\(formatter.string(from: Date())).jsonl"
        )
        guard manager.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { return nil }
        self.url = url
        self.handle = handle
    }

    func chunk(_ chunk: Data, uuid: String) {
        record(["t": elapsed, "uuid": uuid, "chunk": Self.hex([UInt8](chunk))])
    }

    func frame(_ inner: [UInt8], uuid: String) {
        let frame: [String: Any] = [
            "t": elapsed,
            "uuid": uuid,
            "packet_type": inner.first.map { Int($0) } ?? NSNull(),
            "seq": inner.count > 1 ? Int(inner[1]) : NSNull(),
            "opcode": inner.count > 2 ? Int(inner[2]) : NSNull(),
            "len": inner.count,
            "inner": Self.hex(inner)
        ]
        record(["frame": frame])
    }

    func close() {
        queue.sync {
            guard !isClosed else { return }
            isClosed = true
            try? handle.close()
        }
    }

    private var elapsed: Double {
        (Date().timeIntervalSince(started) * 10_000).rounded() / 10_000
    }

    private func record(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let line = data + Data([0x0A])
        queue.async { [handle] in
            try? handle.write(contentsOf: line)
        }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

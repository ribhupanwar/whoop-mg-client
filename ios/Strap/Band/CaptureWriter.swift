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
    private var writeFailed = false
    private var buffer = Data()
    private static let bufferLimit = 64 * 1024

    init?(directory: URL? = nil) {
        let manager = FileManager.default
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = directory ?? documents.appendingPathComponent("captures", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent(
            "capture-\(formatter.string(from: Date()))-\(UUID().uuidString).jsonl"
        )
        guard manager.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { return nil }
        self.url = url
        self.handle = handle
    }

    func chunk(_ chunk: Data, uuid: String) {
        let time = elapsed
        queue.async {
            self.record(["t": time, "uuid": uuid, "chunk": Self.hex([UInt8](chunk))])
        }
    }

    func frame(_ inner: [UInt8], uuid: String) {
        let time = elapsed
        queue.async {
            let frame: [String: Any] = [
                "t": time,
                "uuid": uuid,
                "packet_type": inner.first.map { Int($0) } ?? NSNull(),
                "seq": inner.count > 1 ? Int(inner[1]) : NSNull(),
                "opcode": inner.count > 2 ? Int(inner[2]) : NSNull(),
                "len": inner.count,
                "inner": Self.hex(inner)
            ]
            self.record(["frame": frame])
        }
    }

    /// Drain queued writes and sync the raw capture before acknowledging a
    /// HISTORY_END trim cursor. A failed sync must not release strap history.
    func flushToDisk(completion: @escaping (Bool) -> Void) {
        queue.async {
            var saved = false
            if !self.isClosed && !self.writeFailed {
                do {
                    try self.writeBuffer()
                    try self.handle.synchronize()
                    saved = true
                } catch {
                    self.writeFailed = true
                }
            }
            let result = saved
            DispatchQueue.main.async { completion(result) }
        }
    }

    func close() {
        queue.async {
            guard !self.isClosed else { return }
            do {
                try self.writeBuffer()
                try self.handle.synchronize()
            } catch { self.writeFailed = true }
            self.isClosed = true
            try? self.handle.close()
        }
    }

    private var elapsed: Double {
        (Date().timeIntervalSince(started) * 10_000).rounded() / 10_000
    }

    private func record(_ object: [String: Any]) {
        // Only the serial writer touches encoding, the buffer or the file.
        // BLE callbacks enqueue raw values and return immediately.
        guard !isClosed, !writeFailed else { writeFailed = true; return }
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            buffer.append(data)
            buffer.append(0x0A)
            if buffer.count >= Self.bufferLimit { try writeBuffer() }
        } catch { writeFailed = true }
    }

    private func writeBuffer() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: result, as: UTF8.self)
    }
}

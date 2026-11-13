import Foundation

/// Rebuild the usable archive from raw JSONL already saved before trim ACKs.
/// No missing samples or beats are synthesized. Replays choose one whole record.
enum HistoricalCaptureRecovery {
    static func merged(_ samples: [V18Sample]) -> [Int: V18Sample] {
        var result: [Int: V18Sample] = [:]
        for sample in samples {
            if let old = result[sample.unix],
               !HistoricalRecordSelection.prefers(sample, over: old) { continue }
            result[sample.unix] = sample
        }
        return result
    }

    static func decodeLine(_ data: Data) -> V18Sample? {
        guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frame = row["frame"] as? [String: Any],
              let hex = frame["inner"] as? String,
              let bytes = decodeHex(hex) else { return nil }
        return V18Decoder.decode(bytes)
    }

    private static func decodeHex(_ hex: String) -> [UInt8]? {
        guard hex.count <= 4096, hex.count.isMultiple(of: 2) else { return nil }
        let chars = Array(hex.utf8)
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let value = UInt8(String(bytes: chars[index..<(index + 2)], encoding: .utf8) ?? "", radix: 16)
            else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    private static func samples(in line: Data, reassemblers: inout [String: FrameReassembler]) -> [V18Sample] {
        if let decoded = decodeLine(line) { return [decoded] }
        guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let hex = row["chunk"] as? String, let bytes = decodeHex(hex),
              let uuid = row["uuid"] as? String else { return [] }
        let reassembler = reassemblers[uuid] ?? FrameReassembler()
        reassemblers[uuid] = reassembler
        return reassembler.feed(bytes).compactMap { V18Decoder.decode($0) }
    }

    static func read(directory: URL, now: Date = Date()) -> [V18Sample] {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        var records: [Int: V18Sample] = [:]
        // Retention is 72 hours; inspect a week of captures to include long
        // interrupted syncs, while keeping startup work bounded to recent files.
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "jsonl" {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= now.addingTimeInterval(-7 * 86400),
                  let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            var pending = Data()
            var reassemblers: [String: FrameReassembler] = [:]
            while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    for sample in samples(in: line, reassemblers: &reassemblers) {
                        if let old = records[sample.unix], !HistoricalRecordSelection.prefers(sample, over: old) { continue }
                        records[sample.unix] = sample
                    }
                }
                // A truncated/malformed giant row must not grow memory forever.
                if pending.count > 1024 * 1024 { pending.removeAll() }
            }
            // A crash can truncate the final line; only complete frame rows survive.
            for sample in samples(in: pending, reassemblers: &reassemblers) {
                if let old = records[sample.unix] {
                    if HistoricalRecordSelection.prefers(sample, over: old) { records[sample.unix] = sample }
                } else { records[sample.unix] = sample }
            }
        }
        guard let latest = records.keys.max() else { return [] }
        return records.values.filter { $0.unix >= latest - 72 * 3600 }.sorted { $0.unix < $1.unix }
    }
}

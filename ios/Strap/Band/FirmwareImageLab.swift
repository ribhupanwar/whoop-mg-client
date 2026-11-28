import Foundation
import CryptoKit

/// Local inspection only. A digest identifies bytes; it is not a signature,
/// manufacturer authorization, model compatibility or proof of safe firmware.
struct FirmwareImageInspection: Equatable, Sendable {
    static let maximumBytes = 4 * 1024 * 1024
    static let plannedChunkBytes = 128
    enum Failure: Error, LocalizedError {
        case empty, oversized
        var errorDescription: String? {
            switch self {
            case .empty: return "The selected file is empty."
            case .oversized: return "The file exceeds the 4 MiB laboratory limit."
            }
        }
    }
    let name: String
    let byteCount: Int
    let sha256: String
    var chunkCount: Int {
        (byteCount + Self.plannedChunkBytes - 1) / Self.plannedChunkBytes
    }
    init(name: String, data: Data) throws {
        guard !data.isEmpty else { throw Failure.empty }
        guard data.count <= Self.maximumBytes else { throw Failure.oversized }
        self.name = name
        byteCount = data.count
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Read at most the bound plus one byte even if provider metadata lies.
    /// No file is copied into the app archive and no contents are transmitted.
    static func inspect(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data()
        while bytes.count <= maximumBytes {
            let count = min(64 * 1024, maximumBytes + 1 - bytes.count)
            guard count > 0, let next = try handle.read(upToCount: count), !next.isEmpty else { break }
            bytes.append(next)
        }
        return try Self(name: url.lastPathComponent, data: bytes)
    }
}

/// A pure, local model of the staged workflow. It has NO BLE transport,
/// no device command builder, and no access to BandLink or device storage.
/// Every acknowledgement is synthetic. Never interpret its result as a
/// verified or installed image.
struct FirmwareDryRun {
    enum Phase: Equatable {
        case idle, staging, awaitingVerification, verified, committed, failed, commitUnknown
    }
    enum CommitReply { case accepted, rejected, unknown }
    let image: FirmwareImageInspection
    private(set) var phase: Phase = .idle
    private(set) var acknowledgedBytes = 0
    init(image: FirmwareImageInspection) { self.image = image }

    @discardableResult
    mutating func start(simulatedBattery: Int?, simulatedReady: Bool) -> Bool {
        guard phase == .idle, simulatedReady, let battery = simulatedBattery,
              (50...100).contains(battery) else { return false }
        phase = .staging
        return true
    }

    @discardableResult
    mutating func acknowledgeChunk(offset: Int, count: Int, accepted: Bool) -> Bool {
        guard phase == .staging else { return false }
        let expected = min(FirmwareImageInspection.plannedChunkBytes, image.byteCount - acknowledgedBytes)
        guard accepted, offset == acknowledgedBytes, count == expected, count > 0 else {
            phase = .failed
            return false
        }
        acknowledgedBytes += count
        if acknowledgedBytes == image.byteCount { phase = .awaitingVerification }
        return true
    }

    mutating func verify(simulatedAcceptance: Bool) {
        guard phase == .awaitingVerification else { return }
        phase = simulatedAcceptance ? .verified : .failed
    }

    /// One confirmation only. Unknown outcomes are terminal, not retryable.
    mutating func commit(confirmed: Bool, reply: CommitReply) {
        guard phase == .verified, confirmed else { return }
        switch reply {
        case .accepted: phase = .committed
        case .rejected: phase = .failed
        case .unknown: phase = .commitUnknown
        }
    }

    mutating func cancel() {
        switch phase {
        case .staging, .awaitingVerification, .verified: phase = .failed
        default: break
        }
    }
}

import Foundation

/// Live presentation accepts only current-connection, recent sensor packets.
/// Archive samples and ATT read/write acknowledgements are never live samples.
enum LiveHeartRateState {
    static let freshnessSeconds: TimeInterval = 8
    enum Recovery: Equatable { case wait, rearm, reconnect, unavailable }

    static func fresh(_ bpm: Int?, receivedAt: Date?, connected: Bool, now: Date) -> Int? {
        guard connected, let bpm, (25...230).contains(bpm), let receivedAt else { return nil }
        let age = now.timeIntervalSince(receivedAt)
        return age >= 0 && age <= freshnessSeconds ? bpm : nil
    }

    static func recovery(now: Date, connectedAt: Date?, receivedAt: Date?,
                         lastAttempt: Date?, attempts: Int, reconnects: Int) -> Recovery {
        guard let origin = receivedAt ?? connectedAt else { return .wait }
        guard now.timeIntervalSince(origin) >= 30,
              lastAttempt.map({ now.timeIntervalSince($0) >= 45 }) ?? true else { return .wait }
        if attempts < 4 { return .rearm }
        return reconnects < 2 ? .reconnect : .unavailable
    }

    /// Fixed 40–180 display scale; padding keeps the endpoint inside its frame.
    static func indicatorFraction(bpm: Int) -> Double {
        min(1, max(0, (Double(bpm) - 40) / 140))
    }
}

enum Type40HeartRate {
    struct Reading: Equatable { let bpm: Int; let rrMS: [Int] }
    /// Gen5 inner payload, after CRC-validated envelope removal: HR@8, count@9.
    static func parse(_ inner: [UInt8]) -> Reading? {
        guard inner.first == 0x28, inner.count > 8, (25...230).contains(Int(inner[8])) else { return nil }
        let count = inner.count > 9 ? Int(inner[9]) : 0
        var rr: [Int] = []
        if count <= 4, inner.count >= 10 + count * 2 {
            for index in 0..<count {
                let offset = 10 + 2 * index
                let ms = Int(inner[offset]) | (Int(inner[offset + 1]) << 8)
                if (V18Decoder.minRRMS...V18Decoder.maxRRMS).contains(ms) { rr.append(ms) }
            }
        }
        // Bad/missing RR does not invalidate an independently valid HR byte.
        return Reading(bpm: Int(inner[8]), rrMS: rr)
    }
}

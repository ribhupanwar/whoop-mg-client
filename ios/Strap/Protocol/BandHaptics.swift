import Foundation

/// Gen5 haptic wire facts documented by the Goose/NOOP interoperability work:
/// https://github.com/ryanbr/noop/blob/main/Packages/WhoopProtocol/Sources/WhoopProtocol/HapticPayloads.swift
/// https://github.com/DX23876/goose/blob/main/.planning/seeds/smart-alarm-strap-haptic.md
/// An ATT write is transport delivery, not proof that the motor fired.
enum BandHaptics {
    static let buzzOpcode: UInt8 = 0x13
    static let alarmOpcode: UInt8 = 0x42
    static let disableOpcode: UInt8 = 0x45
    static let alarmID: UInt8 = 1
    static let waveform: [UInt8] = [0x2F, 0x98, 0, 0, 0, 0, 0, 0]

    // The loop byte counts repeats after the initial pulse: zero = one buzz.
    static var buzzBody: [UInt8] { [1] + waveform + [0, 0, 0] }
    // Captured Gen5 cancellation form; per-slot cancellation is unverified.
    static var disableBody: [UInt8] { [2, 0xFF] }

    static func alarmBody(at date: Date) -> [UInt8]? {
        let seconds = floor(date.timeIntervalSince1970)
        guard seconds.isFinite, seconds >= 0, seconds <= Double(UInt32.max) else { return nil }
        let epoch = UInt32(seconds)
        let timestamp = (0..<4).map { UInt8(truncatingIfNeeded: epoch >> ($0 * 8)) }
        // Revision 4, alarm slot, Unix seconds, zero subseconds, waveform,
        // per-effect loop control, seven waveform loops, 30-second duration.
        return [4, alarmID] + timestamp + [0, 0] + waveform + [0, 0, 7, 30]
    }

    static func nextWake(minutes: Int, after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard (0..<1440).contains(minutes) else { return nil }
        return calendar.nextDate(after: now, matching: DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}

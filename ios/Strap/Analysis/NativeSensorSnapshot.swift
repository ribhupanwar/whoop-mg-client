import Foundation

/// Timestamped native band sensor quality, wrist-contact, and cadence snapshot.
/// Never presents historical records as live when `observedAt` exceeds `maxAge`.
struct NativeSensorSnapshot: Equatable, Codable {
    static let unavailablePSNR = -128
    static let validCadenceRange = 0...250

    /// Latest observation across sources, for diagnostics only.
    let observedAt: Date
    let sampleObservedAt: Date?
    let contactObservedAt: Date?
    let sampleWearing: Bool?
    let source: String
    let wristContact: WristContactState
    let wristStateRaw: UInt16?
    /// Optical pSNR in dB; `nil` when absent or `-128` (unavailable sentinel).
    let psnrA: Int?
    let psnrB: Int?
    let signalQualityLogVariance: Double?
    let hrQualityFlags: Int?
    let stepCadenceSPM: Int?
    let activityClass: Int?
    let skinTempC: Double?
    let spo2CandidateRaw: Int?
    let spo2CandidateKind: Spo2CandidateKind

    var capacitiveTouch: Bool? {
        wristStateRaw.map { ($0 & 0x0001) != 0 }
    }

    var opticalReflectance: Bool? {
        wristStateRaw.map { ($0 & 0x0002) != 0 }
    }

    var onBodyPlacement: Bool? {
        wristStateRaw.map { ($0 & 0x0004) != 0 }
    }

    func isFresh(at now: Date = Date(), maxAge: TimeInterval = 600) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age >= 0 && age <= maxAge
    }

    private static func fresh(_ date: Date?, at now: Date, maxAge: TimeInterval) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age <= maxAge
    }

    func isSampleFresh(at now: Date = Date(), maxAge: TimeInterval = 600) -> Bool {
        Self.fresh(sampleObservedAt, at: now, maxAge: maxAge)
    }

    func isContactFresh(at now: Date = Date(), maxAge: TimeInterval = 600) -> Bool {
        Self.fresh(contactObservedAt, at: now, maxAge: maxAge)
    }

    /// V18 history can be delivered late. Never use receipt/contact time to
    /// make a stale measured cadence appear live, and never invent cadence.
    func recentStepCadence(at now: Date, connected: Bool, maxAge: TimeInterval = 15) -> Int? {
        guard connected, sampleWearing == true, wristContact != .offWrist,
              wristContact != .uncertain, isSampleFresh(at: now, maxAge: maxAge) else { return nil }
        return stepCadenceSPM
    }

    static func sanitizedPSNR(_ raw: Int?) -> Int? {
        guard let raw, raw != unavailablePSNR else { return nil }
        return raw
    }

    static func sanitizedCadence(_ raw: Int?) -> Int? {
        guard let raw, validCadenceRange.contains(raw) else { return nil }
        return raw
    }

    static func build(
        latestSample: V18Sample?,
        statusPacket: WhoopStatusPacket?,
        statusObservedAt: Date?,
        fallbackWristState: WristContactState,
        fallbackWristObservedAt: Date? = nil
    ) -> NativeSensorSnapshot? {
        let sampleDate = latestSample.map { Date(timeIntervalSince1970: TimeInterval($0.unix)) }
        let contactDate = [statusObservedAt, fallbackWristObservedAt].compactMap { $0 }.max()
        let observedAt: Date
        let source: String
        if let sampleDate, let contactDate {
            observedAt = max(sampleDate, contactDate)
            source = "V18 + StatusPacket"
        } else if let sampleDate {
            observedAt = sampleDate
            source = "V18"
        } else if let contactDate {
            observedAt = contactDate
            source = "StatusPacket"
        } else {
            return nil
        }

        let preferFallbackContact: Bool = {
            guard fallbackWristState != .unknown, let fallbackWristObservedAt else { return false }
            guard let statusObservedAt else { return true }
            return fallbackWristObservedAt > statusObservedAt
        }()
        let wristContact = preferFallbackContact ? fallbackWristState : (statusPacket?.contactState ?? fallbackWristState)
        let wristStateRaw = preferFallbackContact ? nil : statusPacket?.wristStateRaw
        let selectedContactDate = preferFallbackContact ? fallbackWristObservedAt
            : (statusPacket == nil ? fallbackWristObservedAt : statusObservedAt)
        return NativeSensorSnapshot(
            observedAt: observedAt,
            sampleObservedAt: sampleDate,
            contactObservedAt: selectedContactDate,
            sampleWearing: latestSample?.wearing,
            source: source,
            wristContact: wristContact,
            wristStateRaw: wristStateRaw,
            psnrA: sanitizedPSNR(latestSample?.psnrA),
            psnrB: sanitizedPSNR(latestSample?.psnrB),
            signalQualityLogVariance: latestSample?.signalQualityLogVariance,
            hrQualityFlags: latestSample?.hrQualityFlags,
            stepCadenceSPM: sanitizedCadence(latestSample?.stepCadence),
            activityClass: latestSample?.activityClass,
            skinTempC: latestSample?.skinTempC,
            spo2CandidateRaw: latestSample?.spo2CandidateRaw,
            spo2CandidateKind: latestSample?.spo2CandidateKind ?? .absent
        )
    }
}

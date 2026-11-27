import Foundation

/// Timestamped native band sensor quality, wrist-contact, and cadence snapshot.
/// Never presents historical records as live when `observedAt` exceeds `maxAge`.
struct NativeSensorSnapshot: Equatable, Codable {
    static let unavailablePSNR = -128
    static let validCadenceRange = 0...250

    let observedAt: Date
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
        fallbackWristState: WristContactState
    ) -> NativeSensorSnapshot? {
        let sampleDate = latestSample.map { Date(timeIntervalSince1970: TimeInterval($0.unix)) }
        let observedAt: Date
        let source: String
        if let sampleDate, let statusObservedAt {
            observedAt = max(sampleDate, statusObservedAt)
            source = "V18 + StatusPacket"
        } else if let sampleDate {
            observedAt = sampleDate
            source = "V18"
        } else if let statusObservedAt {
            observedAt = statusObservedAt
            source = "StatusPacket"
        } else {
            return nil
        }

        let wristContact = statusPacket?.contactState ?? fallbackWristState
        return NativeSensorSnapshot(
            observedAt: observedAt,
            source: source,
            wristContact: wristContact,
            wristStateRaw: statusPacket?.wristStateRaw,
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

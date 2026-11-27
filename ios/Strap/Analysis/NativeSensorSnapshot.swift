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


/// Historical deep-record measurements, kept separate from 1 Hz biometrics.
/// Counts are received frames in this drain, including replay; latest means
/// newest band timestamp, not receipt time. Raw data remains in the capture.
struct NativeDeepTelemetry: Equatable {
    struct Motion: Equatable {
        let version: UInt8
        let unix: UInt32
        let accelerationSamples: Int
        let gyroSamples: Int
        let centeredAccelerationRMSG: Double
        let angularVelocityRMSDPS: Double
        let features: Gen5IMUBuffer.BlockFeatures?

        init(_ record: Gen5IMUBuffer) {
            features = record.blockFeatures
            version = record.version
            unix = record.unix
            accelerationSamples = record.accelerationG.first?.count ?? 0
            gyroSamples = record.angularVelocityDPS.first?.count ?? 0
            // Remove per-axis mean (including static gravity); do not infer
            // cadence, sleep stages or orientation from one historical block.
            centeredAccelerationRMSG = Self.vectorRMS(record.accelerationG, centered: true)
            angularVelocityRMSDPS = Self.vectorRMS(record.angularVelocityDPS, centered: false)
        }

        private static func vectorRMS(_ axes: [[Double]], centered: Bool) -> Double {
            guard let count = axes.first?.count, count > 0 else { return 0 }
            let sum = axes.reduce(0.0) { total, axis in
                let mean = centered ? axis.reduce(0, +) / Double(count) : 0
                return total + axis.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
            }
            return sqrt(sum / Double(count))
        }
    }

    struct Optical: Equatable {
        let unix: UInt32
        let bytes: Int
    }

    struct Tagged: Equatable {
        let unix: UInt32
        let tag: UInt8
        let known: Bool
        let queuedChannel: UInt8?
        let queuedSampleCount: Int?
        let firstAmbiguousIndex: Int?
    }

    struct PIP: Equatable {
        let unix: UInt32
        let deltaCount: Int
        let deltaRMSADC: Double?
        let firstADC: Int32
        let accelerationDeltaG: Double?
        let reconstructedCount: Int
        let firstAmbiguousIndex: Int?
        let outOfRangeCount: Int

        init(_ record: Gen5V26Record) {
            unix = record.header.unix
            deltaCount = record.opticalDeltas.count
            let squares = record.opticalDeltas.reduce(0.0) { total, value in
                total + Double(value) * Double(value)
            }
            deltaRMSADC = deltaCount > 0 ? sqrt(squares / Double(deltaCount)) : nil
            firstADC = record.firstSampleADC
            accelerationDeltaG = record.accelDeltaG
            let decoded = record.reconstruction
            reconstructedCount = decoded.codes.count
            firstAmbiguousIndex = decoded.firstAmbiguousIndex
            outOfRangeCount = decoded.outOfRangeCount
        }
    }

    private(set) var v20Frames = 0
    private(set) var imuFrames = 0
    private(set) var v22Frames = 0
    private(set) var unknownV22Frames = 0
    private(set) var v26Frames = 0
    private(set) var optical: Optical?
    private(set) var motion: Motion?
    private(set) var tagged: Tagged?
    private(set) var pip: PIP?

    /// Called only for validated historical frame routes. Returns true for
    /// recognized deep records (including unresolved v22 tags).
    mutating func ingest(_ inner: [UInt8]) -> Bool {
        if let record = Gen5V26Record.decode(inner) {
            v26Frames += 1
            if pip.map({ record.header.unix >= $0.unix }) ?? true {
                pip = PIP(record)
            }
        } else if let record = Gen5IMUBuffer.decode(inner) {
            imuFrames += 1
            if motion.map({ record.unix >= $0.unix }) ?? true {
                motion = Motion(record)
            }
        } else if let record = Gen5V20Record.decode(inner) {
            v20Frames += 1
            if optical.map({ record.header.unix >= $0.unix }) ?? true {
                optical = Optical(unix: record.header.unix, bytes: record.rawBody.count)
            }
        } else if let record = Gen5V22Record.decode(inner) {
            v22Frames += 1
            if !record.hasKnownLayout { unknownV22Frames += 1 }
            if tagged.map({ record.header.unix >= $0.unix }) ?? true {
                let queued = record.queuedOptical
                tagged = Tagged(unix: record.header.unix, tag: record.tag, known: record.hasKnownLayout,
                                queuedChannel: queued?.channel, queuedSampleCount: queued?.sampleBits.count,
                                firstAmbiguousIndex: queued?.firstAmbiguousIndex)
            }
        } else {
            return false
        }
        return true
    }
}

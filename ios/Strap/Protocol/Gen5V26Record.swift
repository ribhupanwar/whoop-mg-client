import Foundation

/// WHOOP Gen5 v26 optical PPG waveform (OpenStrap gen5_records.dart).
/// This is NOT a heart-rate or R-R record and must never enter HRV analysis.
struct Gen5V26Record: Equatable {
    let header: BandRecordHeader
    let pipStateCounter: UInt16
    let firstSampleADC: Int32
    let opticalDeltas: [Int16]
    let accelDeltaG: Double?
    let channelStateWord: UInt16
    let primaryFlagsByte: UInt8
    let morphologyByte: UInt8
    let alignedTailByte: UInt8

    init(
        header: BandRecordHeader,
        pipStateCounter: UInt16,
        firstSampleADC: Int32,
        opticalDeltas: [Int16],
        accelDeltaG: Double? = nil,
        channelStateWord: UInt16,
        primaryFlagsByte: UInt8,
        morphologyByte: UInt8,
        alignedTailByte: UInt8
    ) {
        self.header = header
        self.pipStateCounter = pipStateCounter
        self.firstSampleADC = firstSampleADC
        self.opticalDeltas = opticalDeltas
        self.accelDeltaG = accelDeltaG
        self.channelStateWord = channelStateWord
        self.primaryFlagsByte = primaryFlagsByte
        self.morphologyByte = morphologyByte
        self.alignedTailByte = alignedTailByte
    }

    struct Reconstruction: Equatable {
        let codes: [Int64]
        let firstAmbiguousIndex: Int?
        let outOfRangeCount: Int
    }

    /// Transmitted approximation only. A rail delta can hide clipping; every
    /// subsequent sample is then ambiguous. Do not infer physiological metrics.
    var reconstruction: Reconstruction {
        var value = Int64(firstSampleADC)
        var codes = [value]
        var ambiguous: Int?
        for (i, delta) in opticalDeltas.enumerated() {
            if ambiguous == nil && (delta == Int16.min || delta == Int16.max) { ambiguous = i + 1 }
            value += Int64(delta)
            codes.append(value)
        }
        return Reconstruction(codes: codes, firstAmbiguousIndex: ambiguous,
                              outOfRangeCount: codes.filter { !(-524_288...524_287).contains($0) }.count)
    }

    static func decode(_ bytes: [UInt8]) -> Gen5V26Record? {
        guard bytes.count == 76, bytes[0] == 0x2F, bytes[1] == 26,
              let header = V18Decoder.header(of: bytes) else { return nil }
        func u16(_ i: Int) -> UInt16 {
            UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
        }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8) |
                (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 3]) << 24)
        }
        let deltas: [Int16] = (0..<24).map {
            Int16(bitPattern: u16(19 + 2 * $0))
        }
        var accel: Double? = nil
        if let f = V18Decoder.f32(bytes, 67), (0...V18Decoder.fullScaleG).contains(f) {
            accel = V18Decoder.round4(f)
        }
        let rawAnchor = u32(15)
        let anchor: Int32 = (rawAnchor >= 524_288 && rawAnchor < 1_048_576)
            ? Int32(rawAnchor) - 1_048_576
            : Int32(bitPattern: rawAnchor)
        return Gen5V26Record(
            header: header, pipStateCounter: u16(13),
            firstSampleADC: anchor,
            opticalDeltas: deltas,
            accelDeltaG: accel,
            channelStateWord: u16(71),
            primaryFlagsByte: bytes[73], morphologyByte: bytes[74],
            alignedTailByte: bytes[75])
    }
}


/// Shadow pulse estimator for a narrow, explicitly timed V26 shape. Not a
/// replacement for measured HR, not beat intervals, and not used by scores.
/// Independent autocorrelation implementation; constants are provisional.
struct V26PulseEvidence: Equatable {
    struct Candidate: Equatable {
        let unix: UInt32
        let bpm: Double
        let correlation: Double
    }
    private var previous: Gen5V26Record?
    private var waveform: [Double] = []
    private(set) var candidate: Candidate?

    mutating func ingest(_ record: Gen5V26Record) {
        if let previous, record.header.unix <= previous.header.unix { return }
        let r = record.reconstruction
        // 25 declared samples at 25 Hz can fill one second. The 50 Hz
        // configuration cannot be stitched on a one-second time grid.
        guard record.header.ppgSampleRateHz == 25, r.codes.count == 25,
              r.firstAmbiguousIndex == nil, r.outOfRangeCount == 0,
              record.morphologyByte == 1,
              !r.codes.contains(where: { $0 == -524288 || $0 == 524287 }) else {
            previous = nil; waveform.removeAll(); candidate = nil; return
        }
        if let last = previous {
            if UInt64(record.header.unix) != UInt64(last.header.unix) + 1 ||
                record.header.recordIndex != (last.header.recordIndex &+ 1) ||
                record.header.subsecQ15 != last.header.subsecQ15 {
                waveform.removeAll(); candidate = nil
            }
        }
        previous = record
        waveform.append(contentsOf: r.codes.map(Double.init))
        if waveform.count > 200 { waveform.removeFirst(waveform.count - 200) }
        guard waveform.count == 200 else { return }
        // Reject record-boundary discontinuities rather than interpreting
        // a repeating block artifact as 60 bpm.
        var boundary = 0.0, within = 0.0
        for i in 1..<waveform.count {
            let change = abs(waveform[i] - waveform[i - 1])
            if i % 25 == 0 { boundary += change } else { within += change }
        }
        guard within > 0, boundary / 7 <= 3 * within / 192 else {
            candidate = nil; return
        }
        let mean = waveform.reduce(0, +) / 200.0
        let mid = 99.5
        var xy = 0.0, xx = 0.0
        for i in waveform.indices {
            let x = Double(i) - mid
            xy += x * (waveform[i] - mean)
            xx += x * x
        }
        let slope = xy / xx
        var centered: [Double] = []
        for i in waveform.indices {
            centered.append(waveform[i] - mean - slope * (Double(i) - mid))
        }
        var values: [Double] = []
        for lag in 6...51 {
            var dot = 0.0, a = 0.0, b = 0.0
            for j in lag..<centered.count {
                let x = centered[j]
                let y = centered[j - lag]
                dot += x * y; a += x * x; b += y * y
            }
            values.append(a > 0 && b > 0 ? dot / sqrt(a * b) : 0)
        }
        guard let strongest = values.max(), strongest >= 0.7 else { candidate = nil; return }
        var chosen: Int?
        for i in 1..<(values.count - 1) {
            if values[i] >= 0.9 * strongest, values[i] >= 0.7,
               values[i] > values[i - 1], values[i] >= values[i + 1] {
                chosen = i; break
            }
        }
        guard let chosen else { candidate = nil; return }
        candidate = Candidate(unix: record.header.unix, bpm: 1500.0 / Double(6 + chosen),
                              correlation: values[chosen])
    }
}


/// Research-only respiratory modulation evidence. One full clean 40-second
/// burst; both intensity (RIIV) and amplitude (RIAV) must support the same
/// frequency. One-second modulation features, not beat intervals. No clinical
/// interpretation, nightly aggregation, or replacement of the RR estimator.
struct V26RespiratoryEvidence: Equatable {
    struct Candidate: Equatable {
        let endUnix: UInt32
        let breathsPerMinute: Double
        let intensityConcentration: Double
        let amplitudeConcentration: Double
    }
    private var last: Gen5V26Record?
    private var intensity: [Double] = []
    private var amplitude: [Double] = []
    private(set) var candidate: Candidate?
    private(set) var lastAccepted: Candidate?
    private(set) var acceptedBursts: [Candidate] = []

    private mutating func reset() {
        last = nil
        intensity.removeAll()
        amplitude.removeAll()
        candidate = nil
    }

    mutating func ingest(_ record: Gen5V26Record) {
        if let last, record.header.unix <= last.header.unix { return }
        let reconstruction = record.reconstruction
        guard record.header.ppgSampleRateHz == 25, reconstruction.codes.count == 25,
              reconstruction.firstAmbiguousIndex == nil, reconstruction.outOfRangeCount == 0,
              record.morphologyByte == 1,
              let motion = record.accelDeltaG, motion.isFinite,
              motion >= 0, motion <= Hrv.restingQuietAccelG,
              !reconstruction.codes.contains(where: { $0 == -524288 || $0 == 524287 }) else {
            reset(); return
        }
        if let previous = last {
            if UInt64(record.header.unix) != UInt64(previous.header.unix) + 1 ||
                record.header.recordIndex != (previous.header.recordIndex &+ 1) ||
                record.header.subsecQ15 != previous.header.subsecQ15 ||
                record.channelStateWord != previous.channelStateWord {
                reset()
            }
        }
        last = record
        let codes = reconstruction.codes.map(Double.init)
        let mean = codes.reduce(0, +) / Double(codes.count)
        var variance = 0.0
        for code in codes {
            let delta = code - mean
            variance += delta * delta
        }
        guard variance > 0 else { reset(); return }
        intensity.append(mean)
        amplitude.append(sqrt(variance / Double(codes.count)))
        guard intensity.count == 40 else { return }
        defer { intensity.removeAll(); amplitude.removeAll() }
        guard let a = Self.peak(intensity), let b = Self.peak(amplitude),
              a.bin == b.bin else { candidate = nil; return }
        candidate = Candidate(endUnix: record.header.unix,
                              breathsPerMinute: Double(a.bin) * 60.0 / 40.0,
                              intensityConcentration: a.concentration,
                              amplitudeConcentration: b.concentration)
        lastAccepted = candidate
        if let candidate, acceptedBursts.last.map({ candidate.endUnix > $0.endUnix }) ?? true {
            acceptedBursts.append(candidate)
            if acceptedBursts.count > 128 { acceptedBursts.removeFirst() }
        }
    }

    /// 40 one-second values yield 1.5 rpm bins; require a prominent interior
    /// peak, not the largest bin of a flat spectrum. Thresholds are exploratory.
    private static func peak(_ values: [Double]) -> (bin: Int, concentration: Double)? {
        guard values.count == 40 else { return nil }
        let mean = values.reduce(0, +) / 40.0
        var covariance = 0.0
        var timeEnergy = 0.0
        for j in values.indices {
            let t = Double(j) - 19.5
            covariance += t * (values[j] - mean)
            timeEnergy += t * t
        }
        let slope = covariance / timeEnergy
        var signal: [Double] = []
        for j in values.indices {
            let detrended = values[j] - mean - slope * (Double(j) - 19.5)
            let taper = 0.5 - 0.5 * cos(2 * Double.pi * Double(j) / 39.0)
            signal.append(detrended * taper)
        }
        var power = [Double](repeating: 0, count: 21)
        for k in 1...20 {
            var re = 0.0, im = 0.0
            for j in signal.indices {
                let phase = 2 * Double.pi * Double(k * j) / 40.0
                re += signal[j] * cos(phase)
                im += signal[j] * sin(phase)
            }
            power[k] = re * re + im * im
        }
        let total = power.dropFirst().reduce(0, +)
        guard total.isFinite, total > 1e-9,
              let bin = (6...16).max(by: { power[$0] < power[$1] }),
              power[bin] > power[bin - 1], power[bin] >= power[bin + 1] else { return nil }
        let concentration = (power[bin - 1] + power[bin] + power[bin + 1]) / total
        guard concentration >= 0.65 else { return nil }
        return (bin, concentration)
    }
}

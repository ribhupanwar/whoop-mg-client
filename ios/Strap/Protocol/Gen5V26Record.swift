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
        return Gen5V26Record(
            header: header, pipStateCounter: u16(13),
            firstSampleADC: Int32(bitPattern: u32(15)),
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

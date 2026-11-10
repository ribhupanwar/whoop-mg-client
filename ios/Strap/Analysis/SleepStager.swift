import Foundation

/// Four-stage sleep stager over a window the actigraphy detector already found.
///
/// This is an APPROXIMATION, not PSG-validated staging. It exists because the
/// v18 stream carries the three channels a transparent rule stager needs — 1 Hz
/// HR, beat-to-beat R-R and a gravity vector — and a labelled estimate is more
/// useful than silence. Every surface that shows these stages labels them as an
/// estimate.
///
/// The recipe follows the published approach NOOP's SleepStagerV2 documents,
/// reimplemented here from the description (no code copied):
///   1. per-night z-scores of HR, 5-minute HR variability, movement fraction
///      and R-R RSA regularity;
///   2. a deep gate on the night's own 11-minute HR-flatness percentile;
///   3. a soft sleep-cycle prior (deep early, REM rising) plus REM/deep latency
///      guards measured from the first sustained sleep run;
///   4. a wake gate on peak jerk relative to the night's own quiescent floor;
///   5. Viterbi smoothing with a sticky transition matrix.
///
/// Two deliberate departures: staging refuses below 50 % HR coverage instead of
/// collapsing to "all light", and the latency guards run in absolute minutes so
/// a long window cannot stretch them.
///
/// Four-class agreement for rules of this family on wrist data is low, so treat
/// the hypnogram as a plausible shape, never as a clinical reading.
enum SleepStager {
    static let epochS = 30
    static let minHRCoverage = 0.5
    static let minBeatsPerEpoch = 12

    private static let stageOrder: [SleepStage] = [.deep, .rem, .light, .wake]
    private static let baseLogPrior: [SleepStage: Double] = [
        .light: log(0.50), .deep: log(0.15), .rem: log(0.22), .wake: log(0.10)
    ]

    private static let deepGateThreshold = 0.25
    private static let deepGateSlope = 5.0
    private static let jerkFloorMoveMult = 38.0
    private static let jerkFloorGateMult = 55.0
    private static let motionGateBoost = 2.0
    private static let respWeight = 0.6

    private static let remLatencyPenalty = 3.0
    private static let remLatencyMinutes = 60.0
    private static let deepLatencyPenalty = 3.0
    private static let deepLatencyMinutes = 20.0
    private static let onsetSustainedEpochs = 10

    private static let rrMinMS = 300.0
    private static let rrMaxMS = 2000.0
    private static let respResampleHz = 4.0
    private static let respBandHz = (lo: 0.15, hi: 0.40)

    private static let transition: [SleepStage: [SleepStage: Double]] = [
        .deep: [.deep: 0.86, .rem: 0.007, .light: 0.126, .wake: 0.007],
        .rem: [.deep: 0.005, .rem: 0.88, .light: 0.10, .wake: 0.015],
        .light: [.deep: 0.06, .rem: 0.06, .light: 0.85, .wake: 0.03],
        .wake: [.deep: 0.0, .rem: 0.0, .light: 0.10, .wake: 0.90]
    ]

    // MARK: - Public entry

    static func stage(samples: [V18Sample], period: SleepPeriod) -> SleepStaging {
        let start = period.startUnix
        let end = period.endUnix + 1  // SleepPeriod's end is inclusive
        guard end > start else {
            return SleepStaging(
                segments: [], deepMinutes: 0, lightMinutes: 0, remMinutes: 0,
                wakeMinutes: 0, epochs: 0, hrCoverage: 0, reason: "empty sleep window"
            )
        }
        let firstEpoch = ((start + epochS - 1) / epochS) * epochS
        let gridEpochs = max(0, (end - firstEpoch + epochS - 1) / epochS)
        guard gridEpochs > 0 else {
            return SleepStaging(
                segments: [], deepMinutes: 0, lightMinutes: 0, remMinutes: 0,
                wakeMinutes: 0, epochs: 0, hrCoverage: 0,
                reason: "sleep window shorter than one \(epochS) s epoch"
            )
        }

        let ordered = samples.sorted { $0.unix < $1.unix }
        let padLo = start - 360
        let padHi = end + 420

        var hrSum: [Int: Double] = [:]
        var hrCount: [Int: Int] = [:]
        var gx: [Int: Double] = [:]
        var gy: [Int: Double] = [:]
        var gz: [Int: Double] = [:]
        var gCount: [Int: Int] = [:]
        var rrBySecond: [Int: [Double]] = [:]

        for sample in ordered where sample.unix >= padLo && sample.unix < padHi {
            let second = sample.unix
            if sample.heartRate > 0 {
                hrSum[second, default: 0] += Double(sample.heartRate)
                hrCount[second, default: 0] += 1
            }
            if let x = sample.gravityXG, let y = sample.gravityYG, let z = sample.gravityZG {
                gx[second, default: 0] += x
                gy[second, default: 0] += y
                gz[second, default: 0] += z
                gCount[second, default: 0] += 1
            }
            for rr in sample.rrIntervalsMS where rr >= 300 && rr <= 2000 {
                rrBySecond[second, default: []].append(Double(rr))
            }
        }

        var secHR: [Int: Double] = [:]
        for (second, total) in hrSum {
            secHR[second] = total / Double(hrCount[second] ?? 1)
        }
        var secGravity: [Int: (Double, Double, Double)] = [:]
        for (second, count) in gCount {
            secGravity[second] = (
                (gx[second] ?? 0) / Double(count),
                (gy[second] ?? 0) / Double(count),
                (gz[second] ?? 0) / Double(count)
            )
        }

        let epochs = features(
            start: start, end: end, secHR: secHR, secGravity: secGravity, rrBySecond: rrBySecond
        )
        let hrEpochs = epochs.filter { $0.hr != nil }.count
        let coverage = Double(hrEpochs) / Double(gridEpochs)
        guard coverage >= minHRCoverage else {
            let percent = Int((coverage * 100).rounded())
            return SleepStaging(
                segments: [], deepMinutes: 0, lightMinutes: 0, remMinutes: 0,
                wakeMinutes: 0, epochs: epochs.count, hrCoverage: coverage,
                reason: "heart rate covers \(percent)% of the sleep window; staging needs at least 50%"
            )
        }

        let labels = stageEpochs(epochs)
        guard labels.count == epochs.count else {
            return SleepStaging(
                segments: [], deepMinutes: 0, lightMinutes: 0, remMinutes: 0,
                wakeMinutes: 0, epochs: epochs.count, hrCoverage: coverage,
                reason: "staging produced no labels"
            )
        }

        var segments: [SleepStageSegment] = []
        for (index, epoch) in epochs.enumerated() {
            let stage = labels[index]
            let segmentStart = index == 0 ? start : epoch.start
            let segmentEnd = index == epochs.count - 1 ? end : epochs[index + 1].start
            if let last = segments.last, last.stage == stage {
                segments[segments.count - 1] = SleepStageSegment(
                    startUnix: last.startUnix, endUnix: segmentEnd, stage: stage
                )
            } else {
                segments.append(
                    SleepStageSegment(startUnix: segmentStart, endUnix: segmentEnd, stage: stage)
                )
            }
        }

        var deep = 0.0
        var light = 0.0
        var rem = 0.0
        var wake = 0.0
        for segment in segments {
            switch segment.stage {
            case .deep: deep += segment.minutes
            case .light: light += segment.minutes
            case .rem: rem += segment.minutes
            case .wake: wake += segment.minutes
            }
        }

        return SleepStaging(
            segments: segments, deepMinutes: deep, lightMinutes: light,
            remMinutes: rem, wakeMinutes: wake, epochs: epochs.count,
            hrCoverage: coverage, reason: nil
        )
    }

    // MARK: - Features

    private struct RawFeature {
        let start: Int
        let hr: Double?
        let hrVar: Double?
        let hrFlat11: Double?
        let jerks: [Double]
        let gapCount: Int
        let jerkMax: Double
        let respReg: Double?
        let clock: Double
        let minutes: Double
    }

    private struct Epoch {
        let start: Int
        let hr: Double?
        let hrVar: Double?
        let hrFlat11: Double?
        let moveFrac: Double
        let jerkMax: Double
        let respReg: Double?
        let clock: Double
        let jerkScale: Double
        let minutes: Double
    }

    private static func features(
        start: Int,
        end: Int,
        secHR: [Int: Double],
        secGravity: [Int: (Double, Double, Double)],
        rrBySecond: [Int: [Double]]
    ) -> [Epoch] {
        let span = Double(max(1, end - start))
        let first = ((start + epochS - 1) / epochS) * epochS

        func windowStd(_ lo: Int, _ hi: Int) -> Double? {
            var sum = 0.0
            var squares = 0.0
            var count = 0
            for second in lo..<hi {
                guard let value = secHR[second] else { continue }
                sum += value
                squares += value * value
                count += 1
            }
            guard count >= 2 else { return nil }
            let mean = sum / Double(count)
            return sqrt(max(0, squares / Double(count) - mean * mean))
        }

        var raws: [RawFeature] = []
        var allJerks: [Double] = []

        var epochStart = first
        while epochStart < end {
            var hrs: [Double] = []
            var gravity: [(Double, Double, Double)] = []
            for second in epochStart..<(epochStart + epochS) {
                if let value = secHR[second] { hrs.append(value) }
                if let point = secGravity[second] { gravity.append(point) }
            }
            if hrs.isEmpty && gravity.isEmpty {
                epochStart += epochS
                continue
            }

            var jerks: [Double] = []
            if gravity.count >= 2 {
                for index in 1..<gravity.count {
                    let a = gravity[index - 1]
                    let b = gravity[index]
                    let dx = a.0 - b.0
                    let dy = a.1 - b.1
                    let dz = a.2 - b.2
                    jerks.append(sqrt(dx * dx + dy * dy + dz * dz))
                }
            }
            allJerks.append(contentsOf: jerks)

            var beats: [(t: Double, rr: Double)] = []
            for second in (epochStart - 90)..<(epochStart + 120) {
                guard let values = rrBySecond[second] else { continue }
                for rr in values {
                    beats.append((t: Double(second), rr: min(max(rr, rrMinMS), rrMaxMS)))
                }
            }

            raws.append(
                RawFeature(
                    start: epochStart,
                    hr: hrs.isEmpty ? nil : Stats.mean(hrs),
                    hrVar: windowStd(epochStart - 150, epochStart + epochS + 150),
                    hrFlat11: windowStd(epochStart - 330, epochStart + epochS + 360),
                    jerks: jerks,
                    gapCount: max(1, gravity.count - 1),
                    jerkMax: jerks.max() ?? 0,
                    respReg: respRegularity(beats),
                    clock: Double(epochStart + 15 - start) / span,
                    minutes: Double(epochStart + 15 - start) / 60.0
                )
            )
            epochStart += epochS
        }

        let jerkScale: Double
        if allJerks.isEmpty {
            jerkScale = 1e-6
        } else {
            let median = Stats.median(allJerks)
            jerkScale = median > 0 ? median : 1e-6
        }
        let moveThreshold = jerkScale * jerkFloorMoveMult

        return raws.map { raw in
            let moves = raw.jerks.filter { $0 > moveThreshold }.count
            return Epoch(
                start: raw.start,
                hr: raw.hr,
                hrVar: raw.hrVar,
                hrFlat11: raw.hrFlat11,
                moveFrac: Double(moves) / Double(raw.gapCount),
                jerkMax: raw.jerkMax,
                respReg: raw.respReg,
                clock: raw.clock,
                jerkScale: jerkScale,
                minutes: raw.minutes
            )
        }
    }

    /// Peakedness of RSA power in 0.15-0.40 Hz over a 4 Hz resampled tachogram.
    private static func respRegularity(_ beats: [(t: Double, rr: Double)]) -> Double? {
        guard beats.count >= minBeatsPerEpoch else { return nil }
        let sorted = beats.sorted { $0.t != $1.t ? $0.t < $1.t : $0.rr < $1.rr }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let t0 = first.t
        let t1 = last.t
        guard t1 > t0 else { return nil }

        let step = 1.0 / respResampleHz
        let count = Int(ceil((t1 - t0) / step - 1e-9))
        guard count >= 16 else { return nil }

        var grid = [Double](repeating: 0, count: count)
        var segment = 0
        for index in 0..<count {
            let time = t0 + step * Double(index)
            while segment < sorted.count - 2 && sorted[segment + 1].t < time {
                segment += 1
            }
            let a = sorted[segment]
            let b = sorted[segment + 1]
            if b.t <= a.t {
                grid[index] = a.rr
            } else {
                let fraction = min(max((time - a.t) / (b.t - a.t), 0), 1)
                grid[index] = a.rr + fraction * (b.rr - a.rr)
            }
        }

        let mean = Stats.mean(grid)
        for index in 0..<count { grid[index] -= mean }

        let kLo = Int(ceil(respBandHz.lo * step * Double(count)))
        let kHi = Int(floor(respBandHz.hi * step * Double(count)))
        guard kHi >= kLo, kLo >= 0 else { return nil }

        var maxPower = 0.0
        var sumPower = 0.0
        for k in kLo...kHi {
            let omega = 2.0 * Double.pi * Double(k) / Double(count)
            var real = 0.0
            var imaginary = 0.0
            for j in 0..<count {
                let angle = omega * Double(j)
                real += grid[j] * cos(angle)
                imaginary -= grid[j] * sin(angle)
            }
            let power = real * real + imaginary * imaginary
            sumPower += power
            if power > maxPower { maxPower = power }
        }
        guard sumPower > 0 else { return nil }
        return maxPower / sumPower
    }

    // MARK: - Staging

    private static func zScorer(_ values: [Double?]) -> (Double?) -> Double {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return { _ in 0 } }
        let mean = Stats.mean(present)
        let variance = present.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(present.count)
        let sd = variance > 0 ? sqrt(variance) : 1
        return { value in
            guard let value else { return 0 }
            return (value - mean) / sd
        }
    }

    private static func percentileRank(_ sorted: [Double], _ value: Double?) -> Double {
        guard let value, !sorted.isEmpty else { return 0.5 }
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] <= value { low = mid + 1 } else { high = mid }
        }
        return Double(low) / Double(sorted.count)
    }

    private static func motionQuiescent(_ epoch: Epoch) -> Bool {
        epoch.moveFrac <= 0 && epoch.jerkMax <= epoch.jerkScale * jerkFloorGateMult
    }

    private static func remGuard(_ minutesSinceOnset: Double) -> Double {
        remLatencyPenalty * min(1, max(0, 1 - minutesSinceOnset / remLatencyMinutes))
    }

    private static func deepGuard(_ minutesSinceOnset: Double) -> Double {
        deepLatencyPenalty * min(1, max(0, 1 - minutesSinceOnset / deepLatencyMinutes))
    }

    private static func cyclePrior(
        clock: Double, minutesSinceOnset: Double
    ) -> [SleepStage: Double] {
        [
            .deep: 1.2 * max(0, 1 - clock / 0.55),
            .rem: clock - remGuard(minutesSinceOnset),
            .light: 0,
            .wake: 0
        ]
    }

    private static func viterbi(_ emissions: [[SleepStage: Double]]) -> [SleepStage] {
        guard !emissions.isEmpty else { return [] }
        var logTransition: [SleepStage: [SleepStage: Double]] = [:]
        for (source, row) in transition {
            var logged: [SleepStage: Double] = [:]
            for (target, value) in row {
                logged[target] = log(max(value, 1e-9))
            }
            logTransition[source] = logged
        }

        var scores = emissions[0]
        var back: [[SleepStage: SleepStage]] = []
        for index in 1..<emissions.count {
            var newScores: [SleepStage: Double] = [:]
            var pointers: [SleepStage: SleepStage] = [:]
            for stage in stageOrder {
                var bestPrevious = stageOrder[0]
                var best = scores[bestPrevious]! + logTransition[bestPrevious]![stage]!
                for previous in stageOrder.dropFirst() {
                    let value = scores[previous]! + logTransition[previous]![stage]!
                    if value > best {
                        best = value
                        bestPrevious = previous
                    }
                }
                newScores[stage] = best + emissions[index][stage]!
                pointers[stage] = bestPrevious
            }
            scores = newScores
            back.append(pointers)
        }

        var last = stageOrder[0]
        var lastScore = scores[last]!
        for stage in stageOrder.dropFirst() where scores[stage]! > lastScore {
            lastScore = scores[stage]!
            last = stage
        }
        var path = [last]
        for pointers in back.reversed() {
            last = pointers[last]!
            path.append(last)
        }
        return Array(path.reversed())
    }

    private static func sustainedSleepOnset(_ labels: [SleepStage]) -> Int? {
        var run = 0
        for (index, label) in labels.enumerated() {
            if label == .wake {
                run = 0
                continue
            }
            run += 1
            if run >= onsetSustainedEpochs {
                return index - onsetSustainedEpochs + 1
            }
        }
        return nil
    }

    private static func stageEpochs(_ epochs: [Epoch]) -> [SleepStage] {
        guard !epochs.isEmpty else { return [] }
        let zHR = zScorer(epochs.map { $0.hr })
        let zVar = zScorer(epochs.map { $0.hrVar })
        let zMove = zScorer(epochs.map { Optional($0.moveFrac) })
        let zResp = zScorer(epochs.map { $0.respReg })
        let flatSorted = epochs.compactMap { $0.hrFlat11 }.sorted()

        var emissions: [[SleepStage: Double]] = []
        for epoch in epochs {
            let gate = deepGateSlope
                * max(0, percentileRank(flatSorted, epoch.hrFlat11) - deepGateThreshold)
            var awakeCardiac = 0.8 * zVar(epoch.hrVar) + 0.4 * zHR(epoch.hr)
            if motionQuiescent(epoch) {
                awakeCardiac = min(0, awakeCardiac)
            }
            var emission: [SleepStage: Double] = [
                .deep: -1.1 * zVar(epoch.hrVar) - 0.5 * zMove(epoch.moveFrac)
                    - gate + baseLogPrior[.deep]!,
                .rem: 0.6 * zVar(epoch.hrVar) - 0.6 * zMove(epoch.moveFrac)
                    + 0.4 * zHR(epoch.hr) + baseLogPrior[.rem]!,
                .light: baseLogPrior[.light]!,
                .wake: zMove(epoch.moveFrac) + awakeCardiac + baseLogPrior[.wake]!
            ]
            // Pass 1 keeps the latency guards disabled; pass 2 re-adds them
            // from the onset that first pass finds.
            let prior = cyclePrior(clock: epoch.clock, minutesSinceOnset: .infinity)
            for stage in stageOrder {
                emission[stage]! += prior[stage]!
            }
            if epoch.jerkMax > epoch.jerkScale * jerkFloorGateMult {
                emission[.wake]! += motionGateBoost
            }
            if let resp = epoch.respReg {
                let value = zResp(resp)
                emission[.deep]! += respWeight * value
                emission[.rem]! -= respWeight * value
            }
            emissions.append(emission)
        }

        let provisional = viterbi(emissions)
        let origin = sustainedSleepOnset(provisional).map { epochs[$0].minutes } ?? 0
        for index in epochs.indices {
            let sinceOnset = epochs[index].minutes - origin
            var emission = emissions[index]
            emission[.rem] = (emission[.rem] ?? 0) - remGuard(sinceOnset)
            emission[.deep] = (emission[.deep] ?? 0) - deepGuard(sinceOnset)
            emissions[index] = emission
        }
        return viterbi(emissions)
    }
}

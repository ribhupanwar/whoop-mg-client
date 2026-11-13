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
        // Match the physiological HR gate used by sleep detection and resting HRV.
        // One timestamp contributes at most one worn second, regardless of replay.
        var records: [Int: V18Sample] = [:]
        for sample in samples where sample.unix >= start && sample.unix < end {
            guard sample.wearing, (35...220).contains(sample.heartRate) else { continue }
            if let previous = records[sample.unix], !preferRecord(sample, over: previous) {
                continue
            }
            records[sample.unix] = sample
        }

        var secHR: [Int: Double] = [:]
        var secGravity: [Int: (Double, Double, Double)] = [:]
        var rrBySecond: [Int: [Double]] = [:]
        var bandStateBySecond: [Int: Int] = [:]
        for (second, sample) in records {
            secHR[second] = Double(sample.heartRate)
            secGravity[second] = finiteGravity(sample)
            rrBySecond[second] = validRR(sample)
            if let state = sample.sleepState, (0...3).contains(state) {
                bandStateBySecond[second] = state
            }
        }

        let epochs = features(
            start: start, end: end, secHR: secHR, secGravity: secGravity,
            rrBySecond: rrBySecond, bandStateBySecond: bandStateBySecond
        )
        let coverage = Double(secHR.count) / Double(end - start)
        let validEpochCount = epochs.filter { $0.hr != nil }.count
        let coveragePercent = Int((coverage * 100).rounded())
        let coverageReason = coverage < minHRCoverage
            ? "heart rate covers \(coveragePercent)% of the sleep window; full-night scoring needs at least 50%"
            : nil
        // Keep the full-night quality threshold for sleep score/recovery. When
        // enough complete 30-second epochs exist, retain stages for those
        // observed intervals and leave every other epoch as a gap. This mirrors
        // partial-window behavior without inventing stages in missing sensor time.
        let minimumPartialEpochs = 120 // one hour of independently valid epochs
        if coverageReason != nil && validEpochCount < minimumPartialEpochs {
            return SleepStaging(
                segments: [], deepMinutes: 0, lightMinutes: 0, remMinutes: 0,
                wakeMinutes: 0, epochs: validEpochCount, hrCoverage: coverage,
                reason: coverageReason
            )
        }

        let labels = labelsForValidRuns(epochs)
        guard labels.count == epochs.count else {
            return SleepStaging(
                segments: [], deepMinutes: 0, lightMinutes: 0, remMinutes: 0,
                wakeMinutes: 0, epochs: validEpochCount, hrCoverage: coverage,
                reason: "staging produced no labels"
            )
        }

        var segments: [SleepStageSegment] = []
        for (index, epoch) in epochs.enumerated() {
            let stage: SleepStage?
            switch epoch.bandState {
            case 0, 3:
                stage = .wake
            case 1, -1:
                // "Still" and a mixed state transition cannot establish sleep.
                stage = nil
            default:
                stage = labels[index]
            }
            guard let stage else { continue }
            if let last = segments.last, last.stage == stage, last.endUnix == epoch.start {
                segments[segments.count - 1] = SleepStageSegment(
                    startUnix: last.startUnix, endUnix: epoch.end, stage: stage
                )
            } else {
                segments.append(
                    SleepStageSegment(startUnix: epoch.start, endUnix: epoch.end, stage: stage)
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
            remMinutes: rem, wakeMinutes: wake, epochs: validEpochCount,
            hrCoverage: coverage,
            reason: coverageReason ?? (segments.isEmpty ? "no sleep epochs were confirmed in this window" : nil)
        )
    }

    // MARK: - Features

    private static func validRR(_ sample: V18Sample) -> [Double] {
        sample.rrIntervalsMS.filter { (Int(rrMinMS)...Int(rrMaxMS)).contains($0) }.map { Double($0) }
    }

    private static func finiteGravity(_ sample: V18Sample) -> (Double, Double, Double)? {
        guard let x = sample.gravityXG, let y = sample.gravityYG, let z = sample.gravityZG,
              x.isFinite, y.isFinite, z.isFinite else { return nil }
        return (x, y, z)
    }

    /// Select one whole packet, rather than averaging HR or concatenating replayed beats.
    private static func preferRecord(_ sample: V18Sample, over previous: V18Sample) -> Bool {
        let rr = validRR(sample)
        let oldRR = validRR(previous)
        if rr.count != oldRR.count { return rr.count > oldRR.count }
        let gravity = finiteGravity(sample)
        let oldGravity = finiteGravity(previous)
        if (gravity != nil) != (oldGravity != nil) { return gravity != nil }
        if sample.header.subsecQ15 != previous.header.subsecQ15 {
            return sample.header.subsecQ15 < previous.header.subsecQ15
        }
        if sample.header.recordIndex != previous.header.recordIndex {
            return sample.header.recordIndex < previous.header.recordIndex
        }
        if sample.heartRate != previous.heartRate { return sample.heartRate < previous.heartRate }
        // A payload tie-break selects a packet; the beat order inside it is unchanged.
        if rr != oldRR { return rr.lexicographicallyPrecedes(oldRR) }
        if let a = gravity, let b = oldGravity {
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            if a.2 != b.2 { return a.2 < b.2 }
        }
        return false
    }

    private struct RawFeature {
        let start: Int
        let end: Int
        let hr: Double?
        let hrVar: Double?
        let hrFlat11: Double?
        let jerks: [Double]
        let gapCount: Int
        let jerkMax: Double
        let respReg: Double?
        let bandState: Int?
        let clock: Double
        let minutes: Double
    }

    private struct Epoch {
        let start: Int
        let end: Int
        let hr: Double?
        let hrVar: Double?
        let hrFlat11: Double?
        let moveFrac: Double
        let jerkMax: Double
        let respReg: Double?
        let bandState: Int?
        let clock: Double
        let jerkScale: Double
        let minutes: Double
    }

    private static func features(
        start: Int,
        end: Int,
        secHR: [Int: Double],
        secGravity: [Int: (Double, Double, Double)],
        rrBySecond: [Int: [Double]],
        bandStateBySecond: [Int: Int]
    ) -> [Epoch] {
        let span = Double(end - start)

        func windowStd(_ lo: Int, _ hi: Int) -> Double? {
            var sum = 0.0
            var squares = 0.0
            var count = 0
            for second in max(start, lo)..<min(end, hi) {
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

        // Keep the absolute 30-second grid, clipping both boundary epochs.
        var gridStart = start - ((start % epochS + epochS) % epochS)
        while gridStart < end {
            let epochStart = max(start, gridStart)
            let epochEnd = min(end, gridStart + epochS)
            let hrs = (epochStart..<epochEnd).compactMap { secHR[$0] }
            let valid = Double(hrs.count) / Double(epochEnd - epochStart) >= minHRCoverage
            let observedStates = (epochStart..<epochEnd).compactMap { bandStateBySecond[$0] }
            let bandState: Int?
            if Double(observedStates.count) / Double(epochEnd - epochStart) >= minHRCoverage {
                let counts = (0...3).map { value in observedStates.filter { $0 == value }.count }
                let dominant = counts.indices.max { counts[$0] < counts[$1] } ?? 0
                // A mixed epoch is an observed transition, not permission to
                // fall back to guessed physiology. Reserve -1 for unclassified;
                // nil means the band field was absent and physiology may be used.
                bandState = counts[dominant] * 5 >= observedStates.count * 3 ? dominant : -1
            } else {
                bandState = nil
            }

            var jerks: [Double] = []
            if valid {
                for second in epochStart..<epochEnd {
                    // Missing seconds are not consecutive motion observations.
                    guard second > epochStart,
                          let a = secGravity[second - 1], let b = secGravity[second] else { continue }
                    let dx = a.0 - b.0
                    let dy = a.1 - b.1
                    let dz = a.2 - b.2
                    let jerk = sqrt(dx * dx + dy * dy + dz * dz)
                    if jerk.isFinite { jerks.append(jerk) }
                }
                allJerks.append(contentsOf: jerks)
            }

            var beats: [(t: Double, rr: Double)] = []
            if valid {
                for second in max(start, epochStart - 90)..<min(end, epochEnd + 90) {
                    guard let values = rrBySecond[second], !values.isEmpty else { continue }
                    // Subsecond beat times are unavailable: distribute the packet's
                    // beats within its second in their original acquisition order.
                    for (index, rr) in values.enumerated() {
                        beats.append((t: Double(second) + Double(index) / Double(values.count), rr: rr))
                    }
                }
            }

            let midpoint = (Double(epochStart) + Double(epochEnd)) / 2 - Double(start)
            raws.append(
                RawFeature(
                    start: epochStart,
                    end: epochEnd,
                    hr: valid ? Stats.mean(hrs) : nil,
                    hrVar: valid ? windowStd(epochStart - 150, epochEnd + 150) : nil,
                    hrFlat11: valid ? windowStd(epochStart - 330, epochEnd + 360) : nil,
                    jerks: jerks,
                    gapCount: max(1, jerks.count),
                    jerkMax: jerks.max() ?? 0,
                    respReg: valid ? respRegularity(beats) : nil,
                    bandState: valid ? bandState : nil,
                    clock: midpoint / span,
                    minutes: midpoint / 60.0
                )
            )
            gridStart += epochS
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
                end: raw.end,
                hr: raw.hr,
                hrVar: raw.hrVar,
                hrFlat11: raw.hrFlat11,
                moveFrac: Double(moves) / Double(raw.gapCount),
                jerkMax: raw.jerkMax,
                respReg: raw.respReg,
                bandState: raw.bandState,
                clock: raw.clock,
                jerkScale: jerkScale,
                minutes: raw.minutes
            )
        }
    }

    /// Peakedness of RSA power in 0.15-0.40 Hz over a 4 Hz resampled tachogram.
    private static func respRegularity(_ beats: [(t: Double, rr: Double)]) -> Double? {
        guard beats.count >= minBeatsPerEpoch else { return nil }
        // The caller supplies chronological seconds and original within-packet order.
        guard let first = beats.first, let last = beats.last else { return nil }
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
            while segment < beats.count - 2 && beats[segment + 1].t < time {
                segment += 1
            }
            let a = beats[segment]
            let b = beats[segment + 1]
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

    private static func labelsForValidRuns(_ epochs: [Epoch]) -> [SleepStage?] {
        let population = epochs.filter { $0.hr != nil }
        var labels = [SleepStage?](repeating: nil, count: epochs.count)
        var index = 0
        while index < epochs.count {
            guard epochs[index].hr != nil else {
                index += 1
                continue
            }
            let first = index
            index += 1
            while index < epochs.count, epochs[index].hr != nil,
                  epochs[index - 1].end == epochs[index].start {
                index += 1
            }
            let runLabels = stageEpochs(Array(epochs[first..<index]), population: population)
            for (offset, label) in runLabels.enumerated() { labels[first + offset] = label }
        }
        return labels
    }

    private static func stageEpochs(_ epochs: [Epoch], population: [Epoch]) -> [SleepStage] {
        guard !epochs.isEmpty else { return [] }
        // Normalize against valid epochs in this window, but run both HMM passes
        // and sustained-onset detection separately on either side of every hole.
        let zHR = zScorer(population.map { $0.hr })
        let zVar = zScorer(population.map { $0.hrVar })
        let zMove = zScorer(population.map { Optional($0.moveFrac) })
        let zResp = zScorer(population.map { $0.respReg })
        let flatSorted = population.compactMap { $0.hrFlat11 }.sorted()

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

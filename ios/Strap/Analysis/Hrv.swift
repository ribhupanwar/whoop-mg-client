import Foundation

/// Published HRV and strain definitions ported from the Python reference
/// (`whoop/metrics.py`). Pure functions: samples in, numbers out.
///
/// Provenance: NN filtering, RMSSD, SDNN and pNN50 follow Malik et al. (1996)
/// and the Task Force standards; TRIMP follows Banister with the sex-specific
/// coefficients from Morton et al. (1990). None of these are WHOOP scores.
enum Hrv {
    static let nnMaxDeviation = 0.20
    static let nnReferenceBeats = 5
    static let restingQuietAccelG = 0.10
    static let restingMinWindowS = 60
    static let strainScaleTrimp = 150.0
    static let strainMax = 21.0

    // MARK: - NN filtering

    /// Normal-to-normal intervals, with ectopic beats and artefacts removed.
    ///
    /// The reference is a rolling median of recently accepted beats, not the
    /// single preceding interval: an ectopic beat produces a short-then-long
    /// pair, and comparing against the raw predecessor would also reject the
    /// normal recovery beat. The reference seeds only once two consecutive
    /// beats agree and is abandoned after a full window of rejections;
    /// otherwise a lone artefact becomes the permanent reference.
    static func nnIntervals(_ rrMS: [Double]) -> [Double] {
        let minimum = Double(V18Decoder.minRRMS)
        let maximum = Double(V18Decoder.maxRRMS)
        var accepted: [Double] = []
        var recent: [Double] = []
        var candidate: Double?
        var rejectedRun = 0

        for value in rrMS {
            guard value >= minimum && value <= maximum else {
                recent.removeAll()
                rejectedRun = 0
                continue
            }
            if recent.isEmpty {
                guard let pending = candidate else {
                    candidate = value
                    continue
                }
                let midpoint = Stats.median([pending, value])
                if abs(value - pending) > nnMaxDeviation * midpoint {
                    candidate = value
                    continue
                }
                accepted.append(pending)
                recent.append(pending)
                candidate = nil
            } else {
                let reference = Stats.median(recent)
                if abs(value - reference) > nnMaxDeviation * reference {
                    rejectedRun += 1
                    if rejectedRun >= nnReferenceBeats {
                        recent.removeAll()
                        rejectedRun = 0
                    }
                    continue
                }
            }
            accepted.append(value)
            recent.append(value)
            rejectedRun = 0
            if recent.count > nnReferenceBeats { recent.removeFirst() }
        }
        return accepted
    }

    // MARK: - Standard HRV

    static func rmssd(_ nnMS: [Double]) -> Double? {
        guard nnMS.count >= 2 else { return nil }
        var squares = 0.0
        for index in 1..<nnMS.count {
            let difference = nnMS[index] - nnMS[index - 1]
            squares += difference * difference
        }
        return (squares / Double(nnMS.count - 1)).squareRoot()
    }

    static func sdnn(_ nnMS: [Double]) -> Double? {
        Stats.sampleStdev(nnMS)
    }

    static func pnn50(_ nnMS: [Double]) -> Double? {
        guard nnMS.count >= 2 else { return nil }
        var count = 0
        for index in 1..<nnMS.count where abs(nnMS[index] - nnMS[index - 1]) > 50 {
            count += 1
        }
        return 100.0 * Double(count) / Double(nnMS.count - 1)
    }

    static func fromRR(_ rrMS: [Double]) -> HrvResult {
        let nn = nnIntervals(rrMS)
        let value = rmssd(nn)
        var ln: Double?
        if let value, value > 0 { ln = log(value) }
        return HrvResult(
            beats: rrMS.count,
            nnBeats: nn.count,
            rmssdMS: value,
            sdnnMS: sdnn(nn),
            pnn50Pct: pnn50(nn),
            lnRMSSD: ln,
            meanRRMS: nn.isEmpty ? nil : Stats.mean(nn)
        )
    }

    /// Compute RMSSD only across consecutive beats inside contiguous records.
    /// Never bridge a missing second or an artefact-rejected beat: doing so
    /// creates an artificial successive-NN difference and biases recovery.
    /// Each contiguous run is cleaned independently, preventing a stale
    /// rolling-median reference from leaking across a recording gap.
    static func fromSamples(_ samples: [V18Sample]) -> HrvResult {
        let ordered = samples.sorted { $0.unix < $1.unix }
        let runs = contiguousRuns(ordered)
        var allNN: [Double] = []
        var squaredDifferences = 0.0
        var successivePairs = 0
        var over50 = 0
        var rawBeats = 0

        for run in runs {
            // A missing R-R field or rejected ectopic beat is a hard boundary.
            // Never calculate RMSSD across those boundaries: doing so can
            // produce artificially high overnight HRV.
            var previous: Double?
            var recent: [Double] = []
            for sample in run {
                let rr = sample.rrIntervalsMS.map(Double.init)
                rawBeats += rr.count
                if rr.isEmpty { previous = nil; recent.removeAll(); continue }
                for value in rr {
                    guard value >= Double(V18Decoder.minRRMS),
                          value <= Double(V18Decoder.maxRRMS) else {
                        previous = nil; recent.removeAll(); continue
                    }
                    if !recent.isEmpty {
                        let reference = Stats.median(recent)
                        if abs(value - reference) > nnMaxDeviation * reference {
                            previous = nil
                            recent.removeAll()
                            continue
                        }
                    }
                    if let previous {
                        let delta = value - previous
                        squaredDifferences += delta * delta
                        successivePairs += 1
                        if abs(delta) > 50 { over50 += 1 }
                    }
                    allNN.append(value)
                    recent.append(value)
                    if recent.count > nnReferenceBeats { recent.removeFirst() }
                    previous = value
                }
            }
        }
        // The 20-clean-beat gate is a quality floor, not clinical validation.
        guard allNN.count >= 20, successivePairs > 0 else {
            return HrvResult(beats: rawBeats, nnBeats: allNN.count,
                             rmssdMS: nil, sdnnMS: nil, pnn50Pct: nil,
                             lnRMSSD: nil, meanRRMS: nil)
        }
        let rmssd = sqrt(squaredDifferences / Double(successivePairs))
        return HrvResult(
            beats: rawBeats,
            nnBeats: allNN.count,
            rmssdMS: rmssd,
            sdnnMS: sdnn(allNN),
            pnn50Pct: 100 * Double(over50) / Double(successivePairs),
            lnRMSSD: rmssd > 0 ? log(rmssd) : nil,
            meanRRMS: Stats.mean(allNN)
        )
    }

    // MARK: - Resting windows

    /// Consecutive seconds, split wherever the record clock jumps.
    static func contiguousRuns(_ samples: [V18Sample]) -> [[V18Sample]] {
        var runs: [[V18Sample]] = []
        var current: [V18Sample] = []
        for sample in samples.sorted(by: { $0.unix < $1.unix }) {
            // Archive replay can duplicate a timestamp. Preserve continuity
            // instead of splitting a valid resting window at duplicates.
            if current.last?.unix == sample.unix { continue }
            if let last = current.last, sample.unix != last.unix + 1 {
                runs.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Diagnostics only: do not weaken the resting or R-R quality gates.
    static func restingQualityReason(_ samples: [V18Sample]) -> String {
        let worn = samples.filter { $0.wearing && (35...220).contains($0.heartRate) }
        guard !worn.isEmpty else { return "No valid on-wrist heart-rate seconds" }
        let motion = worn.filter { $0.dynamicAccelG != nil }
        guard !motion.isEmpty else { return "Motion data missing; cannot verify rest" }
        let quiet = motion.filter { $0.dynamicAccelG! <= restingQuietAccelG }
        guard !quiet.isEmpty else { return "No motion-verified quiet seconds" }
        let longest = contiguousRuns(quiet.sorted { $0.unix < $1.unix })
            .map(\.count).max() ?? 0
        guard longest >= restingMinWindowS else {
            return "Longest continuous quiet run: \\(longest)s; need \\(restingMinWindowS)s"
        }
        let result = restingHRV(samples)
        guard result.result.rmssdMS != nil else {
            let rrSeconds = quiet.filter { !$0.rrIntervalsMS.isEmpty }.count
            let rrBeats = quiet.reduce(0) { $0 + $1.rrIntervalsMS.count }
            return "Quiet run found; R-R: \\(rrBeats) beats in \\(rrSeconds)s, but insufficient clean consecutive pairs"
        }
        return "Validated quiet HRV available"
    }

    /// HRV from the longest verified-quiet contiguous run, and its length.
    ///
    /// RMSSD is only interpretable at rest. Pooling a capture lets motion
    /// artefacts in a plausible R-R range inflate it, and the NN filter cannot
    /// catch those because they look normal. Beats either side of a gap are
    /// not successive, so a run is never joined across one.
    static func restingHRV(
        _ samples: [V18Sample],
        quietAccelG: Double = restingQuietAccelG,
        minWindowS: Int = restingMinWindowS
    ) -> (result: HrvResult, windowSeconds: Int) {
        let eligible = samples
            .filter {
                $0.wearing && (35...220).contains($0.heartRate)
                    && $0.dynamicAccelG != nil && $0.dynamicAccelG! <= quietAccelG
            }
            .sorted { $0.unix < $1.unix }
        let runs = contiguousRuns(eligible).filter { $0.count >= minWindowS }
        guard let longest = runs.max(by: { $0.count < $1.count }) else {
            return (.empty, 0)
        }
        return (fromSamples(longest), longest.count)
    }

    /// Lowest sustained heart rate across a quiet window, in bpm.
    ///
    /// Resting HR is the lowest sustained rate during quiet, not the single
    /// lowest reading. Seconds must be contiguous and motion must be measured:
    /// a sample with no accelerometer value is excluded, not assumed quiet.
    static func restingHeartRate(
        _ samples: [V18Sample],
        windowS: Int = 60,
        quietAccelG: Double = restingQuietAccelG
    ) -> Double? {
        let eligible = samples
            .filter {
                $0.wearing && (35...220).contains($0.heartRate)
                    && $0.dynamicAccelG != nil && $0.dynamicAccelG! <= quietAccelG
            }
            .sorted { $0.unix < $1.unix }
        var best: Double?
        for run in contiguousRuns(eligible) {
            guard let value = minimumRollingMean(run.map { Double($0.heartRate) }, window: windowS)
            else { continue }
            if best == nil || value < best! { best = value }
        }
        return best
    }

    static func minimumRollingMean(_ values: [Double], window: Int) -> Double? {
        guard window > 0, values.count >= window else { return nil }
        var total = values[0..<window].reduce(0.0, +)
        var best = total
        var index = window
        while index < values.count {
            total += values[index] - values[index - window]
            best = min(best, total)
            index += 1
        }
        return best / Double(window)
    }

    // MARK: - Strain

    static func hrReserveRatio(_ hr: Double, resting: Double, maximum: Double) -> Double? {
        guard maximum > resting else { return nil }
        return max(0.0, min(1.0, (hr - resting) / (maximum - resting)))
    }

    /// Banister's training impulse over observed seconds.
    ///
    /// TRIMP = minutes * HRR * k1 * exp(k2 * HRR), with coefficients that are
    /// sex-specific. Sex "not set" returns nil rather than silently applying
    /// one set of coefficients to another body.
    static func trimp(
        _ samples: [V18Sample],
        maxHR: Double,
        restingHR: Double,
        sex: Sex
    ) -> Double? {
        let coefficients: (k1: Double, k2: Double)
        switch sex {
        case .male: coefficients = (0.64, 1.92)
        case .female: coefficients = (0.86, 1.67)
        case .unspecified: return nil
        }
        guard maxHR > restingHR else { return nil }
        // The decoded archive may contain multiple records per second and
        // discontinuous sync chunks. Integrate observed seconds only: counting
        // every record as one second overstates strain after repeat imports.
        let valid = samples.filter {
            $0.wearing && (35...220).contains($0.heartRate)
        }.sorted { $0.unix < $1.unix }
        guard !valid.isEmpty else { return nil }
        var total = 0.0
        var lastSecond: Int?
        for sample in valid {
            guard sample.unix != lastSecond else { continue }
            lastSecond = sample.unix
            guard let ratio = hrReserveRatio(
                Double(sample.heartRate), resting: restingHR, maximum: maxHR
            ) else { continue }
            total += (1.0 / 60.0) * ratio * coefficients.k1 * exp(coefficients.k2 * ratio)
        }
        return total
    }

    /// Map TRIMP onto our own local 0-21 scale. Not WHOOP strain.
    static func strainScore(_ trimp: Double?) -> Double? {
        guard let trimp, trimp >= 0 else { return nil }
        return strainMax * (1.0 - exp(-trimp / strainScaleTrimp))
    }

    /// Uth 2004 non-exercise estimate: 15.3 × HRmax / HRrest (ml/kg/min).
    /// Needs a max HR strictly above a positive resting HR.
    static func vo2Max(maxHR: Double, restingHR: Double) -> Double? {
        guard maxHR > restingHR, restingHR > 0 else { return nil }
        return 15.3 * maxHR / restingHR
    }

    /// Exploratory running-derived VO2max estimate (ml/kg/min).
    ///
    /// ACSM level-ground running oxygen cost: 0.2 × speed(m/min) + 3.5.
    /// Extrapolation uses heart-rate reserve as a *proxy* for fractional
    /// aerobic effort, not a directly measured VO2 fraction. This is not a
    /// laboratory VO2max measurement and must be labelled an estimate.
    /// Call only with a time-aligned, steady, level-ground GPS/HR segment.
    static func runningVO2Estimate(
        speedMetersPerSecond: Double,
        meanHR: Double,
        restingHR: Double,
        maxHR: Double,
        durationSeconds: Double,
        grade: Double = 0
    ) -> Double? {
        guard speedMetersPerSecond.isFinite, (2.0...5.5).contains(speedMetersPerSecond),
              meanHR.isFinite, restingHR.isFinite, maxHR.isFinite,
              durationSeconds.isFinite, durationSeconds >= 360,
              grade.isFinite, abs(grade) <= 0.02,
              (35...100).contains(restingHR),
              (140...220).contains(maxHR), maxHR > restingHR + 40,
              meanHR > restingHR, meanHR < maxHR else { return nil }
        let reserveFraction = (meanHR - restingHR) / (maxHR - restingHR)
        // Avoid low-intensity HR noise and near-maximal nonlinearity.
        guard (0.65...0.90).contains(reserveFraction) else { return nil }
        let speedMPerMin = speedMetersPerSecond * 60
        let oxygenCost = 0.2 * speedMPerMin + 0.9 * speedMPerMin * grade + 3.5
        let estimated = (oxygenCost - 3.5) / reserveFraction + 3.5
        guard estimated.isFinite, (20...85).contains(estimated) else { return nil }
        return estimated
    }

    /// Robust 30-day running fitness trend. Each input is a *quality-gated*
    /// steady-state running estimate with its timestamp. Do not feed the
    /// HR-only Uth estimate here: that would mix incompatible methods.
    /// Median resists a single anomalous GPS/HR session. At least three
    /// distinct days are required before showing a running-derived trend.
    static func runningVO2Trend(
        _ observations: [(unix: Int, value: Double)],
        nowUnix: Int,
        windowDays: Int = 30
    ) -> Double? {
        guard windowDays > 0 else { return nil }
        let cutoff = nowUnix - windowDays * 86_400
        let valid = observations.filter {
            $0.unix >= cutoff && $0.unix <= nowUnix &&
            $0.value.isFinite && (20...85).contains($0.value)
        }
        let days = Set(valid.map { $0.unix / 86_400 })
        guard days.count >= 3 else { return nil }
        let sorted = valid.map(\.value).sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    static func strainLabel(_ score: Double?) -> String {
        guard let score else { return "unknown" }
        if score < 10 { return "light" }
        if score < 14 { return "moderate" }
        if score < 18 { return "high" }
        return "all-out"
    }
}

/// Fill brief holes inside otherwise-true stretches. Shared by sleep and
/// activity detection; spans are inclusive seconds, so a run is
/// `lastUnix - firstUnix + 1`.
enum GapClosing {
    static func closed(_ flags: [Bool], unix: [Int], maxGapS: Int) -> [Bool] {
        var filled = flags
        var index = 0
        while index < flags.count {
            if filled[index] {
                index += 1
                continue
            }
            let start = index
            while index < flags.count && !filled[index] { index += 1 }
            let end = index
            let bounded = start > 0 && end < flags.count && filled[start - 1] && filled[end]
            if bounded {
                let span = unix[end - 1] - unix[start] + 1
                if span <= maxGapS {
                    for fill in start..<end { filled[fill] = true }
                }
            }
        }
        return filled
    }
}

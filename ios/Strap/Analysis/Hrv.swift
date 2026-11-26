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
    static let minCleanBeats = 20

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
                // Invalid/padding RR is a hard beat-continuity boundary.
                // Do not pair a pre-gap seed with a post-gap interval.
                recent.removeAll()
                candidate = nil
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

    /// Research-only RR duration coverage. Never rescale production HRV.
    /// Requires a verified contiguous observation interval.
    static func rrDurationCoverage(_ rrMS: [Int], observedSeconds: Int) -> Double? {
        guard observedSeconds > 0 else { return nil }
        var totalMilliseconds = 0.0
        for rr in rrMS {
            guard (V18Decoder.minRRMS...V18Decoder.maxRRMS).contains(rr) else { continue }
            totalMilliseconds += Double(rr)
        }
        guard totalMilliseconds > 0 else { return nil }
        return totalMilliseconds / (Double(observedSeconds) * 1_000)
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

    /// Choose one RR payload per timestamp after history/live retransmission.
    /// An extra invalid/padding word must not outrank a shorter, valid payload.
    /// Ties retain the first observation for deterministic replay behavior.
    static func preferRetransmittedRR(_ candidate: [Int], over existing: [Int]) -> Bool {
        func validCount(_ rr: [Int]) -> Int {
            rr.filter { (V18Decoder.minRRMS...V18Decoder.maxRRMS).contains($0) }.count
        }
        let candidateValid = validCount(candidate)
        let existingValid = validCount(existing)
        if candidateValid != existingValid { return candidateValid > existingValid }
        let candidateInvalid = candidate.count - candidateValid
        let existingInvalid = existing.count - existingValid
        return candidateInvalid < existingInvalid
    }

    /// Compute RMSSD only across consecutive beats inside contiguous records.
    /// Never bridge a missing second or an artefact-rejected beat: doing so
    /// creates an artificial successive-NN difference and biases recovery.
    /// Each contiguous run is cleaned independently, preventing a stale
    /// rolling-median reference from leaking across a recording gap.
    static func fromSamples(_ samples: [V18Sample]) -> HrvResult {
        // Offload may replay a second after reconnect. Count its R-R beats once.
        // Prefer the copy with more beat intervals rather than duplicating data.
        var uniqueBySecond: [Int: V18Sample] = [:]
        for sample in samples {
            if let previous = uniqueBySecond[sample.unix],
               !preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) {
                continue
            }
            uniqueBySecond[sample.unix] = sample
        }
        let ordered = uniqueBySecond.values.sorted { $0.unix < $1.unix }
        let runs = contiguousRuns(ordered)
        return evaluateRuns(runs) { $0.rrIntervalsMS }
    }

    /// Compute RMSSD for live streaming samples across consecutive beats inside
    /// contiguous records. Never bridge missing timestamps or disconnect gaps:
    /// doing so creates artificial successive-NN deltas and inflates live HRV.
    static func fromLiveSamples(_ samples: [LiveSample]) -> HrvResult {
        // Live reconnect/replay can deliver the same timestamp twice.
        // Match historical processing: count one record per second, keeping
        // the one with the most RR intervals instead of duplicating beats.
        var uniqueBySecond: [Int: LiveSample] = [:]
        for sample in samples {
            if let previous = uniqueBySecond[sample.unix],
               !preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) {
                continue
            }
            uniqueBySecond[sample.unix] = sample
        }
        let runs = contiguousLiveRuns(Array(uniqueBySecond.values))
        return evaluateRuns(runs) { $0.rrIntervalsMS }
    }

    private static func evaluateRuns<T>(_ runs: [[T]], getRR: (T) -> [Int]) -> HrvResult {
        var allNN: [Double] = []
        var squaredDifferences = 0.0
        var successivePairs = 0
        var over50 = 0
        var rawBeats = 0

        for run in runs {
            // A missing R-R field or rejected ectopic beat is a hard boundary.
            // Never calculate RMSSD across those boundaries: doing so can
            // produce artificially high HRV.
            var previous: Double?
            var recent: [Double] = []
            var seedCandidate: Double?
            for sample in run {
                let rr = getRR(sample).map(Double.init)
                rawBeats += rr.count
                if rr.isEmpty {
                    previous = nil; recent.removeAll(); seedCandidate = nil
                    continue
                }
                for value in rr {
                    guard value >= Double(V18Decoder.minRRMS),
                          value <= Double(V18Decoder.maxRRMS) else {
                        previous = nil; recent.removeAll(); seedCandidate = nil
                        continue
                    }
                    if recent.isEmpty {
                        // Confirm a stable pair before seeding RMSSD. A single
                        // plausible PPG spike must not become the reference.
                        guard let pending = seedCandidate else {
                            seedCandidate = value
                            continue
                        }
                        let midpoint = Stats.median([pending, value])
                        guard abs(value - pending) <= nnMaxDeviation * midpoint else {
                            seedCandidate = value
                            continue
                        }
                        allNN.append(pending)
                        recent.append(pending)
                        previous = pending
                        seedCandidate = nil
                    } else {
                        let reference = Stats.median(recent)
                        if abs(value - reference) > nnMaxDeviation * reference {
                            previous = nil
                            recent.removeAll()
                            seedCandidate = nil
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
        guard allNN.count >= minCleanBeats, successivePairs > 0 else {
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

    /// Generates detailed HRV calculation diagnostics for provenance auditing.
    static func detailedDiagnostics(
        samples: [V18Sample],
        swsEpochs: [ClosedRange<Int>] = []
    ) -> HrvDetailedDiagnostics {
        var uniqueBySecond: [Int: V18Sample] = [:]
        for sample in samples {
            if let previous = uniqueBySecond[sample.unix],
               !preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) {
                continue
            }
            uniqueBySecond[sample.unix] = sample
        }
        let ordered = uniqueBySecond.values.sorted { $0.unix < $1.unix }
        let targetSamples: [V18Sample]
        let windowType: String
        if !swsEpochs.isEmpty {
            let filtered = ordered.filter { sample in
                swsEpochs.contains { $0.contains(sample.unix) }
            }
            if !filtered.isEmpty {
                targetSamples = filtered
                windowType = "SWS_DEEP_SLEEP"
            } else {
                targetSamples = ordered
                windowType = "ALL_VALID_SLEEP"
            }
        } else {
            targetSamples = ordered
            windowType = "ALL_VALID_SLEEP"
        }

        var timestampGaps = 0
        if ordered.count > 1 {
            for i in 1..<ordered.count {
                if ordered[i].unix > ordered[i - 1].unix + 1 {
                    timestampGaps += 1
                }
            }
        }

        var rawBeats = 0
        var rejectionReasons: [String: Int] = [
            "outOfPlausibleRange": 0,
            "ectopicDeviation": 0,
            "seedMismatch": 0
        ]

        let runs = contiguousRuns(targetSamples)
        var allNN: [Double] = []
        var squaredDifferences = 0.0
        var successivePairs = 0

        for run in runs {
            var previous: Double?
            var recent: [Double] = []
            var seedCandidate: Double?
            for sample in run {
                let rr = sample.rrIntervalsMS.map(Double.init)
                rawBeats += rr.count
                if rr.isEmpty {
                    previous = nil; recent.removeAll(); seedCandidate = nil
                    continue
                }
                for value in rr {
                    guard value >= Double(V18Decoder.minRRMS),
                          value <= Double(V18Decoder.maxRRMS) else {
                        rejectionReasons["outOfPlausibleRange", default: 0] += 1
                        previous = nil; recent.removeAll(); seedCandidate = nil
                        continue
                    }
                    if recent.isEmpty {
                        guard let pending = seedCandidate else {
                            seedCandidate = value
                            continue
                        }
                        let midpoint = Stats.median([pending, value])
                        guard abs(value - pending) <= nnMaxDeviation * midpoint else {
                            rejectionReasons["seedMismatch", default: 0] += 1
                            seedCandidate = value
                            continue
                        }
                        allNN.append(pending)
                        recent.append(pending)
                        previous = pending
                        seedCandidate = nil
                    } else {
                        let reference = Stats.median(recent)
                        if abs(value - reference) > nnMaxDeviation * reference {
                            rejectionReasons["ectopicDeviation", default: 0] += 1
                            previous = nil
                            recent.removeAll()
                            seedCandidate = nil
                            continue
                        }
                    }
                    if let previous {
                        let delta = value - previous
                        squaredDifferences += delta * delta
                        successivePairs += 1
                    }
                    allNN.append(value)
                    recent.append(value)
                    if recent.count > nnReferenceBeats { recent.removeFirst() }
                    previous = value
                }
            }
        }

        let acceptedNN = allNN.count
        let coveragePct = rawBeats > 0 ? (Double(acceptedNN) / Double(rawBeats)) * 100.0 : 0.0
        let finalRMSSD: Double? = (acceptedNN >= minCleanBeats && successivePairs > 0)
            ? sqrt(squaredDifferences / Double(successivePairs))
            : nil
        let finalLn: Double? = finalRMSSD.flatMap { $0 > 0 ? log($0) : nil }

        return HrvDetailedDiagnostics(
            rawRRCount: rawBeats,
            acceptedNNCount: acceptedNN,
            rejectedBeatsByReason: rejectionReasons,
            coveragePercentage: coveragePct,
            timestampGaps: timestampGaps,
            selectedCalculationWindow: windowType,
            finalRMSSD: finalRMSSD,
            finalLnRMSSD: finalLn
        )
    }

    // MARK: - Resting windows

    /// Consecutive seconds, split wherever the record clock jumps.
    static func contiguousRuns(_ samples: [V18Sample]) -> [[V18Sample]] {
        splitContiguousRuns(samples) { $0.unix }
    }

    /// Consecutive seconds for live samples, split wherever the timestamp jumps.
    static func contiguousLiveRuns(_ samples: [LiveSample]) -> [[LiveSample]] {
        splitContiguousRuns(samples) { $0.unix }
    }

    private static func splitContiguousRuns<T>(
        _ samples: [T],
        getUnix: (T) -> Int
    ) -> [[T]] {
        var runs: [[T]] = []
        var current: [T] = []
        for sample in samples.sorted(by: { getUnix($0) < getUnix($1) }) {
            let u = getUnix(sample)
            // Archive replay can duplicate a timestamp. Preserve continuity
            // instead of splitting a valid resting window at duplicates.
            if let last = current.last, getUnix(last) == u { continue }
            if let last = current.last, u != getUnix(last) + 1 {
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
        let quiet = motion.filter { ($0.dynamicAccelG ?? Double.infinity) <= restingQuietAccelG }
        guard !quiet.isEmpty else { return "No motion-verified quiet seconds" }
        let longest = contiguousRuns(quiet.sorted { $0.unix < $1.unix })
            .map(\.count).max() ?? 0
        guard longest >= restingMinWindowS else {
            return "Longest continuous quiet run: \(longest)s; need \(restingMinWindowS)s"
        }
        let result = restingHRV(samples)
        guard result.result.rmssdMS != nil else {
            let rrSeconds = quiet.filter { !$0.rrIntervalsMS.isEmpty }.count
            let rrBeats = quiet.reduce(0) { $0 + $1.rrIntervalsMS.count }
            return "Quiet run found; R-R: \(rrBeats) beats in \(rrSeconds)s, but insufficient clean consecutive pairs"
        }
        return "Validated quiet HRV available"
    }

    /// HRV from the longest usable verified-quiet run, and its length.
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
                    && ($0.dynamicAccelG ?? Double.infinity) <= quietAccelG
            }
            .sorted { $0.unix < $1.unix }
        let runs = contiguousRuns(eligible).filter { $0.count >= minWindowS }
        // A longer quiet run can contain no R-R data at all. Try each run in
        // duration order instead of letting that run hide a valid measurement.
        for run in runs.sorted(by: { $0.count > $1.count }) {
            let result = fromSamples(run)
            if result.rmssdMS != nil { return (result, run.count) }
        }
        return (.empty, 0)
    }

    /// Evaluates HRV during Slow Wave Sleep (SWS / deep sleep) epochs.
    /// WHOOP physiological research documents that HRV is calculated during SWS (deep sleep)
    /// because parasympathetic vagal stability is maximized. When SWS epochs contain >= 20 NN beats
    /// and >= minWindowS (default 300s), SWS RMSSD is returned. Otherwise, falls back to quiet-window HRV.
    static func swsRestingHRV(
        _ samples: [V18Sample],
        deepEpochs: [ClosedRange<Int>] = [],
        quietAccelG: Double = restingQuietAccelG,
        minWindowS: Int = restingMinWindowS
    ) -> (result: HrvResult, windowSeconds: Int, isSWS: Bool) {
        if !deepEpochs.isEmpty {
            let deepSamples = samples.filter { sample in
                deepEpochs.contains { $0.contains(sample.unix) }
            }
            let deepResult = restingHRV(deepSamples, quietAccelG: quietAccelG, minWindowS: minWindowS)
            if let rmssd = deepResult.result.rmssdMS, rmssd.isFinite, rmssd > 0, deepResult.result.nnBeats >= 20 {
                return (result: deepResult.result, windowSeconds: deepResult.windowSeconds, isSWS: true)
            }
        }
        let fallback = restingHRV(samples, quietAccelG: quietAccelG, minWindowS: minWindowS)
        return (result: fallback.result, windowSeconds: fallback.windowSeconds, isSWS: false)
    }

    /// Multi-window 5-minute sleep RMSSD estimator (Accuracy Engine V2).
    ///
    /// Instead of selecting a single longest contiguous run (which introduces ±7–15 ms
    /// sampling variance whenever a single micro-movement or 1s gap splits a run),
    /// this partitions the sleep period into 5-minute windows, enforces per-window
    /// RR coverage (<= 1.05 * elapsed) and gap-aware NN cleaning (>= 21 clean beats),
    /// and averages the qualifying window RMSSDs across the sleep session.
    /// Falls back to `swsRestingHRV` when no 5-minute window qualifies.
    static func windowedSleepHRV(
        _ samples: [V18Sample],
        deepEpochs: [ClosedRange<Int>] = [],
        quietAccelG: Double = 0.15,
        windowSeconds: Int = 300,
        minBeatsPerWindow: Int = 21
    ) -> (result: HrvResult, windowSeconds: Int, qualifyingWindows: Int, usedSWSFallback: Bool) {
        var uniqueBySecond: [Int: V18Sample] = [:]
        for sample in samples {
            if let previous = uniqueBySecond[sample.unix],
               !preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) {
                continue
            }
            uniqueBySecond[sample.unix] = sample
        }
        let eligible = uniqueBySecond.values
            .filter {
                $0.wearing && (35...220).contains($0.heartRate)
                    && ($0.dynamicAccelG ?? Double.infinity) <= quietAccelG
            }
            .sorted { $0.unix < $1.unix }

        var buckets: [Int: [V18Sample]] = [:]
        for sample in eligible {
            buckets[sample.unix / windowSeconds, default: []].append(sample)
        }

        var windowRMSSDs: [Double] = []
        var windowSDNNs: [Double] = []
        var windowPNN50s: [Double] = []
        var windowMeanRRs: [Double] = []
        var totalBeats = 0
        var totalNNBeats = 0
        var totalSeconds = 0

        let minCoveredSeconds = max(60, windowSeconds / 2)
        let minRRDurationS = Double(windowSeconds) * 0.25

        for bucket in buckets.keys.sorted() {
            guard let records = buckets[bucket],
                  records.count >= minCoveredSeconds,
                  let firstUnix = records.first?.unix,
                  let lastUnix = records.last?.unix else { continue }
            let elapsed = lastUnix - firstUnix + 1
            guard elapsed >= minCoveredSeconds else { continue }
            let validRRSumMS = records.reduce(0) { acc, s in
                acc + s.rrIntervalsMS.filter {
                    (V18Decoder.minRRMS...V18Decoder.maxRRMS).contains($0)
                }.reduce(0, +)
            }
            let validRRSumS = Double(validRRSumMS) / 1000.0
            if validRRSumS < minRRDurationS || validRRSumS > Double(elapsed) * 1.05 {
                continue
            }
            let res = fromSamples(records)
            guard let rmssd = res.rmssdMS, rmssd.isFinite, rmssd > 0,
                  res.nnBeats >= minBeatsPerWindow else { continue }
            windowRMSSDs.append(rmssd)
            if let sd = res.sdnnMS, sd.isFinite { windowSDNNs.append(sd) }
            if let p50 = res.pnn50Pct, p50.isFinite { windowPNN50s.append(p50) }
            if let mrr = res.meanRRMS, mrr.isFinite { windowMeanRRs.append(mrr) }
            totalBeats += res.beats
            totalNNBeats += res.nnBeats
            totalSeconds += records.count
        }

        if !windowRMSSDs.isEmpty {
            let meanRMSSD = Stats.mean(windowRMSSDs)
            let result = HrvResult(
                beats: totalBeats,
                nnBeats: totalNNBeats,
                rmssdMS: meanRMSSD,
                sdnnMS: windowSDNNs.isEmpty ? nil : Stats.mean(windowSDNNs),
                pnn50Pct: windowPNN50s.isEmpty ? nil : Stats.mean(windowPNN50s),
                lnRMSSD: meanRMSSD > 0 ? log(meanRMSSD) : nil,
                meanRRMS: windowMeanRRs.isEmpty ? nil : Stats.mean(windowMeanRRs)
            )
            return (result: result, windowSeconds: totalSeconds,
                    qualifyingWindows: windowRMSSDs.count, usedSWSFallback: false)
        }

        let fallback = swsRestingHRV(samples, deepEpochs: deepEpochs,
                                     quietAccelG: min(quietAccelG, restingQuietAccelG),
                                     minWindowS: windowSeconds)
        return (result: fallback.result, windowSeconds: fallback.windowSeconds,
                qualifyingWindows: fallback.result.rmssdMS != nil ? 1 : 0,
                usedSWSFallback: fallback.isSWS)
    }

    /// Diagnostic provenance for overnight HRV/RHR comparisons. Does not
    /// change either production estimator or its quality thresholds.
    struct RestingWindowDiagnostic: Encodable {
        let startUnix: Int
        let endUnix: Int
        let durationSeconds: Int
        let rrBeats: Int
        let cleanBeats: Int
        let rmssdMS: Double?
        let meanHeartRate: Double
        let minimumRollingHeartRate: Double?
    }

    static func restingWindowDiagnostics(
        _ samples: [V18Sample],
        quietAccelG: Double = restingQuietAccelG,
        minWindowS: Int = restingMinWindowS
    ) -> [RestingWindowDiagnostic] {
        let eligible = samples.filter {
            $0.wearing && (35...220).contains($0.heartRate)
                && ($0.dynamicAccelG ?? Double.infinity) <= quietAccelG
        }
        // Use the same contiguous-run and RR quality rules as production HRV.
        return contiguousRuns(eligible)
            .filter { $0.count >= minWindowS }
            .map { run in
                let result = fromSamples(run)
                let heartRates = run.map { Double($0.heartRate) }
                return RestingWindowDiagnostic(
                    startUnix: run[0].unix,
                    endUnix: run[run.count - 1].unix,
                    durationSeconds: run.count,
                    rrBeats: result.beats,
                    cleanBeats: result.nnBeats,
                    rmssdMS: result.rmssdMS,
                    meanHeartRate: Stats.mean(heartRates),
                    minimumRollingHeartRate: minimumRollingMean(heartRates, window: minWindowS)
                )
            }
            .sorted { $0.startUnix < $1.startUnix }
    }

    /// Robust overnight resting heart rate across motion-verified quiet windows.
    ///
    /// The former minimum of all five-minute averages systematically
    /// underestimated overnight RHR (5 paired nights: 8.1 bpm mean absolute
    /// error against the user's WHOOP export). The median of eligible rolling
    /// windows reduced that retrospective error to 1.5 bpm. This is an
    /// independently derived estimate, NOT a claim about WHOOP's proprietary
    /// estimator. Keep contiguous-second and measured-motion quality gates.
    /// A sample with missing accelerometer data is never assumed quiet.
    static func restingHeartRate(
        _ samples: [V18Sample],
        windowS: Int = 60,
        quietAccelG: Double = restingQuietAccelG
    ) -> Double? {
        let eligible = samples
            .filter {
                $0.wearing && (35...220).contains($0.heartRate)
                    && ($0.dynamicAccelG ?? Double.infinity) <= quietAccelG
            }
            .sorted { $0.unix < $1.unix }
        guard windowS > 0 else { return nil }
        var windowMeans: [Double] = []
        for run in contiguousRuns(eligible) where run.count >= windowS {
            let values = run.map { Double($0.heartRate) }
            var total = values[0..<windowS].reduce(0.0, +)
            windowMeans.append(total / Double(windowS))
            for index in windowS..<values.count {
                total += values[index] - values[index - windowS]
                windowMeans.append(total / Double(windowS))
            }
        }
        guard !windowMeans.isEmpty else { return nil }
        return Stats.median(windowMeans)
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
        guard hr.isFinite, resting.isFinite, maximum.isFinite,
              resting > 0, maximum > resting else { return nil }
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
        // WHOOP 5/MG archive HR can be sparse. One record is not necessarily
        // one second of wear. Integrate the observed cadence, but never fill
        // long disconnects or missing archive chunks with invented exercise.
        // Deduplicate repeated records at the same timestamp first.
        var unique: [V18Sample] = []
        for sample in valid where unique.last?.unix != sample.unix {
            unique.append(sample)
        }
        // Price effort ABOVE the user's observed quiet-waking HR reserve.
        // Ordinary sedentary wear must not accumulate exercise strain.
        // Abstain when we cannot establish a reliable quiet baseline.
        let quietHR = unique.filter {
            guard let accel = $0.dynamicAccelG else { return false }
            return accel <= restingQuietAccelG
        }.map { Double($0.heartRate) }
        guard quietHR.count >= 300 else { return nil }
        let quietBaseline = Stats.median(quietHR)
        guard let baselineRatio = hrReserveRatio(
            quietBaseline, resting: restingHR, maximum: maxHR
        ) else { return nil }
        let baselineLoad = baselineRatio * coefficients.k1 * exp(coefficients.k2 * baselineRatio)
        var total = 0.0
        for index in unique.indices {
            let sample = unique[index]
            guard let ratio = hrReserveRatio(
                Double(sample.heartRate), resting: restingHR, maximum: maxHR
            ) else { continue }
            // Preserve dense 1 Hz behavior, but do not assume a sparse HR
            // observation represents the full interval. Cap extrapolation at
            // five seconds; longer gaps are not evidence of sustained effort.
            let seconds: Int
            if index + 1 < unique.count {
                let gap = unique[index + 1].unix - sample.unix
                // Treat gaps over 30 seconds as a disconnect: the next
                // observation cannot establish sustained effort in between.
                // For shorter sparse intervals, cap extrapolation at five seconds.
                seconds = gap > 30 ? 1 : (gap > 0 ? min(gap, 5) : 1)
            } else {
                // A final sample has no following timestamp to establish
                // duration. Count only its observed second, never 30 seconds.
                seconds = 1
            }
            let gross = ratio * coefficients.k1 * exp(coefficients.k2 * ratio)
            total += (Double(seconds) / 60.0) * max(0, gross - baselineLoad)
        }
        return total
    }

    /// Map TRIMP onto our own local 0-21 scale. Not WHOOP strain.
    static func strainScore(_ trimp: Double?) -> Double? {
        guard let trimp, trimp.isFinite, trimp >= 0 else { return nil }
        return strainMax * (1.0 - exp(-trimp / strainScaleTrimp))
    }

    /// Uth 2004 non-exercise estimate: 15.3 × HRmax / HRrest (ml/kg/min).
    /// Needs a max HR strictly above a positive resting HR.
    static func vo2Max(maxHR: Double, restingHR: Double) -> Double? {
        guard maxHR.isFinite, restingHR.isFinite,
              maxHR > restingHR, restingHR > 0 else { return nil }
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

// MARK: - Observation-Only Diagnostics (Non-Production)

extension Hrv {
    /// Lag-1 autocorrelation of the NN successive-difference series, pooled
    /// over CONTIGUOUS runs. Returns nil when there are fewer than 30 pairs
    /// or the series is constant.
    ///
    /// This is an OBSERVATION-ONLY diagnostic. It does not gate or modify
    /// production HRV. OpenStrap uses kNnDiffAcf1Floor = -0.35 as a refusal
    /// threshold; we compute and expose the value for comparison.
    static func nnDiffAcf1(_ nnMS: [Double]) -> Double? {
        guard nnMS.count >= 2 else { return nil }
        let diffs = (1..<nnMS.count).map { nnMS[$0] - nnMS[$0 - 1] }
        guard diffs.count >= 30 else { return nil }
        let mean = diffs.reduce(0, +) / Double(diffs.count)
        var cov = 0.0
        var varSum = 0.0
        for i in 0..<diffs.count {
            let a = diffs[i] - mean
            varSum += a * a
            if i > 0 {
                let b = diffs[i - 1] - mean
                cov += a * b
            }
        }
        guard varSum > 0 else { return nil }
        return cov / varSum
    }

    /// RR coverage diagnostic: Σ plausible RR ÷ wall-clock span.
    ///
    /// Returns coverage ratio. A value > 1.10 indicates duplicate or
    /// interleaved beats (more beat-time than elapsed time).
    ///
    /// This is an OBSERVATION-ONLY diagnostic. It does not gate or modify
    /// production HRV. OpenStrap uses kRrCoverageCeiling = 1.10.
    static func rrCoverage(_ rrMS: [Double], timestamps: [Int]) -> Double? {
        guard rrMS.count >= 2, rrMS.count == timestamps.count else { return nil }
        var lo = 0, hi = 0
        for i in 1..<timestamps.count {
            if timestamps[i] < timestamps[lo] { lo = i }
            if timestamps[i] > timestamps[hi] { hi = i }
        }
        let first = rrMS[lo]
        let spanSec = (Double(timestamps[hi] - timestamps[lo]) +
                       ((300...2400).contains(first) ? first : 0)) / 1000.0
        guard spanSec >= 600 else { return nil }
        var sum = 0.0
        var seen = Set<Int>()
        for i in 0..<rrMS.count {
            let v = rrMS[i]
            if (300...2400).contains(v) {
                sum += v
            }
            if !seen.insert(timestamps[i]).inserted {
                // duplicate timestamp - counted but not summed
            }
        }
        return (sum / 1000.0) / spanSec
    }

    /// Extended diagnostics including ACF1 and RR coverage.
    struct ExtendedDiagnostics: Encodable {
        let rawRRCount: Int
        let acceptedNNCount: Int
        let coveragePercentage: Double
        let timestampGaps: Int
        let selectedCalculationWindow: String
        let finalRMSSD: Double?
        let finalLnRMSSD: Double?
        // Observation-only jitter/coverage diagnostics
        let nnDiffAcf1: Double?
        let rrCoverageRatio: Double?
        let acf1BelowFloor: Bool?  // true if below -0.35 (OpenStrap floor)
        let rrOverCoverage: Bool?  // true if above 1.10 (OpenStrap ceiling)
    }

    /// Generates extended HRV calculation diagnostics including ACF1 and RR coverage.
    /// These are OBSERVATION-ONLY diagnostics that do not affect production HRV.
    static func extendedDiagnostics(
        samples: [V18Sample],
        swsEpochs: [ClosedRange<Int>] = []
    ) -> ExtendedDiagnostics {
        var uniqueBySecond: [Int: V18Sample] = [:]
        for sample in samples {
            if let previous = uniqueBySecond[sample.unix],
               !preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) {
                continue
            }
            uniqueBySecond[sample.unix] = sample
        }
        let ordered = uniqueBySecond.values.sorted { $0.unix < $1.unix }
        let targetSamples: [V18Sample]
        let windowType: String
        if !swsEpochs.isEmpty {
            let filtered = ordered.filter { sample in
                swsEpochs.contains { $0.contains(sample.unix) }
            }
            if !filtered.isEmpty {
                targetSamples = filtered
                windowType = "SWS_DEEP_SLEEP"
            } else {
                targetSamples = ordered
                windowType = "ALL_VALID_SLEEP"
            }
        } else {
            targetSamples = ordered
            windowType = "ALL_VALID_SLEEP"
        }

        var timestampGaps = 0
        if ordered.count > 1 {
            for i in 1..<ordered.count {
                if ordered[i].unix > ordered[i - 1].unix + 1 {
                    timestampGaps += 1
                }
            }
        }

        var rawBeats = 0
        var rejectionReasons: [String: Int] = [
            "outOfPlausibleRange": 0,
            "ectopicDeviation": 0,
            "seedMismatch": 0
        ]

        let runs = contiguousRuns(targetSamples)
        var allNN: [Double] = []
        var allNNTimestamps: [Int] = []
        var squaredDifferences = 0.0
        var successivePairs = 0

        for run in runs {
            var previous: Double?
            var recent: [Double] = []
            var seedCandidate: Double?
            for sample in run {
                let rr = sample.rrIntervalsMS.map(Double.init)
                rawBeats += rr.count
                if rr.isEmpty {
                    previous = nil; recent.removeAll(); seedCandidate = nil
                    continue
                }
                for (_, value) in rr.enumerated() {
                    guard value >= Double(V18Decoder.minRRMS),
                          value <= Double(V18Decoder.maxRRMS) else {
                        rejectionReasons["outOfPlausibleRange", default: 0] += 1
                        previous = nil; recent.removeAll(); seedCandidate = nil
                        continue
                    }
                    if recent.isEmpty {
                        guard let pending = seedCandidate else {
                            seedCandidate = value
                            continue
                        }
                        let midpoint = Stats.median([pending, value])
                        guard abs(value - pending) <= nnMaxDeviation * midpoint else {
                            rejectionReasons["seedMismatch", default: 0] += 1
                            seedCandidate = value
                            continue
                        }
                        allNN.append(pending)
                        allNNTimestamps.append(sample.unix * 1_000)
                        recent.append(pending)
                        previous = pending
                        seedCandidate = nil
                    } else {
                        let reference = Stats.median(recent)
                        if abs(value - reference) > nnMaxDeviation * reference {
                            rejectionReasons["ectopicDeviation", default: 0] += 1
                            previous = nil
                            recent.removeAll()
                            seedCandidate = nil
                            continue
                        }
                    }
                    if let previous {
                        let delta = value - previous
                        squaredDifferences += delta * delta
                        successivePairs += 1
                    }
                    allNN.append(value)
                    allNNTimestamps.append(sample.unix * 1_000)
                    recent.append(value)
                    if recent.count > nnReferenceBeats { recent.removeFirst() }
                    previous = value
                }
            }
        }

        let acceptedNN = allNN.count
        let coveragePct = rawBeats > 0 ? (Double(acceptedNN) / Double(rawBeats)) * 100.0 : 0.0
        let finalRMSSD: Double? = (acceptedNN >= minCleanBeats && successivePairs > 0)
            ? sqrt(squaredDifferences / Double(successivePairs))
            : nil
        let finalLn: Double? = finalRMSSD.flatMap { $0 > 0 ? log($0) : nil }

        // Observation-only diagnostics
        let acf1 = nnDiffAcf1(allNN)
        let rrCov = rrCoverage(allNN, timestamps: allNNTimestamps)
        let acf1Floor: Double = -0.35  // OpenStrap kNnDiffAcf1Floor
        let rrCeiling: Double = 1.10   // OpenStrap kRrCoverageCeiling

        return ExtendedDiagnostics(
            rawRRCount: rawBeats,
            acceptedNNCount: acceptedNN,
            coveragePercentage: coveragePct,
            timestampGaps: timestampGaps,
            selectedCalculationWindow: windowType,
            finalRMSSD: finalRMSSD,
            finalLnRMSSD: finalLn,
            nnDiffAcf1: acf1,
            rrCoverageRatio: rrCov,
            acf1BelowFloor: acf1.map { $0 < acf1Floor },
            rrOverCoverage: rrCov.map { $0 > rrCeiling }
        )
    }

    /// Computes median-of-5-minute-window RMSSD for SWS/quiet epochs.
    ///
    /// This is an ALTERNATIVE estimator for comparison, not the production
    /// estimator. It splits the NN series into 5-minute windows, computes
    /// RMSSD in each window with >= 20 clean successive differences, and
    /// returns the median across windows.
    static func medianOfWindowedRMSSD(
        _ nnMS: [Double],
        timestamps: [Int],
        windowSeconds: Int = 300
    ) -> Double? {
        guard nnMS.count >= 2, nnMS.count == timestamps.count else { return nil }
        var windows: [Int: [(Double, Int)]] = [:]
        for i in 0..<nnMS.count {
            let windowIdx = timestamps[i] / windowSeconds
            windows[windowIdx, default: []].append((nnMS[i], timestamps[i]))
        }
        var windowRMSSDs: [Double] = []
        for (_, beats) in windows.sorted(by: { $0.key < $1.key }) {
            guard beats.count >= 21 else { continue } // need >= 20 diffs
            let nn = beats.map { $0.0 }
            let ts = beats.map { $0.1 }
            var sqDiff = 0.0
            var pairs = 0
            for j in 1..<nn.count {
                // Only count successive differences within the same contiguous run
                if ts[j] - ts[j - 1] <= 2 { // allow 1-2s gap tolerance
                    let d = nn[j] - nn[j - 1]
                    sqDiff += d * d
                    pairs += 1
                }
            }
            if pairs >= 20 {
                windowRMSSDs.append(sqrt(sqDiff / Double(pairs)))
            }
        }
        guard !windowRMSSDs.isEmpty else { return nil }
        let sorted = windowRMSSDs.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}

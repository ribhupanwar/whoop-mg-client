import Foundation

/// Coverage of received decoded seconds. This describes the transfer, independently
/// of the archive writer's persisted-row progress and ACK write acknowledgements.
struct HistoryCoverage: Equatable {
    let observedSeconds: Int
    let heartRateSeconds: Int
    let rrSeconds: Int
    let motionSeconds: Int
    let missingSeconds: Int
    let repeatedSecondRecords: Int
    let backwardsTransitions: Int

    init(_ samples: [V18Sample]) {
        var channelsBySecond: [Int: UInt8] = [:]
        var earliest: Int?
        var latest: Int?
        var previous: Int?
        var backwards = 0
        for sample in samples {
            let second = sample.unix
            earliest = min(earliest ?? second, second)
            latest = max(latest ?? second, second)
            if let previous, second < previous { backwards += 1 }
            previous = second

            var channels: UInt8 = 0
            if (35...220).contains(sample.heartRate) { channels |= 1 }
            if !sample.rrIntervalsMS.isEmpty { channels |= 2 }
            if let motion = sample.dynamicAccelG, motion.isFinite, motion >= 0 { channels |= 4 }
            channelsBySecond[second, default: 0] |= channels
        }
        var hr = 0
        var rr = 0
        var motion = 0
        for channels in channelsBySecond.values {
            if channels & 1 != 0 { hr += 1 }
            if channels & 2 != 0 { rr += 1 }
            if channels & 4 != 0 { motion += 1 }
        }

        observedSeconds = channelsBySecond.count
        heartRateSeconds = hr
        rrSeconds = rr
        motionSeconds = motion
        if let earliest, let latest {
            missingSeconds = latest - earliest + 1 - observedSeconds
        } else {
            missingSeconds = 0
        }
        repeatedSecondRecords = samples.count - observedSeconds
        backwardsTransitions = backwards
    }

    /// RR totals are computed once per observed second, not by blindly
    /// concatenating retransmitted records. A duration greater than wall-clock
    /// coverage is a diagnostic warning, not proof of a specific bad packet.
    var rrCoverageAudit: RRCoverageAudit {
        RRCoverageAudit(rrSeconds: rrSeconds,
                        observedSeconds: observedSeconds,
                        repeatedSecondRecords: repeatedSecondRecords)
    }


    /// Diagnostic only: compare summed beat durations against the unique
    /// observed-second span. RR intervals can cross second boundaries, so
    /// a small tolerance is necessary and overflow is not automatic rejection.
    /// Prefer the retransmission with the most RR beats for each second,
    /// consistent with Hrv.fromSamples.
    static func beatDurationAudit(_ records: [(second: Int, intervalsMS: [Int])]) -> RRBeatDurationAudit {
        var unique: [Int: [Int]] = [:]
        for record in records {
            if (unique[record.second]?.count ?? -1) < record.intervalsMS.count {
                unique[record.second] = record.intervalsMS
            }
        }
        let total = unique.values.reduce(Int64(0)) { sum, intervals in
            sum + intervals.reduce(Int64(0)) { $0 + Int64(max(0, $1)) }
        }
        let seconds = unique.count
        // Negative/zero RR values must never silently look like valid beats.
        let invalidIntervals = unique.values.reduce(0) { count, intervals in
            count + intervals.filter { $0 <= 0 }.count
        }
        // Two seconds of boundary slack prevents flagging a beat that
        // started before the first record or ended after the last.
        let allowance = Int64(seconds) * 1_000 + 2_000
        return RRBeatDurationAudit(uniqueSeconds: seconds,
                                   invalidIntervals: invalidIntervals,
                                   totalRRDurationMS: total,
                                   exceedsObservedSpan: total > allowance)
    }

    static func beatDurationAudit(_ samples: [V18Sample]) -> RRBeatDurationAudit {
        beatDurationAudit(samples.map { (second: $0.unix, intervalsMS: $0.rrIntervalsMS) })
    }

    var summary: String {
        "Received seconds: \(observedSeconds), HR: \(heartRateSeconds), RR: \(rrSeconds), motion: \(motionSeconds), gaps: \(missingSeconds)s, repeated-second records: \(repeatedSecondRecords), backwards transitions: \(backwardsTransitions)"
    }
}

struct RRCoverageAudit: Equatable {
    let rrSeconds: Int
    let observedSeconds: Int
    let repeatedSecondRecords: Int

    var rrFraction: Double {
        guard observedSeconds > 0 else { return 0 }
        return Double(rrSeconds) / Double(observedSeconds)
    }

    var hasRepeatedSeconds: Bool { repeatedSecondRecords > 0 }

    /// Per-second RR channel presence must not exceed the number of unique
    /// seconds. Raw beat-duration overflow needs a separate packet-level audit.
    var isValid: Bool {
        rrSeconds >= 0 && observedSeconds >= 0
            && rrSeconds <= observedSeconds && repeatedSecondRecords >= 0
    }
}

struct RRBeatDurationAudit: Equatable {
    let uniqueSeconds: Int
    let invalidIntervals: Int
    let totalRRDurationMS: Int64
    /// Warning only; packet timing must be validated before excluding beats.
    let exceedsObservedSpan: Bool
}

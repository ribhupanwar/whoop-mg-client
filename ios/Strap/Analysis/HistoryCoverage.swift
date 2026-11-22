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

    var summary: String {
        "Received seconds: \(observedSeconds), HR: \(heartRateSeconds), RR: \(rrSeconds), motion: \(motionSeconds), gaps: \(missingSeconds)s, repeated-second records: \(repeatedSecondRecords), backwards transitions: \(backwardsTransitions)"
    }
}

import Foundation

/// Experimental sleep-end evidence classifier. No production scoring call sites.
/// This is NOT a port of GGIR/HDCZA: 1 Hz band state and dynamic acceleration
/// cannot substitute for calibrated raw wrist-angle time series.
enum SleepEndResumptionExperiment {
    /// Shadow-only personal night context. Never substitute this value into
    /// detector thresholds, recovery, or a missing current-night measurement.
    struct PersonalNightContext: Encodable {
        let eligibleNights: Int
        let medianNightHeartRate: Double?
        let habitualMidpointLocalSeconds: Int?
        let minimumNights: Int
    }

    static func personalNightContext(prior: [SleepSession], before current: SleepSession,
                                     calendar: Calendar = .current) -> PersonalNightContext {
        let minimumNights = 14
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(current.endUnix - 1)))
        let candidates = prior.filter {
            $0.endUnix > $0.startUnix && $0.endUnix <= current.startUnix
                && $0.isComplete && $0.classification == .overnight
                && $0.bandSleepConfirmed == true
                && $0.timezoneIdentifier == current.timezoneIdentifier
                && Date(timeIntervalSince1970: Double($0.endUnix - 1)) < today
        }
        let groups = Dictionary(grouping: candidates) {
            calendar.startOfDay(for: Date(timeIntervalSince1970: Double($0.endUnix - 1)))
        }
        let nights = groups.keys.sorted().suffix(28).compactMap { key in
            groups[key].flatMap { DailyAnalysis.primaryNight($0) }
        }
        var hrMedians: [Double] = []
        var midpoints: [Double] = []
        for night in nights {
            var minuteHR: [Int: Double] = [:]
            for point in night.heartRate where night.startUnix <= point.unix && point.unix < night.endUnix
                && point.bpm.isFinite && (35...220).contains(point.bpm) {
                minuteHR[point.unix / 60] = point.bpm
            }
            let expected = max(1, (night.endUnix - 1) / 60 - night.startUnix / 60 + 1)
            guard minuteHR.count * 5 >= expected * 4 else { continue }
            hrMedians.append(Stats.median(Array(minuteHR.values)))
            let midpoint = Date(timeIntervalSince1970: Double(night.startUnix)
                + Double(night.endUnix - night.startUnix) / 2)
            let parts = calendar.dateComponents([.hour, .minute, .second], from: midpoint)
            let seconds = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
            // Unwrap around midnight to avoid 23:50 and 00:10 averaging to noon.
            midpoints.append(Double(seconds >= 43200 ? seconds - 86400 : seconds))
        }
        guard hrMedians.count >= minimumNights else {
            return PersonalNightContext(eligibleNights: hrMedians.count, medianNightHeartRate: nil,
                                        habitualMidpointLocalSeconds: nil, minimumNights: minimumNights)
        }
        let midpoint = Int(Stats.median(midpoints).rounded())
        return PersonalNightContext(eligibleNights: hrMedians.count,
            medianNightHeartRate: max(40, Stats.median(hrMedians)),
            habitualMidpointLocalSeconds: (midpoint + 86400) % 86400,
            minimumNights: minimumNights)
    }

    enum Decision: Equatable {
        case resumedSleep(endUnix: Int)
        case confirmedWake(endUnix: Int)
        case insufficientEvidence
    }

    /// Examine a candidate wake and the following observations. Never infer
    /// sleep resumption from quiet HR or low motion alone: a positive band
    /// sleep(2) segment must be observed after the interruption.
    static func evaluate(_ samples: [V18Sample], wakeStartUnix: Int,
                         minimumResumptionSeconds: Int = 300) -> Decision {
        let later = samples.filter { $0.unix >= wakeStartUnix }
            .sorted { $0.unix < $1.unix }
        guard let first = later.first, first.unix <= wakeStartUnix + 2 else {
            return .insufficientEvidence
        }
        var contiguousSleepStart: Int?
        var lastUnix: Int?
        var lastResumedUnix: Int?
        for row in later {
            guard row.wearing, (35...220).contains(row.heartRate),
                  let accel = row.dynamicAccelG, accel.isFinite, accel >= 0 else {
                contiguousSleepStart = nil
                lastUnix = row.unix
                continue
            }
            if row.sleepState == 2 && accel <= 0.08 {
                if let previous = lastUnix, row.unix - previous > 2 {
                    contiguousSleepStart = nil
                }
                if contiguousSleepStart == nil { contiguousSleepStart = row.unix }
                if let start = contiguousSleepStart,
                   row.unix - start + 1 >= minimumResumptionSeconds {
                    lastResumedUnix = row.unix
                }
            } else {
                contiguousSleepStart = nil
            }
            lastUnix = row.unix
        }
        if let end = lastResumedUnix { return .resumedSleep(endUnix: end) }
        // A confirmed wake needs independent HR/motion corroboration, not
        // just persistent coarse up(3), which can stick after a bathroom visit.
        let waking = later.filter {
            $0.sleepState == 3 && $0.wearing
                && ($0.dynamicAccelG ?? 0) >= 0.08
        }
        if waking.count >= 300, let last = waking.last,
           last.unix - waking[0].unix >= 299 {
            return .confirmedWake(endUnix: wakeStartUnix - 1)
        }
        return .insufficientEvidence
    }
}

import Foundation

/// Experimental sleep-end evidence classifier. No production scoring call sites.
/// This is NOT a port of GGIR/HDCZA: 1 Hz band state and dynamic acceleration
/// cannot substitute for calibrated raw wrist-angle time series.
enum SleepEndResumptionExperiment {
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

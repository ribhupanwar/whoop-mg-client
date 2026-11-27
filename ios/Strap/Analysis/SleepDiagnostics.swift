import Foundation

/// A reproducible, night-bound export for comparing stage estimates to an
/// independent reference. Missing rows and missing fields remain missing.
enum SleepDiagnostics {
    enum ExportError: LocalizedError {
        case noNight
        case noSamples
        var errorDescription: String? {
            switch self {
            case .noNight: return "Wait for sleep analysis to finish before exporting a night."
            case .noSamples: return "No retained sensor samples cover this sleep window."
            }
        }
    }

    static let maximumPostSleepSeconds = 3 * 3600

    /// Exclusive upper bound for raw diagnostic context, not a new sleep end.
    static func contextEnd(_ sleepEnd: Int, postSleepSeconds: Int) -> Int {
        let lookahead = min(max(0, postSleepSeconds), maximumPostSleepSeconds)
        let (end, overflow) = sleepEnd.addingReportingOverflow(lookahead)
        return overflow ? Int.max : end
    }

    static func csv(samples: [V18Sample], session: SleepSession,
                    preSleepSeconds: Int = 0, postSleepSeconds: Int = 0) throws -> String {
        // Clamp before subtraction so an imported/corrupt extreme timestamp
        // cannot trap the diagnostic exporter on integer underflow.
        let lookback = min(max(0, preSleepSeconds), 3600)
        let (candidateLowerBound, overflow) = session.startUnix.subtractingReportingOverflow(lookback)
        let lowerBound = overflow ? Int.min : candidateLowerBound
        // Do not label an invalid/empty edited night as a valid export window.
        guard session.startUnix < session.endUnix else { throw ExportError.noNight }
        let upperBound = contextEnd(session.endUnix, postSleepSeconds: postSleepSeconds)
        let rows = samples.filter { lowerBound <= $0.unix && $0.unix < upperBound }
            .sorted {
                if $0.unix != $1.unix { return $0.unix < $1.unix }
                if $0.header.subsecQ15 != $1.header.subsecQ15 {
                    return $0.header.subsecQ15 < $1.header.subsecQ15
                }
                return $0.header.recordIndex < $1.header.recordIndex
            }
        guard !rows.isEmpty else { throw ExportError.noSamples }
        let segments = session.staging.segments.sorted { $0.startUnix < $1.startUnix }
        var segmentIndex = 0
        var result = "window_start_unix,window_end_unix,algorithm_version,unix,record_index,subsec_q15,heart_rate_bpm,rr_ms,dynamic_accel_g,gravity_x_g,gravity_y_g,gravity_z_g,band_state,hr_quality_flags,estimated_stage,skin_temp_c,temp_aux1_c,temp_aux2_c,spo2_candidate_raw,spo2_candidate_pct,spo2_candidate_kind,cardiac_flags,signal_quality_log_variance,step_motion_counter,activity_class,wearing\n"
        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "" }
            return String(value)
        }
        for sample in rows {
            while segmentIndex < segments.count && segments[segmentIndex].endUnix <= sample.unix { segmentIndex += 1 }
            let stage: String
            if session.startUnix <= sample.unix, sample.unix < session.endUnix,
               segmentIndex < segments.count,
               segments[segmentIndex].startUnix <= sample.unix,
               sample.unix < segments[segmentIndex].endUnix {
                stage = segments[segmentIndex].stage.rawValue
            } else { stage = "" }
            var fields: [String] = []
            fields.reserveCapacity(26)
            fields.append(String(session.startUnix))
            fields.append(String(session.endUnix))
            fields.append(String(session.version))
            fields.append(String(sample.unix))
            fields.append(String(sample.header.recordIndex))
            fields.append(String(sample.header.subsecQ15))
            fields.append(String(sample.heartRate))
            fields.append(sample.rrIntervalsMS.map { String($0) }.joined(separator: "|"))
            fields.append(number(sample.dynamicAccelG))
            fields.append(number(sample.gravityXG))
            fields.append(number(sample.gravityYG))
            fields.append(number(sample.gravityZG))
            fields.append(sample.sleepState.map { String($0) } ?? "")
            fields.append(sample.hrQualityFlags.map { String($0) } ?? "")
            fields.append(stage)
            fields.append(number(sample.skinTempC))
            fields.append(number(sample.tempAux1C))
            fields.append(number(sample.tempAux2C))
            fields.append(sample.spo2CandidateRaw.map { String($0) } ?? "")
            fields.append(sample.spo2CandidatePct.map { String($0) } ?? "")
            fields.append(sample.spo2CandidateKind.rawValue)
            fields.append(sample.cardiacFlags.map { String($0) } ?? "")
            fields.append(number(sample.signalQualityLogVariance))
            fields.append(sample.stepCounter.map { String($0) } ?? "")
            fields.append(sample.activityClass.map { String($0) } ?? "")
            fields.append(sample.wearing ? "1" : "0")
            result += fields.joined(separator: ",") + "\n"
        }
        return result
    }

    static func write(samples: [V18Sample], session: SleepSession, directory: URL,
                      preSleepSeconds: Int = 0, postSleepSeconds: Int = 0) throws -> URL {
        let contents = try csv(samples: samples, session: session,
                               preSleepSeconds: preSleepSeconds, postSleepSeconds: postSleepSeconds)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sleep-\(session.startUnix)-\(session.endUnix)-\(UUID().uuidString).csv")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}

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

    static func csv(samples: [V18Sample], session: SleepSession) throws -> String {
        let rows = samples.filter { session.startUnix <= $0.unix && $0.unix < session.endUnix }
            .sorted { $0.unix < $1.unix }
        guard !rows.isEmpty else { throw ExportError.noSamples }
        let segments = session.staging.segments.sorted { $0.startUnix < $1.startUnix }
        var segmentIndex = 0
        var result = "window_start_unix,window_end_unix,algorithm_version,unix,record_index,subsec_q15,heart_rate_bpm,rr_ms,dynamic_accel_g,gravity_x_g,gravity_y_g,gravity_z_g,band_state,hr_quality_flags,estimated_stage\n"
        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "" }
            return String(value)
        }
        for sample in rows {
            while segmentIndex < segments.count && segments[segmentIndex].endUnix <= sample.unix { segmentIndex += 1 }
            let stage: String
            if segmentIndex < segments.count, segments[segmentIndex].startUnix <= sample.unix {
                stage = segments[segmentIndex].stage.rawValue
            } else { stage = "" }
            let fields = [
                String(session.startUnix), String(session.endUnix), String(session.version), String(sample.unix),
                String(sample.header.recordIndex), String(sample.header.subsecQ15), String(sample.heartRate),
                sample.rrIntervalsMS.map(String.init).joined(separator: "|"),
                number(sample.dynamicAccelG), number(sample.gravityXG), number(sample.gravityYG), number(sample.gravityZG),
                sample.sleepState.map(String.init) ?? "", sample.hrQualityFlags.map(String.init) ?? "", stage
            ]
            result += fields.joined(separator: ",") + "\n"
        }
        return result
    }

    static func write(samples: [V18Sample], session: SleepSession, directory: URL) throws -> URL {
        let contents = try csv(samples: samples, session: session)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sleep-\(session.startUnix)-\(session.endUnix)-\(UUID().uuidString).csv")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}

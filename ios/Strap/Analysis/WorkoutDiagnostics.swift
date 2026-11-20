import Foundation

/// A reproducible, workout-bound export for comparing gym sessions and physical
/// exertion against WHOOP or another reference device in controlled dual-band trials.
/// Missing rows and missing fields remain missing without interpolation.
enum WorkoutDiagnostics {
    enum ExportError: LocalizedError {
        case noWorkout
        case noSamples
        var errorDescription: String? {
            switch self {
            case .noWorkout: return "No workout activity selected or valid time bounds provided."
            case .noSamples: return "No retained sensor samples cover this workout window."
            }
        }
    }

    struct WorkoutSummary {
        let activityKind: String
        let startUnix: Int
        let endUnix: Int
        let meanHR: Double?
        let maxHR: Double?
        let workoutStrain: Double?
        let dayStrain: Double?
        let activeKcal: Double?
        let steps: Int
        let detectionConfidence: String
        let detectionReason: String
        let firmwareVersion: String
        let decoderVersion: String
    }

    static func csv(
        samples: [V18Sample],
        summary: WorkoutSummary,
        preActivitySeconds: Int = 60,
        postActivitySeconds: Int = 60
    ) throws -> String {
        guard summary.startUnix < summary.endUnix else { throw ExportError.noWorkout }
        
        let lookback = min(max(0, preActivitySeconds), 3600)
        let lookahead = min(max(0, postActivitySeconds), 3600)
        
        let (lowerCandidate, underflow) = summary.startUnix.subtractingReportingOverflow(lookback)
        let lowerBound = underflow ? Int.min : lowerCandidate
        
        let (upperCandidate, overflow) = summary.endUnix.addingReportingOverflow(lookahead)
        let upperBound = overflow ? Int.max : upperCandidate

        let rows = samples.filter { lowerBound <= $0.unix && $0.unix <= upperBound }
            .sorted {
                if $0.unix != $1.unix { return $0.unix < $1.unix }
                if $0.header.subsecQ15 != $1.header.subsecQ15 {
                    return $0.header.subsecQ15 < $1.header.subsecQ15
                }
                return $0.header.recordIndex < $1.header.recordIndex
            }

        guard !rows.isEmpty else { throw ExportError.noSamples }

        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "" }
            return String(format: "%.4f", value)
        }

        func intVal(_ value: Int?) -> String {
            guard let value else { return "" }
            return String(value)
        }

        var csv = "# STRAP Controlled Workout Telemetry Export\n"
        csv += "# Activity: \(summary.activityKind)\n"
        csv += "# Start: \(summary.startUnix) | End: \(summary.endUnix) | Duration: \(summary.endUnix - summary.startUnix)s\n"
        csv += "# Mean HR: \(summary.meanHR.map { String(format: "%.1f", $0) } ?? "—") bpm | Max HR: \(summary.maxHR.map { String(format: "%.1f", $0) } ?? "—") bpm\n"
        csv += "# Workout Strain: \(summary.workoutStrain.map { String(format: "%.2f", $0) } ?? "—") | Day Strain: \(summary.dayStrain.map { String(format: "%.2f", $0) } ?? "—")\n"
        csv += "# Active Kcal: \(summary.activeKcal.map { String(format: "%.1f", $0) } ?? "—") | Steps: \(summary.steps)\n"
        csv += "# Detection Confidence: \(summary.detectionConfidence) | Reason: \(summary.detectionReason)\n"
        csv += "# Firmware: \(summary.firmwareVersion) | Decoder: \(summary.decoderVersion)\n"
        csv += "unix,iso8601,record_index,subsec_q15,heart_rate_bpm,rr_ms,dynamic_accel_g,gravity_x_g,gravity_y_g,gravity_z_g,band_state,hr_quality_flags,is_workout_epoch\n"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for sample in rows {
            let isWorkout = (summary.startUnix <= sample.unix && sample.unix < summary.endUnix) ? "1" : "0"
            let dt = Date(timeIntervalSince1970: TimeInterval(sample.unix) + Double(sample.header.subsecQ15) / 32768.0)
            let isoStr = isoFormatter.string(from: dt)
            let rrStr = sample.rrIntervalsMS.map { String($0) }.joined(separator: "|")

            var fields: [String] = []
            fields.reserveCapacity(13)
            fields.append(String(sample.unix))
            fields.append(isoStr)
            fields.append(String(sample.header.recordIndex))
            fields.append(String(sample.header.subsecQ15))
            fields.append(String(sample.heartRate))
            fields.append(rrStr)
            fields.append(number(sample.dynamicAccelG))
            fields.append(number(sample.gravityXG))
            fields.append(number(sample.gravityYG))
            fields.append(number(sample.gravityZG))
            fields.append(sample.sleepState.map { String($0) } ?? "")
            fields.append(sample.hrQualityFlags.map { String($0) } ?? "")
            fields.append(isWorkout)

            csv += fields.joined(separator: ",") + "\n"
        }

        return csv
    }

    static func write(
        samples: [V18Sample],
        summary: WorkoutSummary,
        directory: URL,
        preActivitySeconds: Int = 60,
        postActivitySeconds: Int = 60
    ) throws -> URL {
        let contents = try csv(
            samples: samples,
            summary: summary,
            preActivitySeconds: preActivitySeconds,
            postActivitySeconds: postActivitySeconds
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = summary.activityKind.lowercased().replacingOccurrences(of: " ", with: "_")
        let url = directory.appendingPathComponent("workout-\(safeName)-\(summary.startUnix)-\(summary.endUnix).csv")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}

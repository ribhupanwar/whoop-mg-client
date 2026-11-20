import Foundation

/// Forensic Raw Telemetry CSV exporter for WHOOP 5.0 / MG comparative analysis.
/// Exports complete 14-column V18 records including subsecond clocks, dynamic accel,
/// 3-axis gravity, pedometer cadence, temperature sensors, and on-band state flags.
enum RawTelemetryDiagnostics {
    enum ExportError: LocalizedError {
        case noSamples
        var errorDescription: String? {
            "No sensor samples available in the selected window for raw export."
        }
    }

    static func csv(samples: [V18Sample]) throws -> String {
        guard !samples.isEmpty else { throw ExportError.noSamples }
        let sorted = samples.sorted {
            if $0.unix != $1.unix { return $0.unix < $1.unix }
            if $0.header.subsecQ15 != $1.header.subsecQ15 {
                return $0.header.subsecQ15 < $1.header.subsecQ15
            }
            return $0.header.recordIndex < $1.header.recordIndex
        }

        func formatDouble(_ val: Double?) -> String {
            guard let val, val.isFinite else { return "" }
            return String(format: "%.4f", val)
        }

        var csv = "unix,record_index,subsec_q15,heart_rate_bpm,rr_ms,dynamic_accel_g,gravity_x_g,gravity_y_g,gravity_z_g,step_counter,step_cadence,activity_class,skin_temp_c,band_state,hr_quality_flags\n"
        for s in sorted {
            var fields: [String] = []
            fields.reserveCapacity(15)
            fields.append(String(s.unix))
            fields.append(String(s.header.recordIndex))
            fields.append(String(s.header.subsecQ15))
            fields.append(String(s.heartRate))
            fields.append(s.rrIntervalsMS.map(String.init).joined(separator: "|"))
            fields.append(formatDouble(s.dynamicAccelG))
            fields.append(formatDouble(s.gravityXG))
            fields.append(formatDouble(s.gravityYG))
            fields.append(formatDouble(s.gravityZG))
            fields.append(s.stepCounter.map(String.init) ?? "")
            fields.append(s.stepCadence.map(String.init) ?? "")
            fields.append(s.activityClass.map(String.init) ?? "")
            fields.append(formatDouble(s.skinTempC))
            fields.append(s.sleepState.map(String.init) ?? "")
            fields.append(s.hrQualityFlags.map(String.init) ?? "")
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    static func write(samples: [V18Sample], directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let content = try csv(samples: samples)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "STRAP-raw-telemetry-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).csv"
        let url = directory.appendingPathComponent(filename)
        try Data(content.utf8).write(to: url, options: .atomic)
        return url
    }
}

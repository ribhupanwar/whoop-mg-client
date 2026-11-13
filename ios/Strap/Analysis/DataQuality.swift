import Foundation

/// Explain measured data coverage without inventing sensor values.
enum DataQuality {
    struct Item: Identifiable {
        let name: String
        let available: Int
        let total: Int
        let reason: String
        var id: String { name }
        var percentage: Int { total > 0 ? Int((100.0 * Double(available) / Double(total)).rounded()) : 0 }
    }

    static func inspect(_ summary: CaptureSummary?) -> [Item] {
        guard let summary, summary.sampleCount > 0 else {
            return [Item(name: "Capture", available: 0, total: 0,
                         reason: "No band history has been analyzed yet. Connect and sync your band.")]
        }
        let total = summary.sampleCount
        return [
            Item(name: "On-wrist HR", available: summary.wearingCount, total: total,
                 reason: "Off-wrist and missing records cannot support HR-based estimates."),
            Item(name: "Steps", available: summary.steps == nil ? 0 : total, total: total,
                 reason: summary.steps == nil ? "No decoded step counter in this capture." :
                    "Step totals exclude counter resets and large gaps; coverage is not measured per record."),
            Item(name: "HRV", available: summary.hrv.rmssdMS == nil ? 0 : 1, total: 1,
                 reason: summary.hrv.rmssdMS == nil ? "No qualifying resting R-R window." :
                    "Resting R-R estimate available."),
            Item(name: "Sleep stages", available: summary.latestSleepSession?.isComplete == true ? 1 : 0,
                 total: 1, reason: summary.latestSleepSession?.durationReason ??
                    "A complete estimated night is required for reliable sleep duration."),
            Item(name: "Activity detection", available: summary.activities.count, total: max(1, summary.activities.count),
                 reason: summary.activities.isEmpty ?
                    "No sustained motion/HR session met detection thresholds." :
                    "Detected sessions require measured evidence; verify against your workout log.")
        ]
    }
}

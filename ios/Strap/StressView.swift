import SwiftUI

/// Stress detail — a local 0–3 estimate, explicitly not any proprietary
/// algorithm. Live mode is unavailable until the awake-quiet baseline exists.
struct StressView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                gaugePanel
                seriesPanel
                totalDayPanel
                outsideWorkoutsPanel
            }
        }
        .navigationTitle("Stress monitor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var gaugePanel: some View {
        Panel {
            ZStack {
                StressGauge(value: demo ? SampleData.stressGauge : stressIndex)
                VStack(spacing: 5) {
                    Text(demo ? String(format: "%.1f", SampleData.stressGauge) : gaugeValue)
                        .font(.system(size: 33, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text(demo ? "HIGH · SAMPLE" : "\(store.band.stress.band.uppercased())")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.0)
                        .foregroundStyle(demo ? Color.appWarn : Color.appMuted)
                }
                .position(x: 115, y: 72)
            }
            .frame(width: 230, height: 124)
            .frame(maxWidth: .infinity)

            HStack {
                Text("0.0 low")
                Spacer()
                Text("1.5")
                Spacer()
                Text("3.0 high")
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.appMuted)
            .padding(.horizontal, 6)
            .padding(.top, 2)

            if !demo {
                Text(stressStateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(stressIndex == nil ? Color.appWarn : Color.appGood)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
            }

            Hint("local estimate — SD of lnRMSSD below your awake-quiet norm, not WHOOP's algorithm")
        }
    }

    private var stressIndex: Double? { store.band.stress.index }

    private var gaugeValue: String {
        guard let index = stressIndex else { return "—" }
        return String(format: "%.1f", index)
    }

    private var stressStateText: String {
        if let reason = store.band.stress.reason { return reason }
        return "\(store.recordedDayCount) awake baseline days recorded"
    }

    private var seriesPanel: some View {
        Panel {
            SectionTitle("Stress through the day")
            if demo {
                LineChart(
                    values: SampleData.stressDaySeries,
                    color: .appGood,
                    minY: 0,
                    maxY: 3,
                    height: 130,
                    yLabels: ["3.0", "1.5", "0.0"],
                    xLabels: ["00:00", "12:00", "24:00"]
                )
            } else {
                EmptyState(
                    title: "No stress series yet",
                    detail: "Needs 7 days of awake-quiet baseline plus a full day of wear."
                )
            }
        }
    }

    private var totalDayPanel: some View {
        Panel {
            SectionTitle("Total day")
            if demo {
                SplitBar(segments: [
                    SplitBar.Segment(fraction: 0.47, color: .appAccent),
                    SplitBar.Segment(fraction: 0.27, color: .appGood),
                    SplitBar.Segment(fraction: 0.26, color: .appWarn)
                ])
                .padding(.bottom, 10)

                HStack(spacing: 8) {
                    splitValue("11:14", label: "low")
                    splitValue("6:42", label: "medium")
                    splitValue("4:03", label: "high")
                }
            } else if let split = awakeStress {
                SplitBar(segments: segments(for: split))
                    .padding(.bottom, 10)
                HStack(spacing: 8) {
                    splitValue(durationText(split.lowPct, in: split), label: "low")
                    splitValue(durationText(split.mediumPct, in: split), label: "medium")
                    splitValue(durationText(split.highPct, in: split), label: "high")
                }
                Hint("Awake windows only, scored against your awake baseline; \(split.windows) five-minute windows. Sleep windows are excluded.")
            } else {
                EmptyState(
                    title: "No awake stress windows yet",
                    detail: store.band.summary?.awakeStress?.reason
                        ?? "Needs 7 awake-baseline days plus R-R beats outside sleep in the last capture."
                )
            }
        }
    }

    private var outsideWorkoutsPanel: some View {
        Panel {
            SectionTitle("Outside workouts")
            if demo {
                SplitBar(segments: [
                    SplitBar.Segment(fraction: 0.30, color: .appAccent),
                    SplitBar.Segment(fraction: 0.40, color: .appGood),
                    SplitBar.Segment(fraction: 0.30, color: .appWarn)
                ])
            } else if let split = outsideWorkoutStress {
                SplitBar(segments: segments(for: split))
                    .padding(.bottom, 10)
                HStack(spacing: 8) {
                    splitValue(durationText(split.lowPct, in: split), label: "low")
                    splitValue(durationText(split.mediumPct, in: split), label: "medium")
                    splitValue(durationText(split.highPct, in: split), label: "high")
                }
            }
            Hint("Training stress is the point. This strips workouts out so you can see whether the rest of your day is also running hot — for a daily trainer that matters more than the all-day number.")
        }
    }

    private var awakeStress: StressSplit? {
        guard let split = store.band.summary?.awakeStress, split.lowPct != nil else { return nil }
        return split
    }

    private var outsideWorkoutStress: StressSplit? {
        guard let split = store.band.summary?.outsideWorkoutStress, split.lowPct != nil else {
            return nil
        }
        return split
    }

    private func segments(for split: StressSplit) -> [SplitBar.Segment] {
        [
            SplitBar.Segment(fraction: (split.lowPct ?? 0) / 100.0, color: .appAccent),
            SplitBar.Segment(fraction: (split.mediumPct ?? 0) / 100.0, color: .appGood),
            SplitBar.Segment(fraction: (split.highPct ?? 0) / 100.0, color: .appWarn)
        ]
    }

    private func durationText(_ pct: Double?, in split: StressSplit) -> String {
        guard let pct else { return "—" }
        let hours = StressWindows.scoredSeconds(split) * pct / 100.0 / 3600.0
        return CoachFormat.duration(hours)
    }

    private func splitValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
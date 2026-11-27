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
        .navigationTitle("STRESS MONITOR")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var gaugePanel: some View {
        Panel {
            ZStack {
                StressGauge(value: demo ? SampleData.stressGauge : stressIndex)
                VStack(spacing: 5) {
                    Text(demo ? String(format: "%.1f", SampleData.stressGauge) : gaugeValue)
                        .font(StrapTypography.metric(36, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    Text(demo ? "HIGH · SAMPLE" : (lastMeasured != nil ? "LAST MEASURED" : (stressIndex == nil ? "UNAVAILABLE" : store.band.stress.band.uppercased())))
                        .font(StrapTypography.body(11, weight: .medium))
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
            .font(StrapTypography.body(10))
            .foregroundStyle(Color.appMuted)
            .padding(.horizontal, 6)
            .padding(.top, 2)

            if !demo {
                Text(stressStateText)
                    .font(StrapTypography.body(12, weight: .medium))
                    .foregroundStyle(store.band.stress.index == nil ? Color.appWarn : Color.appGood)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
            }

            Hint("local estimate — SD of lnRMSSD below your awake-quiet norm, not WHOOP's algorithm")
        }
    }

    private var lastMeasured: StressPoint? {
        store.band.stress.lastMeasuredPoint(in: store.band.summary?.stressSeries)
    }

    private var stressIndex: Double? { store.band.stress.index ?? lastMeasured?.index }

    private var gaugeValue: String {
        guard let index = stressIndex else { return "—" }
        return String(format: "%.1f", index)
    }

    private var stressStateText: String {
        if let point = lastMeasured {
            let time = Date(timeIntervalSince1970: Double(point.unix)).formatted(date: .omitted, time: .shortened)
            return "Stale · last measured at \(time). Waiting for a new qualifying R-R window."
        }
        if let reason = store.band.stress.reason { return reason }
        if let diagnostics = store.band.stress.diagnostics,
           let deviation = diagnostics.unclampedScore, deviation <= 0 {
            return "Low estimate: HRV at or above your awake baseline"
        }
        return "Awake-quiet baseline available"
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
            } else if let series = store.band.summary?.stressSeries,
                      !StressDayChart.todayPoints(series).isEmpty {
                StressDayChart(points: series, height: 130)
                HStack {
                    Text("00:00")
                    Spacer()
                    Text("12:00")
                    Spacer()
                    Text("24:00")
                }
                .font(StrapTypography.body(10))
                .foregroundStyle(Color.appMuted)
                Hint("Qualifying awake 5-minute windows only; missing intervals are not measured. Local estimate, not WHOOP's algorithm.")
            } else {
                EmptyState(
                    title: "No stress series yet",
                    detail: store.band.summary?.awakeStress?.reason
                        ?? "Needs 7 days of awake-quiet baseline plus R-R beats outside sleep in the last capture."
                )
            }
        }
    }

    private func stressTimeLabels(_ series: [StressPoint]) -> [String] {
        guard let first = series.first, let last = series.last else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let stamps = [first.unix, series[series.count / 2].unix, last.unix]
        return stamps.map { formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0))) }
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
        guard let pct, let seconds = StressWindows.scoredSeconds(split) else { return "—" }
        let hours = seconds * pct / 100.0 / 3600.0
        return CoachFormat.duration(hours)
    }

    private func splitValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(StrapTypography.body(15, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(label)
                .font(StrapTypography.body(10))
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Local-day, timestamp-positioned series. Do not interpolate unmeasured gaps.
struct StressDayChart: View {
    let points: [StressPoint]
    var height: CGFloat = 60

    static func todayPoints(_ points: [StressPoint], now: Date = Date(),
                            calendar: Calendar = .current) -> [StressPoint] {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return [] }
        return points.filter {
            let stamp = Double($0.unix)
            return stamp >= day.start.timeIntervalSince1970 && stamp <= now.timeIntervalSince1970
                && stamp < day.end.timeIntervalSince1970 && $0.index.isFinite
                && (0...3).contains($0.index)
        }.sorted { $0.unix < $1.unix }
    }

    var body: some View {
        Canvas { context, size in
            let now = Date()
            guard let day = Calendar.current.dateInterval(of: .day, for: now) else { return }
            let visible = Self.todayPoints(points, now: now)
            var previous: StressPoint?
            var previousPosition: CGPoint?
            for reading in visible {
                let x = size.width * CGFloat((Double(reading.unix) - day.start.timeIntervalSince1970) / day.duration)
                let y = 3 + max(0, size.height - 6) * CGFloat(1 - reading.index / 3)
                let position = CGPoint(x: x, y: y)
                let color: Color = reading.index >= Recovery.stressHighSD ? .appWarn :
                    (reading.index >= Recovery.stressElevatedSD ? .appAccent : .appGood)
                if let previous, let previousPosition,
                   reading.unix - previous.unix == StressWindows.windowSeconds {
                    var line = Path()
                    line.move(to: previousPosition)
                    line.addLine(to: position)
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(color))
                previous = reading
                previousPosition = position
            }
        }
        .frame(height: height)
        .accessibilityLabel("Today's recorded stress windows, with gaps for missing data")
    }
}

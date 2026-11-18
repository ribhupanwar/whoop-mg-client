import SwiftUI

/// Reference-sized sleep charts. A nil point leaves a visible day-sized gap.
/// The last column is the selected day, including when it has no reading.
struct SleepTrendChart: View {
    enum Style { case bars, line, stacked, range }
    let dates: [Date]
    let values: [Double?]
    var secondary: [Double?] = []
    var tertiary: [Double?] = []
    var style: Style = .bars
    var maximum: Double = 100
    var minimum: Double = 0
    var color: Color = .appSleep
    var secondaryColor: Color = .appGood
    var tertiaryColor: Color = .appWarn
    var format: (Double) -> String = { "\(Int($0.rounded()))%" }
    var secondaryFormat: ((Double) -> String)? = nil

    private let plotHeight: CGFloat = 200
    private func value(_ series: [Double?], _ index: Int) -> Double? {
        guard series.indices.contains(index), let v = series[index], v.isFinite else { return nil }
        return v
    }
    private func y(_ value: Double) -> CGFloat {
        let fraction = CGFloat(min(1, max(0, (value - minimum) / max(0.001, maximum - minimum))))
        return plotHeight * (style == .range ? fraction : 1 - fraction)
    }
    var body: some View {
        GeometryReader { geometry in
            let slot = geometry.size.width / CGFloat(max(1, dates.count))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: slot * 0.62, height: plotHeight + 44)
                    .offset(x: slot * (CGFloat(max(0, dates.count - 1)) + 0.19), y: -3)
                ForEach(0...4, id: \.self) { tick in
                    Path { path in
                        let ordinate = plotHeight * CGFloat(tick) / 4
                        path.move(to: CGPoint(x: 0, y: ordinate))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: ordinate))
                    }.stroke(Color.appLine, lineWidth: 0.7)
                }
                if style == .line {
                    seriesPath(values, slot: slot).stroke(color.opacity(0.65), lineWidth: 1.7)
                    seriesPath(secondary, slot: slot).stroke(secondaryColor.opacity(0.65), lineWidth: 1.7)
                }
                ForEach(dates.indices, id: \.self) { index in
                    let x = slot * (CGFloat(index) + 0.5)
                    if let v = value(values, index) {
                        if style == .line {
                            marker(color).position(x: x, y: y(v))
                            annotation(format(v), color: color).position(x: x, y: min(plotHeight - 6, y(v) + 14))
                            if let other = value(secondary, index) {
                                marker(secondaryColor).position(x: x, y: y(other))
                                annotation((secondaryFormat ?? format)(other), color: secondaryColor)
                                    .position(x: x, y: max(8, y(other) - 13))
                            }
                        } else if style == .range {
                            if let end = value(secondary, index) {
                                RoundedRectangle(cornerRadius: 2).fill(color)
                                    .frame(width: 15, height: max(2, abs(y(end) - y(v))))
                                    .position(x: x, y: (y(v) + y(end)) / 2)
                                annotation(format(v), color: color).position(x: x, y: y(v) - 11)
                                annotation((secondaryFormat ?? format)(end), color: color).position(x: x, y: y(end) + 11)
                            }
                        } else {
                            let second = value(secondary, index) ?? 0
                            let third = value(tertiary, index) ?? 0
                            let total = style == .stacked ? v + second + third : v
                            VStack(spacing: 1.5) {
                                if style == .stacked {
                                    if third > 0 { tertiaryColor.frame(height: max(1, plotHeight - y(third))) }
                                    if second > 0 { secondaryColor.frame(height: max(1, plotHeight - y(second))) }
                                }
                                color.frame(height: max(0, plotHeight - y(v)))
                            }
                            .frame(width: 15)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                            .position(x: x, y: plotHeight - (plotHeight - y(total)) / 2)
                            annotation(format(total), color: style == .stacked ? .appFG : color)
                                .position(x: x, y: max(8, y(total) - 12))
                        }
                    }
                    VStack(spacing: 3) {
                        Text(dates[index].formatted(.dateTime.weekday(.abbreviated)))
                        Text(dates[index].formatted(.dateTime.day()))
                    }
                    .font(StrapTypography.body(10, weight: index == dates.count - 1 ? .bold : .regular))
                    .foregroundStyle(index == dates.count - 1 ? Color.appFG : Color.appMuted)
                    .position(x: x, y: plotHeight + 24)
                }
            }
        }
        .frame(height: plotHeight + 44)
        .padding(.top, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dates.indices.map { index in
            "\(dates[index].formatted(date: .abbreviated, time: .omitted)): \(value(values, index).map(format) ?? "No reading")"
        }.joined(separator: ", "))
    }
    private func annotation(_ text: String, color: Color) -> some View {
        Text(text).font(StrapTypography.metric(12, weight: .bold)).foregroundStyle(color)
    }
    private func marker(_ color: Color) -> some View {
        Circle().fill(Color.appSurface).frame(width: 7, height: 7)
            .overlay(Circle().stroke(color, lineWidth: 1.8))
    }
    private func seriesPath(_ series: [Double?], slot: CGFloat) -> Path {
        Path { path in
            var connected = false
            for index in dates.indices {
                guard let v = value(series, index) else { connected = false; continue }
                let point = CGPoint(x: slot * (CGFloat(index) + 0.5), y: y(v))
                if connected { path.addLine(to: point) } else { path.move(to: point) }
                connected = true
            }
        }
    }
}

/// True timestamped stage segments; unclassified time remains a hatched gap.
struct SleepEfficiencyTimeline: View {
    let session: SleepSession
    var body: some View {
        VStack(spacing: 12) {
            timeline(awake: false)
            timeline(awake: true)
        }
    }
    private func timeline(awake: Bool) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                SleepHatchedTrack()
                ForEach(session.staging.segments) { segment in
                    let start = max(session.startUnix, segment.startUnix)
                    let end = min(session.endUnix, segment.startUnix + segment.durationS)
                    // Reject out-of-window and empty segments instead of drawing
                    // a zero-width rectangle beyond the recorded timeline.
                    if end > start && (segment.stage == .wake) == awake {
                        let span = Double(max(1, session.endUnix - session.startUnix))
                        Rectangle()
                            .fill(awake ? Color(hex: 0xD2D5D7) : Color.appSleep)
                            .frame(width: geometry.size.width * CGFloat(Double(end - start) / span))
                            .offset(x: geometry.size.width * CGFloat(Double(start - session.startUnix) / span))
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 3))
        }.frame(height: 15)
    }
}

struct SleepHatchedTrack: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.appRaised.opacity(0.5)))
            var path = Path()
            stride(from: -size.height, to: size.width, by: 7).forEach { x in
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
            }
            context.stroke(path, with: .color(Color.appMuted.opacity(0.2)), lineWidth: 3)
        }
    }
}

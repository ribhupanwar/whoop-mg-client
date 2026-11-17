import SwiftUI

/// A timestamped plot: no line joins missing minute buckets.
struct SleepHeartRateChart: View {
    let session: SleepSession
    // Sorting and clipping are presentation-only: never rewrite recorded sensor data.
    private var validIndices: [Int] {
        Self.sanitizedIndices(
            session.heartRate.map { (unix: $0.unix, bpm: $0.bpm) },
            start: session.startUnix, end: session.endUnix
        )
    }

    static func sanitizedIndices(_ points: [(unix: Int, bpm: Double)], start: Int, end: Int) -> [Int] {
        guard end > start else { return [] }
        return points.indices.filter { index in
            let point = points[index]
            return point.unix >= start && point.unix <= end
                && point.bpm.isFinite && point.bpm > 0
        }.sorted { a, b in
            if points[a].unix == points[b].unix { return a < b }
            return points[a].unix < points[b].unix
        }
    }

    private var low: Double {
        let minimum = validIndices.map { session.heartRate[$0].bpm }.min() ?? 30
        return min(30, floor(minimum - 2))
    }
    private var high: Double {
        let maximum = validIndices.map { session.heartRate[$0].bpm }.max() ?? 110
        return max(110, ceil(maximum + 2))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                VStack {
                    Text(String(format: "%.0f", high))
                    Spacer()
                    Text(String(format: "%.0f", (high + low) / 2))
                    Spacer()
                    Text(String(format: "%.0f", low))
                }
                .font(StrapTypography.body(9))
                .foregroundStyle(Color.appMuted)
                .frame(width: 25)
                GeometryReader { geometry in
                    ZStack {
                        Path { path in
                            for x in [CGFloat.zero, geometry.size.width] {
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                            }
                        }
                        .stroke(Color.appMuted.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        Path { path in
                            for fraction in [0.0, 0.5, 1.0] {
                                let y = geometry.size.height * CGFloat(fraction)
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                        }.stroke(Color.appLine, lineWidth: 1)
                        Path { path in
                            var previous: Int?
                            let span = Double(max(1, session.endUnix - session.startUnix))
                            for index in validIndices {
                                let point = session.heartRate[index]
                                let x = geometry.size.width * CGFloat(Double(point.unix - session.startUnix) / span)
                                let y = geometry.size.height * CGFloat(1 - (point.bpm - low) / max(1, high - low))
                                let position = CGPoint(x: x, y: y)
                                if let previous, point.unix - previous <= 90 {
                                    path.addLine(to: position)
                                } else {
                                    path.move(to: position)
                                }
                                previous = point.unix
                            }
                        }.stroke(Color.appSleep, lineWidth: 1.2)
                    }
                }
            }.frame(height: 160)
            HStack {
                Text(clock(session.startUnix))
                Spacer()
                Text(clock(session.endUnix))
            }
            .font(StrapTypography.metric(10))
            .foregroundStyle(Color.appFG)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep heart rate, \(clock(session.startUnix)) to \(clock(session.endUnix)), \(validIndices.count) in-window recorded minute buckets. Missing intervals are gaps.")
    }

    private func clock(_ unix: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }
}

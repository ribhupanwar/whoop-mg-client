import SwiftUI

/// A timestamped plot: no line joins missing minute buckets.
struct SleepHeartRateChart: View {
    let session: SleepSession
    private var low: Double { floor(session.heartRate.map(\.bpm).min() ?? 40) - 2 }
    private var high: Double { ceil(session.heartRate.map(\.bpm).max() ?? 80) + 2 }

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
                .font(.system(size: 9))
                .foregroundStyle(Color.appMuted)
                .frame(width: 25)
                GeometryReader { geometry in
                    ZStack {
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
                            for point in session.heartRate {
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
                        }.stroke(Color.appAccent, lineWidth: 1.5)
                    }
                }
            }.frame(height: 120)
            HStack {
                Text(clock(session.startUnix))
                Spacer()
                Text(clock(session.endUnix))
            }
            .font(.system(size: 9))
            .foregroundStyle(Color.appMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep heart rate, \(clock(session.startUnix)) to \(clock(session.endUnix)), \(session.heartRate.count) recorded minute buckets. Missing intervals are gaps.")
    }

    private func clock(_ unix: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }
}

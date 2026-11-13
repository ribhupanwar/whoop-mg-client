import SwiftUI

struct CombinedLoadChart: View {
    @EnvironmentObject private var store: AppStore
    private var points: [MetricDay] {
        if store.isPreview { return MetricTimeline.preview(ending: Date(), count: 7) }
        return MetricTimeline.make(days: store.band.days, live: [], manual: [], caloriesByDay: [:],
                            ending: Date(), count: 7, sleepNeedHours: store.settings.sleepNeedHours)
    }
    var body: some View {
        let days = points
        Panel {
            CardHead(title: "Strain & Recovery", trailing: "7 days")
            GeometryReader { geometry in
                let plotH: CGFloat = 180
                let left: CGFloat = 22
                let width = max(1, geometry.size.width - 52)
                let slot = width / CGFloat(max(1, days.count))
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4) { tick in
                        let y = plotH * CGFloat(tick) / 3
                        Path { p in p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: left + width, y: y)) }
                            .stroke(Color.appLine, lineWidth: 1)
                        Text("\(21 - tick * 7)").font(.system(size: 8)).foregroundStyle(Color.appAccent).position(x: 9, y: y)
                        Text("\(100 - Int((Double(tick) * 100 / 3).rounded()))%")
                            .font(.system(size: 8)).foregroundStyle(Color.appMuted).position(x: left + width + 18, y: y)
                    }
                    if !days.isEmpty {
                        RoundedRectangle(cornerRadius: 4).fill(Color.appFG.opacity(0.08))
                            .frame(width: slot * 0.82, height: plotH + 44)
                            .position(x: left + width - slot / 2, y: (plotH + 44) / 2)
                    }
                    path(days, metric: .strain, scale: 21, left: left, width: width, height: plotH)
                        .stroke(Color.appAccent.opacity(0.7), lineWidth: 1.5)
                    path(days, metric: .recovery, scale: 100, left: left, width: width, height: plotH)
                        .stroke(Color.appMuted.opacity(0.6), lineWidth: 1.5)
                    ForEach(Array(days.enumerated()), id: \.element.key) { index, day in
                        let x = left + slot * (CGFloat(index) + 0.5)
                        if let value = day.value(.strain) {
                            let y = plotH * CGFloat(1 - value / 21)
                            Circle().fill(LinearGradient.appCard).frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.appAccent, lineWidth: 2)).position(x: x, y: y)
                            Text(DetailMetric.strain.text(value)).font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.appAccent).position(x: x, y: min(plotH - 3, y + 12))
                        }
                        if let value = day.recovery {
                            let y = plotH * CGFloat(1 - value / 100)
                            let color = DetailMetric.recovery.color(value)
                            Circle().fill(LinearGradient.appCard).frame(width: 7, height: 7)
                                .overlay(Circle().stroke(color, lineWidth: 2)).position(x: x, y: y)
                            Text(DetailMetric.recovery.text(value)).font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(color).position(x: x, y: max(6, y - 13))
                        }
                        VStack(spacing: 3) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            Text(day.date.formatted(.dateTime.day()))
                        }.font(.system(size: 9)).foregroundStyle(Color.appMuted).position(x: x, y: plotH + 24)
                    }
                }
            }.frame(height: 230)
            Hint("Blue: recorded strain (0–21). Colored markers: local Recovery (0–100%). Missing days remain gaps.")
        }
    }
    private func path(_ days: [MetricDay], metric: DetailMetric, scale: Double,
                      left: CGFloat, width: CGFloat, height: CGFloat) -> Path {
        Path { p in
            var previous = false
            for (index, day) in days.enumerated() {
                guard let value = day.value(metric) else { previous = false; continue }
                let point = CGPoint(x: left + width * (CGFloat(index) + 0.5) / CGFloat(max(1, days.count)),
                                    y: height * CGFloat(1 - min(1, max(0, value / scale))))
                if previous { p.addLine(to: point) } else { p.move(to: point) }
                previous = true
            }
        }
    }
}

struct RecordedStressChart: View {
    let points: [StressPoint]
    var body: some View {
        let sorted = points.filter { $0.index.isFinite }.sorted { $0.unix < $1.unix }
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let first = sorted.first?.unix ?? 0
                let span = Double(max(1, (sorted.last?.unix ?? first + 1) - first))
                ZStack {
                    Path { p in
                        for step in 0...3 {
                            let y = geometry.size.height * CGFloat(step) / 3
                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }.stroke(Color.appLine, lineWidth: 1)
                    Path { p in
                        var previous: Int?
                        for point in sorted {
                            let position = CGPoint(x: geometry.size.width * CGFloat(Double(point.unix - first) / span),
                                y: geometry.size.height * CGFloat(1 - min(3, max(0, point.index)) / 3))
                            if let previous, point.unix - previous <= 600 { p.addLine(to: position) }
                            else { p.move(to: position) }
                            previous = point.unix
                        }
                    }.stroke(LinearGradient(colors: [.appAccent, .appGood, .appWarn], startPoint: .bottom, endPoint: .top), lineWidth: 1.7)
                }
            }.frame(height: 150)
            HStack {
                Text(sorted.first.map { Date(timeIntervalSince1970: TimeInterval($0.unix)).formatted(date: .omitted, time: .shortened) } ?? "—")
                Spacer()
                Text(sorted.last.map { Date(timeIntervalSince1970: TimeInterval($0.unix)).formatted(date: .omitted, time: .shortened) } ?? "—")
            }.font(.system(size: 9)).foregroundStyle(Color.appMuted)
            if sorted.isEmpty { Hint("Recorded stress windows appear after the awake baseline and R-R coverage are available.") }
        }
    }
}

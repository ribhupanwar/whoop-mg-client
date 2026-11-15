import SwiftUI

private let healthspanMint = Color(hex: 0x55DDA6)

struct HealthspanPoint: Identifiable {
    let date: Date
    let years: Double?
    var id: Date { date }
}

/// Aura's published body-age presentation is the visual reference. The
/// calculation is Strap's independent, explicitly labelled fitness-age model.
struct HealthspanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var points: [HealthspanPoint] = []
    @State private var window = 30
    @State private var snapshot: FitnessAgeSnapshot?
    private func makeSnapshot() -> FitnessAgeSnapshot? {
        guard !store.isPreview else {
            return FitnessAgeSnapshot(years: 25, chronologicalYears: 30, restingHeartRate: 54,
                physicalActivityIndex: 7.5, restingNights: 6, capturedDays: 7,
                exerciseDays: 4, confidenceNote: "Design preview sample")
        }
        return FitnessAgeModel.snapshot(age: store.settings.age, sex: store.settings.sex,
            ageConfirmed: store.settings.ageConfirmed, days: store.band.days,
            detected: store.detectedBandActivities, live: store.liveActivities)
    }
    private var refreshKey: String {
        let days = store.band.days.map { "\($0.dateKey):\($0.restingHR ?? -1):\($0.steps ?? -1)" }.joined(separator: "|")
        return "\(window):\(store.isPreview):\(store.settings.age):\(store.settings.sex):\(store.settings.ageConfirmed):\(store.liveActivities.count):\(store.detectedBandActivities.count):" + days
    }
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your fitness age").font(StrapTypography.body(26, weight: .bold))
                        Text("The bigger picture, over time.").font(StrapTypography.body(14)).foregroundStyle(Color.appMuted)
                    }
                    Spacer()
                    Image(systemName: "leaf.fill").font(.system(size: 26, weight: .light)).foregroundStyle(healthspanMint)
                }.padding(.top, 12)
                HealthspanOrb(years: snapshot?.years).frame(height: 190).padding(.vertical, 8)
                ageCard
                trendCard
                factors
                if snapshot == nil { readiness }
                DisclosureGroup("How this estimate works") {
                    Text("Strap compares measured resting heart rate and recent exercise using its independent Nes/HUNT-inspired fitness model. This is an exploratory fitness comparison; it does not measure biological age or lifespan.")
                    Text("The ±5-year display band is part of the presentation, not a validated confidence interval. Trend points are reconstructed from saved observations and your current confirmed profile; missing dates remain gaps.")
                }.font(StrapTypography.body(12)).foregroundStyle(Color.appMuted).tint(healthspanMint)
                    .padding(.vertical, 14)
            }.foregroundStyle(Color.appFG)
        }
        .navigationTitle("HEALTHSPAN").navigationBarTitleDisplayMode(.inline)
        .task(id: refreshKey) { rebuildTrend() }
    }
    private var ageCard: some View {
        Panel {
            CardHead(title: "Fitness age")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.map { String(format: "%.0f", $0.years) } ?? "—")
                    .font(StrapTypography.metric(48, weight: .light))
                Text("years").font(StrapTypography.body(13)).foregroundStyle(Color.appMuted)
            }
            if let snapshot {
                let gap = snapshot.years - Double(snapshot.chronologicalYears)
                Text(String(format: "%.1f years %@ than your age", abs(gap), gap <= 0 ? "younger" : "older"))
                    .font(StrapTypography.body(14, weight: .semibold)).foregroundStyle(gap <= 0 ? healthspanMint : Color.appWarn)
                    .padding(.bottom, 18)
                HealthspanAgeScale(years: snapshot.years, actualAge: snapshot.chronologicalYears)
                Text("±5-year display band").font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
                    .frame(maxWidth: .infinity).padding(.top, 6)
            } else {
                Text("Build your baseline to reveal your fitness-age comparison.")
                    .font(StrapTypography.body(13)).foregroundStyle(Color.appMuted).padding(.top, 8)
            }
        }
    }
    private var trendCard: some View {
        Panel {
            HStack {
                Text("YOUR AGE TREND").font(StrapTypography.body(11, weight: .bold)).tracking(0.8)
                Spacer()
                Picker("Trend period", selection: $window) {
                    Text("M").tag(30)
                    Text("3M").tag(90)
                }.pickerStyle(.segmented).frame(width: 108)
            }.padding(.bottom, 16)
            HStack(spacing: 14) {
                legend("Fitness age", color: healthspanMint)
                legend("Your age", color: .appMuted)
            }.padding(.bottom, 16)
            HealthspanTrendChart(points: points, actualAge: snapshot?.chronologicalYears
                ?? (store.settings.ageConfirmed ? store.settings.age : nil))
            if points.allSatisfy({ $0.years == nil }) {
                Text("Your trend appears as enough recorded nights and exercise accumulate.")
                    .font(StrapTypography.body(12)).foregroundStyle(Color.appMuted).padding(.top, 12)
            }
        }
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(title).font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
        }
    }
    private var factors: some View {
        Panel {
            CardHead(title: "What's moving it")
            factor("Resting heart rate", symbol: "heart", value: snapshot.map { String(format: "%.0f bpm", $0.restingHeartRate) } ?? "—",
                   detail: "Median of your recorded resting nights")
            Divider().overlay(Color.appLine).padding(.vertical, 14)
            factor("Recent exercise", symbol: "figure.run", value: snapshot.map { "\($0.exerciseDays) days" } ?? "—",
                   detail: "Recorded sessions in the last seven days")
            Divider().overlay(Color.appLine).padding(.vertical, 14)
            factor("Data coverage", symbol: "checkmark.shield", value: snapshot.map { "\($0.capturedDays)/7 days" } ?? "—",
                   detail: "Observed days with saved step counts")
        }
    }
    private func factor(_ title: String, symbol: String, value: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(healthspanMint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(StrapTypography.body(14, weight: .semibold))
                Text(detail).font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
            }
            Spacer()
            Text(value).font(StrapTypography.metric(17))
        }
    }
    private var readiness: some View {
        Panel {
            CardHead(title: "Build your baseline")
            Text("Confirm your age and sex, then record at least four resting-HR nights, four days of steps and one workout within seven days.")
                .font(StrapTypography.body(13)).foregroundStyle(Color.appMuted)
            NavigationLink(value: Route.settings) {
                Label("Review your profile", systemImage: "person.crop.circle")
                    .font(StrapTypography.body(13, weight: .bold)).foregroundStyle(healthspanMint).padding(.top, 14)
            }.buttonStyle(.plain)
        }
    }
    private func rebuildTrend() {
        snapshot = makeSnapshot()
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        points = (0..<window).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - window + 1, to: end) else { return nil }
            if store.isPreview {
                let missing = index % 13 == 5
                return HealthspanPoint(date: date, years: missing ? nil : 27 - Double(index) / Double(window) * 2 + sin(Double(index) * 0.35) * 0.35)
            }
            let result = FitnessAgeModel.snapshot(age: store.settings.age, sex: store.settings.sex,
                ageConfirmed: store.settings.ageConfirmed, days: store.band.days,
                detected: store.detectedBandActivities, live: store.liveActivities, asOf: date)
            return HealthspanPoint(date: date, years: result?.years)
        }
    }
}

struct HealthspanOrb: View {
    let years: Double?
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [healthspanMint.opacity(0.02), healthspanMint.opacity(0.32), .clear],
                                         center: .center, startRadius: 30, endRadius: 90))
            Circle().stroke(healthspanMint.opacity(0.25), lineWidth: 9).blur(radius: 7).padding(22)
            Circle().stroke(LinearGradient(colors: [healthspanMint.opacity(0.05), healthspanMint.opacity(0.65), healthspanMint.opacity(0.1)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3).blur(radius: 2).padding(24)
            Canvas { context, size in
                for index in 0..<32 {
                    let angle = Double(index) * 2.39996
                    let radius = size.width * (0.22 + Double(index % 9) * 0.015)
                    let x = size.width / 2 + cos(angle) * radius
                    let y = size.height / 2 + sin(angle) * radius
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                 with: .color(healthspanMint.opacity(0.2 + Double(index % 4) * 0.12)))
                }
            }
            Text(years.map { String(format: "%.0f", $0) } ?? "—")
                .font(StrapTypography.metric(42, weight: .light)).foregroundStyle(Color.appFG)
        }.frame(width: 180, height: 180).frame(maxWidth: .infinity)
        .accessibilityLabel(years.map { String(format: "Fitness age %.0f years", $0) } ?? "Fitness age needs more data")
    }
}

private struct HealthspanAgeScale: View {
    let years: Double
    let actualAge: Int
    private var low: Double { min(years - 7, Double(actualAge) - 2) }
    private var high: Double { max(years + 7, Double(actualAge) + 2) }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let span = max(1, high - low)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appRaised).frame(height: 3)
                Capsule().fill(healthspanMint.opacity(0.4)).frame(width: width * CGFloat(10 / span), height: 5)
                    .offset(x: width * CGFloat((years - 5 - low) / span))
                Circle().fill(healthspanMint.opacity(0.4)).frame(width: 22, height: 22).blur(radius: 5)
                    .offset(x: width * CGFloat((years - low) / span) - 11)
                Circle().fill(Color.appFG).frame(width: 9, height: 9)
                    .offset(x: width * CGFloat((years - low) / span) - 4.5)
                Rectangle().fill(Color.appMuted).frame(width: 1.5, height: 12)
                    .offset(x: width * CGFloat((Double(actualAge) - low) / span))
            }.frame(height: 30)
            Text("You are \(actualAge)").font(StrapTypography.body(9)).foregroundStyle(Color.appMuted)
                .position(x: min(width - 30, max(30, width * CGFloat((Double(actualAge) - low) / span))), y: -4)
        }.frame(height: 34)
    }
}

private struct HealthspanTrendChart: View {
    let points: [HealthspanPoint]
    let actualAge: Int?
    private var low: Double { max(15, (points.compactMap(\.years).min() ?? Double(actualAge ?? 30)) - 6) }
    private var high: Double { max(Double(actualAge ?? 0) + 2, (points.compactMap(\.years).max() ?? low + 10) + 6) }
    var body: some View {
        GeometryReader { geometry in
            let left: CGFloat = 26
            let width = max(1, geometry.size.width - left - 10)
            let height: CGFloat = 160
            ZStack(alignment: .topLeading) {
                ForEach(0...3, id: \.self) { tick in
                    let y = height * CGFloat(tick) / 3
                    Path { p in p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: left + width, y: y)) }
                        .stroke(Color.appLine, lineWidth: 0.7)
                    Text(String(format: "%.0f", high - Double(tick) / 3 * (high - low)))
                        .font(StrapTypography.metric(9, weight: .regular)).foregroundStyle(Color.appMuted).position(x: 9, y: y)
                }
                if let actualAge {
                    let y = ordinate(Double(actualAge), height: height)
                    Path { p in p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: left + width, y: y)) }
                        .stroke(Color.appMuted.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let latest = points.last?.years {
                    let y = ordinate(latest + 5, height: height)
                    Rectangle().fill(healthspanMint.opacity(0.05))
                        .frame(width: width, height: height * CGFloat(10 / max(1, high - low))).offset(x: left, y: y)
                }
                trendPath(left: left, width: width, height: height)
                    .stroke(healthspanMint.opacity(0.15), style: StrokeStyle(lineWidth: 7, lineCap: .round)).blur(radius: 3)
                trendPath(left: left, width: width, height: height)
                    .stroke(healthspanMint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(points.indices, id: \.self) { index in
                    if let value = points[index].years,
                       index == points.count - 1 || (index == 0 || points[index - 1].years == nil) {
                        Circle().fill(Color.appSurface).frame(width: 6, height: 6)
                            .overlay(Circle().stroke(healthspanMint, lineWidth: 1.5))
                            .position(x: left + width * CGFloat(index) / CGFloat(max(1, points.count - 1)), y: ordinate(value, height: height))
                    }
                }
                if let first = points.first, let last = points.last {
                    Text(first.date.formatted(.dateTime.month(.abbreviated).day()))
                        .position(x: left + 16, y: height + 18)
                    Text(last.date.formatted(.dateTime.month(.abbreviated).day()))
                        .position(x: left + width - 16, y: height + 18)
                }
            }.font(StrapTypography.body(9)).foregroundStyle(Color.appMuted)
        }.frame(height: 185)
        .accessibilityLabel("Fitness-age trend with gaps for dates without enough measured data")
    }
    private func ordinate(_ value: Double, height: CGFloat) -> CGFloat {
        height * CGFloat(1 - min(1, max(0, (value - low) / max(1, high - low))))
    }
    private func trendPath(left: CGFloat, width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            var connected = false
            for (index, point) in points.enumerated() {
                guard let years = point.years else { connected = false; continue }
                let position = CGPoint(x: left + width * CGFloat(index) / CGFloat(max(1, points.count - 1)), y: ordinate(years, height: height))
                if connected { path.addLine(to: position) } else { path.move(to: position) }
                connected = true
            }
        }
    }
}

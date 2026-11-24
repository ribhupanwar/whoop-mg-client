import SwiftUI
import UIKit

// Use the same cool cyan accent as the Healthspan orb and Health Monitor.
private let healthspanMint = Color(hex: 0x54D7E9)

struct HealthspanPoint: Identifiable, Sendable {
    let date: Date
    let years: Double?
    var comparisonAge: Double? = nil
    var id: Date { date }
}

/// Aura's published body-age presentation is the visual reference. The
/// calculation is Strap's independent, explicitly labelled fitness-age model.
struct HealthspanView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var points: [HealthspanPoint] = []
    @State private var window = 30
    @State private var weekOffset = 0
    @State private var insights: HealthspanInsights?
    @State private var showsMethod = false
    private var selectedEnd: Date {
        Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: day) ?? day
    }
    private var selectedStart: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: selectedEnd) ?? selectedEnd
    }
    @State private var snapshot: FitnessAgeSnapshot?
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var baselineCoverage = (restingNights: 0, stepDays: 0)
    private func makeSnapshot() -> FitnessAgeSnapshot? {
        guard !store.isPreview else {
            return FitnessAgeSnapshot(years: 25, chronologicalYears: 30, restingHeartRate: 54,
                physicalActivityIndex: 7.5, restingNights: 6, capturedDays: 7,
                exerciseDays: 4, confidenceNote: "Design preview sample")
        }
        return weekOffset == 0 ? store.fitnessSnapshot : nil
    }
    private struct Inputs: Equatable {
        let date: Date
        let count: Int
        let days: [DayMetrics]
        let detected: [ActivitySession]
        let live: [LiveActivityRecord]
        let manual: [ManualActivity]
        let settings: AppSettings
        let currentSnapshot: FitnessAgeSnapshot?
    }

    private var inputs: Inputs {
        Inputs(date: selectedEnd, count: window, days: store.band.days, detected: store.detectedBandActivities,
               live: store.liveActivities, manual: store.manualActivities, settings: store.settings,
               currentSnapshot: store.fitnessSnapshot)
    }
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                weekPicker
                HealthspanOrb(years: snapshot?.years, chronologicalYears: snapshot?.comparisonAge)
                    .frame(height: 300)
                    .padding(.vertical, 10)
                ageCard
                readiness
                paceCard
                if let insights {
                    contributionSection("Sleep", readings: insights.sleep)
                    contributionSection("Activity", readings: insights.activity)
                    contributionSection("Fitness", readings: insights.fitness)
                }
                trendCard
                milestones
                improvementPlan
            }
            .padding(.bottom, 72)
            .foregroundStyle(Color.appFG)
        }
        .navigationTitle("HEALTHSPAN").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsMethod = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About Healthspan")
            }
        }
        .alert("About Healthspan", isPresented: $showsMethod) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Fitness Age compares measured resting heart rate and recent exercise using STRAP’s HUNT-inspired model. Historical values are reconstructed from saved observations and the current confirmed profile. The display band is illustrative.")
        }
        .task(id: inputs) { await rebuildTrend(inputs) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            day = Calendar.current.startOfDay(for: Date())
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { day = Calendar.current.startOfDay(for: Date()) }
        }
    }

    private var weekPicker: some View {
        VStack(spacing: 6) {
            HStack {
                Button { weekOffset -= 1 } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous week")
                .disabled(weekOffset <= -51)
                Spacer()
                Text(selectedStart.formatted(.dateTime.month(.abbreviated).day()) + " – "
                     + selectedEnd.formatted(.dateTime.month(.abbreviated).day()))
                    .font(StrapTypography.body(17, weight: .bold))
                Spacer()
                Button { weekOffset += 1 } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next week")
                .disabled(weekOffset == 0)
            }
            .buttonStyle(.plain)
            if weekOffset == 0, let next = Calendar.current.date(byAdding: .day, value: 1, to: day) {
                HStack(spacing: 4) {
                    Text("Next window in")
                    Text(next, style: .relative)
                }
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appMuted)
            }
        }
    }

    private var ageCard: some View {
        Panel {
            CardHead(title: "Fitness age")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.map { String(format: "%.1f", $0.years) } ?? "—")
                    .font(StrapTypography.metric(48, weight: .light))
                Text("years").font(StrapTypography.body(13)).foregroundStyle(Color.appMuted)
            }
            if let snapshot {
                let gap = snapshot.years - snapshot.comparisonAge
                Text(String(format: "%.1f years %@ than your age", abs(gap), gap <= 0 ? "younger" : "older"))
                    .font(StrapTypography.body(14, weight: .semibold)).foregroundStyle(gap <= 0 ? healthspanMint : Color.appWarn)
                    .padding(.bottom, 18)
                HealthspanAgeScale(years: snapshot.years, actualAge: snapshot.comparisonAge)
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
            HealthspanTrendChart(points: points, actualAge: snapshot?.comparisonAge
                ?? (store.settings.ageConfirmed ? Double(store.settings.age) : nil))
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
    private var paceCard: some View {
        Panel {
            CardHead(title: "Pace of Aging", trailing: "Pending validation")
            Hint(HealthspanInsights.paceExplanation)
        }
    }

    private func contributionSection(_ title: String, readings: [HealthspanInsights.Reading]) -> some View {
        Panel {
            CardHead(title: title, trailing: "7-day window")
            ForEach(readings) { reading in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(reading.source)
                        if reading.id != "Lean body mass" {
                            Text("Coverage · \(reading.observed) of 7 days")
                        }
                        Text("Previous 7 days · \(display(reading.prior, unit: reading.unit))")
                        if let range = reading.observedReference {
                            Text("Observed range · \(display(range.lowerBound, unit: reading.unit)) to \(display(range.upperBound, unit: reading.unit))")
                        }
                    }
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                    .padding(.vertical, 6)
                } label: {
                    HStack {
                        Text(reading.id)
                        Spacer()
                        Text(display(reading.value, unit: reading.unit))
                            .font(StrapTypography.metric(17, weight: .medium))
                    }
                }
                .padding(.vertical, 7)
                if let value = reading.value, let range = reading.observedReference,
                   range.upperBound > range.lowerBound {
                    HealthspanMetricScale(value: value, previous: reading.prior,
                        lower: range.lowerBound, upper: range.upperBound, unit: reading.unit)
                        .padding(.bottom, 12)
                } else {
                    Text("Chart unavailable · insufficient measured reference range")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private func display(_ value: Double?, unit: String) -> String {
        guard let value else { return "Unavailable" }
        let precision = unit == "h" || unit == "ml/kg/min" ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(precision)))
        return unit == "%" ? number + unit : number + " " + unit
    }

    private var milestones: some View {
        Panel {
            CardHead(title: "Milestones")
            if store.isPreview {
                Hint("Recorded milestones appear in live mode.")
            } else if let snapshot {
                Label("Fitness Age estimate available", systemImage: "checkmark.circle")
                if snapshot.capturedDays == 7 {
                    Label("7 days with recorded steps", systemImage: "checkmark.circle")
                }
            } else {
                Hint("Your first estimate appears once this period has enough recorded data.")
            }
        }
    }

    private var improvementPlan: some View {
        Panel {
            CardHead(title: "Where to focus")
            if let impact = snapshot?.impact {
                if impact.activity > 0 {
                    Hint("Recent recorded exercise is below the model’s activity reference. Review missing exercise logs and plan activity that fits your current ability.")
                } else if impact.restingHeartRate > 0 {
                    Hint("Resting heart rate is above the model’s comparison reference. Review the trend across nights before interpreting a change.")
                } else {
                    Hint("Both model inputs are at or below their reference age contribution.")
                }
            } else {
                Hint("The estimate needs more measured data before STRAP can identify model inputs to review.")
            }
        }
    }

    private var readiness: some View {
        Panel {
            CardHead(title: "Fitness Age coverage", trailing: snapshot == nil ? "Collecting data" : "Estimate available")
            Text("Rolling seven-day window")
                .font(StrapTypography.body(13, weight: .semibold))
            baselineRow("Resting heart rate nights", observed: baselineCoverage.restingNights,
                        required: FitnessAgeModel.minRestingNights)
            baselineRow("Days with steps", observed: baselineCoverage.stepDays,
                        required: FitnessAgeModel.minCapturedDays)
            if let estimate = snapshot, let impact = estimate.impact {
                Text(String(format: "Measured median %.1f bpm · Activity index %.2f",
                            estimate.restingHeartRate, estimate.physicalActivityIndex))
                Text("Model reference · 65 bpm and activity index 5")
                Text(String(format: "RHR %+.1f years · Exercise %+.1f years", impact.restingHeartRate, impact.activity))
                if abs(impact.boundaryAdjustment) > 0.01 {
                    Text(String(format: "Model bounds %+.1f years", impact.boundaryAdjustment))
                }
            }
            Text("The estimate requires a confirmed age and sex and a workout of at least 10 minutes with recorded heart rate.")
                .font(StrapTypography.body(13)).foregroundStyle(Color.appMuted)
            NavigationLink(value: Route.settings) {
                Label("Review your profile", systemImage: "person.crop.circle")
                    .font(StrapTypography.body(13, weight: .bold)).foregroundStyle(healthspanMint).padding(.top, 14)
            }.buttonStyle(.plain)
        }
    }
    private func baselineRow(_ title: String, observed: Int, required: Int) -> some View {
        ProgressView(value: Double(min(observed, required)), total: Double(required)) {
            Text(title)
        } currentValueLabel: {
            Text("\(observed) recorded · \(required) needed")
        }
        .font(StrapTypography.body(12))
        .tint(healthspanMint)
        .padding(.vertical, 4)
    }

    @MainActor private func rebuildTrend(_ input: Inputs) async {
        snapshot = makeSnapshot()
        insights = nil
        let calendar = Calendar.current
        let now = Date()
        baselineCoverage = FitnessAgeModel.baselineCoverage(days: input.days, asOf: input.date)
        let result = await Task.detached(priority: .utility) {
            let series = (0..<input.count).compactMap { index -> HealthspanPoint? in
                guard let date = calendar.date(byAdding: .day, value: index - input.count + 1, to: input.date) else { return nil }
                let value = FitnessAgeModel.snapshot(age: input.settings.age, sex: input.settings.sex,
                    ageConfirmed: input.settings.ageConfirmed, days: input.days, detected: input.detected,
                    live: input.live, asOf: date, birthDate: input.settings.birthDate)
                return HealthspanPoint(date: date, years: value?.years,
                    comparisonAge: input.settings.birthDate?.age(on: date))
            }
            let days = MetricTimeline.make(days: input.days, live: input.live, manual: input.manual,
                caloriesByDay: [:], ending: input.date, count: 14, sleepNeedHours: input.settings.sleepNeedHours,
                maxHR: input.settings.profileMaxHeartRate(on: input.date),
                calendar: calendar)
            let latest = FitnessAgeModel.snapshot(age: input.settings.age, sex: input.settings.sex,
                ageConfirmed: input.settings.ageConfirmed, days: input.days, detected: input.detected,
                live: input.live, asOf: input.date, birthDate: input.settings.birthDate)
            let leanMass = HealthspanInsights.recentLeanMass(input.settings.leanMass,
                                                              endingOn: input.date, now: now, calendar: calendar)
            return (series, HealthspanInsights(days: days, leanMass: leanMass), latest)
        }.value
        guard !Task.isCancelled else { return }
        points = input.settings.designPreview ? [] : result.0
        insights = input.settings.designPreview ? nil : result.1
        if weekOffset != 0, !input.settings.designPreview { snapshot = result.2 }
    }

}

struct HealthspanOrb: View {
    let years: Double?
    var chronologicalYears: Double? = nil

    private var ageGapText: String {
        guard let years, let chronologicalYears else { return "Building your baseline" }
        let gap = years - Double(chronologicalYears)
        return String(format: "%.1f years %@", abs(gap), gap <= 0 ? "younger" : "older")
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            ZStack {
                // The particle canvas owns both the animated membrane and its
                // clipping path. A second animated clip created conflicting
                // silhouettes and hid the changing edge.
                HealthspanParticleField()
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(years.map { String(format: "%.1f", $0) } ?? "—")
                        .font(StrapTypography.metric(47, weight: .bold))
                        .foregroundStyle(.white)
                    Text("FITNESS AGE")
                        .font(StrapTypography.body(12, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(.white)
                    Text(ageGapText)
                        .font(StrapTypography.body(14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x9DE5F0))
                        .padding(.top, 7)
                }
                .multilineTextAlignment(.center)
            }
            .frame(width: diameter, height: diameter)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityLabel(years.map { String(format: "Fitness age %.1f years. %@", $0, ageGapText) }
                            ?? "Fitness age needs more data")
    }
}

private struct HealthspanAgeScale: View {
    let years: Double
    let actualAge: Double
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
            Text("You are \(actualAge.formatted(.number.precision(.fractionLength(0...1))))").font(StrapTypography.body(9)).foregroundStyle(Color.appMuted)
                .position(x: min(width - 30, max(30, width * CGFloat((Double(actualAge) - low) / span))), y: -4)
        }.frame(height: 34)
    }
}

private struct HealthspanTrendChart: View {
    let points: [HealthspanPoint]
    let actualAge: Double?
    @State private var selectedDate: Date?
    private var ages: [Double] {
        points.flatMap { [$0.years, $0.comparisonAge].compactMap { $0 } }
            + [actualAge].compactMap { $0 }
    }
    private var low: Double { max(0, (ages.min() ?? 30) - 6) }
    private var high: Double { (ages.max() ?? 34) + 6 }
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
                if actualAge != nil || points.contains(where: { $0.comparisonAge != nil }) {
                    Path { path in
                        var connected = false
                        for (index, point) in points.enumerated() {
                            guard let comparisonAge = point.comparisonAge ?? actualAge else {
                                connected = false
                                continue
                            }
                            let x = left + width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                            let y = ordinate(comparisonAge, height: height)
                            if connected { path.addLine(to: CGPoint(x: x, y: y)) }
                            else { path.move(to: CGPoint(x: x, y: y)) }
                            connected = true
                        }
                    }
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
                if let selected = points.first(where: { $0.date == selectedDate }) {
                    Text(selected.date.formatted(.dateTime.month(.abbreviated).day()) + " · "
                         + (selected.years.map { String(format: "%.1f years", $0) } ?? "Unavailable"))
                        .padding(5)
                        .background(Color.appSurface, in: Capsule())
                        .position(x: geometry.size.width / 2, y: 9)
                }
            }
            .font(StrapTypography.body(9)).foregroundStyle(Color.appMuted)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard !points.isEmpty else { return }
                let fraction = max(0, min(1, (location.x - left) / width))
                let index = Int((fraction * CGFloat(points.count - 1)).rounded())
                selectedDate = points[index].date
            }
            .onChange(of: points.last?.date) { _, _ in selectedDate = nil }
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

// Measured-value visualization only: colors do not imply proprietary age impact.
private struct HealthspanMetricScale: View {
    let value: Double
    let previous: Double?
    let lower: Double
    let upper: Double
    let unit: String

    private func fraction(_ number: Double) -> CGFloat {
        CGFloat(min(1, max(0, (number - lower) / (upper - lower))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { index in
                            Rectangle()
                                .fill(Color(red: 0.22 + 0.045 * Double(index),
                                            green: 0.48 + 0.038 * Double(index),
                                            blue: 0.54 + 0.015 * Double(index)))
                        }
                    }
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    if let previous {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.appMuted)
                            .rotationEffect(.degrees(180))
                            .offset(x: max(0, min(width - 10, width * fraction(previous) - 5)), y: -11)
                    }
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appFG)
                        .offset(x: max(0, min(width - 10, width * fraction(value) - 5)), y: 10)
                }
            }
            .frame(height: 25)
            HStack {
                Text(lower.formatted() + " " + unit)
                Spacer()
                Text(upper.formatted() + " " + unit)
            }
            .font(StrapTypography.body(10))
            .foregroundStyle(Color.appMuted)
            Text("Measured range · lower marker: current · upper marker: previous")
                .font(StrapTypography.body(10))
                .foregroundStyle(Color.appMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

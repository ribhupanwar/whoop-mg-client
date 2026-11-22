import Foundation

struct HealthspanInsights {
    struct Reading: Identifiable {
        let id: String
        let unit: String
        let value: Double?
        let prior: Double?
        let observed: Int
        let source: String
        var observedReference: ClosedRange<Double>? = nil
    }

    let sleep: [Reading]
    let activity: [Reading]
    let fitness: [Reading]

    /// Include the seven local calendar days ending today, not a rolling 144-hour
    /// interval anchored to the current clock time. Reject future measurements.
    static func recentLeanMass(_ measurement: ProfileBodyMeasurement?,
                               asOf: Date, calendar: Calendar = .current) -> ProfileBodyMeasurement? {
        guard let measurement, measurement.date <= asOf else { return nil }
        let today = calendar.startOfDay(for: asOf)
        guard let first = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
        let sampleDay = calendar.startOfDay(for: measurement.date)
        return (first...today).contains(sampleDay) ? measurement : nil
    }

    static let paceExplanation = "A validated rate needs independent long-term measurements and a calibrated trend model. Rolling fitness-age estimates overlap and cannot establish an aging rate."

    init(days: [MetricDay], leanMass: ProfileBodyMeasurement? = nil) {
        let current = Array(days.suffix(7))
        let prior = Array(days.dropLast(min(7, days.count)).suffix(7))
        func reading(_ name: String, _ unit: String, _ source: String, sum: Bool = false,
                     value: (MetricDay) -> Double?) -> Reading {
            func aggregate(_ values: [Double]) -> Double? {
                guard !values.isEmpty else { return nil }
                return sum ? values.reduce(0, +) : Stats.mean(values)
            }
            let observed = current.compactMap(value)
            let previous = prior.compactMap(value)
            let reference = sum ? nil : previous.min().flatMap { low in previous.max().map { low...$0 } }
            return Reading(id: name, unit: unit, value: aggregate(observed),
                           prior: aggregate(previous), observed: observed.count, source: source,
                           observedReference: reference)
        }
        func consistency(_ days: [MetricDay]) -> (pct: Double?, nights: Int) {
            SleepReport.consistency(nights: days.compactMap { day in
                guard let recorded = day.recorded, recorded.reliableSleepHours != nil else { return nil }
                return recorded.night
            })
        }
        let regularity = consistency(current)
        sleep = [
            reading("Sleep performance", "%", "STRAP nightly scores") {
                $0.usesWHOOP(.sleepPerformance) ? nil : $0.value(.sleepPerformance)
            },
            Reading(id: "Sleep consistency", unit: "%", value: regularity.pct,
                    prior: consistency(prior).pct, observed: regularity.nights,
                    source: "Local bed and wake times within 60 minutes of the week's medians"),
            reading("Hours of sleep", "h", "Complete staged STRAP nights") { $0.recorded?.reliableSleepHours }
        ]
        activity = [
            reading("HR zones 1–3", "min", "Recorded awake HR and nonoverlapping live sessions", sum: true) { $0.value(.zonesLow) },
            reading("HR zones 4–5", "min", "Recorded awake HR and nonoverlapping live sessions", sum: true) { $0.value(.zonesHigh) },
            reading("Strength activity", "min", "Dated strength logs with known duration", sum: true) { $0.value(.strength) },
            reading("Daily steps", "steps", "Mean across available recorded days") { $0.value(.steps) }
        ]
        fitness = [
            reading("VO₂ max estimate", "ml/kg/min", "Uth heart-rate ratio from saved overnight RHR and current max-HR settings") { $0.value(.vo2) },
            reading("Resting heart rate", "bpm", "Mean of STRAP overnight measurements") {
                $0.recorded?.state == "sleep" && !$0.usesWHOOP(.rhr) ? $0.value(.rhr) : nil
            },
            Reading(id: "Lean body mass", unit: "kg", value: leanMass?.kilograms, prior: nil,
                    observed: leanMass == nil ? 0 : 1, source: leanMass.map {
                        "Apple Health · " + $0.source + " · " + $0.date.formatted(date: .abbreviated, time: .omitted)
                    } ?? "Needs a sourced lean-mass measurement")
        ]
    }
}

import Foundation

/// Display-only whole-minute allocation. Raw 30-second sleep epochs and all
/// Recovery/sleep computations remain unchanged. Independent rounding of four
/// stages can otherwise show one extra minute compared with the sleep window.
enum SleepStageDisplay {
    struct Minutes: Equatable {
        let stages: [SleepStage: Int]
        let unclassified: Int
        let window: Int
        var restorative: Int { (stages[.deep] ?? 0) + (stages[.rem] ?? 0) }
        func duration(_ minutes: Int) -> String {
            let sign = minutes < 0 ? "-" : ""
            let safe = abs(minutes)
            return "\(sign)\(safe / 60):" + String(format: "%02d", safe % 60)
        }
    }

    static func rounded(stageMinutes: [SleepStage: Double], windowMinutes: Double) -> Minutes {
        let order: [SleepStage] = [.wake, .light, .deep, .rem]
        let validWindow = windowMinutes.isFinite ? max(0, windowMinutes) : 0
        let target = Int(validWindow.rounded())
        let values = order.map { stage -> Double in
            let value = stageMinutes[stage] ?? 0
            return value.isFinite ? max(0, value) : 0
        }
        let unknown = max(0, validWindow - values.reduce(0, +))
        let fractions = values + [unknown]
        var allocation = fractions.map { Int(floor($0)) }
        var difference = target - allocation.reduce(0, +)
        // Assign each residual minute to the largest fractional 30-second
        // epoch. This keeps the displayed stage total equal to displayed
        // time in bed without changing measured/raw durations.
        let ranked = fractions.indices.sorted {
            let left = fractions[$0] - floor(fractions[$0])
            let right = fractions[$1] - floor(fractions[$1])
            return left == right ? $0 < $1 : left > right
        }
        for index in ranked where difference > 0 {
            allocation[index] += 1
            difference -= 1
        }
        // Invalid oversummed source rows are not silently normalized.
        // They remain visible in the report's underlying completeness checks.
        let stages = Dictionary(uniqueKeysWithValues: zip(order, allocation.prefix(4)))
        return Minutes(stages: stages, unclassified: allocation[4], window: target)
    }
}

import SwiftUI

/// Plan — week skeleton (not a generated programme) plus the sleep target.
struct PlanView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                outlookBox
                weekPanel
                sleepTargetPanel
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var outlookBox: some View {
        CTABox {
            Text(outlookTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(outlookBody)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var outlookTitle: String {
        if demo { return "Green — go hard if you planned it" }
        guard let score = store.band.recovery.score else {
            return "Today: train on feel, not on a score"
        }
        return "\(store.band.recovery.band.capitalized) · recovery \(Int(score.rounded()))"
    }

    private var outlookBody: String {
        if demo {
            return "Sample outlook: recovery above normal and sleep on target, so a threshold run or a heavy lift both fit today."
        }
        guard store.band.recovery.score != nil else {
            return "No recovery score exists yet. Until the baseline fills, keep easy runs conversational and let the gym session follow how you actually feel."
        }
        switch store.band.recovery.band {
        case "green":
            return "Local recovery estimate from HRV, resting HR and last night's sleep against your own baseline — a planned hard session fits today."
        case "yellow":
            return "Local recovery estimate sits mid-range. Keep the hard work short; the easy day is doing its job."
        default:
            return "Local recovery estimate is below your normal. Make today easy — adaptation happens in recovery, not in another hard session."
        }
    }

    private var weekPanel: some View {
        Panel {
            SectionTitle("This week")
            VStack(spacing: 8) {
                planRow(name: "Easy run · Z2", status: demo ? "42 min · done" : "planned")
                planRow(name: "Push day", status: demo ? "55 min · done" : "planned")
                planRow(name: "Threshold run · Z4", status: "tomorrow")
                planRow(name: "Pull day", status: "Wednesday")
                planRow(name: "Long run · Z2", status: "Saturday")
            }
            Hint("A plan skeleton, not a generated programme. Hard sessions stay separated by easy days — that spacing is what makes daily training survivable.")
        }
    }

    private func planRow(name: String, status: String) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appFG)
            Spacer()
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.appRaised))
    }

    private var sleepTargetPanel: some View {
        Panel {
            SectionTitle("Sleep target")
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CoachFormat.duration(store.settings.sleepNeedHours))
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("HOURS\nNEEDED")
                        .font(.system(size: 9.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.appMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(Color.appLine).frame(width: 26, height: 1)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(demo ? SampleData.planActualSleep : store.band.lastNightHours.map(CoachFormat.duration) ?? "—")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("LAST NIGHT\nACTUAL")
                        .font(.system(size: 9.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Hint("The need comes from Settings. Last night's actual is the detector's sleep time from your most recent capture; debt and tomorrow's intent live in Sleep coach.")
        }
    }
}
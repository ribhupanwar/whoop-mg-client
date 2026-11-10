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
            Text(demo ? "Green — go hard if you planned it" : "Today: train on feel, not on a score")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(demo
                 ? "Sample outlook: recovery above normal and sleep on target, so a threshold run or a heavy lift both fit today."
                 : "No recovery score exists yet. Until the baseline fills, keep easy runs conversational and let the gym session follow how you actually feel.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
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
                    Text(demo ? SampleData.planActualSleep : "—")
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
            Hint("Sleep need rises with training load. Once activity capture works, heavy days will push this target up automatically.")
        }
    }
}
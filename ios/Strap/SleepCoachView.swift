import SwiftUI

struct SleepCoachView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var alarmOn = WakeAlarm.isEnabled
    @State private var nextWake = WakeAlarm.nextWakeDate()
    @State private var showSchedule = false

    private var recommendation: SleepRecommendation {
        store.sleepPlan(nextWake: nextWake)
    }

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                planCard
                alarmCard
                DisclosureGroup("How the plan is calculated") {
                    Text("Sleep need is the estimated time asleep. Time in bed divides that need by your estimated sleep efficiency.")
                    Text("Sleep debt and efficiency each require at least three qualifying nights in the last 14 days. With no usable efficiency, the bedtime allows exactly the estimated sleep need.")
                    Text("Hard, Easy, and Rest describe your goal. Each adds zero minutes in this planning model.")
                }
                .font(StrapTypography.body(13))
                .foregroundStyle(Color.appMuted)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Sleep Planner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSchedule = true } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Edit weekly alarm schedule")
            }
        }
        .sheet(isPresented: $showSchedule, onDismiss: refreshAlarm) {
            NavigationStack {
                BandAlarmsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSchedule = false }
                        }
                    }
            }
        }
        .onAppear(perform: refreshAlarm)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshAlarm() }
        }
    }

    private var planCard: some View {
        let rec = recommendation
        return Panel {
            Image(systemName: "moon.stars")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Color.appSleep)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityHidden(true)
            Text("Aim for bed at \(CoachFormat.localClock(rec.bedtimeMinutes)). Your estimated sleep need is \(CoachFormat.duration(rec.needHours)).")
                .font(StrapTypography.body(19, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            Picker("Tomorrow’s goal", selection: $store.settings.sleepIntent) {
                ForEach(SleepIntent.allCases) { option in Text(option.label).tag(option) }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 14)
            Stepper(value: $store.settings.sleepNeedHours, in: 5...12, step: 0.25) {
                Text("Baseline sleep need · \(CoachFormat.duration(rec.baselineHours))")
            }
            LabeledContent("Sleep debt applied", value: rec.debtHours == nil
                ? "0:00 · insufficient history" : CoachFormat.duration(rec.appliedDebtHours))
            LabeledContent("Effort adjustment", value: CoachFormat.duration(rec.additionalHours))
            LabeledContent("Sleep efficiency", value: rec.measuredEfficiency.map {
                $0.formatted(.percent.precision(.fractionLength(0)))
            } ?? "Unavailable")
            .padding(.bottom, 12)
            HStack(alignment: .top) {
                timeLabel("Suggested bedtime", minutes: rec.bedtimeMinutes, identifier: "planner.bedtime")
                Spacer(minLength: 12)
                timeLabel(nextWake == nil && !store.isPreview ? "Target wake time" : "Scheduled wake time",
                          minutes: rec.wakeMinutes)
            }
            SectionTitle("Time in bed")
                .padding(.top, 12)
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [.appSleep.opacity(0.65), .appSleep.opacity(0.22)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                Text(CoachFormat.duration(rec.timeInBedHours))
                    .font(StrapTypography.metric(17, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.appBG, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.appSleep, lineWidth: 1))
            }
            .accessibilityLabel("Time in bed \(CoachFormat.duration(rec.timeInBedHours))")
        }
        .foregroundStyle(Color.appFG)
    }

    private func timeLabel(_ label: String, minutes: Int, identifier: String = "") -> some View {
        VStack(spacing: 3) {
            Text(CoachFormat.localClock(minutes))
                .accessibilityIdentifier(identifier)
                .font(StrapTypography.metric(28, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(StrapTypography.body(11, weight: .medium))
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var alarmCard: some View {
        Panel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle("Alarm")
                    Text(nextWake.map { $0.formatted(.dateTime.weekday(.wide)) } ?? "No alarm scheduled")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                }
                Spacer()
                Toggle("Wake alarm", isOn: Binding(
                    get: { alarmOn },
                    set: { enabled in
                        WakeAlarm.isEnabled = enabled
                        store.band.syncWakeAlarm(force: true)
                        refreshAlarm()
                    }
                ))
                .labelsHidden()
                .tint(Color.appGood)
            }
            Button { showSchedule = true } label: {
                HStack {
                    Label("Weekly schedule", systemImage: "calendar")
                    Spacer()
                    Text(nextWake.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                        .monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("alarm.wakeTime")
            Text(store.band.bandAlarmMessage)
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appMuted)
                .padding(.top, 8)
            Button { store.band.testBuzz() } label: {
                Label(store.band.testingBuzz ? "Sending…" : "Test band buzz", systemImage: "waveform")
            }
            .buttonStyle(.bordered)
            .disabled(store.isPreview || !store.band.canTestBuzz)
            .padding(.top, 4)
            if !store.band.buzzMessage.isEmpty {
                Text(store.band.buzzMessage).font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
            }
        }
        .foregroundStyle(Color.appFG)
    }

    private func refreshAlarm() {
        alarmOn = WakeAlarm.isEnabled
        nextWake = WakeAlarm.nextWakeDate()
    }
}

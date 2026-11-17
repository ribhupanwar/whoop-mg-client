import SwiftUI

/// Sleep Coach — computes the recommended bedtime LIVE in Swift:
///   need = base + extra(intent) + min(debt, 2.0)
///   timeInBed = need / 0.90 + 0.25
///   bedtime = wake − timeInBed
/// Debt is the Kitamura 2016 running shortfall over the last 14 recorded
/// nights, floored at 0. With no nights: "debt unknown — starts counting
/// tonight". This is our own published-science coach, not a proprietary one.
struct SleepCoachView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var phoneAlarm = WakeAlarmDelivery.shared

    @State private var wakeMinutes = 7 * 60
    @State private var intent: SleepIntent = .easy
    @State private var alarmOn = false
    @State private var alarmConfirmation = false
    @State private var seeded = false
    @State private var showWakePicker = false

    private var demo: Bool { store.isPreview }

    private var nights: [RecordedNight] {
        demo ? SampleData.nights : store.recordedNights
    }

    private var debt: Double? {
        SleepCoach.sleepDebt(nights: nights)
    }

    private var rec: SleepRecommendation {
        SleepCoach.recommendation(
            baseNeedHours: store.settings.sleepNeedHours,
            intent: intent,
            debtHours: debt,
            wakeMinutes: wakeMinutes
        )
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                coachPanel
                statsRow
                debtPanel
                alarmPanel
            }
        }
        .strapTabTypography("Sleep coach")
        .sheet(isPresented: $showWakePicker) {
            NavigationStack {
                DatePicker("Wake time", selection: wakeDateBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().padding()
                    .navigationTitle("Wake time")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showWakePicker = false }.font(StrapTypography.body(16, weight: .bold))
                    } }
            }.presentationDetents([.height(300)])
        }
        .onAppear {
            if !seeded { intent = store.settings.sleepIntent; seeded = true }
            if demo { wakeMinutes = SampleData.demoWakeMinutes }
            else if WakeAlarm.usesWeeklySchedule, let next = WakeAlarm.plannedWakeDate() {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: next)
                wakeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            } else { wakeMinutes = store.settings.wakeTimeMinutes }
            alarmOn = WakeAlarm.isEnabled
        }
        .onChange(of: wakeMinutes) { _, newValue in
            guard !WakeAlarm.usesWeeklySchedule else { return }
            if store.settings.wakeTimeMinutes != newValue {
                store.settings.wakeTimeMinutes = newValue
            }
            if alarmOn {
                WakeAlarm.setEnabled(true, wakeMinutes: newValue)
                store.band.syncWakeAlarm(force: true)
            }
        }
        .onChange(of: alarmOn) { _, newValue in
            WakeAlarm.setEnabled(newValue, wakeMinutes: wakeMinutes)
            store.band.syncWakeAlarm(force: true)
        }
        .onChange(of: intent) { _, newValue in
            if store.settings.sleepIntent != newValue {
                store.settings.sleepIntent = newValue
            }
        }
    }

    // MARK: Coach panel

    private var coachPanel: some View {
        Panel {
            Text(introSentence)
                .font(StrapTypography.body(12.5))
                .foregroundStyle(Color.appFG)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            SectionTitle("Tomorrow I want to")
            ChipPicker(options: SleepIntent.allCases, label: { $0.label }, selection: intentBinding)
                .padding(.bottom, 12)

            timesRow

            SectionTitle("Time in bed")
            SplitBar(segments: [
                SplitBar.Segment(fraction: rec.needHours / rec.timeInBedHours, color: .appSleep),
                SplitBar.Segment(fraction: 1.0 - rec.needHours / rec.timeInBedHours, color: .appRaised)
            ])
            .padding(.bottom, 4)

            Hint("Time in bed runs longer than sleep need: 15 min assumed latency and 90% assumed efficiency. This band cannot measure either, so both stay stated assumptions, not readings.")
        }
    }

    private var introSentence: String {
        var sentence = "Get to bed by \(CoachFormat.clock(rec.bedtimeMinutes)) to reach \(String(format: "%.1f", rec.needHours)) h of sleep by \(CoachFormat.clock(wakeMinutes))."
        if let debt {
            sentence += " Includes \(String(format: "%.1f", debt)) h of sleep debt\(demo ? " (sample)" : "")."
        } else {
            sentence += " Debt unknown until nights are recorded."
        }
        return sentence
    }

    private var timesRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(CoachFormat.clock(rec.bedtimeMinutes))
                    .font(StrapTypography.body(26, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Text("SUGGESTED\nBEDTIME")
                    .font(StrapTypography.body(9.5))
                    .tracking(0.7)
                    .foregroundStyle(Color.appMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Button { showWakePicker = true } label: {
                    Text(CoachFormat.clock(wakeMinutes))
                        .font(StrapTypography.metric(26, weight: .bold))
                        .foregroundStyle(Color.appFG)
                }.buttonStyle(.plain).accessibilityLabel("Change wake time").disabled(WakeAlarm.usesWeeklySchedule)
                Text("YOUR WAKE\nTIME")
                    .font(StrapTypography.body(9.5))
                    .tracking(0.7)
                    .foregroundStyle(Color.appMuted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.bottom, 12)
    }

    private var intentBinding: Binding<SleepIntent?> {
        Binding(
            get: { Optional(intent) },
            set: { if let value = $0 { intent = value } }
        )
    }

    private var wakeDateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(wakeMinutes * 60))
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                wakeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // MARK: Need / in-bed / debt cards

    private var statsRow: some View {
        HStack(spacing: 8) {
            StatCard(title: "Sleep need", value: CoachFormat.duration(rec.needHours))
            StatCard(title: "Time in bed", value: CoachFormat.duration(rec.timeInBedHours))
            StatCard(
                title: "Sleep debt",
                value: debt.map { String(format: "%.1f h", $0) } ?? "—",
                detail: debt == nil ? "starts counting tonight" : (demo ? "sample nights" : "last 14 nights")
            )
        }
        .padding(.bottom, 11)
    }

    private var debtPanel: some View {
        Panel {
            SectionTitle("Sleep debt")
            Text(debtSentence)
                .font(StrapTypography.body(15, weight: .medium))
                .foregroundStyle(Color.appFG)
                .padding(.bottom, 2)
            Hint("The running shortfall against your need over the last 14 nights; a longer night repays it. At most 2 h of debt joins one night's need, so a bad week cannot demand an impossible bedtime. Our own coach built on the Kitamura 2016 sleep-debt model — not a proprietary algorithm.")
        }
    }

    private var debtSentence: String {
        if let debt {
            return String(format: "%.1f h", debt) + (demo ? " · sample" : "")
        }
        return "debt unknown — starts counting tonight"
    }

    // MARK: Alarm (local phone notification)

    private var alarmPanel: some View {
        Panel {
            HStack {
                Text("ALARM")
                    .font(StrapTypography.body(11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Toggle("", isOn: $alarmOn)
                    .labelsHidden()
                    .tint(.appGood)
            }
            .padding(.bottom, 10)

            HStack(spacing: 9) {
                coachButton("ALARM SET TO \(alarmOn ? "ON" : "OFF")") {
                    alarmOn.toggle()
                }
                coachTile("WAKE TIME \(CoachFormat.clock(wakeMinutes))")
            }

            NavigationLink("Different wake time per weekday") { WeeklyWakeScheduleView() }
                .font(StrapTypography.body(12)).padding(.vertical, 8)
            if WakeAlarm.usesWeeklySchedule { Hint("Weekly schedule active. Edit each weekday in the schedule above.") }
            Button("OK") {
                WakeAlarm.setEnabled(alarmOn, wakeMinutes: wakeMinutes)
                store.band.syncWakeAlarm(force: true)
                alarmConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
            .font(StrapTypography.body(12, weight: .bold))
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .trailing)
            if alarmConfirmation {
                Text("Alarm preference saved for \(CoachFormat.clock(wakeMinutes)).")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appGood)
            }
            Text(phoneAlarm.status).font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
            Text(store.band.bandAlarmMessage)
                .font(StrapTypography.body(12)).foregroundStyle(Color.appMuted).padding(.top, 10)
            Button { store.band.testBuzz() } label: {
                Label(store.band.testingBuzz ? "Sending…" : "Test band buzz", systemImage: "waveform")
                    .font(StrapTypography.body(13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).tint(Color.appSleep)
                .disabled(demo || !store.band.canTestBuzz).padding(.top, 12)
            if !store.band.buzzMessage.isEmpty {
                Text(store.band.buzzMessage).font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
            }
            Hint("The next wake alarm is sent to your connected band. Use Test band buzz to check vibration on your wrist. Reconnect after waking to send the following day's alarm. The phone notification repeats daily; allow notifications when prompted.")
        }
    }

    private func coachButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            coachLabel(title)
        }
        .buttonStyle(.plain)
    }

    private func coachTile(_ title: String) -> some View {
        coachLabel(title)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }

    private func coachLabel(_ title: String) -> some View {
        Text(title)
            .font(StrapTypography.body(10.5, weight: .medium))
            .tracking(0.4)
            .foregroundStyle(Color.appFG)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
    }
}

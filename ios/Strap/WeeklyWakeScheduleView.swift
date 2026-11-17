import SwiftUI

struct WeeklyWakeScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var delivery = WakeAlarmDelivery.shared
    @State private var slots = WeeklyWakeSchedule.defaults(minutes: 7 * 60, enabled: false)
    @State private var useWeekly = false
    @State private var status = ""

    var body: some View {
        Form {
            Section {
                Toggle("Different wake time per weekday", isOn: $useWeekly)
                Text("Phone notifications repeat on enabled weekdays. The band receives only the next alarm; reconnect after waking to send the following occurrence.")
            }
            Section("Weekday times") {
                ForEach(slots.indices, id: \.self) { index in
                    HStack {
                        Toggle(Calendar.current.weekdaySymbols[slots[index].weekday - 1], isOn: $slots[index].enabled)
                        DatePicker("Time", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                            .labelsHidden().disabled(!slots[index].enabled)
                    }.disabled(!useWeekly)
                }
            }
            Section {
                Button("Save schedule") {
                    do {
                        try WeeklyWakeSchedule.save(slots, active: useWeekly)
                        if useWeekly { WakeAlarm.setEnabled(slots.contains(where: \.enabled), wakeMinutes: WakeAlarm.wakeMinutes) }
                        else { WakeAlarm.setEnabled(WakeAlarm.isEnabled, wakeMinutes: WakeAlarm.wakeMinutes) }
                        store.band.syncWakeAlarm(force: true)
                        status = "Schedule saved. Phone permission and band delivery are shown separately below."
                    } catch { status = error.localizedDescription }
                }
                Text(status)
                Text(delivery.status)
                Text(store.band.bandAlarmMessage)
            }
        }
        .navigationTitle("Weekly wake schedule")
        .onAppear {
            useWeekly = WakeAlarm.usesWeeklySchedule
            do { slots = try WeeklyWakeSchedule.load() ?? WeeklyWakeSchedule.defaults(minutes: WakeAlarm.wakeMinutes, enabled: WakeAlarm.isEnabled) }
            catch { status = "Saved schedule could not be read; original bytes preserved. " + error.localizedDescription }
        }
    }
    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(get: {
            // A stable clock-only reference day, not an invented alarm occurrence.
            Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15,
                hour: slots[index].minutes / 60, minute: slots[index].minutes % 60)) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            if let hour = parts.hour, let minute = parts.minute { slots[index].minutes = hour * 60 + minute }
        })
    }
}

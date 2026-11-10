import SwiftUI

/// Settings — everything persists to UserDefaults through AppStore.
/// The design-preview toggle defaults OFF: live mode shows em dashes only.
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                profilePanel
                overridesPanel
                sleepPanel
                previewPanel
                aboutPanel
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Profile

    private var profilePanel: some View {
        Panel {
            SectionTitle("Profile")
            fieldRow(label: "Age") {
                TextField("30", value: $store.settings.age, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appFG)
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
            }
            Picker("Sex", selection: $store.settings.sex) {
                ForEach(Sex.allCases) { sex in
                    Text(sex.label).tag(sex)
                }
            }
            .pickerStyle(.segmented)
            Hint("Age feeds the default max-HR estimate (208 − 0.7 × age). Sex is kept for future calorie estimates (Keytel 2005); nothing is computed from it yet.")
        }
    }

    // MARK: HR overrides

    private var overridesPanel: some View {
        Panel {
            SectionTitle("Heart-rate overrides")
            Toggle("Override resting HR", isOn: restingOverrideOn)
                .font(.system(size: 12))
                .tint(.appAccent)
            if store.settings.restingHROverride != nil {
                overrideField(value: restingOverrideValue)
            }
            Toggle("Override max HR", isOn: maxOverrideOn)
                .font(.system(size: 12))
                .tint(.appAccent)
            if store.settings.maxHROverride != nil {
                overrideField(value: maxOverrideValue)
            }
            Hint("Use values you have actually measured. Overrides feed the Train zone calculator; zone minutes stay unmeasured until captures exist.")
        }
    }

    private func overrideField(value: Binding<Double>) -> some View {
        HStack {
            Text("bpm")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            Spacer()
            TextField("72", value: value, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15))
                .foregroundStyle(Color.appFG)
                .frame(width: 84)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .padding(.bottom, 8)
    }

    private var restingOverrideOn: Binding<Bool> {
        Binding(
            get: { store.settings.restingHROverride != nil },
            set: { isOn in
                store.settings.restingHROverride = isOn ? (store.settings.restingHROverride ?? 72.0) : nil
            }
        )
    }

    private var restingOverrideValue: Binding<Double> {
        Binding(
            get: { store.settings.restingHROverride ?? 72.0 },
            set: { store.settings.restingHROverride = $0 }
        )
    }

    private var maxOverrideOn: Binding<Bool> {
        Binding(
            get: { store.settings.maxHROverride != nil },
            set: { isOn in
                store.settings.maxHROverride = isOn
                    ? (store.settings.maxHROverride ?? Karvonen.agePredictedMaxHR(age: store.settings.age))
                    : nil
            }
        )
    }

    private var maxOverrideValue: Binding<Double> {
        Binding(
            get: { store.settings.maxHROverride ?? Karvonen.agePredictedMaxHR(age: store.settings.age) },
            set: { store.settings.maxHROverride = $0 }
        )
    }

    // MARK: Sleep

    private var sleepPanel: some View {
        Panel {
            SectionTitle("Sleep")
            Stepper(value: $store.settings.sleepNeedHours, in: 5.0...12.0, step: 0.25) {
                Text("Sleep need · \(CoachFormat.duration(store.settings.sleepNeedHours)) h")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appFG)
            }
            .tint(.appAccent)
            HStack {
                Text("Wake time")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                Spacer()
                DatePicker("", selection: wakeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.top, 8)
            Hint("The sleep coach works bedtime back from this wake time, your need and recorded sleep debt.")
        }
    }

    private var wakeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: Date())
                    .addingTimeInterval(TimeInterval(store.settings.wakeTimeMinutes * 60))
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                store.settings.wakeTimeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // MARK: Design preview

    private var previewPanel: some View {
        Panel {
            Toggle("Design preview with sample data", isOn: $store.settings.designPreview)
                .font(.system(size: 12))
                .tint(.appAccent)
            Hint("OFF (default): every unmeasured metric shows — and waiting states explain what data is needed. ON: labelled sample values fill the layout behind a visible banner. Sample values are never measurements.")
        }
    }

    // MARK: About

    private var aboutPanel: some View {
        Panel {
            SectionTitle("About")
            Text("Works with WHOOP MG bands.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appFG)
                .padding(.bottom, 6)
            Text("Strap is an independent, clean-room client. It is not affiliated with or endorsed by WHOOP. All layouts and scores shown here are original designs.")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Text("UI preview build — Bluetooth capture is not wired yet. Your data stays on this phone.")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    private func fieldRow<Control: View>(label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))
        .padding(.bottom, 10)
    }
}
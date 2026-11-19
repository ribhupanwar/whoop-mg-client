import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

/// Settings — everything persists to UserDefaults through AppStore.
/// The design-preview toggle defaults OFF: live mode never invents a value.
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    /// Text state so a half-typed decimal ("70.") is not rewritten mid-entry.
    @AppStorage("strap.spo2ResearchEnabled") private var spo2ResearchEnabled = false
    @AppStorage("strap.spo2ResearchReport") private var spo2ResearchReport = "No research capture yet. Sync band history to collect candidates."
    @FocusState private var profileEditing: Bool
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var showWhoopImporter = false
    @State private var importingWhoop = false
    @State private var limitWhoopDates = false
    @State private var whoopFrom = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    @State private var whoopThrough = Date()
    @State private var whoopImportStatus = "No WHOOP file imported"
    @State private var showPairingSheet = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                profilePanel
                strapPanel
                overridesPanel
                sleepPanel
                healthPanel
                spo2ResearchPanel
                whoopImportPanel
                previewPanel
                aboutPanel
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPairingSheet) {
            PairDeviceView()
                .environmentObject(store)
        }
        .fileImporter(isPresented: $showWhoopImporter, allowedContentTypes: [.zip, .commaSeparatedText, .plainText], onCompletion: importWhoopFile)
        .onAppear {
            weightText = store.settings.weightKG.map { String(format: "%g", $0) } ?? ""
            heightText = store.settings.heightCM.map { String(format: "%g", $0) } ?? ""
        }
    }

    private func importWhoopFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            let from = limitWhoopDates ? JournalStore.dayKey(for: whoopFrom) : nil
            let through = limitWhoopDates ? JournalStore.dayKey(for: whoopThrough) : nil
            importingWhoop = true
            whoopImportStatus = "Reading and validating all WHOOP files…"
            Task {
                defer { if scoped { url.stopAccessingSecurityScopedResource() }; importingWhoop = false }
                do {
                    let plan = try await Task.detached(priority: .userInitiated) {
                        try WhoopImportBatch.prepare(url, fromDate: from, throughDate: through)
                    }.value
                    try plan.commit()
                    let updated = store.band.importWhoopHistory(plan.biometricRows)
                    store.refreshWhoopImportedHistory()
                    whoopImportStatus = plan.summary(updatedDays: updated)
                } catch { whoopImportStatus = "Import failed; existing source records preserved: " + error.localizedDescription }
            }
        } catch { whoopImportStatus = "Import failed: " + error.localizedDescription }
    }

    // MARK: Profile

    private var profilePanel: some View {
        Panel {
            SectionTitle("Profile")
            fieldRow(label: "Age") {
                HStack(spacing: 6) {
                TextField("30", value: $store.settings.age, format: .number)
                    .keyboardType(.numberPad)
                    .focused($profileEditing)
                    .onChange(of: store.settings.age) { _, _ in
                        store.settings.ageConfirmed = true
                    }
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(StrapTypography.body(15))
                    .foregroundStyle(Color.appFG)
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                profileOK { store.settings.ageConfirmed = true }
                }
            }
            if !store.settings.ageConfirmed {
                Button("Confirm age for Fitness Age") {
                    store.settings.ageConfirmed = true
                }
                .font(StrapTypography.body(11, weight: .medium))
                .foregroundStyle(Color.appAccent)
                Hint("30 is only a placeholder until you confirm your actual age.")
            }
            Picker("Sex", selection: $store.settings.sex) {
                ForEach(Sex.allCases) { sex in
                    Text(sex.label).tag(sex)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                profileOK { }
            }
            fieldRow(label: "Weight · kg") {
                HStack(spacing: 6) {
                TextField("70", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($profileEditing)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(StrapTypography.body(15))
                    .foregroundStyle(Color.appFG)
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                    .onChange(of: weightText) { _, text in
                        store.settings.weightKG = Self.parsedNumber(text)
                    }
                profileOK { }
                }
            }
            fieldRow(label: "Height · cm") {
                HStack(spacing: 6) {
                TextField("175", text: $heightText)
                    .keyboardType(.decimalPad)
                    .focused($profileEditing)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(StrapTypography.body(15))
                    .foregroundStyle(Color.appFG)
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                    .onChange(of: heightText) { _, text in
                        store.settings.heightCM = Self.parsedNumber(text)
                    }
                profileOK { }
                }
            }
            Hint("Age feeds the default max-HR estimate (208 − 0.7 × age). Sex selects the Banister TRIMP coefficients, which drive strain, and the Keytel calorie coefficients. Weight and height only price the calorie estimate — leave them blank and the app shows an em dash rather than a number built on a guess.")
        }
    }

    private func profileOK(_ save: @escaping () -> Void) -> some View {
        Button("OK") {
            save()
            profileEditing = false
        }
        .font(StrapTypography.body(11, weight: .bold))
        .foregroundStyle(Color.appAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.appRaised))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Confirm profile value")
    }

    /// Blank means "not measured": the fields show placeholders but the stored
    /// value stays nil, so no calorie figure is built on a stand-in body.
    /// Text-backed so an empty field stores nil, never 0 — a zero weight would
    /// price every energy figure as nothing.
    static func parsedNumber(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    // MARK: Strap

    private var strapPanel: some View {
        Panel {
            HStack {
                SectionTitle("Strap")
                Spacer()
                NavigationLink { DeviceSettingsView() } label: {
                    HStack(spacing: 4) {
                        Text("Device Settings")
                        Image(systemName: "chevron.right")
                    }
                    .font(StrapTypography.body(11, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.band.bandName ?? store.band.preferredBandName ?? "WHOOP MG")
                        .font(StrapTypography.body(13, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text(store.band.status.title)
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                }
                Spacer()
                Button(store.band.isConnected ? "Disconnect" : "Connect") {
                    if store.band.isConnected {
                        store.band.disconnect()
                    } else {
                        store.connectBand()
                    }
                }
                .font(StrapTypography.body(12, weight: .bold))
                .foregroundStyle(Color.appAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))

            HStack(spacing: 12) {
                Button("Pair a Device") {
                    showPairingSheet = true
                }
                .font(StrapTypography.body(12, weight: .bold))
                .foregroundStyle(Color.appAccent)

                Spacer()

                if store.band.preferredBandID != nil {
                    Button("Unpair Device") { store.unpairBand() }
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appHigh)
                }
            }
            .padding(.top, 8)

            if !store.band.discoveredBands.isEmpty {
                VStack(spacing: 0) {
                    ForEach(store.band.discoveredBands) { band in
                        Button {
                            store.band.connect(to: band)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(band.name)
                                        .font(StrapTypography.body(12, weight: .medium))
                                        .foregroundStyle(Color.appFG)
                                    Text("signal \(band.rssi) dBm")
                                        .font(StrapTypography.body(10))
                                        .foregroundStyle(Color.appMuted)
                                }
                                Spacer()
                                if band.id == store.band.preferredBandID {
                                    Text("saved")
                                        .font(StrapTypography.body(10, weight: .medium))
                                        .foregroundStyle(Color.appGood)
                                }
                                Text("Connect")
                                    .font(StrapTypography.body(11, weight: .bold))
                                    .foregroundStyle(Color.appAccent)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.appLine).frame(height: 1)
                        }
                    }
                }
                .padding(.top, 6)
                Hint("Strongest signal first — the strap on your wrist is usually the top row. Names match because both bands are the same model.")
            }

            // Read-only hardware identity: never substitute a fabricated serial number.
            if let identifier = store.band.preferredBandID {
                Text("DEVICE ID  \\(identifier)")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            } else {
                Hint("Device ID unavailable until a band is selected.")
            }
            if let lastSync = store.band.lastHistorySyncAt {
                Text("LAST SYNC  \\(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 4)
            }
            if let firmware = store.band.firmwareRevision {
                Text("Firmware \(firmware)")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 8)
                if firmware.hasPrefix("50.43.") {
                    Hint("Community reports: some WHOOP 5/MG firmware 50.43 builds connect over Bluetooth but restrict history or live data. A successful connection does not guarantee data access.")
                }
            } else {
                Hint("Firmware revision unavailable until the band exposes its Device Information characteristic.")
            }
            if let battery = store.band.batteryPercent {
                Text("Battery \(battery)%")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 8)
            }
            if store.band.lastHistoryRecordCount > 0 {
                Text("Last history transfer: \(store.band.lastHistoryRecordCount) record frames")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 6)
            }
            if let lastSync = store.band.lastHistorySyncAt {
                Text("Last complete history sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
            }
            if let message = store.band.lastMessage {
                Hint(message)
            }
            Button {
                if store.band.isConnected {
                    store.band.readHistory()
                } else {
                    store.connectBand()
                }
            } label: {
                Label(store.band.isConnected ? "Sync band now" : "Connect & sync band",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(StrapTypography.body(13, weight: .bold))
                    .foregroundStyle(Color.appAccent)
            }
            .padding(.top, 10)
            Hint("Reads stored history when connected; otherwise starts Bluetooth connection.")

            if let summary = store.band.summary {
                let stats = store.band.drainStats
                Text("Last capture \(summary.sampleCount) samples · \(stats.acks) offload ACKs · \(store.band.days.count) day(s) scored")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 8)
                Button("Read stored history again") { store.band.readHistory() }
                    .font(StrapTypography.body(11, weight: .medium))
                    .foregroundStyle(Color.appAccent)
                    .padding(.top, 6)
            }
            Hint("Two straps in range? Tap Find another band and pick the one on your wrist; the choice is saved by its Bluetooth identifier, so later connects go straight to it. The iPhone's own pairing to the strap must stay off — BLE allows one central, and a stale pairing blocks the app. The first write triggers a pairing prompt; accept it. History lands as a JSONL capture plus per-day metrics.")
        }
    }

    // MARK: HR overrides

    private var overridesPanel: some View {
        Panel {
            SectionTitle("Heart-rate overrides")
            Toggle("Override resting HR", isOn: restingOverrideOn)
                .font(StrapTypography.body(12))
                .tint(.appAccent)
            if store.settings.restingHROverride != nil {
                overrideField(value: restingOverrideValue)
            }
            Toggle("Override max HR", isOn: maxOverrideOn)
                .font(StrapTypography.body(12))
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
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appMuted)
            Spacer()
            TextField("72", value: value, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(StrapTypography.body(15))
                .foregroundStyle(Color.appFG)
                .frame(width: 84)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
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
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appFG)
            }
            .tint(.appAccent)
            HStack {
                Text("Wake time")
                    .font(StrapTypography.body(12))
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

    // MARK: Apple Health

    private var healthPanel: some View {
        Panel {
            SectionTitle("Apple Health")
            Button {
                store.setHealthKit(true)
            } label: {
                Label("Connect Apple Health", systemImage: "heart.text.square")
                    .font(StrapTypography.body(14, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
            .disabled(store.health.state == .ready)
            .accessibilityHint("Request permission to export measured workouts to Apple Health")
            Toggle("Export measured sessions", isOn: Binding(
                get: { store.settings.healthKitEnabled },
                set: { store.setHealthKit($0) }
            ))
            .font(StrapTypography.body(12))
            .tint(.appAccent)
            Text(store.healthKitStatus)
                .font(StrapTypography.body(11))
                .foregroundStyle(healthStatusColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Hint("Writes band-detected and live sessions as workouts with their real start, end and step count. No estimate — VO₂ max, SpO₂ candidate or calories — is ever written, and nothing is read back. HealthKit needs the capability in the signing profile; a free Apple ID may not grant it.")
        }
    }

    private var healthStatusColor: Color {
        switch store.health.state {
        case .ready: return .appGood
        case .denied, .failed: return .appWarn
        default: return .appMuted
        }
    }

    // MARK: Opt-in optical research (never a clinical reading)

    private var spo2ResearchPanel: some View {
        Panel {
            SectionTitle("SpO₂ Research")
            Toggle("Collect candidate diagnostics", isOn: $spo2ResearchEnabled)
                .font(StrapTypography.body(12))
                .tint(.appAccent)
            Text(spo2ResearchReport)
                .font(StrapTypography.body(11))
                .foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
            Hint("Experimental: summarizes uncalibrated v18 historical candidate bytes after the next band sync. It does not measure blood oxygen, infer desaturation, or affect Recovery. Disable to stop future research summaries.")
        }
    }

    // MARK: WHOOP historical import

    private var whoopImportPanel: some View {
        Panel {
            SectionTitle("Import WHOOP history")
            Toggle("Limit imported dates", isOn: $limitWhoopDates)
            if limitWhoopDates {
                DatePicker("From", selection: $whoopFrom, displayedComponents: .date)
                DatePicker("Through", selection: $whoopThrough, displayedComponents: .date)
            }
            Button("Import WHOOP data ZIP or CSV") {
                showWhoopImporter = true
            }
            .font(StrapTypography.body(12, weight: .bold))
            .foregroundStyle(Color.appAccent)
            .disabled(importingWhoop || (limitWhoopDates && whoopFrom > whoopThrough))
            Text(whoopImportStatus)
                .font(StrapTypography.body(11))
                .foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            NavigationLink("View imported WHOOP data") { ImportHistoryView() }
            Hint("Select the whole WHOOP ZIP once. All four source categories are retained together. New and already-saved counts are shown separately; repeated imports add no duplicates. Dated WHOOP Recovery, Strain and Sleep values appear in history charts. Existing band measurements and edited sleep take precedence.")
        }
    }

    // MARK: Design preview

    private var previewPanel: some View {
        Panel {
            Toggle("Design preview with sample data", isOn: $store.settings.designPreview)
                .font(StrapTypography.body(12))
                .tint(.appAccent)
            Hint("OFF (default): every unmeasured metric shows — and waiting states explain what data is needed. ON: labelled sample values fill the layout behind a visible banner. Sample values are never measurements.")
        }
    }

    // MARK: About

    private var aboutPanel: some View {
        Panel {
            SectionTitle("About")
            Text("Works with WHOOP MG bands.")
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appFG)
                .padding(.bottom, 6)
            Text("Strap is an independent, clean-room client. It is not affiliated with or endorsed by WHOOP. All layouts and scores shown here are original designs.")
                .font(StrapTypography.body(11))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Text("Reads stored history and live heart rate directly over Bluetooth. Nothing links back to WHOOP's services; your data stays on this phone unless you turn on the optional Apple Health export above.")
                .font(StrapTypography.body(11))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    private func fieldRow<Control: View>(label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appMuted)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        .padding(.bottom, 10)
    }
}
enum WhoopImportSafetyError: LocalizedError {
    case extractionLimit
    var errorDescription: String? { "WHOOP import exceeds the safe 50 MB per-file limit." }
}

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
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var showWhoopImporter = false
    @State private var whoopImportStatus = "No WHOOP file imported"

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
        .fileImporter(isPresented: $showWhoopImporter, allowedContentTypes: [.zip, .commaSeparatedText, .plainText]) { result in
            do {
                let url = try result.get()
                guard url.startAccessingSecurityScopedResource() else {
                    whoopImportStatus = "File permission denied — choose the CSV again."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                if url.pathExtension.lowercased() == "zip" {
                    let archive = try Archive(url: url, accessMode: .read)
                    var importedDays = 0
                    var supplementalCounts: [String] = []
                    var recognizedFiles: [String] = []
                    var failures: [String] = []
                    for entry in archive where entry.type == .file {
                        let name = (entry.path as NSString).lastPathComponent.lowercased()
                        guard name.hasSuffix(".csv") else { continue }
                        // ZIPFoundation extracts to memory: no archive paths are written.
                        if entry.uncompressedSize > 50_000_000 {
                            failures.append("\(name): exceeds 50 MB limit")
                            continue
                        }
                        do {
                            var data = Data()
                            _ = try archive.extract(entry) { chunk in data.append(chunk) }
                            recognizedFiles.append(name)
                            if name.contains("physiological") || name.contains("cycle") {
                                let rows = try WhoopCSVImport.parse(data)
                                importedDays += store.band.importWhoopHistory(rows)
                            } else {
                                let category: String? = name.contains("journal") ? "journal_entries" :
                                    (name.contains("workout") ? "workouts" :
                                    (name.contains("sleep") ? "sleeps" : nil))
                                if let category {
                                    let count = try WhoopCSVImport.importSupplemental(data, source: category)
                                    supplementalCounts.append("\(category): \(count)")
                                } else {
                                    failures.append("\(name): unsupported WHOOP CSV category")
                                }
                            }
                        } catch {
                            failures.append("\(name): \(error.localizedDescription)")
                        }
                    }
                    let outcome = failures.isEmpty ? "All recognized files processed." :
                        "Not imported: " + failures.joined(separator: "; ")
                    whoopImportStatus = "ZIP: \(recognizedFiles.count) CSV files · \(importedDays) HRV/RHR days · \(supplementalCounts.joined(separator: ", ")). \(outcome) Supplemental rows are stored locally; activity/Recovery mapping pending."
                } else {
                    let data = try Data(contentsOf: url)
                    let name = url.lastPathComponent.lowercased()
                    let category: String? = name.contains("journal") ? "journal_entries" :
                        (name.contains("workout") ? "workouts" :
                        (name.contains("sleep") ? "sleeps" : nil))
                    if let category {
                        let count = try WhoopCSVImport.importSupplemental(data, source: category)
                        whoopImportStatus = "Saved \(count) \(category) records locally. Activity/Recovery mapping pending."
                    } else {
                        let rows = try WhoopCSVImport.parse(data)
                        let added = store.band.importWhoopHistory(rows)
                        whoopImportStatus = "Imported or completed \(added) days · \(store.band.baseline?.days ?? 0)/7 HRV + RHR baseline days"
                    }
                }
            } catch {
                whoopImportStatus = "Import failed: \(error.localizedDescription)"
            }
        }
        .onAppear {
            weightText = store.settings.weightKG.map { String(format: "%g", $0) } ?? ""
            heightText = store.settings.heightCM.map { String(format: "%g", $0) } ?? ""
        }
    }

    // MARK: Profile

    private var profilePanel: some View {
        Panel {
            SectionTitle("Profile")
            fieldRow(label: "Age") {
                TextField("30", value: $store.settings.age, format: .number)
                    .keyboardType(.numberPad)
                    .onChange(of: store.settings.age) { _, _ in
                        store.settings.ageConfirmed = true
                    }
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
            if !store.settings.ageConfirmed {
                Button("Confirm age for Fitness Age") {
                    store.settings.ageConfirmed = true
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.appAccent)
                Hint("30 is only a placeholder until you confirm your actual age.")
            }
            Picker("Sex", selection: $store.settings.sex) {
                ForEach(Sex.allCases) { sex in
                    Text(sex.label).tag(sex)
                }
            }
            .pickerStyle(.segmented)
            fieldRow(label: "Weight · kg") {
                TextField("70", text: $weightText)
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
                    .onChange(of: weightText) { _, text in
                        store.settings.weightKG = Self.parsedNumber(text)
                    }
            }
            fieldRow(label: "Height · cm") {
                TextField("175", text: $heightText)
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
                    .onChange(of: heightText) { _, text in
                        store.settings.heightCM = Self.parsedNumber(text)
                    }
            }
            Hint("Age feeds the default max-HR estimate (208 − 0.7 × age). Sex selects the Banister TRIMP coefficients, which drive strain, and the Keytel calorie coefficients. Weight and height only price the calorie estimate — leave them blank and the app shows an em dash rather than a number built on a guess.")
        }
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
            SectionTitle("Strap")
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.band.bandName ?? store.band.preferredBandName ?? "WHOOP MG")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text(store.band.status.title)
                        .font(.system(size: 11))
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))

            HStack(spacing: 12) {
                Button(store.band.isFindingBands ? "Searching…" : "Find another band") {
                    store.band.findBands()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appAccent)
                .disabled(store.band.isFindingBands)

                Spacer()

                if store.band.preferredBandID != nil {
                    Button("Forget saved band") { store.band.forgetPreferredBand() }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
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
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.appFG)
                                    Text("signal \(band.rssi) dBm")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.appMuted)
                                }
                                Spacer()
                                if band.id == store.band.preferredBandID {
                                    Text("saved")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.appGood)
                                }
                                Text("Connect")
                                    .font(.system(size: 11, weight: .semibold))
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

            if let firmware = store.band.firmwareRevision {
                Text("Firmware \(firmware)")
                    .font(.system(size: 11))
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
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 8)
            }
            if store.band.lastHistoryRecordCount > 0 {
                Text("Last history transfer: \(store.band.lastHistoryRecordCount) record frames")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 6)
            }
            if let lastSync = store.band.lastHistorySyncAt {
                Text("Last successful history decode: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
            .padding(.top, 10)
            Hint("Reads stored history when connected; otherwise starts Bluetooth connection.")

            if let summary = store.band.summary {
                let stats = store.band.drainStats
                Text("Last capture \(summary.sampleCount) samples · \(stats.acks) offload ACKs · \(store.band.days.count) day(s) scored")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 8)
                Button("Read stored history again") { store.band.readHistory() }
                    .font(.system(size: 11, weight: .medium))
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

    // MARK: Apple Health

    private var healthPanel: some View {
        Panel {
            SectionTitle("Apple Health")
            Toggle("Export measured sessions", isOn: Binding(
                get: { store.settings.healthKitEnabled },
                set: { store.setHealthKit($0) }
            ))
            .font(.system(size: 12))
            .tint(.appAccent)
            Text(store.healthKitStatus)
                .font(.system(size: 11))
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
                .font(.system(size: 12))
                .tint(.appAccent)
            Text(spo2ResearchReport)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
            Hint("Experimental: summarizes uncalibrated v18 historical candidate bytes after the next band sync. It does not measure blood oxygen, infer desaturation, or affect Recovery. Disable to stop future research summaries.")
        }
    }

    // MARK: WHOOP historical import

    private var whoopImportPanel: some View {
        Panel {
            SectionTitle("Import WHOOP history")
            Button("Import WHOOP data ZIP or CSV") {
                showWhoopImporter = true
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.appAccent)
            Text(whoopImportStatus)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Hint("Select the original WHOOP export ZIP directly. The importer reads CSVs locally and currently imports physiological-cycle HRV/RHR values; sleep, workout and journal rows are recognized but not yet mapped. Existing measured band values are preserved.")
        }
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
            Text("Reads stored history and live heart rate directly over Bluetooth. Nothing links back to WHOOP's services; your data stays on this phone unless you turn on the optional Apple Health export above.")
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
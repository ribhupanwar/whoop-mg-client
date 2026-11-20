import SwiftUI
import ZIPFoundation
import UniformTypeIdentifiers
import UserNotifications

// MARK: - 1. Connection & Sync View

struct ConnectionSyncView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("BAND STATUS")
                    HStack(spacing: 12) {
                        Circle()
                            .fill(store.band.isConnected ? Color.appGood : Color.appMuted)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.band.isConnected ? "Connected" : "Disconnected")
                                .font(StrapTypography.body(14, weight: .bold))
                                .foregroundStyle(Color.appFG)
                            Text(store.band.status.title)
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        if let pct = store.band.batteryPercent {
                            Text("\(pct)%")
                                .font(StrapTypography.metric(15, weight: .bold))
                                .foregroundStyle(Color.appFG)
                        }
                    }
                    .padding(.vertical, 6)

                    if let syncDate = store.band.lastHistorySyncAt {
                        Divider().background(Color.appLine).padding(.vertical, 6)
                        HStack {
                            Text("Last History Sync")
                                .font(StrapTypography.body(12, weight: .medium))
                                .foregroundStyle(Color.appMuted)
                            Spacer()
                            Text(syncDate.formatted(date: .abbreviated, time: .shortened))
                                .font(StrapTypography.body(12))
                                .foregroundStyle(Color.appFG)
                        }
                    }
                }

                Panel {
                    SectionTitle("SYNC ACTIONS")
                    Button {
                        store.band.readHistory()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text((store.band.isAnalyzingHistory || store.band.isSavingHistory) ? "Syncing with band…" : "Sync Band History Now")
                                .font(StrapTypography.body(13, weight: .semibold))
                            Spacer()
                            if store.band.isAnalyzingHistory || store.band.isSavingHistory {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 8)
                    }
                    .disabled(store.band.isAnalyzingHistory || store.band.isSavingHistory || !store.band.isConnected)

                    Divider().background(Color.appLine)

                    Button {
                        store.band.autoConnectIfNeeded()
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Reconnect Band Session")
                                .font(StrapTypography.body(13, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 8)
                    }
                }

                Panel {
                    SectionTitle("CAPTURE DIAGNOSTICS")
                    Text("Indicators evaluate the latest analyzed capture window.")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                        .padding(.bottom, 6)

                    ForEach(DataQuality.inspect(store.lastCapture)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.name)
                                    .font(StrapTypography.body(13, weight: .medium))
                                    .foregroundStyle(Color.appFG)
                                Spacer()
                                Text(item.total == 0 ? "No data" : "\(item.available)/\(item.total)")
                                    .font(StrapTypography.body(11))
                                    .foregroundStyle(Color.appMuted)
                            }
                            Text(item.reason)
                                .font(StrapTypography.body(10.5))
                                .foregroundStyle(Color.appMuted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Connection & Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 2. Band Alarms View

struct BandAlarmsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var alarmOn = WakeAlarm.isEnabled
    @State private var wakeMinutes = WakeAlarm.wakeMinutes
    @State private var showWakePicker = false
    @State private var savedConfirmation = false

    private var wakeDateBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = (wakeMinutes / 60) % 24
                c.minute = wakeMinutes % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let mins = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                wakeMinutes = mins
                if alarmOn {
                    WakeAlarm.setEnabled(true, wakeMinutes: mins)
                    store.band.syncWakeAlarm(force: true)
                }
            }
        )
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("WAKE ALARM")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Silent Haptic Alarm")
                                .font(StrapTypography.body(14, weight: .bold))
                                .foregroundStyle(Color.appFG)
                            Text("Wakes you with gentle wrist vibrations")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        Toggle("", isOn: $alarmOn)
                            .labelsHidden()
                            .tint(Color.appGood)
                            .onChange(of: alarmOn) { _, newValue in
                                WakeAlarm.setEnabled(newValue, wakeMinutes: wakeMinutes)
                                store.band.syncWakeAlarm(force: true)
                                savedConfirmation = true
                            }
                    }
                    .padding(.vertical, 4)

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wake Time")
                                .font(StrapTypography.body(13, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("Daily target wake schedule")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        Button {
                            showWakePicker = true
                        } label: {
                            Text(CoachFormat.clock(wakeMinutes))
                                .font(StrapTypography.metric(17, weight: .bold))
                                .foregroundStyle(Color.appFG)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.appRaised))
                        }
                    }
                    .padding(.vertical, 4)

                    if savedConfirmation {
                        Text("Alarm preference updated for \(CoachFormat.clock(wakeMinutes)).")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appGood)
                            .padding(.top, 4)
                    }
                }

                Panel {
                    SectionTitle("BAND HAPTIC SYNC")
                    Text(store.band.bandAlarmMessage)
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 4)

                    if store.band.canTestBuzz {
                        Divider().background(Color.appLine).padding(.vertical, 4)
                        Button {
                            store.band.testBuzz()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                Text(store.band.testingBuzz ? "Sending buzz…" : "Test Band Vibration")
                                    .font(StrapTypography.body(13, weight: .semibold))
                            }
                            .foregroundStyle(Color.appAccent)
                            .padding(.vertical, 6)
                        }
                        .disabled(store.band.testingBuzz)

                        if !store.band.buzzMessage.isEmpty {
                            Text(store.band.buzzMessage)
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                    }
                }

                Panel {
                    SectionTitle("PHONE NOTIFICATION BACKUP")
                    Text("A local phone alert also schedules as an emergency backup if your band battery is depleted.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
        .navigationTitle("Band Alarms")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWakePicker) {
            NavigationStack {
                DatePicker("Wake time", selection: wakeDateBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                    .navigationTitle("Select Wake Time")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showWakePicker = false
                                WakeAlarm.setEnabled(alarmOn, wakeMinutes: wakeMinutes)
                                store.band.syncWakeAlarm(force: true)
                                savedConfirmation = true
                            }
                            .font(StrapTypography.body(16, weight: .bold))
                        }
                    }
            }
            .presentationDetents([.height(300)])
        }
    }
}

// MARK: - 3. Data Management View

struct DataManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var preparingExport = false
    @State private var exportingBackup = false
    @State private var showRestoreImporter = false
    @State private var restorePreview: StrapBackup.Preview?
    @State private var restoreStatus: String?
    @State private var showWhoopImporter = false
    @State private var importingWhoop = false
    @State private var whoopImportStatus = "No WHOOP file imported"

    private var backupUnavailable: Bool {
        preparingExport || store.band.isConnected || store.band.isAnalyzingHistory || store.band.isSavingHistory
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                // SECTION 1: WHOOP DATA IMPORT
                Panel {
                    SectionTitle("WHOOP ARCHIVE IMPORT")
                    Button {
                        showWhoopImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text(importingWhoop ? "Importing…" : "Import WHOOP ZIP or CSV")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            if importingWhoop { ProgressView().controlSize(.small) }
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }
                    .disabled(importingWhoop)

                    if !whoopImportStatus.isEmpty {
                        Text(whoopImportStatus)
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                            .padding(.top, 2)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    NavigationLink { ImportHistoryView() } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                            Text("Inspect Past Import Records")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.appFG)
                        .padding(.vertical, 6)
                    }
                }

                // SECTION 2: BACKUP & RESTORE
                Panel {
                    SectionTitle("STRAP BACKUP & RESTORE")
                    Button {
                        prepareExport(fullBackup: true)
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive.badge.checkmark")
                            Text("Export Full STRAP Backup (ZIP)")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            if preparingExport && exportingBackup { ProgressView().controlSize(.small) }
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }
                    .disabled(backupUnavailable)

                    if backupUnavailable && store.band.isConnected {
                        Text("Disconnect band before full database backup to guarantee SQLite snapshot integrity.")
                            .font(StrapTypography.body(10.5))
                            .foregroundStyle(Color.appMuted)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    Button {
                        prepareExport(fullBackup: false)
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Diagnostic Summary & Captures")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            if preparingExport && !exportingBackup { ProgressView().controlSize(.small) }
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }
                    .disabled(preparingExport)

                    if let exportURL {
                        Divider().background(Color.appLine).padding(.vertical, 4)
                        ShareLink(item: exportURL) {
                            HStack {
                                Image(systemName: "square.and.arrow.up.fill")
                                Text("Save Export File to Files / iCloud")
                                    .font(StrapTypography.body(13.5, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(Color.appGood)
                            .padding(.vertical, 6)
                        }
                    }

                    if let exportError {
                        Text(exportError).font(StrapTypography.body(11)).foregroundStyle(Color.appWarn)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    Button {
                        showRestoreImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restore STRAP Backup (ZIP)")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }

                    if let restoreStatus {
                        Text(restoreStatus)
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appGood)
                            .padding(.top, 2)
                    }
                }

                // SECTION 3: REVISIONS & CORRECTIONS
                Panel {
                    SectionTitle("REVISIONS & CORRECTIONS")
                    NavigationLink { SleepRecoveryView() } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Preview & Recover Saved Sleep")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.appFG)
                        .padding(.vertical, 6)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    NavigationLink { ManualActivityHistoryView() } label: {
                        HStack {
                            Image(systemName: "figure.run.circle")
                            Text("Manual Activity History & Merges")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.appFG)
                        .padding(.vertical, 6)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    NavigationLink(value: Route.sleepAnalysis) {
                        HStack {
                            Image(systemName: "moon.stars")
                            Text("Sleep Staging Epoch Export (CSV)")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.appFG)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Data Import & Export")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showWhoopImporter, allowedContentTypes: [.zip, .commaSeparatedText, .plainText]) { result in
            importWhoopFile(result)
        }
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.zip]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do { restorePreview = try await Task.detached { try StrapBackup.inspect(url) }.value }
                    catch { restoreStatus = error.localizedDescription }
                }
            } catch { restoreStatus = error.localizedDescription }
        }
        .alert("Restore preview", isPresented: Binding(get: { restorePreview != nil }, set: { if !$0 { restorePreview = nil } })) {
            Button("Stage for next launch") {
                guard let preview = restorePreview else { return }
                do {
                    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    try StrapBackup.stage(preview, support: support)
                    restoreStatus = "Backup validated and staged. Restart STRAP to complete restore. Existing records take precedence."
                } catch { restoreStatus = error.localizedDescription }
                restorePreview = nil
            }
            Button("Cancel", role: .cancel) { restorePreview = nil }
        } message: { Text(restorePreview?.description ?? "") }
    }

    private func importWhoopFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            importingWhoop = true
            whoopImportStatus = "Reading and validating WHOOP export…"
            Task {
                defer { if scoped { url.stopAccessingSecurityScopedResource() }; importingWhoop = false }
                do {
                    let plan = try await Task.detached(priority: .userInitiated) {
                        try WhoopImportBatch.prepare(url, fromDate: nil, throughDate: nil)
                    }.value
                    try plan.commit()
                    let updated = store.band.importWhoopHistory(plan.biometricRows)
                    store.refreshWhoopImportedHistory()
                    whoopImportStatus = plan.summary(updatedDays: updated)
                } catch { whoopImportStatus = "Import failed: " + error.localizedDescription }
            }
        } catch { whoopImportStatus = "Import failed: " + error.localizedDescription }
    }

    private func prepareExport(fullBackup: Bool) {
        exportURL = nil
        exportError = nil
        exportingBackup = fullBackup
        preparingExport = true
        Task {
            do {
                if fullBackup { try await store.band.flushPersistedCaches() }
                let preferences = UserDefaults.standard.dictionaryRepresentation()
                let fm = FileManager.default
                let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                exportURL = try await Task.detached(priority: .userInitiated) {
                    try PersistenceDiagnostics.write(support: support, documents: documents,
                        preferences: preferences, fullBackup: fullBackup)
                }.value
            } catch { exportError = error.localizedDescription }
            preparingExport = false
        }
    }
}

// MARK: - 4. Notification Settings View

struct NotificationSettingsView: View {
    @AppStorage("strap.wake.alarm.enabled.v1") private var wakeAlarmEnabled = false
    @AppStorage("strap.notifications.bedtimeReminders") private var bedtimeReminders = false
    @AppStorage("strap.notifications.targetAlerts") private var targetAlerts = false
    @State private var permissionStatus: String = "Checking permissions…"
    @State private var authorized = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("SYSTEM NOTIFICATION STATUS")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permissionStatus)
                                .font(StrapTypography.body(14, weight: .bold))
                                .foregroundStyle(Color.appFG)
                            Text("Local notifications require iOS authorization")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        Circle()
                            .fill(authorized ? Color.appGood : Color.appWarn)
                            .frame(width: 10, height: 10)
                    }
                    .padding(.vertical, 4)

                    if !authorized {
                        Divider().background(Color.appLine).padding(.vertical, 4)
                        Button {
                            requestPermission()
                        } label: {
                            Text("Request Notification Access")
                                .font(StrapTypography.body(13, weight: .semibold))
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                }

                Panel {
                    SectionTitle("ALERT CHANNELS")
                    Toggle(isOn: $wakeAlarmEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wake Alarm Phone Alert")
                                .font(StrapTypography.body(13.5, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("Fires backup phone sound at scheduled wake time")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                    }
                    .tint(Color.appGood)
                    .padding(.vertical, 6)

                    Divider().background(Color.appLine)

                    Toggle(isOn: $bedtimeReminders) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bedtime Reminder")
                                .font(StrapTypography.body(13.5, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("Notifies when your optimal sleep window approaches")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                    }
                    .tint(Color.appGood)
                    .padding(.vertical, 6)

                    Divider().background(Color.appLine)

                    Toggle(isOn: $targetAlerts) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recovery & Strain Target Alerts")
                                .font(StrapTypography.body(13.5, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("Alerts when morning recovery or day strain target is reached")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                    }
                    .tint(Color.appGood)
                    .padding(.vertical, 6)
                }

                Panel {
                    SectionTitle("LOCAL PRIVACY")
                    Text("STRAP notification triggers are evaluated and scheduled entirely on your iPhone using UNCalendarNotificationTrigger. No network requests or notification servers are ever contacted.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { checkPermission() }
    }

    private func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    permissionStatus = "Notifications Allowed"
                    authorized = true
                case .denied:
                    permissionStatus = "Notifications Denied in iOS Settings"
                    authorized = false
                case .notDetermined:
                    permissionStatus = "Permission Not Yet Requested"
                    authorized = false
                @unknown default:
                    permissionStatus = "Status Unknown"
                    authorized = false
                }
            }
        }
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                checkPermission()
            }
        }
    }
}

// MARK: - 5. App Preferences View

struct AppPreferencesView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("strap.preferences.useMetric") private var useMetric = true
    @AppStorage("strap.preferences.use24HourTime") private var use24HourTime = false
    @AppStorage("strap.spo2ResearchEnabled") private var spo2ResearchEnabled = false
    @AppStorage("strap.spo2ResearchReport") private var spo2ResearchReport = "No research capture yet."

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("MEASUREMENT UNITS")
                    Picker("Unit System", selection: $useMetric) {
                        Text("Metric (kg, cm)").tag(true)
                        Text("Imperial (lbs, ft/in)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    Divider().background(Color.appLine).padding(.vertical, 6)

                    Toggle(isOn: $use24HourTime) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("24-Hour Clock")
                                .font(StrapTypography.body(13.5, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("Use 24:00 time notation across timelines")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                    }
                    .tint(Color.appGood)
                    .padding(.vertical, 4)
                }

                Panel {
                    SectionTitle("RESEARCH & EXPERIMENTAL")
                    Toggle(isOn: $spo2ResearchEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Collect SpO₂ Research Candidates")
                                .font(StrapTypography.body(13.5, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("Extract candidate pulses from V18 Gen5 hardware packets")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                    }
                    .tint(Color.appGood)
                    .padding(.vertical, 4)

                    if spo2ResearchEnabled {
                        Text(spo2ResearchReport)
                            .font(StrapTypography.body(10.5))
                            .foregroundStyle(Color.appMuted)
                            .padding(.top, 4)
                    }
                }

                Panel {
                    SectionTitle("PREVIEW & TESTING")
                    Toggle("Design preview with sample data", isOn: $store.settings.designPreview)
                        .font(StrapTypography.body(13.5, weight: .medium))
                        .tint(Color.appAccent)
                        .padding(.vertical, 4)

                    Text("OFF: every unmeasured metric shows — and waiting states explain what data is needed. ON: labelled sample values fill the layout behind a visible banner.")
                        .font(StrapTypography.body(10.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.top, 2)
                }
            }
        }
        .navigationTitle("App Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 6. App Information View

struct AppInfoView: View {
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("STRAP")
                            .font(StrapTypography.metric(28, weight: .bold))
                            .foregroundStyle(Color.appFG)
                        Text("LOCAL-FIRST BIOMETRIC CLIENT")
                            .font(StrapTypography.body(11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Color.appAccent)
                        Text("Version 1.0 (Build \(BuildInfo.revision))")
                            .font(StrapTypography.body(12))
                            .foregroundStyle(Color.appMuted)
                    }
                    .padding(.vertical, 8)
                }

                Panel {
                    SectionTitle("LOCAL-FIRST ARCHITECTURE")
                    Text("STRAP is an offline-capable, clean-room client engineered for WHOOP 5.0 and WHOOP MG devices. All signal processing, heart rate tracking, HRV analysis, strain accumulation, and sleep calculations run directly on your iPhone. Your biometrics are never sent to external cloud servers.")
                        .font(StrapTypography.body(12.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 4)
                }

                Panel {
                    SectionTitle("TYPOGRAPHY")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Proxima Nova & DIN Pro")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                                .foregroundStyle(Color.appFG)
                            Text(StrapTypography.missingBundledFaces.isEmpty ? "All licensed font faces verified and loaded." : "Missing: \(StrapTypography.missingBundledFaces.joined(separator: ", "))")
                                .font(StrapTypography.body(11))
                                .foregroundStyle(StrapTypography.missingBundledFaces.isEmpty ? Color.appGood : Color.appWarn)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Panel {
                    SectionTitle("COMMUNITY & REPOSITORY")
                    ShareLink(item: "Experience offline health tracking with STRAP: https://github.com/ribhupanwar/whoop-mg-client") {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share STRAP with Friends")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    Link(destination: URL(string: "https://github.com/ribhupanwar/whoop-mg-client")!) {
                        HStack {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                            Text("Open GitHub Repository")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.appFG)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("App Information")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 7. Diagnostics & Support View

struct DiagnosticsSupportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var preparingExport = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("SYSTEM STATUS")
                    HStack {
                        Text("Active Band Connection")
                            .font(StrapTypography.body(13, weight: .medium))
                            .foregroundStyle(Color.appFG)
                        Spacer()
                        Text(store.band.isConnected ? "Connected" : "Disconnected")
                            .font(StrapTypography.body(12, weight: .bold))
                            .foregroundStyle(store.band.isConnected ? Color.appGood : Color.appMuted)
                    }
                    .padding(.vertical, 4)

                    Divider().background(Color.appLine)

                    HStack {
                        Text("Band Hardware UUID")
                            .font(StrapTypography.body(13, weight: .medium))
                            .foregroundStyle(Color.appFG)
                        Spacer()
                        Text(store.band.preferredBandID?.prefix(8).appending("…") ?? "None")
                            .font(StrapTypography.body(12))
                            .foregroundStyle(Color.appMuted)
                    }
                    .padding(.vertical, 4)

                    Divider().background(Color.appLine)

                    HStack {
                        Text("Last History Sync")
                            .font(StrapTypography.body(13, weight: .medium))
                            .foregroundStyle(Color.appFG)
                        Spacer()
                        Text(store.band.lastHistorySyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "None")
                            .font(StrapTypography.body(12))
                            .foregroundStyle(Color.appMuted)
                    }
                    .padding(.vertical, 4)
                }

                Panel {
                    SectionTitle("BLE STREAM & PACKET INTEGRITY")
                    NavigationLink(value: Route.dataQuality) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("Open Data Quality Inspector")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.appFG)
                        .padding(.vertical, 6)
                    }
                }

                Panel {
                    SectionTitle("DIAGNOSTICS EXPORT")
                    Button {
                        prepareDiagnosticExport()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Generate Diagnostics Archive")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            if preparingExport { ProgressView().controlSize(.small) }
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }
                    .disabled(preparingExport)

                    if let exportURL {
                        Divider().background(Color.appLine).padding(.vertical, 4)
                        ShareLink(item: exportURL) {
                            HStack {
                                Image(systemName: "square.and.arrow.up.fill")
                                Text("Save Diagnostics Bundle")
                                    .font(StrapTypography.body(13.5, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(Color.appGood)
                            .padding(.vertical, 6)
                        }
                    }

                    if let exportError {
                        Text(exportError).font(StrapTypography.body(11)).foregroundStyle(Color.appWarn)
                    }
                }

                Panel {
                    SectionTitle("OFFLINE HARDWARE SUPPORT")
                    Text("• Sensor Placement: Position the optical sensor 1 finger-width above the wrist bone with a snug band tension.\n• Double-Tap Pairing: Firmly double-tap the top of your WHOOP band until the blue LED blinks to advertise.\n• Reconnection: STRAP automatically reconnects to your paired band in the background when in range.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Diagnostics & Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prepareDiagnosticExport() {
        exportURL = nil
        exportError = nil
        preparingExport = true
        Task {
            do {
                let preferences = UserDefaults.standard.dictionaryRepresentation()
                let fm = FileManager.default
                let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                exportURL = try await Task.detached(priority: .userInitiated) {
                    try PersistenceDiagnostics.write(support: support, documents: documents,
                        preferences: preferences, fullBackup: false)
                }.value
            } catch { exportError = error.localizedDescription }
            preparingExport = false
        }
    }
}

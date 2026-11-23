import SwiftUI
import ZIPFoundation
import UniformTypeIdentifiers
import UserNotifications
import UIKit

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
                            Text(store.band.isConnected && store.band.status == .scanning
                                 ? "Connected · updating connection status"
                                 : store.band.status.title)
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

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    HStack {
                        Text("Device Serial Number")
                            .font(StrapTypography.body(12, weight: .medium))
                            .foregroundStyle(Color.appMuted)
                        Spacer()
                        Text(store.band.serialNumber ?? (store.band.isConnected ? "Reading from strap…" : "Unavailable offline"))
                            .font(StrapTypography.body(12, weight: .semibold))
                            .foregroundStyle(Color.appFG)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    HStack {
                        Text("Last History Sync")
                            .font(StrapTypography.body(12, weight: .medium))
                            .foregroundStyle(Color.appMuted)
                        Spacer()
                        Text(store.band.lastHistorySyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "No sync recorded yet")
                            .font(StrapTypography.body(12))
                            .foregroundStyle(store.band.lastHistorySyncAt != nil ? Color.appFG : Color.appMuted)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    HStack {
                        Text("History Processing")
                            .font(StrapTypography.body(12, weight: .medium))
                            .foregroundStyle(Color.appMuted)
                        Spacer()
                        Text(pendingDataDescription)
                            .font(StrapTypography.body(12, weight: .semibold))
                            .foregroundStyle(store.band.isAnalyzingHistory || store.band.status == .draining ? Color.appAccent : Color.appFG)
                    }

                    if case .reconnecting(let attempt) = store.band.status {
                        Divider().background(Color.appLine).padding(.vertical, 4)
                        HStack {
                            Text("Reconnect Attempt")
                                .font(StrapTypography.body(12, weight: .medium))
                                .foregroundStyle(Color.appWarn)
                            Spacer()
                            Text("Attempt \(attempt) · Backoff \(Int(ReconnectBackoffPolicy.delay(forAttempt: attempt)))s")
                                .font(StrapTypography.metric(11, weight: .semibold))
                                .foregroundStyle(Color.appWarn)
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

                if store.band.status == .draining || store.band.drainStats.acks > 0 {
                    Panel {
                        SectionTitle("BAND HISTORY TRANSFER")
                        Text("\(store.band.drainStats.acks) chunks acknowledged · \(store.band.drainStats.samples) records received")
                            .font(StrapTypography.body(12))
                            .foregroundStyle(Color.appFG)
                        Text("These are measured transfer counters, not a percentage of total band history.")
                            .font(StrapTypography.body(10.5))
                            .foregroundStyle(Color.appMuted)
                    }
                }

                if let progress = store.band.historyProgress {
                    Panel {
                        SectionTitle("HISTORICAL BACKFILL PROGRESS")
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Sync Phase: \(progress.stage.title)")
                                    .font(StrapTypography.body(12, weight: .bold))
                                    .foregroundStyle(Color.appFG)
                                Spacer()
                                if progress.total > 0 {
                                    Text("\(progress.completed)/\(progress.total) chunks")
                                        .font(StrapTypography.metric(12, weight: .medium))
                                        .foregroundStyle(Color.appMuted)
                                }
                            }
                            if progress.total > 0 {
                                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                                    .tint(Color.appAccent)
                            }
                            if progress.reused > 0 {
                                Text("\(progress.reused) verified night records reused from cache.")
                                    .font(StrapTypography.body(10.5))
                                    .foregroundStyle(Color.appGood)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Panel {
                    SectionTitle("CAPTURE & PACKET DIAGNOSTICS")
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

                Panel {
                    SectionTitle("STREAM INTEGRITY & PACKET ERRORS")
                    VStack(alignment: .leading, spacing: 6) {
                        metricDiagnosticsRow("Packet Gap Drops", value: "\(store.band.packetGapCount)")
                        Divider().background(Color.appLine)
                        metricDiagnosticsRow("Duplicate Packets", value: "\(store.band.duplicatePacketCount)")
                        Divider().background(Color.appLine)
                        metricDiagnosticsRow("Undecodable Frames", value: "\(store.band.historyUndecodableFrames)")
                        Divider().background(Color.appLine)
                        metricDiagnosticsRow("Live Packets Processed", value: "\(store.band.type40HRPackets + store.band.standardHRPackets)")
                        Divider().background(Color.appLine)
                        metricDiagnosticsRow("History Records With R-R Data", value: "\(store.band.historyRRRecords)")
                        Divider().background(Color.appLine)
                        metricDiagnosticsRow("Sync Stream Error", value: store.band.historySyncError ?? "No error recorded")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Connection & Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pendingDataDescription: String {
        if store.band.isAnalyzingHistory || store.band.isSavingHistory {
            if let p = store.band.historyProgress, p.total > 0 {
                return p.detail(now: Date())
            }
            return "Analyzing history…"
        } else if store.band.status == .draining {
            return "Draining flash frames…"
        } else {
            return "Idle · band backlog unknown"
        }
    }

    private func metricDiagnosticsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appMuted)
            Spacer()
            Text(value)
                .font(StrapTypography.body(12, weight: .semibold))
                .foregroundStyle(Color.appFG)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 2. Band Alarms View

struct BandAlarmsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var alarmOn = WakeAlarm.isEnabled
    @State private var wakeMinutes = WakeAlarm.wakeMinutes
    @State private var schedule = WakeAlarm.schedule
    @State private var editingWeekday: Int? = nil
    @State private var editingMinutes = 7 * 60
    @State private var savedConfirmation = false

    private var nextWake: Date? {
        WakeAlarm.nextWakeDate()
    }

    private var isBandConfirmed: Bool {
        WakeAlarm.isBandConfirmed(for: nextWake)
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                // Section 1: Master Wake Alarm Card
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
                                WakeAlarm.isEnabled = newValue
                                store.band.syncWakeAlarm(force: true)
                                savedConfirmation = true
                            }
                    }
                    .padding(.vertical, 4)

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    // Next Armed Alarm Status Banner
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Scheduled Wake")
                                .font(StrapTypography.body(13, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            if alarmOn, let next = nextWake {
                                Text(next.formatted(date: .abbreviated, time: .shortened))
                                    .font(StrapTypography.body(11))
                                    .foregroundStyle(Color.appMuted)
                            } else {
                                Text("No alarm set")
                                    .font(StrapTypography.body(11))
                                    .foregroundStyle(Color.appMuted)
                            }
                        }
                        Spacer()
                        if alarmOn, nextWake != nil {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isBandConfirmed ? Color.appGood : Color.appWarn)
                                    .frame(width: 7, height: 7)
                                Text(isBandConfirmed ? "Armed on band" : "Pending sync")
                                    .font(StrapTypography.body(11, weight: .semibold))
                                    .foregroundStyle(isBandConfirmed ? Color.appGood : Color.appWarn)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.appRaised))
                        }
                    }
                    .padding(.vertical, 4)

                    if savedConfirmation {
                        Text(alarmOn ? "Alarm preference updated. Synchronizing with strap…" : "Alarm disabled.")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appGood)
                            .padding(.top, 2)
                    }
                }

                // Section 2: 7-Day Weekly Repeat Schedule
                Panel {
                    SectionTitle("WEEKLY SCHEDULE (7 DAYS)")
                    Text("Configure different wake targets for weekdays and weekends. Reconnect strap to upload updated schedules.")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                        .padding(.bottom, 6)

                    ForEach(schedule) { dayEntry in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                // Day Name
                                Text(dayEntry.weekdayShort.uppercased())
                                    .font(StrapTypography.body(12, weight: .bold))
                                    .foregroundStyle(dayEntry.isEnabled ? Color.appFG : Color.appMuted)
                                    .frame(width: 36, alignment: .leading)

                                Text(dayEntry.weekdayName)
                                    .font(StrapTypography.body(13, weight: .medium))
                                    .foregroundStyle(dayEntry.isEnabled ? Color.appFG : Color.appMuted)

                                Spacer()

                                // Time Picker Trigger
                                Button {
                                    editingWeekday = dayEntry.weekday
                                    editingMinutes = dayEntry.wakeMinutes
                                } label: {
                                    Text(CoachFormat.clock(dayEntry.wakeMinutes))
                                        .font(StrapTypography.metric(15, weight: .bold))
                                        .foregroundStyle(dayEntry.isEnabled ? Color.appFG : Color.appMuted)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.appRaised))
                                }
                                .disabled(!dayEntry.isEnabled || !alarmOn)

                                // Individual Day Toggle
                                Toggle("", isOn: Binding(
                                    get: { dayEntry.isEnabled },
                                    set: { newEnabled in
                                        WakeAlarm.updateSchedule(weekday: dayEntry.weekday, isEnabled: newEnabled, wakeMinutes: dayEntry.wakeMinutes)
                                        schedule = WakeAlarm.schedule
                                        store.band.syncWakeAlarm(force: true)
                                    }
                                ))
                                .labelsHidden()
                                .tint(Color.appGood)
                                .disabled(!alarmOn)
                            }
                            .padding(.vertical, 6)

                            if dayEntry.weekday != 7 {
                                Divider().background(Color.appLine).padding(.vertical, 2)
                            }
                        }
                    }
                }

                // Section 3: Band Haptic Vibration Test
                Panel {
                    SectionTitle("BAND HAPTIC SYNC & TEST")
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
                                Image(systemName: StrapIcon.Device.vibrationBuzz)
                                Text(store.band.testingBuzz ? "Sending buzz…" : "Test Band Vibration Buzz")
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

                // Section 4: Emergency Backup Notification
                Panel {
                    SectionTitle("EMERGENCY PHONE BACKUP")
                    Text("A local notification alert is automatically scheduled as an emergency backup if your band battery is depleted at wake time.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
        .navigationTitle("Band Alarms")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { editingWeekday.map { DayIdentifiable(id: $0) } },
            set: { editingWeekday = $0?.id }
        )) { dayIdent in
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker("Wake time", selection: Binding(
                        get: {
                            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                            c.hour = (editingMinutes / 60) % 24
                            c.minute = editingMinutes % 60
                            return Calendar.current.date(from: c) ?? Date()
                        },
                        set: { newDate in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            editingMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                        }
                    ), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()

                    Spacer()
                }
                .navigationTitle("Set \(schedule.first(where: { $0.weekday == dayIdent.id })?.weekdayName ?? "") Wake")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            WakeAlarm.updateSchedule(weekday: dayIdent.id, isEnabled: true, wakeMinutes: editingMinutes)
                            schedule = WakeAlarm.schedule
                            editingWeekday = nil
                            store.band.syncWakeAlarm(force: true)
                        }
                        .font(StrapTypography.body(16, weight: .bold))
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingWeekday = nil }
                    }
                }
            }
            .presentationDetents([.height(320)])
        }
    }
}

private struct DayIdentifiable: Identifiable {
    let id: Int
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
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var denied = false
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
                            if denied, let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            } else {
                                requestPermission()
                            }
                        } label: {
                            Text(denied ? "Open iOS Settings" : "Request Notification Access")
                                .font(StrapTypography.body(13, weight: .semibold))
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                }

                Panel {
                    SectionTitle("WAKE ALARM")
                    NavigationLink {
                        BandAlarmsView()
                    } label: {
                        Label("Edit wake alarm schedule", systemImage: "alarm")
                            .font(StrapTypography.body(13.5, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                    }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkPermission() }
        }
    }

    private func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                denied = settings.authorizationStatus == .denied
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
    @AppStorage("strap.spo2ResearchEnabled") private var spo2ResearchEnabled = false
    @AppStorage("strap.spo2ResearchReport") private var spo2ResearchReport = "No research capture yet."

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("DISPLAY FORMATS")
                    Text("Measurements are shown in metric units. Localized times follow your iPhone settings.")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
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
                    SectionTitle("TYPOGRAPHY ASSET STATUS")
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
                    SectionTitle("DEVELOPER ICON REGISTRY")
                    NavigationLink {
                        IconGalleryView()
                    } label: {
                        HStack {
                            Image(systemName: "square.grid.3x3.fill")
                            Text("Developer Icon Gallery & Contact Sheet")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }
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
    @State private var activityDecisionURL: URL?
    @State private var exportError: String?
    @State private var preparingExport = false
    @State private var anonymizeDiagnostics = true

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                // Section 1: CoreBluetooth & Central State
                Panel {
                    SectionTitle("COREBLUETOOTH RESTORATION & LINK")
                    infoRow("Bluetooth Central State", value: "Powered On")
                    Divider().background(Color.appLine)
                    infoRow("Restoration Identifier", value: "strap.central.restore")
                    Divider().background(Color.appLine)
                    infoRow("Active Connection", value: store.band.isConnected ? "Connected" : store.band.status.title)
                    Divider().background(Color.appLine)
                    infoRow("HR Bond Status", value: store.band.hrBondConfirmed ? "Bond Confirmed" : "Not Bonded")
                }

                // Section 2: Hardware Details
                Panel {
                    SectionTitle("HARDWARE IDENTITY")
                    infoRow("Device Serial Number", value: store.band.serialNumber ?? (store.band.isConnected ? "Reading from strap…" : "Unavailable offline"))
                    Divider().background(Color.appLine)
                    infoRow("Device Model", value: store.band.modelNumber ?? store.band.bandName ?? store.band.preferredBandName ?? "WHOOP 5.0 / MG")
                    Divider().background(Color.appLine)
                    infoRow("Firmware Revision", value: store.band.firmwareRevision ?? "Reading from strap…")
                    Divider().background(Color.appLine)
                    infoRow("Hardware Revision", value: store.band.hardwareRevision ?? "WHOOP MG")
                }

                // Section 3: Historical Sync & Packet Stream
                Panel {
                    SectionTitle("STREAM & PACKET INTEGRITY")
                    infoRow("Last Packet Received", value: store.band.lastPacketReceivedAt?.formatted(date: .abbreviated, time: .standard) ?? "None")
                    Divider().background(Color.appLine)
                    infoRow("Last History Sync", value: store.band.lastHistorySyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "None")
                    Divider().background(Color.appLine)
                    infoRow("Packet Decoder Format", value: "V18 Gen5 Maverick / R24")
                    Divider().background(Color.appLine)
                    infoRow("Live RR Packets Processed", value: "\(store.band.type40RRPackets + store.band.standardRRPackets)")
                    Divider().background(Color.appLine)
                    infoRow("History Records With R-R Data", value: "\(store.band.historyRRRecords)")
                }

                // Section 4: Sensor Feeds
                Panel {
                    SectionTitle("SENSOR STATUS & FEEDS")
                    sensorFeedRow(name: "Optical PPG (Green / Red / IR)", status: store.band.isConnected ? "Active" : "Idle")
                    Divider().background(Color.appLine)
                    sensorFeedRow(name: "3-Axis Accelerometer (25-50 Hz)", status: store.band.isConnected ? "Active" : "Idle")
                    Divider().background(Color.appLine)
                    sensorFeedRow(name: "Capacitive Contact (CapSense)", status: store.band.isConnected ? "Monitoring" : "Idle")
                    Divider().background(Color.appLine)
                    sensorFeedRow(name: "Battery Fuel Gauge", status: store.band.batteryPercent.map { "\($0)%" } ?? "Unknown")
                }

                // Section 5: Diagnostics Export
                Panel {
                    SectionTitle("DIAGNOSTICS EXPORT")
                    Toggle(isOn: $anonymizeDiagnostics) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anonymize Hardware Identifiers")
                                .font(StrapTypography.body(13, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("Masks real serial and Bluetooth UUIDs in export")
                                .font(StrapTypography.body(10.5))
                                .foregroundStyle(Color.appMuted)
                        }
                    }
                    .tint(Color.appGood)
                    .padding(.vertical, 4)

                    Divider().background(Color.appLine).padding(.vertical, 4)

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

                    Button("Generate Activity Decision Report") {
                        preparingExport = true
                        exportError = nil
                        activityDecisionURL = nil
                        Task {
                            defer { preparingExport = false }
                            do { activityDecisionURL = try await store.band.exportActivityDecisions() }
                            catch { exportError = error.localizedDescription }
                        }
                    }
                    .disabled(preparingExport)
                    if let activityDecisionURL {
                        ShareLink("Share Activity Decision JSON", item: activityDecisionURL)
                    }

                    Divider().background(Color.appLine).padding(.vertical, 4)
                    ShareLink(item: BLEDiagnosticLog.shared.exportURL()) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("Export BLE Logs")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }

                    if let exportError {
                        Text(exportError).font(StrapTypography.body(11)).foregroundStyle(Color.appWarn)
                    }
                }

                // Section 6: Hardware Support Guidelines
                Panel {
                    SectionTitle("OFFLINE HARDWARE SUPPORT")
                    Text("• Sensor Placement: Position the optical sensor 1 finger-width above the wrist bone with snug band tension.\n• Double-Tap Pairing: Firmly double-tap the top of your WHOOP band until the blue LED blinks to advertise.\n• Reconnection: STRAP automatically reconnects to your paired band in the background when in range using bounded exponential backoff.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Diagnostics & Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appMuted)
            Spacer()
            Text(value)
                .font(StrapTypography.body(12, weight: .semibold))
                .foregroundStyle(Color.appFG)
        }
        .padding(.vertical, 4)
    }

    private func sensorFeedRow(name: String, status: String) -> some View {
        HStack {
            Text(name)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appFG)
            Spacer()
            Text(status)
                .font(StrapTypography.body(11, weight: .semibold))
                .foregroundStyle(status == "Active" || status == "Monitoring" ? Color.appGood : Color.appMuted)
        }
        .padding(.vertical, 3)
    }

    private func prepareDiagnosticExport() {
        exportURL = nil
        exportError = nil
        preparingExport = true
        Task {
            do {
                var preferences = UserDefaults.standard.dictionaryRepresentation()
                if anonymizeDiagnostics {
                    preferences.removeValue(forKey: "strap.band.preferredID")
                    preferences.removeValue(forKey: "strap.band.cachedSerial")
                }
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

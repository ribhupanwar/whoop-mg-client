import SwiftUI
import UniformTypeIdentifiers

/// One metadata source for the production menu labels, icons and UI test identifiers.
enum MoreMenuItem: String, CaseIterable {
    case deviceSettings
    case connectionSync
    case bandAlarms
    case sleepPlanner
    case journal
    case trainingPlan
    case guidedBreathing
    case healthIntegrations
    case dataImportExport
    case backupRestore
    case healthActivitySettings
    case notifications
    case appPreferences
    case homeWidgets
    case appInformation
    case diagnosticsSupport

    var metadata: (title: String, icon: String, section: String) {
        switch self {
        case .deviceSettings: return ("Device Settings", "radiowaves.right", "DEVICE")
        case .connectionSync: return ("Connection & Sync", "arrow.triangle.2.circlepath", "DEVICE")
        case .bandAlarms: return ("Band Alarms", "alarm", "DEVICE")
        case .sleepPlanner: return ("Sleep Planner", "moon.stars", "HEALTH & ACTIVITY")
        case .journal: return ("Journal", "book.closed", "HEALTH & ACTIVITY")
        case .trainingPlan: return ("Training Plan", "calendar", "HEALTH & ACTIVITY")
        case .guidedBreathing: return ("Guided Breathing", "wind", "HEALTH & ACTIVITY")
        case .healthIntegrations: return ("Health Integrations", "link", "DATA & INTEGRATIONS")
        case .dataImportExport: return ("Data Import & Export", "externaldrive", "DATA & INTEGRATIONS")
        case .backupRestore: return ("Backup & Restore", "externaldrive.badge.timemachine", "DATA & INTEGRATIONS")
        case .healthActivitySettings: return ("Health & Activity Settings", "figure.run", "DATA & INTEGRATIONS")
        case .notifications: return ("Notifications", "bell", "PREFERENCES")
        case .appPreferences: return ("App Preferences", "gearshape", "PREFERENCES")
        case .homeWidgets: return ("Home Screen Widgets", "square.grid.2x2", "WIDGETS & LIVE ACTIVITIES")
        case .appInformation: return ("App Information", "info.circle", "ABOUT")
        case .diagnosticsSupport: return ("Diagnostics & Support", "wrench.and.screwdriver", "ABOUT")
        }
    }

    var accessibilityID: String { "more." + rawValue }
}

/// WHOOP/NOOP-inspired clean More tab hierarchy.
/// Consolidates all settings, integrations, device controls, diagnostics,
/// and local data management into four functional sections without repetitive
/// rows, placeholder alerts, or redundant shortcuts.
struct MoreView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(ProfileView.nameKey) private var displayName = ""
    @AppStorage(DailyLocalBackup.enabledKey) private var dailyBackupEnabled = false
    @AppStorage(DailyLocalBackup.intervalKey) private var backupIntervalSeconds = 86_400
    @AppStorage(DailyLocalBackup.retentionKey) private var backupRetentionDays = 30

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 20) {
                profileHeaderCard

                // SECTION 1: DEVICE
                MoreSettingsCard("DEVICE") {
                    NavigationLink { DeviceSettingsView() } label: {
                        moreRow(.deviceSettings, subtitle: deviceSettingsSubtitle)
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                    .accessibilityIdentifier(MoreMenuItem.deviceSettings.accessibilityID)

                    Divider().overlay(Color.appLine)

                    NavigationLink { ConnectionSyncView() } label: {
                        moreRow(.connectionSync, subtitle: store.band.status.title)
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink { BandAlarmsView() } label: {
                        moreRow(.bandAlarms, subtitle: bandAlarmsSubtitle)
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                }

                MoreSettingsCard("HEALTH & ACTIVITY") {
                    NavigationLink(value: Route.sleepCoach) {
                        moreRow(.sleepPlanner, subtitle: "Sleep need, bedtime & wake schedule")
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink(value: Route.journal) {
                        moreRow(.journal, subtitle: "Daily behaviors and notes")
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink { PlanView() } label: {
                        moreRow(.trainingPlan, subtitle: "Daily goals and schedule")
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink { StrapGuidedBreathingView() } label: {
                        moreRow(.guidedBreathing, subtitle: "Optional paced breathing session")
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                }

                MoreSettingsCard("DATA & INTEGRATIONS") {
                    NavigationLink { AppleHealthImportView() } label: {
                        moreRow(.healthIntegrations, subtitle: "Apple HealthKit sync & data exchange")
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink { DataManagementView() } label: {
                        moreRow(.dataImportExport, subtitle: "Backup, restore, WHOOP archive & captures")
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink { BackupRestoreSettingsView() } label: {
                        moreRow(.backupRestore, subtitle: "Schedule, retention, export & restore")
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                    Divider().overlay(Color.appLine)

                    NavigationLink { SettingsView() } label: {
                        moreRow(.healthActivitySettings, subtitle: "Profile, heart rate zones & sleep need")
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                }

                // SECTION 3: PREFERENCES
                MoreSettingsCard("PREFERENCES") {
                    NavigationLink { NotificationSettingsView() } label: {
                        moreRow(.notifications, subtitle: "Wake alarm & schedule alerts")
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink { AppPreferencesView() } label: {
                        moreRow(.appPreferences, subtitle: "Appearance, widget privacy & research")
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                }

                MoreSettingsCard("WIDGETS & LIVE ACTIVITIES") {
                    NavigationLink { StrapWidgetGuideView() } label: {
                        moreRow(.homeWidgets, subtitle: "Health, steps, workouts & Dynamic Island")
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                }

                // SECTION 4: ABOUT
                MoreSettingsCard("ABOUT") {
                    NavigationLink { AppInfoView() } label: {
                        moreRow(.appInformation, subtitle: "Version 1.0 (Build \(BuildInfo.revision))")
                    }
                    .buttonStyle(MoreSettingsPressStyle())

                    Divider().overlay(Color.appLine)

                    NavigationLink { DiagnosticsSupportView() } label: {
                        moreRow(.diagnosticsSupport, subtitle: "System diagnostics & documentation")
                    }
                    .buttonStyle(MoreSettingsPressStyle())
                }

                // FOOTER
                VStack(alignment: .leading, spacing: 4) {
                    Text("APP VERSION: 1.0 (BUILD \(BuildInfo.revision))")
                        .font(StrapTypography.body(11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.appMuted)
                    Text(StrapTypography.missingBundledFaces.isEmpty
                        ? "FONTS: PROXIMA NOVA · DIN PRO"
                        : "Font assets unavailable: " + StrapTypography.missingBundledFaces.joined(separator: ", "))
                        .font(StrapTypography.body(10))
                        .foregroundStyle(Color.appMuted.opacity(0.8))
                }
                .padding(.vertical, 14)
            }
        }
        .strapTabTypography("More")
    }

    private var deviceSettingsSubtitle: String {
        let name = store.band.bandName ?? store.band.preferredBandName ?? "STRAP Band"
        let connection = store.band.isConnected ? "Connected" : (store.band.preferredBandID == nil ? "Not Paired" : "Disconnected")
        let status = store.band.isConnected && store.band.batteryPercent != nil
            ? "\(connection) · \(store.band.batteryPercent.map { String($0) } ?? "")%"
            : connection
        if let serial = store.band.serialNumber, !serial.isEmpty {
            return "\(name) (SN: \(serial)) · \(status)"
        } else if let model = store.band.modelNumber, !model.isEmpty {
            return "\(name) (\(model)) · \(status)"
        } else {
            return "\(name) · \(status)"
        }
    }

    private var bandAlarmsSubtitle: String {
        guard WakeAlarm.isEnabled else { return "Alarm off" }
        guard let next = WakeAlarm.nextWakeDate() else { return "Alarm off" }
        let timeStr = DateFormatter.localizedString(from: next, dateStyle: .none, timeStyle: .short)
        if WakeAlarm.isBandConfirmed(for: next) {
            return "Armed on band · \(timeStr)"
        } else {
            return "Pending sync · \(timeStr)"
        }
    }

    private var profileHeaderCard: some View {
        NavigationLink(value: Route.profile) {
            HStack(spacing: 14) {
                ProfileAvatarView(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName.isEmpty ? "Your profile" : displayName)
                        .font(StrapTypography.body(18, weight: .bold))
                        .foregroundStyle(Color.appFG)
                        .lineLimit(1)
                    Text("Edit name and avatar")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(StrapTypography.body(15, weight: .bold))
                    .foregroundStyle(Color.appMuted)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient.appCard))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(MoreSettingsPressStyle())
        .accessibilityIdentifier("more.profile")
    }

    private func moreRow(_ item: MoreMenuItem, subtitle: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.metadata.icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.metadata.title)
                    .font(StrapTypography.body(13.5, weight: .semibold))
                    .foregroundStyle(Color.appFG)
                if let subtitle {
                    Text(subtitle)
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.appMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier(item.accessibilityID)
    }
}

 
/// Explicit backup controls, with no claim of guaranteed background execution.
private struct BackupRestoreSettingsView: View {
    @AppStorage(DailyLocalBackup.enabledKey) private var enabled = false
    @AppStorage(DailyLocalBackup.intervalKey) private var cadence = 86_400
    @AppStorage(DailyLocalBackup.retentionKey) private var retention = 30
    @State private var selectedFolder: URL?
    @State private var choosingFolder = false
    @State private var busy = false
    @State private var exported: URL?
    @State private var message: String?
    private let bookmarkKey = "strap.backup.destinationBookmark"

    var body: some View {
        Form {
            Section("Automatic backups") {
                Toggle("Enable automatic local backups", isOn: $enabled)
                Picker("Back Up When", selection: $cadence) {
                    Text("Hourly").tag(3_600)
                    Text("Every 6 hours").tag(21_600)
                    Text("Every 12 hours").tag(43_200)
                    Text("Daily").tag(86_400)
                    Text("Weekly").tag(604_800)
                    Text("Manual only").tag(0)
                }
                Picker("Keep Backups For", selection: $retention) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Until I delete them").tag(0)
                }
                Text("Scheduled backups are kept inside STRAP and run when the app is active. iOS does not guarantee exact background timing. The newest archive is protected.")
                    .font(.footnote)
            }
            Section("Files / iCloud Drive") {
                Button("Choose export folder") { choosingFolder = true }
                Text(selectedFolder?.lastPathComponent ?? "No external folder selected")
                    .font(.footnote)
                Text("Choosing a folder does not move or delete STRAP's existing automatic backups.")
                    .font(.footnote)
            }
            Section("Backup now") {
                Button(busy ? "Creating backup…" : "Create & export backup") {
                    Task { await createBackup() }
                }
                .disabled(busy)
                if let exported {
                    ShareLink("Share backup ZIP", item: exported)
                }
            }
            Section("Restore") {
                NavigationLink("View and restore backups") { DataManagementView() }
                Text("Restores use STRAP's existing validated restore workflow. Review the archive before restoring.")
                    .font(.footnote)
            }
            Section("Status") {
                if let date = UserDefaults.standard.object(forKey: DailyLocalBackup.lastSuccessKey) as? Date {
                    LabeledContent("Last automatic backup", value: date.formatted())
                } else {
                    Text("No automatic backup recorded yet")
                }
                if let error = UserDefaults.standard.string(forKey: DailyLocalBackup.lastErrorKey) {
                    Text(error).foregroundStyle(.red)
                }
                if let message { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Backup & Restore")
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
                    selectedFolder = url
                    message = "Export folder selected. Existing backups remain inside STRAP."
                } catch { message = error.localizedDescription }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .onAppear { restoreFolder() }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale), !stale {
            selectedFolder = url
        } else {
            selectedFolder = nil
            message = "Folder permission expired. Please choose the folder again."
        }
    }

    @MainActor private func createBackup() async {
        busy = true
        defer { busy = false }
        do {
            let fm = FileManager.default
            guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                  let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            let preferences = UserDefaults.standard.dictionaryRepresentation()
            let archive = try await Task.detached(priority: .userInitiated) {
                let archive = try PersistenceDiagnostics.write(
                    support: support, documents: documents,
                    preferences: preferences, fullBackup: true)
                let inspected = try StrapBackup.inspect(archive)
                try? FileManager.default.removeItem(at: inspected.folder)
                return archive
            }.value
            exported = archive
            if let folder = selectedFolder {
                let access = folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                guard access else {
                    message = "Backup created. Folder access unavailable; use Share backup ZIP."
                    return
                }
                let stamp = DateFormatter()
                stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let filename = "STRAP-backup-" + stamp.string(from: Date()) + ".zip"
                let target = folder.appendingPathComponent(filename)
                if fm.fileExists(atPath: target.path) {
                    message = "Backup created. A backup with this timestamp already exists; use Share backup ZIP or retry in a second."
                    return
                }
                try fm.copyItem(at: archive, to: target)
                // Validate the external copy itself, not only the sandbox source.
                // A failed Files-provider copy must never be reported as a usable backup.
                do {
                    let inspectedCopy = try StrapBackup.inspect(target)
                    try? fm.removeItem(at: inspectedCopy.folder)
                } catch {
                    try? fm.removeItem(at: target)
                    throw error
                }
                message = "Verified backup exported to " + folder.lastPathComponent
            } else {
                message = "Verified backup created. Use Share backup ZIP to save it to Files."
            }
        } catch { message = "Backup failed: " + error.localizedDescription }
    }
}


/// Discoverability for already shipped WidgetKit / ActivityKit features.
/// No unsupported widget or refresh behavior is promised.
struct StrapWidgetGuideView: View {
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {
                Panel {
                    SectionTitle("HOME SCREEN")
                    Text("Captured Steps")
                        .font(StrapTypography.body(16, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    Text("Touch and hold your iPhone Home Screen, choose Edit > Add Widget, search for STRAP, and select Captured Steps if available in your installed build.")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                    Hint("Displays band-recorded steps and last-sync status. iOS manages the widget refresh schedule.")
                    Divider()
                    Text("Daily Health")
                        .font(StrapTypography.body(16, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    Text("Enable Share health metrics with widgets in App Preferences, then add Daily Health from the widget gallery.")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                }
                Panel {
                    SectionTitle("LIVE ACTIVITIES")
                    Text("Workouts & captured steps")
                        .font(StrapTypography.body(16, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    Text("During a recorded workout, the Lock Screen and Dynamic Island can display available session metrics. A fresh band step-counter increase may start the captured-steps Live Activity when STRAP is running and iOS permits it.")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                    Hint("Live Activities depend on your iPhone settings, installed extension and available sensor data. They do not guarantee continuous background updates.")
                }
            }
        }
        .navigationTitle("Widgets & Live Activities")
        .navigationBarTitleDisplayMode(.inline)
    }
}
/// A local voluntary timer, not a measured stress treatment.
struct StrapGuidedBreathingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var durationMinutes = 2
    @State private var completed = false

    var body: some View {
        Screen {
            Panel {
                SectionTitle("GUIDED BREATHING")
                Picker("Duration", selection: $durationMinutes) {
                    Text("1 min").tag(1)
                    Text("2 min").tag(2)
                    Text("5 min").tag(5)
                }
                .pickerStyle(.segmented)
                .disabled(startedAt != nil)

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let elapsed = startedAt.map { max(0, Int(timeline.date.timeIntervalSince($0))) } ?? 0
                    let remaining = completed ? 0 : max(0, durationMinutes * 60 - elapsed)
                    let inhale = elapsed % 8 < 4
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color.appAccent.opacity(0.20))
                            .overlay(Circle().strokeBorder(Color.appAccent, lineWidth: 2))
                            .frame(width: 140, height: 140)
                            .scaleEffect(reduceMotion || startedAt == nil || remaining == 0 ? 1 : (inhale ? 1.15 : 0.85))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 3), value: inhale)
                            .accessibilityHidden(true)
                        Text(completed ? "Session complete" : startedAt == nil ? "Ready" : remaining == 0 ? "Complete" : inhale ? "Breathe in" : "Breathe out")
                            .font(StrapTypography.body(20, weight: .bold))
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            .font(StrapTypography.metric(28, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .onChange(of: remaining) { _, seconds in
                        if startedAt != nil && seconds == 0 { completed = true; startedAt = nil }
                    }
                }
                Button(startedAt == nil ? "Start session" : "Stop session") {
                    if startedAt == nil { completed = false; startedAt = Date() }
                    else { startedAt = nil; completed = false }
                }
                .buttonStyle(.borderedProminent)
                Hint("Breathe comfortably, without forcing or holding your breath. Stop if uncomfortable. This timer does not calculate or change your stress score.")
            }
        }
        .navigationTitle("Guided Breathing")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { startedAt = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { startedAt = nil }
        }
    }
}

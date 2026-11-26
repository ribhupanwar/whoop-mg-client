import SwiftUI
import UniformTypeIdentifiers

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
            VStack(alignment: .leading, spacing: 16) {
                profileHeaderCard

                // SECTION 1: DEVICE
                SectionTitle("DEVICE")
                Panel {
                    NavigationLink { DeviceSettingsView() } label: {
                        moreRow(
                            "Device Settings",
                            subtitle: deviceSettingsSubtitle,
                            icon: "radiowaves.right"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { ConnectionSyncView() } label: {
                        moreRow(
                            "Connection & Sync",
                            subtitle: store.band.status.title,
                            icon: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { BandAlarmsView() } label: {
                        moreRow(
                            "Band Alarms",
                            subtitle: bandAlarmsSubtitle,
                            icon: "alarm"
                        )
                    }
                    .buttonStyle(.plain)
                }

                SectionTitle("HEALTH & ACTIVITY")
                Panel {
                    NavigationLink(value: Route.sleepCoach) {
                        moreRow("Sleep Planner", subtitle: "Sleep need, bedtime & wake schedule", icon: "moon.stars")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink(value: Route.journal) {
                        moreRow("Journal", subtitle: "Daily behaviors and notes", icon: "book.closed")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { PlanView() } label: {
                        moreRow("Training Plan", subtitle: "Daily goals and schedule", icon: "calendar")
                    }
                    .buttonStyle(.plain)
                }

                SectionTitle("DATA & INTEGRATIONS")
                Panel {
                    NavigationLink { AppleHealthImportView() } label: {
                        moreRow(
                            "Health Integrations",
                            subtitle: "Apple HealthKit sync & data exchange",
                            icon: "link"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { DataManagementView() } label: {
                        moreRow(
                            "Data Import & Export",
                            subtitle: "Backup, restore, WHOOP archive & captures",
                            icon: "externaldrive"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { BackupRestoreSettingsView() } label: {
                        moreRow("Backup & Restore", subtitle: "Schedule, retention, export & restore", icon: "externaldrive.badge.timemachine")
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.appLine)

                    NavigationLink { SettingsView() } label: {
                        moreRow(
                            "Health & Activity Settings",
                            subtitle: "Profile, heart rate zones & sleep need",
                            icon: "figure.run"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // SECTION 3: PREFERENCES
                SectionTitle("PREFERENCES")
                Panel {
                    NavigationLink { NotificationSettingsView() } label: {
                        moreRow(
                            "Notifications",
                            subtitle: "Wake alarm & schedule alerts",
                            icon: "bell"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { AppPreferencesView() } label: {
                        moreRow(
                            "App Preferences",
                            subtitle: "Units, display & research features",
                            icon: "gearshape"
                        )
                    }
                    .buttonStyle(.plain)
                }

                SectionTitle("WIDGETS & LIVE ACTIVITIES")
                Panel {
                    NavigationLink { StrapWidgetGuideView() } label: {
                        moreRow("Home Screen Widgets", subtitle: "Captured steps, workout & Dynamic Island", icon: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)
                }

                // SECTION 4: ABOUT
                SectionTitle("ABOUT")
                Panel {
                    NavigationLink { AppInfoView() } label: {
                        moreRow(
                            "App Information",
                            subtitle: "Version 1.0 (Build \(BuildInfo.revision))",
                            icon: "info.circle"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { DiagnosticsSupportView() } label: {
                        moreRow(
                            "Diagnostics & Support",
                            subtitle: "System diagnostics & documentation",
                            icon: "wrench.and.screwdriver"
                        )
                    }
                    .buttonStyle(.plain)
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
        let status = store.band.isConnected ? "Connected" : (store.band.preferredBandID == nil ? "Not Paired" : "Disconnected")
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
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("more.profile")
    }

    private func moreRow(_ title: String, subtitle: String? = nil, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(Color.appAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(StrapTypography.body(13.5, weight: .semibold))
                    .foregroundStyle(Color.appFG)
                if let subtitle {
                    Text(subtitle)
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
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
private struct StrapWidgetGuideView: View {
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

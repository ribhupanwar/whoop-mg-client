import SwiftUI
import ZIPFoundation
import UniformTypeIdentifiers

/// Forensic reconstruction of WHOOP's 3-section More menu hierarchy:
/// 1. SHOP & GIFT (Gift STRAP, Partner Offers, Accessories, Refer a Friend)
/// 2. ACCOUNT & SETTINGS (My Account, Device Settings, Activity Settings, Journal, Integrations, Data Management & Export, Notifications, Privacy Settings)
/// 3. SUPPORT (Membership Services, Tutorials, About, Version & Build)
/// Preserves all local STRAP offline features, live band controls, and backup/restore capabilities.
struct MoreView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var preparingExport = false
    @State private var exportingBackup = false
    @State private var showRestoreImporter = false
    @State private var restorePreview: StrapBackup.Preview?
    @State private var restoreStatus: String?
    @State private var infoAlert: String?

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Text("More")
                    .font(StrapTypography.body(26, weight: .bold))
                    .foregroundStyle(Color.appFG)

                profileHeaderCard

                // SECTION 1: SHOP & GIFT
                SectionTitle("SHOP & GIFT")
                Panel {
                    Button {
                        infoAlert = "STRAP is a local-first, independent client. Hardware accessories and memberships are managed directly on-device or via community hardware."
                    } label: {
                        moreRow("GIFT STRAP", subtitle: "Gift health with memberships and accessories", icon: "gift")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    Button {
                        infoAlert = "Curated partner discounts and community integrations are coming soon."
                    } label: {
                        moreRow("PARTNER OFFERS", subtitle: "Explore curated perks for STRAP members", icon: "tag")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    Button {
                        infoAlert = "STRAP is compatible with standard 24mm WHOOP 4.0/5.0 bands and accessories."
                    } label: {
                        moreRow("STRAP ACCESSORIES", subtitle: "Shop bands and hardware accessories", icon: "bag")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    ShareLink(item: "Experience offline health tracking with STRAP: https://github.com/ribhupanwar/whoop-mg-client") {
                        moreRow("REFER A FRIEND", subtitle: "Share STRAP with friends and community", icon: "heart")
                    }
                    .buttonStyle(.plain)
                }

                // SECTION 2: ACCOUNT & SETTINGS
                SectionTitle("ACCOUNT & SETTINGS")
                Panel {
                    NavigationLink { SettingsView() } label: {
                        moreRow("MY ACCOUNT", subtitle: "Profile, age, height, weight, and baseline settings", icon: "person.crop.circle")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { SettingsView() } label: {
                        moreRow("DEVICE SETTINGS", subtitle: "\(store.band.bandName ?? "STRAP Band") · \(store.band.isConnected ? "Connected" : "Disconnected")", icon: "radiowaves.right")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { SettingsView() } label: {
                        moreRow("ACTIVITY SETTINGS", subtitle: "Auto-detection, HR zones, and GPS tracking", icon: "figure.run")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink(value: Route.journal) {
                        moreRow("JOURNAL", subtitle: "Customize daily journal questions & tracked behaviors", icon: "book.closed")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { AppleHealthImportView() } label: {
                        moreRow("INTEGRATIONS", subtitle: "Apple HealthKit & data exchange", icon: "link")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink(value: Route.sleepCoach) {
                        moreRow("SLEEP COACH", subtitle: "Target bedtime, wake alarm, and sleep debt", icon: "moon.stars")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    Button {
                        infoAlert = "STRAP operates completely on-device. Local notifications alert you when sleep need or recovery targets are ready."
                    } label: {
                        moreRow("NOTIFICATIONS", subtitle: "Sleep alerts, journal reminders, strain targets", icon: "bell")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    Button {
                        infoAlert = "STRAP never uploads health data to third-party servers. All biometrics remain private in local SQLite storage."
                    } label: {
                        moreRow("PRIVACY SETTINGS", subtitle: "Local-only storage & zero telemetry", icon: "lock.shield")
                    }
                    .buttonStyle(.plain)
                }

                // DATA MANAGEMENT & EXPORT (All working capabilities preserved)
                dataManagementPanel

                // SECTION 3: SUPPORT
                SectionTitle("SUPPORT")
                Panel {
                    Button {
                        infoAlert = "Need assistance? STRAP documentation and guides are bundled locally in the repository."
                    } label: {
                        moreRow("MEMBERSHIP SERVICES", subtitle: "Help guides, offline documentation & support", icon: "questionmark.circle")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    Button {
                        infoAlert = "Sensor placement: Wear the band 1 finger width above wrist bone. Snug fit ensures optimal optical R-R capture."
                    } label: {
                        moreRow("TUTORIALS", subtitle: "Band fit, sleep capture, and sensor placement guide", icon: "play.rectangle")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { SettingsView() } label: {
                        moreRow("ABOUT", subtitle: "Licenses, terms of use, and local architecture", icon: "info.circle")
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
        .alert("Notice", isPresented: Binding(get: { infoAlert != nil }, set: { if !$0 { infoAlert = nil } })) {
            Button("OK", role: .cancel) { infoAlert = nil }
        } message: {
            Text(infoAlert ?? "")
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
                    restoreStatus = "Backup validated and staged. Close and reopen STRAP to restore. Existing values take precedence; the original backup is retained."
                } catch { restoreStatus = error.localizedDescription }
                restorePreview = nil
            }
            Button("Cancel", role: .cancel) { restorePreview = nil }
        } message: { Text(restorePreview?.description ?? "") }
    }

    private var profileHeaderCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.appAccent)
                .frame(width: 58, height: 58)
                .background(Color.appAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("STRAP MEMBER")
                    .font(StrapTypography.body(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.appMuted)
                Text(store.band.bandName ?? store.band.preferredBandName ?? "Personal Dashboard")
                    .font(StrapTypography.body(18, weight: .bold))
                    .foregroundStyle(Color.appFG)
                    .lineLimit(1)
                Label(store.band.isConnected ? "Band connected" : "Band disconnected",
                      systemImage: store.band.isConnected ? "checkmark.circle.fill" : "circle.dotted")
                    .font(StrapTypography.body(11.5, weight: .medium))
                    .foregroundStyle(store.band.isConnected ? Color.appGood : Color.appMuted)
            }
            Spacer(minLength: 0)
            NavigationLink(value: Route.settings) {
                Image(systemName: "chevron.right")
                    .font(StrapTypography.body(15, weight: .bold))
                    .foregroundStyle(Color.appMuted)
            }
            .accessibilityLabel("Open profile and settings")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient.appCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appLine, lineWidth: 1))
    }

    private var dataManagementPanel: some View {
        Panel {
            SectionTitle("DATA MANAGEMENT & EXPORT")
            importActions
            exportActions
            restoreActions
            diagnosticsActions
        }
    }

    private var importActions: some View {
        Group {
            NavigationLink { SettingsView() } label: { moreRow("Import WHOOP Data", subtitle: "Import archive ZIP or CSV export", icon: "square.and.arrow.down") }
            NavigationLink { AppleHealthImportView() } label: { moreRow("Import Apple Health", subtitle: "Sync historical workouts & HR", icon: "heart.text.square") }
            NavigationLink { ImportHistoryView() } label: { moreRow("Import History and Diagnostics", subtitle: "Inspect past captures", icon: "list.bullet.rectangle") }
            NavigationLink { ManualActivityHistoryView() } label: { moreRow("Manual Activity History", subtitle: "Recover or revise logged sessions", icon: "clock.arrow.circlepath") }
        }
    }

    private var exportActions: some View {
        Group {
            Button { prepareExport(fullBackup: false) } label: {
                moreRow("Export Diagnostics & Records", subtitle: "Read-only summary and raw captures", icon: "square.and.arrow.up")
            }.disabled(preparingExport)
            Button { prepareExport(fullBackup: true) } label: {
                moreRow("Export Full STRAP Backup", subtitle: "Complete SQLite history and database", icon: "externaldrive.badge.checkmark")
            }.disabled(backupUnavailable)
            if let exportURL { ShareLink(item: exportURL) { moreRow("Save Export to Files or iCloud", subtitle: "Tap to share or archive", icon: "externaldrive") } }
            if let exportError { Text(exportError).font(StrapTypography.body(11)).foregroundStyle(Color.appWarn) }
        }
    }

    private var backupUnavailable: Bool {
        preparingExport || store.band.isConnected || store.band.isAnalyzingHistory || store.band.isSavingHistory
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

    private var restoreActions: some View {
        Group {
            Button { showRestoreImporter = true } label: { moreRow("Restore STRAP Backup", subtitle: "Stage validated backup for next launch", icon: "arrow.counterclockwise") }
            if let restoreStatus { Text(restoreStatus).font(StrapTypography.body(11)).foregroundStyle(Color.appAccent) }
        }
    }

    private var diagnosticsActions: some View {
        Group {
            NavigationLink { SleepRecoveryView() } label: { moreRow("Preview & Recover Saved Sleep", subtitle: "Replay sleep staging models", icon: "clock.arrow.circlepath") }
            NavigationLink { ImportHistoryView() } label: { moreRow("Export Individual JSON", subtitle: "Single-day capture inspect", icon: "doc.text") }
            NavigationLink(value: Route.sleepAnalysis) { moreRow("Export Individual Sleep CSV", subtitle: "30-second epoch export", icon: "moon.stars") }
            NavigationLink(value: Route.dataQuality) { moreRow("Data Quality & Diagnostics", subtitle: "BLE connection & packet integrity", icon: "waveform.path.ecg") }
            NavigationLink(value: Route.settings) { moreRow("Health Permissions & System Info", subtitle: "Sensors & background permissions", icon: "lock.shield") }
        }
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

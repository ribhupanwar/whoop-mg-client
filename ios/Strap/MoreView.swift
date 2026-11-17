import SwiftUI
import ZIPFoundation
import UniformTypeIdentifiers

/// Utility and account hub, not another copy of Home or Health metrics.
/// Inspired by the navigation structure of WHOOP and offline-first clients.
struct MoreView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var preparingExport = false
    @State private var showRestoreImporter = false
    @State private var restorePreview: StrapBackup.Preview?
    @State private var restoreStatus: String?

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {
                Text("More")
                    .font(StrapTypography.body(26, weight: .bold))
                    .foregroundStyle(Color.appFG)

                Panel {
                    SectionTitle("My band")
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.band.bandName ?? store.band.preferredBandName ?? "No saved band")
                                .font(StrapTypography.body(14, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text(store.band.status.title)
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        Circle()
                            .fill(store.band.isConnected ? Color.appGood : Color.appWarn)
                            .frame(width: 9, height: 9)
                    }
                    Button {
                        if store.band.isConnected {
                            store.band.readHistory()
                        } else {
                            store.connectBand()
                        }
                    } label: {
                        Label(store.band.isConnected ? "Sync now" : "Connect & sync",
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(StrapTypography.body(14, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    if let message = store.band.lastMessage {
                        Hint(message)
                    }
                    NavigationLink(value: Route.settings) {
                        moreRow("Band connection & sync settings", icon: "bluetooth")
                    }
                    .buttonStyle(.plain)
                }

                Panel {
                    SectionTitle("Your tools")
                    NavigationLink(value: Route.journal) {
                        moreRow("Journal", icon: "book.closed")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.sleepCoach) {
                        moreRow("Sleep coach", icon: "moon.stars")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.settings) {
                        moreRow("Profile & personal settings", icon: "person.crop.circle")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.settings) {
                        moreRow("Import WHOOP history", icon: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                }

                Panel {
                    SectionTitle("Data Management")
                    Text("Your band history is stored locally. HealthKit export is optional.")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                    Button {
                        // Never leave an older export shareable after a failed refresh:
                        // it could be mistaken for a current uninstall-safety backup.
                        exportURL = nil
                        exportError = nil
                        preparingExport = true
                        Task {
                            do {
                                let preferences = UserDefaults.standard.dictionaryRepresentation()
                                let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                exportURL = try await Task.detached(priority: .userInitiated) {
                                    try PersistenceDiagnostics.write(support: support, documents: documents, preferences: preferences)
                                }.value
                            } catch { exportError = error.localizedDescription }
                            preparingExport = false
                        }
                    } label: {
                        moreRow("Export persisted records & diagnostics", icon: "square.and.arrow.up")
                    }
                    .disabled(preparingExport)
                    Button {
                        exportURL = nil
                        exportError = nil
                        preparingExport = true
                        Task {
                            // Drain queued cache writes before snapshotting preferences.
                            await store.band.flushPersistedCaches()
                            let preferences = UserDefaults.standard.dictionaryRepresentation()
                            do {
                                let fm = FileManager.default
                                let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                exportURL = try await Task.detached {
                                    try PersistenceDiagnostics.write(support: support, documents: documents,
                                        preferences: preferences, fullBackup: true)
                                }.value
                            } catch { exportError = error.localizedDescription }
                            preparingExport = false
                        }
                    } label: { moreRow("Export Full STRAP Backup", icon: "externaldrive.badge.checkmark") }
                    .disabled(preparingExport || store.band.isConnected || store.band.isAnalyzingHistory || store.band.isSavingHistory)
                    Text("Disconnect the band and let analysis finish before a full backup, so all stores describe the same saved state.")
                        .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
                    Button { showRestoreImporter = true } label: {
                        moreRow("Restore STRAP Backup", icon: "arrow.counterclockwise")
                    }
                    if let restoreStatus { Text(restoreStatus).font(StrapTypography.body(11)) }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            moreRow("Save export to Files or iCloud", icon: "externaldrive")
                        }
                    }
                    if let exportError {
                        Text(exportError).font(StrapTypography.body(11)).foregroundStyle(Color.appWarn)
                    }
                    Text("Includes a read-only SQLite snapshot, sleep caches, corrections, raw captures and checksums. Contains private health records. Save outside this app. This is diagnostic evidence, not a full restorable backup.")
                        .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
                    NavigationLink {
                        SleepRecoveryView()
                    } label: {
                        moreRow("Preview & recover saved sleep", icon: "clock.arrow.circlepath")
                    }
                    NavigationLink(value: Route.dataQuality) {
                        moreRow("Data quality & diagnostics", icon: "waveform.path.ecg")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.settings) {
                        moreRow("Health permissions & app information", icon: "lock.shield")
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Build " + BuildInfo.revision)
                    Text(StrapTypography.missingBundledFaces.isEmpty
                        ? "Fonts: Proxima Nova · DIN Pro" : "Font assets unavailable: " + StrapTypography.missingBundledFaces.joined(separator: ", "))
                }
                .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted).padding(.vertical, 12)
            }
        }
        .strapTabTypography("More")
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

    private func moreRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Color.appAccent)
            Text(title)
                .font(StrapTypography.body(13, weight: .semibold))
                .foregroundStyle(Color.appFG)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

}

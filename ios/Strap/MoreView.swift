import SwiftUI
import ZIPFoundation

/// Utility and account hub, not another copy of Home or Health metrics.
/// Inspired by the navigation structure of WHOOP and offline-first clients.
struct MoreView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var preparingExport = false

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

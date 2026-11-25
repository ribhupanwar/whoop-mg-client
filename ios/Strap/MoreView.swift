import SwiftUI

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
                Text("More")
                    .font(StrapTypography.body(26, weight: .bold))
                    .foregroundStyle(Color.appFG)

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

                // SECTION 2: HEALTH & DATA
                SectionTitle("HEALTH & DATA")
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

                    Toggle(isOn: $dailyBackupEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Local Backups").font(StrapTypography.body(13.5, weight: .semibold))
                            Text("Saved in STRAP · older backups expire by age")
                                .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
                        }
                    }
                    .accessibilityIdentifier("more.dailyBackup")
                    if dailyBackupEnabled {
                        Divider().background(Color.appLine)
                        Picker("Back Up When", selection: $backupIntervalSeconds) {
                            Text("Every hour").tag(3_600)
                            Text("Every 6 hours").tag(21_600)
                            Text("Every 12 hours").tag(43_200)
                            Text("Daily").tag(86_400)
                            Text("Weekly").tag(604_800)
                            Text("Manual only").tag(0)
                        }
                        .accessibilityIdentifier("more.backupFrequency")
                        Divider().background(Color.appLine)
                        Picker("Keep Backups For", selection: $backupRetentionDays) {
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("Until I delete them").tag(0)
                        }
                        .accessibilityIdentifier("more.backupRetention")
                        Text("Backups are stored inside STRAP. They run when the app is active and due; iOS does not guarantee background timing. The newest backup is kept even after older copies expire.")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                    }
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

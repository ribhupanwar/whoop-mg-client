import SwiftUI

enum ProfileAvatar: String, CaseIterable, Identifiable {
    case person = "person.fill"
    case mountain = "mountain.2.fill"
    case moon = "moon.stars.fill"
    case bolt = "bolt.fill"

    static let storageKey = "strap.profile.avatar.v1"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .person: "Person"
        case .mountain: "Mountain"
        case .moon: "Moon"
        case .bolt: "Bolt"
        }
    }
}

struct ProfileAvatarView: View {
    @AppStorage(ProfileAvatar.storageKey) private var avatar: ProfileAvatar = .person
    let size: CGFloat

    var body: some View {
        Image(systemName: avatar.rawValue)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Color.appBG)
            .frame(width: size, height: size)
            .background(Color(hex: 0x72CED1), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct ProfileEditor: View {
    @AppStorage(ProfileView.nameKey) private var displayName = ""
    @AppStorage(ProfileAvatar.storageKey) private var avatar: ProfileAvatar = .person
    @State private var hasLoadedDraft = false
    @State private var draftName = ""
    @State private var draftAvatar: ProfileAvatar = .person
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $draftName)
                    .textContentType(.nickname)
                    .accessibilityIdentifier("profile.displayName")
                Picker("Avatar", selection: $draftAvatar) {
                    ForEach(ProfileAvatar.allCases) { option in
                        Label(option.title, systemImage: option.rawValue).tag(option)
                    }
                }
            } header: {
                Text("Personal profile")
            } footer: {
                Text("Your name and avatar are stored on this device.")
            }

            Section {
                NavigationLink("Health & Activity Settings") { SettingsView() }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    displayName = String(draftName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                    avatar = draftAvatar
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !hasLoadedDraft else { return }
            draftName = displayName
            draftAvatar = avatar
            hasLoadedDraft = true
        }
    }
}

struct ProfileView: View {
    static let nameKey = "strap.profile.displayName.v1"
    @AppStorage(ProfileView.nameKey) private var displayName = ""
    @EnvironmentObject private var store: AppStore
    @State private var period: Period = .all
    @State private var showAllActivities = false

    private enum Period: String, CaseIterable {
        case month = "1M"
        case quarter = "3M"
        case all = "All time"

        var months: Int? {
            switch self {
            case .month: 1
            case .quarter: 3
            case .all: nil
            }
        }
    }

    private var rangeStart: Date? {
        period.months.flatMap { Calendar.current.date(byAdding: .month, value: -$0, to: Date()) }
    }

    private var activityGroups: [(name: String, count: Int)] {
        let start = rangeStart?.timeIntervalSince1970 ?? -.infinity
        let sessions = store.detectedBandActivities.filter { Double($0.startUnix) >= start }
        return Dictionary(grouping: sessions, by: \.kind).map { ($0.key, $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var body: some View {
        let streak = AppOpenStreak.stored()
        Screen {
            VStack(alignment: .leading, spacing: 18) {
                header
                NavigationLink(value: Route.dayStreak) {
                    Panel {
                        HStack {
                            Label("Day Streak", systemImage: "flame.fill")
                            Spacer()
                            Text("\(streak.current) days")
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.dayStreak")

                NavigationLink(value: Route.healthspan) {
                    Panel {
                        HStack {
                            Label("Healthspan", systemImage: "waveform.path.ecg")
                            Spacer()
                            Text(store.fitnessSnapshot.map { String(format: "%.0f yrs fitness age", $0.years) } ?? "Building your baseline")
                                .foregroundStyle(Color.appMuted)
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)

                Picker("History range", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                highlights
                activitySummary
            }
            .foregroundStyle(Color.appFG)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileAvatarView(size: 82)
            HStack {
                Text(displayName.isEmpty ? "Your profile" : displayName)
                    .font(StrapTypography.body(27, weight: .bold))
                Spacer()
                NavigationLink(destination: ProfileEditor()) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("profile.edit")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x28494C), .appRaised], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: AppLayout.cardRadius)
        )
    }

    private var highlights: some View {
        let cutoff = rangeStart.map { JournalStore.dayKey(for: $0) }
        let days = store.band.days.filter { day in cutoff.map { day.dateKey >= $0 } ?? true }
        let sleep = days.compactMap(\.sleepPerformancePct).filter { $0.isFinite && (0...100).contains($0) }.max()
        let strain = days.compactMap(\.strain).filter { $0.isFinite && (0...21).contains($0) }.max()
        let rhr = days.compactMap(\.restingHR).filter { $0.isFinite && $0 > 0 }
        let hrv = days.compactMap(\.lnRMSSD).map { exp($0) }.filter { $0.isFinite && $0 > 0 }
        let longest = days.compactMap(\.reliableSleepHours).filter { $0.isFinite && $0 > 0 }.max()

        return Panel {
            SectionTitle("Data Highlights")
            HStack {
                highlight("Best sleep", value: sleep, scale: 100, color: .appSleep, suffix: "%")
                highlight("Max strain", value: strain, scale: 21, color: .appAccent, suffix: "")
            }
            .padding(.vertical, 10)
            stat("Lowest resting heart rate", value: formatted(rhr.min(), unit: "bpm"))
            stat("Highest resting heart rate", value: formatted(rhr.max(), unit: "bpm"))
            stat("Lowest HRV", value: formatted(hrv.min(), unit: "ms"))
            stat("Highest HRV", value: formatted(hrv.max(), unit: "ms"))
            stat("Longest sleep", value: longest.map(CoachFormat.duration) ?? "—")
        }
    }

    private func highlight(_ title: String, value: Double?, scale: Double, color: Color, suffix: String) -> some View {
        VStack {
            RingView(progress: value.map { $0 / scale }, color: color, size: 60,
                     centerText: value.map { scale == 21 ? String(format: "%.1f", $0) : String(format: "%.0f", $0) + suffix } ?? "—",
                     centerFont: 17)
            Text(title).font(StrapTypography.body(12, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ value: Double?, unit: String) -> String {
        value.map { String(format: "%.0f", $0) + " " + unit } ?? "—"
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Text(title)
                Spacer()
                Text(value).font(StrapTypography.metric(15, weight: .bold))
            }
            .padding(.vertical, 3)
        }
    }

    private var activitySummary: some View {
        let groups = activityGroups
        return Panel {
            SectionTitle("Activity Summary")
            Text(groups.isEmpty ? "No band-detected activities in this range." : "\(groups.reduce(0) { $0 + $1.count }) band-detected activities")
                .foregroundStyle(Color.appMuted)
            ForEach(Array(groups.prefix(showAllActivities ? groups.count : 3)), id: \.name) { group in
                stat(group.name.capitalized, value: group.count.formatted())
                ProgressView(value: Double(group.count), total: Double(groups.first?.count ?? 1))
                    .tint(Color.appAccent)
            }
            if groups.count > 3 {
                Button(showAllActivities ? "Show fewer" : "Show all") { showAllActivities.toggle() }
                    .padding(.top, 8)
            }
        }
    }
}

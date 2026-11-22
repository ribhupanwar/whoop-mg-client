import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    static var allCases: [AppTab] { [.home, .health, .humans, .more] }
    case home
    case health
    case humans
    case train
    case plan
    case more

    var label: String { rawValue.capitalized }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .health: return "heart.fill"
        case .humans: return "person.2.fill"
        case .train: return "dumbbell.fill"
        case .plan: return "calendar"
        case .more: return "line.3.horizontal"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .health: return "heart"
        case .humans: return "person.2"
        case .train: return "dumbbell"
        case .plan: return "calendar"
        case .more: return "line.3.horizontal"
        }
    }
}

/// Pushed screens. Journal, Sleep Coach, Sleep Analysis and Stress detail are
/// reached from Home (and Dashboard for Stress); Settings from the Home gear.
enum Route: Hashable {
    case health
    case gpsRun
    case recovery
    case strain
    case stress
    case journal
    case sleepCoach
    case sleepAnalysis
    case settings
    case profile
    case dayStreak
    case dataQuality
    case healthspan
    case metricHistory(DetailMetric)
}

private final class AppStoreOwner: ObservableObject {
    let store = AppStore()
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    // The navigation shell owns the store without subscribing to sensor changes.
    // Descendant screens observe it; tab selection never rebuilds every screen per packet.
    @StateObject private var owner = AppStoreOwner()
    private var store: AppStore { owner.store }
    @State private var tab: AppTab = .home
    @State private var showInsights = false
    @State private var showPlan = false
    @State private var showCoach = false
    @State private var homePath: [Route] = []

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(openPlan: { showPlan = true }, openInsights: { showInsights = true })
                    .strapDestinations()
            }
            .font(StrapTypography.body(15))
            .tabItem { Label(AppTab.home.label, systemImage: AppTab.home.icon) }
            .tag(AppTab.home)

            NavigationStack {
                HealthHubView()
                    .strapDestinations()
            }
            .font(StrapTypography.body(15))
            .tabItem { Label(AppTab.health.label, systemImage: AppTab.health.icon) }
            .tag(AppTab.health)

            NavigationStack {
                HumansView()
                    .strapDestinations()
            }
            .font(StrapTypography.body(15))
            .tabItem { Label(AppTab.humans.label, systemImage: AppTab.humans.icon) }
            .tag(AppTab.humans)

            NavigationStack {
                MoreView()
                    .strapDestinations()
            }
            .font(StrapTypography.body(15))
            .tabItem { Label(AppTab.more.label, systemImage: AppTab.more.icon) }
            .tag(AppTab.more)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { floatingNavigation }
        .sheet(isPresented: $showInsights) { DailyInsightsView().environmentObject(store) }
        .sheet(isPresented: $showPlan) { NavigationStack { PlanView().strapDestinations() }.environmentObject(store) }
        .sheet(isPresented: $showCoach) {
            StrapAICoachView()
                .environmentObject(store)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(25)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Count app launches even when returning to Health, Train, Plan or More.
                AppOpenDayTracker.recordOpen()
                store.band.resumeHistoryProcessing()
                store.band.autoConnectIfNeeded()
            }
            else { store.band.persistLiveRRArchive(force: true) }
        }
        .onAppear {
            AppOpenDayTracker.recordOpen()
            store.band.autoConnectIfNeeded()
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--preview-health-monitor") { homePath = [.health] }
            else if args.contains("--preview-recovery") { homePath = [.recovery] }
            else if args.contains("--preview-strain") { homePath = [.strain] }
            else if args.contains("--preview-sleep") { homePath = [.sleepAnalysis] }
            else if args.contains("--preview-healthspan") { homePath = [.healthspan] }
            else if args.contains("--preview-health") { tab = .health }
            else if args.contains("--preview-humans") { tab = .humans }
            else if args.contains("--preview-train") { showPlan = true }
            else if args.contains("--preview-plan") { showPlan = true }
            else if args.contains("--preview-more") { tab = .more }
            #endif
        }
        .tint(.appAccent)
        .font(StrapTypography.body(15))
        .environmentObject(store)
        .preferredColorScheme(.dark)
    }

    private var floatingNavigation: some View {
        // WHOOP-reference navigation: four tabs with a separate circular accessory.
        // The selected tab is legible without relying on glass blur alone.
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    let selected = tab == item
                    Button { tab = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: selected ? item.selectedIcon : item.icon)
                                .font(.system(size: 20, weight: selected ? .semibold : .regular))
                                .frame(height: 24)
                            Text(item.label)
                                .font(StrapTypography.body(10, weight: selected ? .bold : .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(selected ? Color.white : Color(hex: 0x6B7882))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)

                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityHint("Switch to \(item.label) tab")
                    .accessibilityIdentifier("tab.\(item.rawValue)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color(hex: 0x171E22).opacity(0.95), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Color(hex: 0x2D373E).opacity(0.50), lineWidth: 0.5))
            Button { showCoach = true } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color(hex: 0x6661B9).opacity(0.7), lineWidth: 1.4)
                        .frame(width: 43, height: 43)
                    Circle()
                        .trim(from: 0.05, to: 0.79)
                        .stroke(Color(hex: 0x7995F7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 43, height: 43)
                    WhoopWGlyph(color: .white)
                        .frame(width: 25, height: 25)
                }
                .frame(width: 54, height: 54)
                .background(Color(hex: 0x171E2B).opacity(0.98), in: Circle())
                .overlay(Circle().strokeBorder(Color(hex: 0x3E385A).opacity(0.8), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("STRAP AI Coach")
            .accessibilityHint("Open coaching chat and model settings")
            .accessibilityIdentifier("nav.aiCoach")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 5)
        .padding(.top, 5)
    }

}


/// Material-backed floating navigation compatible with the CI Xcode SDK.
/// Keep glass limited to the floating navigation: applying it to every scrolling
/// card increases offscreen compositing and harms scroll responsiveness.
private extension View {
    @ViewBuilder
    func strapLiquidGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.appLine, lineWidth: 1))
        }
    }

    @ViewBuilder
    func strapLiquidGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.appCustomizeEnd.opacity(0.8), lineWidth: 1))
        }
    }
}

extension View {
    /// Registers every pushed destination on each tab's navigation stack.
    func strapDestinations() -> some View {
        toolbar(.hidden, for: .tabBar)
            .toolbarBackground(Color.appCanvasTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
            switch route {
            case .health: HealthView()
            case .gpsRun: GPSRunView()
            case .recovery: MetricDetailView(recoveryMode: true)
            case .strain: MetricDetailView(recoveryMode: false)
            case .stress: StressView()
            case .journal: JournalView()
            case .sleepCoach: SleepCoachView()
            case .sleepAnalysis: SleepAnalysisView()
            case .settings: SettingsView()
            case .profile: ProfileView()
            case .dayStreak: DayStreakView()
            case .dataQuality: DataQualityView()
            case .healthspan: HealthspanView()
            case .metricHistory(let metric):
                MetricHistoryView(metric: metric)
            }
        }
    }
}

private struct DailyInsightsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Screen {
                Panel {
                    CardHead(title: "Your recorded day")
                    Text("Recovery " + DetailMetric.recovery.text(store.band.recovery.score))
                        .font(StrapTypography.body(22, weight: .bold)).padding(.bottom, 12)
                    Text("HRV " + (store.lastCapture?.hrv.rmssdMS.map { String(format: "%.0f ms", $0) } ?? "—"))
                        .font(StrapTypography.body(16)).padding(.bottom, 8)
                    Text("Resting HR " + (store.measuredRestingHR.map { String(format: "%.0f bpm", $0) } ?? "—"))
                        .font(StrapTypography.body(16))
                    Hint("These are your recorded measurements and local estimates. Open each detail screen to review dated inputs and data coverage.")
                }
                NavigationLink(value: Route.recovery) { Panel { Label("Recovery details", systemImage: "heart") } }.buttonStyle(.plain)
                NavigationLink(value: Route.strain) { Panel { Label("Strain details", systemImage: "chart.bar") } }.buttonStyle(.plain)
                NavigationLink(value: Route.journal) { Panel { Label("Your journal", systemImage: "book.closed") } }.buttonStyle(.plain)
            }.strapDestinations().navigationTitle("Daily insights").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}


// The reference navigation includes Humans, not Train/Plan. Community requires
// a real service integration; never display invented people or activity.
private struct HumansView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedSegment = 0

    // Use the same dated recovery calculation as Metric History. DayMetrics
    // retains measured inputs, not a stored `recovery` field.
    private var peakRecoveryText: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let values = store.band.days.compactMap { day -> Double? in
            guard let date = formatter.date(from: day.dateKey) else { return nil }
            return DatedRecovery.evaluate(day: day, priorDays: store.band.days, date: date,
                sleepNeedHours: store.settings.sleepNeedHours, calendar: calendar).result.score
        }
        guard let peak = values.max() else { return "—" }
        return "\(Int(peak.rounded()))%"
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Text("Humans")
                    .font(StrapTypography.body(26, weight: .bold))
                    .foregroundStyle(Color.appFG)

                Picker("Community Section", selection: $selectedSegment) {
                    Text("MY TEAMS").tag(0)
                    Text("LEADERBOARDS").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                if selectedSegment == 0 {
                    Panel {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.appAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.appAccent.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("PERSONAL BASELINE CLUB")
                                    .font(StrapTypography.body(13, weight: .bold))
                                    .foregroundStyle(Color.appFG)
                                Text("App-open streak: \(AppOpenStreak.stored().current) days")
                                    .font(StrapTypography.body(11))
                                    .foregroundStyle(Color.appMuted)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().background(Color.appLine)
                        Text("Cloud team synchronization requires WHOOP server credentials. Your personal records and streaks remain stored privately on-device.")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                            .lineSpacing(2)
                    }
                } else {
                    Panel {
                        SectionTitle("LOCAL RECORDS")
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PEAK STRAIN")
                                    .font(StrapTypography.body(10, weight: .bold))
                                    .foregroundStyle(Color.appMuted)
                                Text(store.band.days.compactMap(\.strain).max().map { String(format: "%.1f", $0) } ?? (store.isPreview ? String(format: "%.1f", SampleData.strain) : "—"))
                                    .font(StrapTypography.metric(22, weight: .bold))
                                    .foregroundStyle(Color.appAccent)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("RECOVERY SCORE")
                                    .font(StrapTypography.body(10, weight: .bold))
                                    .foregroundStyle(Color.appMuted)
                                Text(peakRecoveryText)
                                    .font(StrapTypography.metric(22, weight: .bold))
                                    .foregroundStyle(Color.appGood)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Panel {
                    SectionTitle("TRAINING & PLANNING")
                    NavigationLink { TrainView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .frame(width: 24)
                                .foregroundStyle(Color.appAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TRAINING & GPS RUN")
                                    .font(StrapTypography.body(13, weight: .bold))
                                    .foregroundStyle(Color.appFG)
                                Text("Live pace, route capture, and manual workout logger")
                                    .font(StrapTypography.body(11))
                                    .foregroundStyle(Color.appMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.appMuted)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.appLine)

                    NavigationLink { PlanView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .frame(width: 24)
                                .foregroundStyle(Color.appAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DAILY PLAN & SCHEDULES")
                                    .font(StrapTypography.body(13, weight: .bold))
                                    .foregroundStyle(Color.appFG)
                                Text("Sleep targets, bedtime schedules, and strain goals")
                                    .font(StrapTypography.body(11))
                                    .foregroundStyle(Color.appMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.appMuted)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .strapTabTypography("Humans")
    }
}

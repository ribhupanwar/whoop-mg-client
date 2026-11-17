import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home
    case health
    case train
    case plan
    case more

    var label: String { rawValue.capitalized }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .health: return "heart.fill"
        case .train: return "dumbbell.fill"
        case .plan: return "calendar"
        case .more: return "ellipsis.circle.fill"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .health: return "heart"
        case .train: return "dumbbell"
        case .plan: return "calendar"
        case .more: return "ellipsis.circle"
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
    @State private var homePath: [Route] = []

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(openPlan: { tab = .plan })
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
                TrainView()
                    .strapDestinations()
            }
            .font(StrapTypography.body(15))
            .tabItem { Label(AppTab.train.label, systemImage: AppTab.train.icon) }
            .tag(AppTab.train)

            NavigationStack {
                PlanView()
                    .strapDestinations()
            }
            .font(StrapTypography.body(15))
            .tabItem { Label(AppTab.plan.label, systemImage: AppTab.plan.icon) }
            .tag(AppTab.plan)

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Count app launches even when returning to Health, Train, Plan or More.
                AppOpenDayTracker.recordOpen()
                store.band.resumeHistoryProcessing()
            }
            else { store.band.persistLiveRRArchive(force: true) }
        }
        .onAppear {
            AppOpenDayTracker.recordOpen()
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--preview-health-monitor") { homePath = [.health] }
            else if args.contains("--preview-recovery") { homePath = [.recovery] }
            else if args.contains("--preview-strain") { homePath = [.strain] }
            else if args.contains("--preview-sleep") { homePath = [.sleepAnalysis] }
            else if args.contains("--preview-healthspan") { homePath = [.healthspan] }
            else if args.contains("--preview-health") { tab = .health }
            else if args.contains("--preview-train") { tab = .train }
            else if args.contains("--preview-plan") { tab = .plan }
            else if args.contains("--preview-more") { tab = .more }
            #endif
        }
        .tint(.appAccent)
        .font(StrapTypography.body(15))
        .environmentObject(store)
        .preferredColorScheme(.dark)
    }

    private var floatingNavigation: some View {
        // Keep all five destinations on a single stable bottom bar.
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
                                .font(StrapTypography.body(11, weight: selected ? .bold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(selected ? Color.appFG : Color.appMuted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.white.opacity(0.09))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.label)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityHint("Switch to \(item.label) tab")
                    .accessibilityIdentifier("tab.\(item.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.appBG.opacity(0.97), in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
            Button { showInsights = true } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.appFG)
                    .frame(width: 54, height: 54)
                    .background(Color.appBG.opacity(0.97), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Daily insights")
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

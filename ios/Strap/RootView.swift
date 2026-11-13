import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home
    case health
    case train
    case plan
    case more

    var label: String { rawValue.capitalized }

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
}

struct RootView: View {
    @StateObject private var store = AppStore()
    @State private var tab: AppTab = .home
    @State private var showInsights = false
    @State private var homePath: [Route] = []

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(openPlan: { tab = .plan })
                    .strapDestinations()
            }
            .tabItem { Label(AppTab.home.label, systemImage: AppTab.home.icon) }
            .tag(AppTab.home)

            NavigationStack {
                HealthHubView()
                    .strapDestinations()
            }
            .tabItem { Label(AppTab.health.label, systemImage: AppTab.health.icon) }
            .tag(AppTab.health)

            NavigationStack {
                TrainView()
                    .strapDestinations()
            }
            .tabItem { Label(AppTab.train.label, systemImage: AppTab.train.icon) }
            .tag(AppTab.train)

            NavigationStack {
                PlanView()
                    .strapDestinations()
            }
            .tabItem { Label(AppTab.plan.label, systemImage: AppTab.plan.icon) }
            .tag(AppTab.plan)

            NavigationStack {
                MoreView()
                    .strapDestinations()
            }
            .tabItem { Label(AppTab.more.label, systemImage: AppTab.more.icon) }
            .tag(AppTab.more)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { floatingNavigation }
        .sheet(isPresented: $showInsights) { DailyInsightsView().environmentObject(store) }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--preview-recovery") { homePath = [.recovery] }
            else if args.contains("--preview-strain") { homePath = [.strain] }
            else if args.contains("--preview-sleep") { homePath = [.sleepAnalysis] }
            else if args.contains("--preview-health") { tab = .health }
            else if args.contains("--preview-train") { tab = .train }
            else if args.contains("--preview-plan") { tab = .plan }
            else if args.contains("--preview-more") { tab = .more }
            #endif
        }
        .tint(.appAccent)
        .environmentObject(store)
        .preferredColorScheme(.dark)
    }

    private var floatingNavigation: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon).font(.system(size: 19, weight: .medium))
                            Text(item.label).font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(tab == item ? Color.appFG : Color.appMuted)
                        .frame(maxWidth: .infinity).frame(height: 52)
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .strapLiquidGlass(cornerRadius: 29)
            Button { showInsights = true } label: {
                Image(systemName: "waveform.path.ecg").font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.appFG).frame(width: 54, height: 54)
                    .strapLiquidGlassCircle()
            }.buttonStyle(.plain).accessibilityLabel("Daily insights")
        }
        .padding(.horizontal, 10).padding(.bottom, 4).padding(.top, 5)
    }

}


/// Material-backed floating navigation compatible with the CI Xcode SDK.
/// Keep glass limited to the floating navigation: applying it to every scrolling
/// card increases offscreen compositing and harms scroll responsiveness.
private extension View {
    @ViewBuilder
    func strapLiquidGlass(cornerRadius: CGFloat) -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.appLine, lineWidth: 1))
    }

    @ViewBuilder
    func strapLiquidGlassCircle() -> some View {
        self.background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.appCustomizeEnd.opacity(0.8), lineWidth: 1))
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
                        .font(.system(size: 22, weight: .semibold)).padding(.bottom, 12)
                    Text("HRV " + (store.lastCapture?.hrv.rmssdMS.map { String(format: "%.0f ms", $0) } ?? "—"))
                        .font(.system(size: 16)).padding(.bottom, 8)
                    Text("Resting HR " + (store.measuredRestingHR.map { String(format: "%.0f bpm", $0) } ?? "—"))
                        .font(.system(size: 16))
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

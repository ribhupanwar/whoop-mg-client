import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home
    case health
    case train
    case plan
    case dashboard

    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .home: return "house"
        case .health: return "heart"
        case .train: return "dumbbell"
        case .plan: return "calendar"
        case .dashboard: return "list.bullet"
        }
    }
}

/// Pushed screens. Journal, Sleep Coach, Sleep Analysis and Stress detail are
/// reached from Home (and Dashboard for Stress); Settings from the Home gear.
enum Route: Hashable {
    case health
    case stress
    case journal
    case sleepCoach
    case sleepAnalysis
    case settings
}

struct RootView: View {
    @StateObject private var store = AppStore()
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView(openPlan: { tab = .plan })
                    .strapDestinations()
            }
            .tabItem { Label(AppTab.home.label, systemImage: AppTab.home.icon) }
            .tag(AppTab.home)

            NavigationStack {
                HealthView()
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
                DashboardView()
                    .strapDestinations()
            }
            .tabItem { Label(AppTab.dashboard.label, systemImage: AppTab.dashboard.icon) }
            .tag(AppTab.dashboard)
        }
        .tint(.appAccent)
        .environmentObject(store)
        .preferredColorScheme(.dark)
    }
}

extension View {
    /// Registers every pushed destination on each tab's navigation stack.
    func strapDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .health: HealthView()
            case .stress: StressView()
            case .journal: JournalView()
            case .sleepCoach: SleepCoachView()
            case .sleepAnalysis: SleepAnalysisView()
            case .settings: SettingsView()
            }
        }
    }
}
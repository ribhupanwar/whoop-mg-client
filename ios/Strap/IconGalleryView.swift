import SwiftUI

/// Developer Icon Gallery & Visual Verification Contact Sheet.
///
/// Surfaces the complete iconography portfolio across all 137 supported sports,
/// biometric vitals, battery/charging states, device/BLE connection indicators,
/// and navigation elements to verify visual consistency without scraping proprietary WHOOP assets.
public struct IconGalleryView: View {
    @State private var selectedCategory: CategoryFilter = .all
    @State private var searchQuery: String = ""

    enum CategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case activities = "Activities"
        case metrics = "Metrics"
        case device = "Device & Battery"
        case navigation = "Navigation"
        case states = "Charts & States"

        var id: String { rawValue }
    }

    struct IconItem: Identifiable {
        let id = UUID()
        let name: String
        let symbol: String
        let category: CategoryFilter
        let note: String?
    }

    /// Performance-optimized static collection of all cataloged icons.
    /// Initialized once to eliminate repeated allocations and frame drops during search and filtering.
    static let allItems: [IconItem] = {
        var items: [IconItem] = []

        // Activities (all 137 kinds)
        for kind in ActivityKind.allCases {
            items.append(IconItem(
                name: kind.label,
                symbol: kind.icon,
                category: .activities,
                note: kind.rawValue
            ))
        }

        // Metrics
        items.append(IconItem(name: "Heart Rate", symbol: StrapIcon.Metric.heartRate, category: .metrics, note: "Live pulse"))
        items.append(IconItem(name: "Resting Heart Rate", symbol: StrapIcon.Metric.restingHeartRate, category: .metrics, note: "Nightly minimum"))
        items.append(IconItem(name: "HRV (rMSSD)", symbol: StrapIcon.Metric.hrv, category: .metrics, note: "SWS / slow wave sleep"))
        items.append(IconItem(name: "Respiratory Rate", symbol: StrapIcon.Metric.respiration, category: .metrics, note: "rpm"))
        items.append(IconItem(name: "Blood Oxygen (SpO₂)", symbol: StrapIcon.Metric.bloodOxygen, category: .metrics, note: "O₂ Saturation"))
        items.append(IconItem(name: "Skin Temperature", symbol: StrapIcon.Metric.skinTemp, category: .metrics, note: "°C delta"))
        items.append(IconItem(name: "Recovery Score", symbol: StrapIcon.Metric.recovery, category: .metrics, note: "0-100%"))
        items.append(IconItem(name: "Day Strain", symbol: StrapIcon.Metric.strain, category: .metrics, note: "0-21 Borg"))
        items.append(IconItem(name: "Day Stress", symbol: StrapIcon.Metric.stress, category: .metrics, note: "0-3 scale"))
        items.append(IconItem(name: "Sleep", symbol: StrapIcon.Metric.sleep, category: .metrics, note: "Primary sleep"))
        items.append(IconItem(name: "Nap", symbol: StrapIcon.Metric.nap, category: .metrics, note: "Daytime sleep"))
        items.append(IconItem(name: "Active Calories", symbol: StrapIcon.Metric.calories, category: .metrics, note: "kcal"))
        items.append(IconItem(name: "Steps", symbol: StrapIcon.Metric.steps, category: .metrics, note: "Total cadence"))

        // Device & Battery
        items.append(IconItem(name: "Battery (Full)", symbol: StrapIcon.Device.batteryFull, category: .device, note: "100%"))
        items.append(IconItem(name: "Battery (Half)", symbol: StrapIcon.Device.batteryHalf, category: .device, note: "50%"))
        items.append(IconItem(name: "Battery (Low)", symbol: StrapIcon.Device.batteryLow, category: .device, note: "<20% warning"))
        items.append(IconItem(name: "Battery (Charging)", symbol: StrapIcon.Device.batteryCharging, category: .device, note: "Pack attached"))
        items.append(IconItem(name: "Band Sensor", symbol: StrapIcon.Device.bandSensor, category: .device, note: "Screenless hardware"))
        items.append(IconItem(name: "BLE Connected", symbol: StrapIcon.Device.bluetoothConnected, category: .device, note: "Streaming"))
        items.append(IconItem(name: "BLE Searching", symbol: StrapIcon.Device.bluetoothConnecting, category: .device, note: "Discovery"))
        items.append(IconItem(name: "BLE Disconnected", symbol: StrapIcon.Device.bluetoothDisconnected, category: .device, note: "Idle"))
        items.append(IconItem(name: "Sync Catching Up", symbol: StrapIcon.Device.syncCatchingUp, category: .device, note: "Transferring history"))
        items.append(IconItem(name: "Sync Caught Up", symbol: StrapIcon.Device.syncCaughtUp, category: .device, note: "Up to date"))
        items.append(IconItem(name: "Haptic Alarm", symbol: StrapIcon.Device.hapticAlarm, category: .device, note: "Wake schedule"))
        items.append(IconItem(name: "Haptic Vibration", symbol: StrapIcon.Device.vibrationBuzz, category: .device, note: "Buzz test"))

        // Navigation
        items.append(IconItem(name: "Home Tab", symbol: StrapIcon.Navigation.home, category: .navigation, note: "Tab 1"))
        items.append(IconItem(name: "Health Tab", symbol: StrapIcon.Navigation.health, category: .navigation, note: "Tab 2"))
        items.append(IconItem(name: "Humans Tab", symbol: StrapIcon.Navigation.community, category: .navigation, note: "Tab 3"))
        items.append(IconItem(name: "More Tab", symbol: StrapIcon.Navigation.more, category: .navigation, note: "Tab 4"))
        items.append(IconItem(name: "Device Settings", symbol: StrapIcon.Navigation.settings, category: .navigation, note: "Config"))
        items.append(IconItem(name: "Chevron Right", symbol: StrapIcon.Navigation.chevronRight, category: .navigation, note: "Disclosure"))
        items.append(IconItem(name: "Close / Dismiss", symbol: StrapIcon.Navigation.close, category: .navigation, note: "Sheets"))
        items.append(IconItem(name: "Information", symbol: StrapIcon.Navigation.info, category: .navigation, note: "Help"))
        items.append(IconItem(name: "HealthKit Link", symbol: StrapIcon.Navigation.link, category: .navigation, note: "Integrations"))
        items.append(IconItem(name: "Diagnostics", symbol: StrapIcon.Navigation.diagnostics, category: .navigation, note: "Logs"))
        items.append(IconItem(name: "External Drive", symbol: StrapIcon.Navigation.externalDrive, category: .navigation, note: "Data export"))

        // Charts & States
        items.append(IconItem(name: "Trend Up", symbol: StrapIcon.State.trendUp, category: .states, note: "Positive slope"))
        items.append(IconItem(name: "Trend Down", symbol: StrapIcon.State.trendDown, category: .states, note: "Negative slope"))
        items.append(IconItem(name: "Trend Neutral", symbol: StrapIcon.State.trendNeutral, category: .states, note: "Stable"))
        items.append(IconItem(name: "Success Check", symbol: StrapIcon.State.checkmarkCircle, category: .states, note: "Validated"))
        items.append(IconItem(name: "Warning Alert", symbol: StrapIcon.State.warning, category: .states, note: "Attention"))
        items.append(IconItem(name: "Error / Reject", symbol: StrapIcon.State.error, category: .states, note: "Failed"))

        return items
    }()

    private var filteredItems: [IconItem] {
        Self.allItems.filter { item in
            let matchesCategory = selectedCategory == .all || item.category == selectedCategory
            let matchesSearch = searchQuery.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchQuery)
                || item.symbol.localizedCaseInsensitiveContains(searchQuery)
                || (item.note?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            return matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {
                Text("Icon Gallery & Contact Sheet")
                    .font(StrapTypography.body(22, weight: .bold))
                    .foregroundStyle(Color.appFG)

                Text("Visual contact sheet of \(Self.allItems.count) verified icons across activities, metrics, device states, and navigation.")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)

                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CategoryFilter.allCases) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                Text(cat.rawValue)
                                    .font(StrapTypography.body(11, weight: selectedCategory == cat ? .bold : .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == cat ? Color.appAccent : Color.appRaised)
                                    .foregroundStyle(selectedCategory == cat ? Color.black : Color.appFG)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.appMuted)
                    TextField("Search icons by name or SF Symbol…", text: $searchQuery)
                        .font(StrapTypography.body(13))
                        .foregroundStyle(Color.appFG)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.appMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 10))

                // Icon Grid
                let columns = [
                    GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredItems) { item in
                        VStack(spacing: 8) {
                            StrapIconView(item.symbol, size: 24, frameWidth: 32, color: Color.appFG)

                            Text(item.name)
                                .font(StrapTypography.body(11, weight: .semibold))
                                .foregroundStyle(Color.appFG)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)

                            Text(item.symbol)
                                .font(StrapTypography.body(9))
                                .foregroundStyle(Color.appMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let note = item.note {
                                Text(note)
                                    .font(StrapTypography.body(8))
                                    .foregroundStyle(Color.appAccent)
                                    .lineLimit(1)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 6)
            }
        }
        .navigationTitle("Icons")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct AppOpenStreak {
    let current: Int
    let best: Int
    let start: Date?
    let week: [(date: Date, opened: Bool)]

    init(keys: [String], today: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: today)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = Set(keys.compactMap { formatter.date(from: $0) }.filter { $0 <= today })
        var previous: Date?
        var runStart: Date?
        var length = 0
        var longest = 0
        for date in dates.sorted() {
            if let previous, calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: previous) ?? previous) {
                length += 1
            } else {
                runStart = date
                length = 1
            }
            previous = date
            longest = max(longest, length)
        }
        let active = previous.map { calendar.isDate($0, inSameDayAs: today) || calendar.isDate($0, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today) ?? today) } ?? false
        current = active ? length : 0
        best = longest
        start = active ? runStart : nil
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            .map { ($0, dates.contains($0)) }
    }

    static func stored() -> Self {
        Self(keys: UserDefaults.standard.stringArray(forKey: AppOpenDayTracker.key) ?? [])
    }
}

struct DayStreakView: View {
    private let milestones = [7, 14, 25, 50, 100, 200, 365]
    private var streak: AppOpenStreak { .stored() }

    var body: some View {
        let snapshot = streak
        let next = milestones.first { $0 > snapshot.current }
        Screen {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 94, weight: .regular))
                        .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .bottom, endPoint: .top))
                        .accessibilityHidden(true)
                    Text(snapshot.current.formatted()).font(StrapTypography.metric(64, weight: .bold))
                    Text("Day Streak").font(StrapTypography.body(26, weight: .bold))
                    Text("Consecutive days opening STRAP").foregroundStyle(Color.appMuted)
                }
                .frame(maxWidth: .infinity)
                HStack {
                    statistic("Streak started", value: snapshot.start?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                    Divider().frame(height: 36)
                    statistic("Best streak", value: snapshot.best.formatted())
                }
                Panel {
                    SectionTitle("This week")
                    HStack {
                        ForEach(snapshot.week, id: \.date) { day in
                            VStack(spacing: 8) {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(StrapTypography.body(11, weight: .bold))
                                Image(systemName: day.opened ? "flame.fill" : "circle.dashed")
                                    .foregroundStyle(day.opened ? Color.orange : Color.appMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(day.opened ? "Opened STRAP" : "No app open recorded")
                        }
                    }
                }
                if let next {
                    let previous = milestones.last { $0 <= snapshot.current } ?? 0
                    Panel {
                        SectionTitle("Next milestone · \(next) days")
                        ProgressView(value: Double(snapshot.current - previous), total: Double(next - previous))
                            .tint(.orange)
                        Text("\(next - snapshot.current) more consecutive days")
                            .foregroundStyle(Color.appMuted)
                    }
                }
                ShareLink(item: "My STRAP app-open streak: \(snapshot.current) days.") {
                    Label("Share Day Streak", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
            }
            .foregroundStyle(Color.appFG)
        }
        .navigationTitle("Day Streak")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statistic(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(StrapTypography.body(15, weight: .bold))
            Text(title).font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

/// Home — ports the approved mockup's structure and ordering.
/// Live mode: every unmeasured metric is "—"; waiting states say what is needed.
/// Demo mode: labelled sample values behind the persistent banner.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    let openPlan: () -> Void

    @State private var dayOffset = 0
    @State private var activityNote: String? = nil
    @State private var showCustomizeHint = false

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleBlock
                ringTrio
                insightCard
                monitorDuo
                myDayOutlook
                activitiesCard
                tonightCard
                journalCard
                dashboardSection
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(Color.appMuted, lineWidth: 1.5)
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appMuted)
            }
            .frame(width: 30, height: 30)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if dayOffset > -6 { dayOffset -= 1 }
                } label: {
                    Text("‹").font(.system(size: 16)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(dayOffset <= -6)
                .foregroundStyle(dayOffset <= -6 ? Color.appLine : Color.appFG)

                Text(dayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(Color.appFG)
                    .frame(minWidth: 62)

                Button {
                    if dayOffset < 0 { dayOffset += 1 }
                } label: {
                    Text("›").font(.system(size: 16)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(dayOffset >= 0)
                .foregroundStyle(dayOffset >= 0 ? Color.appLine : Color.appFG)
            }
            .padding(2)
            .background(Capsule().fill(Color.appRaised))

            Spacer()

            HStack(spacing: 5) {
                Text(demo ? "\(SampleData.batteryPercent)%" : "—")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                Image(systemName: "battery.100")
                    .font(.system(size: 14))
                    .foregroundStyle(demo ? Color.appGood : Color.appMuted)
            }

            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.appMuted)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.bottom, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Home")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.bottom, 12)
    }

    // MARK: Trio rings

    private var ringTrio: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                NavigationLink(value: Route.sleepAnalysis) {
                    trioItem(
                        label: "SLEEP ›",
                        text: demo ? "\(SampleData.sleepRingPercent)%" : "—",
                        progress: demo ? Double(SampleData.sleepRingPercent) / 100.0 : nil,
                        color: .appSleep
                    )
                }
                .buttonStyle(.plain)

                trioItem(
                    label: "RECOVERY ›",
                    text: demo ? "\(SampleData.recoveryRingPercent)%" : "—",
                    progress: demo ? Double(SampleData.recoveryRingPercent) / 100.0 : nil,
                    color: .appGood
                )
                trioItem(
                    label: "STRAIN ›",
                    text: demo ? String(format: "%.1f", SampleData.strain) : "—",
                    progress: demo ? SampleData.strain / 21.0 : nil,
                    color: .appAccent
                )
            }
            if !demo {
                Hint("Sleep needs an overnight capture; recovery needs a 7-day baseline; strain needs a measured max HR and a full day of wear.")
            }
        }
        .padding(.bottom, 12)
    }

    private func trioItem(label: String, text: String, progress: Double?, color: Color) -> some View {
        VStack(spacing: 8) {
            RingView(progress: progress, color: color, lineWidth: 8, size: 96, centerText: text)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Insight

    private var insightCard: some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(demo ? "Elevated HRV" : "Waiting for first capture")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text(demo
                         ? "Sample: your HRV is 6% above your usual, which signals strong recovery. A planned threshold run or heavy lift both fit today."
                         : "Strap reads your band locally. Sleep, recovery and HRV insights appear once overnight and daytime captures exist — nothing is estimated until then.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appGood)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
                    Text(demo ? "1" : "0")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
    }

    // MARK: Monitor duo

    private var monitorDuo: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.health) {
                tapCard(
                    title: "Health monitor",
                    pill: demo ? "✓" : "—",
                    pillColor: demo ? .appGood : .appWarn,
                    state: demo ? "WITHIN RANGE" : "WAITING",
                    stateColor: demo ? .appGood : .appWarn,
                    detail: demo ? "4/4 metrics · sample" : "needs a capture"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.stress) {
                tapCard(
                    title: "Stress monitor",
                    pill: demo ? String(format: "%.1f", SampleData.stressHome) : "—",
                    pillColor: demo ? .appAccent : .appMuted,
                    state: demo ? "LOW" : "NO BASELINE",
                    stateColor: demo ? .appAccent : .appWarn,
                    detail: demo ? "11:49 · sample" : "unlocks day 7"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 14)
    }

    private func tapCard(title: String, pill: String, pillColor: Color, state: String, stateColor: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
            }
            HStack(spacing: 7) {
                Text(pill)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.appLine, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(stateColor)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appSurface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.appLine, lineWidth: 1))
    }

    // MARK: My Day

    private var myDayOutlook: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Day")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.appFG)
            Button(action: openPlan) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appWarn)
                    Text("Your Daily Outlook")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color.appRaised, Color.appSurface], startPoint: .leading, endPoint: .trailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 11)
    }

    // MARK: Today's activities

    private var activitiesCard: some View {
        Panel {
            CardHead(title: "Today's activities", trailing: "›")

            NavigationLink(value: Route.sleepAnalysis) {
                HStack(spacing: 11) {
                    HStack(spacing: 7) {
                        Image(systemName: "moon.fill").font(.system(size: 12))
                        Text(demo ? SampleData.lastNightSleep : "—")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: 0x0D1219))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.appSleep))

                    Text("SLEEP")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text(demo ? "00:26\n07:33" : "wear it\ntonight")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            VStack(spacing: 8) {
                activityRow(icon: "figure.run", name: "Run", detail: demo ? "42 min · Z2" : "none detected")
                activityRow(icon: "figure.walk", name: "Walk", detail: demo ? "28 min · errands" : "none detected")
                activityRow(icon: "dumbbell.fill", name: "Gym workout", detail: demo ? "55 min · push" : "none detected")
                activityRow(icon: "clock", name: "Rest session", detail: "15 min · measured")
            }
            .padding(.bottom, 10)

            if !demo {
                Text("Run, walk and gym sessions auto-detect from the band's gait readout, step counter and heart rate — anything sustained 10+ minutes appears here after each capture, no start tap.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 9) {
                activityButton("+ ADD ACTIVITY") {
                    activityNote = "Logger design: cardio comes from the band automatically; lifting is entered as sets × reps × load. Not wired in this preview."
                }
                activityButton("START ACTIVITY") {
                    activityNote = "Live session design: streams heart rate and zones while you train. Not wired in this preview."
                }
            }

            if let activityNote {
                Hint(activityNote)
            }
        }
    }

    private func activityRow(icon: String, name: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.appMuted)
                .frame(width: 20)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appFG)
            Spacer()
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.appRaised))
    }

    private func activityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Color.appFG)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tonight's sleep

    private var tonightCard: some View {
        Panel {
            HStack {
                Text("TONIGHT'S SLEEP")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                Spacer()
                NavigationLink(value: Route.sleepCoach) {
                    Text("›")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appMuted)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.bottom, 6)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(demo ? SampleData.bedtime : "—")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("RECOMMENDED\nBEDTIME")
                        .font(.system(size: 9.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.appMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(Color.appLine).frame(width: 26, height: 1)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(demo ? SampleData.latestAlarm : "—")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("LATEST\nALARM")
                        .font(.system(size: 9.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Hint("Bedtime is worked back from your wake time, your sleep need and accumulated sleep debt. Open the coach to set a wake time; debt starts counting from tonight's capture.")
        }
    }

    // MARK: Journal

    private var journalCard: some View {
        Panel {
            HStack {
                Text("MY JOURNAL")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                Spacer()
                NavigationLink(value: Route.journal) {
                    Text("✎ FILL OUT")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.7)
                        .foregroundStyle(Color.appFG)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
                }
            }
            .padding(.bottom, 9)

            Text(journalStateText)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var journalStateText: String {
        if let entry = store.todayEntry() {
            return "Filled today · \(entry.yesCount) yes · mood \(entry.mood?.label ?? "—"). Edit any time."
        }
        if demo {
            return "Filled · 2 yes · mood Good · sample"
        }
        return "Not filled today — seven yes/no taps, a mood and a soreness pick."
    }

    // MARK: Inline dashboard

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My Dashboard")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Spacer()
                Button {
                    showCustomizeHint.toggle()
                } label: {
                    Text("CUSTOMIZE ✎")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.7)
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.appLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 10)

            if showCustomizeHint {
                Hint("Reordering and hiding rows is a design intent — not wired in this preview.")
                    .padding(.bottom, 10)
            }

            DashboardRows()
        }
    }

    // MARK: Day navigation helpers

    private var shiftedDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private var dayLabel: String {
        dayOffset == 0 ? "TODAY" : Self.shortDayFormatter.string(from: shiftedDate).uppercased()
    }

    private var subtitle: String {
        if dayOffset != 0 {
            return "No capture for this day yet"
        }
        let date = Self.longDateFormatter.string(from: shiftedDate)
        return demo ? "\(date) · design preview" : "\(date) · waiting for first capture"
    }

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter
    }()

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}
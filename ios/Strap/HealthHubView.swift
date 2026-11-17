import Foundation
import SwiftUI

/// Health tab landing — an overview hub, matching the approved layout.
/// The vitals detail (HealthView) is a drill-in opened only from a Health
/// Monitor card (here and on Home), never the tab itself.
/// Only metrics this client actually measures are shown; blood pressure is
/// absent, respiratory rate is an RSA estimate from R-R, and SpO₂ is the
/// band's labelled candidate rather than a clinical percentage.
struct HealthHubView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                healthspanHero
                advancedLabsCard
                healthMonitorCard
                bloodPressureCard
                stressMonitorCard
                Text("Healthspan, Health Monitor, and Stress Monitor are wellness estimates, not medical devices. Blood pressure is not measured by STRAP. Consult a doctor for health concerns.")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
            }
        }
        .strapTabTypography("Health")
    }

    // MARK: Health tab hero, modelled on the supplied reference

    private var healthspanHero: some View {
        VStack(spacing: 14) {
            HealthspanOrb(years: demo ? 25 : fitnessSnapshot?.years,
                          chronologicalYears: demo ? 30 : fitnessSnapshot?.chronologicalYears)
                .frame(height: 310)
                .padding(.top, 4)
            if !store.hasRecoveryBaseline {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(Color(hex: 0x70BDE4))
                    Text("Your fitness age is calibrating. As STRAP collects more resting and activity data, this estimate may stabilize.")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color(hex: 0x8FC6E7))
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color(hex: 0x20303F)))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PACE OF AGING")
                        .font(StrapTypography.body(12, weight: .bold))
                        .tracking(1)
                    Spacer()
                    Text("Awaiting validated trend")
                        .font(StrapTypography.body(10))
                        .foregroundStyle(Color.appMuted)
                }
                HStack {
                    Text("Slow")
                    Spacer()
                    Text("—")
                        .font(StrapTypography.metric(28, weight: .bold))
                    Spacer()
                    Text("Fast")
                }
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appMuted)
                HStack(spacing: 3) {
                    ForEach(0..<60, id: \.self) { _ in
                        Capsule().fill(Color.appMuted.opacity(0.28)).frame(height: 24)
                    }
                }
                HStack {
                    Text("-1.0x")
                    Spacer()
                    Text("1.0x")
                    Spacer()
                    Text("3.0x")
                }
                .font(StrapTypography.body(10))
                .foregroundStyle(Color.appMuted)
                NavigationLink { HealthspanView() } label: {
                    Text("GO TO HEALTHSPAN")
                        .font(StrapTypography.body(12, weight: .bold))
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            .padding(17)
            .background(RoundedRectangle(cornerRadius: 17).fill(LinearGradient.appCard))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 22)
    }

    private var advancedLabsCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 15) {
                Text("ADVANCED LABS")
                    .font(StrapTypography.body(12, weight: .bold))
                    .tracking(1)
                Text("Add laboratory results to understand your health alongside wearable trends.")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("NOT CONNECTED")
                    .font(StrapTypography.body(11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x72C4E8))
            }
            Spacer(minLength: 0)
            Image(systemName: "testtube.2")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color(hex: 0x4DE0B3))
                .frame(width: 88)
        }
        .padding(19)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 17).fill(
            LinearGradient(colors: [Color(hex: 0x292D30), Color(hex: 0x155B50)],
                           startPoint: .leading, endPoint: .trailing)))
        .padding(.bottom, 20)
    }

    private var bloodPressureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BLOOD PRESSURE INSIGHTS")
                    .font(StrapTypography.body(12, weight: .bold))
                    .tracking(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.appMuted)
            }
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TODAY'S ESTIMATE")
                        .font(StrapTypography.body(10, weight: .bold))
                        .foregroundStyle(Color.appMuted)
                    Text("— / —")
                        .font(StrapTypography.metric(30, weight: .bold))
                }
                Spacer()
                Image(systemName: "waveform.path")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color.appMuted)
            }
            .padding(.vertical, 12)
            Text("Unavailable · STRAP cannot estimate blood pressure from the verified band data.")
                .font(StrapTypography.body(10))
                .foregroundStyle(Color.appMuted)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient.appCard))
        .padding(.bottom, 18)
    }

    // MARK: Baseline progress

    private var baselinePanel: some View {
        Panel {
            CardHead(title: "Personal baseline",
                     trailing: demo ? "\(SampleData.baselineDaysDone)/\(SampleData.baselineDaysTarget)"
                                    : "\(min(store.recordedDayCount, SampleData.baselineDaysTarget))/\(SampleData.baselineDaysTarget)")
            MiniProgress(fraction: demo
                         ? Double(SampleData.baselineDaysDone) / Double(SampleData.baselineDaysTarget)
                         : min(Double(store.recordedDayCount) / Double(SampleData.baselineDaysTarget), 1.0))
            Hint(demo
                 ? "Sample: \(SampleData.baselineDaysTarget - SampleData.baselineDaysDone) more days to unlock your personal baseline and recovery score."
                 : store.hasRecoveryBaseline
                    ? "Baseline ready — recovery and stress compare today against your own \(store.recordedDayCount) recorded days."
                    : "\(max(0, SampleData.baselineDaysTarget - store.recordedDayCount)) more recorded days unlock recovery and stress. Each history capture adds its days.")
        }
    }

    // MARK: Independent fitness-age comparison

    private var fitnessSnapshot: FitnessAgeSnapshot? { store.fitnessSnapshot }

    private var fitnessAgePanel: some View {
        NavigationLink { HealthspanView() } label: {
            Panel {
                HStack {
                    Text("HEALTHSPAN").font(StrapTypography.body(12, weight: .bold)).tracking(1)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.appMuted)
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your fitness age").font(StrapTypography.body(20, weight: .semibold))
                        Text(demo ? "25 years · sample" : fitnessSnapshot.map { String(format: "%.0f years", $0.years) } ?? "Building your baseline")
                            .font(StrapTypography.body(14)).foregroundStyle(Color(hex: 0x55DDA6))
                        Text("See your age trend and what's moving it")
                            .font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                    }
                    Spacer(minLength: 0)
                    HealthspanOrb(years: demo ? 25 : fitnessSnapshot?.years)
                        .scaleEffect(0.6).frame(width: 100, height: 112)
                }.padding(.top, 12)
            }
        }.buttonStyle(.plain).foregroundStyle(Color.appFG)
    }

    // MARK: Health Monitor card (drill-in)

    private var healthMonitorCard: some View {
        NavigationLink(value: Route.health) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("HEALTH MONITOR")
                        .font(StrapTypography.body(12, weight: .bold)).tracking(1)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.appMuted)
                }
                HStack(alignment: .top, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 3)) { context in
                        let bpm = LiveHeartRateState.fresh(store.band.liveHeartRate, receivedAt: store.band.lastLiveHRAt,
                            connected: store.band.isConnected, now: context.date)
                        monitorCheck("HR", icon: "heart.fill", reading: HealthReading(vital: .rhr,
                            value: bpm.map(Double.init), status: bpm == nil ? .unavailable : .calibrating,
                            baselineDays: 0, reference: nil), status: bpm == nil ? "UNAVAILABLE" : "LIVE")
                    }
                    monitorCheck("RESP", icon: "lungs.fill", reading: store.healthMonitor[.respiration])
                    monitorCheck("SPO₂", icon: "drop", reading: store.healthMonitor[.oxygen])
                    monitorCheck("RHR", icon: "heart", reading: store.healthMonitor[.rhr])
                    monitorCheck("HRV", icon: "waveform.path.ecg", reading: store.healthMonitor[.hrv])
                }
                HStack(spacing: 10) {
                    Image(systemName: monitorCount == 4 ? "checkmark.square.fill" : "exclamationmark.square")
                        .foregroundStyle(monitorCount == 4 ? Color.appGood : Color.appMuted)
                    Text("\(monitorCount)/4 nightly metrics within personal range")
                        .font(StrapTypography.body(12, weight: .semibold))
                    Spacer()
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.appRaised))
                Text("Captured does not mean clinically validated or within range. SpO₂ is an unvalidated candidate; respiratory rate is an RSA estimate.")
                    .font(StrapTypography.body(10))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient.appCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 11)
    }

    private var respirationAvailable: Bool {
        demo || store.lastCapture?.respiration.breathsPerMinute != nil
    }
    private var oxygenAvailable: Bool {
        demo || store.lastCapture?.spo2.pct != nil
    }
    // Match the Health Monitor detail's validated overnight source. A daytime
    // capture must not light up the nightly HRV/RHR indicators.
    private var latestNightMetrics: DayMetrics? {
        guard let session = store.band.latestSleepSession else { return nil }
        let day = JournalStore.dayKey(
            for: Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1)))
        return store.band.days.first { $0.dateKey == day && $0.state == "sleep" }
    }
    private var restingAvailable: Bool {
        demo || latestNightMetrics?.restingHR != nil
    }
    private var hrvAvailable: Bool {
        guard !demo else { return true }
        guard let lnRMSSD = latestNightMetrics?.lnRMSSD else { return false }
        return lnRMSSD.isFinite
    }
    private var temperatureAvailable: Bool {
        demo || store.lastCapture?.skinTempMean != nil
    }
    private var monitorCount: Int {
        store.healthMonitor.readings.filter { $0.vital != .temperature && $0.verifiedWithinRange }.count
    }

    private func monitorCheck(_ label: String, icon: String, reading: HealthReading, status: String? = nil) -> some View {
        let present = demo || reading.value != nil
        let verified = !demo && reading.verifiedWithinRange
        return VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(present ? Color(hex: 0x163C4B) : Color.appRaised)
                    .frame(width: 43, height: 43)
                Circle()
                    .strokeBorder(present ? Color(hex: 0x59D5E8) : Color.appLine,
                                  lineWidth: 1)
                    .frame(width: 43, height: 43)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(present ? Color(hex: 0x7CE3F1) : Color.appMuted)
            }
            Text(label)
                .font(StrapTypography.body(10, weight: .bold))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(Color.appFG)
            Image(systemName: verified ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 17))
                .foregroundStyle(verified ? Color.appGood : Color.appMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(status ?? reading.statusText)")
    }

    // MARK: Stress Monitor card (drill-in)

    private var stressMonitorCard: some View {
        NavigationLink(value: Route.stress) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("STRESS MONITOR")
                        .font(StrapTypography.body(11, weight: .bold)).tracking(0.8)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text("›").font(StrapTypography.body(15)).foregroundStyle(Color.appMuted)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TODAY'S STRESS INDEX")
                            .font(StrapTypography.body(9.5)).tracking(0.6)
                            .foregroundStyle(Color.appMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(demo ? SampleData.highStressToday : stressText)
                                .font(StrapTypography.metric(26, weight: .bold))
                                .foregroundStyle(Color.appFG)
                            Text(demo ? "hrs" : "SD")
                                .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
                        }
                    }
                    Spacer()
                    if demo {
                        LineChart(values: SampleData.stressMiniSeries, color: .appGood,
                                  minY: 0, maxY: 3, height: 60)
                            .frame(width: 150)
                    }
                }
                if !demo {
                    Text(stressDetail)
                        .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient.appCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 11)
    }

    private var stressText: String {
        guard let index = store.band.stress.index else { return "—" }
        return String(format: "%.1f", index)
    }

    private var stressDetail: String {
        if let reason = store.band.stress.reason { return reason }
        return "\(store.band.stress.band) — SD of lnRMSSD below your awake norm."
    }

    // MARK: Honest limitations

    private var notMeasuredPanel: some View {
        Panel {
            CardHead(title: "Not measured by this client")
            Text("Blood pressure is not produced here. Respiratory rate is an RSA estimate from R-R timing. SpO₂ and skin temperature remain unvalidated sensor candidates. Temperature deviation needs seven qualifying prior nights; personal ranges are observed readings, not clinical limits.")
                .font(StrapTypography.body(11.5))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

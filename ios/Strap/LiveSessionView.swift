import SwiftUI

/// Live session: measured heart rate from the standard 0x2A37 profile, Karvonen
/// zone time and R-R-derived HRV, saved as a measured record on stop.
struct LiveSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let zoneColors: [Color] = [.appMuted, .appGood, .appAccent, .appWarn, .appHigh]

    var body: some View {
        NavigationStack {
            Screen {
                if store.band.isConnected {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 0) {
                            heartPanel(now: context.date)
                            zonesPanel
                            hrvPanel
                            Hint("Zones use Karvonen reserve with your resting HR override, or the rest measured in the last capture. Stop & save keeps the measured record; swiping this sheet down discards it.")
                        }
                    }
                } else {
                    Panel {
                        SectionTitle("Not connected")
                        Text("Connect to the strap to stream live heart rate. The band must not be paired in iOS Settings first.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appMuted)
                            .lineSpacing(3)
                            .padding(.bottom, 10)
                        Button {
                            store.connectBand()
                        } label: {
                            Text("CONNECT")
                                .font(.system(size: 11, weight: .medium))
                                .tracking(0.5)
                                .foregroundStyle(Color.appFG)
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appLine, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Hint(store.band.status.title)
                    }
                }
            }
            .navigationTitle("Live session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        store.band.endLiveSession()
                        dismiss()
                    }
                    .foregroundStyle(Color.appMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stop & save") { stopAndSave() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appAccent)
                        .disabled(!store.band.isLiveSession || elapsedSeconds(now: Date()) < 10)
                }
            }
        }
        .onAppear {
            if store.band.isConnected && !store.band.isLiveSession {
                store.band.startLiveSession()
            }
        }
        .onDisappear {
            if store.band.isLiveSession {
                store.band.endLiveSession()
            }
        }
    }

    // MARK: Panels

    private func heartPanel(now: Date) -> some View {
        Panel {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.band.liveHeartRate.map { "\($0)" } ?? "—")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Text("bpm")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                Spacer()
                Text(clock(elapsedSeconds(now: now)))
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.appMuted)
            }
            Text("LIVE HEART RATE · STANDARD 0x2A37")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(Color.appMuted)
                .padding(.top, 2)
            if let message = store.band.lastMessage {
                Hint(message)
            }
        }
    }

    private var zonesPanel: some View {
        Panel {
            SectionTitle("Zone time")
            let zones = store.liveZones
            let buckets = LiveZones.seconds(samples: store.band.liveSamples, zones: zones)
            let total = buckets.reduce(0, +)
            if let zones, total > 0 {
                SplitBar(segments: zip(zones, buckets).map { pair in
                    SplitBar.Segment(
                        fraction: Double(pair.1) / Double(total),
                        color: zoneColors[min(max(pair.0.index - 1, 0), zoneColors.count - 1)]
                    )
                })
                .padding(.bottom, 10)
                ForEach(Array(zip(zones, buckets).enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(zoneColors[min(pair.0.index - 1, zoneColors.count - 1)])
                            .frame(width: 8, height: 8)
                        Text(pair.0.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.appFG)
                        Text(pair.0.use)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appMuted)
                        Spacer()
                        Text(clock(pair.1))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Color.appMuted)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("—")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Text(zones == nil
                     ? "Set a resting HR override in Settings, or take one history capture, before zones can be computed."
                     : "Zone time appears once heart rate is streaming.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private var hrvPanel: some View {
        Panel {
            SectionTitle("Beat-to-beat")
            let hrv = store.band.currentLiveHRV
            HStack(spacing: 18) {
                stat(label: "R-R BEATS", value: hrv.beats > 0 ? "\(hrv.beats)" : "—")
                stat(label: "RMSSD", value: hrv.rmssdMS.map { String(format: "%.0f ms", $0) } ?? "—")
                stat(label: "MEAN R-R", value: hrv.meanRRMS.map { String(format: "%.0f ms", $0) } ?? "—")
            }
            Hint("R-R beats arrive inside the standard heart-rate notification. HRV needs a steady 30+ seconds to mean anything.")
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.appMuted)
        }
    }

    // MARK: Helpers

    private func elapsedSeconds(now: Date) -> Int {
        guard let start = store.band.sessionStartedUnix else { return 0 }
        return max(0, Int(now.timeIntervalSince1970) - start)
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func stopAndSave() {
        let samples = store.band.liveSamples
        let zones = LiveZones.seconds(samples: samples, zones: store.liveZones)
        guard let result = store.band.endLiveSession() else {
            dismiss()
            return
        }
        let record = LiveActivityRecord(
            dateKey: JournalStore.dayKey(
                for: Date(timeIntervalSince1970: TimeInterval(result.startedUnix))
            ),
            startedUnix: result.startedUnix,
            endedUnix: result.endedUnix,
            meanHR: result.meanHR,
            maxHR: result.maxHeartRate,
            beats: result.beats,
            hrv: result.hrv,
            zoneSeconds: zones
        )
        store.addLiveSession(record)
        dismiss()
    }
}

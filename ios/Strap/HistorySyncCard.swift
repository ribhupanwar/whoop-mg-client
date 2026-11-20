import SwiftUI

/// Sync and analysis are separate stages: a radio transfer is not a finished score.
struct HistorySyncCard: View {
    @EnvironmentObject private var store: AppStore
    private var band: BandLink { store.band }
    private var visible: Bool {
        !store.isPreview && (band.status == .authenticating || band.status == .draining || band.isSavingHistory
                            || band.isAnalyzingHistory || band.historySyncError != nil)
    }
    var body: some View {
        if visible {
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        if band.historySyncError != nil {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.orange)
                        } else { ProgressView().tint(Color.appSleep) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(StrapTypography.body(14, weight: .bold))
                            Text(detail(now: clock.date))
                                .font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    if let fraction = band.historyProgress?.fraction, band.historySyncError == nil {
                        ProgressView(value: fraction).tint(Color.appSleep)
                    }
                    if band.historySyncError != nil {
                        Button("Retry sync") { band.retryHistorySync() }
                            .font(StrapTypography.body(13, weight: .bold)).foregroundStyle(Color.appAccent)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(Color.appRaised))
                .padding(.bottom, AppLayout.cardSpacing)
                .accessibilityElement(children: .contain)
            }
        }
    }
    private var title: String {
        if band.historySyncError != nil { return "History needs attention" }
        if band.status == .authenticating { return "Waiting for WHOOP handshake" }
        if let progress = band.historyProgress { return progress.title }
        return band.isSavingHistory ? "Saving band history" : "Syncing band history"
    }
    private func detail(now: Date) -> String {
        if let error = band.historySyncError { return error }
        if band.status == .authenticating { return "Bluetooth connected; waiting for band acknowledgement before requesting history." }
        if let progress = band.historyProgress { return progress.detail(now: now) }
        if band.status == .draining {
            return "\(band.drainStats.frames) frames · \(band.drainStats.samples) records · \(band.drainStats.acks) chunks acknowledged"
        }
        return "Your results update here automatically."
    }
}

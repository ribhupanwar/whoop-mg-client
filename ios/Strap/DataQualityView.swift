import SwiftUI

struct DataQualityView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Screen {
            Panel {
                SectionTitle("Capture diagnostics")
                Text("These indicators describe the most recent analyzed capture, not the entire day.")
                    .font(.system(size: 12)).foregroundStyle(Color.appMuted)
                ForEach(DataQuality.inspect(store.lastCapture)) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(item.total == 0 ? "No data" : "\(item.available)/\(item.total)")
                                .font(.system(size: 12)).foregroundStyle(Color.appMuted)
                        }
                        Text(item.reason).font(.system(size: 11)).foregroundStyle(Color.appMuted)
                    }
                    .padding(.vertical, 8)
                }
            }
            Panel {
                SectionTitle("Connection")
                Text(store.band.status.title).foregroundStyle(Color.appFG)
                if let date = store.band.lastHistorySyncAt {
                    Text("Last history sync: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12)).foregroundStyle(Color.appMuted)
                }
                Text("A missing metric is not zero. Capture gaps and device reconnection may require a fresh history sync.")
                    .font(.system(size: 12)).foregroundStyle(Color.appMuted)
            }
        }
        .navigationTitle("Data quality")
        .navigationBarTitleDisplayMode(.inline)
    }
}

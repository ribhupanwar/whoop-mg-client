import SwiftUI

/// Utility and account hub, not another copy of Home or Health metrics.
/// Inspired by the navigation structure of WHOOP and offline-first clients.
struct MoreView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {
                Text("More")
                    .font(StrapTypography.body(26, weight: .semibold))
                    .foregroundStyle(Color.appFG)

                Panel {
                    SectionTitle("My band")
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.band.bandName ?? store.band.preferredBandName ?? "No saved band")
                                .font(StrapTypography.body(14, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text(store.band.status.title)
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        Circle()
                            .fill(store.band.isConnected ? Color.appGood : Color.appWarn)
                            .frame(width: 9, height: 9)
                    }
                    Button {
                        if store.band.isConnected {
                            store.band.readHistory()
                        } else {
                            store.connectBand()
                        }
                    } label: {
                        Label(store.band.isConnected ? "Sync now" : "Connect & sync",
                              systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    if let message = store.band.lastMessage {
                        Hint(message)
                    }
                    NavigationLink(value: Route.settings) {
                        moreRow("Band connection & sync settings", icon: "bluetooth")
                    }
                    .buttonStyle(.plain)
                }

                Panel {
                    SectionTitle("Your tools")
                    NavigationLink(value: Route.journal) {
                        moreRow("Journal", icon: "book.closed")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.sleepCoach) {
                        moreRow("Sleep coach", icon: "moon.stars")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.settings) {
                        moreRow("Profile & personal settings", icon: "person.crop.circle")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.settings) {
                        moreRow("Import WHOOP history", icon: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                }

                Panel {
                    SectionTitle("Privacy & data")
                    Text("Your band history is stored locally. HealthKit export is optional.")
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                    NavigationLink(value: Route.settings) {
                        moreRow("Health permissions & app information", icon: "lock.shield")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moreRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Color.appAccent)
            Text(title)
                .font(StrapTypography.body(13))
                .foregroundStyle(Color.appFG)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

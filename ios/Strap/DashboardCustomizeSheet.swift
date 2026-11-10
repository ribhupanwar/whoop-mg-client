import SwiftUI

/// Arranges the shared Home/Dashboard stack: move a row, hide it, or reset.
///
/// Hidden rows stay in the list at their saved position, so unhiding restores
/// where the row was rather than appending it — the same behaviour NOOP and
/// OpenStrap use for their reorderable dashboards. Movement is one slot per tap,
/// which needs no drag mode and keeps every step undoable.
struct DashboardCustomizeSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.settings.dashboardOrder.enumerated()), id: \.element) { index, row in
                        rowCard(row, index: index)
                    }
                    Hint("Hidden rows keep their position, so switching one back on restores where it was. Order and visibility are saved on this device and apply to both Home and Dashboard.")
                        .padding(.top, 4)
                    Button {
                        store.resetDashboardLayout()
                    } label: {
                        Text("RESET TO DEFAULT ORDER")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.7)
                            .foregroundStyle(Color.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 11).fill(Color.appRaised))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.appLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
                .padding(16)
            }
            .background(Color.appBG.ignoresSafeArea())
            .navigationTitle("Arrange dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rowCard(_ row: DashboardRow, index: Int) -> some View {
        let hidden = store.isDashboardRowHidden(row)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(hidden ? Color.appMuted : Color.appFG)
                Text(hidden ? "Hidden" : "Shown")
                    .font(.system(size: 10.5))
                    .foregroundStyle(hidden ? Color.appWarn : Color.appGood)
            }
            Spacer()
            HStack(spacing: 6) {
                stepButton(row: row, offset: -1, system: "chevron.up", disabled: index == 0)
                stepButton(row: row, offset: 1, system: "chevron.down",
                           disabled: index == store.settings.dashboardOrder.count - 1)
                Button {
                    store.setDashboardRow(row, hidden: !hidden)
                } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(hidden ? Color.appWarn : Color.appAccent)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.appLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hidden ? "Show \(row.title)" : "Hide \(row.title)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appSurface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))
        .padding(.bottom, 8)
    }

    private func stepButton(row: DashboardRow, offset: Int, system: String, disabled: Bool) -> some View {
        Button {
            store.moveDashboardRow(row, by: offset)
        } label: {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(disabled ? Color.appLine : Color.appFG)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(offset < 0 ? "Move \(row.title) up" : "Move \(row.title) down")
    }
}

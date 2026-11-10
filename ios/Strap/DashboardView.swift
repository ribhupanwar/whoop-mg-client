import SwiftUI

/// Dashboard tab — the exact same metric rows as Home's My Dashboard
/// (shared component), plus the customize hint and baseline progress.
struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCustomizeHint = false

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
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
                .padding(.bottom, 10)

                if showCustomizeHint {
                    Hint("Reordering and hiding rows is a design intent — not wired in this preview.")
                        .padding(.bottom, 10)
                }

                DashboardRows()
                baselinePanel
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var baselinePanel: some View {
        Panel {
            SectionTitle("Baseline progress")
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    Text("\(day)")
                        .font(.system(size: 11))
                        .foregroundStyle(day == 1 && demo ? Color(hex: 0x08130C) : Color.appMuted)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9).fill(day == 1 && demo ? Color.appGood : Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(day == 1 && demo ? Color.appGood : Color.appLine, lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Hint("The small number under each metric is your comparison value. It stays absent until there is history to compare against — that is the whole point of a personal baseline.")
        }
        .padding(.top, 12)
    }
}
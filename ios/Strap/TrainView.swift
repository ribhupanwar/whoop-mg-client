import SwiftUI

/// Train — Karvonen HR-reserve zone calculator with live recompute.
/// Defaults: resting HR 72 (or the Settings override), max HR from the
/// Settings override or the age estimate 208 − 0.7 × age.
struct TrainView: View {
    @EnvironmentObject private var store: AppStore

    @State private var rhrText = ""
    @State private var maxText = ""
    @State private var seeded = false

    private let zoneColors: [Color] = [.appMuted, .appGood, .appAccent, .appWarn, .appHigh]

    private var restingHR: Double? { Double(rhrText) }
    private var maxHR: Double? { Double(maxText) }

    private var zones: [HRZone]? {
        guard let rhr = restingHR, let maxHR = maxHR else { return nil }
        return Karvonen.zones(restingHR: rhr, maxHR: maxHR)
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                inputsPanel
                zonesPanel
                ctaBox
                gymPanel
            }
        }
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { seedIfNeeded() }
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        let rhr = store.settings.restingHROverride ?? 72.0
        let maxHR = store.settings.maxHROverride ?? Karvonen.agePredictedMaxHR(age: store.settings.age)
        rhrText = String(format: "%.0f", rhr)
        maxText = String(format: "%.0f", maxHR)
        seeded = true
    }

    private var inputsPanel: some View {
        Panel {
            SectionTitle("Your numbers")
            fieldRow(label: "Resting HR (bpm)") {
                TextField("72", text: $rhrText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appFG)
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
            }
            fieldRow(label: "Max HR (bpm)") {
                TextField("190", text: $maxText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appFG)
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
            }
            Hint("Max HR defaults to the age estimate 208 − 0.7 × age (age \(store.settings.age) → \(String(format: "%.0f", Karvonen.agePredictedMaxHR(age: store.settings.age))) bpm). An age formula is only a population guess — replace it with a max you have actually seen in a hard session. Overrides from Settings apply on first open.")
        }
    }

    private func fieldRow<Control: View>(label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appSurface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))
        .padding(.bottom, 10)
    }

    private var zonesPanel: some View {
        Panel {
            HStack {
                Text("ZONE")
                    .frame(width: 52, alignment: .leading)
                Text("USE")
                Spacer()
                Text("BPM")
            }
            .font(.system(size: 10, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Color.appMuted)
            .padding(.horizontal, 8)
            .padding(.bottom, 7)

            ForEach(0..<5, id: \.self) { index in
                zoneRow(index: index)
            }

            Hint("Karvonen HR-reserve method: zone bpm = RHR + pct × (HRmax − RHR). Zones recompute as you type.")
            if zones == nil {
                Hint("Enter a max HR above your resting HR to compute zones.")
            }
        }
    }

    private func zoneRow(index: Int) -> some View {
        let zone = zones?[index]
        let range = zone.map { "\(Int($0.lowerBPM.rounded()))–\(Int($0.upperBPM.rounded()))" } ?? "—"
        return HStack(spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(zoneColors[index])
                    .frame(width: 7, height: 18)
                Text("Z\(index + 1)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appFG)
            }
            .frame(width: 52, alignment: .leading)

            Text(Karvonen.uses[index])
                .font(.system(size: 12))
                .foregroundStyle(Color.appFG)
            Spacer()
            Text(range)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appFG)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 6).fill(index == 1 ? Color.appGoodChipBG : Color.clear))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.appLine).frame(height: 1)
        }
    }

    private var ctaBox: some View {
        CTABox {
            Text("Most of your running belongs in Z2")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text("You run and lift daily, so the trap is drifting into the middle zone every day — hard enough to accumulate fatigue, too easy to drive adaptation. Z2 should feel conversational. Save Z4/Z5 for sessions you planned as hard.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gymPanel: some View {
        Panel {
            SectionTitle("Gym day")
            Text("Lifting barely moves heart rate, so HR-based load alone undercounts a heavy session. Lifts get logged separately as sets × reps × load rather than pretending a HR-derived number captures them.")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
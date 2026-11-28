import SwiftUI

/// Local to More and device settings. Deliberately does not change the
/// shared Panel or global layout tokens used by biometric screens.
struct MoreSettingsCard<Content: View>: View {
    let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                SectionTitle(title)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppLayout.cardInset)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.dashboardCard))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 0.5))
    }
}

/// Uniform outline artwork, sized independently of the row text.
struct MoreSettingsIcon: View {
    let symbol: String
    var tint: Color = .appAccent

    var body: some View {
        ReferencePictogram(symbol: symbol, size: 21)
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

struct MoreSettingsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccent.opacity(configuration.isPressed ? 0.12 : 0))
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// One row grammar: navigation has a chevron, actions have an action label,
/// restricted rows have a status label only. Full-width interaction target
/// with multiline copy and the same leading/trailing alignment.
struct MoreSettingsDetailRow: View {
    enum Accessory {
        case navigation
        case action(String, Color)
        case progress
        case restricted(String)
    }

    let title: String
    var icon: String? = nil
    let subtitle: String
    var titleColor: Color = .appFG
    let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                MoreSettingsIcon(symbol: icon, tint: iconTint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(StrapTypography.body(13, weight: .bold))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(StrapTypography.body(11.5))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessoryView
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var iconTint: Color {
        switch accessory {
        case .navigation, .progress: return .appAccent
        case .action(_, let color): return color
        case .restricted: return .appMuted
        }
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .navigation:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
        case .action(let text, let color):
            Text(text)
                .font(StrapTypography.metric(10, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
        case .progress:
            ProgressView().controlSize(.small)
        case .restricted(let text):
            Text(text)
                .font(StrapTypography.metric(9, weight: .bold))
                .foregroundStyle(Color.appWarn)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(Color.appWarn.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
        }
    }
}

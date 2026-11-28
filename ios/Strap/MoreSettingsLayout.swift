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
                    .padding(.bottom, 2)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppLayout.cardInset)
        .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(LinearGradient.appCard))
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
    let subtitle: String
    var titleColor: Color = .appFG
    let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                .padding(.top, 2)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
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
                .fixedSize()
        case .progress:
            ProgressView().controlSize(.small)
        case .restricted(let text):
            Text(text)
                .font(StrapTypography.metric(9, weight: .bold))
                .foregroundStyle(Color.appWarn)
                .fixedSize()
        }
    }
}

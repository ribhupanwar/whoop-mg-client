import SwiftUI

enum ActivitySwipeIntent: Equatable {
    case showDelete, hideDelete
    static func resolve(_ translation: CGSize) -> ActivitySwipeIntent? {
        let x = translation.width, y = translation.height
        guard x.isFinite, y.isFinite, abs(x) > abs(y) * 1.5 else { return nil }
        if x < -60 { return .showDelete }
        if x > 40 { return .hideDelete }
        return nil
    }
}

/// ScrollView activity cards use an explicit reveal-and-tap action; a drag
/// never deletes a record. Vertical scrolling does not reveal deletion.
struct ActivityDeleteReveal: ViewModifier {
    let delete: () -> Void
    @State private var revealed = false
    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            if revealed {
                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash").font(.caption.bold())
                        .frame(minWidth: 64, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(Color.appHigh)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard let intent = ActivitySwipeIntent.resolve(value.translation) else { return }
            withAnimation(.easeInOut(duration: 0.18)) { revealed = intent == .showDelete }
        })
        .accessibilityAction(named: Text("Show delete activity")) { revealed = true }
    }
}

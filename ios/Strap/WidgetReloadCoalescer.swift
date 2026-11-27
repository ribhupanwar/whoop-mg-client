import Foundation

/// Throttles WidgetKit timeline reloads while guaranteeing a single trailing
/// reload after the cooldown expires so the latest persisted snapshot is never dropped.
@MainActor
final class WidgetReloadCoalescer {
    private let minimumInterval: TimeInterval
    private let now: () -> Date
    private var lastReloadAt: Date = .distantPast
    private var trailingTask: Task<Void, Never>?
    private var pendingAction: (@MainActor () -> Void)?

    nonisolated init(minimumInterval: TimeInterval = 60, now: @escaping () -> Date = Date.init) {
        self.minimumInterval = minimumInterval
        self.now = now
    }

    func requestReload(_ action: @escaping @MainActor () -> Void) {
        let current = now()
        let elapsed = current.timeIntervalSince(lastReloadAt)
        if elapsed >= minimumInterval {
            trailingTask?.cancel()
            trailingTask = nil
            pendingAction = nil
            lastReloadAt = current
            action()
            return
        }
        pendingAction = action
        guard trailingTask == nil else { return }
        let delay = max(0.05, minimumInterval - elapsed)
        trailingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((delay * 1_000_000_000).rounded()))
            guard !Task.isCancelled, let self else { return }
            self.trailingTask = nil
            guard let deferred = self.pendingAction else { return }
            self.pendingAction = nil
            self.lastReloadAt = self.now()
            deferred()
        }
    }

    func cancel() {
        trailingTask?.cancel()
        trailingTask = nil
        pendingAction = nil
    }
}

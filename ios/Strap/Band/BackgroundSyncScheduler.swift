import BackgroundTasks
import Foundation

/// Opportunistic BGProcessingTask scheduler for background BLE history sync.
/// iOS decides when to grant background execution; force-quit apps are not woken.
final class BackgroundSyncScheduler {
    static let shared = BackgroundSyncScheduler()
    static let taskIdentifier = "com.ribhupanwar.strap.history-sync"

    private var registered = false
    private let lock = NSLock()
    private var syncHandler: ((@escaping (Bool) -> Void) -> Void)?
    private(set) var lastScheduledAt: Date?
    private(set) var lastExecutedAt: Date?

    private init() {}

    func setSyncHandler(_ handler: @escaping (@escaping (Bool) -> Void) -> Void) {
        lock.lock()
        syncHandler = handler
        lock.unlock()
    }

    func registerIfNeeded() {
        lock.lock()
        let shouldRegister = !registered
        registered = true
        lock.unlock()
        guard shouldRegister else { return }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(processingTask)
        }
    }

    func makeRequest(earliestBeginDate: Date = Date(timeIntervalSinceNow: 15 * 60)) -> BGProcessingTaskRequest {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = earliestBeginDate
        return request
    }

    func scheduleIfPermitted(isPaired: Bool) {
        guard isPaired else { return }
        do {
            try BGTaskScheduler.shared.submit(makeRequest())
            lastScheduledAt = Date()
        } catch {
            // Simulator or unentitled builds reject BGTaskScheduler; ignore cleanly.
        }
    }

    private func handle(_ task: BGProcessingTask) {
        lastExecutedAt = Date()
        scheduleIfPermitted(isPaired: true)

        lock.lock()
        let handler = syncHandler
        lock.unlock()

        guard let handler else {
            task.setTaskCompleted(success: true)
            return
        }

        var completed = false
        let finish: (Bool) -> Void = { [weak self] success in
            self?.lock.lock()
            let already = completed
            completed = true
            self?.lock.unlock()
            guard !already else { return }
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            finish(false)
        }

        handler(finish)
    }
}

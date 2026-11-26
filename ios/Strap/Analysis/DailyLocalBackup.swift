import Foundation

/// Opportunistic local backups: never promise precise background scheduling.
/// Existing WAL-safe snapshot/manifest and verified restore pipeline are reused.
actor DailyLocalBackup {
    static let shared = DailyLocalBackup()
    static let enabledKey = "strap.backup.daily.enabled"
    static let intervalKey = "strap.backup.intervalSeconds"
    static let retentionKey = "strap.backup.retentionDays"
    static let lastSuccessKey = "strap.backup.daily.lastSuccess"
    static let lastErrorKey = "strap.backup.daily.lastError"
    private var running = false

    static func interval(_ defaults: UserDefaults = .standard) -> TimeInterval? {
        let seconds = defaults.object(forKey: intervalKey) as? Int ?? 86_400
        guard [0, 3_600, 21_600, 43_200, 86_400, 604_800].contains(seconds) else { return 86_400 }
        return seconds == 0 ? nil : TimeInterval(seconds)
    }

    static func retentionDays(_ defaults: UserDefaults = .standard) -> Int? {
        let days = defaults.object(forKey: retentionKey) as? Int ?? 30
        return days == 0 ? nil : ([7, 30].contains(days) ? days : 30)
    }

    /// A remembered success cannot defer a new backup when every archive was
    /// deleted or moved out of the app's backup directory.
    static func effectiveLastSuccess(newestArchive: Date?, recordedSuccess: Date?) -> Date? {
        guard let newestArchive else { return nil }
        return max(newestArchive, recordedSuccess ?? newestArchive)
    }

    static func isDue(now: Date, lastSuccess: Date?, interval: TimeInterval?) -> Bool {
        guard let interval else { return false }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }

    func runIfDue(preferences: [String: Any], now: Date = Date()) {
        guard !running, UserDefaults.standard.bool(forKey: Self.enabledKey),
              let cadence = Self.interval() else { return }
        running = true
        defer { running = false }
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let directory = support.appendingPathComponent("daily-backups", isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let archives = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "zip" && $0.lastPathComponent.hasPrefix("STRAP-backup-") }
            let newest = archives.compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }.max()
            let recorded = UserDefaults.standard.object(forKey: Self.lastSuccessKey) as? Date
            let lastSuccess = Self.effectiveLastSuccess(newestArchive: newest, recordedSuccess: recorded)
            guard Self.isDue(now: now, lastSuccess: lastSuccess, interval: cadence) else { return }
            let output = try PersistenceDiagnostics.write(
                support: support, documents: documents, preferences: preferences,
                destinationDirectory: directory, fullBackup: true)
            let preview = try StrapBackup.inspect(output)
            try? fm.removeItem(at: preview.folder)
            let all = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "zip" && $0.lastPathComponent.hasPrefix("STRAP-backup-") }
                .sorted {
                    let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return a > b
                }
            // Never delete the newest verified backup, even when retention has expired.
            if let days = Self.retentionDays() {
                let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
                for old in all.dropFirst() {
                    let created = (try? old.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
                    if created < cutoff { try? fm.removeItem(at: old) }
                }
            }
            UserDefaults.standard.set(now, forKey: Self.lastSuccessKey)
            UserDefaults.standard.removeObject(forKey: Self.lastErrorKey)
        } catch {
            // A failed backup must not delete or modify existing archives.
            UserDefaults.standard.set(error.localizedDescription, forKey: Self.lastErrorKey)
        }
    }
}

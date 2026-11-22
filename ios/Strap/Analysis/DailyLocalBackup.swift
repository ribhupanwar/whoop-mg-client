import Foundation

/// Optional local-only backups. Uses the existing WAL-safe SQLite snapshot and
/// manifest ZIP writer; never modifies the live archive or any user records.
actor DailyLocalBackup {
    static let shared = DailyLocalBackup()
    static let enabledKey = "strap.backup.daily.enabled"
    private var running = false

    func runIfDue(preferences: [String: Any], now: Date = Date()) {
        guard !running, UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
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
            // Skip until at least 24 hours since the newest successful archive.
            let newest = archives.compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }.max()
            if let newest, now.timeIntervalSince(newest) < 86_400 { return }
            // A failed write never triggers retention deletion.
            let output = try PersistenceDiagnostics.write(
                support: support, documents: documents, preferences: preferences,
                destinationDirectory: directory, fullBackup: true)
            // Validate the newly written archive before rotating older copies.
            let preview = try StrapBackup.inspect(output)
            try? fm.removeItem(at: preview.folder)
            let all = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "zip" && $0.lastPathComponent.hasPrefix("STRAP-backup-") }
                .sorted {
                    let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return a > b
                }
            for old in all.dropFirst(3) { try? fm.removeItem(at: old) }
            UserDefaults.standard.set(now, forKey: "strap.backup.daily.lastSuccess")
        } catch {
            // Preserve all prior archives and source data. Retry next launch.
            UserDefaults.standard.set(error.localizedDescription, forKey: "strap.backup.daily.lastError")
        }
    }
}

import SwiftUI

struct FilteredRecordsExportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var through = Date()
    @State private var running = false
    @State private var status = ""
    @State private var exported: URL?
    var body: some View {
        Form {
            Text("Export retained band seconds/RR, loaded saved daily metrics/sleep, manual/live/detected activities, local journal, GPS runs and imported Apple Health records. CSV includes each complete original record as a quoted JSON cell. JSON embeds original records with source labels. This is a report, not a restorable backup.")
            DatePicker("From", selection: $from, displayedComponents: .date)
            DatePicker("Through", selection: $through, displayedComponents: .date)
            Text("Whole selected days use this phone's current calendar/timezone. Timestamped activities use start, saved sleep uses wake, and day-only entries use their recorded date. SQLite contains committed records only; an ongoing session or unsaved sync may appear after it is persisted.")
            Button("Export local & Apple Health JSON") { export(asCSV: false) }.disabled(running || from > through)
            Button("Export local & Apple Health CSV") { export(asCSV: true) }.disabled(running || from > through)
            NavigationLink("Export original WHOOP CSV/JSON") { ImportHistoryView() }
            Text(status)
            if let exported { ShareLink("Save exported report", item: exported) }
        }.navigationTitle("Filtered records export")
    }
    private func export(asCSV: Bool) {
        running = true
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)) else {
            status = "Cannot resolve selected calendar dates."; running = false; return
        }
        do {
            var records: [FilteredRecordExport.Record] = []
            for day in store.band.days { records.append(try .make(day, source: "band_daily_metrics", id: day.dateKey, dateKey: day.dateKey)) }
            for row in store.manualActivities { records.append(try .make(row, source: "manual_activity", id: row.id.uuidString, dateKey: row.dateKey)) }
            for row in store.liveActivities { records.append(try .make(row, source: "live_activity", id: row.id.uuidString, unix: Double(row.startedUnix))) }
            for row in store.detectedBandActivities { records.append(try .make(row, source: "band_activity", id: String(row.id), unix: Double(row.startUnix))) }
            for (key, row) in store.journalEntries { records.append(try .make(row, source: "local_journal", id: key, dateKey: key)) }
            for row in store.band.summary?.sleepSessions ?? [] { records.append(try .make(row, source: "saved_sleep", id: String(row.sourceStartUnix), unix: Double(row.endUnix))) }
            let snapshot = records
            Task {
                defer { running = false }
                do {
                    let result = try await Task.detached(priority: .utility) {
                        var rows = snapshot
                        for row in try AppleHealthImport.load() {
                            rows.append(try .make(row, source: "apple_health:" + row.sourceBundle, id: row.id.uuidString, unix: row.startUnix))
                        }
                        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        let gps = support.appendingPathComponent("Strap/gps-runs-v2.json")
                        let gpsData: Data?
                        if FileManager.default.fileExists(atPath: gps.path) { gpsData = try Data(contentsOf: gps) }
                        else { gpsData = UserDefaults.standard.data(forKey: "strap.gps.runs.v1") }
                        if let gpsData {
                            for row in try JSONDecoder().decode([GPSRunRecord].self, from: gpsData) {
                                rows.append(try .make(row, source: "gps_run", id: row.id.uuidString, unix: row.startedAt.timeIntervalSince1970))
                            }
                        }
                        return try FilteredRecordExport.write(rows, database: support.appendingPathComponent("strap-history-v18.sqlite"),
                            from: start, until: end, calendar: calendar, asCSV: asCSV, destination: FileManager.default.temporaryDirectory)
                    }.value
                    exported = result.url
                    status = "Exported \(result.count) records. \(result.undated) undated records excluded. Older recovery-vault revisions, OS reports and unsupported raw captures remain available in full diagnostics/backup."
                } catch { status = error.localizedDescription }
            }
        } catch { status = error.localizedDescription; running = false }
    }
}

import Combine
import CoreBluetooth
import Foundation

enum BandStatus: Equatable {
    case idle
    case poweredOff
    case unauthorized
    case unsupported
    case scanning
    case connecting(String)
    case authenticating
    case draining
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Not connected"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied"
        case .unsupported: return "Bluetooth LE unsupported"
        case .scanning: return "Searching for your strap…"
        case .connecting: return "Connecting…"
        case .authenticating: return "Pairing — accept the Bluetooth prompt"
        case .draining: return "Reading stored history…"
        case .ready: return "Connected"
        case .failed(let message): return message
        }
    }

    var isConnected: Bool {
        switch self {
        case .authenticating, .draining, .ready: return true
        default: return false
        }
    }
}

struct DrainStats: Equatable {
    var frames = 0
    var samples = 0
    var acks = 0
}

/// One live heart-rate reading. Standard 0x2A37, not the proprietary history.
struct LiveSample: Codable, Equatable, Identifiable {
    let unix: Int
    let heartRate: Int
    let rrIntervalsMS: [Int]

    var id: Int { unix }
}

struct LiveSessionSummary: Codable, Equatable {
    let startedUnix: Int
    let endedUnix: Int
    let seconds: Int
    let meanHR: Double?
    let maxHeartRate: Int?
    let beats: Int
    let hrv: HrvResult
}

/// The band link: scan, bond, drain stored history, and stream live HR.
///
/// Sequence observed on real hardware: subscribe first, write CLIENT_HELLO
/// (0x91) with response to trigger the just-works bond, then GET_DATA_RANGE
/// and SEND_HISTORICAL_DATA with empty bodies. Every HISTORY_END token is
/// echoed back with HISTORICAL_DATA_RESULT. Commands are spaced ~120 ms.
/// BLE is one-central: turn the phone's own Bluetooth pairing to the band off.
final class BandLink: NSObject, ObservableObject {
    static let commandSpacing: TimeInterval = 0.12
    static let drainIdleSeconds: TimeInterval = 30
    static let drainEmptySeconds: TimeInterval = 25
    static let drainMaxSeconds: TimeInterval = 3600

    @Published private(set) var status: BandStatus = .idle
    @Published private(set) var bandName: String?
    @Published private(set) var firmwareRevision: String?
    @Published private(set) var lastHistoryRecordCount = 0
    @Published private(set) var lastHistorySyncAt: Date?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var liveHeartRate: Int?
    @Published private(set) var recentLiveHR: [LiveSample] = []
    @Published private(set) var lastLiveHRAt: Date?
    @Published private(set) var liveHRNotificationCount = 0
    @Published private(set) var liveRRIntervalsMS: [Int] = []
    @Published private(set) var archivedLiveRRSamples: [LiveSample] = []
    @Published private(set) var type40RRPackets = 0
    @Published private(set) var standardRRPackets = 0
    @Published private(set) var historyRRRecords = 0
    @Published private(set) var historyRRDeclared = 0
    @Published private(set) var historyRRAccepted = 0
    @Published private(set) var historyRRRejected = 0
    @Published private(set) var historyUndecodableFrames = 0
    @Published private(set) var historyVersionCounts: [Int: Int] = [:]
    @Published private(set) var liveSamples: [LiveSample] = []
    @Published private(set) var sessionStartedUnix: Int?
    @Published private(set) var lastLiveSession: LiveSessionSummary?
    @Published private(set) var summary: CaptureSummary?
    @Published private(set) var lastSleepAnalysis: SleepAnalysis?
    @Published private(set) var days: [DayMetrics] = []
    @Published private(set) var drainStats = DrainStats()
    @Published private(set) var lastCapturePath: String?
    @Published private(set) var isLiveSession = false
    @Published var lastMessage: String?
    /// Straps seen in the current discovery pass, strongest signal first.
    @Published private(set) var discoveredBands: [DiscoveredBand] = []
    @Published private(set) var isFindingBands = false
    /// The band this phone last connected to. Bands of the same model share a
    /// name, so the stored peripheral identifier is what pins the choice.
    @Published private(set) var preferredBandID: String?
    @Published private(set) var preferredBandName: String?

    private enum Keys {
        static let days = "strap.days.v1"
        static let summary = "strap.capture.summary.v1"
        static let sleepAnalysis = "strap.sleep.analysis.v1"
        static let capturePath = "strap.capture.path.v1"
        static let preferredBandID = "strap.band.preferred.id.v1"
        static let preferredBandName = "strap.band.preferred.name.v1"
        static let liveRRArchive = "strap.live.rr.samples.v1"
        static let retainedHistoryCount = "strap.history.retained.count.v1"
    }

    private struct PendingCommand {
        let opcode: UInt8
        let body: [UInt8]
        let expectResponse: Bool
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?
    private var notifyCharacteristics: [CBCharacteristic] = []
    private var reassemblers: [CBUUID: FrameReassembler] = [:]
    private var subscribed: Set<CBUUID> = []
    private var subscriptionAttempts = 0

    /// Public read-only stage helps distinguish GATT connection from an
    /// authenticated Gen5 stream when the live packet counter stays at zero.
    var hrConnectionDiagnostic: String {
        guard isConnected else { return "Bluetooth disconnected" }
        guard commandCharacteristic != nil else { return "Waiting for WHOOP command characteristic" }
        guard handshakeStarted else { return "WHOOP handshake has not started" }
        guard hrBondConfirmed else { return "WHOOP hello/bond acknowledgement pending" }
        if hrCharacteristic == nil {
            return "WHOOP authenticated · standard HR characteristic unavailable · checking vendor stream"
        }
        if hrCharacteristic?.isNotifying != true {
            return "WHOOP authenticated · HR notifications not enabled"
        }
        return "WHOOP authenticated · HR subscribed · awaiting first data packet"
    }

    private var wantsConnection = false
    private var handshakeStarted = false
    private var helloAttempts = 0
    private var scanTimeout: DispatchWorkItem?
    private var pickerTimeout: DispatchWorkItem?
    /// True while the picker owns the scan: sightings are listed, not connected.
    private var pickerMode = false
    private var discoveredPeripherals: [String: CBPeripheral] = [:]

    private var commandQueue: [PendingCommand] = []
    private var commandInFlight = false
    private var commandSeq: UInt8 = 1

    private var captureWriter: CaptureWriter?
    private var capturedSamples: [V18Sample] = []
    private var retainedHistoricalSamples: [V18Sample] = []
    /// Live R-R is diagnostic-only until a verified sleep/rest window exists.
    /// Never mix it into overnight recovery or bridge missing seconds.
    var liveRRQualityDiagnostic: String {
        let records = archivedLiveRRSamples.sorted { $0.unix < $1.unix }
        guard !records.isEmpty else { return "No archived live R-R packets yet" }
        let beats = records.reduce(0) { $0 + $1.rrIntervalsMS.count }
        var longest = 0
        var current = 0
        var previous: Int?
        for sample in records {
            if let last = previous {
                if sample.unix == last { continue }
                current = sample.unix == last + 1 ? current + 1 : 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = sample.unix
        }
        return "Live R-R archive: \(beats) beats / \(records.count) seconds; longest contiguous: \(longest)s (not overnight HRV)"
    }

    var historicalRestQualityReason: String {
        guard !retainedHistoricalSamples.isEmpty else { return "No retained historical records" }
        let periods = SleepDetect.detect(retainedHistoricalSamples)
        guard !periods.isEmpty else {
            return "Sleep session not detected; " + Hrv.restingQualityReason(retainedHistoricalSamples)
        }
        let overnight = retainedHistoricalSamples.filter { sample in
            periods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
        }
        return Hrv.restingQualityReason(overnight)
    }

    private var historicalArchiveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("strap-history-v18.json")
    }

    private func mergeHistoricalArchive(_ incoming: [V18Sample]) -> [V18Sample]? {
        // Older archives may contain duplicate timestamps. Never crash during reload.
        var bySecond: [Int: V18Sample] = [:]
        for sample in retainedHistoricalSamples {
            if let old = bySecond[sample.unix] {
                let oldScore = old.rrIntervalsMS.count * 10 + (old.dynamicAccelG == nil ? 0 : 1)
                let newScore = sample.rrIntervalsMS.count * 10 + (sample.dynamicAccelG == nil ? 0 : 1)
                if newScore > oldScore { bySecond[sample.unix] = sample }
            } else {
                bySecond[sample.unix] = sample
            }
        }
        for sample in incoming {
            if let old = bySecond[sample.unix] {
                let oldScore = old.rrIntervalsMS.count * 10 + (old.dynamicAccelG == nil ? 0 : 1)
                let newScore = sample.rrIntervalsMS.count * 10 + (sample.dynamicAccelG == nil ? 0 : 1)
                if newScore > oldScore { bySecond[sample.unix] = sample }
            } else {
                bySecond[sample.unix] = sample
            }
        }
        let ordered = bySecond.values.sorted { $0.unix < $1.unix }
        let cutoff = (ordered.last?.unix ?? 0) - 72 * 3600
        let merged = ordered.filter { $0.unix >= cutoff }
        do {
            let url = historicalArchiveURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(merged).write(to: url, options: .atomic)
            retainedHistoricalSamples = merged
            return merged
        } catch {
            lastMessage = "History archive save failed: \(error.localizedDescription)"
            return nil
        }
    }
    private var seenRecordIndices: Set<UInt32> = []
    private var drainFrames = 0
    private var historicalRecordFrames = 0
    private var drainAcks = 0
    private var drainStartedAt: Date?
    private var lastFrameAt: Date?
    private var drainTimer: Timer?
    private var liveHRWatchdog: Timer?
    private var lastHRRecoveryAt: Date?
    private var hrRecoveryAttempts = 0
    private var hrDiscoveryRequestedAt: Date?
    private var hrResubscribePending = false
    private var hrSubscribedBeforeBond = false
    private var hrBondConfirmed = false
    private var hrSubscriptionConfirmedAt: Date?
    private var hrConnectedAt: Date?
    private var reconnectWork: DispatchWorkItem?
    private var reconnectAttempt = 0
    private static let restoreIdentifier = "com.strap.band.central.v1"
    private static let firmwareRevisionUUID = CBUUID(string: "2A26")
    private var hrCharacteristic: CBCharacteristic?
    private var hrProfileEnabled = false
    private var hrEnableQueued = false

    private var sex: Sex = .unspecified
    private var maxHR: Double?
    private var needHours: Double = 8

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Keys.days),
           let saved = try? JSONDecoder().decode([DayMetrics].self, from: data) {
            days = saved
        }
        if let data = UserDefaults.standard.data(forKey: Keys.summary),
           let saved = try? JSONDecoder().decode(CaptureSummary.self, from: data) {
            summary = saved
        }
        if let data = UserDefaults.standard.data(forKey: Keys.sleepAnalysis),
           let saved = try? JSONDecoder().decode(SleepAnalysis.self, from: data) {
            lastSleepAnalysis = saved
        }
        if let data = UserDefaults.standard.data(forKey: Keys.liveRRArchive),
           let saved = try? JSONDecoder().decode([LiveSample].self, from: data) {
            archivedLiveRRSamples = saved
        }
        if let data = try? Data(contentsOf: historicalArchiveURL),
           let saved = try? JSONDecoder().decode([V18Sample].self, from: data) {
            retainedHistoricalSamples = saved
        }
        lastHistoryRecordCount = retainedHistoricalSamples.count
        lastCapturePath = UserDefaults.standard.string(forKey: Keys.capturePath)
        preferredBandID = UserDefaults.standard.string(forKey: Keys.preferredBandID)
        preferredBandName = UserDefaults.standard.string(forKey: Keys.preferredBandName)
        central = CBCentralManager(delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier])
    }

    // MARK: - Settings

    private var lastRecalculationSettings: String?

    func configure(sex: Sex, maxHR: Double?, needHours: Double) {
        self.sex = sex
        self.maxHR = maxHR
        self.needHours = needHours
        // Avoid reprocessing the full BLE archive whenever SwiftUI reconfigures
        // the same BandLink instance with unchanged settings.
        let settingsKey = "\(sex)|\(String(describing: maxHR))|\(needHours)"
        guard lastRecalculationSettings != settingsKey else { return }
        lastRecalculationSettings = settingsKey
        recalculateRetainedMetrics()
    }

    /// Read-only coverage diagnostics for today's locally retained archive.
    /// Reports observed HR coverage, not inferred exercise duration.
    var strainDiagnostics: String {
        let calendar = Calendar.current
        let today = retainedHistoricalSamples.filter {
            calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0.unix)), inSameDayAs: Date())
        }
        let valid = today.filter { $0.wearing && (35...220).contains($0.heartRate) }
            .sorted { $0.unix < $1.unix }
        let timestamps = Array(Set(valid.map(\.unix))).sorted()
        guard !timestamps.isEmpty else { return "No valid awake HR records in today's retained archive." }
        let sleeps = SleepDetect.detect(retainedHistoricalSamples)
        let awake = timestamps.filter { t in
            !sleeps.contains { $0.startUnix <= t && t <= $0.endUnix }
        }
        var observedSeconds = 0
        var capped5Seconds = 0
        var capped30Seconds = 0
        var gapsOver30 = 0
        for i in awake.indices {
            let gap = i + 1 < awake.count ? awake[i + 1] - awake[i] : 1
            if gap > 30 { gapsOver30 += 1 }
            observedSeconds += 1
            capped5Seconds += gap > 0 ? min(gap, 5) : 1
            capped30Seconds += gap > 0 && gap <= 30 ? gap : 1
        }
        let score = days.first { $0.dateKey == JournalStore.dayKey(for: Date()) }?.strain
        let scoreText = score.map { String(format: "%.2f", $0) } ?? "unavailable"
        return "Today's stored HR: \(today.count) records; valid unique: \(timestamps.count); awake: \(awake.count); sleep-excluded: \(timestamps.count - awake.count).\nObserved: \(observedSeconds)s; 5s-cap estimate: \(capped5Seconds)s; 30s-cap estimate: \(capped30Seconds)s; gaps >30s: \(gapsOver30).\nDaily strain: \(scoreText). These coverage estimates are not verified continuous wear time."
    }

    /// Rebuild derived scores from the retained raw archive without requiring
    /// another BLE drain. This also migrates cached values after algorithm fixes.
    func recalculateRetainedMetrics() {
        guard !retainedHistoricalSamples.isEmpty else { return }
        let fresh = CaptureSummary.make(
            samples: retainedHistoricalSamples, sex: sex, maxHR: maxHR,
            awakeBaseline: awakeBaseline
        )
        summary = fresh
        persist(fresh)
        merge(DailyAnalysis.metrics(
            from: retainedHistoricalSamples, sex: sex, maxHR: maxHR
        ))
        if !fresh.sleepPeriods.isEmpty {
            let analysis = SleepReport.analyze(
                samples: retainedHistoricalSamples,
                periods: fresh.sleepPeriods,
                needHours: needHours,
                nights: recentNights,
                sleepBaseline: sleepBaseline
            )
            lastSleepAnalysis = analysis
            if let analysis, let data = try? JSONEncoder().encode(analysis) {
                UserDefaults.standard.set(data, forKey: Keys.sleepAnalysis)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.sleepAnalysis)
            }
        } else {
            // A new archive with no detected night must not keep displaying
            // the previous capture's sleep report.
            lastSleepAnalysis = nil
            UserDefaults.standard.removeObject(forKey: Keys.sleepAnalysis)
        }
    }

    // MARK: - Derived values

    var isConnected: Bool { peripheral?.state == .connected }

    var baseline: Baseline? {
        DailyAnalysis.baseline(from: Array(days.suffix(30)))
    }

    /// Stress is scored against awake days only: sleep lnRMSSD runs higher.
    var awakeBaseline: Baseline? {
        DailyAnalysis.baseline(from: Array(days.filter { $0.state == "awake" }.suffix(30)))
    }

    var sleepBaseline: Baseline? {
        DailyAnalysis.baseline(from: Array(days.filter { $0.state == "sleep" }.suffix(30)))
    }

    var recentNights: [NightSpan] {
        days.suffix(14).compactMap { $0.night }
    }

    var stress: StressResult {
        Recovery.stressIndex(lnRMSSD: summary?.hrv.lnRMSSD, baseline: awakeBaseline)
    }

    /// Corrected sleep durations affect Recovery immediately; original
    /// physiological samples remain unchanged for HRV/RHR provenance.
    var lastNightHours: Double? {
        guard let periods = summary?.sleepPeriods else { return nil }
        let overrides = UserDefaults.standard.dictionary(forKey: "strap.sleep.time.corrections.v1") as? [String: [Int]] ?? [:]
        // Manual corrections define the sleep window, but awake periods must
        // still be excluded when no correction is present.
        // The Home card represents the latest sleep session, not the sum of
        // every detected nap/session in the retained multi-day capture.
        guard let period = periods.max(by: { $0.endUnix < $1.endUnix }) else { return nil }
        let corrected = overrides[String(period.startUnix)]
        if let corrected, corrected.count == 2, corrected[1] > corrected[0] {
            let correctedHours = Double(corrected[1] - corrected[0]) / 3600.0
            return correctedHours * min(1.0, max(0.0, period.quietFraction))
        }
        if let stage = summary?.sleepStaging,
           summary?.sleepPeriods.last?.startUnix == period.startUnix,
           stage.reason == nil {
            return stage.asleepMinutes / 60.0
        }
        return period.hours * min(1.0, max(0.0, period.quietFraction))
    }

    func notifySleepCorrectionChanged() {
        objectWillChange.send()
    }

    var recovery: RecoveryResult {
        Recovery.score(
            lnRMSSD: summary?.hrv.lnRMSSD,
            rhr: summary?.restingHeartRate,
            sleepHours: lastNightHours,
            sleepNeedHours: needHours,
            baseline: baseline
        )
    }

    /// Import dated WHOOP recovery inputs without overwriting band-captured
    /// values. The imported days are persisted and can contribute to baselines.
    @discardableResult
    func importWhoopHistory(_ rows: [WhoopCSVImport.Row]) -> Int {
        var byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
        var inserted = 0
        for row in rows {
            if let old = byDate[row.dateKey] {
                // Prefer locally measured values when present; fill only gaps.
                guard old.lnRMSSD == nil || old.restingHR == nil else { continue }
                byDate[row.dateKey] = DayMetrics(
                    dateKey: old.dateKey, state: old.state,
                    restingHR: old.restingHR ?? row.restingHR,
                    lnRMSSD: old.lnRMSSD ?? log(row.hrvMS),
                    hrvWindowSeconds: old.hrvWindowSeconds,
                    sleepHours: old.sleepHours, sleepStartUnix: old.sleepStartUnix,
                    sleepEndUnix: old.sleepEndUnix, strain: old.strain, steps: old.steps
                )
            } else {
                byDate[row.dateKey] = DayMetrics(
                    dateKey: row.dateKey, state: "imported",
                    restingHR: row.restingHR, lnRMSSD: log(row.hrvMS),
                    hrvWindowSeconds: 0, sleepHours: 0,
                    sleepStartUnix: nil, sleepEndUnix: nil, strain: nil, steps: nil
                )
            }
            inserted += 1
        }
        if inserted > 0 {
            days = byDate.values.sorted { $0.dateKey < $1.dateKey }
            if let encoded = try? JSONEncoder().encode(days) {
                UserDefaults.standard.set(encoded, forKey: Keys.days)
            }
        }
        return inserted
    }

    // MARK: - Connection

    func connect(sex: Sex, maxHR: Double?, needHours: Double) {
        configure(sex: sex, maxHR: maxHR, needHours: needHours)
        stopPicker()
        wantsConnection = true
        if let peripheral, peripheral.state == .connected {
            maybeBeginHandshake()
            return
        }
        // A saved CoreBluetooth peripheral can remain in .connecting forever
        // without didConnect/didFailToConnect (e.g. the band stopped advertising).
        // A deliberate Connect tap must recover instead of silently returning.
        if let peripheral, peripheral.state == .connecting {
            lastMessage = "Retrying saved strap connection and discovery…"
            central.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
            reconnectWork?.cancel()
            reconnectWork = nil
            if central.state == .poweredOn { beginScan() }
            return
        }
        if central.state == .poweredOn {
            reconnectSavedPeripheralOrScan()
        } else {
            lastMessage = status.title
        }
    }

    /// Open a discovery pass for the picker. Nothing connects until the user
    /// taps a row, so two straps on the same desk cannot race for the link.
    func findBands() {
        guard central.state == .poweredOn else {
            lastMessage = status.title
            return
        }
        stopPicker()
        pickerMode = true
        isFindingBands = true
        wantsConnection = true
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isFindingBands else { return }
            self.isFindingBands = false
            self.pickerMode = false
            self.central.stopScan()
            if self.discoveredBands.isEmpty {
                self.lastMessage = "No straps found. Bring the band close, and forget it in iPhone Settings → Bluetooth if it is paired there."
            }
        }
        pickerTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    /// Connect to a strap the picker found and remember it for next launch.
    func connect(to band: DiscoveredBand) {
        guard central.state == .poweredOn else {
            lastMessage = status.title
            return
        }
        let target = discoveredPeripherals[band.id]
            ?? central.retrievePeripherals(withIdentifiers: [band.uuid]).first
        guard let target else {
            lastMessage = "That strap is out of range now — search again."
            return
        }
        pickerTimeout?.cancel()
        pickerTimeout = nil
        scanTimeout?.cancel()
        scanTimeout = nil
        isFindingBands = false
        pickerMode = false
        central.stopScan()

        wantsConnection = true
        preferredBandID = band.id
        preferredBandName = band.name
        UserDefaults.standard.set(band.id, forKey: Keys.preferredBandID)
        UserDefaults.standard.set(band.name, forKey: Keys.preferredBandName)

        // Already talking to this strap: keep the live link and its drain.
        if let current = peripheral, current.identifier == target.identifier,
           current.state == .connected {
            bandName = band.name
            discoveredBands = []
            discoveredPeripherals = [:]
            return
        }

        if let current = peripheral, current.state != .disconnected,
           current.identifier != target.identifier {
            central.cancelPeripheralConnection(current)
        }
        reconnectWork?.cancel()
        reconnectWork = nil
        reconnectAttempt = 0
        resetLink()
        bandName = band.name
        target.delegate = self
        peripheral = target
        discoveredBands = []
        discoveredPeripherals = [:]
        status = .connecting(band.name)
        central.connect(target, options: nil)
    }

    /// Drop the saved choice without touching the current link; the next
    /// Connect picks whichever strap answers first.
    func forgetPreferredBand() {
        preferredBandID = nil
        preferredBandName = nil
        UserDefaults.standard.removeObject(forKey: Keys.preferredBandID)
        UserDefaults.standard.removeObject(forKey: Keys.preferredBandName)
    }

    private func stopPicker() {
        pickerTimeout?.cancel()
        pickerTimeout = nil
        isFindingBands = false
        pickerMode = false
        discoveredBands = []
        discoveredPeripherals = [:]
        if central.state == .poweredOn { central.stopScan() }
    }

    func disconnect() {
        wantsConnection = false
        reconnectWork?.cancel()
        reconnectWork = nil
        reconnectAttempt = 0
        if status == .draining { finishDrain() }
        scanTimeout?.cancel()
        scanTimeout = nil
        stopPicker()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetLink()
        isLiveSession = false
        sessionStartedUnix = nil
        liveSamples = []
        status = .idle
    }

    func refreshBattery() {
        guard let peripheral, let batteryCharacteristic else { return }
        peripheral.readValue(for: batteryCharacteristic)
    }

    // Preserve actual beat intervals outside manual live sessions. Keep one
    // timestamped record per second and bound disk use to the latest hour.
    // Gaps must not be treated as consecutive beats for RMSSD.
    private func archiveLiveRR(unix: Int, heartRate: Int, intervals: [Int]) {
        guard !intervals.isEmpty else { return }
        let entry = LiveSample(unix: unix, heartRate: heartRate, rrIntervalsMS: intervals)
        if archivedLiveRRSamples.last?.unix == unix {
            // Prefer the richer packet, not the last HR-only notification.
            if intervals.count > archivedLiveRRSamples[archivedLiveRRSamples.count - 1].rrIntervalsMS.count {
                archivedLiveRRSamples[archivedLiveRRSamples.count - 1] = entry
            }
        } else {
            archivedLiveRRSamples.append(entry)
        }
        archivedLiveRRSamples = Array(archivedLiveRRSamples.suffix(3600))
        if let data = try? JSONEncoder().encode(archivedLiveRRSamples) {
            UserDefaults.standard.set(data, forKey: Keys.liveRRArchive)
        }
    }

    // Always collect a bounded, timestamped live HR graph, including outside
    // manually started sessions. One point per second; latest 30 minutes.
    private func recordLiveHR(_ bpm: Int) {
        let now = Int(Date().timeIntervalSince1970)
        let entry = LiveSample(unix: now, heartRate: bpm, rrIntervalsMS: [])
        if recentLiveHR.last?.unix == now {
            recentLiveHR[recentLiveHR.count - 1] = entry
        } else {
            recentLiveHR.append(entry)
        }
        recentLiveHR.removeAll { $0.unix < now - 1800 }
    }

    // MARK: - Live session

    /// Live HR comes from the standard 0x2A37 profile, so this works while the
    /// strap streams whether or not a history drain is running.
    func startLiveSession() {
        guard isConnected else {
            lastMessage = "Connect the strap first."
            return
        }
        liveSamples = []
        liveRRIntervalsMS = []
        ensureHeartRateStream()
        sessionStartedUnix = Int(Date().timeIntervalSince1970)
        isLiveSession = true
    }

    @discardableResult
    func endLiveSession() -> LiveSessionSummary? {
        guard isLiveSession else { return nil }
        isLiveSession = false
        let started = sessionStartedUnix ?? Int(Date().timeIntervalSince1970)
        let ended = Int(Date().timeIntervalSince1970)
        let rr = liveSamples.flatMap { sample in sample.rrIntervalsMS.map { Double($0) } }
        let result = LiveSessionSummary(
            startedUnix: started,
            endedUnix: ended,
            seconds: max(0, ended - started),
            meanHR: liveSamples.isEmpty
                ? nil
                : Stats.mean(liveSamples.map { Double($0.heartRate) }),
            maxHeartRate: liveSamples.map { $0.heartRate }.max(),
            beats: rr.count,
            hrv: Hrv.fromRR(rr)
        )
        lastLiveSession = result
        sessionStartedUnix = nil
        liveSamples = []
        return result
    }

    var currentLiveHRV: HrvResult {
        Hrv.fromRR(liveSamples.flatMap { sample in sample.rrIntervalsMS.map { Double($0) } })
    }

    // MARK: - Scan and connect

    private func beginScan() {
        guard central.state == .poweredOn else { return }
        switch status {
        case .ready, .draining, .authenticating: return
        default: break
        }
        if let peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            return
        }
        status = .scanning
        lastMessage = nil
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.status == .scanning else { return }
            self.central.stopScan()
            // NOOP-style persistent desired connection: an iOS background
            // scan timeout must not silently abandon the remembered band.
            if self.wantsConnection, let id = self.preferredBandID,
               let uuid = UUID(uuidString: id),
               let saved = self.central.retrievePeripherals(withIdentifiers: [uuid]).first {
                saved.delegate = self
                self.peripheral = saved
                self.status = .connecting(self.preferredBandName ?? saved.name ?? "Saved strap")
                self.central.connect(saved, options: nil)
            } else {
                self.status = .failed("No strap found. Keep Bluetooth enabled and use Find another band if needed.")
                self.scheduleReconnect()
            }
        }
        scanTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    /// A pending CoreBluetooth connect survives iOS suspension, unlike a
    /// DispatchQueue retry timer. Prefer the saved device before scanning.
    private func reconnectSavedPeripheralOrScan() {
        guard wantsConnection, central.state == .poweredOn else { return }
        if let peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            return
        }
        if let id = preferredBandID, let uuid = UUID(uuidString: id),
           let saved = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            saved.delegate = self
            peripheral = saved
            status = .connecting(preferredBandName ?? saved.name ?? "Saved strap")
            central.connect(saved, options: nil)
            return
        }
        beginScan()
    }

    private func scheduleReconnect() {
        guard wantsConnection, central.state == .poweredOn else { return }
        reconnectWork?.cancel()
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        if reconnectAttempt >= 3, let peripheral, peripheral.state == .disconnected {
            // Leave an outstanding connection for iOS to complete on re-advertisement.
            peripheral.delegate = self
            status = .connecting(preferredBandName ?? peripheral.name ?? "Saved strap")
            central.connect(peripheral, options: nil)
            return
        }
        let delay = min(30.0, Double(1 << reconnectAttempt))
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsConnection, self.central.state == .poweredOn else { return }
            self.reconnectSavedPeripheralOrScan()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resetLink() {
        drainTimer?.invalidate()
        drainTimer = nil
        liveHRWatchdog?.invalidate()
        liveHRWatchdog = nil
        lastHRRecoveryAt = nil
        hrRecoveryAttempts = 0
        hrDiscoveryRequestedAt = nil
        hrResubscribePending = false
        hrSubscribedBeforeBond = false
        hrBondConfirmed = false
        hrSubscriptionConfirmedAt = nil
        hrConnectedAt = nil
        lastLiveHRAt = nil
        liveHeartRate = nil
        liveRRIntervalsMS = []
        liveHRNotificationCount = 0
        hrCharacteristic = nil
        hrProfileEnabled = false
        hrEnableQueued = false
        drainStartedAt = nil
        lastFrameAt = nil
        peripheral = nil
        commandCharacteristic = nil
        batteryCharacteristic = nil
        notifyCharacteristics = []
        reassemblers = [:]
        subscribed = []
        subscriptionAttempts = 0
        handshakeStarted = false
        helloAttempts = 0
        commandQueue = []
        commandInFlight = false
        commandSeq = 1
        captureWriter?.close()
        captureWriter = nil
    }

    // MARK: - Handshake

    private func maybeBeginHandshake() {
        guard !handshakeStarted,
              commandCharacteristic != nil,
              subscriptionAttempts > 0,
              peripheral?.state == .connected else { return }
        handshakeStarted = true
        status = .authenticating
        enqueue(BandCommand.clientHello.rawValue, body: [0x01])
    }

    private func beginDrainRequests() {
        guard status == .authenticating else { return }
        startDraining()
    }

    /// Pull stored history again on an already-authenticated link. Used for a
    /// second read while the strap stays connected.
    func readHistory() {
        guard peripheral?.state == .connected, commandCharacteristic != nil else {
            connect(sex: sex, maxHR: maxHR, needHours: needHours)
            return
        }
        guard status != .draining, status != .authenticating else { return }
        startDraining()
    }

    private func startDraining() {
        resubscribeNotifyCharacteristics()
        startCaptureFile()
        // 0x0E enables the standard HR profile so 0x180D broadcasts. It is a
        // documented band setting, not a destructive command.
        ensureHeartRateStream()
        // PulseForge's captured Gen5 protocol uses a separate vendor
        // REALTIME_HR_ON (0x03, body 0x01). Standard 2A37 alone can be
        // subscribed yet never deliver a packet on these straps.
        enqueue(BandCommand.realtimeHROn.rawValue, body: [0x01])
        enqueue(BandCommand.getDataRange.rawValue)
        enqueue(BandCommand.sendHistoricalData.rawValue)
        status = .draining
        drainStartedAt = Date()
        historicalRecordFrames = 0
        lastFrameAt = Date()
        drainTimer?.invalidate()
        drainTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickDrain()
        }
    }

    private func resubscribeNotifyCharacteristics() {
        guard let peripheral else { return }
        for characteristic in notifyCharacteristics where !characteristic.isNotifying {
            peripheral.setNotifyValue(true, for: characteristic)
        }
        if let hrCharacteristic, !hrCharacteristic.isNotifying {
            peripheral.setNotifyValue(true, for: hrCharacteristic)
        }
    }

    /// Re-arm both parts of the live path: the standard GATT subscription and
    /// the band's generic HR output mode. Do not flood the command queue on each
    /// watchdog tick, and never interfere with a pending CLIENT_HELLO.
    private func ensureHeartRateStream() {
        guard let peripheral, peripheral.state == .connected else { return }
        if let hrCharacteristic, !hrCharacteristic.isNotifying, !hrResubscribePending {
            peripheral.setNotifyValue(true, for: hrCharacteristic)
        }
        guard handshakeStarted, commandCharacteristic != nil,
              !hrProfileEnabled, !hrEnableQueued else { return }
        hrEnableQueued = true
        enqueue(BandCommand.setGenericHRProfile.rawValue)
    }

    private func startHRWatchdog() {
        liveHRWatchdog?.invalidate()
        liveHRWatchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isConnected else { return }
            let now = Date()
            if let last = self.lastLiveHRAt, now.timeIntervalSince(last) < 10 { return }
            // Never present an old sample as today's live pulse.
            self.liveHeartRate = nil
            // An off-wrist band can legitimately pause streaming. Renew
            // only once after a sustained 90s silent stretch; don't hammer
            // its CCCD every 15 seconds. A pre-bond subscription is renewed
            // immediately after hello acknowledgement below.
            // An absent first packet needs recovery too: waiting for an
            // existing packet timestamp alone can leave the UI stuck forever.
            // NOOP confirms standard 0x2A37 can stream before the vendor
            // handshake/bond. Do not gate its recovery on CLIENT_HELLO.
            guard self.hrRecoveryAttempts < 4,
                  let confirmed = self.hrSubscriptionConfirmedAt ?? self.hrConnectedAt,
                  now.timeIntervalSince(max(confirmed, self.lastLiveHRAt ?? confirmed)) >= 30,
                  self.lastHRRecoveryAt.map({ now.timeIntervalSince($0) >= 45 }) ?? true,
                  !self.hrResubscribePending
            else { return }
            self.lastHRRecoveryAt = now
            self.hrRecoveryAttempts += 1

            if let hr = self.hrCharacteristic {
                // The CCCD can remain enabled even when 0x2A37 stops sending.
                // Re-enable through the notification-state callback.
                if hr.isNotifying && !self.hrResubscribePending {
                    self.hrResubscribePending = true
                    self.peripheral?.setNotifyValue(false, for: hr)
                } else if !hr.isNotifying && !self.hrResubscribePending {
                    self.peripheral?.setNotifyValue(true, for: hr)
                }
                if hr.properties.contains(.read) {
                    self.peripheral?.readValue(for: hr)
                }
            } else if self.hrDiscoveryRequestedAt.map({
                now.timeIntervalSince($0) >= 20
            }) ?? true {
                // Some firmware exposes 180D after output mode is enabled.
                self.hrDiscoveryRequestedAt = now
                self.peripheral?.discoverServices([BandUUID.heartRateService])
            }
            // An ATT write ack is not evidence of ongoing notifications.
            self.hrProfileEnabled = false
            self.ensureHeartRateStream()
            // WHOOP Gen5's vendor Type-40 stream is controlled independently
            // of the standard 2A37 CCCD. Re-arm both paths on silence.
            if self.commandCharacteristic != nil, self.handshakeStarted {
                self.enqueue(BandCommand.realtimeHROn.rawValue, body: [0x01])
            }
            self.lastMessage = "No fresh HR packets · recovery attempt \(self.hrRecoveryAttempts). Check live packet count."
        }
    }

    private func enqueue(_ opcode: UInt8, body: [UInt8] = [], response: Bool = true) {
        commandQueue.append(PendingCommand(opcode: opcode, body: body, expectResponse: response))
        pump()
    }

    private func pump() {
        guard !commandInFlight, let next = commandQueue.first,
              let peripheral, let characteristic = commandCharacteristic else { return }
        commandInFlight = true
        let inner: [UInt8] = [BandPacket.command, commandSeq, next.opcode] + next.body
        commandSeq &+= 1
        let frame = Gen5Frame.build(inner)
        if next.expectResponse {
            peripheral.writeValue(Data(frame), for: characteristic, type: .withResponse)
        } else {
            peripheral.writeValue(Data(frame), for: characteristic, type: .withoutResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.commandSpacing) { [weak self] in
                self?.completeCommandSent()
            }
        }
    }

    private func completeCommandSent() {
        guard !commandQueue.isEmpty else {
            commandInFlight = false
            return
        }
        commandQueue.removeFirst()
        commandInFlight = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.commandSpacing) { [weak self] in
            self?.pump()
        }
    }

    private func isPairingInformationLost(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("removed pairing information")
            || message.contains("peer removed pairing")
    }

    private func isAuthenticationError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == CBATTErrorDomain {
            return ns.code == CBATTError.insufficientAuthentication.rawValue
                || ns.code == CBATTError.insufficientEncryption.rawValue
        }
        // CBError has no stable encryption constant across SDKs; the message is
        // the dependable signal for a dropped bond.
        let text = ns.localizedDescription.lowercased()
        return text.contains("encrypt") || text.contains("authenticat") || text.contains("pair")
    }

    // MARK: - Drain lifecycle

    private func startCaptureFile() {
        capturedSamples = []
        seenRecordIndices = []
        drainFrames = 0
        drainAcks = 0
        drainStats = DrainStats()
        historyRRRecords = 0
        historyRRDeclared = 0
        historyRRAccepted = 0
        historyRRRejected = 0
        historyUndecodableFrames = 0
        historyVersionCounts = [:]
        captureWriter?.close()
        captureWriter = CaptureWriter()
        lastCapturePath = captureWriter?.url.path
        if let path = lastCapturePath {
            UserDefaults.standard.set(path, forKey: Keys.capturePath)
        }
    }

    private func tickDrain() {
        guard let started = drainStartedAt else { return }
        let now = Date()
        let idle = now.timeIntervalSince(lastFrameAt ?? started)
        let elapsed = now.timeIntervalSince(started)
        drainStats = DrainStats(
            frames: drainFrames, samples: capturedSamples.count, acks: drainAcks
        )
        if drainFrames > 0 && idle >= Self.drainIdleSeconds {
            finishDrain(reason: "idle timeout after \(Int(idle))s")
        } else if drainFrames == 0 && elapsed >= Self.drainEmptySeconds {
            finishDrain(reason: "no history frames after \(Int(elapsed))s")
        } else if elapsed >= Self.drainMaxSeconds {
            finishDrain(reason: "maximum sync duration")
        }
    }

    private func finishDrain(reason: String = "interrupted") {
        drainTimer?.invalidate()
        drainTimer = nil
        drainStartedAt = nil
        captureWriter?.close()
        captureWriter = nil

        let samples = capturedSamples.sorted {
            $0.unix != $1.unix
                ? $0.unix < $1.unix
                : $0.header.recordIndex < $1.header.recordIndex
        }
        drainStats = DrainStats(frames: drainFrames, samples: samples.count, acks: drainAcks)
        // Diagnostic only: never infer missing R-R from a zero count and
        // never silently treat a partial history offload as a full night.
        if UserDefaults.standard.bool(forKey: "strap.spo2ResearchEnabled") {
            let candidates = samples.filter { $0.spo2CandidatePct != nil }
            let values = candidates.compactMap(\.spo2CandidatePct)
            let sentinelCount = samples.filter { $0.spo2CandidateKind == .saturated }.count
            let diagnosticCount = samples.filter { $0.spo2CandidateKind == .diagnostic }.count
            let average = values.isEmpty ? "none" :
                String(format: "%.1f", Double(values.reduce(0, +)) / Double(values.count))
            let report = "Research only · \(samples.count) v18 records · \(values.count) candidate readings · mean \(average) · \(sentinelCount) sentinels · \(diagnosticCount) diagnostic codes. Not calibrated SpO₂."
            UserDefaults.standard.set(report, forKey: "strap.spo2ResearchReport")
        }
        let rrSeconds = samples.filter { !$0.rrIntervalsMS.isEmpty }.count
        let rrBeats = samples.reduce(0) { $0 + $1.rrIntervalsMS.count }
        let uniqueSeconds = Set(samples.map(\.unix)).sorted()
        let missingSeconds = zip(uniqueSeconds, uniqueSeconds.dropFirst()).reduce(0) {
            $0 + max(0, $1.1 - $1.0 - 1)
        }
        let historyQuality = "R-R: \(rrBeats) beats / \(rrSeconds) seconds; gaps: \(missingSeconds)s"
        if !samples.isEmpty { lastHistorySyncAt = Date() }
        status = .ready
        ensureHeartRateStream()

        guard !samples.isEmpty else {
            if historicalRecordFrames == 0 && liveHRNotificationCount == 0 && firmwareRevision?.hasPrefix("50.43.") == true {
                lastMessage = "Connected, but no history records or live HR arrived. Firmware 50.43.x has reported data-access restrictions; this is not proof of a token issue. Check firmware and retry after verifying band access."
            } else if historicalRecordFrames > 0 {
                lastMessage = "Received \(historicalRecordFrames) history frames but decoded no samples. Check record version and decoder compatibility; do not discard the raw capture."
            } else {
                lastMessage = "No historical records arrived (\(drainFrames) history/metadata frames, \(drainAcks) ACKs). Check sync, clock, firmware access and retry."
            }
            return
        }
        guard let combined = mergeHistoricalArchive(samples) else { return }
        let fresh = CaptureSummary.make(
            samples: combined, sex: sex, maxHR: maxHR, awakeBaseline: awakeBaseline
        )
        // Preserve previously validated recovery if merged data lacks a quiet window.
        let previousHasRestMetrics = summary?.hrv.rmssdMS != nil || summary?.restingHeartRate != nil
        let freshHasRestMetrics = fresh.hrv.rmssdMS != nil || fresh.restingHeartRate != nil
        let preservePrevious = previousHasRestMetrics && !freshHasRestMetrics
        if !preservePrevious {
            summary = fresh
            persist(fresh)
            lastHistoryRecordCount = combined.count
            UserDefaults.standard.set(combined.count, forKey: Keys.retainedHistoryCount)
        }
        merge(DailyAnalysis.metrics(from: combined, sex: sex, maxHR: maxHR))

        if !preservePrevious && !fresh.sleepPeriods.isEmpty {
            let analysis = SleepReport.analyze(
                samples: combined,
                periods: fresh.sleepPeriods,
                needHours: needHours,
                nights: recentNights,
                sleepBaseline: sleepBaseline
            )
            lastSleepAnalysis = analysis
            if let analysis, let data = try? JSONEncoder().encode(analysis) {
                UserDefaults.standard.set(data, forKey: Keys.sleepAnalysis)
            }
        }
        lastMessage = "History sync: \(reason). Captured \(samples.count) records, \(drainAcks) ACKs. \(historyQuality). \(reason == "explicit completion" ? "" : "History may be incomplete; retry sync.")"
    }

    private func persist(_ summary: CaptureSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: Keys.summary)
        }
    }

    private func merge(_ fresh: [DayMetrics]) {
        guard !fresh.isEmpty else { return }
        var map = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
        // A short subsequent capture must not erase a fuller day's steps.
        // This is a conservative lower bound, NOT an additive daily total:
        // overlapping capture windows must never be double-counted.
        for day in fresh {
            guard let previous = map[day.dateKey] else {
                map[day.dateKey] = day
                continue
            }
            map[day.dateKey] = DayMetrics(
                dateKey: day.dateKey,
                state: day.state == "sleep" ? day.state : previous.state,
                restingHR: day.restingHR ?? previous.restingHR,
                lnRMSSD: day.lnRMSSD ?? previous.lnRMSSD,
                hrvWindowSeconds: max(day.hrvWindowSeconds, previous.hrvWindowSeconds),
                // Recomputed sleep is authoritative when a detected night is present.
                // A max() merge would permanently preserve the older inflated value.
                sleepHours: day.sleepStartUnix != nil ? day.sleepHours : previous.sleepHours,
                sleepStartUnix: day.sleepStartUnix ?? previous.sleepStartUnix,
                sleepEndUnix: day.sleepEndUnix ?? previous.sleepEndUnix,
                // Strain is a recomputed score, not an additive counter.
                // Keeping the historical maximum permanently locks in an
                // overestimated value after HR/sleep quality improves.
                // Prefer a fresh, valid recomputation; preserve the prior
                // score only when this capture cannot calculate one.
                strain: day.strain.flatMap { $0.isFinite && (0...21).contains($0) ? $0 : nil }
                    ?? previous.strain,
                steps: day.steps == nil && previous.steps == nil ? nil :
                    max(day.steps ?? 0, previous.steps ?? 0)
            )
        }
        days = map.values.sorted { $0.dateKey < $1.dateKey }
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: Keys.days)
        }
    }

    // MARK: - Notifications

    private func handleChunk(_ value: Data, uuid: CBUUID) {
        captureWriter?.chunk(value, uuid: uuid.uuidString.lowercased())
        let reassembler: FrameReassembler
        if let existing = reassemblers[uuid] {
            reassembler = existing
        } else {
            let created = FrameReassembler()
            reassemblers[uuid] = created
            reassembler = created
        }
        for inner in reassembler.feed([UInt8](value)) {
            handleFrame(inner, uuid: uuid)
        }
    }

    private func handleFrame(_ inner: [UInt8], uuid: CBUUID) {
        captureWriter?.frame(inner, uuid: uuid.uuidString.lowercased())
        guard let type = inner.first else { return }

        if type == BandPacket.historicalData {
            historicalRecordFrames += 1
        }
        if type == BandPacket.historicalData || type == BandPacket.metadata {
            drainFrames += 1
            lastFrameAt = Date()
        }
        if type == BandPacket.realtimeData {
            // Gen5 frame header is stripped by FrameReassembler. PulseForge
            // observed HR at absolute frame byte 16 => inner byte 8.
            guard inner.count > 8 else { return }
            let bpm = Int(inner[8])
            guard (25...230).contains(bpm) else { return }
            // NOOP's verified Type-40 map: absolute frame byte 17 is the
            // count; RR words start at byte 18 and are milliseconds on WHOOP 5.
            // FrameReassembler removes the 8-byte envelope and CRC trailer.
            let rrCount = inner.count > 9 ? Int(inner[9]) : 0
            var rrMS: [Int] = []
            if rrCount > 0 && rrCount <= 4 && inner.count >= 10 + rrCount * 2 {
                for i in 0..<rrCount {
                    let offset = 10 + 2 * i
                    let ms = Int(inner[offset]) | (Int(inner[offset + 1]) << 8)
                    if ms == 0 { continue } // NOOP Whoop5RR: words are already milliseconds.
                    if (V18Decoder.minRRMS...V18Decoder.maxRRMS).contains(ms) {
                        rrMS.append(ms)
                    }
                }
            }
            liveHeartRate = bpm
            recordLiveHR(bpm)
            lastLiveHRAt = Date()
            liveHRNotificationCount += 1
            hrRecoveryAttempts = 0
            if !rrMS.isEmpty {
                type40RRPackets += 1
                archiveLiveRR(unix: Int(Date().timeIntervalSince1970), heartRate: bpm, intervals: rrMS)
                liveRRIntervalsMS = Array((liveRRIntervalsMS + rrMS).suffix(120))
            }
            if isLiveSession {
                let unix = Int(Date().timeIntervalSince1970)
                let sample = LiveSample(unix: unix, heartRate: bpm, rrIntervalsMS: rrMS)
                if liveSamples.last?.unix == unix {
                    // Prefer RR-bearing packets over HR-only packets.
                    if !rrMS.isEmpty || liveSamples[liveSamples.count - 1].rrIntervalsMS.isEmpty {
                        liveSamples[liveSamples.count - 1] = sample
                    }
                } else {
                    liveSamples.append(sample)
                }
            }
        } else if type == BandPacket.historicalData {
            if inner.count > 1 {
                historyVersionCounts[Int(inner[1]), default: 0] += 1
            }
            // OpenStrap: v26 is a 76-byte optical waveform, NOT an RR/HR
            // biometric record. Recognize it without inventing heartbeats.
            if Gen5V26Record.decode(inner) != nil { return }
            guard let sample = V18Decoder.decode(inner) else {
                historyUndecodableFrames += 1
                return
            }
            if seenRecordIndices.insert(sample.header.recordIndex).inserted {
                if !sample.rrIntervalsMS.isEmpty { historyRRRecords += 1 }
                let declared = Int(inner[15])
                if declared <= 4 {
                    historyRRDeclared += declared
                    historyRRAccepted += sample.rrIntervalsMS.count
                    historyRRRejected += declared - sample.rrIntervalsMS.count
                } else {
                    historyRRRejected += 1 // malformed count byte
                }
                capturedSamples.append(sample)
            }
        } else if type == BandPacket.metadata, inner.count >= 3 {
            if inner[2] == BandPacket.historyEnd, inner.count >= 21 {
                // WHOOP 5: eight-byte end_data token at absolute frame[21:29].
                // Keep the complete token: a truncated ACK can stall backfill.
                let token = Array(inner[13..<21])
                // NOOP's safe-trim invariant: never ACK a section until its
                // raw frames are durably saved. Otherwise the strap may trim
                // records that the app has not actually preserved.
                guard let writer = captureWriter, writer.flushToDisk() else {
                    lastMessage = "History chunk not ACKed: raw capture could not be saved. Band data preserved for retry."
                    return
                }
                enqueue(BandCommand.historicalDataResult.rawValue, body: [0x01] + token)
                drainAcks += 1
                lastFrameAt = Date()
            } else if inner[2] == 3, status == .draining {
                // HISTORY_COMPLETE: stop only on the explicit completion marker.
                finishDrain(reason: "explicit completion")
            }
        }
    }

    private func handleHeartRate(_ characteristic: CBCharacteristic) {
        guard let value = characteristic.value,
              let reading = StandardHeartRate.parse(value) else { return }
        liveHeartRate = reading.heartRate
        recordLiveHR(reading.heartRate)
        lastLiveHRAt = Date()
        liveHRNotificationCount += 1
        hrRecoveryAttempts = 0
        lastMessage = nil
        if !reading.rrMS.isEmpty {
            standardRRPackets += 1
            archiveLiveRR(unix: Int(Date().timeIntervalSince1970), heartRate: reading.heartRate, intervals: reading.rrMS)
            liveRRIntervalsMS = Array((liveRRIntervalsMS + reading.rrMS).suffix(120))
        }
        guard isLiveSession else { return }
        let unix = Int(Date().timeIntervalSince1970)
        let sample = LiveSample(unix: unix, heartRate: reading.heartRate, rrIntervalsMS: reading.rrMS)
        if liveSamples.last?.unix == unix {
            // Type-40 and standard 2A37 can arrive in the same second.
            // An HR-only notification must never erase previously received
            // R-R beats. Prefer the standard 2A37 R-R source when available.
            let previous = liveSamples[liveSamples.count - 1]
            if !reading.rrMS.isEmpty || previous.rrIntervalsMS.isEmpty {
                liveSamples[liveSamples.count - 1] = sample
            }
        } else {
            liveSamples.append(sample)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BandLink: CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first(where: {
            preferredBandID == nil || $0.identifier.uuidString == preferredBandID
        }) else { return }
        wantsConnection = true
        peripheral = restored
        restored.delegate = self
        bandName = restored.name ?? preferredBandName
        status = .connecting(bandName ?? "Restored strap")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if wantsConnection || preferredBandID != nil {
                wantsConnection = true
                reconnectSavedPeripheralOrScan()
            } else {
                status = .idle
            }
        case .poweredOff:
            if pickerMode {
                pickerTimeout?.cancel()
                pickerTimeout = nil
                isFindingBands = false
                pickerMode = false
            }
            status = .poweredOff
        case .unauthorized:
            status = .unauthorized
        case .unsupported:
            status = .unsupported
        default:
            status = .idle
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let overflowServices = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]) ?? [:]
        // WHOOP 5.0 and MG use the same fd4b Gen5 transport. Some
        // advertisements omit a local name or put fd4b in overflow/service
        // data, so accepting only the visible UUID or "WHOOP" name misses them.
        let hasGen5Service = services.contains(BandUUID.service)
            || overflowServices.contains(BandUUID.service)
            || serviceData.keys.contains(BandUUID.service)
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let named = (peripheral.name ?? "").lowercased().contains("whoop")
            || advertisedName.lowercased().contains("whoop")
        guard hasGen5Service || named else { return }

        let identifier = peripheral.identifier.uuidString
        let name = !advertisedName.isEmpty ? advertisedName
            : (peripheral.name ?? "WHOOP 5.0 / MG")
        discoveredPeripherals[identifier] = peripheral
        discoveredBands = BandDiscovery.merge(
            discoveredBands,
            adding: DiscoveredBand(
                id: identifier,
                uuid: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                lastSeenUnix: Int(Date().timeIntervalSince1970)
            )
        )

        // The picker only lists sightings; the user taps the band to connect.
        if pickerMode { return }
        // With a saved band, ignore the other strap even if it advertises first.
        if let preferredBandID, identifier != preferredBandID { return }
        // A duplicate advertisement can arrive after connect was requested.
        // Never replace a connecting/connected peripheral with another callback.
        if let current = self.peripheral,
           current.state == .connecting || current.state == .connected { return }

        central.stopScan()
        scanTimeout?.cancel()
        scanTimeout = nil
        bandName = name
        peripheral.delegate = self
        self.peripheral = peripheral
        status = .connecting(name)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard wantsConnection, peripheral === self.peripheral else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        scanTimeout?.cancel()
        scanTimeout = nil
        central.stopScan()
        reconnectWork?.cancel()
        reconnectWork = nil
        reconnectAttempt = 0
        // A restored/standing connection is a fresh GATT session. Rebuild
        // subscriptions and protocol state instead of reusing stale handles.
        resetLink()
        // resetLink clears the stored peripheral reference. Restore it before
        // GATT discovery: all subsequent characteristic callbacks and handshake
        // guards require self.peripheral to be the connected device.
        self.peripheral = peripheral
        bandName = peripheral.name ?? preferredBandName ?? bandName
        status = .authenticating
        lastMessage = "Bluetooth connected; discovering WHOOP services…"
        peripheral.delegate = self
        hrConnectedAt = Date()
        startHRWatchdog()
        peripheral.discoverServices([
            BandUUID.service,
            BandUUID.heartRateService,
            BandUUID.batteryService,
            BandUUID.deviceInfoService
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        // Switching bands cancels the old link; its callback must not wipe the
        // new one.
        guard peripheral === self.peripheral else { return }
        let pairingLost = error.map { isPairingInformationLost($0) } ?? false
        resetLink()
        if pairingLost {
            // A stale iOS/strap bond cannot be repaired by repeatedly
            // reconnecting to the same remembered peripheral identifier.
            wantsConnection = false
            reconnectWork?.cancel()
            reconnectWork = nil
            forgetPreferredBand()
            status = .failed("Bluetooth pairing was removed. In iPhone Settings → Bluetooth, forget the WHOOP strap if listed; restart Bluetooth, put the strap in pairing mode, then search for it again in Strap.")
            return
        }
        status = .failed(error.map { "Could not connect: \($0.localizedDescription)" } ?? "Could not connect")
        scheduleReconnect()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral === self.peripheral else { return }
        let wasDraining = status == .draining
        if wasDraining { finishDrain() }
        resetLink()
        isLiveSession = false
        sessionStartedUnix = nil
        liveSamples = []
        status = .failed(
            error.map { "Disconnected: \($0.localizedDescription)" } ?? "Strap disconnected"
        )
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BandLink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            status = .failed("Service discovery failed: \(error.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case BandUUID.service:
                peripheral.discoverCharacteristics(
                    [BandUUID.commandTo] + BandUUID.notifiable, for: service
                )
            case BandUUID.heartRateService:
                peripheral.discoverCharacteristics([BandUUID.heartRateMeasurement], for: service)
            case BandUUID.batteryService:
                peripheral.discoverCharacteristics([BandUUID.batteryLevel], for: service)
            default:
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            lastMessage = "Characteristics unavailable: \(error.localizedDescription)"
            if service.uuid == BandUUID.service {
                status = .failed("WHOOP GATT characteristic discovery failed: \(error.localizedDescription)")
            }
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case BandUUID.commandTo:
                commandCharacteristic = characteristic
            case BandUUID.heartRateMeasurement:
                hrCharacteristic = characteristic
                subscriptionAttempts += 1
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    lastMessage = "The band did not expose HR notifications on 0x2A37."
                }
            case Self.firmwareRevisionUUID:
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            case BandUUID.batteryLevel:
                batteryCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            default:
                if BandUUID.notifiable.contains(characteristic.uuid),
                   !notifyCharacteristics.contains(where: { $0.uuid == characteristic.uuid }) {
                    notifyCharacteristics.append(characteristic)
                    subscriptionAttempts += 1
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
        maybeBeginHandshake()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            if characteristic.uuid == BandUUID.heartRateMeasurement {
                hrResubscribePending = false
            }
            if BandUUID.notifiable.contains(characteristic.uuid) {
                status = .failed("WHOOP notification subscription failed: \(error.localizedDescription)")
            }
            if isAuthenticationError(error) {
                lastMessage = "The strap needs pairing before it will stream. Accept the prompt, then reconnect."
            } else {
                lastMessage = "Subscribe failed: \(error.localizedDescription)"
            }
            return
        }
        if characteristic.isNotifying {
            subscribed.insert(characteristic.uuid)
        }
        if characteristic.uuid == BandUUID.heartRateMeasurement {
            if characteristic.isNotifying {
                hrSubscriptionConfirmedAt = Date()
                if !hrBondConfirmed { hrSubscribedBeforeBond = true }
            }
        }
        maybeBeginHandshake()
        if characteristic.uuid == BandUUID.heartRateMeasurement {
            if !characteristic.isNotifying {
                liveHeartRate = nil
                if hrResubscribePending {
                    hrResubscribePending = false
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            } else {
                hrResubscribePending = false
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        switch characteristic.uuid {
        case BandUUID.heartRateMeasurement:
            handleHeartRate(characteristic)
        case Self.firmwareRevisionUUID:
            if let data = characteristic.value,
               let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !version.isEmpty {
                firmwareRevision = version
            }
        case BandUUID.batteryLevel:
            if let value = characteristic.value, let level = value.first {
                batteryPercent = Int(level)
            }
        default:
            if BandUUID.notifiable.contains(characteristic.uuid),
               let value = characteristic.value, !value.isEmpty {
                handleChunk(value, uuid: characteristic.uuid)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic == commandCharacteristic else { return }
        if let error {
            commandInFlight = false
            if isAuthenticationError(error), helloAttempts < 2 {
                helloAttempts += 1
                commandInFlight = false
                lastMessage = "Waiting for the pairing prompt — accept it to authenticate the strap."
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.pump()
                }
                return
            }
            drainTimer?.invalidate()
            drainTimer = nil
            // Drop the failed command so later retries cannot deadlock behind it.
            if !commandQueue.isEmpty {
                if commandQueue[0].opcode == BandCommand.setGenericHRProfile.rawValue { hrEnableQueued = false }
                commandQueue.removeFirst()
            }
            status = .failed("The strap rejected a command: \(error.localizedDescription)")
            if !isAuthenticationError(error) { scheduleReconnect() }
            return
        }
        let finished = commandQueue.first?.opcode
        if finished == BandCommand.setGenericHRProfile.rawValue {
            hrEnableQueued = false
            hrProfileEnabled = true
        }
        completeCommandSent()
        if finished == BandCommand.clientHello.rawValue {
            hrBondConfirmed = true
            // Field captures show an enabled 0x2A37 subscription BEFORE
            // Gen5 encryption can remain silent forever. The bonded link
            // must renew its CCCD regardless of isNotifying=true.
            if hrSubscribedBeforeBond, let hr = hrCharacteristic, hr.isNotifying {
                hrResubscribePending = true
                peripheral.setNotifyValue(false, for: hr)
            }
            hrSubscribedBeforeBond = false
            status = .authenticating
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.beginDrainRequests()
                self?.ensureHeartRateStream()
            }
        }
    }
}

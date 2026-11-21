import Combine
import CoreBluetooth
import Foundation

enum BandStatus: Equatable {
    case unpaired
    case idle
    case poweredOff
    case unauthorized
    case unsupported
    case scanning
    case deviceFound(String)
    case connecting(String)
    case authenticating
    case connected(String)
    case streaming(bpm: Int)
    case draining
    case ready
    case disconnected(String)
    case reconnecting(attempt: Int)
    case failed(String)

    var title: String {
        switch self {
        case .unpaired: return "No band paired — tap Pair a Device"
        case .idle: return "Not connected"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied"
        case .unsupported: return "Bluetooth LE unsupported"
        case .scanning: return "Searching for your WHOOP band…"
        case .deviceFound(let name): return "Found \(name)"
        case .connecting(let name): return "Connecting to \(name)…"
        case .authenticating: return "Pairing — accept the Bluetooth prompt"
        case .connected(let name): return "Connected to \(name)"
        case .streaming(let bpm): return "Streaming live (\(bpm) BPM)"
        case .draining: return "Reading stored history…"
        case .ready: return "Connected"
        case .disconnected(let message): return "Disconnected (\(message))"
        case .reconnecting(let attempt): return "Reconnecting (attempt \(attempt))…"
        case .failed(let message): return message
        }
    }

    var isConnected: Bool {
        switch self {
        case .authenticating, .connected, .streaming, .draining, .ready: return true
        default: return false
        }
    }

    var isReady: Bool {
        switch self {
        case .ready, .connected, .streaming: return true
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
    private let preferencesWriter = BackgroundPreferencesWriter()
    private var lastLiveRRSaveAt = Date.distantPast

    static let commandSpacing: TimeInterval = 0.12
    static let drainIdleSeconds: TimeInterval = 30
    static let drainEmptySeconds: TimeInterval = 25
    static let drainMaxSeconds: TimeInterval = 3600

    @Published private(set) var status: BandStatus = .idle
    @Published private(set) var bandName: String?
    @Published private(set) var firmwareRevision: String?
    @Published private(set) var hardwareRevision: String?
    @Published private(set) var serialNumber: String?
    @Published private(set) var modelNumber: String?
    @Published private(set) var isBroadcastingHR: Bool = false
    @Published private(set) var isRebooting = false
    @Published private(set) var rebootMessage: String?
    private var rebootExpectedDisconnect = false
    @Published private(set) var lastHistoryRecordCount = 0
    @Published private(set) var lastHistorySyncAt: Date?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var liveHeartRate: Int?
    @Published private(set) var recentLiveHR: [LiveSample] = []
    @Published private(set) var liveDayStrain: Double?
    @Published private(set) var liveDayRawStrain: Double = 0.0
    private var liveDayStrainKey: String = ""
    private var lastLiveStrainSampleUnix: Int?
    private var configuredRestingHR: Double?
    @Published private(set) var lastLiveHRAt: Date?
    @Published private(set) var liveHRNotificationCount = 0
    @Published private(set) var liveRRIntervalsMS: [Int] = []
    @Published private(set) var archivedLiveRRSamples: [LiveSample] = []
    @Published private(set) var persistedLiveRRCount: Int?
    private var pendingLiveRRRecords: [LiveRRRecord] = []
    private var liveRRFlushWork: DispatchWorkItem?
    private var liveRRMigrationComplete = false
    @Published private(set) var type40RRPackets = 0
    @Published private(set) var type40HRPackets = 0
    @Published private(set) var standardHRPackets = 0
    private var lastType40HRAt: Date?
    private var staleHRReconnects = 0
    private var commandDeadline: DispatchWorkItem?
    private var currentWriteID: UUID?
    private var commandWriteTimedOut = false
    private var linkGeneration = UUID()
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
    @Published private(set) var isAnalyzingHistory = false
    @Published private(set) var isSavingHistory = false
    @Published private(set) var historyProgress: HistoryProgress?
    @Published private(set) var historySyncError: String?
    @Published private(set) var packetGapCount = 0
    @Published private(set) var duplicatePacketCount = 0
    @Published private(set) var lastPacketReceivedAt: Date?
    private var pendingArchiveWrites = 0
    private var hasUnsavedArchiveRecords = false
    @Published private(set) var historicalRestQualityReason = "Loading retained historical records…"
    private var metricsRequest = 0
    private var metricsRefreshPending = false
    private var sleepCorrectionRevision = 0
    private var lastCheckpointCount = 0
    private var lastCheckpointAt = Date.distantPast
    private lazy var archiveWriter = HistoricalArchiveWriter(url: historicalArchiveURL)
    private let analysisQueue = DispatchQueue(label: "strap.history.analysis", qos: .userInitiated)

    var latestSleepSession: SleepSession? {
        // Recipe versions invalidate calculation caches, not the recorded night.
        summary?.latestSleepSession
    }
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
        static let cachedFirmware = "strap.band.cached_firmware_revision"
        static let cachedHardware = "strap.band.cached_hardware_revision"
        static let cachedSerial = "strap.band.cached_serial_number"
        static let cachedModel = "strap.band.cached_model_number"
        static let broadcastHREnabled = "strap.band.broadcast_hr_enabled"
    }

    private struct PendingCommand {
        let opcode: UInt8
        let body: [UInt8]
        let expectResponse: Bool
        var onWrite: (() -> Void)? = nil
        var onFailure: ((String) -> Void)? = nil
    }

    @Published private(set) var bandAlarmMessage = "Connect your band to sync the wake alarm."
    @Published private(set) var buzzMessage = ""
    @Published private(set) var testingBuzz = false
    private var nextBandAlarm: Date?
    private var syncedAlarmMinutes: Int?
    private var alarmWasDisabled = false
    private var alarmWritePending = false
    private var lastBuzzAt: Date?
    private var lastAlarmAttempt: Date?

    var canTestBuzz: Bool {
        peripheral?.state == .connected && commandCharacteristic != nil && hrBondConfirmed && !testingBuzz
    }

    func testBuzz() {
        guard canTestBuzz else { buzzMessage = "Connect your band before testing vibration."; return }
        guard lastBuzzAt.map({ Date().timeIntervalSince($0) >= 3 }) ?? true else { return }
        lastBuzzAt = Date()
        testingBuzz = true
        buzzMessage = "Sending test buzz…"
        commandQueue.append(PendingCommand(opcode: BandHaptics.buzzOpcode, body: BandHaptics.buzzBody,
            expectResponse: true, onWrite: { [weak self] in
                self?.testingBuzz = false
                self?.buzzMessage = "Test command delivered. Did you feel the band buzz?"
            }, onFailure: { [weak self] error in
                self?.testingBuzz = false
                self?.buzzMessage = "Test buzz failed: " + error
            }))
        pump()
    }

    /// The band stores a timestamp, so its next alarm does not depend on an
    /// iOS timer firing in the background. Reconnect/open the app after waking
    /// to program the following day; the phone notification repeats daily.
    func syncWakeAlarm(force: Bool = false) {
        guard WakeAlarm.hasPreference else { return }
        guard peripheral?.state == .connected, commandCharacteristic != nil, hrBondConfirmed else {
            bandAlarmMessage = WakeAlarm.isEnabled ? "Reconnect strap to arm the next wake alarm on your band." : "Alarm off. Reconnect to cancel any previously sent band alarm."
            return
        }
        guard !alarmWritePending else { return }
        if !force, let lastAlarmAttempt, Date().timeIntervalSince(lastAlarmAttempt) < 30 { return }
        let on = WakeAlarm.isEnabled
        let minutes = WakeAlarm.wakeMinutes
        let next = on ? WakeAlarm.nextWakeDate() : nil
        if !force {
            if on, syncedAlarmMinutes == minutes, let nextBandAlarm, nextBandAlarm > Date(), WakeAlarm.isBandConfirmed(for: next) { return }
            if !on && alarmWasDisabled { return }
        }
        guard !on || next != nil else { bandAlarmMessage = "Could not calculate the next wake time."; return }
        let body = next.flatMap(BandHaptics.alarmBody) ?? BandHaptics.disableBody
        let opcode = on ? BandHaptics.alarmOpcode : BandHaptics.disableOpcode
        alarmWritePending = true
        lastAlarmAttempt = Date()
        bandAlarmMessage = on ? "Sending the next wake alarm to your band…" : "Cancelling the band alarm…"
        commandQueue.append(PendingCommand(opcode: opcode, body: body, expectResponse: true,
            onWrite: { [weak self] in
                guard let self else { return }
                self.alarmWritePending = false
                self.nextBandAlarm = next
                self.syncedAlarmMinutes = on ? minutes : nil
                self.alarmWasDisabled = !on
                WakeAlarm.bandConfirmedEpoch = next.map { Int($0.timeIntervalSince1970) }
                self.bandAlarmMessage = next.map {
                    "Alarm armed on band for " + $0.formatted(date: .abbreviated, time: .shortened) + "."
                } ?? "Band alarm cancellation delivered."
                // A preference may have changed while this write was queued.
                if WakeAlarm.isEnabled != on || WakeAlarm.wakeMinutes != minutes { self.syncWakeAlarm(force: true) }
            }, onFailure: { [weak self] error in
                self?.alarmWritePending = false
                WakeAlarm.bandConfirmedEpoch = nil
                self?.bandAlarmMessage = "Band alarm could not be sent: " + error
            }))
        pump()
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
    private var pendingHistoryFlushes = 0
    private var historyPersistenceStalled = false
    private var lastChunkCount = 0
    private var lastSyncAttempt: Date?
    private var emptySyncStreak = 0
    private var automaticSyncTimer: Timer?
    private var continuationAttempts = 0
    private var continuationFrontier: Int?
    private var historySyncGeneration = 0
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

    /// Export the exact retained channels and staged labels for this displayed
    /// night. The file stays local until the user explicitly shares it.
    func exportSleepDiagnostics() async throws -> URL {
        guard !isAnalyzingHistory, let session = latestSleepSession else { throw SleepDiagnostics.ExportError.noNight }
        // The in-memory analysis window may start exactly at detected sleep
        // onset. Fetch the preceding 30 minutes from the durable raw archive
        // instead of exporting only the currently retained analysis samples.
        let lookback = 30 * 60
        let (candidateStart, overflow) = session.startUnix.subtractingReportingOverflow(lookback)
        let archiveStart = overflow ? Int.min : candidateStart
        let archiveRows = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[V18Sample], Error>) in
            archiveWriter.samples(from: archiveStart, through: session.endUnix - 1) { result in
                continuation.resume(with: result)
            }
        }
        let samples = HistoricalCaptureRecovery.merged(retainedHistoricalSamples + archiveRows)
            .values.sorted { $0.unix < $1.unix }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sleep-exports", isDirectory: true)
        return try await Task.detached(priority: .utility) {
            try SleepDiagnostics.write(samples: samples, session: session, directory: directory,
                                       preSleepSeconds: lookback)
        }.value
    }

    private var historicalArchiveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("strap-history-v18.json")
    }

    /// Serial disk work never blocks BLE callbacks or SwiftUI. The writer owns
    /// the latest archive so recovery and a live drain cannot overwrite each other.
    private func mergeHistoricalArchive(
        _ incoming: [V18Sample], retriesRemaining: Int = 2, completion: @escaping () -> Void
    ) {
        pendingArchiveWrites += 1
        isSavingHistory = true
        archiveWriter.merge(incoming) { [weak self] result in
            guard let self else { return }
            self.pendingArchiveWrites -= 1
            self.isSavingHistory = self.pendingArchiveWrites > 0
            switch result {
            case .success(let merged):
                self.hasUnsavedArchiveRecords = false
                self.retainedHistoricalSamples = merged
                self.lastHistoryRecordCount = merged.count
                completion()
            case .failure(let error):
                self.hasUnsavedArchiveRecords = true
                self.lastMessage = "History archive save failed: \(error.localizedDescription)"
                self.historySyncError = "History save failed: \(error.localizedDescription). Saved raw data will be retried."
                if retriesRemaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.mergeHistoricalArchive([], retriesRemaining: retriesRemaining - 1,
                                                     completion: completion)
                    }
                }
            }
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
    private var pendingHistoryRRRecords = 0
    private var pendingHistoryRRDeclared = 0
    private var pendingHistoryRRAccepted = 0
    private var pendingHistoryRRRejected = 0
    private var pendingHistoryUndecodableFrames = 0
    private var pendingHistoryVersionCounts: [Int: Int] = [:]
    private var lastHRRecoveryAt: Date?
    private var hrRecoveryAttempts = 0
    private var hrDiscoveryRequestedAt: Date?
    private var hrResubscribePending = false
    private var hrSubscribedBeforeBond = false
    @Published private(set) var hrBondConfirmed = false
    private var hrSubscriptionConfirmedAt: Date?
    private(set) var hrConnectedAt: Date?
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
        archiveWriter.importLegacyLiveRR(archivedLiveRRSamples) { [weak self] result in
            switch result {
            case .success(let count):
                self?.persistedLiveRRCount = count
                self?.liveRRMigrationComplete = true
            case .failure(let error):
                self?.historySyncError = "Live R-R archive migration failed; original preferences preserved: " + error.localizedDescription
            }
        }
        lastCapturePath = UserDefaults.standard.string(forKey: Keys.capturePath)
        lastHistorySyncAt = UserDefaults.standard.object(forKey: "strap.history.lastComplete.v1") as? Date
        preferredBandID = UserDefaults.standard.string(forKey: Keys.preferredBandID)
        preferredBandName = UserDefaults.standard.string(forKey: Keys.preferredBandName)
        firmwareRevision = UserDefaults.standard.string(forKey: Keys.cachedFirmware)
        hardwareRevision = UserDefaults.standard.string(forKey: Keys.cachedHardware)
        serialNumber = UserDefaults.standard.string(forKey: Keys.cachedSerial)
        modelNumber = UserDefaults.standard.string(forKey: Keys.cachedModel)
        isBroadcastingHR = UserDefaults.standard.bool(forKey: Keys.broadcastHREnabled)
        if preferredBandID == nil {
            status = .unpaired
        }
        applySavedSleepBounds()
        central = CBCentralManager(delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier])
        recoverSavedCaptures()
    }

    deinit {
        automaticSyncTimer?.invalidate()
        drainTimer?.invalidate()
        liveHRWatchdog?.invalidate()
        #if DEBUG
        uiStressTimer?.invalidate()
        #endif
        reconnectWork?.cancel()
        scanTimeout?.cancel()
        pickerTimeout?.cancel()
        commandDeadline?.cancel()
    }

    /// Raw chunks are saved before the strap's trim ACK. Recover them after
    /// an app interruption or a decoder update, before relying on old summaries.
    private func recoverSavedCaptures() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures", isDirectory: true)
        analysisQueue.async { [weak self] in
            let recovered = HistoricalCaptureRecovery.read(directory: directory)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.mergeHistoricalArchive(recovered) { [weak self] in
                    self?.recalculateRetainedMetrics()
                }
            }
        }
    }

    #if DEBUG
    private var uiStressTimer: Timer?
    /// UI regression replay: 250 published mutations/second, without BLE I/O,
    /// sample persistence or changing a user's stored measurements.
    func startUIStressReplay() {
        uiStressTimer?.invalidate()
        var tick = 0
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self else { return }
            tick += 1
            self.liveHeartRate = 60 + tick % 20
            self.liveHRNotificationCount = tick
            self.historyRRRecords = tick * 100
            self.pendingHistoryRRRecords = tick * 100
            self.historyVersionCounts[18] = tick
            self.pendingHistoryVersionCounts[18] = tick
            self.drainStats = DrainStats(frames: tick * 100, samples: tick * 100, acks: tick)
        }
        RunLoop.main.add(timer, forMode: .common)
        uiStressTimer = timer
    }
    #endif

    // MARK: - Settings

    private var lastRecalculationSettings: String?

    func configure(sex: Sex, maxHR: Double?, restingHR: Double? = nil, needHours: Double) {
        self.sex = sex
        self.maxHR = maxHR
        if let restingHR = restingHR {
            self.configuredRestingHR = restingHR
        }
        self.needHours = needHours
        // Avoid reprocessing the full BLE archive whenever SwiftUI reconfigures
        // the same BandLink instance with unchanged settings.
        let settingsKey = "\(sex)|\(String(describing: maxHR))|\(String(describing: configuredRestingHR))|\(needHours)"
        guard lastRecalculationSettings != settingsKey else { return }
        lastRecalculationSettings = settingsKey
        // Migrate old results and refresh changed settings off the main thread.
        // The versioned session replaces all legacy quiet-fraction totals together.
        recalculateRetainedMetrics()
    }

    /// Rebuild derived scores from the retained raw archive without requiring
    /// another BLE drain. This also migrates cached values after algorithm fixes.
    func recalculateRetainedMetrics() {
        // Repeated settings, recovery and drain callbacks request one follow-up,
        // rather than queueing multiple full-night analyses behind stale work.
        guard !isAnalyzingHistory else {
            metricsRefreshPending = true
            return
        }
        metricsRequest += 1
        guard !retainedHistoricalSamples.isEmpty else {
            isAnalyzingHistory = false
            return
        }
        let request = metricsRequest
        let correctionRevision = sleepCorrectionRevision
        isAnalyzingHistory = true
        let began = Date()
        historyProgress = HistoryProgress(stage: .preparing, completed: 0, total: 0, reused: 0,
                                          startedAt: began, lastStepAt: began)
        let databaseURL = archiveWriter.databaseURL
        let samples = retainedHistoricalSamples
        let sexSnapshot = sex
        let maxSnapshot = maxHR
        let needSnapshot = needHours
        let baselineSnapshot = awakeBaseline
        let daysSnapshot = days
        let sessionsSnapshot = summary?.sleepSessions ?? []
        let corrections = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey)
            as? [String: [Int]] ?? [:]
        analysisQueue.async { [weak self] in
            let cache: HistoryAnalysisCache?
            var cacheSetupError: String?
            do { cache = try HistoryAnalysisCache(url: databaseURL) }
            catch { cache = nil; cacheSetupError = error.localizedDescription }
            var reusedNights = 0
            var rebuilt = CaptureSummary.make(
                samples: samples, sex: sexSnapshot, maxHR: maxSnapshot,
                awakeBaseline: baselineSnapshot, sleepCorrections: corrections,
                analysisCache: cache, sleepProgress: { completed, total, reused in
                    if reused { reusedNights += 1 }
                    let snapshot = HistoryProgress(stage: .nights, completed: completed, total: total,
                                                   reused: reusedNights, startedAt: began, lastStepAt: Date())
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.metricsRequest == request else { return }
                        self.historyProgress = snapshot
                    }
                }
            )
            rebuilt.sleepSessions = SleepSession.retainingUncovered(
                previous: sessionsSnapshot, fresh: rebuilt.sleepSessions ?? [],
                coverageStart: rebuilt.firstUnix, coverageEnd: rebuilt.lastUnix,
                samples: samples, overrides: corrections, cache: cache
            )
            rebuilt.sleepStaging = rebuilt.latestSleepSession?.staging
            var fresh = rebuilt
            var reusedDays = 0
            let daysBegan = Date()
            var freshDays = DailyAnalysis.metrics(
                from: samples, sex: sexSnapshot, maxHR: maxSnapshot,
                sleepCorrections: corrections, analyzedSleepSessions: fresh.sleepSessions,
                analysisCache: cache, progress: { completed, total, reused in
                    if reused { reusedDays += 1 }
                    let snapshot = HistoryProgress(stage: .days, completed: completed, total: total,
                                                   reused: reusedDays, startedAt: daysBegan, lastStepAt: Date())
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.metricsRequest == request else { return }
                        self.historyProgress = snapshot
                    }
                }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.metricsRequest == request else { return }
                self.historyProgress = HistoryProgress(stage: .finishing, completed: 0, total: 0, reused: 0,
                                                      startedAt: began, lastStepAt: Date())
            }
            let editedDays = Set(freshDays.filter { day in
                fresh.sleepSessions?.contains {
                    $0.isEdited && $0.startUnix == day.sleepStartUnix
                        && $0.endUnix - 1 == day.sleepEndUnix
                } ?? false
            }.map(\.dateKey))
            let previousEditedDays = Set(sessionsSnapshot.filter(\.isEdited).compactMap { session in
                JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1)), calendar: .current)
            })
            var byDay: [String: DayMetrics] = [:]
            for day in daysSnapshot { byDay[day.dateKey] = day }
            for day in freshDays {
                let previousIsEdited = previousEditedDays.contains(day.dateKey)
                if let previous = byDay[day.dateKey], previous.sleepStartUnix != nil,
                   !DailyAnalysis.replacesSleep(previous: previous, fresh: day,
                                                coverageStart: fresh.firstUnix, coverageEnd: fresh.lastUnix,
                                                isEdited: editedDays.contains(day.dateKey),
                                                previousIsEdited: previousIsEdited) {
                    continue
                }
                byDay[day.dateKey] = day
            }
            let allDays = byDay.values.sorted { $0.dateKey < $1.dateKey }
            let awakeNorm = DailyAnalysis.awakeBaseline(from: Array(allDays.suffix(DailyAnalysis.rollingBaselineDays)))
            let sleepWindows = (fresh.sleepSessions ?? []).map { (start: $0.startUnix, end: $0.endUnix - 1) }
            let excluded = sleepWindows + fresh.activities.map { (start: $0.startUnix, end: $0.endUnix) }
            fresh.awakeStress = StressWindows.share(samples: samples, baseline: awakeNorm, excluded: sleepWindows)
            fresh.outsideWorkoutStress = StressWindows.share(samples: samples, baseline: awakeNorm, excluded: excluded)
            let stressPoints = StressWindows.series(samples: samples, baseline: awakeNorm, excluded: sleepWindows)
            fresh.stressSeries = stressPoints.isEmpty ? nil : stressPoints
            // Use the newly analyzed nights for sleep consistency. The
            // previously persisted day can still describe the pre-edit bounds.
            let nights = Array(allDays.map { day in
                freshDays.first(where: { $0.dateKey == day.dateKey }) ?? day
            }.suffix(14)).compactMap(\.night)
            let sleepBaseline = DailyAnalysis.baseline(
                from: Array(allDays.filter { $0.state == "sleep" }.suffix(DailyAnalysis.rollingBaselineDays))
            )
            let report = fresh.latestSleepSession.flatMap {
                SleepReport.analyze(
                    samples: samples, session: $0, needHours: needSnapshot,
                    nights: nights, sleepBaseline: sleepBaseline
                )
            }
            let diagnosticPeriods = fresh.sleepPeriods
            let restSamples = diagnosticPeriods.isEmpty ? samples : samples.filter { sample in
                diagnosticPeriods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
            }
            let restReason = (diagnosticPeriods.isEmpty ? "Sleep session not detected; " : "")
                + Hrv.restingQualityReason(restSamples)
            // Persist the same night-bound report used by Sleep Analysis, so
            // weekly Recovery charts never substitute a different sleep score.
            for index in freshDays.indices {
                let day = freshDays[index]
                guard let session = fresh.sleepSessions?.first(where: {
                    $0.startUnix == day.sleepStartUnix && $0.endUnix - 1 == day.sleepEndUnix
                }) else { continue }
                let segment = samples.filter { session.startUnix <= $0.unix && $0.unix < session.endUnix }
                let respiration = Respiration.estimate(segment)
                freshDays[index].respiratoryRate = respiration.breathsPerMinute
                freshDays[index].respiratoryWindows = respiration.windows
                let datedNights = Array(allDays.map { existing in
                    freshDays.first(where: { $0.dateKey == existing.dateKey }) ?? existing
                }.filter { $0.dateKey <= day.dateKey }.suffix(14)).compactMap(\.night)
                let datedReport = SleepReport.analyze(samples: samples, session: session,
                    needHours: needSnapshot, nights: datedNights, sleepBaseline: sleepBaseline)
                freshDays[index].sleepPerformancePct = datedReport?.performancePct
            }
            let scoredDays = freshDays
            let finalFresh = fresh
            let checkpointError = cacheSetupError ?? cache?.lastError
            DispatchQueue.main.async { [weak self] in
                guard let self, self.metricsRequest == request else { return }
                guard self.sleepCorrectionRevision == correctionRevision else {
                    // Never publish/persist a calculation begun before a new edit.
                    self.isAnalyzingHistory = false
                    self.historyProgress = nil
                    self.metricsRefreshPending = false
                    self.recalculateRetainedMetrics()
                    return
                }
                self.historicalRestQualityReason = restReason
                self.summary = finalFresh
                self.merge(scoredDays, coverageStart: finalFresh.firstUnix, coverageEnd: finalFresh.lastUnix,
                           editedDays: editedDays)
                self.lastSleepAnalysis = report
                self.persist(finalFresh)
                if let report { self.preferencesWriter.write(report, forKey: Keys.sleepAnalysis) } else {
                    self.preferencesWriter.remove(forKey: Keys.sleepAnalysis)
                }
                self.isAnalyzingHistory = false
                self.historyProgress = nil
                if let checkpointError {
                    self.historySyncError = "Results updated, but analysis checkpoints could not be saved: \(checkpointError)"
                }
                if self.metricsRefreshPending {
                    self.metricsRefreshPending = false
                    self.recalculateRetainedMetrics()
                }
            }
        }
    }

    // MARK: - Derived values

    var isConnected: Bool { peripheral?.state == .connected }

    var baseline: Baseline? {
        DailyAnalysis.baseline(from: Array(days.suffix(DailyAnalysis.rollingBaselineDays)))
    }

    /// Stress uses verified awake-quiet windows; overnight HRV is a separate baseline.
    var awakeBaseline: Baseline? {
        DailyAnalysis.awakeBaseline(from: Array(days.suffix(DailyAnalysis.rollingBaselineDays)))
    }

    var sleepBaseline: Baseline? {
        DailyAnalysis.baseline(from: Array(days.filter { $0.state == "sleep" }.suffix(DailyAnalysis.rollingBaselineDays)))
    }

    var recentNights: [NightSpan] {
        days.suffix(14).compactMap { $0.night }
    }

    var stress: StressResult {
        guard let baseline = awakeBaseline, baseline.days >= Recovery.minBaselineDays else {
            return Recovery.stressIndex(lnRMSSD: nil, baseline: awakeBaseline)
        }
        guard let point = summary?.stressSeries?.last else {
            return StressResult(index: nil, reason: "Needs recorded awake R-R windows")
        }
        return StressResult(index: point.index, reason: nil)
    }

    /// Corrected bounds select the sensor samples used for nightly metrics;
    /// neither the heart rates nor R-R measurements are modified.
    var lastNightHours: Double? { latestSleepSession?.asleepHours }

    func notifySleepCorrectionChanged() {
        sleepCorrectionRevision += 1
        applySavedSleepBounds()
        guard let session = latestSleepSession else { recalculateRetainedMetrics(); return }
        let revision = sleepCorrectionRevision
        // Edited nights can be older than the active 72-hour analysis window.
        // Load their own durable samples rather than requiring a new BLE drain.
        archiveWriter.samples(from: session.startUnix, through: session.endUnix - 1) { [weak self] result in
            guard let self, self.sleepCorrectionRevision == revision else { return }
            switch result {
            case .success(let rows):
                self.retainedHistoricalSamples = HistoricalCaptureRecovery.merged(self.retainedHistoricalSamples + rows)
                    .values.sorted { $0.unix < $1.unix }
            case .failure(let error):
                self.historySyncError = "Saved sleep times preserved; sensor history could not be read: \(error.localizedDescription)"
            }
            self.recalculateRetainedMetrics()
        }
    }

    private func applySavedSleepBounds() {
        guard var saved = summary, let sessions = saved.sleepSessions else { return }
        let overrides = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
        let updated = sessions.map { $0.applyingSavedBounds(overrides) }
        guard updated != sessions else { return }
        saved.sleepSessions = updated
        saved.sleepStaging = saved.latestSleepSession?.staging
        summary = saved
        lastSleepAnalysis = nil
        preferencesWriter.remove(forKey: Keys.sleepAnalysis)
        persist(saved)
    }

    /// Returning from the lock screen must use the data already received,
    /// rather than relying on startup recovery after a force-quit.
    func resumeHistoryProcessing() {
        if drainStartedAt != nil {
            tickDrain(forceCheckpoint: true)
        } else if hasUnsavedArchiveRecords && !isSavingHistory {
            mergeHistoricalArchive([]) { [weak self] in
                self?.recalculateRetainedMetrics()
            }
        } else if status.isReady, isConnected,
                  HistorySyncPolicy.shouldSync(now: Date(), lastAttempt: lastSyncAttempt, foreground: true) {
            readHistory()
        }
    }

    var recovery: RecoveryResult {
        if isAnalyzingHistory {
            return RecoveryResult(score: nil, reason: "Recalculating retained history",
                                  hrvComponent: nil, rhrComponent: nil, sleepComponent: nil)
        }
        return latestSleepSession.map { recoveryAssessment(for: $0).result }
            ?? Recovery.score(lnRMSSD: nil, rhr: nil, sleepHours: nil, sleepNeedHours: needHours, baseline: nil)
    }

    var recoveryNight: DayMetrics? {
        guard !isAnalyzingHistory, let session = latestSleepSession else { return nil }
        return recoveryNight(for: session, calendar: .current)
    }

    private func recoveryNight(for session: SleepSession, calendar: Calendar) -> DayMetrics? {
        let date = Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1))
        let key = JournalStore.dayKey(for: date, calendar: calendar)
        return days.last {
            $0.dateKey == key && $0.state == "sleep"
                && $0.sleepStartUnix == session.startUnix && $0.sleepEndUnix == session.endUnix - 1
        }
    }

    private func recoveryAssessment(for session: SleepSession, calendar: Calendar = .current) -> DatedRecovery {
        let date = Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1))
        return DatedRecovery.evaluate(day: recoveryNight(for: session, calendar: calendar), priorDays: days,
                                      date: date, sleepNeedHours: needHours, calendar: calendar)
    }

    func exportRecoveryDiagnostics() async throws -> URL {
        guard !isAnalyzingHistory, let session = latestSleepSession else { throw SleepDiagnostics.ExportError.noNight }
        let calendar = Calendar.current
        let assessment = recoveryAssessment(for: session, calendar: calendar)
        let oldDay = days.first {
            $0.dateKey == assessment.dateKey && $0.sleepStartUnix == session.startUnix
                && $0.sleepEndUnix == session.endUnix - 1
        }
        let legacy = DatedRecovery.replayLegacyHome(day: oldDay, priorDays: days,
            dateKey: assessment.dateKey, sleepNeedHours: needHours)
        let sync = lastHistorySyncAt
        let revision = Bundle.main.object(forInfoDictionaryKey: "StrapBuildRevision") as? String
        let archived = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[V18Sample], Error>) in
            archiveWriter.samples(from: session.startUnix, through: session.endUnix - 1) {
                continuation.resume(with: $0)
            }
        }
        let samples = HistoricalCaptureRecovery.merged(archived).values.sorted { $0.unix < $1.unix }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recovery-exports", isDirectory: true)
        return try await Task.detached(priority: .utility) {
            let deep = session.staging.segments.filter { $0.stage == .deep && $0.endUnix > $0.startUnix }
                .map { $0.startUnix...($0.endUnix - 1) }
            let hrv = Hrv.swsRestingHRV(samples, deepEpochs: deep, minWindowS: 300)
            let report = RecoveryDiagnostics.Report(
                buildRevision: revision, timezone: calendar.timeZone.identifier,
                lastCompletedHistorySync: sync, assessment: assessment,
                breakdown: RecoveryDiagnostics.Breakdown(assessment: assessment), legacyHomeReplay: legacy,
                legacyHomeBreakdown: RecoveryDiagnostics.Breakdown(assessment: legacy), session: session,
                archiveFirstUnix: samples.first?.unix, archiveLastUnix: samples.last?.unix,
                archiveFirstRecordIndex: samples.first?.header.recordIndex,
                archiveLastRecordIndex: samples.last?.header.recordIndex,
                archiveSampleCount: samples.count, recomputedHRV: hrv.result,
                recomputedHRVWindowSeconds: hrv.windowSeconds, recomputedHRVUsedDeepSleep: hrv.isSWS,
                quietWindows: Hrv.restingWindowDiagnostics(samples, minWindowS: 300),
                deepQuietWindows: Hrv.restingWindowDiagnostics(
                    samples.filter { sample in deep.contains { $0.contains(sample.unix) } }, minWindowS: 300),
                recomputedRHR: Hrv.restingHeartRate(samples, windowS: 300))
            return try RecoveryDiagnostics.write(report, to: directory)
        }.value
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
                    sleepEndUnix: old.sleepEndUnix, strain: old.strain, steps: old.steps,
                    sleepDurationReliable: old.sleepDurationReliable,
                    respiratoryRate: old.respiratoryRate,
                    sleepPerformancePct: old.sleepPerformancePct,
                    zoneSeconds: old.zoneSeconds,
                    awakeLnRMSSD: old.awakeLnRMSSD,
                    awakeRestingHR: old.awakeRestingHR,
                    restingHRWindowSeconds: old.restingHRWindowSeconds,
                    respiratoryWindows: old.respiratoryWindows,
                    skinTemperatureC: old.skinTemperatureC,
                    skinTemperatureSeconds: old.skinTemperatureSeconds,
                    skinTemperatureSource: old.skinTemperatureSource,
                    oxygenCandidatePct: old.oxygenCandidatePct,
                    zoneCoverageStartUnix: old.zoneCoverageStartUnix,
                    zoneCoverageEndUnix: old.zoneCoverageEndUnix
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
            preferencesWriter.write(days, forKey: Keys.days)
        }
        return inserted
    }

    // MARK: - Connection

    func connect(sex: Sex, maxHR: Double?, restingHR: Double? = nil, needHours: Double) {
        staleHRReconnects = 0
        hrRecoveryAttempts = 0
        configure(sex: sex, maxHR: maxHR, restingHR: restingHR, needHours: needHours)
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
            status = liveHeartRate != nil ? .streaming(bpm: liveHeartRate!) : .connected(band.name)
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
        firmwareRevision = nil
        hardwareRevision = nil
        serialNumber = nil
        modelNumber = nil
        UserDefaults.standard.removeObject(forKey: Keys.preferredBandID)
        UserDefaults.standard.removeObject(forKey: Keys.preferredBandName)
        UserDefaults.standard.removeObject(forKey: Keys.cachedFirmware)
        UserDefaults.standard.removeObject(forKey: Keys.cachedHardware)
        UserDefaults.standard.removeObject(forKey: Keys.cachedSerial)
        UserDefaults.standard.removeObject(forKey: Keys.cachedModel)
    }

    /// Set verified Broadcast Heart Rate (Command 14 / 0x0E).
    func setBroadcastHeartRate(enabled: Bool) {
        isBroadcastingHR = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.broadcastHREnabled)
        guard isConnected, commandCharacteristic != nil else { return }
        enqueue(BandCommand.setGenericHRProfile.rawValue, body: [enabled ? 0x01 : 0x00])
    }

    /// Safely sends REBOOT_STRAP (Command 29 / 0x1D) to restart the WHOOP strap.
    /// Non-destructive: circular flash history buffers in SPI NOR flash survive warm MCU reset.
    func rebootBand() {
        guard isConnected, commandCharacteristic != nil else {
            rebootMessage = "WHOOP is not connected"
            return
        }
        isRebooting = true
        rebootMessage = "Sending reboot command to WHOOP..."
        enqueue(BandCommand.rebootStrap.rawValue, body: [], response: true, onWrite: { [weak self] in
            self?.rebootExpectedDisconnect = true
            self?.rebootMessage = "Reboot command sent. Awaiting band restart..."
        })
    }

    /// Explicit unpair clears the saved association, terminates any active connection,
    /// and completely disables automatic reconnection until a new device is paired.
    func unpair() {
        wantsConnection = false
        forgetPreferredBand()
        reconnectWork?.cancel()
        reconnectWork = nil
        reconnectAttempt = 0
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetLink()
        stopPicker()
        status = .unpaired
        lastMessage = "Band unpaired. Double-tap your WHOOP to enter pairing mode when ready to pair."
    }

    /// Automatically restore and maintain connection to the saved WHOOP band without manual taps.
    func autoConnectIfNeeded() {
        guard let id = preferredBandID, !id.isEmpty else {
            if peripheral == nil && status != .scanning {
                status = .unpaired
            }
            return
        }
        wantsConnection = true

        // 1. If already connected, refresh telemetry, ensure streams, and prevent duplicate sessions
        if let peripheral, peripheral.state == .connected {
            refreshBattery()
            ensureHeartRateStream()
            if status != .draining && status != .authenticating {
                if let bpm = liveHeartRate {
                    status = .streaming(bpm: bpm)
                } else {
                    status = .connected(bandName ?? preferredBandName ?? "WHOOP MG")
                }
            }
            return
        }

        // 2. If already in flight, reuse existing connection attempt
        if let peripheral, peripheral.state == .connecting {
            return
        }

        // 3. Central check
        guard central.state == .poweredOn else {
            if central.state == .poweredOff { status = .poweredOff }
            return
        }

        // 4. Reset retry counter and attempt immediate reconnect
        reconnectWork?.cancel()
        reconnectWork = nil
        reconnectAttempt = 0
        reconnectSavedPeripheralOrScan()
    }

    /// Dedicated WHOOP pairing scan triggered by "Pair a Device" flow.
    func startPairingScan() {
        guard central.state == .poweredOn else {
            lastMessage = status.title
            return
        }
        stopPicker()
        pickerMode = true
        isFindingBands = true
        wantsConnection = true
        discoveredBands = []
        discoveredPeripherals = [:]
        status = .scanning
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
                self.lastMessage = "No WHOOP bands found. Double-tap your band until the side LED blinks blue to enter pairing mode."
            }
        }
        pickerTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    func stopPairingScan() {
        stopPicker()
        if !isConnected && preferredBandID == nil {
            status = .unpaired
        }
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
    private func archiveLiveRR(unix: Int, heartRate: Int, intervals: [Int], source: String) {
        guard !intervals.isEmpty else { return }
        let entry = LiveSample(unix: unix, heartRate: heartRate, rrIntervalsMS: intervals)
        pendingLiveRRRecords.append(.received(entry, source: source))
        if liveRRFlushWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.persistLiveRRArchive(force: true) }
            liveRRFlushWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
        if archivedLiveRRSamples.last?.unix == unix {
            if intervals.count > archivedLiveRRSamples[archivedLiveRRSamples.count - 1].rrIntervalsMS.count {
                archivedLiveRRSamples[archivedLiveRRSamples.count - 1] = entry
            }
        } else { archivedLiveRRSamples.append(entry) }
        archivedLiveRRSamples = Array(archivedLiveRRSamples.suffix(3600))
        persistLiveRRArchive()
    }
    func persistLiveRRArchive(force: Bool = false) {
        guard !archivedLiveRRSamples.isEmpty,
              force || Date().timeIntervalSince(lastLiveRRSaveAt) >= 5 else { return }
        lastLiveRRSaveAt = Date()
        liveRRFlushWork?.cancel(); liveRRFlushWork = nil
        let records = pendingLiveRRRecords
        pendingLiveRRRecords = []
        archiveWriter.persistLiveRR(records) { [weak self] result in
            switch result {
            case .success(let count):
                self?.persistedLiveRRCount = count
                self?.liveRRMigrationComplete = true
            case .failure(let error):
                self?.historySyncError = "Live R-R save failed; pending records retained for retry: " + error.localizedDescription
            }
        }
        if liveRRMigrationComplete { preferencesWriter.write(archivedLiveRRSamples, forKey: Keys.liveRRArchive) }
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
        accumulateLiveStrain(bpm: bpm, unix: now)
    }

    private func effectiveRestingHR(for dayKey: String) -> Double? {
        if let configured = configuredRestingHR, configured.isFinite, configured > 0 {
            return configured
        }
        if let day = days.first(where: { $0.dateKey == dayKey }) {
            if let rhr = day.restingHR, rhr.isFinite, rhr > 0 { return rhr }
            if let awake = day.awakeRestingHR, awake.isFinite, awake > 0 { return awake }
        }
        if let rhr = summary?.restingHeartRate, rhr.isFinite, rhr > 0 {
            return rhr
        }
        return days.lazy.filter { $0.state == "sleep" && $0.restingHR != nil }.last?.restingHR
    }

    private func accumulateLiveStrain(bpm: Int, unix: Int) {
        let currentDayKey = JournalStore.dayKey(for: Date(timeIntervalSince1970: Double(unix)))

        if currentDayKey != liveDayStrainKey {
            liveDayStrainKey = currentDayKey
            lastLiveStrainSampleUnix = nil
            if let todayBatchStrain = days.first(where: { $0.dateKey == currentDayKey })?.strain,
               let baseRaw = WhoopDerivedStrain.raw(forScore: todayBatchStrain) {
                liveDayRawStrain = baseRaw
                liveDayStrain = todayBatchStrain
            } else {
                liveDayRawStrain = 0.0
                liveDayStrain = nil
            }
        }

        let effectiveMax = maxHR ?? Karvonen.effectiveMaxHR(configuredMaxHR: nil, age: nil)
        let effectiveResting = effectiveRestingHR(for: currentDayKey) ?? Karvonen.effectiveRestingHR(measuredRestingHR: nil)
        guard effectiveMax > effectiveResting else { return }

        let delta: Double
        if let lastUnix = lastLiveStrainSampleUnix {
            if unix <= lastUnix { return }
            delta = Double(unix - lastUnix)
        } else {
            delta = 1.0
        }
        lastLiveStrainSampleUnix = unix

        liveDayRawStrain = WhoopDerivedStrain.accumulateStep(
            currentRaw: liveDayRawStrain,
            hr: Double(bpm),
            deltaSeconds: delta,
            restingHR: effectiveResting,
            maxHR: effectiveMax
        )

        if let score = WhoopDerivedStrain.display(raw: liveDayRawStrain) {
            let batch = days.first(where: { $0.dateKey == currentDayKey })?.strain ?? 0.0
            liveDayStrain = max(batch, score)
        }
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
            hrv: Hrv.fromLiveSamples(liveSamples)
        )
        lastLiveSession = result
        sessionStartedUnix = nil
        liveSamples = []
        return result
    }

    var currentLiveHRV: HrvResult {
        Hrv.fromLiveSamples(liveSamples)
    }

    // MARK: - Scan and connect

    private func beginScan() {
        guard central.state == .poweredOn else { return }
        switch status {
        case .ready, .connected, .streaming, .draining, .authenticating: return
        default: break
        }
        if let peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            return
        }
        status = .scanning
        lastMessage = nil
        // Hardware-filtered scan: passing WHOOP Gen5 service and HR service allows
        // the iOS Bluetooth controller to filter packets in hardware and wake the app
        // reliably during background execution without scanning unrelated devices.
        central.scanForPeripherals(
            withServices: [BandUUID.service, BandUUID.heartRateService],
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
                self.status = .connecting(self.preferredBandName ?? saved.name ?? "Saved WHOOP")
                self.central.connect(saved, options: nil)
            } else if self.wantsConnection && self.preferredBandID != nil {
                self.scheduleReconnect()
            } else {
                self.status = .failed("No WHOOP band found. Keep Bluetooth enabled and use Pair a Device if needed.")
            }
        }
        scanTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    /// 3-tier reconnection architecture derived from WHOOP 5.80.2 runtime forensics:
    /// Tier 1: Check connected peripherals via retrieveConnectedPeripherals(withServices:)
    /// Tier 2: Check known peripherals by identifier via retrievePeripherals(withIdentifiers:)
    /// Tier 3: Hardware-filtered BLE scan matching WHOOP transport service UUIDs.
    private func reconnectSavedPeripheralOrScan() {
        guard wantsConnection, central.state == .poweredOn else { return }
        if let peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            return
        }

        // Tier 1: Instant reconnect if iOS already maintains an active BLE link
        let connected = central.retrieveConnectedPeripherals(withServices: [BandUUID.service])
        if let id = preferredBandID, let uuid = UUID(uuidString: id),
           let matched = connected.first(where: { $0.identifier == uuid }) {
            matched.delegate = self
            peripheral = matched
            status = .connecting(preferredBandName ?? matched.name ?? "Saved WHOOP")
            central.connect(matched, options: nil)
            return
        } else if preferredBandID == nil, let first = connected.first {
            first.delegate = self
            peripheral = first
            status = .connecting(first.name ?? "Connected WHOOP")
            central.connect(first, options: nil)
            return
        }

        // Tier 2: Retrieve known peripheral by saved identifier
        if let id = preferredBandID, let uuid = UUID(uuidString: id),
           let saved = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            saved.delegate = self
            peripheral = saved
            status = .connecting(preferredBandName ?? saved.name ?? "Saved WHOOP")
            central.connect(saved, options: nil)
            return
        }

        // Tier 3: Scan for matching WHOOP peripherals
        beginScan()
    }

    private func scheduleReconnect() {
        guard wantsConnection, central.state == .poweredOn else { return }
        reconnectWork?.cancel()
        reconnectAttempt = min(reconnectAttempt + 1, ReconnectBackoffPolicy.maximumAttempts)
        status = .reconnecting(attempt: reconnectAttempt)
        if reconnectAttempt >= 3 {
            let target = peripheral ?? (preferredBandID.flatMap { UUID(uuidString: $0) }.flatMap { central.retrievePeripherals(withIdentifiers: [$0]).first })
            if let target, target.state == .disconnected {
                self.peripheral = target
                target.delegate = self
                status = .connecting(preferredBandName ?? target.name ?? "Saved WHOOP")
                central.connect(target, options: nil)
                return
            }
        }
        let delay = ReconnectBackoffPolicy.delay(forAttempt: reconnectAttempt)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsConnection, self.central.state == .poweredOn else { return }
            self.reconnectSavedPeripheralOrScan()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resetLink() {
        linkGeneration = UUID()
        commandDeadline?.cancel()
        commandDeadline = nil
        currentWriteID = nil
        commandWriteTimedOut = false
        lastType40HRAt = nil
        type40HRPackets = 0
        standardHRPackets = 0
        persistLiveRRArchive(force: true)
        // Status can already be .failed after a rejected BLE command.
        // The drain clock, not the presentation status, owns its lifecycle.
        if drainStartedAt != nil { finishDrain(reason: "link reset") }
        drainTimer?.invalidate()
        drainTimer = nil
        automaticSyncTimer?.invalidate()
        automaticSyncTimer = nil
        #if DEBUG
        uiStressTimer?.invalidate()
        uiStressTimer = nil
        #endif
        liveHRWatchdog?.invalidate()
        liveHRWatchdog = nil
        liveRRFlushWork?.cancel()
        liveRRFlushWork = nil
        pickerTimeout?.cancel()
        pickerTimeout = nil
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
        recentLiveHR.removeAll(keepingCapacity: true)
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
        commandQueue.forEach { $0.onFailure?("Band disconnected. Reconnect and try again.") }
        commandQueue = []
        commandInFlight = false
        alarmWritePending = false
        testingBuzz = false
        nextBandAlarm = nil
        syncedAlarmMinutes = nil
        alarmWasDisabled = false
        lastAlarmAttempt = nil
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
        // The clientHello acknowledgement moves status to .connected before
        // scheduling this callback. Requiring .authenticating here silently
        // prevented the initial history request on a successfully bonded link.
        guard hrBondConfirmed, peripheral?.state == .connected,
              commandCharacteristic != nil, status != .draining else { return }
        startDraining()
    }

    /// Pull stored history again on an already-authenticated link. Used for a
    /// second read while the strap stays connected.
    func readHistory() {
        guard peripheral?.state == .connected, commandCharacteristic != nil else {
            connect(sex: sex, maxHR: maxHR, needHours: needHours)
            return
        }
        guard status != .draining else {
            lastMessage = "History transfer already in progress."
            return
        }
        guard status != .authenticating else {
            historySyncError = "WHOOP handshake is still pending. History sync cannot start until the band acknowledges pairing."
            lastMessage = historySyncError ?? "WHOOP handshake pending"
            return
        }
        startDraining()
    }

    func retryHistorySync() {
        if drainStartedAt != nil { finishDrain(reason: "retry requested") }
        readHistory()
    }

    private func armAutomaticSync() {
        guard automaticSyncTimer == nil else { return }
        let timer = Timer(timeInterval: HistorySyncPolicy.periodicSeconds, repeats: true) { [weak self] _ in
            guard let self, self.status.isReady, self.isConnected,
                  !self.isSavingHistory, !self.isAnalyzingHistory,
                  HistorySyncPolicy.shouldSync(now: Date(), lastAttempt: self.lastSyncAttempt,
                                               emptyStreak: self.emptySyncStreak) else { return }
            self.readHistory()
        }
        automaticSyncTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func recordCompletedHistorySync() {
        let now = Date()
        lastHistorySyncAt = now
        UserDefaults.standard.set(now, forKey: "strap.history.lastComplete.v1")
        historySyncError = nil
    }

    private func startDraining(continuing: Bool = false) {
        if drainStartedAt != nil { finishDrain(reason: "starting a new sync") }
        if !continuing {
            continuationAttempts = 0
            continuationFrontier = retainedHistoricalSamples.last?.unix
        }
        resubscribeNotifyCharacteristics()
        startCaptureFile()
        lastSyncAttempt = Date()
        historySyncError = nil
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
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickDrain()
        }
        drainTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
              isBroadcastingHR, !hrProfileEnabled, !hrEnableQueued else { return }
        hrEnableQueued = true
        enqueue(BandCommand.setGenericHRProfile.rawValue, body: [0x01])
    }

    private func startHRWatchdog() {
        liveHRWatchdog?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isConnected else { return }
            self.syncWakeAlarm()
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
            let action = LiveHeartRateState.recovery(now: now, connectedAt: self.hrConnectedAt,
                receivedAt: self.lastLiveHRAt, lastAttempt: self.lastHRRecoveryAt,
                attempts: self.hrRecoveryAttempts, reconnects: self.staleHRReconnects)
            if action == .reconnect, let peripheral = self.peripheral {
                self.staleHRReconnects += 1
                self.lastMessage = "HR stream stayed silent after re-arming; reconnecting the strap."
                self.central.cancelPeripheralConnection(peripheral)
                return
            }
            if action == .unavailable {
                self.lastMessage = "Live HR unavailable after bounded recovery. Check wrist contact and reconnect."
                return
            }
            guard action == .rearm else { return }
            self.lastHRRecoveryAt = now
            self.hrRecoveryAttempts += 1
            self.hrResubscribePending = false // A missing CCCD callback cannot lock recovery forever.

            if let hr = self.hrCharacteristic {
                // The CCCD can remain enabled even when 0x2A37 stops sending.
                // Re-enable through the notification-state callback.
                if hr.isNotifying && !self.hrResubscribePending {
                    self.hrResubscribePending = true
                    self.peripheral?.setNotifyValue(false, for: hr)
                } else if !hr.isNotifying && !self.hrResubscribePending {
                    self.peripheral?.setNotifyValue(true, for: hr)
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
        liveHRWatchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func enqueue(_ opcode: UInt8, body: [UInt8] = [], response: Bool = true, onWrite: (() -> Void)? = nil) {
        commandQueue.append(PendingCommand(opcode: opcode, body: body, expectResponse: response, onWrite: onWrite))
        pump()
    }

    private func pump() {
        guard !commandInFlight, let next = commandQueue.first,
              let peripheral, let characteristic = commandCharacteristic else { return }
        commandInFlight = true
        let writeID = UUID()
        currentWriteID = writeID
        let inner: [UInt8] = [BandPacket.command, commandSeq, next.opcode] + next.body
        commandSeq &+= 1
        let frame = Gen5Frame.build(inner)
        if next.expectResponse {
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.currentWriteID == writeID, self.commandInFlight,
                      let peripheral = self.peripheral else { return }
                self.commandWriteTimedOut = true
                self.liveHeartRate = nil
                self.lastMessage = "WHOOP command write timed out; reconnecting without discarding saved history."
                // Do not advance a timed-out ATT queue: a late write callback
                // could otherwise acknowledge the wrong subsequent command.
                self.central.cancelPeripheralConnection(peripheral)
            }
            commandDeadline?.cancel()
            commandDeadline = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + (next.opcode == BandCommand.clientHello.rawValue ? 30 : 10), execute: timeout)
            peripheral.writeValue(Data(frame), for: characteristic, type: .withResponse)
        } else {
            peripheral.writeValue(Data(frame), for: characteristic, type: .withoutResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.commandSpacing) { [weak self] in
                guard let self, self.currentWriteID == writeID else { return }
                self.completeCommandSent()
            }
        }
    }

    private func completeCommandSent() {
        commandDeadline?.cancel()
        commandDeadline = nil
        currentWriteID = nil
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
        historySyncGeneration += 1
        capturedSamples = []
        pendingHistoryFlushes = 0
        historyPersistenceStalled = false
        lastChunkCount = 0
        lastCheckpointCount = 0
        lastCheckpointAt = Date()
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
        pendingHistoryRRRecords = 0
        pendingHistoryRRDeclared = 0
        pendingHistoryRRAccepted = 0
        pendingHistoryRRRejected = 0
        pendingHistoryUndecodableFrames = 0
        pendingHistoryVersionCounts = [:]
        captureWriter?.close()
        captureWriter = CaptureWriter()
        lastCapturePath = captureWriter?.url.path
        if let path = lastCapturePath {
            UserDefaults.standard.set(path, forKey: Keys.capturePath)
        }
    }

    private func tickDrain(forceCheckpoint: Bool = false) {
        guard let started = drainStartedAt else { return }
        let now = Date()
        let idle = now.timeIntervalSince(lastFrameAt ?? started)
        let elapsed = now.timeIntervalSince(started)
        drainStats = DrainStats(
            frames: drainFrames, samples: capturedSamples.count, acks: drainAcks
        )
        // Throttle high-frequency drain diagnostic counters to 1 Hz to prevent
        // flooding SwiftUI with hundreds of objectWillChange notifications per second.
        if historyRRRecords != pendingHistoryRRRecords || historyUndecodableFrames != pendingHistoryUndecodableFrames {
            historyRRRecords = pendingHistoryRRRecords
            historyRRDeclared = pendingHistoryRRDeclared
            historyRRAccepted = pendingHistoryRRAccepted
            historyRRRejected = pendingHistoryRRRejected
            historyUndecodableFrames = pendingHistoryUndecodableFrames
            historyVersionCounts = pendingHistoryVersionCounts
        }
        // A band can keep sending metadata without completing its offload.
        // Analyze durable checkpoints while it is still connected; reopening
        // the app must not be required to discover the night's saved records.
        if capturedSamples.count > lastCheckpointCount,
           (forceCheckpoint || now.timeIntervalSince(lastCheckpointAt) >= 60),
           !isAnalyzingHistory, !isSavingHistory {
            // The archive writer already owns earlier checkpoints. Submit only
            // new packets instead of copying/re-merging the entire drain again.
            let incoming = Array(capturedSamples.dropFirst(lastCheckpointCount))
            lastCheckpointCount = capturedSamples.count
            lastCheckpointAt = now
            mergeHistoricalArchive(incoming) { [weak self] in
                self?.recalculateRetainedMetrics()
            }
        }
        if drainFrames > 0 && pendingHistoryFlushes == 0 && idle >= Self.drainIdleSeconds {
            finishDrain(reason: "idle timeout after \(Int(idle))s")
        } else if drainFrames == 0 && elapsed >= Self.drainEmptySeconds {
            finishDrain(reason: "no history frames after \(Int(elapsed))s")
        } else if elapsed >= Self.drainMaxSeconds {
            finishDrain(reason: "maximum sync duration")
        }
    }

    private func finishDrain(reason: String = "interrupted") {
        guard drainStartedAt != nil else { return }
        let generation = historySyncGeneration
        drainTimer?.invalidate()
        drainTimer = nil
        drainStartedAt = nil
        captureWriter?.close()
        captureWriter = nil

        // Ordering belongs to the archive worker. Release the completed drain
        // buffer instead of holding a second raw-history copy until the next sync.
        let samples = capturedSamples
        capturedSamples = []
        seenRecordIndices.removeAll()
        drainStats = DrainStats(frames: drainFrames, samples: samples.count, acks: drainAcks)
        historyRRRecords = pendingHistoryRRRecords
        historyRRDeclared = pendingHistoryRRDeclared
        historyRRAccepted = pendingHistoryRRAccepted
        historyRRRejected = pendingHistoryRRRejected
        historyUndecodableFrames = pendingHistoryUndecodableFrames
        historyVersionCounts = pendingHistoryVersionCounts
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
        let uniqueSeconds = Set(samples.map(\.unix))
        let missingSeconds: Int
        if let maxSec = uniqueSeconds.max(), let minSec = uniqueSeconds.min() {
            missingSeconds = maxSec - minSec + 1 - uniqueSeconds.count
        } else {
            missingSeconds = 0
        }
        let historyQuality = "R-R: \(rrBeats) beats / \(rrSeconds) seconds; gaps: \(missingSeconds)s"
        let completed = reason == "explicit completion" && !historyPersistenceStalled && historyUndecodableFrames == 0
        let newest = uniqueSeconds.max()
        let continueBacklog = !historyPersistenceStalled && HistorySyncPolicy.shouldContinue(
            timedOut: reason.hasPrefix("idle timeout"), newest: newest,
            previous: continuationFrontier, attempts: continuationAttempts, now: Date())
        emptySyncStreak = samples.isEmpty ? min(10, emptySyncStreak + 1) : 0
        if !completed && !continueBacklog {
            historySyncError = "History sync stopped (\(reason)). Saved data is safe; retry to fetch the remaining records."
        }
        if let bpm = liveHeartRate {
            status = .streaming(bpm: bpm)
        } else {
            status = .ready
        }
        ensureHeartRateStream()
        armAutomaticSync()

        guard !samples.isEmpty else {
            // The strap may already have trimmed ACKed raw records. An empty
            // retry still needs to persist pending records from that earlier drain.
            if hasUnsavedArchiveRecords || (completed && historicalRecordFrames == 0) {
                mergeHistoricalArchive([]) { [weak self] in
                    guard let self else { return }
                    UserDefaults.standard.set(self.lastHistoryRecordCount, forKey: Keys.retainedHistoryCount)
                    if completed, self.historySyncGeneration == generation { self.recordCompletedHistorySync() }
                    self.recalculateRetainedMetrics()
                }
            }
            if completed && historicalRecordFrames == 0 {
                lastMessage = "History sync completed. No new stored sensor records."
            } else if historicalRecordFrames == 0 && liveHRNotificationCount == 0 && firmwareRevision?.hasPrefix("50.43.") == true {
                lastMessage = "Connected, but no history records or live HR arrived. Firmware 50.43.x has reported data-access restrictions; this is not proof of a token issue. Check firmware and retry after verifying band access."
            } else if historicalRecordFrames > 0 {
                lastMessage = "Received \(historicalRecordFrames) history frames but decoded no samples. Check record version and decoder compatibility; do not discard the raw capture."
            } else {
                lastMessage = "No historical records arrived (\(drainFrames) history/metadata frames, \(drainAcks) ACKs). Check sync, clock, firmware access and retry."
            }
            return
        }
        mergeHistoricalArchive(samples) { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.lastHistoryRecordCount, forKey: Keys.retainedHistoryCount)
            if completed, self.historySyncGeneration == generation { self.recordCompletedHistorySync() }
            self.recalculateRetainedMetrics()
            if continueBacklog, self.historySyncGeneration == generation,
               self.status.isReady, self.isConnected, self.drainStartedAt == nil {
                self.continuationAttempts += 1
                self.continuationFrontier = newest
                self.startDraining(continuing: true)
            }
        }
        lastMessage = "History sync: \(reason). Captured \(samples.count) records, \(drainAcks) ACKs. \(historyQuality). \(reason == "explicit completion" ? "" : "History may be incomplete; retry sync.")"
    }

    /// Freeze *all* later ACKs after a failed commit. Otherwise a later empty
    /// END could free strap history past the failed chunk. Writer identity also
    /// prevents an old connection's completion from ACKing a new connection.
    private func persistHistoryChunk(token: [UInt8], writer: CaptureWriter) {
        guard !historyPersistenceStalled else { return }
        let incoming = Array(capturedSamples.dropFirst(lastChunkCount))
        lastChunkCount = capturedSamples.count
        let checkpoint = token.map { String(format: "%02x", $0) }.joined()
        pendingHistoryFlushes += 1
        writer.flushToDisk { [weak self] saved in
            guard let self, self.captureWriter === writer, self.drainStartedAt != nil else { return }
            guard saved else {
                self.pendingHistoryFlushes -= 1
                self.historyPersistenceStalled = true
                self.historySyncError = "Raw history could not be saved. Band history has not been acknowledged. Retry sync."
                return
            }
            self.archiveWriter.persistChunk(incoming, token: checkpoint) { [weak self] result in
                guard let self, self.captureWriter === writer, self.drainStartedAt != nil else { return }
                self.pendingHistoryFlushes -= 1
                switch result {
                case .success:
                    guard !self.historyPersistenceStalled else { return }
                    self.enqueue(BandCommand.historicalDataResult.rawValue, body: [0x01] + token)
                    self.drainAcks += 1
                    self.lastFrameAt = Date()
                case .failure(let error):
                    self.historyPersistenceStalled = true
                    self.hasUnsavedArchiveRecords = true
                    self.historySyncError = "History database save failed: \(error.localizedDescription). Band history is preserved for retry."
                }
            }
        }
    }

    func flushPersistedCaches() async throws {
        persistLiveRRArchive(force: true)
        await withCheckedContinuation { continuation in
            preferencesWriter.flush { continuation.resume() }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            archiveWriter.flush { result in
                switch result {
                case .success: continuation.resume(returning: ())
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Explicit recovery only; archived evidence remains available for reversal.
    func restoreSavedSleep(_ candidate: SleepRecoveryVault.Candidate) throws {
        let encoder = JSONEncoder()
        if let previous = summary {
            try SleepRecoveryVault.preserve(encoder.encode(previous), key: Keys.summary)
        }
        let overrides = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
        let restored = candidate.session.applyingSavedBounds(overrides)
        guard restored.endUnix > restored.startUnix else {
            throw PersistenceDiagnostics.Failure(message: "Invalid recorded sleep bounds.")
        }
        // Cancel in-flight analysis so it cannot undo the reviewed selection.
        metricsRequest += 1
        sleepCorrectionRevision += 1
        var updated = summary ?? .empty
        var sessions = updated.sleepSessions ?? []
        sessions.removeAll { max($0.startUnix, restored.startUnix) < min($0.endUnix, restored.endUnix) }
        sessions.append(restored)
        updated.sleepSessions = sessions.sorted { $0.endUnix < $1.endUnix }
        updated.sleepStaging = updated.latestSleepSession?.staging
        try SleepRecoveryVault.preserve(encoder.encode(updated), key: Keys.summary)
        summary = updated
        lastSleepAnalysis = nil
        isAnalyzingHistory = false
        historyProgress = nil
        persist(updated)
        preferencesWriter.remove(forKey: Keys.sleepAnalysis)
        // Recalculation is separate: recovery does not invent HRV or Recovery.
    }

    private func persist(_ summary: CaptureSummary) {
        preferencesWriter.write(summary, forKey: Keys.summary)
    }

    private func merge(
        _ fresh: [DayMetrics], coverageStart: Int? = nil, coverageEnd: Int? = nil,
        editedDays: Set<String> = []
    ) {
        guard !fresh.isEmpty else { return }
        let overrides = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
        let previousEditedDays = Set((summary?.sleepSessions ?? []).filter(\.isEdited).compactMap { session in
            JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1)), calendar: .current)
        })
        var map = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
        // A short subsequent capture must not erase a fuller day's steps.
        // This is a conservative lower bound, NOT an additive daily total:
        // overlapping capture windows must never be double-counted.
        for day in fresh {
            guard let previous = map[day.dateKey] else {
                map[day.dateKey] = day
                continue
            }
            let isPrevEdited = previousEditedDays.contains(day.dateKey)
                || (previous.sleepStartUnix.map { overrides[String($0)] != nil } ?? false)
            let replacesSleep = DailyAnalysis.replacesSleep(
                previous: previous, fresh: day, coverageStart: coverageStart, coverageEnd: coverageEnd,
                isEdited: editedDays.contains(day.dateKey),
                previousIsEdited: isPrevEdited
            )
            map[day.dateKey] = DailyAnalysis.mergeDay(previous: previous, fresh: day, replacesSleep: replacesSleep)
        }
        days = map.values.sorted { $0.dateKey < $1.dateKey }
        preferencesWriter.write(days, forKey: Keys.days)
        let today = JournalStore.dayKey(for: Date())
        if let batch = days.first(where: { $0.dateKey == today })?.strain {
            if let currentLive = liveDayStrain {
                liveDayStrain = max(batch, currentLive)
            } else {
                liveDayStrain = batch
                if let baseRaw = WhoopDerivedStrain.raw(forScore: batch) {
                    liveDayRawStrain = max(liveDayRawStrain, baseRaw)
                }
            }
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

        if uuid == BandUUID.events {
            let eventOpcode = (inner.count >= 3 && inner[0] == 0x30) ? inner[2] : (inner.first ?? 0)
            if eventOpcode == BandHardwareEvent.bleHRProfileEnable.rawValue {
                isBroadcastingHR = true
            }
        }

        if type == BandPacket.historicalData {
            historicalRecordFrames += 1
        }
        if type == BandPacket.historicalData || type == BandPacket.metadata {
            drainFrames += 1
            lastFrameAt = Date()
        }
        if type == BandPacket.realtimeData {
            guard let reading = Type40HeartRate.parse(inner) else { return }
            let bpm = reading.bpm
            let rrMS = reading.rrMS
            lastType40HRAt = Date()
            type40HRPackets += 1
            staleHRReconnects = 0
            liveHeartRate = bpm
            if case .connected = status {
                status = .streaming(bpm: bpm)
            } else if case .ready = status {
                status = .streaming(bpm: bpm)
            } else if case .streaming = status {
                status = .streaming(bpm: bpm)
            }
            recordLiveHR(bpm)
            lastLiveHRAt = Date()
            liveHRNotificationCount += 1
            hrRecoveryAttempts = 0
            if !rrMS.isEmpty {
                type40RRPackets += 1
                archiveLiveRR(unix: Int(Date().timeIntervalSince1970), heartRate: bpm, intervals: rrMS, source: "WHOOP Type-40")
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
                pendingHistoryVersionCounts[Int(inner[1]), default: 0] += 1
            }
            // OpenStrap: v26 is a 76-byte optical waveform, NOT an RR/HR
            // biometric record. Recognize it without inventing heartbeats.
            if Gen5V26Record.decode(inner) != nil { return }
            guard let sample = V18Decoder.decode(inner) else {
                pendingHistoryUndecodableFrames += 1
                return
            }
            if seenRecordIndices.insert(sample.header.recordIndex).inserted {
                if !sample.rrIntervalsMS.isEmpty { pendingHistoryRRRecords += 1 }
                let declared = Int(inner[15])
                if declared <= 4 {
                    pendingHistoryRRDeclared += declared
                    pendingHistoryRRAccepted += sample.rrIntervalsMS.count
                    pendingHistoryRRRejected += declared - sample.rrIntervalsMS.count
                } else {
                    pendingHistoryRRRejected += 1 // malformed count byte
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
                guard let writer = captureWriter else { return }
                persistHistoryChunk(token: token, writer: writer)
            } else if inner[2] == 3, drainStartedAt != nil {
                // HISTORY_COMPLETE: stop only on the explicit completion marker.
                finishDrain(reason: "explicit completion")
            }
        } else if (type == BandPacket.commandResponse || type == BandPacket.puffinCommandResponse), inner.count >= 5 {
            // WHOOP 5/MG Puffin command response inner structure:
            // inner[0] = 0x24 (commandResponse) or 0x26 (puffinCommandResponse)
            // inner[1] = response sequence number
            // inner[2] = command opcode (e.g. 0x1D for rebootStrap)
            // inner[3] = origin sequence number
            // inner[4] = result code (0x01 = SUCCESS, 0x00 = FAILURE)
            // Note: in raw Gen5 BLE frame, inner[4] resides at byte 12 (+4 shift from 4.0 byte 8).
            let cmdOpcode = inner[2]
            let resultCode = inner[4]
            if cmdOpcode == BandCommand.rebootStrap.rawValue {
                if resultCode == 1 {
                    rebootExpectedDisconnect = true
                    isRebooting = true
                    rebootMessage = "WHOOP acknowledged reboot. Restarting hardware..."
                } else {
                    isRebooting = false
                    rebootMessage = "WHOOP refused reboot command (result code \(resultCode))"
                }
            }
        }
    }

    private func handleHeartRate(_ characteristic: CBCharacteristic) {
        guard let value = characteristic.value,
              let reading = StandardHeartRate.parse(value),
              (25...230).contains(reading.heartRate) else { return }
        standardHRPackets += 1
        // Prefer the Gen5 stream while it is fresh; SIG remains a live fallback.
        guard LiveHeartRateState.fresh(liveHeartRate, receivedAt: lastType40HRAt,
                                       connected: isConnected, now: Date()) == nil else { return }
        staleHRReconnects = 0
        liveHeartRate = reading.heartRate
        if case .connected = status {
            status = .streaming(bpm: reading.heartRate)
        } else if case .ready = status {
            status = .streaming(bpm: reading.heartRate)
        } else if case .streaming = status {
            status = .streaming(bpm: reading.heartRate)
        }
        recordLiveHR(reading.heartRate)
        lastLiveHRAt = Date()
        liveHRNotificationCount += 1
        hrRecoveryAttempts = 0
        lastMessage = nil
        if !reading.rrMS.isEmpty {
            standardRRPackets += 1
            archiveLiveRR(unix: Int(Date().timeIntervalSince1970), heartRate: reading.heartRate, intervals: reading.rrMS, source: "Bluetooth 2A37")
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
        // CoreBluetooth may restore an already-connected peripheral without
        // delivering didConnect again. Rebuild GATT and restart history sync.
        if restored.state == .connected {
            centralManager(central, didConnect: restored)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if wantsConnection || preferredBandID != nil {
                wantsConnection = true
                reconnectSavedPeripheralOrScan()
            } else {
                status = preferredBandID == nil ? .unpaired : .idle
            }
        case .poweredOff:
            resetLink()
            isLiveSession = false
            sessionStartedUnix = nil
            liveSamples = []
            reconnectWork?.cancel()
            reconnectWork = nil
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
        let hasStandardHR = services.contains(BandUUID.heartRateService)
            || overflowServices.contains(BandUUID.heartRateService)
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let named = (peripheral.name ?? "").lowercased().contains("whoop")
            || advertisedName.lowercased().contains("whoop")
        guard hasGen5Service || hasStandardHR || named else { return }

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

        // The picker/pairing flow only lists sightings; the user taps the band to connect.
        if pickerMode {
            status = .deviceFound(name)
            return
        }
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
        resetLink()
        isLiveSession = false
        sessionStartedUnix = nil
        liveSamples = []
        if rebootExpectedDisconnect {
            rebootExpectedDisconnect = false
            status = .connecting("Rebooting WHOOP…")
            lastMessage = "WHOOP is restarting; waiting for re-advertisement…"
            scheduleReconnect()
            return
        }
        status = .disconnected(
            error.map { $0.localizedDescription } ?? "Strap disconnected"
        )
        if wantsConnection || preferredBandID != nil {
            scheduleReconnect()
        }
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
            case BandUUID.deviceInfoService:
                peripheral.discoverCharacteristics(BandUUID.disCharacteristics, for: service)
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
            case BandUUID.firmwareRevision, BandUUID.hardwareRevision, BandUUID.serialNumber, BandUUID.modelNumber, BandUUID.softwareRevision, BandUUID.manufacturerName:
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
        guard peripheral === self.peripheral else { return }
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

    private func decodeDISString(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let raw = String(decoding: data, as: UTF8.self)
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? nil : cleaned
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, peripheral === self.peripheral, peripheral.state == .connected else { return }
        lastPacketReceivedAt = Date()
        switch characteristic.uuid {
        case BandUUID.heartRateMeasurement:
            handleHeartRate(characteristic)
        case BandUUID.firmwareRevision:
            if let version = decodeDISString(characteristic.value) {
                firmwareRevision = version
                UserDefaults.standard.set(version, forKey: Keys.cachedFirmware)
            }
        case BandUUID.hardwareRevision:
            if let hw = decodeDISString(characteristic.value) {
                hardwareRevision = hw
                UserDefaults.standard.set(hw, forKey: Keys.cachedHardware)
            }
        case BandUUID.serialNumber:
            if let serial = decodeDISString(characteristic.value) {
                serialNumber = serial
                UserDefaults.standard.set(serial, forKey: Keys.cachedSerial)
            }
        case BandUUID.modelNumber:
            if let model = decodeDISString(characteristic.value) {
                modelNumber = model
                UserDefaults.standard.set(model, forKey: Keys.cachedModel)
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
        guard peripheral === self.peripheral, characteristic == commandCharacteristic,
              !commandWriteTimedOut else { return }
        commandDeadline?.cancel()
        commandDeadline = nil
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
            if let failed = commandQueue.first, let onFailure = failed.onFailure {
                commandQueue.removeFirst()
                onFailure(error.localizedDescription)
                commandInFlight = false
                pump()
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
        commandQueue.first?.onWrite?()
        if finished == BandCommand.setGenericHRProfile.rawValue {
            hrEnableQueued = false
            let bodyByte = commandQueue.first?.body.first ?? 0x01
            hrProfileEnabled = (bodyByte == 0x01)
            isBroadcastingHR = hrProfileEnabled
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
            status = .connected(bandName ?? "WHOOP MG")
            isRebooting = false
            rebootMessage = nil
            let generation = linkGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.linkGeneration == generation, self.hrBondConfirmed else { return }
                self.beginDrainRequests()
                self.ensureHeartRateStream()
                self.syncWakeAlarm(force: true)
                self.refreshBattery()
            }
        }
    }
}

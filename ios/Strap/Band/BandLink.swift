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
    static let drainIdleSeconds: TimeInterval = 6
    static let drainEmptySeconds: TimeInterval = 25
    static let drainMaxSeconds: TimeInterval = 120

    @Published private(set) var status: BandStatus = .idle
    @Published private(set) var bandName: String?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var liveHeartRate: Int?
    @Published private(set) var lastLiveHRAt: Date?
    @Published private(set) var liveHRNotificationCount = 0
    @Published private(set) var liveRRIntervalsMS: [Int] = []
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
    private var seenRecordIndices: Set<UInt32> = []
    private var drainFrames = 0
    private var drainAcks = 0
    private var drainStartedAt: Date?
    private var lastFrameAt: Date?
    private var drainTimer: Timer?
    private var liveHRWatchdog: Timer?
    private var lastHRRecoveryAt: Date?
    private var reconnectWork: DispatchWorkItem?
    private var reconnectAttempt = 0
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
        lastCapturePath = UserDefaults.standard.string(forKey: Keys.capturePath)
        preferredBandID = UserDefaults.standard.string(forKey: Keys.preferredBandID)
        preferredBandName = UserDefaults.standard.string(forKey: Keys.preferredBandName)
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Settings

    func configure(sex: Sex, maxHR: Double?, needHours: Double) {
        self.sex = sex
        self.maxHR = maxHR
        self.needHours = needHours
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

    var lastNightHours: Double? {
        summary.map { SleepDetect.totalHours($0.sleepPeriods) }
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

    // MARK: - Connection

    func connect(sex: Sex, maxHR: Double?, needHours: Double) {
        configure(sex: sex, maxHR: maxHR, needHours: needHours)
        stopPicker()
        wantsConnection = true
        if let peripheral, peripheral.state == .connected {
            maybeBeginHandshake()
            return
        }
        if central.state == .poweredOn {
            beginScan()
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
            self.status = .failed(
                self.preferredBandName.map {
                    "\($0) is not answering. Use Find another band to pick the one on your wrist."
                } ?? "No strap found. If the phone is paired to the band in Settings, forget it there — the app needs sole access."
            )
        }
        scanTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func scheduleReconnect() {
        guard wantsConnection, central.state == .poweredOn else { return }
        reconnectWork?.cancel()
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        let delay = min(30.0, Double(1 << reconnectAttempt))
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsConnection, self.central.state == .poweredOn else { return }
            self.beginScan()
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
        enqueue(BandCommand.getDataRange.rawValue)
        enqueue(BandCommand.sendHistoricalData.rawValue)
        status = .draining
        drainStartedAt = Date()
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
        if let hrCharacteristic, !hrCharacteristic.isNotifying {
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
            if let last = self.lastLiveHRAt, Date().timeIntervalSince(last) < 12 { return }
            // A missing HR notification must not remain displayed as live data.
            self.liveHeartRate = nil
            let now = Date()
            guard self.lastHRRecoveryAt.map({ now.timeIntervalSince($0) >= 15 }) ?? true else { return }
            self.lastHRRecoveryAt = now
            self.hrProfileEnabled = false
            self.ensureHeartRateStream()
            self.lastMessage = "Live HR paused; refreshing the band stream."
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
            finishDrain()
        } else if drainFrames == 0 && elapsed >= Self.drainEmptySeconds {
            finishDrain()
        } else if elapsed >= Self.drainMaxSeconds {
            finishDrain()
        }
    }

    private func finishDrain() {
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
        status = .ready
        ensureHeartRateStream()

        guard !samples.isEmpty else {
            lastMessage = "No history came back this drain. Wear the strap, keep phone Bluetooth off the band, and retry."
            return
        }
        let fresh = CaptureSummary.make(
            samples: samples, sex: sex, maxHR: maxHR, awakeBaseline: awakeBaseline
        )
        summary = fresh
        persist(fresh)
        merge(DailyAnalysis.metrics(from: samples, sex: sex, maxHR: maxHR))

        if !fresh.sleepPeriods.isEmpty {
            let analysis = SleepReport.analyze(
                samples: samples,
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
        lastMessage = "Captured \(samples.count) seconds of history (\(drainAcks) offload ACKs)."
    }

    private func persist(_ summary: CaptureSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: Keys.summary)
        }
    }

    private func merge(_ fresh: [DayMetrics]) {
        guard !fresh.isEmpty else { return }
        var map = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
        for day in fresh { map[day.dateKey] = day }
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

        if type == BandPacket.historicalData || type == BandPacket.metadata {
            drainFrames += 1
            lastFrameAt = Date()
        }
        if type == BandPacket.historicalData {
            guard let sample = V18Decoder.decode(inner) else { return }
            if seenRecordIndices.insert(sample.header.recordIndex).inserted {
                capturedSamples.append(sample)
            }
        } else if type == BandPacket.metadata,
                  inner.count >= 21,
                  inner[2] == BandPacket.historyEnd {
            let token = Array(inner[13..<21])
            enqueue(BandCommand.historicalDataResult.rawValue, body: [0x01] + token)
            drainAcks += 1
        }
    }

    private func handleHeartRate(_ characteristic: CBCharacteristic) {
        guard let value = characteristic.value,
              let reading = StandardHeartRate.parse(value) else { return }
        liveHeartRate = reading.heartRate
        lastLiveHRAt = Date()
        liveHRNotificationCount += 1
        if !reading.rrMS.isEmpty {
            liveRRIntervalsMS = Array((liveRRIntervalsMS + reading.rrMS).suffix(120))
        }
        guard isLiveSession else { return }
        let unix = Int(Date().timeIntervalSince1970)
        let sample = LiveSample(unix: unix, heartRate: reading.heartRate, rrIntervalsMS: reading.rrMS)
        if liveSamples.last?.unix == unix {
            liveSamples[liveSamples.count - 1] = sample
        } else {
            liveSamples.append(sample)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BandLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if wantsConnection {
                beginScan()
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
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let named = (peripheral.name ?? "").lowercased().contains("whoop")
            || advertisedName.lowercased().contains("whoop")
        guard services.contains(BandUUID.service) || named else { return }

        let identifier = peripheral.identifier.uuidString
        let name = peripheral.name ?? (advertisedName.isEmpty ? "WHOOP" : advertisedName)
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
        reconnectWork?.cancel()
        reconnectWork = nil
        reconnectAttempt = 0
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
        resetLink()
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
        maybeBeginHandshake()
        if characteristic.uuid == BandUUID.heartRateMeasurement && !characteristic.isNotifying {
            liveHeartRate = nil
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
            status = .authenticating
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.beginDrainRequests()
                self?.ensureHeartRateStream()
            }
        }
    }
}

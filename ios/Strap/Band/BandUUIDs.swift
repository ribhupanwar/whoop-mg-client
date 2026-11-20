import CoreBluetooth

/// UUID constants for WHOOP 4.0 and WHOOP 5.0 / MG (Gen5).
enum BandUUID {
    static let service              = CBUUID(string: "FD4B")
    static let commandTo            = CBUUID(string: "00000001-FD4B-4E36-8E30-EC7DE3E5A004")
    static let commandFrom          = CBUUID(string: "00000002-FD4B-4E36-8E30-EC7DE3E5A004")
    static let events               = CBUUID(string: "00000004-FD4B-4E36-8E30-EC7DE3E5A004")
    static let data                 = CBUUID(string: "00000005-FD4B-4E36-8E30-EC7DE3E5A004")
    static let memfault             = CBUUID(string: "00000006-FD4B-4E36-8E30-EC7DE3E5A004")

    // Standard Bluetooth SIG Heart Rate Service (0x180D)
    static let heartRateService     = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")

    // Standard Bluetooth SIG Device Information Service (0x180A)
    static let deviceInfoService    = CBUUID(string: "180A")
    static let modelNumber          = CBUUID(string: "2A24")
    static let serialNumber         = CBUUID(string: "2A25")
    static let firmwareRevision     = CBUUID(string: "2A26")
    static let hardwareRevision     = CBUUID(string: "2A27")
    static let softwareRevision     = CBUUID(string: "2A28")
    static let manufacturerName     = CBUUID(string: "2A29")

    // Standard Battery Service (0x180F)
    static let batteryService       = CBUUID(string: "180F")
    static let batteryLevel         = CBUUID(string: "2A19")

    static let notifiable: [CBUUID] = [commandFrom, events, data, memfault]

    static let disCharacteristics: [CBUUID] = [
        modelNumber,
        serialNumber,
        firmwareRevision,
        hardwareRevision,
        softwareRevision,
        manufacturerName
    ]
}

/// Command opcodes observed on gen5 hardware.
/// FORGET_BONDS (0x0F), FORCE_TRIM (0x19), and POWER_CYCLE_STRAP (0x20) are
/// destructive/quarantined.
/// REBOOT_STRAP (0x1D / 29) is the verified warm MCU reboot that preserves flash history.
enum BandCommand: UInt8 {
    case realtimeHROn = 0x03
    case setGenericHRProfile = 0x0E
    case abortHistoricalTransmits = 0x14
    case sendHistoricalData = 0x16
    case historicalDataResult = 0x17
    case forceTrim = 0x19              // 25: Quarantined destructive flash trim
    case rebootStrap = 0x1D            // 29: Verified warm MCU reboot
    case powerCycleStrap = 0x20        // 32: Quarantined cold power cycle
    case getDataRange = 0x22
    case clientHello = 0x91
}

/// Hardware event notification codes notified asynchronously on fd4b0004.
enum BandHardwareEvent: UInt8 {
    case wristOff = 0x0A              // 10: Optical PPG off-wrist (green LEDs off)
    case bleConnectionUp = 0x0B       // 11: BLE connected
    case bleConnectionDown = 0x0C     // 12: BLE disconnected
    case rtcLost = 0x0D               // 13: RTC desynchronized
    case doubleTap = 0x0E             // 14: Accelerometer double-tap detected
    case boot = 0x0F                  // 15: Power-on / reboot
    case setRTC = 0x10                // 16: Time synchronized
    case temperatureLevel = 0x11      // 17: Skin temperature update
    case pairingMode = 0x12           // 18: Pairing mode activated (pulsing blue LED)
    case batteryPackConnected = 0x15  // 21: Charger attached
    case batteryPackRemoved = 0x16    // 22: Charger detached
    case bleBonded = 0x17             // 23: BLE pairing/bonding completed
    case bleHRProfileEnable = 0x18    // 24: Standard 0x180D HR broadcast active
}

enum BandPacket {
    static let command: UInt8 = 0x23
    static let commandResponse: UInt8 = 0x24
    static let puffinCommandResponse: UInt8 = 0x26
    static let realtimeData: UInt8 = 0x28
    static let historicalData: UInt8 = 0x2F
    static let metadata: UInt8 = 0x31
    static let historyEnd: UInt8 = 0x02
}

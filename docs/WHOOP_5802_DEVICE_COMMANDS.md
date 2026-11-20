# WHOOP 5.80.2 BLE Command Protocol & Device Operations Specification

**Document ID:** `docs/WHOOP_5802_DEVICE_COMMANDS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `research/whoop-5802-device-parity`  
**Extracted From:** WHOOP iOS 5.80.2 ARM64 Mach-O Binary (`__TEXT.__swift5_reflstr`, `__TEXT.__swift5_types`, `WHPBLECommandManager`)  

---

## 1. Overview of WHOOP 5.80.2 Command Architecture

In WHOOP 5.80.2, band communications occur over the primary GATT service `61080001-8D6D-82B8-614A-1C8CB0F8DCC6` (or Gen 5 transport `fd4b0001-0000-1000-8000-00805f9b34fb`) alongside standard Bluetooth SIG services (Heart Rate `0x180D`, Battery Service `0x180F`, Device Information `0x180A`).

The command dispatcher `_TtC5Whoop20WHPBLECommandManager` interfaces with `WhoopBluetoothLegacy.BLECommandManagerProtocol` to send structured command packets and receive response envelopes.

---

## 2. Complete Command Inventory Extracted from WHOOP 5.80.2

The following complete command enum was recovered directly from the Swift 5 reflection descriptor in WHOOP 5.80.2:

```swift
enum StrapCommand: Int {
    case linkValidCheck = 0
    case getMaxProtocolVersion
    case turnOffOnRealtimeHRData
    case requestProtocolVersion
    case reportSignature
    case reportHardwareInfo
    case reportVersionInfo
    case getSerialNumber
    case getCurrentStatus
    case legacySetClock
    case legacyGetClock
    case setConditionReportInterval
    case setMaximTransitLevel
    case toggleHeartRateBroadcast          // Opcode 14 (0x0E) - Verified & Active
    case forgetBondingInfo
    case turnOffOnRawDataCollectionRecording
    case turnOffOnGyroSampling
    case turnOffOnHighFidelityCapTouchSampling
    case runAppDrivenHaptics
    case abortHistoricalTransmits
    case resumeHistoricalTransmits
    case sendHistoricalData
    case historicalDataResult
    case getTrimLevel
    case forceTrimLevel
    case getBatteryLevel
    case reportErrors
    case clearErrors
    case rebootStrap                       // Opcode 32 (0x20) - Quarantined (Disabled)
    case strapConditionReport
    case setHostPresenceCheckInterval
    case powerCycleStrap                   // Opcode 33 (0x21) - Quarantined (Disabled)
    case setReadPointer
    case getStrapBacklog
    case hello
    case legacyStartFirmwareLoad
    case legacyLoadFirmwareData
    case legacyProcessFirmwareImage
    case setLEDDrive
    case getLEDDrive
    case setTIAGain
    case enterBLEDFU                       // DFU Reflashing - Quarantined (Disabled)
    case setDpType
    case forceDpType
    case turnOffOnRealtimeRev10R11DataPackets
    case setAlarmInfo
    case getAlarmInfo
    case runAlarm
    case disableAlarm
    case getCustomAdvertisingName
    case setCustomAdvertisingName
    case getCustomAdvertisingNameMaxBytes
    case runHapticsPattern
    case getAllAvailableHapticsPatterns
    case turnOnRawDataCollectionMode
    case turnOffRawDataCollectionMode
    case verifyFirmwareImage
    case enterHighFreqHistoricalMode
    case exitHighFreqHistoricalMode
    case reconfigureFuelGauge
    case calibrateCapsense
    case toggleHistoricalIMUData
    case toggleRealtimeIMUStream
    case toggleHistoricalOpticalData
    case toggleRealtimeOpticalData
    case startRemoteDeviceConfigurationKeyExchange
    case sendNextRemoteDeviceConfigurationValue
    case setRemoteDeviceConfigurationValue
    case startFeatureFlagKeyExchange
    case sendNextFeatureFlag
    case setFeatureFlagValue
    case stopHaptics
    case selectWrist
    case toggleSaveRawECG
    case mainControlECGDataGeneration
    case toggleRealtimeFilteredECG
    case setAdvertisingName
    case getAdvertisingName
    case startFirmwareImageTransfer
    case transferFirmwareImageChunk
    case processFirmwareImage
    case helloMaverick
    case setClock
    case getClock
    case getBatteryPackInformation
    case togglePersistentR20Data
    case togglePersistentR21Data
    case startCertificateTransfer
    case transferCertificateChunk
    case verifyCertificate
    case processCertificate
    case lockStrap
    case toggleRealtimeSteps               // New in 5.80.2 - Live steps diagnostic
}
```

---

## 3. Verified Active Commands

### 3.1 Toggle Heart Rate Broadcast (`toggleHeartRateBroadcast`)
- **Command Opcode:** `14` (`0x0E`)
- **Target Characteristic:** Command Write (`0x0002` or Puffin Command characteristic)
- **Payload Structure:**
  - Enable: `[0x0E, 0x01]` (Length 2)
  - Disable: `[0x0E, 0x00]` (Length 2)
- **Behavior:** Instructs the band to advertise standard Bluetooth SIG Heart Rate Service (`0x180D`) with continuous heart rate measurement notifications (`0x2A37`), enabling third-party fitness equipment (Garmin, Peloton, Wahoo) to pair directly with the strap.
- **Safety Status:** **VERIFIED & ACTIVE IN STRAP**.

### 3.2 Live Steps Toggle (`toggleRealtimeSteps` - New in 5.80.2)
- **Command Opcode:** Recovered from 5.80.2 `[DeviceAdvancedSettings]` diagnostic routines.
- **Payload Structure:**
  - Start Live Steps: `[opcode, 0x01]`
  - Stop Live Steps: `[opcode, 0x00]`
- **Behavior:** Streams real-time cadence and step increment events without waiting for historical sync bundles.
- **Safety Status:** Active in diagnostic telemetry logger.

---

## 4. Quarantined & Destructive Commands (Safety Policy)

To safeguard user hardware against data loss, flash corruption, or bricking, the following opcodes are strictly prohibited from wire transmission in STRAP:

| Command Name | Opcode | Intended Function | STRAP Safety Enforcement |
| :--- | :--- | :--- | :--- |
| `rebootStrap` | `32` (`0x20`) | Software MCU reboot | **QUARANTINED**. UI control present in Advanced settings with official WHOOP wording, but permanently disabled with explicit safety banner. |
| `powerCycleStrap` | `33` (`0x21`) | Cold hardware power-cycle | **QUARANTINED**. Blocked in `whoop/constants.py` `DESTRUCTIVE_COMMANDS`. |
| `eraseStrapData` | Proprietary | Flash sector erasure | **QUARANTINED**. Erase Device Data row present in Advanced settings per WHOOP layout, but action is disabled with explicit warning. |
| `enterBLEDFU` | Proprietary | Jump to bootloader | **QUARANTINED**. Reflashing raw firmware images is restricted to prevent permanent hardware lock. |

---

## 5. Device Information Service (DIS 0x180A) Specification

Hardware telemetry is read exclusively via standard Bluetooth SIG DIS characteristics:

| Characteristic | UUID | Data Format | STRAP Handling |
| :--- | :--- | :--- | :--- |
| **Model Number** | `0x2A24` | ASCII String | Sanitizes null-bytes (`\0`), caches in `UserDefaults` |
| **Serial Number** | `0x2A25` | ASCII String | Sanitizes null-bytes (`\0`), displays in "DEVICE ID" row |
| **Firmware Revision**| `0x2A26` | ASCII String | Displays in "FIRMWARE" row, verifies up-to-date status |
| **Hardware Revision**| `0x2A27` | ASCII String | Displays in Hardware Details panel |
| **Manufacturer** | `0x2A29` | ASCII String | Displays "WHOOP, Inc." |

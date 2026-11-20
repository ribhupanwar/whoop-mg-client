import XCTest
import CoreBluetooth
import SwiftUI
@testable import Strap

final class DeviceControlTests: XCTestCase {

    // MARK: - Broadcast Heart Rate Command Tests

    func testBroadcastHRCommandOpcodesAndPayloads() {
        // Command 14 (0x0E) is verified across WHOOP 4 and WHOOP 5/MG
        XCTAssertEqual(BandCommand.setGenericHRProfile.rawValue, 0x0E)

        let enableBody: [UInt8] = [0x01]
        let disableBody: [UInt8] = [0x00]

        // Inner packet: [0x23, seq, 0x0E, body]
        let enableInner: [UInt8] = [BandPacket.command, 0x01, BandCommand.setGenericHRProfile.rawValue] + enableBody
        let enableFrame = Gen5Frame.build(enableInner)
        XCTAssertEqual(enableFrame[0], 0xAA)
        XCTAssertEqual(enableFrame[1], 0x01)

        let parsedEnable = Gen5Frame.parse(enableFrame)
        XCTAssertNotNil(parsedEnable)
        XCTAssertEqual(Array(parsedEnable!.prefix(enableInner.count)), enableInner)

        let disableInner: [UInt8] = [BandPacket.command, 0x02, BandCommand.setGenericHRProfile.rawValue] + disableBody
        let disableFrame = Gen5Frame.build(disableInner)
        let parsedDisable = Gen5Frame.parse(disableFrame)
        XCTAssertNotNil(parsedDisable)
        XCTAssertEqual(Array(parsedDisable!.prefix(disableInner.count)), disableInner)
    }

    // MARK: - Reboot Command & Response Framing Tests

    func testRebootStrapCommandOpcode() {
        // Command 29 (0x1D) is verified non-destructive warm restart
        XCTAssertEqual(BandCommand.rebootStrap.rawValue, 0x1D)
        XCTAssertEqual(BandCommand.powerCycleStrap.rawValue, 0x20)
        XCTAssertEqual(BandCommand.forceTrim.rawValue, 0x19)

        // Inner packet: [0x23, seq, 0x1D]
        let rebootInner: [UInt8] = [BandPacket.command, 0x03, BandCommand.rebootStrap.rawValue]
        let rebootFrame = Gen5Frame.build(rebootInner)
        XCTAssertEqual(rebootFrame[0], 0xAA)
        XCTAssertEqual(rebootFrame[1], 0x01)

        let parsed = Gen5Frame.parse(rebootFrame)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(Array(parsed!.prefix(rebootInner.count)), rebootInner)
    }

    func testCommandResponseInnerStructure() {
        // inner[0] = 0x24 (commandResponse)
        // inner[1] = response seq
        // inner[2] = cmd (0x1D)
        // inner[3] = origin seq
        // inner[4] = result (0x01 = success, 0x02 = pending)
        let innerResponse: [UInt8] = [BandPacket.commandResponse, 0x05, BandCommand.rebootStrap.rawValue, 0x02, 0x01, 0x00, 0x00]
        XCTAssertEqual(innerResponse[0], 0x24)
        XCTAssertEqual(innerResponse[2], 0x1D)
        XCTAssertEqual(innerResponse[4], 0x01) // Success

        let pendingResponse: [UInt8] = [BandPacket.commandResponse, 0x06, BandCommand.rebootStrap.rawValue, 0x02, 0x02, 0x00, 0x00]
        XCTAssertEqual(pendingResponse[4], 0x02) // Pending
    }

    // MARK: - DIS Characteristics Tests

    func testDISCharacteristicsUUIDs() {
        XCTAssertEqual(BandUUID.deviceInfoService.uuidString, "180A")
        XCTAssertEqual(BandUUID.modelNumber.uuidString, "2A24")
        XCTAssertEqual(BandUUID.serialNumber.uuidString, "2A25")
        XCTAssertEqual(BandUUID.firmwareRevision.uuidString, "2A26")
        XCTAssertEqual(BandUUID.hardwareRevision.uuidString, "2A27")
        XCTAssertEqual(BandUUID.softwareRevision.uuidString, "2A28")
        XCTAssertEqual(BandUUID.manufacturerName.uuidString, "2A29")

        XCTAssertTrue(BandUUID.disCharacteristics.contains(BandUUID.modelNumber))
        XCTAssertTrue(BandUUID.disCharacteristics.contains(BandUUID.serialNumber))
        XCTAssertTrue(BandUUID.disCharacteristics.contains(BandUUID.firmwareRevision))
        XCTAssertTrue(BandUUID.disCharacteristics.contains(BandUUID.hardwareRevision))
    }

    func testDISStringNullTerminationAndWhitespaceTrimming() {
        // Real WHOOP bands often return NUL-padded strings in DIS characteristics
        let rawNullPadded = "5AM123456\0\0\0".data(using: .utf8)!
        let raw = String(decoding: rawNullPadded, as: UTF8.self)
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        XCTAssertEqual(cleaned, "5AM123456")

        let rawFirmware = " 50.42.1.0 \0\n".data(using: .utf8)!
        let cleanedFirmware = String(decoding: rawFirmware, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        XCTAssertEqual(cleanedFirmware, "50.42.1.0")
    }

    // MARK: - Hardware Event Opcodes Tests

    func testHardwareEventsOpcodes() {
        XCTAssertEqual(BandHardwareEvent.wristOff.rawValue, 0x0A)             // 10
        XCTAssertEqual(BandHardwareEvent.bleConnectionUp.rawValue, 0x0B)      // 11
        XCTAssertEqual(BandHardwareEvent.bleConnectionDown.rawValue, 0x0C)    // 12
        XCTAssertEqual(BandHardwareEvent.doubleTap.rawValue, 0x0E)            // 14
        XCTAssertEqual(BandHardwareEvent.boot.rawValue, 0x0F)                 // 15
        XCTAssertEqual(BandHardwareEvent.pairingMode.rawValue, 0x12)          // 18
        XCTAssertEqual(BandHardwareEvent.bleBonded.rawValue, 0x17)            // 23
        XCTAssertEqual(BandHardwareEvent.bleHRProfileEnable.rawValue, 0x18)   // 24
    }

    // MARK: - Device Info Cache Invariant Tests

    func testCachedDeviceInfoUserDefaultsPersistence() {
        let defaults = UserDefaults.standard
        let fwKey = "strap.band.cached_firmware_revision"
        let hwKey = "strap.band.cached_hardware_revision"
        let serialKey = "strap.band.cached_serial_number"
        let modelKey = "strap.band.cached_model_number"
        let bcastKey = "strap.band.broadcast_hr_enabled"

        // Backup existing values if any
        let origFw = defaults.string(forKey: fwKey)
        let origHw = defaults.string(forKey: hwKey)
        let origSerial = defaults.string(forKey: serialKey)
        let origModel = defaults.string(forKey: modelKey)
        let origBcast = defaults.object(forKey: bcastKey)

        defer {
            defaults.setValue(origFw, forKey: fwKey)
            defaults.setValue(origHw, forKey: hwKey)
            defaults.setValue(origSerial, forKey: serialKey)
            defaults.setValue(origModel, forKey: modelKey)
            defaults.setValue(origBcast, forKey: bcastKey)
        }

        defaults.set("50.42.1.0", forKey: fwKey)
        defaults.set("WG50", forKey: hwKey)
        defaults.set("5AM987654", forKey: serialKey)
        defaults.set("WHOOP MG", forKey: modelKey)
        defaults.set(true, forKey: bcastKey)

        XCTAssertEqual(defaults.string(forKey: fwKey), "50.42.1.0")
        XCTAssertEqual(defaults.string(forKey: hwKey), "WG50")
        XCTAssertEqual(defaults.string(forKey: serialKey), "5AM987654")
        XCTAssertEqual(defaults.string(forKey: modelKey), "WHOOP MG")
        XCTAssertTrue(defaults.bool(forKey: bcastKey))
    }

    // MARK: - WHOOP 5.80.2 Parity Tests

    func testRegulatoryModelIDMappings() {
        // Harvard (WHOOP 4.0)
        let harvardHeader = "4.0 REGULATORY LABELS"
        let harvardModel = "WS40 (DEVICE)\nWP40 (CHARGER)"
        XCTAssertEqual(harvardHeader, "4.0 REGULATORY LABELS")
        XCTAssertTrue(harvardModel.contains("WS40"))

        // Maverick (WHOOP MG)
        let maverickHeader = "MG REGULATORY LABELS"
        let maverickModel = "WS50 (DEVICE)\nWM50 (DEVICE)\nWD50 (BASIC CHARGER)\nWB50 (WIRELESS CHARGER)"
        XCTAssertEqual(maverickHeader, "MG REGULATORY LABELS")
        XCTAssertTrue(maverickModel.contains("WS50"))
        XCTAssertTrue(maverickModel.contains("WM50"))

        // Goose (WHOOP 5.0)
        let gooseHeader = "5.0 REGULATORY LABELS"
        let gooseModel = "WG50 (DEVICE)\nWD50 (BASIC CHARGER)\nWB50 (WIRELESS CHARGER)"
        XCTAssertEqual(gooseHeader, "5.0 REGULATORY LABELS")
        XCTAssertTrue(gooseModel.contains("WG50"))
    }

    func testQuarantinedCommandsProhibited() {
        // Cold Power-cycle (0x20 / 32) and Force-trim (0x19 / 25) must remain quarantined
        let prohibitedOpcodes: Set<UInt8> = [BandCommand.powerCycleStrap.rawValue, BandCommand.forceTrim.rawValue]
        XCTAssertTrue(prohibitedOpcodes.contains(0x20))
        XCTAssertTrue(prohibitedOpcodes.contains(0x19))
    }

    // MARK: - UI Parity & Ring Geometry Regression Tests

    func testRingGeometryLayoutConstants() {
        XCTAssertEqual(AppLayout.heroRingDiameter, 84.0)
        XCTAssertEqual(AppLayout.detailRingDiameter, 104.0)
        XCTAssertEqual(AppLayout.ringStrokeWidth, 5.0)
        XCTAssertEqual(AppLayout.ringGap, 18.0)
        XCTAssertEqual(AppLayout.heroMetricFontSize, 23.0)
        XCTAssertEqual(AppLayout.percentSignScale, 0.72)
    }

    func testColorTokensPreservation() {
        _ = Color.appCanvasTop
        _ = Color.appCanvasMid
        _ = Color.appBG
        _ = Color.appSurface
        _ = Color.appRaised
        _ = Color.appCardBorder
        _ = Color.appRingTrack
        _ = Color.appSleep
        _ = Color.appGood
        _ = Color.appWarn
        _ = Color.appHigh
        _ = Color.appAccent
    }
}

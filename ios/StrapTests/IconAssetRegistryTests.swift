import XCTest
@testable import Strap

final class IconAssetRegistryTests: XCTestCase {
    func testAllIconAssetsHaveCases() {
        // Verify all 27 icon assets are defined
        XCTAssertEqual(IconAsset.allCases.count, 27)
    }

    func testAllIconAssetsHaveNonEmptyRawValue() {
        for asset in IconAsset.allCases {
            XCTAssertFalse(asset.rawValue.isEmpty, "Icon asset \(asset) has empty rawValue")
        }
    }

    func testAllIconAssetsHaveSFSymbolFallback() {
        for asset in IconAsset.allCases {
            XCTAssertFalse(asset.sfSymbolFallback.isEmpty, "Icon asset \(asset) has empty SF Symbol fallback")
        }
    }

    func testIconAssetImageNamesAreUnique() {
        let names = IconAsset.allCases.map { $0.rawValue }
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Duplicate icon asset names found")
    }

    func testDeviceIconsExist() {
        let deviceIcons: [IconAsset] = [.deviceStrapIdle, .deviceStrapConnected, .deviceStrapDisconnected,
                                         .deviceBatteryFull, .deviceBatteryLow, .deviceBatteryCritical,
                                         .deviceBatteryCharging, .deviceBleConnected, .deviceBleSearching]
        XCTAssertEqual(deviceIcons.count, 9)
    }

    func testHealthIconsExist() {
        let healthIcons: [IconAsset] = [.healthHeartRate, .healthHrv, .healthRespiratory,
                                         .healthBloodOxygen, .healthTemperature, .healthSleep,
                                         .healthRecovery, .healthStrain]
        XCTAssertEqual(healthIcons.count, 8)
    }

    func testSettingsIconsExist() {
        let settingsIcons: [IconAsset] = [.settingsAccount, .settingsPrivacy, .settingsNotifications,
                                           .settingsLanguage, .settingsIntegrations]
        XCTAssertEqual(settingsIcons.count, 5)
    }

    func testNavigationIconsExist() {
        let navIcons: [IconAsset] = [.navHome, .navProfile, .navMore]
        XCTAssertEqual(navIcons.count, 3)
    }

    func testAlarmIconsExist() {
        let alarmIcons: [IconAsset] = [.alarmWake, .alarmSleepGoal]
        XCTAssertEqual(alarmIcons.count, 2)
    }
}
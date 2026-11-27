import XCTest
import UIKit
import SwiftUI
@testable import Strap

final class TypographyTests: XCTestCase {
    func testEveryRequiredLicensedFontFaceIsRegisteredInTheApp() {
        XCTAssertTrue(StrapTypography.missingBundledFaces.isEmpty,
                      "Missing or unregistered licensed font faces: \(StrapTypography.missingBundledFaces)")
    }
}

extension TypographyTests {
    func testActualRenderedFacesAreTheBundledPurchasedFonts() {
        let expected = ["ProximaNova-Regular": "ProximaNova-Regular",
                        "ProximaNova-Bold": "ProximaNova-Bold",
                        "proxima-nova-medium": "ProximaNova-Medium",
                        "proxima-nova-semibold": "ProximaNova-Semibold",
                        "DINPro-Regular": "DINPro-Regular", "DINPro-Bold": "DINPro-Bold"]
        for (file, name) in expected {
            for size in [CGFloat(12), 17, 26, 64] {
                XCTAssertEqual(StrapTypography.resolvedPostScriptName(file, size: size), name)
            }
        }
    }
}

extension TypographyTests {
    func testSleepChartRejectsOutOfWindowAndNonFiniteSamplesAndSorts() {
        let points: [(unix: Int, bpm: Double)] = [
            (150, 63), (99, 60), (120, .nan), (110, 61),
            (205, 68), (170, .infinity), (150, 65), (180, 0)
        ]
        XCTAssertEqual(SleepHeartRateChart.sanitizedIndices(points, start: 100, end: 200),
                       [3, 0, 6])
        XCTAssertTrue(SleepHeartRateChart.sanitizedIndices(points, start: 200, end: 100).isEmpty)
    }
}

extension TypographyTests {
    func testAppearancePaletteResolvesDistinctTraits() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let light = UITraitCollection(userInterfaceStyle: .light)
        let source = Color.adaptiveUIColor(dark: 0x0D1112, light: 0xF7F8FA)
        func rgb(_ color: UIColor) -> [Int] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
            return [r, g, b].map { Int(($0 * 255).rounded()) }
        }
        XCTAssertEqual(rgb(source.resolvedColor(with: dark)), [13, 17, 18])
        XCTAssertEqual(rgb(source.resolvedColor(with: light)), [247, 248, 250])
        XCTAssertNotEqual(rgb(UIColor(Color.appFG).resolvedColor(with: dark)),
                          rgb(UIColor(Color.appFG).resolvedColor(with: light)))
    }
}

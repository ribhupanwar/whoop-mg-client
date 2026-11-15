import XCTest
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

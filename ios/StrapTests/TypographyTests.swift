import XCTest
@testable import Strap

final class TypographyTests: XCTestCase {
    func testEveryRequiredLicensedFontFaceIsRegisteredInTheApp() {
        XCTAssertTrue(StrapTypography.missingBundledFaces.isEmpty,
                      "Missing or unregistered licensed font faces: \(StrapTypography.missingBundledFaces)")
    }
}

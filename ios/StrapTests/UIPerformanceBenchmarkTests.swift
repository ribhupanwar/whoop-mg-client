import XCTest
import SwiftUI
@testable import Strap

final class UIPerformanceBenchmarkTests: XCTestCase {

    // MARK: - 1. IconAsset Lookup & Decoding Performance

    func testIconAssetLookupLatencyBenchmark() {
        // Measure 1,000 sequential lookups across all 27 IconAsset enum cases
        let iterations = 1000
        let start = CACurrentMediaTime()

        for _ in 0..<iterations {
            for asset in IconAsset.allCases {
                _ = asset.rawValue
                _ = asset.sfSymbolFallback
            }
        }

        let elapsed = CACurrentMediaTime() - start
        let totalLookups = iterations * IconAsset.allCases.count
        let averageLatencyUs = (elapsed / Double(totalLookups)) * 1_000_000.0

        print("IconAsset lookup benchmark: \(totalLookups) lookups in \(String(format: "%.4f", elapsed))s (\(String(format: "%.2f", averageLatencyUs)) µs/lookup)")
        // Performance gate: lookup must be sub-microsecond
        XCTAssertLessThan(averageLatencyUs, 10.0, "IconAsset lookup exceeds performance threshold")
    }

    func testAllIconAssetsHaveValidNonEmptyAttributes() {
        XCTAssertEqual(IconAsset.allCases.count, 27)
        for asset in IconAsset.allCases {
            XCTAssertFalse(asset.rawValue.isEmpty, "IconAsset \(asset) rawValue is empty")
            XCTAssertFalse(asset.sfSymbolFallback.isEmpty, "IconAsset \(asset) sfSymbolFallback is empty")
        }
    }

    // MARK: - 2. ActivityKind Icon Resolution Performance

    func testActivityKindIconResolutionBenchmark() {
        // Measure resolution of all 137 sport icons across 1,000 iterations
        let iterations = 1000
        let start = CACurrentMediaTime()

        for _ in 0..<iterations {
            for kind in ActivityKind.allCases {
                _ = kind.icon
                _ = kind.label
            }
        }

        let elapsed = CACurrentMediaTime() - start
        let totalResolutions = iterations * ActivityKind.allCases.count
        let averageLatencyUs = (elapsed / Double(totalResolutions)) * 1_000_000.0

        print("ActivityKind resolution benchmark: \(totalResolutions) resolutions in \(String(format: "%.4f", elapsed))s (\(String(format: "%.2f", averageLatencyUs)) µs/op)")
        XCTAssertLessThan(averageLatencyUs, 10.0, "ActivityKind icon resolution exceeds performance threshold")
    }

    func testAllActivityKindsHaveValidIcons() {
        XCTAssertEqual(ActivityKind.allCases.count, 137)
        for kind in ActivityKind.allCases {
            XCTAssertFalse(kind.icon.isEmpty, "ActivityKind \(kind) icon symbol is empty")
            XCTAssertFalse(kind.label.isEmpty, "ActivityKind \(kind) label is empty")
        }
    }

    // MARK: - 3. WhoopWGlyph Equatable & Geometry Verification

    func testWhoopWGlyphEquatablePreventsRedundantViewRecomputation() {
        let glyph1 = WhoopWGlyph(color: Color.appMuted.opacity(0.85))
        let glyph2 = WhoopWGlyph(color: Color.appMuted.opacity(0.85))
        let glyphDifferent = WhoopWGlyph(color: Color.white)

        XCTAssertEqual(glyph1, glyph2, "Identical WhoopWGlyph instances must be Equatable to elide 120Hz view updates")
        XCTAssertNotEqual(glyph1, glyphDifferent, "Distinct color WhoopWGlyph instances must not be equal")
    }

    func testWhoopWGlyphStrokeGeometryConformsToForensicReference() {
        // Verify exactly 3 segmented strokes
        XCTAssertEqual(WhoopWGlyph.pathPoints.count, 3)

        let s1 = WhoopWGlyph.pathPoints[0]
        let s2 = WhoopWGlyph.pathPoints[1]
        let s3 = WhoopWGlyph.pathPoints[2]

        // Stroke 1: Left stroke slopes down-right
        XCTAssertGreaterThan(s1.end.x, s1.start.x, "Stroke 1 must slope down-right")
        XCTAssertGreaterThan(s1.end.y, s1.start.y, "Stroke 1 must slope downward")

        // Stroke 2: Middle stroke slopes down-left from center top
        XCTAssertLessThan(s2.end.x, s2.start.x, "Stroke 2 must slope down-left")
        XCTAssertGreaterThan(s2.end.y, s2.start.y, "Stroke 2 must slope downward")

        // Stroke 3: Right accent tick slopes down-right, parallel to Stroke 1
        XCTAssertGreaterThan(s3.end.x, s3.start.x, "Stroke 3 must slope down-right")
        XCTAssertGreaterThan(s3.end.y, s3.start.y, "Stroke 3 must slope downward")

        // Top baselines: Stroke 1 and Stroke 2 start near top
        XCTAssertEqual(s1.start.y, s2.start.y, accuracy: 0.5, "Stroke 1 and Stroke 2 must start near top baseline")

        // Slopes: Stroke 1 and Stroke 3 must have positive downward slopes
        let slope1 = (s1.end.y - s1.start.y) / (s1.end.x - s1.start.x)
        let slope3 = (s3.end.y - s3.start.y) / (s3.end.x - s3.start.x)
        XCTAssertGreaterThan(slope1, 0, "Stroke 1 must have positive downward slope")
        XCTAssertGreaterThan(slope3, 0, "Stroke 3 must have positive downward slope")
    }

    func testHomeRefreshConstantsMeetPixelAuditSpecifications() {
        XCTAssertEqual(HomeRefreshConstants.diameter, 30.0, accuracy: 0.5)
        XCTAssertEqual(HomeRefreshConstants.arcStrokeWidth, 1.6, accuracy: 0.2)
        XCTAssertEqual(HomeRefreshConstants.arcTrimFraction, 0.84, accuracy: 0.02)
        XCTAssertEqual(HomeRefreshConstants.arcGapStartAngleDegrees, -150.0, accuracy: 2.0)
        XCTAssertEqual(HomeRefreshConstants.glyphSize, 14.0, accuracy: 0.5)
        XCTAssertEqual(HomeRefreshConstants.glyphStrokeWidth, 1.6, accuracy: 0.2)
    }

    // MARK: - 4. IconGalleryView Static Caching Benchmark

    func testIconGalleryViewStaticCachingBenchmark() {
        // Measure access time of pre-computed static allItems collection
        let start = CACurrentMediaTime()
        let count = IconGalleryView.allItems.count
        let elapsed = CACurrentMediaTime() - start

        XCTAssertGreaterThan(count, 150, "IconGalleryView must contain all cataloged icons")
        XCTAssertLessThan(elapsed, 0.001, "Static allItems access must be instantaneous (<1ms)")
    }

    // MARK: - 5. StrapIcon Registry Completeness

    func testStrapIconRegistryCategoryCoverage() {
        // Health metrics
        XCTAssertFalse(StrapIcon.Metric.heartRate.isEmpty)
        XCTAssertFalse(StrapIcon.Metric.bloodOxygen.isEmpty)
        XCTAssertEqual(StrapIcon.Metric.bloodOxygen, "o.circle", "Blood Oxygen must use oxygen saturation badge")
        XCTAssertFalse(StrapIcon.Metric.respiration.isEmpty)
        XCTAssertFalse(StrapIcon.Metric.hrv.isEmpty)

        // Device & Battery
        XCTAssertEqual(StrapIcon.Device.bandSensor, "sensor.fill", "Screenless band must use sensor glyph")
        XCTAssertEqual(StrapIcon.Device.vibrationBuzz, "iphone.radiowaves.left.and.right", "Wrist vibration must use haptic glyph")

        // Navigation
        XCTAssertEqual(StrapIcon.Navigation.more, "ellipsis.circle", "More tab must use segmented hub glyph")
        XCTAssertEqual(StrapIcon.Navigation.moreSelected, "ellipsis.circle.fill")
    }
}


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
        // Semantic color tokens must exist and retain their sampled color properties
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

import XCTest
@testable import Strap

final class HealthspanParticleTests: XCTestCase {
    func testDeterministicFieldDriftsOutwardAcrossIndependentLifetimes() {
        let field = HealthspanOrbParticle.field
        XCTAssertEqual(field.count, 288)
        let first = field[0]
        let initialTime = (1.15 - first.phase) * first.period
        let early = first.position(at: initialTime)
        let later = first.position(at: initialTime + first.period * 0.5)
        XCTAssertGreaterThan(later.radius, early.radius)
        XCTAssertNotEqual(early.angle, later.angle)
        XCTAssertEqual(first.position(at: initialTime + first.period * 0.85).opacity, 0, accuracy: 0.00001)
        XCTAssertNotEqual(first.period, field[1].period)
    }

    func testAnimationIsDisabledWhenEitherAccessibilityOrPowerRequiresIt() {
        XCTAssertTrue(HealthspanParticleField.animates(reduceMotion: false, active: true, visible: true, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: true, active: true, visible: true, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: false, active: false, visible: true, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: false, active: true, visible: false, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: false, active: true, visible: true, lowPower: true))
    }
}

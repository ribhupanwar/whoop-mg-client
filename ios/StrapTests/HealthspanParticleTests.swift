import XCTest
@testable import Strap

final class HealthspanParticleTests: XCTestCase {
    func testDeterministicFieldDriftsOutwardAcrossIndependentLifetimes() {
        let field = HealthspanOrbParticle.field
        XCTAssertEqual(field, HealthspanOrbParticle.makeField(seed: 0x8C42C0DE))
        XCTAssertEqual(HealthspanOrbParticle.makeField(seed: 42), HealthspanOrbParticle.makeField(seed: 42))
        XCTAssertNotEqual(field, HealthspanOrbParticle.makeField(seed: 42))
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

    func testParticleSamplingPerformance() {
        let field = HealthspanOrbParticle.field
        measure {
            var opacity = 0.0
            for frame in 0..<120 {
                for particle in field {
                    opacity += particle.position(at: Double(frame) / 60).opacity
                }
            }
            XCTAssertGreaterThan(opacity, 0)
        }
    }

    func testAnimationIsDisabledWhenEitherAccessibilityOrPowerRequiresIt() {
        XCTAssertTrue(HealthspanParticleField.animates(reduceMotion: false, active: true, visible: true, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: true, active: true, visible: true, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: false, active: false, visible: true, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: false, active: true, visible: false, lowPower: false))
        XCTAssertFalse(HealthspanParticleField.animates(reduceMotion: false, active: true, visible: true, lowPower: true))
    }
}

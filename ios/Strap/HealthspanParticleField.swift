import SwiftUI

struct HealthspanOrbParticle: Equatable {
    let angle: Double
    let phase: Double
    let period: Double
    let drift: Double
    let startRadius: Double
    let size: Double

    static let field = makeField(seed: 0x8C42C0DE)

    static func makeField(seed: UInt64) -> [Self] {
        var state = seed
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 40) / 16_777_216
        }
        return (0..<288).map { index in
            let angle = next() * 2 * .pi
            let depth = next()
            return Self(angle: angle + 0.21 * sin(3 * angle), phase: next(),
                        period: 6 + 12 * next(), drift: (next() - 0.5) * 0.52,
                        startRadius: 0.29 + 0.41 * depth,
                        size: (index.isMultiple(of: 10) ? 2.9 : 0.65) + depth * 1.4)
        }
    }

    func position(at elapsed: Double) -> (angle: Double, radius: Double, opacity: Double) {
        let lifetime = phase + elapsed / period
        let progress = lifetime - floor(lifetime)
        let radius = startRadius + (0.985 - startRadius) * progress
        let fade = min(1, min(progress * 6, (1 - progress) * 5))
        return (angle + drift * progress + 0.08 * sin(4 * progress + phase * 6),
                radius, fade * (0.43 + radius * 0.57))
    }
}

struct HealthspanParticleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var epoch = Date()

    static func animates(reduceMotion: Bool, active: Bool, visible: Bool, lowPower: Bool) -> Bool {
        !reduceMotion && active && visible && !lowPower
    }

    var body: some View {
        GeometryReader { proxy in
            if Self.animates(reduceMotion: reduceMotion, active: scenePhase == .active,
                             visible: visible, lowPower: lowPower), proxy.size.width >= 150 {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    canvas(elapsed: max(0, timeline.date.timeIntervalSince(epoch)))
                }
            } else {
                canvas(elapsed: 0)
            }
        }
        .onScrollVisibilityChange(threshold: 0.05) { visible = $0 }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func canvas(elapsed: Double) -> some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let diameter = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let cyan = Color(hex: 0x54D7E9)
            let base = diameter * 0.456 * (1 + 0.011 * sin(elapsed * 0.5))
            func membrane(_ angle: Double) -> Double {
                1 + 0.035 * sin(3 * angle - elapsed * 0.16)
                    + 0.019 * cos(5 * angle + elapsed * 0.12)
                    + 0.012 * sin(8 * angle - elapsed * 0.19)
            }
            func point(angle: Double, radius: Double) -> CGPoint {
                CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            }

            var edge = Path()
            for index in 0..<96 {
                let angle = Double(index) * 2 * .pi / 96
                let position = point(angle: angle, radius: base * membrane(angle))
                if index == 0 { edge.move(to: position) } else { edge.addLine(to: position) }
            }
            edge.closeSubpath()
            context.fill(edge, with: .radialGradient(
                Gradient(stops: [.init(color: .black, location: 0.32),
                                 .init(color: Color(hex: 0x06232F), location: 0.62),
                                 .init(color: Color(hex: 0x167487), location: 0.9),
                                 .init(color: Color(hex: 0x0D5366), location: 1)]),
                center: center, startRadius: 0, endRadius: base))
            var clipped = context
            clipped.clip(to: edge)
            var dust = Array(repeating: Path(), count: 5)
            var glows = Path()
            let scale = diameter / 300
            for particle in HealthspanOrbParticle.field {
                let state = particle.position(at: elapsed)
                let location = point(angle: state.angle, radius: base * membrane(state.angle) * state.radius)
                let dot = particle.size * scale
                let level = min(4, Int(state.opacity * 5))
                guard level > 0 else { continue }
                dust[level].addEllipse(in: CGRect(x: location.x - dot / 2, y: location.y - dot / 2,
                                                  width: dot, height: dot))
                if particle.size > 2.9 && level >= 2 {
                    let glow = dot * 2.4
                    glows.addEllipse(in: CGRect(x: location.x - glow / 2, y: location.y - glow / 2,
                                                width: glow, height: glow))
                }
            }
            clipped.drawLayer { glow in
                glow.addFilter(.blur(radius: max(0.5, 2 * scale)))
                glow.fill(glows, with: .color(cyan.opacity(0.42)))
            }
            for level in 1..<dust.count {
                clipped.fill(dust[level], with: .color(cyan.opacity(Double(level) * 0.19)))
            }
            context.stroke(edge, with: .linearGradient(
                Gradient(colors: [cyan.opacity(0.75), Color(hex: 0x4581BB).opacity(0.35), cyan.opacity(0.7)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1.2)
        }
    }
}

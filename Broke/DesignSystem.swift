import Combine
import SwiftUI
import UIKit

struct DesignTokens: Equatable {
    var primaryRed = 0.82
    var primaryGreen = 1.0
    var primaryBlue = 0.4

    var secondaryRed = 0.102
    var secondaryGreen = 0.227
    var secondaryBlue = 0.62

    // Colors used while a list is locked. Default to a swap of the
    // unlocked primary/secondary so the stock look is unchanged.
    var lockedPrimaryRed = 0.102
    var lockedPrimaryGreen = 0.227
    var lockedPrimaryBlue = 0.62

    var lockedSecondaryRed = 0.82
    var lockedSecondaryGreen = 1.0
    var lockedSecondaryBlue = 0.4

    var accentPinkRed = 1.0
    var accentPinkGreen = 0.6
    var accentPinkBlue = 0.8

    var accentBlueRed = 0.651
    var accentBlueGreen = 0.757
    var accentBlueBlue = 1.0

    var surfaceRed = 1.0
    var surfaceGreen = 1.0
    var surfaceBlue = 1.0

    var textRed = 0.071
    var textGreen = 0.071
    var textBlue = 0.071

    var mutedRed = 0.949
    var mutedGreen = 0.949
    var mutedBlue = 0.949

    var signalRed = 1.0
    var signalGreen = 0.42
    var signalBlue = 0.29

    var spacingScale = 1.0
    var radiusScale = 0.65
    var typeScale = 1.0
    var heroScale = 1.0
    var shadowScale = 0.85

    static let production = DesignTokens()

    var primary: Color { rgb(primaryRed, primaryGreen, primaryBlue) }
    var secondary: Color { rgb(secondaryRed, secondaryGreen, secondaryBlue) }
    var lockedPrimary: Color { rgb(lockedPrimaryRed, lockedPrimaryGreen, lockedPrimaryBlue) }
    var lockedSecondary: Color { rgb(lockedSecondaryRed, lockedSecondaryGreen, lockedSecondaryBlue) }
    var accentPink: Color { rgb(accentPinkRed, accentPinkGreen, accentPinkBlue) }
    var accentBlue: Color { rgb(accentBlueRed, accentBlueGreen, accentBlueBlue) }
    var surface: Color { rgb(surfaceRed, surfaceGreen, surfaceBlue) }
    var text: Color { rgb(textRed, textGreen, textBlue) }
    var muted: Color { rgb(mutedRed, mutedGreen, mutedBlue) }
    var signal: Color { rgb(signalRed, signalGreen, signalBlue) }

    var canvas: Color { surface }
    var ink: Color { text }

    /// Primary color for the current lock state (unlocked uses `primary`,
    /// locked uses the dedicated `lockedPrimary`).
    func primaryFor(locked: Bool) -> Color { locked ? lockedPrimary : primary }

    /// Secondary color for the current lock state.
    func secondaryFor(locked: Bool) -> Color { locked ? lockedSecondary : secondary }

    func cardAccent(_ index: Int) -> Color {
        switch index % 3 {
        case 0: primary
        case 1: accentPink
        default: accentBlue
        }
    }

    func spacing(_ value: CGFloat) -> CGFloat { value * CGFloat(spacingScale) }
    func radius(_ value: CGFloat) -> CGFloat { value * CGFloat(radiusScale) }
    func type(_ value: CGFloat) -> CGFloat { value * CGFloat(typeScale) }
    func hero(_ value: CGFloat) -> CGFloat { value * CGFloat(heroScale) }
    func shadow(_ value: CGFloat) -> CGFloat { value * CGFloat(shadowScale) }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }
}

struct DesignPreset: Identifiable {
    let id = UUID()
    var name: String
    var tokens: DesignTokens
}

final class DesignSettings: ObservableObject {
    @Published var tokens = DesignTokens.production

    func reset() {
        tokens = .production
    }

    func apply(_ preset: DesignPreset) {
        tokens = preset.tokens
    }

    func update(_ transform: (inout DesignTokens) -> Void) {
        var updated = tokens
        transform(&updated)
        tokens = updated
    }

    /// Built-in palettes. The first entry, "Citrus", is the saved snapshot of
    /// the current production look (lime + navy, with the navy/lime swap while
    /// locked).
    static let presets: [DesignPreset] = [
        DesignPreset(name: "Citrus", tokens: .production),
        DesignPreset(name: "Grape Soda", tokens: palette(
            primary: (0.72, 0.55, 0.98),
            secondary: (0.28, 0.16, 0.45),
            lockedPrimary: (0.28, 0.16, 0.45),
            lockedSecondary: (0.72, 0.55, 0.98),
            accentPink: (1.0, 0.7, 0.85),
            accentBlue: (0.7, 0.8, 1.0)
        )),
        DesignPreset(name: "Sunset", tokens: palette(
            primary: (1.0, 0.72, 0.3),
            secondary: (0.78, 0.25, 0.36),
            lockedPrimary: (0.78, 0.25, 0.36),
            lockedSecondary: (1.0, 0.72, 0.3),
            accentPink: (1.0, 0.62, 0.6),
            accentBlue: (0.99, 0.85, 0.6)
        ))
    ]

    private static func palette(
        primary: (Double, Double, Double),
        secondary: (Double, Double, Double),
        lockedPrimary: (Double, Double, Double),
        lockedSecondary: (Double, Double, Double),
        accentPink: (Double, Double, Double),
        accentBlue: (Double, Double, Double)
    ) -> DesignTokens {
        var tokens = DesignTokens.production
        tokens.primaryRed = primary.0; tokens.primaryGreen = primary.1; tokens.primaryBlue = primary.2
        tokens.secondaryRed = secondary.0; tokens.secondaryGreen = secondary.1; tokens.secondaryBlue = secondary.2
        tokens.lockedPrimaryRed = lockedPrimary.0; tokens.lockedPrimaryGreen = lockedPrimary.1; tokens.lockedPrimaryBlue = lockedPrimary.2
        tokens.lockedSecondaryRed = lockedSecondary.0; tokens.lockedSecondaryGreen = lockedSecondary.1; tokens.lockedSecondaryBlue = lockedSecondary.2
        tokens.accentPinkRed = accentPink.0; tokens.accentPinkGreen = accentPink.1; tokens.accentPinkBlue = accentPink.2
        tokens.accentBlueRed = accentBlue.0; tokens.accentBlueGreen = accentBlue.1; tokens.accentBlueBlue = accentBlue.2
        return tokens
    }
}

private struct DesignTokensKey: EnvironmentKey {
    static let defaultValue = DesignTokens.production
}

extension EnvironmentValues {
    var designTokens: DesignTokens {
        get { self[DesignTokensKey.self] }
        set { self[DesignTokensKey.self] = newValue }
    }
}

private extension Color {
    func designRGB() -> (red: Double, green: Double, blue: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }
}

struct PlayfulBackdrop: View {
    var tokens: DesignTokens

    var body: some View {
        ZStack {
            tokens.surface.ignoresSafeArea()

            Circle()
                .fill(tokens.primary.opacity(0.18))
                .frame(width: tokens.hero(140))
                .offset(x: -tokens.hero(150), y: -tokens.hero(210))

            Circle()
                .fill(tokens.accentPink.opacity(0.16))
                .frame(width: tokens.hero(96))
                .offset(x: tokens.hero(130), y: -tokens.hero(120))

            Circle()
                .fill(tokens.accentBlue.opacity(0.2))
                .frame(width: tokens.hero(120))
                .offset(x: tokens.hero(160), y: tokens.hero(280))
        }
    }
}

enum FruitKind: CaseIterable {
    case apple, orange, lemon, strawberry, pear, blueberry, watermelon, peach

    var bodyColor: Color {
        switch self {
        case .apple: Color(red: 0.91, green: 0.24, blue: 0.27)
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.16)
        case .lemon: Color(red: 1.0, green: 0.83, blue: 0.25)
        case .strawberry: Color(red: 0.93, green: 0.26, blue: 0.36)
        case .pear: Color(red: 0.74, green: 0.84, blue: 0.36)
        case .blueberry: Color(red: 0.40, green: 0.47, blue: 0.87)
        case .watermelon: Color(red: 0.36, green: 0.72, blue: 0.38)
        case .peach: Color(red: 1.0, green: 0.71, blue: 0.59)
        }
    }
}

enum FruitPersonality: CaseIterable {
    case plain, awe, cool, groovy, freckled, wink, blush, sleepy
}

struct FruitPersona {
    var fruit: FruitKind
    var personality: FruitPersonality

    static let lineup: [FruitPersona] = [
        FruitPersona(fruit: .strawberry, personality: .freckled),
        FruitPersona(fruit: .orange, personality: .cool),
        FruitPersona(fruit: .pear, personality: .groovy),
        FruitPersona(fruit: .lemon, personality: .awe),
        FruitPersona(fruit: .apple, personality: .blush),
        FruitPersona(fruit: .blueberry, personality: .wink),
        FruitPersona(fruit: .watermelon, personality: .plain),
        FruitPersona(fruit: .peach, personality: .sleepy)
    ]

    static func forBlockList(_ index: Int) -> FruitPersona {
        lineup[((index % lineup.count) + lineup.count) % lineup.count]
    }

    static func forStatus(isLocked: Bool) -> FruitPersona {
        isLocked
            ? FruitPersona(fruit: .blueberry, personality: .cool)
            : FruitPersona(fruit: .orange, personality: .groovy)
    }
}

struct FruitMotionPose: Equatable {
    var bodyYOffset: CGFloat = 0
    var bodyRotation: CGFloat = 0
    var bodyScaleX: CGFloat = 1
    var bodyScaleY: CGFloat = 1
    var armSwing: CGFloat = 0
    var legBend: CGFloat = 0
    var smileBoost: CGFloat = 0
    /// How far the feet rise off the floor line (in radius units). 0 = planted.
    var feetLift: CGFloat = 0
    /// Progress through the jump window, 0...1; 0 while idle.
    var jumpProgress: CGFloat = 0
    /// Leg/body spring squeeze: 0 = neutral, 1 = fully compressed.
    var springCompression: CGFloat = 0
    /// Damped post-landing oscillation, decays to 0.
    var settleOscillation: CGFloat = 0
    /// Sparkle burst phase, 0...1; 0 while idle.
    var sparkleProgress: CGFloat = 0
    /// Sparkle intensity envelope, 0...1.
    var sparkleBurstStrength: CGFloat = 0

    static let still = FruitMotionPose()

    /// Calm idle with a phased happy jump: anticipation crouch → launch → airborne
    /// → landing squash → damped spring settle. Deterministic 5.5s loop.
    static func strawberryIdle(at time: TimeInterval) -> FruitMotionPose {
        let sway = sin(time * FruitMotionConstants.swaySpeed)
        let breathe = sin(time * FruitMotionConstants.bobSpeed)
        let breatheOffset = CGFloat(breathe) * FruitMotionConstants.bobHeight

        var pose = FruitMotionPose(
            bodyYOffset: breatheOffset,
            bodyRotation: CGFloat(sway) * FruitMotionConstants.swayAngle,
            armSwing: CGFloat(sway) * FruitMotionConstants.armSwingAngle
        )

        let cycle = FruitMotionConstants.cycleLength
        let jumpDuration = FruitMotionConstants.jumpDuration
        let phase = time.truncatingRemainder(dividingBy: cycle)
        let jumpStart = cycle - jumpDuration

        guard phase >= jumpStart else { return pose }

        let t = CGFloat((phase - jumpStart) / jumpDuration)
        let c = FruitMotionConstants.self

        // Phase boundaries within the jump window.
        let anticipationEnd: CGFloat = 0.12
        let launchEnd: CGFloat = 0.28
        let airborneEnd: CGFloat = 0.58
        let landingEnd: CGFloat = 0.72

        pose.jumpProgress = t

        if t < anticipationEnd {
            // Anticipation: crouch, legs compress, tiny squash.
            let p = easeIn(t / anticipationEnd)
            pose.springCompression = p
            pose.bodyYOffset = breatheOffset + p * c.anticipationDrop
            pose.bodyScaleX = 1 + p * c.squashX
            pose.bodyScaleY = 1 - p * c.squashY
            pose.legBend = p * c.legCompress

        } else if t < launchEnd {
            // Launch: spring releases, body rockets upward, legs extend.
            let p = (t - anticipationEnd) / (launchEnd - anticipationEnd)
            let release = easeOut(p)
            let hop = release * c.jumpHeight * 0.35
            pose.springCompression = (1 - release)
            pose.bodyYOffset = breatheOffset - hop
            pose.bodyScaleX = 1 - release * c.stretchX * 0.5
            pose.bodyScaleY = 1 + release * c.stretchY * 0.5
            pose.legBend = (1 - release) * c.legCompress + release * c.legExtend
            pose.feetLift = hop + release * c.feetLiftBoost
            pose.armSwing = release * c.jumpArmLift
            pose.smileBoost = release * 0.4
            pose.sparkleProgress = p
            pose.sparkleBurstStrength = release * 0.7

        } else if t < airborneEnd {
            // Airborne: higher arc, legs tuck, body stretches tall.
            let p = (t - launchEnd) / (airborneEnd - launchEnd)
            let arc = sin(p * .pi)
            let hop = (c.jumpHeight * 0.35 + arc * c.jumpHeight * 0.65)
            pose.springCompression = max(0, (1 - arc) * 0.15)
            pose.bodyYOffset = breatheOffset - hop
            pose.bodyScaleX = 1 - arc * c.stretchX * 0.3
            pose.bodyScaleY = 1 + arc * c.stretchY
            pose.legBend = c.legExtend + arc * c.legTuck
            pose.feetLift = hop + arc * c.feetLiftBoost
            pose.armSwing = c.jumpArmLift + arc * 0.15
            pose.smileBoost = 0.4 + arc * 0.6
            pose.sparkleProgress = 0.5 + p * 0.5
            pose.sparkleBurstStrength = 0.7 + arc * 0.3

        } else if t < landingEnd {
            // Landing: descend, impact squash, legs compress, sparkles fade.
            let p = (t - airborneEnd) / (landingEnd - airborneEnd)
            let descend = 1 - easeIn(p)
            let hop = descend * c.jumpHeight * 0.35
            let impact = easeIn(p)
            pose.springCompression = impact
            pose.bodyYOffset = breatheOffset - hop
            pose.bodyScaleX = 1 + impact * c.squashX
            pose.bodyScaleY = 1 - impact * c.squashY
            pose.legBend = c.legCompress * impact + (1 - impact) * c.legExtend
            pose.feetLift = hop
            pose.armSwing = c.jumpArmLift * (1 - p * 0.5)
            pose.smileBoost = (1 - p) * 0.5
            pose.sparkleProgress = 1 - p
            pose.sparkleBurstStrength = (1 - p) * 0.5

        } else {
            // Settle: damped spring oscillation back to equilibrium.
            let p = (t - landingEnd) / (1 - landingEnd)
            let oscillation = dampedSpring(p, damping: c.settleDamping, frequency: c.settleFrequency)
            pose.settleOscillation = oscillation
            pose.bodyYOffset = breatheOffset + oscillation * c.settleBody
            pose.bodyScaleX = 1 + abs(oscillation) * c.squashX * 0.5
            pose.bodyScaleY = 1 - abs(oscillation) * c.squashY * 0.5
            pose.legBend = abs(oscillation) * c.legCompress * 0.6
            pose.springCompression = abs(oscillation) * 0.5
            pose.armSwing = CGFloat(sway) * c.armSwingAngle + oscillation * 0.08
        }

        return pose
    }

    private static func easeIn(_ t: CGFloat) -> CGFloat { t * t }
    private static func easeOut(_ t: CGFloat) -> CGFloat { 1 - (1 - t) * (1 - t) }

    /// Damped sine that starts at 1 and decays to 0.
    private static func dampedSpring(_ t: CGFloat, damping: CGFloat, frequency: CGFloat) -> CGFloat {
        exp(-damping * t) * sin(t * frequency * .pi * 2)
    }
}

enum FruitMotionConstants {
    /// Sway ~4s per cycle, breathing bob ~3.4s per cycle.
    static let swaySpeed = 2 * Double.pi / 4.0
    static let bobSpeed = 2 * Double.pi / 3.4

    /// Calm, grounded idle amounts.
    static let bobHeight: CGFloat = 0.03
    static let swayAngle: CGFloat = 0.02
    static let armSwingAngle: CGFloat = 0.07

    /// Jump cycle timing.
    static let cycleLength: TimeInterval = 5.5
    static let jumpDuration: TimeInterval = 0.85

    /// Jump height and body shape.
    static let jumpHeight: CGFloat = 0.44
    static let anticipationDrop: CGFloat = 0.07
    static let feetLiftBoost: CGFloat = 0.14
    static let squashX: CGFloat = 0.09
    static let squashY: CGFloat = 0.1
    static let stretchX: CGFloat = 0.04
    static let stretchY: CGFloat = 0.06
    static let jumpArmLift: CGFloat = 0.65

    /// Spring leg amounts.
    static let legCompress: CGFloat = 0.55
    static let legExtend: CGFloat = 0.12
    static let legTuck: CGFloat = 0.28

    /// Post-landing settle.
    static let settleDamping: CGFloat = 4.5
    static let settleFrequency: CGFloat = 2.2
    static let settleBody: CGFloat = 0.035
}

struct AnimatedStrawberryMascot: View {
    var size: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let pose = FruitMotionPose.strawberryIdle(
                at: timeline.date.timeIntervalSinceReferenceDate
            )
            ZStack {
                if pose.sparkleBurstStrength > 0.01 {
                    Canvas { context, canvasSize in
                        drawSparkles(context, canvasSize: canvasSize, pose: pose)
                    }
                    .frame(width: size, height: size)
                    .allowsHitTesting(false)
                }

                FruitCharacter(
                    fruit: .strawberry,
                    personality: .freckled,
                    size: size,
                    pose: pose,
                    showsArms: true
                )
            }
            .frame(width: size, height: size)
        }
    }

    /// Radial sparkle burst around the whole mascot. Particles are placed at
    /// fixed angles and move outward deterministically from index + phase.
    private func drawSparkles(_ context: GraphicsContext, canvasSize: CGSize, pose: FruitMotionPose) {
        let s = min(canvasSize.width, canvasSize.height)
        let center = CGPoint(x: canvasSize.width * 0.5, y: s * 0.46 + pose.bodyYOffset * s * 0.31)
        let r = s * 0.31
        let strength = pose.sparkleBurstStrength
        let progress = pose.sparkleProgress
        let count = 15

        let colors: [Color] = [
            .white,
            Color(red: 1.0, green: 0.95, blue: 0.6),
            Color(red: 1.0, green: 0.78, blue: 0.86),
            Color(red: 0.95, green: 0.35, blue: 0.42).opacity(0.85)
        ]

        // Envelope: quick rise, fade out before landing settle.
        let envelope = sin(min(1, progress) * .pi) * strength

        for i in 0..<count {
            // Fixed angle around the berry; stagger start times per particle.
            let baseAngle = (CGFloat(i) / CGFloat(count)) * 2 * .pi - .pi / 2
            let angle = baseAngle + CGFloat((i * 17) % 7 - 3) * 0.06
            let stagger = CGFloat((i * 41) % 100) / 100
            let local = min(1, max(0, progress * 1.15 - stagger * 0.2))

            // Emitter on a loose ring around the mascot body.
            let ringR = r * (0.55 + CGFloat(i % 3) * 0.12)
            let emitter = CGPoint(
                x: center.x + cos(angle) * ringR * 0.85,
                y: center.y + sin(angle) * ringR * 0.9
            )

            // Radial outward travel with a tiny upward charm drift.
            let travel = r * (0.15 + local * 0.75) * strength
            let p = CGPoint(
                x: emitter.x + cos(angle) * travel,
                y: emitter.y + sin(angle) * travel - local * r * 0.06
            )

            // Soften sparkles that would land directly on the face band.
            let facePenalty: CGFloat = abs(sin(angle)) < 0.35 && abs(p.y - center.y) < r * 0.35 ? 0.35 : 1.0

            let twinkle = 0.55 + 0.45 * sin((progress * 7 + stagger * 5) * .pi)
            let alpha = Double(envelope * twinkle * facePenalty)
            guard alpha > 0.03 else { continue }

            let sizeScale = (1 - local * 0.35) * (0.55 + envelope * 0.45)
            let particleR = r * 0.09 * sizeScale
            let color = colors[i % colors.count].opacity(min(1, max(0, alpha)))

            switch i % 3 {
            case 0:
                context.fill(sparkleStar(center: p, radius: particleR), with: .color(color))
            case 1:
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - particleR * 0.5, y: p.y - particleR * 0.5, width: particleR, height: particleR)),
                    with: .color(color)
                )
            default:
                context.fill(sparkleDiamond(center: p, radius: particleR), with: .color(color))
            }
        }
    }

    private func sparkleStar(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let inner = radius * 0.38
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let rad = i % 2 == 0 ? radius : inner
            let point = CGPoint(x: center.x + cos(angle) * rad, y: center.y + sin(angle) * rad)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func sparkleDiamond(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let w = radius * 0.7
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + w, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - w, y: center.y))
        path.closeSubpath()
        return path
    }
}

struct FruitCharacter: View {
    var fruit: FruitKind
    var personality: FruitPersonality
    var size: CGFloat
    var pose: FruitMotionPose = .still
    var showsArms: Bool = false

    private let ink = Color(red: 0.13, green: 0.11, blue: 0.13)
    private let leafColor = Color(red: 0.27, green: 0.66, blue: 0.33)
    private let stemColor = Color(red: 0.45, green: 0.30, blue: 0.18)
    private let shine = Color.white.opacity(0.5)

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let baseCenter = CGPoint(x: canvasSize.width * 0.5, y: s * 0.46)
            let radius = s * 0.31
            let lw = max(2, s * 0.03)
            let center = CGPoint(
                x: baseCenter.x,
                y: baseCenter.y + pose.bodyYOffset * radius
            )

            drawLegs(context, baseCenter: baseCenter, center: center, radius: radius, lw: lw)

            var bodyContext = context
            bodyContext.translateBy(x: center.x, y: center.y)
            bodyContext.rotate(by: Angle(radians: Double(pose.bodyRotation)))
            bodyContext.scaleBy(x: pose.bodyScaleX, y: pose.bodyScaleY)
            bodyContext.translateBy(x: -center.x, y: -center.y)

            if showsArms {
                drawArms(bodyContext, center: center, radius: radius, lw: lw)
            }

            drawBodyShell(bodyContext, center: center, radius: radius, lw: lw)

            if fruit == .strawberry {
                drawCrown(bodyContext, center: CGPoint(x: center.x, y: center.y - radius * 0.66), scale: radius)
                drawSeeds(bodyContext, center: center, radius: radius)
            }

            if personality == .groovy {
                drawHeadphones(bodyContext, center: center, radius: radius, lw: lw)
            }

            drawFace(bodyContext, center: center, radius: radius, lw: lw)
        }
        .frame(width: size, height: size)
    }

    // MARK: Body

    private func drawBodyShell(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
        let color = fruit.bodyColor

        switch fruit {
        case .apple:
            drawStem(context, top: CGPoint(x: center.x, y: center.y - r), height: r * 0.4, lw: lw)
            drawLeaf(context, at: CGPoint(x: center.x + r * 0.32, y: center.y - r * 1.05), scale: r)
            context.fill(circlePath(center: center, radius: r), with: .color(color))
            drawShine(context, center: center, radius: r)

        case .orange:
            drawLeaf(context, at: CGPoint(x: center.x + r * 0.18, y: center.y - r * 1.02), scale: r * 0.85)
            context.fill(circlePath(center: center, radius: r), with: .color(color))
            drawShine(context, center: center, radius: r)

        case .lemon:
            let rect = CGRect(x: center.x - r * 1.08, y: center.y - r * 0.84, width: r * 2.16, height: r * 1.68)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.fill(circlePath(center: CGPoint(x: center.x - r * 1.05, y: center.y), radius: r * 0.16), with: .color(color))
            context.fill(circlePath(center: CGPoint(x: center.x + r * 1.05, y: center.y), radius: r * 0.16), with: .color(color))
            drawShine(context, center: center, radius: r)

        case .strawberry:
            context.fill(strawberryPath(center: center, radius: r), with: .color(color))
            drawShine(context, center: CGPoint(x: center.x + r * 0.04, y: center.y - r * 0.02), radius: r * 0.72)

        case .pear:
            context.fill(circlePath(center: CGPoint(x: center.x, y: center.y + r * 0.32), radius: r * 0.92), with: .color(color))
            context.fill(circlePath(center: CGPoint(x: center.x, y: center.y - r * 0.42), radius: r * 0.58), with: .color(color))
            drawStem(context, top: CGPoint(x: center.x, y: center.y - r * 0.96), height: r * 0.3, lw: lw)
            drawLeaf(context, at: CGPoint(x: center.x + r * 0.26, y: center.y - r * 1.02), scale: r * 0.8)
            drawShine(context, center: CGPoint(x: center.x, y: center.y + r * 0.2), radius: r * 0.92)

        case .blueberry:
            context.fill(circlePath(center: center, radius: r), with: .color(color))
            drawBerryCrown(context, center: CGPoint(x: center.x, y: center.y - r * 0.88), scale: r * 0.5)
            drawShine(context, center: center, radius: r)

        case .watermelon:
            context.fill(circlePath(center: center, radius: r), with: .color(color))
            drawMelonStripes(context, center: center, radius: r, lw: lw)
            drawShine(context, center: center, radius: r)

        case .peach:
            drawLeaf(context, at: CGPoint(x: center.x + r * 0.24, y: center.y - r * 1.0), scale: r * 0.8)
            context.fill(circlePath(center: center, radius: r), with: .color(color))
            var cleft = Path()
            cleft.move(to: CGPoint(x: center.x + r * 0.02, y: center.y - r * 0.7))
            cleft.addQuadCurve(to: CGPoint(x: center.x + r * 0.02, y: center.y + r * 0.55), control: CGPoint(x: center.x + r * 0.2, y: center.y))
            context.stroke(cleft, with: .color(Color(red: 0.92, green: 0.55, blue: 0.45)), style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round))
            drawShine(context, center: center, radius: r)
        }
    }

    private func circlePath(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func strawberryPath(center: CGPoint, radius r: CGFloat) -> Path {
        // Slim, taller berry: softly rounded shoulders up top, gently tapering
        // sides, and a soft (not sharp) bottom point. Cute and sticker-like,
        // avoiding the wide "fat heart" silhouette.
        var p = Path()
        let cx = center.x
        let topY = center.y - r * 0.78
        let halfW = r * 0.8
        let wideY = center.y - r * 0.22
        let botY = center.y + r * 1.14

        let leftWide = CGPoint(x: cx - halfW, y: wideY)
        let rightWide = CGPoint(x: cx + halfW, y: wideY)
        let bottom = CGPoint(x: cx, y: botY)

        p.move(to: bottom)
        // Lower-left side tapering up to the widest point.
        p.addQuadCurve(to: leftWide, control: CGPoint(x: cx - halfW * 0.74, y: center.y + r * 0.78))
        // Upper-left rounded shoulder up to the top.
        p.addQuadCurve(to: CGPoint(x: cx, y: topY), control: CGPoint(x: cx - halfW * 0.92, y: topY))
        // Rounded top over to the right shoulder.
        p.addQuadCurve(to: rightWide, control: CGPoint(x: cx + halfW * 0.92, y: topY))
        // Lower-right side back down to the soft point.
        p.addQuadCurve(to: bottom, control: CGPoint(x: cx + halfW * 0.74, y: center.y + r * 0.78))
        p.closeSubpath()
        return p
    }

    private func drawStem(_ context: GraphicsContext, top: CGPoint, height: CGFloat, lw: CGFloat) {
        var stem = Path()
        stem.move(to: CGPoint(x: top.x, y: top.y + height * 0.4))
        stem.addQuadCurve(to: CGPoint(x: top.x - height * 0.2, y: top.y - height * 0.6), control: CGPoint(x: top.x + height * 0.2, y: top.y))
        context.stroke(stem, with: .color(stemColor), style: StrokeStyle(lineWidth: lw * 1.1, lineCap: .round))
    }

    private func drawLeaf(_ context: GraphicsContext, at point: CGPoint, scale: CGFloat) {
        var leaf = Path()
        leaf.move(to: CGPoint(x: point.x - scale * 0.05, y: point.y + scale * 0.12))
        leaf.addQuadCurve(to: CGPoint(x: point.x + scale * 0.42, y: point.y - scale * 0.18), control: CGPoint(x: point.x + scale * 0.34, y: point.y + scale * 0.14))
        leaf.addQuadCurve(to: CGPoint(x: point.x - scale * 0.05, y: point.y + scale * 0.12), control: CGPoint(x: point.x + scale * 0.12, y: point.y - scale * 0.22))
        context.fill(leaf, with: .color(leafColor))
    }

    private func drawCrown(_ context: GraphicsContext, center: CGPoint, scale r: CGFloat) {
        // Small, neat leafy cap that sits on the slim top: a tidy fan of short
        // rounded leaf blobs with a modest green hub.
        let count = 5
        let leafLen = r * 0.4
        let leafW = r * 0.24
        for i in 0..<count {
            let frac = CGFloat(i) / CGFloat(count - 1)
            let spread = (frac - 0.5) * 2 // -1 ... 1
            let dir = -CGFloat.pi / 2 + spread * 1.15
            let baseX = center.x + spread * r * 0.2
            let baseY = center.y + abs(spread) * r * 0.08 + r * 0.06

            var leafContext = context
            leafContext.translateBy(x: baseX, y: baseY)
            leafContext.rotate(by: Angle(radians: Double(dir + .pi / 2)))
            let rect = CGRect(x: -leafW / 2, y: -leafLen, width: leafW, height: leafLen)
            leafContext.fill(Path(ellipseIn: rect), with: .color(leafColor))
        }
        // Modest green hub so the leaves read as one neat crown.
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - r * 0.26, y: center.y - r * 0.06, width: r * 0.52, height: r * 0.38)),
            with: .color(leafColor)
        )
    }

    private func drawSeeds(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat) {
        let seed = Color(red: 1.0, green: 0.93, blue: 0.55)
        // ~12 small teardrop seeds in curved rows following the berry shape,
        // kept off the central face band (eyes ~ -0.02r, mouth ~ 0.26r).
        let spots: [CGPoint] = [
            // Upper row (under the crown, above the eyes).
            CGPoint(x: -0.28, y: -0.32), CGPoint(x: 0.0, y: -0.36), CGPoint(x: 0.28, y: -0.32),
            // Cheek sides, flanking the eyes.
            CGPoint(x: -0.52, y: 0.06), CGPoint(x: 0.52, y: 0.06),
            CGPoint(x: -0.46, y: 0.34), CGPoint(x: 0.46, y: 0.34),
            // Lower belly rows (below the mouth).
            CGPoint(x: -0.3, y: 0.62), CGPoint(x: 0.0, y: 0.66), CGPoint(x: 0.3, y: 0.62),
            CGPoint(x: -0.15, y: 0.9), CGPoint(x: 0.15, y: 0.9)
        ]
        for spot in spots {
            let p = CGPoint(x: center.x + spot.x * r, y: center.y + spot.y * r)
            // Tilt each seed so its point aims toward the berry center.
            let angle = atan2(p.y - center.y, p.x - center.x) + .pi / 2
            var seedContext = context
            seedContext.translateBy(x: p.x, y: p.y)
            seedContext.rotate(by: Angle(radians: Double(angle)))
            let rect = CGRect(x: -r * 0.028, y: -r * 0.056, width: r * 0.056, height: r * 0.112)
            seedContext.fill(Path(ellipseIn: rect), with: .color(seed))
        }
    }

    private func drawBerryCrown(_ context: GraphicsContext, center: CGPoint, scale r: CGFloat) {
        var star = Path()
        for i in 0..<5 {
            let angle = CGFloat(i) / 5 * .pi * 2 - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * r * 0.5, y: center.y + sin(angle) * r * 0.5)
            if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
        }
        star.closeSubpath()
        context.fill(star, with: .color(Color(red: 0.26, green: 0.32, blue: 0.6)))
    }

    private func drawMelonStripes(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
        let stripe = Color(red: 0.22, green: 0.5, blue: 0.24)
        for dx in [-r * 0.42, r * 0.0, r * 0.42] {
            var path = Path()
            path.move(to: CGPoint(x: center.x + dx, y: center.y - r * 0.92))
            path.addQuadCurve(
                to: CGPoint(x: center.x + dx, y: center.y + r * 0.92),
                control: CGPoint(x: center.x + dx * 1.4, y: center.y)
            )
            context.stroke(path, with: .color(stripe), style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
        }
    }

    private func drawShine(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat) {
        let rect = CGRect(x: center.x - r * 0.6, y: center.y - r * 0.62, width: r * 0.38, height: r * 0.5)
        context.fill(Path(ellipseIn: rect), with: .color(shine))
    }

    // MARK: Limbs

    private func drawArms(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
        // Roots start under the body edge (drawn before the body, so the shell
        // overlaps them and they read as connected); hands poke out the sides
        // and lift up a little during the jump.
        let shoulderY = center.y + r * 0.04
        let shoulderSpread = r * 0.6
        let stroke = StrokeStyle(lineWidth: lw * 0.9, lineCap: .round, lineJoin: .round)
        let lift = max(0, pose.armSwing) // positive during the jump

        for side in [-1.0, 1.0] {
            let shoulder = CGPoint(x: center.x + CGFloat(side) * shoulderSpread, y: shoulderY)
            let wiggle = pose.armSwing * CGFloat(-side)
            let hand = CGPoint(
                x: shoulder.x + CGFloat(side) * (r * 0.34 + lift * r * 0.12),
                y: shoulder.y + r * 0.2 - lift * r * 0.4 + sin(wiggle) * r * 0.05
            )
            var arm = Path()
            arm.move(to: shoulder)
            arm.addQuadCurve(
                to: hand,
                control: CGPoint(
                    x: shoulder.x + CGFloat(side) * r * 0.46,
                    y: shoulder.y + r * 0.02 - lift * r * 0.18
                )
            )
            context.stroke(arm, with: .color(ink), style: stroke)
        }
    }

    private func drawLegs(
        _ context: GraphicsContext,
        baseCenter: CGPoint,
        center: CGPoint,
        radius r: CGFloat,
        lw: CGFloat
    ) {
        // Hips ride with the body; feet leave the floor only when airborne.
        // Spring compression shortens the leg (knee rises); settle oscillation
        // adds a damped post-landing wobble.
        let legTop = center.y + r * 1.0 * pose.bodyScaleY
        let floorY = baseCenter.y + r * 1.4
        let footY = floorY - pose.feetLift * r
        let stroke = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        let compress = pose.springCompression + abs(pose.settleOscillation) * 0.45

        for dx in [-r * 0.2, r * 0.2] {
            let hip = CGPoint(x: center.x + dx, y: legTop)
            let foot = CGPoint(x: baseCenter.x + dx, y: footY)
            let midY = (hip.y + foot.y) * 0.5
            // Compression pulls the knee up; legBend bows it outward/inward.
            let knee = CGPoint(
                x: (hip.x + foot.x) * 0.5 + (dx > 0 ? 1 : -1) * pose.legBend * r * 0.14,
                y: midY - compress * r * 0.22 + pose.settleOscillation * r * 0.06
            )

            var leg = Path()
            leg.move(to: hip)
            leg.addQuadCurve(to: foot, control: knee)
            context.stroke(leg, with: .color(ink), style: stroke)

            let fw = r * 0.2
            context.fill(
                Path(ellipseIn: CGRect(x: foot.x - fw / 2, y: foot.y - fw * 0.18, width: fw, height: fw * 0.5)),
                with: .color(ink)
            )
        }
    }

    // MARK: Face

    private func drawFace(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
        let eyeY = center.y - r * 0.02
        let mouthY = center.y + r * 0.26 - pose.smileBoost * r * 0.035
        let gap = r * 0.25
        let eyeR = r * 0.08
        let smileWidth = r * 0.4 * (1 + pose.smileBoost * 0.22)

        switch personality {
        case .plain:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            dotEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.5 * (1 + pose.smileBoost * 0.18), lw: lw)

        case .awe:
            wideEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR * 1.4)
            wideEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR * 1.4)
            context.fill(circlePath(center: CGPoint(x: center.x, y: mouthY + r * 0.05), radius: r * 0.12), with: .color(ink))

        case .cool:
            sunglasses(context, center: CGPoint(x: center.x, y: eyeY), r: r, lw: lw)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.42 * (1 + pose.smileBoost * 0.18), lw: lw)

        case .groovy:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            dotEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.5 * (1 + pose.smileBoost * 0.18), lw: lw)

        case .freckled:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            dotEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: smileWidth, lw: lw)
            freckles(context, center: center, r: r)

        case .wink:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            arcEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR, lw: lw, up: true)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: smileWidth, lw: lw)

        case .blush:
            arcEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR, lw: lw, up: true)
            arcEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR, lw: lw, up: true)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.42 * (1 + pose.smileBoost * 0.18), lw: lw)
            blush(context, center: center, r: r)

        case .sleepy:
            arcEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR, lw: lw, up: false)
            arcEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR, lw: lw, up: false)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.3, lw: lw)
        }
    }

    private func dotEye(_ context: GraphicsContext, at point: CGPoint, r: CGFloat) {
        context.fill(circlePath(center: point, radius: r), with: .color(ink))
        context.fill(circlePath(center: CGPoint(x: point.x - r * 0.3, y: point.y - r * 0.3), radius: r * 0.32), with: .color(.white))
    }

    private func wideEye(_ context: GraphicsContext, at point: CGPoint, r: CGFloat) {
        context.fill(circlePath(center: point, radius: r), with: .color(.white))
        context.stroke(circlePath(center: point, radius: r), with: .color(ink), lineWidth: max(1.5, r * 0.22))
        context.fill(circlePath(center: point, radius: r * 0.55), with: .color(ink))
    }

    private func arcEye(_ context: GraphicsContext, at point: CGPoint, r: CGFloat, lw: CGFloat, up: Bool) {
        var path = Path()
        let dy = up ? -r * 0.9 : r * 0.7
        path.move(to: CGPoint(x: point.x - r, y: point.y))
        path.addQuadCurve(to: CGPoint(x: point.x + r, y: point.y), control: CGPoint(x: point.x, y: point.y + dy))
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: lw * 0.85, lineCap: .round))
    }

    private func smile(_ context: GraphicsContext, center: CGPoint, width: CGFloat, lw: CGFloat) {
        var path = Path()
        let curve = 0.6 + pose.smileBoost * 0.18
        path.move(to: CGPoint(x: center.x - width / 2, y: center.y))
        path.addQuadCurve(
            to: CGPoint(x: center.x + width / 2, y: center.y),
            control: CGPoint(x: center.x, y: center.y + width * curve)
        )
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: lw * 0.85, lineCap: .round))
    }

    private func freckles(_ context: GraphicsContext, center: CGPoint, r: CGFloat) {
        // Two soft freckles per cheek, kept out toward the edges.
        let freckle = ink.opacity(0.4)
        for side in [-1.0, 1.0] {
            let baseX = center.x + CGFloat(side) * r * 0.46
            let baseY = center.y + r * 0.24
            for i in 0..<2 {
                let p = CGPoint(x: baseX + CGFloat(side) * CGFloat(i) * r * 0.1, y: baseY + CGFloat(i) * r * 0.1)
                context.fill(circlePath(center: p, radius: r * 0.03), with: .color(freckle))
            }
        }
    }

    private func blush(_ context: GraphicsContext, center: CGPoint, r: CGFloat) {
        let cheek = Color(red: 1.0, green: 0.45, blue: 0.5).opacity(0.55)
        for side in [-1.0, 1.0] {
            let rect = CGRect(x: center.x + CGFloat(side) * r * 0.5 - r * 0.16, y: center.y + r * 0.16, width: r * 0.32, height: r * 0.2)
            context.fill(Path(ellipseIn: rect), with: .color(cheek))
        }
    }

    private func sunglasses(_ context: GraphicsContext, center: CGPoint, r: CGFloat, lw: CGFloat) {
        let lensW = r * 0.32
        let lensH = r * 0.26
        for dx in [-r * 0.3, r * 0.3] {
            let rect = CGRect(x: center.x + dx - lensW / 2, y: center.y - lensH / 2, width: lensW, height: lensH)
            context.fill(Path(roundedRect: rect, cornerRadius: lensH * 0.4), with: .color(ink))
            context.stroke(
                Path(roundedRect: CGRect(x: rect.minX + lensW * 0.16, y: rect.minY + lensH * 0.22, width: lensW * 0.3, height: lensH * 0.22), cornerRadius: lensH * 0.2),
                with: .color(.white.opacity(0.6)),
                lineWidth: max(1, lw * 0.4)
            )
        }
        var bridge = Path()
        bridge.move(to: CGPoint(x: center.x - r * 0.14, y: center.y))
        bridge.addLine(to: CGPoint(x: center.x + r * 0.14, y: center.y))
        context.stroke(bridge, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }

    private func drawHeadphones(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
        var band = Path()
        band.addArc(center: center, radius: r * 1.04, startAngle: .degrees(212), endAngle: .degrees(328), clockwise: false)
        context.stroke(band, with: .color(ink), style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round))

        let cupW = r * 0.26
        let cupH = r * 0.5
        for dx in [-r * 1.04, r * 1.04] {
            let rect = CGRect(x: center.x + dx - cupW / 2, y: center.y - cupH / 2, width: cupW, height: cupH)
            context.fill(Path(roundedRect: rect, cornerRadius: cupW * 0.45), with: .color(ink))
        }
    }
}

struct PrimaryCTAStyle: ButtonStyle {
    var tokens: DesignTokens
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: tokens.type(16), weight: .black, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(tokens.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: tokens.spacing(58))
            .background(
                isEnabled ? tokens.primary : tokens.muted,
                in: RoundedRectangle(cornerRadius: tokens.radius(8))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

#if DEBUG
struct DesignDebugPanel: View {
    @ObservedObject var settings: DesignSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview
                    presetControls
                    scaleControls
                    colorControls
                }
                .padding(20)
            }
            .background(settings.tokens.surface.ignoresSafeArea())
            .navigationTitle("Design System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            settings.reset()
                        }
                    }
                }
            }
        }
    }

    private var preview: some View {
        let tokens = settings.tokens

        return VStack(alignment: .leading, spacing: tokens.spacing(14)) {
            Text("Live preview")
                .font(.system(size: tokens.type(11), weight: .black, design: .rounded))
                .foregroundStyle(tokens.text.opacity(0.48))

            HStack(spacing: tokens.spacing(6)) {
                ForEach(Array(FruitPersona.lineup.prefix(4).enumerated()), id: \.offset) { _, persona in
                    FruitCharacter(fruit: persona.fruit, personality: persona.personality, size: tokens.hero(60))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, tokens.spacing(8))
            .frame(maxWidth: .infinity)
            .background(tokens.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: tokens.radius(10)))

            Button {} label: {
                Text("Scan to unlock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(tokens: tokens, isEnabled: true))
            .disabled(true)
        }
    }

    private var presetControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DesignSettings.presets) { preset in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                settings.apply(preset)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: -4) {
                                    Circle().fill(preset.tokens.primary).frame(width: 16, height: 16)
                                    Circle().fill(preset.tokens.secondary).frame(width: 16, height: 16)
                                }
                                Text(preset.name)
                                    .font(.system(size: settings.tokens.type(13), weight: .black, design: .rounded))
                            }
                            .foregroundStyle(settings.tokens.text)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(settings.tokens.surface, in: RoundedRectangle(cornerRadius: settings.tokens.radius(8)))
                            .overlay {
                                RoundedRectangle(cornerRadius: settings.tokens.radius(8))
                                    .stroke(settings.tokens.text.opacity(0.1), lineWidth: 1)
                            }
                        }
                        .buttonStyle(PressButtonStyle())
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(16)
        .background(settings.tokens.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: settings.tokens.radius(8)))
    }

    private var scaleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Layout")
            tokenSlider("Spacing", value: binding(\.spacingScale), range: 0.75...1.35)
            tokenSlider("Corners", value: binding(\.radiusScale), range: 0.55...1.65)
            tokenSlider("Type", value: binding(\.typeScale), range: 0.85...1.2)
            tokenSlider("Hero size", value: binding(\.heroScale), range: 0.75...1.3)
            tokenSlider("Shadow", value: binding(\.shadowScale), range: 0...1.7)
        }
        .padding(16)
        .background(settings.tokens.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: settings.tokens.radius(8)))
    }

    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Colors")
            colorPicker("Primary (unlocked)", red: \.primaryRed, green: \.primaryGreen, blue: \.primaryBlue)
            colorPicker("Secondary (unlocked)", red: \.secondaryRed, green: \.secondaryGreen, blue: \.secondaryBlue)
            colorPicker("Primary (locked)", red: \.lockedPrimaryRed, green: \.lockedPrimaryGreen, blue: \.lockedPrimaryBlue)
            colorPicker("Secondary (locked)", red: \.lockedSecondaryRed, green: \.lockedSecondaryGreen, blue: \.lockedSecondaryBlue)
            colorPicker("Accent pink", red: \.accentPinkRed, green: \.accentPinkGreen, blue: \.accentPinkBlue)
            colorPicker("Accent blue", red: \.accentBlueRed, green: \.accentBlueGreen, blue: \.accentBlueBlue)
            colorPicker("Surface", red: \.surfaceRed, green: \.surfaceGreen, blue: \.surfaceBlue)
            colorPicker("Text", red: \.textRed, green: \.textGreen, blue: \.textBlue)
            colorPicker("Muted", red: \.mutedRed, green: \.mutedGreen, blue: \.mutedBlue)
            colorPicker("Signal", red: \.signalRed, green: \.signalGreen, blue: \.signalBlue)
        }
        .padding(16)
        .background(settings.tokens.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: settings.tokens.radius(8)))
    }

    private func colorPicker(
        _ title: String,
        red: WritableKeyPath<DesignTokens, Double>,
        green: WritableKeyPath<DesignTokens, Double>,
        blue: WritableKeyPath<DesignTokens, Double>
    ) -> some View {
        ColorPicker(title, selection: colorBinding(red: red, green: green, blue: blue), supportsOpacity: false)
            .font(.system(size: settings.tokens.type(14), weight: .bold, design: .rounded))
            .foregroundStyle(settings.tokens.text)
    }

    private func colorBinding(
        red: WritableKeyPath<DesignTokens, Double>,
        green: WritableKeyPath<DesignTokens, Double>,
        blue: WritableKeyPath<DesignTokens, Double>
    ) -> Binding<Color> {
        Binding(
            get: {
                Color(
                    red: settings.tokens[keyPath: red],
                    green: settings.tokens[keyPath: green],
                    blue: settings.tokens[keyPath: blue]
                )
            },
            set: { newColor in
                let components = newColor.designRGB()
                settings.update { tokens in
                    tokens[keyPath: red] = components.red
                    tokens[keyPath: green] = components.green
                    tokens[keyPath: blue] = components.blue
                }
            }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: settings.tokens.type(11), weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(settings.tokens.text.opacity(0.46))
    }

    private func tokenSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: settings.tokens.type(13), weight: .bold, design: .rounded))
                .foregroundStyle(settings.tokens.text)
                .frame(width: 72, alignment: .leading)

            Slider(value: value, in: range)
                .tint(settings.tokens.primary)

            Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                .font(.system(size: settings.tokens.type(12), weight: .black, design: .monospaced))
                .foregroundStyle(settings.tokens.text.opacity(0.58))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<DesignTokens, Double>) -> Binding<Double> {
        Binding(
            get: { settings.tokens[keyPath: keyPath] },
            set: { newValue in
                settings.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
#endif

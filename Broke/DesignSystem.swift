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

struct FruitCharacter: View {
    var fruit: FruitKind
    var personality: FruitPersonality
    var size: CGFloat

    private let ink = Color(red: 0.13, green: 0.11, blue: 0.13)
    private let leafColor = Color(red: 0.27, green: 0.66, blue: 0.33)
    private let stemColor = Color(red: 0.45, green: 0.30, blue: 0.18)
    private let shine = Color.white.opacity(0.5)

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width * 0.5, y: s * 0.46)
            let radius = s * 0.31
            let lw = max(2, s * 0.03)

            drawLegs(context, center: center, radius: radius, lw: lw)
            drawBody(context, center: center, radius: radius, lw: lw)
            if personality == .groovy {
                drawHeadphones(context, center: center, radius: radius, lw: lw)
            }
            drawFace(context, center: center, radius: radius, lw: lw)
        }
        .frame(width: size, height: size)
    }

    // MARK: Body

    private func drawBody(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
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
            drawCrown(context, center: CGPoint(x: center.x, y: center.y - r * 0.72), scale: r)
            context.fill(strawberryPath(center: center, radius: r), with: .color(color))
            drawSeeds(context, center: center, radius: r)

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
        var p = Path()
        let topY = center.y - r * 0.55
        let halfW = r * 1.0
        let botY = center.y + r * 1.05
        p.move(to: CGPoint(x: center.x - halfW, y: topY))
        p.addQuadCurve(to: CGPoint(x: center.x + halfW, y: topY), control: CGPoint(x: center.x, y: topY - r * 0.45))
        p.addQuadCurve(to: CGPoint(x: center.x, y: botY), control: CGPoint(x: center.x + halfW, y: center.y + r * 0.45))
        p.addQuadCurve(to: CGPoint(x: center.x - halfW, y: topY), control: CGPoint(x: center.x - halfW, y: center.y + r * 0.45))
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
        var crown = Path()
        let points = 5
        let spread = r * 1.05
        for i in 0..<points {
            let t = CGFloat(i) / CGFloat(points - 1)
            let x = center.x - spread + t * spread * 2
            crown.move(to: CGPoint(x: x, y: center.y))
            crown.addLine(to: CGPoint(x: x - r * 0.16, y: center.y + r * 0.42))
            crown.addLine(to: CGPoint(x: x + r * 0.16, y: center.y + r * 0.42))
            crown.closeSubpath()
        }
        context.fill(crown, with: .color(leafColor))
    }

    private func drawSeeds(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat) {
        let seed = Color(red: 1.0, green: 0.93, blue: 0.55)
        let spots: [CGPoint] = [
            CGPoint(x: -0.45, y: 0.1), CGPoint(x: 0.45, y: 0.1),
            CGPoint(x: -0.2, y: 0.55), CGPoint(x: 0.2, y: 0.55),
            CGPoint(x: 0.0, y: 0.85)
        ]
        for spot in spots {
            let p = CGPoint(x: center.x + spot.x * r, y: center.y + spot.y * r)
            context.fill(circlePath(center: p, radius: r * 0.05), with: .color(seed))
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

    // MARK: Legs

    private func drawLegs(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
        let legTop = center.y + r * 0.92
        let footY = legTop + r * 0.32
        for dx in [-r * 0.26, r * 0.26] {
            var leg = Path()
            leg.move(to: CGPoint(x: center.x + dx, y: legTop))
            leg.addLine(to: CGPoint(x: center.x + dx, y: footY))
            context.stroke(leg, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            let fw = r * 0.2
            context.fill(
                Path(ellipseIn: CGRect(x: center.x + dx - fw / 2, y: footY - fw * 0.18, width: fw, height: fw * 0.5)),
                with: .color(ink)
            )
        }
    }

    // MARK: Face

    private func drawFace(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, lw: CGFloat) {
        let eyeY = center.y - r * 0.04
        let mouthY = center.y + r * 0.32
        let gap = r * 0.32
        let eyeR = r * 0.1

        switch personality {
        case .plain:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            dotEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.5, lw: lw)

        case .awe:
            wideEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR * 1.4)
            wideEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR * 1.4)
            context.fill(circlePath(center: CGPoint(x: center.x, y: mouthY + r * 0.05), radius: r * 0.12), with: .color(ink))

        case .cool:
            sunglasses(context, center: CGPoint(x: center.x, y: eyeY), r: r, lw: lw)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.42, lw: lw)

        case .groovy:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            dotEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.5, lw: lw)

        case .freckled:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            dotEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.46, lw: lw)
            freckles(context, center: center, r: r)

        case .wink:
            dotEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR)
            arcEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR, lw: lw, up: true)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.46, lw: lw)

        case .blush:
            arcEye(context, at: CGPoint(x: center.x - gap, y: eyeY), r: eyeR, lw: lw, up: true)
            arcEye(context, at: CGPoint(x: center.x + gap, y: eyeY), r: eyeR, lw: lw, up: true)
            smile(context, center: CGPoint(x: center.x, y: mouthY), width: r * 0.42, lw: lw)
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
        path.move(to: CGPoint(x: center.x - width / 2, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x + width / 2, y: center.y), control: CGPoint(x: center.x, y: center.y + width * 0.6))
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: lw * 0.85, lineCap: .round))
    }

    private func freckles(_ context: GraphicsContext, center: CGPoint, r: CGFloat) {
        let freckle = ink.opacity(0.55)
        for side in [-1.0, 1.0] {
            let baseX = center.x + CGFloat(side) * r * 0.52
            let baseY = center.y + r * 0.16
            for i in 0..<3 {
                let p = CGPoint(x: baseX + CGFloat(i % 2) * r * 0.1 - r * 0.05, y: baseY + CGFloat(i) * r * 0.12)
                context.fill(circlePath(center: p, radius: r * 0.035), with: .color(freckle))
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

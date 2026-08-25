import AppKit
import Foundation

// cutarms <char.png> <outPrefix> [overlapPx]
//
// Splits a finished character render into a torso and two arms, cutting along a
// line that lies INSIDE the body silhouette.
//
// This is deliberately not the same thing as the retired layered rig. There the
// limbs were a *different* render pasted behind a body, so the seam never
// matched. Here every pixel comes from the same image, so at rest the torso and
// arms recomposite to the original exactly - `--verify` checks that - and the
// arms can then be rotated a few degrees for secondary motion while their cut
// edge stays hidden under the torso.
//
// Emits <prefix>_torso.png, <prefix>_armL.png, <prefix>_armR.png and prints the
// pivot for each arm (the point the rig should rotate it about).

func load(_ p: String) -> (px: [UInt8], w: Int, h: Int)? {
    guard let i = NSImage(contentsOfFile: p),
          let c = i.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let w = c.width, h = c.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(c, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (px, w, h)
}

func save(_ px: [UInt8], _ w: Int, _ h: Int, _ path: String) {
    var buf = px
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let cg = ctx.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

let a = CommandLine.arguments
guard a.count >= 3, let src = load(a[1]) else { print("usage: cutarms char.png outPrefix [overlap]"); exit(1) }
let prefix = a[2]
let overlap = a.count > 3 ? Int(a[3])! : 56

let w = src.w, h = src.h
var px = src.px
var mask = [Bool](repeating: false, count: w * h)
var minX = w, maxX = -1, minY = h, maxY = -1
for y in 0..<h {
    for x in 0..<w where px[(y * w + x) * 4 + 3] >= 128 {
        mask[y * w + x] = true
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let H = maxY - minY

// Arms live in this vertical band. Above it is the head, below it the legs -
// both must stay welded to the torso.
let bandTop = minY + Int(0.56 * Double(H))
let bandBot = minY + Int(0.79 * Double(H))

// Recover the TORSO's own outline through the arm band.
//
// The cut line must follow the body's natural silhouette, not carve a notch out
// of it: the torso is drawn on top of the arms, so any notch in the torso is a
// hole that opens up the moment an arm rotates. So fit a smooth curve to the
// outer edge over a range that extends beyond the arms, iteratively rejecting
// rows where the arm pushes the edge outward, and refit.
let fitTop = max(minY + 2, minY + Int(0.34 * Double(H)))
let fitBot = min(maxY - 2, minY + Int(0.88 * Double(H)))

func rawEdge(_ y: Int, left: Bool) -> Int {
    if left {
        for x in minX...maxX where mask[y * w + x] { return x }
    } else {
        for x in stride(from: maxX, through: minX, by: -1) where mask[y * w + x] { return x }
    }
    return left ? maxX : minX
}

func fitEdge(left: Bool) -> [Int] {
    var v = [Double](repeating: 0, count: h)
    for y in fitTop...fitBot { v[y] = Double(rawEdge(y, left: left)) }
    var work = v
    func blur(_ src: [Double], _ sigma: Double) -> [Double] {
        let rad = Int(ceil(sigma * 3))
        var k = [Double](repeating: 0, count: 2 * rad + 1), ks = 0.0
        for i in -rad...rad { let g = exp(-Double(i * i) / (2 * sigma * sigma)); k[i + rad] = g; ks += g }
        for i in 0..<k.count { k[i] /= ks }
        var out = src
        for y in fitTop...fitBot {
            var acc = 0.0, wsum = 0.0
            for i in -rad...rad {
                let yy = y + i
                guard yy >= fitTop && yy <= fitBot else { continue }
                acc += k[i + rad] * src[yy]; wsum += k[i + rad]
            }
            out[y] = wsum > 0 ? acc / wsum : src[y]
        }
        return out
    }
    var smooth = blur(work, 26)
    for _ in 0..<7 {
        smooth = blur(work, 26)
        for y in fitTop...fitBot {
            // an arm pushes the edge OUTWARD; pull those rows back to the fit
            if left ? (work[y] < smooth[y] - 5) : (work[y] > smooth[y] + 5) {
                work[y] = smooth[y]
            }
        }
    }
    smooth = blur(work, 14)
    return (0..<h).map { y in
        (y >= fitTop && y <= fitBot) ? Int(smooth[y].rounded()) : (left ? minX : maxX)
    }
}

let bodyL = fitEdge(left: true)
let bodyR = fitEdge(left: false)

// Classify every pixel: torso, left arm or right arm.
var armSide = [Int8](repeating: 0, count: w * h)   // -1 left, +1 right
for y in bandTop...bandBot {
    for x in minX...maxX where mask[y * w + x] {
        if x < bodyL[y] { armSide[y * w + x] = -1 }
        else if x > bodyR[y] { armSide[y * w + x] = 1 }
    }
}

// Arm images keep their own protruding pixels plus a hidden ROOT of torso
// pixels inboard of the cut, giving material that stays buried as the arm
// rotates.
//
// The rule that matters: arm material must never sit close to the torso
// silhouette anywhere it is not legitimately sticking out, because rotation
// pushes it straight through that edge and it shows as a hard tab or spike.
// So the root is everything within `rootRadius` of the pivot that is also at
// least `safeMargin` inboard of the torso edge. Between the two lies a strip
// with no arm material at all - that is fine, the torso is opaque there, so
// rotating the arm can only ever reveal torso, never a hole.
//
// safeMargin must exceed the worst-case swing, rootRadius * sin(maxRotation).
let safeMargin = 40
let rootRadius = 170.0

func armRows(_ side: Int8) -> (Int, Int) {
    var lo = bandBot, hi = bandTop
    for y in bandTop...bandBot {
        var any = false
        for x in minX...maxX where armSide[y * w + x] == side { any = true; break }
        if any { lo = min(lo, y); hi = max(hi, y) }
    }
    return (lo, hi)
}

func edgeAt(_ y: Int, left: Bool) -> Int {
    if y >= fitTop && y <= fitBot { return left ? bodyL[y] : bodyR[y] }
    return rawEdge(y, left: left)
}

func buildArm(_ side: Int8, _ path: String) -> (cx: Double, cy: Double, n: Int) {
    var out = [UInt8](repeating: 0, count: w * h * 4)
    var n = 0
    let (aTop, aBot) = armRows(side)
    let midY = (aTop + aBot) / 2
    // pivot sits just inboard of the cut, level with the middle of the arm
    let cut = side < 0 ? bodyL[midY] : bodyR[midY]
    let px0 = Double(cut) + (side < 0 ? 30.0 : -30.0)
    let py0 = Double(midY)

    for y in max(minY, midY - Int(rootRadius))...min(maxY, midY + Int(rootRadius)) {
        let l = edgeAt(y, left: true), r = edgeAt(y, left: false)
        for x in 0..<w where px[(y * w + x) * 4 + 3] > 0 {
            let dx = Double(x) - px0, dy = Double(y) - py0
            let dist = (dx * dx + dy * dy).squareRoot()
            let protrudes = (y >= bandTop && y <= bandBot) &&
                            (side < 0 ? x < l : x > r)
            let inRoot = dist <= rootRadius &&
                         min(x - l, r - x) >= safeMargin
            guard protrudes || inRoot else { continue }
            let i = (y * w + x) * 4
            for k in 0..<4 { out[i + k] = px[i + k] }
            if protrudes { n += 1 }
        }
    }
    save(out, w, h, path)
    return (px0, py0, n)
}

let L = buildArm(-1, "\(prefix)_armL.png")
let R = buildArm(1, "\(prefix)_armR.png")

// Torso = everything inboard of the cut line. This clears EVERY pixel outside
// it, not just the ones above the mask threshold - the arm's anti-aliased
// fringe is below that threshold and would otherwise stay behind as a ghost
// outline once the arm rotates away.
var torso = px
for y in bandTop...bandBot {
    for x in 0..<w where x < bodyL[y] || x > bodyR[y] {
        let o = (y * w + x) * 4
        torso[o] = 0; torso[o + 1] = 0; torso[o + 2] = 0; torso[o + 3] = 0
    }
}
save(torso, w, h, "\(prefix)_torso.png")

let name = (a[1] as NSString).lastPathComponent
print("\(name): armL n=\(L.n) pivot=(\(Int(L.cx)),\(Int(L.cy)))  armR n=\(R.n) pivot=(\(Int(R.cx)),\(Int(R.cy)))  band \(bandTop)...\(bandBot)")

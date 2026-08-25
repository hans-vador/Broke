import AppKit
import Foundation

// Removes baked-in arm/leg "stub" blobs from a soft-3D fruit body PNG.
//
// Every fruit body is star-shaped about its centroid, so the silhouette is a
// function r(theta). The stubs are isolated OUTWARD BUMPS in that function.
// We recover the true body silhouette with iterative robust smoothing (fit a
// smooth curve, reject points that stick out, refit), then shave everything
// outside it. Stems/leaves are protected by only editing below a y cutoff.

func loadRGBA(_ path: String) -> (px: [UInt8], w: Int, h: Int)? {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (px, w, h)
}

func savePNG(_ px: [UInt8], _ w: Int, _ h: Int, to path: String) {
    var buf = px
    guard let ctx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let cg = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    if let d = rep.representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: path))
    }
}

let a = CommandLine.arguments
guard a.count >= 3, let src = loadRGBA(a[1]) else {
    print("usage: destub2 in.png out.png [protectTopFraction] [bumpThresholdPx]"); exit(1)
}
let protectTop = a.count > 3 ? (Double(a[3]) ?? 0.42) : 0.42
let bumpThresh = a.count > 4 ? (Double(a[4]) ?? 9.0) : 9.0

var px = src.px
let w = src.w, h = src.h

// --- mask + bbox (row 0 = visual top)
var mask = [Bool](repeating: false, count: w * h)
var minY = h, maxY = -1, minX = w, maxX = -1
var sumX = 0.0, sumY = 0.0, n = 0.0
for y in 0..<h {
    for x in 0..<w where px[(y * w + x) * 4 + 3] >= 128 {
        mask[y * w + x] = true
        minY = min(minY, y); maxY = max(maxY, y)
        minX = min(minX, x); maxX = max(maxX, x)
        sumX += Double(x); sumY += Double(y); n += 1
    }
}
let bodyH = Double(maxY - minY)
let editCutoffY = Double(minY) + protectTop * bodyH
// Centroid of the LOWER body only -- keeps stems/leaves from dragging it up.
var lx = 0.0, ly = 0.0, ln = 0.0
for y in Int(editCutoffY)..<h {
    for x in 0..<w where mask[y * w + x] {
        lx += Double(x); ly += Double(y); ln += 1
    }
}
let cx = lx / ln, cy = ly / ln

// --- silhouette r(theta)
let N = 1440                       // 0.25 deg steps
let maxR = Double(max(w, h))
var r = [Double](repeating: 0, count: N)
for i in 0..<N {
    let t = Double(i) * 2 * .pi / Double(N)
    let dx = cos(t), dy = sin(t)
    var best = 0.0
    var d = 4.0
    while d < maxR {
        let x = Int((cx + dx * d).rounded()), y = Int((cy + dy * d).rounded())
        if x < 0 || y < 0 || x >= w || y >= h { break }
        if mask[y * w + x] { best = d }
        d += 1
    }
    r[i] = best
}

// --- iterative robust smoothing (circular Gaussian blur + outlier rejection)
func circularBlur(_ v: [Double], sigmaDeg: Double) -> [Double] {
    let sigma = sigmaDeg / 360.0 * Double(N)
    let rad = Int(ceil(sigma * 3))
    var kernel = [Double](repeating: 0, count: 2 * rad + 1)
    var ksum = 0.0
    for k in -rad...rad {
        let g = exp(-Double(k * k) / (2 * sigma * sigma))
        kernel[k + rad] = g; ksum += g
    }
    for k in 0..<kernel.count { kernel[k] /= ksum }
    var out = [Double](repeating: 0, count: v.count)
    for i in 0..<v.count {
        var s = 0.0
        for k in -rad...rad {
            s += kernel[k + rad] * v[((i + k) % N + N) % N]
        }
        out[i] = s
    }
    return out
}

var work = r
var smooth = circularBlur(work, sigmaDeg: 9)
for _ in 0..<8 {
    smooth = circularBlur(work, sigmaDeg: 9)
    for i in 0..<N where work[i] > smooth[i] + bumpThresh {
        // stick-out point: pull it down toward the fitted curve
        work[i] = smooth[i]
    }
}
smooth = circularBlur(work, sigmaDeg: 6)

// --- shave everything outside the recovered silhouette (below the cutoff only)
var removed = 0
for y in 0..<h {
    guard Double(y) >= editCutoffY else { continue }
    for x in 0..<w {
        let i = y * w + x
        // NB: deliberately not limited to `mask` -- the stub's anti-aliased
        // fringe sits below the mask threshold and would survive as a ghost ring.
        guard px[i * 4 + 3] > 0 else { continue }
        let dx = Double(x) - cx, dy = Double(y) - cy
        let dist = (dx * dx + dy * dy).squareRoot()
        var t = atan2(dy, dx)
        if t < 0 { t += 2 * .pi }
        let idx = Int((t / (2 * .pi) * Double(N)).rounded()) % N
        let limit = smooth[idx]
        // 2.5px feather so the new edge stays anti-aliased
        let cover = max(0, min(1, (limit + 1.0 - dist) / 2.5))
        if cover < 0.999 {
            let o = i * 4
            let oldA = Double(px[o + 3])
            let s = cover
            px[o] = UInt8(Double(px[o]) * s)
            px[o + 1] = UInt8(Double(px[o + 1]) * s)
            px[o + 2] = UInt8(Double(px[o + 2]) * s)
            px[o + 3] = UInt8(oldA * s)
            if cover < 0.5 { removed += 1 }
        }
    }
}
for i in stride(from: 0, to: w * h * 4, by: 4) where px[i + 3] < 8 {
    px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
}

savePNG(px, w, h, to: a[2])
let bumps = (0..<N).filter { r[$0] > smooth[$0] + bumpThresh }.count
print("\((a[1] as NSString).lastPathComponent): shaved \(removed)px, bumpArcs=\(bumps)/\(N), centre=(\(Int(cx)),\(Int(cy))), editBelowY=\(Int(editCutoffY))")

import AppKit
import Foundation

// recolor <src.png> <out.png> <R> <G> <B>
// Luminance-preserving recolor: keeps the source's soft-3D shading ramp and
// re-tints it to the target hue, so a recoloured limb still reads as clay.

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

let a = CommandLine.arguments
guard a.count >= 6, let s = load(a[1]) else { print("usage: recolor src out R G B"); exit(1) }
let tR = Double(a[3])!, tG = Double(a[4])!, tB = Double(a[5])!
var px = s.px

func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.299 * r + 0.587 * g + 0.114 * b }

// mean luminance of the solid source pixels == the "base tone" of the clay
var meanL = 0.0, n = 0.0
for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 200 {
    let f = Double(px[i + 3]) / 255
    meanL += lum(Double(px[i]) / f, Double(px[i + 1]) / f, Double(px[i + 2]) / f)
    n += 1
}
meanL /= n

for i in stride(from: 0, to: px.count, by: 4) {
    let alpha = Double(px[i + 3])
    if alpha < 1 { continue }
    let f = alpha / 255
    let L = lum(Double(px[i]) / f, Double(px[i + 1]) / f, Double(px[i + 2]) / f)
    // shading factor relative to the base tone, softened so highlights don't clip
    let k = L / meanL
    let shade = k < 1 ? k : 1 + (k - 1) * 0.55
    let nr = min(255, max(0, tR * shade))
    let ng = min(255, max(0, tG * shade))
    let nb = min(255, max(0, tB * shade))
    px[i] = UInt8(nr * f); px[i + 1] = UInt8(ng * f); px[i + 2] = UInt8(nb * f)
}

var buf = px
let ctx = CGContext(data: &buf, width: s.w, height: s.h, bitsPerComponent: 8,
                    bytesPerRow: s.w * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
try? NSBitmapImageRep(cgImage: ctx.makeImage()!)
    .representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[2]))
print("recolored \((a[1] as NSString).lastPathComponent) -> \((a[2] as NSString).lastPathComponent) (baseL=\(Int(meanL)))")

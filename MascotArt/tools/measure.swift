import AppKit
import Foundation

// Emits per-fruit rig geometry as JSON: body bbox, detected eye centres/size,
// and the base body colour (used to fill the blink "eyelid" shapes).

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

var out: [String] = []
for path in CommandLine.arguments.dropFirst() {
    guard let s = load(path) else { continue }
    let w = s.w, h = s.h, px = s.px
    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension

    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h {
        for x in 0..<w where px[(y * w + x) * 4 + 3] >= 128 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }

    // base body colour: mean of solid, non-dark pixels in the lower body
    var br = 0.0, bg = 0.0, bb = 0.0, bn = 0.0
    for y in ((minY + maxY) / 2)..<maxY {
        for x in minX...max(minX, maxX) {
            let i = (y * w + x) * 4
            guard px[i + 3] > 240 else { continue }
            let R = Double(px[i]), G = Double(px[i + 1]), B = Double(px[i + 2])
            if 0.299 * R + 0.587 * G + 0.114 * B < 70 { continue }
            br += R; bg += G; bb += B; bn += 1
        }
    }
    br /= bn; bg /= bn; bb /= bn

    // --- silhouette width profile: left/right edge at 41 heights across the body.
    // Lets the rig attach limbs flush to whatever shape the fruit actually is.
    var profile: [String] = []
    for k in 0...40 {
        let t = Double(k) / 40.0
        let y = min(maxY, minY + Int(t * Double(maxY - minY)))
        var l = -1, r = -1
        for x in minX...max(minX, maxX) where px[(y * w + x) * 4 + 3] >= 128 {
            if l < 0 { l = x }
            r = x
        }
        profile.append("[\(l), \(r)]")
    }

    // --- underside profile: the LOWEST opaque y at 41 x positions across the
    // body. Legs sit off-centre where the body curves up well above its lowest
    // point, so hips must be tucked against this, not against the global bottom.
    var underside: [String] = []
    for k in 0...40 {
        let t = Double(k) / 40.0
        let x = min(maxX, minX + Int(t * Double(maxX - minX)))
        var lowest = -1
        for y in 0..<h where px[(y * w + x) * 4 + 3] >= 128 { lowest = y }
        underside.append("\(lowest)")
    }

    // --- eye detection: dark blobs in the upper-middle of the body
    let searchTop = minY + Int(0.15 * Double(maxY - minY))
    let searchBot = minY + Int(0.72 * Double(maxY - minY))
    var dark = [Bool](repeating: false, count: w * h)
    for y in searchTop..<searchBot {
        for x in minX...max(minX, maxX) {
            let i = (y * w + x) * 4
            guard px[i + 3] > 200 else { continue }
            let R = Double(px[i]), G = Double(px[i + 1]), B = Double(px[i + 2])
            if 0.299 * R + 0.587 * G + 0.114 * B < 78 { dark[y * w + x] = true }
        }
    }
    // connected components
    var seen = [Bool](repeating: false, count: w * h)
    struct Blob { var cx = 0.0; var cy = 0.0; var n = 0.0; var x0 = 0; var x1 = 0; var y0 = 0; var y1 = 0 }
    var blobs: [Blob] = []
    for y in searchTop..<searchBot {
        for x in minX...max(minX, maxX) {
            let start = y * w + x
            guard dark[start], !seen[start] else { continue }
            var stack = [start]; seen[start] = true
            var b = Blob(); b.x0 = x; b.x1 = x; b.y0 = y; b.y1 = y
            while let cur = stack.popLast() {
                let cy0 = cur / w, cx0 = cur % w
                b.cx += Double(cx0); b.cy += Double(cy0); b.n += 1
                b.x0 = min(b.x0, cx0); b.x1 = max(b.x1, cx0)
                b.y0 = min(b.y0, cy0); b.y1 = max(b.y1, cy0)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx0 + dx, ny = cy0 + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let ni = ny * w + nx
                    if dark[ni], !seen[ni] { seen[ni] = true; stack.append(ni) }
                }
            }
            if b.n > 400 { b.cx /= b.n; b.cy /= b.n; blobs.append(b) }
        }
    }
    // the two biggest blobs that sit at a similar height are the eyes
    blobs.sort { $0.n > $1.n }
    var eyes: [Blob] = []
    outer: for i in 0..<blobs.count {
        for j in (i + 1)..<blobs.count {
            if abs(blobs[i].cy - blobs[j].cy) < 40 && abs(blobs[i].cx - blobs[j].cx) > 60 {
                eyes = blobs[i].cx < blobs[j].cx ? [blobs[i], blobs[j]] : [blobs[j], blobs[i]]
                break outer
            }
        }
    }
    guard eyes.count == 2 else {
        out.append("""
          "\(name)": {"bbox": [\(minX), \(minY), \(maxX), \(maxY)], "color": [\(Int(br)), \(Int(bg)), \(Int(bb))], "eyes": null, "profile": [\(profile.joined(separator: ", "))], "underside": [\(underside.joined(separator: ", "))]}
        """)
        continue
    }
    let eL = eyes[0], eR = eyes[1]

    // --- mouth: the largest dark blob BELOW the eyes, near the centre line.
    // Placing the tongue from eye geometry alone misses badly when a fruit's
    // face is proportioned differently.
    let faceCX = (eL.cx + eR.cx) / 2
    let mouthTop = Int(max(eL.cy, eR.cy)) + Int(Double(max(eL.y1 - eL.y0, eR.y1 - eR.y0)) * 0.35)
    let mouthBot = min(maxY, mouthTop + Int(0.34 * Double(maxY - minY)))
    var seen2 = [Bool](repeating: false, count: w * h)
    var best: Blob? = nil
    if mouthTop < mouthBot {
        for y in mouthTop..<mouthBot {
            for x in minX...max(minX, maxX) {
                let st = y * w + x
                guard dark[st], !seen2[st] else { continue }
                var stack = [st]; seen2[st] = true
                var b = Blob(); b.x0 = x; b.x1 = x; b.y0 = y; b.y1 = y
                while let cur = stack.popLast() {
                    let cy0 = cur / w, cx0 = cur % w
                    b.cx += Double(cx0); b.cy += Double(cy0); b.n += 1
                    b.x0 = min(b.x0, cx0); b.x1 = max(b.x1, cx0)
                    b.y0 = min(b.y0, cy0); b.y1 = max(b.y1, cy0)
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = cx0 + dx, ny = cy0 + dy
                        guard nx >= 0, ny >= mouthTop, nx < w, ny < mouthBot else { continue }
                        let ni = ny * w + nx
                        if dark[ni], !seen2[ni] { seen2[ni] = true; stack.append(ni) }
                    }
                }
                guard b.n > 250 else { continue }
                b.cx /= b.n; b.cy /= b.n
                // a mouth sits near the face's centre line and is wider than tall
                guard abs(b.cx - faceCX) < Double(maxX - minX) * 0.16 else { continue }
                if best == nil || b.n > best!.n { best = b }
            }
        }
    }
    let mouth = best.map {
        "{\"cx\": \(Int($0.cx)), \"cy\": \(Int($0.cy)), \"w\": \($0.x1 - $0.x0), \"h\": \($0.y1 - $0.y0), \"bottom\": \($0.y1)}"
    } ?? "null"
    out.append("""
      "\(name)": {"bbox": [\(minX), \(minY), \(maxX), \(maxY)], "color": [\(Int(br)), \(Int(bg)), \(Int(bb))], "eyes": {"lx": \(Int(eL.cx)), "ly": \(Int(eL.cy)), "rx": \(Int(eR.cx)), "ry": \(Int(eR.cy)), "w": \(max(eL.x1 - eL.x0, eR.x1 - eR.x0)), "h": \(max(eL.y1 - eL.y0, eR.y1 - eR.y0))}, "mouth": \(mouth), "profile": [\(profile.joined(separator: ", "))], "underside": [\(underside.joined(separator: ", "))]}
    """)
}
print("{\n" + out.joined(separator: ",\n") + "\n}")

import AVFoundation
import AppKit
import Foundation

// frames <video> <outDir> <count> [startSeconds] [spanSeconds]
// Extracts evenly spaced frames from a screen recording - reliable, unlike
// spacing `simctl io screenshot` calls (each blocks ~1s and aliases the loop).
let a = CommandLine.arguments
guard a.count >= 4 else { print("usage: frames video outDir count [start] [span]"); exit(1) }
let url = URL(fileURLWithPath: a[1])
let outDir = a[2]
let count = Int(a[3])!
let start = a.count > 4 ? Double(a[4])! : 0.5
let span = a.count > 5 ? Double(a[5])! : 2.4

let asset = AVURLAsset(url: url)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let sem = DispatchSemaphore(value: 0)
var done = 0
for i in 0..<count {
    let t = CMTime(seconds: start + span * Double(i) / Double(count), preferredTimescale: 600)
    do {
        let cg = try gen.copyCGImage(at: t, actualTime: nil)
        let rep = NSBitmapImageRep(cgImage: cg)
        if let d = rep.representation(using: .png, properties: [:]) {
            try d.write(to: URL(fileURLWithPath: "\(outDir)/\(i).png"))
            done += 1
        }
    } catch {
        FileHandle.standardError.write("frame \(i) failed: \(error)\n".data(using: .utf8)!)
    }
}
print("extracted \(done)/\(count) frames")
_ = sem

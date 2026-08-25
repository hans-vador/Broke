import AppKit
import Foundation
// pad <in.png> <out.png> <canvas> [scaleFraction]
// Centres artwork on a square transparent canvas so every Lottie image asset
// can keep the same declared dimensions.
let a=CommandLine.arguments
guard a.count>=4, let img=NSImage(contentsOfFile:a[1]),
      let cg=img.cgImage(forProposedRect:nil,context:nil,hints:nil) else{exit(1)}
let N=Int(a[3])!
let frac = a.count>4 ? Double(a[4])! : 1.0
let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:N,pixelsHigh:N,bitsPerSample:8,
  samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
  bytesPerRow:N*4,bitsPerPixel:32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
NSGraphicsContext.current!.imageInterpolation = .high
let side=Double(N)*frac
let o=(Double(N)-side)/2
NSImage(cgImage:cg,size:.zero).draw(in:NSRect(x:o,y:o,width:side,height:side))
NSGraphicsContext.restoreGraphicsState()
try? rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:a[2]))
print("padded -> \((a[2] as NSString).lastPathComponent) \(N)x\(N)")

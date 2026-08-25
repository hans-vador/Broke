import AppKit
import Foundation
// Reports the horizontal centre of the artwork at several heights, so we can
// see whether a limb is authored leaning rather than straight.
let a=CommandLine.arguments
guard let i=NSImage(contentsOfFile:a[1]),let c=i.cgImage(forProposedRect:nil,context:nil,hints:nil) else{exit(1)}
let w=c.width,h=c.height;var px=[UInt8](repeating:0,count:w*h*4)
let ctx=CGContext(data:&px,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(c,in:CGRect(x:0,y:0,width:w,height:h))
var minY=h,maxY = -1
for y in 0..<h { for x in 0..<w where px[(y*w+x)*4+3] >= 128 { if y<minY{minY=y}; if y>maxY{maxY=y} } }
print("\((a[1] as NSString).lastPathComponent): rows \(minY)...\(maxY)")
for f in [0.0,0.1,0.25,0.5,0.75,0.9,1.0] {
    let y=min(maxY,minY+Int(f*Double(maxY-minY)))
    var lo = -1, hi = -1
    for x in 0..<w where px[(y*w+x)*4+3] >= 128 { if lo<0 {lo=x}; hi=x }
    if lo>=0 { print(String(format:"  t=%.2f y=%4d  x %4d..%4d  centre %4d  width %4d", f, y, lo, hi, (lo+hi)/2, hi-lo)) }
}

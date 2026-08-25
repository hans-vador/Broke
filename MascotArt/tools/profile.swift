import AppKit
import Foundation
// Dense width profile of a character: reveals where arms bump out and where the
// legs are, so rig proportions can be matched to reference art numerically.
let a=CommandLine.arguments
guard let i=NSImage(contentsOfFile:a[1]),let c=i.cgImage(forProposedRect:nil,context:nil,hints:nil) else{exit(1)}
let w=c.width,h=c.height;var px=[UInt8](repeating:0,count:w*h*4)
let ctx=CGContext(data:&px,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(c,in:CGRect(x:0,y:0,width:w,height:h))
// A screenshot has an opaque background, so key against the corner colour as
// well as alpha; that lets the same tool measure art and live renders.
let bg=(Int(px[0]),Int(px[1]),Int(px[2]))
func on(_ x:Int,_ y:Int)->Bool{
  let i=(y*w+x)*4
  if px[i+3] < 128 { return false }
  let d=abs(Int(px[i])-bg.0)+abs(Int(px[i+1])-bg.1)+abs(Int(px[i+2])-bg.2)
  return d > 40
}
var minY=h,maxY = -1,minX=w,maxX = -1
for y in 0..<h { for x in 0..<w where on(x,y) {
  if y<minY{minY=y}; if y>maxY{maxY=y}; if x<minX{minX=x}; if x>maxX{maxX=x} } }
let H=maxY-minY, W=maxX-minX
print("\((a[1] as NSString).lastPathComponent): bbox x \(minX)..\(maxX) (w \(W))  y \(minY)..\(maxY) (h \(H))")
for k in 0...24 {
    let f=Double(k)/24.0
    let y=min(maxY,minY+Int(f*Double(H)))
    var lo = -1, hi = -1, runs = 0, prev = false
    for x in 0..<w {
        let isOn = on(x,y)
        if isOn { if lo<0 {lo=x}; hi=x }
        if isOn && !prev { runs += 1 }
        prev = isOn
    }
    if lo>=0 {
        print(String(format:"  t=%.2f  x %4d..%4d  width %4d (%.0f%% of body w)  runs %d",
                     f, lo, hi, hi-lo, Double(hi-lo)/Double(W)*100, runs))
    }
}

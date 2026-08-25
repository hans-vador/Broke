import AppKit
import Foundation
// For each leg, walk up its centre column and report the gap to the body.
func load(_ p:String)->(px:[UInt8],w:Int,h:Int)?{
 guard let i=NSImage(contentsOfFile:p),let c=i.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}
 let w=c.width,h=c.height;var px=[UInt8](repeating:0,count:w*h*4)
 guard let ctx=CGContext(data:&px,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
 ctx.draw(c,in:CGRect(x:0,y:0,width:w,height:h));return (px,w,h)}
let a=CommandLine.arguments
guard let S=load(a[1]) else{exit(1)}
let w=S.w,h=S.h,px=S.px
func on(_ x:Int,_ y:Int)->Bool{ px[(y*w+x)*4+3] >= 128 }
var minY=h,maxY = -1,minX=w,maxX = -1
for y in 0..<h { for x in 0..<w where on(x,y) {
 if y<minY{minY=y}; if y>maxY{maxY=y}; if x<minX{minX=x}; if x>maxX{maxX=x} } }
let H=maxY-minY
// the bottom row of the character is feet; find their two runs
var footRuns:[(Int,Int)]=[]
var s = -1
let footY = maxY - 4
for x in minX...maxX {
    let o = on(x,footY)
    if o && s<0 { s=x }
    if !o && s >= 0 { footRuns.append((s,x-1)); s = -1 } }
if s >= 0 { footRuns.append((s,maxX)) }
let legs = footRuns.filter { $0.1 - $0.0 > 12 }
var out:[String]=[]
for (n,leg) in legs.enumerated() {
    let cx = (leg.0 + leg.1)/2
    // walk up from the foot: first gap encountered is the body/leg separation
    var y = footY, gap = 0, gapAt = -1
    while y > minY {
        if !on(cx,y) {
            var g = 0; var yy = y
            while yy > minY && !on(cx,yy) { g += 1; yy -= 1 }
            if yy > minY { gap = g; gapAt = yy }   // solid again above => body
            break
        }
        y -= 1 }
    out.append("leg\(n) x=\(cx) gap=\(gap)px\(gapAt >= 0 ? " (body ends y=\(gapAt))" : "")")
}
print("\((a[1] as NSString).lastPathComponent) [h=\(H)]: " + out.joined(separator: "  "))

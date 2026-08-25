import AppKit
import Foundation
// identity <a.png> <b.png> - how far has a regenerated character drifted?
func load(_ p:String)->(px:[UInt8],w:Int,h:Int)?{
 guard let i=NSImage(contentsOfFile:p),let c=i.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}
 let w=c.width,h=c.height;var px=[UInt8](repeating:0,count:w*h*4)
 guard let ctx=CGContext(data:&px,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
 ctx.draw(c,in:CGRect(x:0,y:0,width:w,height:h));return (px,w,h)}
func stats(_ p:String)->(bbox:(Int,Int,Int,Int),col:(Int,Int,Int),area:Int,w:Int,h:Int,px:[UInt8])?{
 guard let S=load(p) else{return nil}
 let w=S.w,h=S.h,px=S.px
 var minY=h,maxY = -1,minX=w,maxX = -1,area=0
 var r=0.0,g=0.0,b=0.0,n=0.0
 for y in 0..<h { for x in 0..<w where px[(y*w+x)*4+3]>=128 {
  minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y);area+=1
  let i=(y*w+x)*4
  let R=Double(px[i]),G=Double(px[i+1]),B=Double(px[i+2])
  if 0.299*R+0.587*G+0.114*B > 70 { r+=R;g+=G;b+=B;n+=1 } } }
 return ((minX,minY,maxX,maxY),(Int(r/n),Int(g/n),Int(b/n)),area,w,h,px)}
let a=CommandLine.arguments
guard let A=stats(a[1]), let B=stats(a[2]) else{exit(1)}
// silhouette IoU on a common grid
var inter=0, uni=0
let n=min(A.w,B.w)
for y in 0..<n { for x in 0..<n {
 let ia = A.px[(y*A.w+x)*4+3] >= 128
 let ib = B.px[(y*B.w+x)*4+3] >= 128
 if ia||ib {uni+=1}; if ia&&ib {inter+=1} } }
let iou = uni>0 ? Double(inter)/Double(uni)*100 : 0
print(String(format:"bbox %@ -> %@ | colour (%d,%d,%d) -> (%d,%d,%d) | area %d -> %d (%+.1f%%) | silhouette IoU %.1f%%",
 "\(A.bbox)","\(B.bbox)",A.col.0,A.col.1,A.col.2,B.col.0,B.col.1,B.col.2,
 A.area,B.area,(Double(B.area)-Double(A.area))/Double(A.area)*100,iou))

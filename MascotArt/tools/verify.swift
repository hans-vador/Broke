import AppKit
import Foundation
// verify <orig.png> <armL> <armR> <torso> <outDiff.png>
// Composites arms-under-torso and reports how far it differs from the original.
func load(_ p:String)->(px:[UInt8],w:Int,h:Int)?{
 guard let i=NSImage(contentsOfFile:p),let c=i.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}
 let w=c.width,h=c.height;var px=[UInt8](repeating:0,count:w*h*4)
 guard let ctx=CGContext(data:&px,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
 ctx.draw(c,in:CGRect(x:0,y:0,width:w,height:h));return (px,w,h)}
let a=CommandLine.arguments
guard let O=load(a[1]),let AL=load(a[2]),let AR=load(a[3]),let T=load(a[4]) else{exit(1)}
let w=O.w,h=O.h
var comp=[UInt8](repeating:0,count:w*h*4)
func over(_ dst:inout [UInt8],_ src:[UInt8]){
 for i in stride(from:0,to:w*h*4,by:4){
  let sa=Double(src[i+3])/255.0
  if sa<=0 {continue}
  for k in 0..<3 { dst[i+k]=UInt8(min(255,Double(src[i+k])+Double(dst[i+k])*(1-sa))) }
  dst[i+3]=UInt8(min(255,Double(src[i+3])+Double(dst[i+3])*(1-sa)))}}
over(&comp,AL.px); over(&comp,AR.px); over(&comp,T.px)
var diff=[UInt8](repeating:0,count:w*h*4)
var bad=0, total=0
for i in stride(from:0,to:w*h*4,by:4){
 let da=abs(Int(comp[i+3])-Int(O.px[i+3]))
 let dc=abs(Int(comp[i])-Int(O.px[i]))+abs(Int(comp[i+1])-Int(O.px[i+1]))+abs(Int(comp[i+2])-Int(O.px[i+2]))
 if O.px[i+3]>8 || comp[i+3]>8 { total+=1 }
 let d=max(da,dc/3)
 if d>12 { bad+=1; diff[i]=255;diff[i+1]=0;diff[i+2]=0;diff[i+3]=255 }
 else { let g=UInt8(60); diff[i]=g;diff[i+1]=g;diff[i+2]=g;diff[i+3]=255 }}
var buf=diff
let ctx=CGContext(data:&buf,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
try? NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:a[5]))
let pct = total>0 ? Double(bad)/Double(total)*100 : 0
print(String(format:"%@: %d mismatched px of %d (%.3f%%)",(a[1] as NSString).lastPathComponent,bad,total,pct))

import AppKit

// Original vector artwork. Re-render every icon size directly, without resampling.
// Coordinates use a 1024-point canvas; transparent corners belong to the asset.
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
 NSColor(srgbRed:r,green:g,blue:b,alpha:a)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
 NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius)
}
func drawIcon() {
 let tile=rounded(NSRect(x:100,y:100,width:824,height:824),184)
 NSGraphicsContext.saveGraphicsState()
 let shadow=NSShadow(); shadow.shadowColor=color(0.03,0.12,0.20,0.28)
 shadow.shadowBlurRadius=28; shadow.shadowOffset=NSSize(width:0,height:-12); shadow.set()
 color(0.03,0.25,0.43).setFill(); tile.fill()
 NSGraphicsContext.restoreGraphicsState()
 NSGradient(starting:color(0.04,0.34,0.57),ending:color(0.10,0.67,0.74))!.draw(in:tile,angle:75)
 color(1,1,1,0.22).setStroke(); tile.lineWidth=2; tile.stroke()

 // A quiet menu-bar line and the familiar three-dot control on its right.
 color(1,1,1,0.60).setFill()
 rounded(NSRect(x:242,y:657,width:250,height:24),12).fill()
 color(1,1,1).setFill()
 for x:CGFloat in [603,669,735] {
  NSBezierPath(ovalIn:NSRect(x:x-18,y:651,width:36,height:36)).fill()
 }

 // The right-aligned shelf below it, holding three compact app tiles.
 let shelf=rounded(NSRect(x:230,y:345,width:564,height:210),58)
 NSGraphicsContext.saveGraphicsState()
 let shelfShadow=NSShadow(); shelfShadow.shadowColor=color(0.01,0.16,0.29,0.25)
 shelfShadow.shadowBlurRadius=18; shelfShadow.shadowOffset=NSSize(width:0,height:-9); shelfShadow.set()
 color(0.95,0.99,1).setFill(); shelf.fill()
 NSGraphicsContext.restoreGraphicsState()
 for x:CGFloat in [293,468,643] {
  let slot=rounded(NSRect(x:x,y:406,width:88,height:88),23)
  NSGradient(starting:color(0.04,0.37,0.56),ending:color(0.10,0.57,0.68))!.draw(in:slot,angle:90)
 }
}

let output=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "build/SideTray.iconset",isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for points in [16,32,128,256,512] {
 for scale in [1,2] {
  let pixels=points*scale
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  bitmap.size=NSSize(width:pixels,height:pixels)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
  let transform=NSAffineTransform(); transform.scale(by:CGFloat(pixels)/1024); transform.concat()
  drawIcon()
  NSGraphicsContext.restoreGraphicsState()
  let suffix=scale == 2 ? "@2x" : ""
  try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
 }
}

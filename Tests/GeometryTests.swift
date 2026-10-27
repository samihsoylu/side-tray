import Foundation
import CoreGraphics
@main struct Tests {
 static func main() {
  let screen=CGRect(x:0,y:0,width:1728,height:1117)
  let anchor=CGRect(x:1600,y:1093,width:28,height:24)
  let short=TrayGeometry.frame(anchor:anchor,screen:screen,count:2)
  let long=TrayGeometry.frame(anchor:anchor,screen:screen,count:100)
  assert(short.height == anchor.height)
  assert(short.width == 2*28+16)
  let notched=TrayGeometry.frame(anchor:CGRect(x:1400,y:1083,width:44,height:34),screen:screen,count:7)
  assert(notched.height == 34 && notched.width == 7*34+16)
  assert(short.maxX == anchor.maxX)
  assert(long.width == anchor.maxX-screen.minX-12)
  assert(long.maxX == anchor.maxX)
  assert(long.minX >= screen.minX+12 && long.maxX <= screen.maxX-12)
  assert(anchor.minY-short.maxY == 2)
  let empty=TrayGeometry.frame(anchor:anchor,screen:screen,count:0)
  assert(empty.width >= 300)
  let external=CGRect(x:-1920,y:-200,width:1920,height:1080)
  let ext=TrayGeometry.frame(anchor:CGRect(x:-100,y:856,width:28,height:24),screen:external,count:4)
  assert(ext.minX >= external.minX+12 && ext.maxX <= external.maxX-12)
  assert(ext.minY >= external.minY+12 && ext.maxY <= external.maxY-12)
  let middle=CGRect(x:900,y:screen.maxY-24,width:28,height:24)
  let crowded=TrayGeometry.frame(anchor:middle,screen:screen,count:100)
  assert(crowded.maxX == middle.maxX)
  assert(crowded.minX == screen.minX+12)
  let primaryCG=CGRect(x:0,y:0,width:1728,height:1117)
  let secondaryCG=CGRect(x:-1920,y:200,width:1920,height:1080)
  let primaryButton=CGRect(x:1500,y:0,width:44,height:34)
  let secondaryButton=CGRect(x:-100,y:200,width:44,height:34)
  let frames=[primaryButton,secondaryButton]
  assert(TrayGeometry.anchorIndex(frames:frames,screens:[primaryCG,secondaryCG],point:CGPoint(x:-80,y:215)) == 1)
  // A shortcut or Settings click uses the pointer's display even off the bar.
  assert(TrayGeometry.anchorIndex(frames:frames,screens:[primaryCG,secondaryCG],point:CGPoint(x:-900,y:800)) == 1)
  assert(TrayGeometry.anchorIndex(frames:frames,screens:[primaryCG,secondaryCG],point:CGPoint(x:900,y:800)) == 0)
  assert(TrayGeometry.anchorIndex(frames:[],screens:[primaryCG],point:nil) == nil)
  assert(TrayGeometry.anchorIndex(frames:frames,screens:[],point:nil) == 0)
  print("PASS: clicked-display selection, pointer-display fallback, button-relative anchor, horizontal expansion, width cap, menu clearance, empty state, negative-origin display")
 }
}

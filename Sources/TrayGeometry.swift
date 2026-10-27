import Foundation
import CoreGraphics

struct TrayGeometry {
 static func anchorIndex(frames:[CGRect],screens:[CGRect],point:CGPoint?) -> Int? {
  guard !frames.isEmpty else { return nil }
  guard let point else { return frames.startIndex }
  if let hit=frames.firstIndex(where:{ $0.contains(point) }) { return hit }
  if let screen=screens.first(where:{ $0.contains(point) }),
     let index=frames.firstIndex(where:{ screen.contains($0) }) { return index }
  return frames.startIndex
 }
 static func itemWidth(rowHeight:CGFloat) -> CGFloat { max(28,rowHeight) }
 static func frame(anchor: CGRect, screen: CGRect, count: Int) -> CGRect {
  let margin: CGFloat=12
  let right=min(max(anchor.maxX,screen.minX+margin+1),screen.maxX-margin)
  let available=max(1,right-screen.minX-margin)
  let height=min(max(1,anchor.height),max(1,screen.height-2*margin))
  let desired: CGFloat=count == 0 ? 330 : CGFloat(count)*itemWidth(rowHeight:height)+16
  let width=min(available,desired)
  let bottom=max(screen.minY+margin,min(anchor.minY-height-2,screen.maxY-margin-height))
  return CGRect(x:right-width,y:bottom,width:width,height:height)
 }
}

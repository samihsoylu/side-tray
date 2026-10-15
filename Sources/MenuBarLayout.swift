import AppKit
import ApplicationServices

struct BarSlot {
 let bundle:String
 let pid:pid_t
 let frame:CGRect
 let element:AXUIElement
}

func barSlots() -> [BarSlot] {
 guard AXIsProcessTrusted(),let agent=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.MenuBarAgent").first else { return [] }
 let root=AXUIElementCreateApplication(agent.processIdentifier)
 AXUIElementSetMessagingTimeout(root,0.1)
 var slots=[BarSlot]()
 for window in children(root) where attribute(window,kAXRoleAttribute) as? String == kAXWindowRole {
  for wrapper in children(window) {
   guard let frame=rectAttribute(wrapper),frame.width>0,frame.height>0 else { continue }
   for child in children(wrapper) {
    // Some MenuBarAgent windows contain AXApplication references. Those are
    // discovery placeholders, not the rendered and actionable status button.
    let role=attribute(child,kAXRoleAttribute) as? String
    guard role == kAXButtonRole || role == kAXMenuBarItemRole else { continue }
    var pid:pid_t=0; AXUIElementGetPid(child,&pid)
    guard pid != agent.processIdentifier,let bundle=NSRunningApplication(processIdentifier:pid)?.bundleIdentifier else { continue }
    slots.append(BarSlot(bundle:bundle,pid:pid,frame:frame,element:child)); break
   }
  }
 }
 return slots
}

/// Reorders only SideTray's separator. Important app icons retain their order.
final class MenuBarOrdering {
 private(set) var isMoving=false
 private var release:CGEvent?
 private var generation=0
 func cancel() {
  generation += 1
  release?.post(tap:.cgSessionEventTap); release=nil; isMoving=false
 }
 func arrange(visible:Set<String>,completion:@escaping(Bool)->Void) {
  guard !isMoving,NSEvent.pressedMouseButtons == 0 else { completion(false); return }
  let own=ProcessInfo.processInfo.processIdentifier
  let slots=barSlots()
  guard let separator=slots.first(where: { $0.pid == own }) else { completion(false); return }
  guard let display=NSScreen.screens.compactMap({ screen -> CGRect? in
   guard let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
   let bounds=CGDisplayBounds(id); return bounds.contains(separator.frame) ? bounds : nil
  }).first else { completion(false); return }
  guard let first=slots.filter({ visible.contains($0.bundle) && display.contains($0.frame) && abs($0.frame.midY-separator.frame.midY)<2 }).min(by: { $0.frame.minX<$1.frame.minX }) else { completion(true); return }
  if separator.frame.maxX <= first.frame.minX+1 { completion(true); return }
  guard let start=verifiedStatusPoint(frame:separator.frame,pid:own) else { completion(false); return }
  let destination=CGPoint(x:first.frame.minX-separator.frame.width/2-2,y:start.y)
  guard display.contains(destination) else { completion(false); return }
  isMoving=true; generation += 1; let request=generation
  let original=CGEvent(source:nil)?.location
  let source=CGEventSource(stateID:.privateState)
  func event(_ type:CGEventType,_ point:CGPoint) -> CGEvent? {
   let value=CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:point,mouseButton:.left)
   value?.flags = .maskCommand; return value
  }
  guard let down=event(.leftMouseDown,start),let up=event(.leftMouseUp,destination) else { isMoving=false; completion(false); return }
  release=up; down.post(tap:.cgSessionEventTap)
  for step in 1...6 {
   DispatchQueue.main.asyncAfter(deadline:.now()+Double(step)*0.04) {
    guard request == self.generation else { return }
    let amount=CGFloat(step)/6
    event(.leftMouseDragged,CGPoint(x:start.x+(destination.x-start.x)*amount,y:start.y))?.post(tap:.cgSessionEventTap)
   }
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+0.3) {
   guard request == self.generation else { return }
   up.post(tap:.cgSessionEventTap); self.release=nil
   if let original,let now=CGEvent(source:nil)?.location,abs(now.x-destination.x)<3,abs(now.y-destination.y)<3 { CGWarpMouseCursorPosition(original) }
   func verify(_ remaining:Int) {
    guard request == self.generation else { return }
    let latest=barSlots()
    if let separator=latest.first(where: { $0.pid == own && display.contains($0.frame) }) {
     let shown=latest.filter { visible.contains($0.bundle) && display.contains($0.frame) && abs($0.frame.midY-separator.frame.midY)<2 }
     if shown.allSatisfy({ separator.frame.maxX <= $0.frame.minX+1 }) {
      self.isMoving=false; completion(true); return
     }
    }
    // MenuBarAgent can report the pre-drag frame while its layout settles.
    // Observe the resulting layout again; never repeat the drag automatically.
    if remaining>0 {
     DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { verify(remaining-1) }
    } else { self.isMoving=false; completion(false) }
   }
   DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { verify(4) }
  }
 }
}

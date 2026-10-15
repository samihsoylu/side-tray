import AppKit
import ApplicationServices

/// Read only window metadata. No screen capture, window titles or menu contents.
enum MenuEvidence {
 static func windows(for pid:pid_t) -> Set<CGWindowID> {
  Set((CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []).compactMap { info in
   guard info[kCGWindowOwnerPID as String] as? Int == Int(pid),
         (info[kCGWindowAlpha as String] as? Double ?? 0)>0,
         let bounds=info[kCGWindowBounds as String] as? [String:Any],
         let frame=CGRect(dictionaryRepresentation:bounds as CFDictionary),frame.width>=80,frame.height>=40,
         let number=info[kCGWindowNumber as String] as? UInt32 else { return nil }
   return number
  })
 }
}

/// One click only, after the reveal has settled and the intended owner is verified.
/// Failed verification never clicks a neighbour or retries a toggle-style menu.
final class MenuActivation {
 private var generation=0
 private var pending:((Bool)->Void)?
 private var release:CGEvent?
 private var original:CGPoint?
 private var clickPoint:CGPoint?
 private(set) var surfaceWindows=Set<CGWindowID>()
 private let actionQueue=DispatchQueue(label:"io.sidetray.menu-action",qos:.userInitiated)

 func close(bundle:String,completion:@escaping()->Void) {
  guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:bundle).first else { completion(); return }
  actionQueue.async {
   let root=AXUIElementCreateApplication(app.processIdentifier)
   AXUIElementSetMessagingTimeout(root,0.2)
   var menu:AXUIElement?
   if let extras=attribute(root,kAXExtrasMenuBarAttribute),CFGetTypeID(extras) == AXUIElementGetTypeID() {
    for item in children(extras as! AXUIElement) {
     for child in children(item) where attribute(child,kAXRoleAttribute) as? String == kAXMenuRole {
      var actions:CFArray?; AXUIElementCopyActionNames(child,&actions)
      if (actions as? [String] ?? []).contains(kAXCancelAction) { menu=child; break }
     }
    }
   }
   if let menu {
    AXUIElementSetMessagingTimeout(menu,0.2)
    let result=AXUIElementPerformAction(menu,kAXCancelAction as CFString)
    UserDefaults.standard.set(result.rawValue,forKey:"lastCancelResult")
   } else {
    let source=CGEventSource(stateID:.hidSystemState)
    let down=CGEvent(keyboardEventSource:source,virtualKey:53,keyDown:true)
    let up=CGEvent(keyboardEventSource:source,virtualKey:53,keyDown:false)
    down?.flags=[]; up?.flags=[]; down?.postToPid(app.processIdentifier); up?.postToPid(app.processIdentifier)
   }
   DispatchQueue.main.async(execute:completion)
  }
 }

 func cancel() {
  generation += 1
  release?.post(tap:.cghidEventTap); release=nil
  let done=pending; pending=nil
  restorePointer()
  done?(false)
 }
 private func restorePointer() {
  defer { original=nil; clickPoint=nil }
  if let original,let point=clickPoint,let now=CGEvent(source:nil)?.location,
     abs(now.x-point.x)<3,abs(now.y-point.y)<3 { CGWarpMouseCursorPosition(original) }
 }
 func open(bundle:String,display:CGDirectDisplayID?=nil,completion:@escaping(Bool)->Void) {
  cancel()
  pending=completion
  surfaceWindows=[]
  let request=generation
  let deadline=Date().addingTimeInterval(1.5)
  var previous:CGRect?
  var previousWindows:Set<CGWindowID>?
  func targetEntry() -> Entry? {
   for slot in barSlots() where slot.bundle == bundle {
    if let display,!CGDisplayBounds(display).contains(slot.frame) { continue }
    if let app=NSRunningApplication(processIdentifier:slot.pid) {
     return Entry(app:app,element:slot.element,frame:slot.frame)
    }
   }
   return nil
  }
  let owner=NSRunningApplication.runningApplications(withBundleIdentifier:bundle).first?.processIdentifier
  let existingMenuOpen=(CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []).contains {
   owner != nil && $0[kCGWindowOwnerPID as String] as? Int == Int(owner!) && $0[kCGWindowLayer as String] as? Int == 101
  }
  func finish(_ observed:Bool) {
   guard request == self.generation else { return }
   self.release=nil; self.pending=nil
   UserDefaults.standard.set(observed,forKey:"lastMenuObserved")
   self.restorePointer()
   completion(observed)
  }
  func click(_ entry:Entry,_ point:CGPoint) {
   // Observe only surfaces created by the status-item action. Do not bring
   // the owner's ordinary windows forward before opening its menu.
   let baseline=MenuEvidence.windows(for:entry.app.processIdentifier)
   func observe() {
    let end=Date().addingTimeInterval(0.8)
    func poll() {
     guard request == self.generation else { return }
     let opened=MenuEvidence.windows(for:entry.app.processIdentifier).subtracting(baseline)
     if !opened.isEmpty { self.surfaceWindows=opened; finish(true); return }
     if Date()>=end { finish(false); return }
     DispatchQueue.main.asyncAfter(deadline:.now()+0.05,execute:poll)
    }
    poll()
   }
   var copiedActions:CFArray?
   AXUIElementCopyActionNames(entry.element,&copiedActions)
   if (copiedActions as? [String] ?? []).contains(kAXPressAction) {
    UserDefaults.standard.set("MenuBarAgent button",forKey:"lastActivationRoute")
    // This is the live button exposed by MenuBarAgent, rather than the app's
    // AXExtrasMenuBar stand-in, which failed earlier tests. Observe even when
    // a modal native menu prevents AX from returning a success response.
    self.actionQueue.async {
     AXUIElementSetMessagingTimeout(entry.element,0.25)
     let result=AXUIElementPerformAction(entry.element,kAXPressAction as CFString)
     DispatchQueue.main.async {
      guard request == self.generation else { return }
      UserDefaults.standard.set(result.rawValue,forKey:"lastNativeActionResult")
      observe()
     }
    }
    return
   }
   UserDefaults.standard.set("Forwarded click",forKey:"lastActivationRoute")
   let source=CGEventSource(stateID:.hidSystemState)
   guard let down=CGEvent(mouseEventSource:source,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),
         let up=CGEvent(mouseEventSource:source,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left) else { finish(false); return }
   // Source state must not inherit the initiating click's modifiers or buttons.
   down.flags=[]; up.flags=[]
   down.setIntegerValueField(.mouseEventClickState,value:1)
   up.setIntegerValueField(.mouseEventClickState,value:1)
   self.original=CGEvent(source:nil)?.location; self.clickPoint=point
   UserDefaults.standard.set([point.x,point.y],forKey:"lastForwardPoint")
   UserDefaults.standard.set(bundle,forKey:"lastForwardBundle")
   // Give MenuBarAgent a move at the resolved slot before the press so hover
   // routing follows the new layout after a hidden item has been revealed.
   let move=CGEvent(mouseEventSource:source,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:.left)
   move?.flags=[]; move?.post(tap:.cghidEventTap)
   DispatchQueue.main.asyncAfter(deadline:.now()+0.05) {
    guard request == self.generation else { return }
    self.release=up
    down.post(tap:.cghidEventTap)
   }
   DispatchQueue.main.asyncAfter(deadline:.now()+0.1) {
    guard request == self.generation else { return }
    up.post(tap:.cghidEventTap); self.release=nil
    observe()
   }
  }
  func settle() {
   guard request == self.generation else { return }
   guard AXIsProcessTrusted(),Date()<deadline else { finish(false); return }
   if NSEvent.pressedMouseButtons == 0,
      let entry=targetEntry(),let frame=entry.frame,
      NSScreen.screens.contains(where: { screen in
       guard let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
       return CGDisplayBounds(id).contains(frame)
      }) {
    let windows=MenuEvidence.windows(for:entry.app.processIdentifier)
    if previous == frame,previousWindows == windows {
     var actions:CFArray?
     AXUIElementCopyActionNames(entry.element,&actions)
     // The live, owner-verified accessibility button addresses the intended
     // item directly, even when full-screen auto-hide covers its screen point.
     // Coordinate forwarding still requires a matching on-screen hit test.
     if (actions as? [String] ?? []).contains(kAXPressAction) {
      click(entry,CGPoint(x:frame.midX,y:frame.midY)); return
     }
     if let point=verifiedStatusPoint(frame:frame,pid:entry.app.processIdentifier) { click(entry,point); return }
    }
    previous=frame
    previousWindows=windows
   }
   DispatchQueue.main.asyncAfter(deadline:.now()+0.08,execute:settle)
  }
  // The status-item action handles its own menu focus. Activating the owner
  // first can switch Spaces and dismiss the just-opened menu in full screen.
  if existingMenuOpen {
   close(bundle:bundle) { DispatchQueue.main.asyncAfter(deadline:.now()+0.05,execute:settle) }
  } else { DispatchQueue.main.asyncAfter(deadline:.now()+0.08,execute:settle) }
 }
}

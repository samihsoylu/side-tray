import AppKit
import ApplicationServices
import ServiceManagement
import Darwin

func attribute(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
 var value: CFTypeRef?
 guard AXUIElementCopyAttributeValue(e,key as CFString,&value) == .success else { return nil }
 return value
}
func children(_ e: AXUIElement) -> [AXUIElement] { attribute(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func rectAttribute(_ element:AXUIElement) -> CGRect? {
 guard let value=attribute(element,"AXFrame"),CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
 var rect=CGRect.zero
 return AXValueGetValue(value as! AXValue,.cgRect,&rect) ? rect : nil
}
func statusItemOwner(at point:CGPoint) -> pid_t? {
 let root=AXUIElementCreateSystemWide()
 AXUIElementSetMessagingTimeout(root,0.1)
 var hit:AXUIElement?
 guard AXUIElementCopyElementAtPosition(root,Float(point.x),Float(point.y),&hit) == .success,let hit else { return nil }
 let role=attribute(hit,kAXRoleAttribute) as? String
 guard role == kAXMenuBarItemRole || role == kAXButtonRole else { return nil }
 var owner:pid_t=0; AXUIElementGetPid(hit,&owner)
 return owner
}
func verifiedStatusPoint(frame:CGRect,pid:pid_t) -> CGPoint? {
 // Resolve drawing/AX layout differences without sending input to another app.
 for offset:CGFloat in [0,-4,4,-8,8,-16,16,-24,24,-32,32,-40,40,-48,48,-64,64] {
  let point=CGPoint(x:frame.midX+offset,y:frame.midY)
  if statusItemOwner(at:point) == pid { return point }
 }
 return nil
}
struct Entry { let app: NSRunningApplication; let element: AXUIElement; let frame:CGRect? }
func entries() -> [Entry] {
 var seen=Set<pid_t>()
 return barSlots().compactMap { slot in
  guard slot.pid != ProcessInfo.processInfo.processIdentifier,seen.insert(slot.pid).inserted,
        let app=NSRunningApplication(processIdentifier:slot.pid) else { return nil }
  return Entry(app:app,element:slot.element,frame:slot.frame)
 }
}
final class TrayButton:NSButton {
 override var acceptsFirstResponder:Bool { true }
 override func becomeFirstResponder() -> Bool { needsDisplay=true; return true }
 override func resignFirstResponder() -> Bool { needsDisplay=true; return true }
 override func draw(_ dirtyRect:NSRect) {
  super.draw(dirtyRect)
  if window?.firstResponder === self {
   NSColor.keyboardFocusIndicatorColor.setStroke()
   let ring=NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:5,yRadius:5); ring.lineWidth=2; ring.stroke()
  }
 }
 override func keyDown(with event:NSEvent) {
  if (window as? TrayPanel)?.handleKey(event) == true { return }; super.keyDown(with:event)
 }
}
final class TrayPanel: NSPanel {
 var keyboardItems=[NSButton]()
 override var canBecomeKey: Bool { true }
 override func cancelOperation(_ sender: Any?) { orderOut(nil) }
 func handleKey(_ event:NSEvent) -> Bool {
  guard !keyboardItems.isEmpty else { return false }
  let current=keyboardItems.firstIndex { firstResponder === $0 }
  if [123,124,48,115,119].contains(event.keyCode) {
   let backwards=event.keyCode == 123 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
   let next:Int
   if event.keyCode == 115 { next=0 } else if event.keyCode == 119 { next=keyboardItems.count-1 }
   else { next=current.map { ($0+(backwards ? -1 : 1)+keyboardItems.count)%keyboardItems.count } ?? (backwards ? keyboardItems.count-1 : 0) }
   let button=keyboardItems[next]; button.scrollToVisible(button.bounds); makeFirstResponder(button); return true
  }
  if event.keyCode == 36 || event.keyCode == 49 {
   keyboardItems[current ?? 0].performClick(nil); return true
  }
  if event.keyCode == 109 && event.modifierFlags.contains(.shift),let current,let menu=keyboardItems[current].menu {
   menu.popUp(positioning:nil,at:NSPoint(x:0,y:keyboardItems[current].bounds.height),in:keyboardItems[current]); return true
  }
  return false
 }
 override func keyDown(with event:NSEvent) { if !handleKey(event) { super.keyDown(with:event) } }
}
final class Controller: NSObject, NSApplicationDelegate {
 var status: NSStatusItem!
 var panel: TrayPanel!
 var trayDisplay:CGDirectDisplayID?
 var current=[Entry]()
 var monitor: Any?
 var localMonitor: Any?
 var settings: NSWindow?
 let updates=Updates()
 let placement=PlacementStore()
 var setupPending=SetupProgress.needsSetup()
 var permissionRecovery=PermissionRecovery()
 var settingsUI:SettingsUI?
 var checkingPermissions=false
 var permissionCheckRequested=false
 var trayErrorBundle:String?
 var visibilityMessage="" { didSet { settingsUI?.updateMessage() } }
 var openingMenu=false
 var listBundles=[String]()
 var placementBusy=false
 var discoveringApps=false
 let shortcut=TrayShortcut()
 var shortcutRegistered=false
 let activation=MenuActivation()
 let ordering=MenuBarOrdering()
 let menuSwitches=MenuSwitches()
 let visibilityPipeline=VisibilityPipeline()
 let visibilityQueue=DispatchQueue(label:"io.sidetray.menu-settings",qos:.userInitiated)
 var useMenuSwitches=true
 var menuDataReadable=false
 var menuDataAccess:MenuDataAccess = .checking
 var startupRecoveryComplete=false
 var recoveryBlocked=false
 var visibilityPaused=false
 var wakeRecovery=WakeRecovery()
 var setupReadiness=WakeRecovery(delays:[0.3,2,5])
 var setupPermissionsWereReady=false
 var terminating=false
 var recoveryWatcher:Process?
 var lastMenuBarRefresh:Date?
 var observers=[(NotificationCenter,NSObjectProtocol)]()
 var permissionTimer:Timer?
 var trusted=false
 var suspended=false
 var activeMenuBundle:String?
 var menuWatcher:Timer?
 var settingsTab="apps"
 var hiddenBundles:Set<String> {
  Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
   .union(placement.names.keys)
   .subtracting(placement.visible)
   .filter { !$0.hasPrefix("com.apple.") && $0 != Bundle.main.bundleIdentifier }
 }
 #if SIDETRAY_UX_FIXTURE
 // Test snapshots never grant OS access or run native visibility operations.
 var fixtureWakeAttempt:((Int,@escaping(Bool)->Void)->Void)?
 var fixtureRestoreVisibility:(()->Void)?
 var fixtureReadinessCheck:((@escaping()->Void)->Void)?
 var fixtureInitialLayout:((@escaping(Bool)->Void)->Void)?
 var fixtureOpenSettings:((String)->Void)?
 var fixtureCheckPermissions:(()->Void)?
 var fixtureControlAccess:Bool?
 var fixtureInstalled:Bool?
 var fixtureHelperRunning:Bool?
 var fixtureResumeVisibility:((@escaping(Bool)->Void)->Void)?
 #endif
 var controlAccessGranted:Bool {
  #if SIDETRAY_UX_FIXTURE
  if let value=fixtureControlAccess { return value }
  #endif
  #if SIDETRAY_UX_FIXTURE && !SIDETRAY_PERMISSION_JOURNEY
  return false
  #else
  return AXIsProcessTrusted()
  #endif
 }
 var isInstalled:Bool {
  #if SIDETRAY_UX_FIXTURE
  if let value=fixtureInstalled { return value }
  #endif
  return Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/")
 }
 var recoveryHelperRunning:Bool {
  #if SIDETRAY_UX_FIXTURE
  if let value=fixtureHelperRunning { return value }
  #endif
  return recoveryWatcher?.isRunning == true
 }
 var accessReady:Bool { controlAccessGranted && isInstalled && menuDataReadable && startupRecoveryComplete && !recoveryBlocked && recoveryHelperRunning }
 var canManageVisibility:Bool { accessReady && !visibilityPaused && !wakeRecovery.isActive && !setupPending && !permissionRecovery.isActive }
 func applicationDidFinishLaunching(_ notification: Notification) {
  if let url=Bundle.main.url(forResource:"SideTray",withExtension:"icns"),let icon=NSImage(contentsOf:url) {
   NSApp.applicationIconImage=icon
  }
  updates.changed={ [weak self] in
   guard let self else { return }
   self.settingsUI?.updateUpdates()
   self.status?.button?.toolTip=self.updates.candidate == nil ? "SideTray — click to open, right-click for options" : "SideTray — update ready in Settings"
  }
  #if !SIDETRAY_FIRST_RUN_TEST
  updates.start()
  #endif
  trusted=controlAccessGranted
  if let issue=menuSwitches.recoveryIssue { visibilityMessage=issue }
  if !UserDefaults.standard.bool(forKey:"didRemoveExperimentalPosition") {
   UserDefaults.standard.removeObject(forKey:"NSStatusItem Preferred Position SideTray.StatusItem")
   UserDefaults.standard.set(true,forKey:"didRemoveExperimentalPosition")
  }
  status=NSStatusBar.system.statusItem(withLength:28)
  status.autosaveName="SideTray.StatusItem"
  status.isVisible=true
  // A text ellipsis follows a font baseline and sits above the menu-row center.
  // Use a symmetric template canvas so AppKit centers the dots as an icon.
  let dots=NSImage(size:NSSize(width:18,height:18),flipped:false) { _ in
   NSColor.black.setFill()
   for x:CGFloat in [3,9,15] { NSBezierPath(ovalIn:NSRect(x:x-1.5,y:7.5,width:3,height:3)).fill() }
   return true
  }
  dots.isTemplate=true
  status.button?.title=""
  status.button?.image=dots
  status.button?.imagePosition = .imageOnly
  status.button?.imageScaling = .scaleNone
  status.button?.setAccessibilityLabel("SideTray")
  status.button?.toolTip="SideTray — click to open, right-click for options"
  status.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
  status.button?.target=self; status.button?.action=#selector(statusClicked)
  panel=TrayPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  panel.level = .popUpMenu; panel.isOpaque=false; panel.backgroundColor = .clear
  panel.hasShadow=true; panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
  localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) { [weak self] event in
   guard let self else { return event }
   if event.type == .keyDown,let recorder=event.window?.firstResponder as? ShortcutRecorder,recorder.recording { return event }
   if event.type == .keyDown && event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," { self.showSettings(); return nil }
   if event.type == .keyDown && event.window === self.panel && self.panel.handleKey(event) { return nil }
   if event.type == .keyDown && event.keyCode == 53 && self.activeMenuBundle != nil { self.closeActiveMenu(); return nil }
   if self.panel.isVisible && event.type == .keyDown && event.keyCode == 53 { self.panel.orderOut(nil); return nil }
   if event.type != .keyDown && event.window !== self.panel && event.window !== self.status.button?.window { self.panel.orderOut(nil) }
   return event
  }
  installGlobalMonitor()
  installAppMenu()
  shortcut.action={ [weak self] in
   UserDefaults.standard.set(Date().timeIntervalSince1970,forKey:"lastShortcutActivation")
   self?.toggle()
  }
  registerShortcut()
  installLifecycle()
  #if SIDETRAY_FIRST_RUN_TEST
  Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
   guard let self else { return }
   let evidence:[String:Any] = ["pid":ProcessInfo.processInfo.processIdentifier,"setupPending":self.setupPending,
    "setupComplete":UserDefaults.standard.bool(forKey:"setupComplete"),"controlGranted":self.controlAccessGranted,
    "dataGranted":self.menuDataReadable,"helperRunning":self.recoveryHelperRunning,"helperPID":self.recoveryWatcher?.processIdentifier ?? 0,
    "accessReady":self.accessReady,"paused":self.visibilityPaused,"message":self.visibilityMessage,"title":self.settings?.title ?? "",
    "checkedAt":ISO8601DateFormatter().string(from:Date())]
   let dir=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("io.sidetray.test.firstrun")
   try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
   if let data=try? JSONSerialization.data(withJSONObject:evidence,options:.sortedKeys) { try? data.write(to:dir.appendingPathComponent("status.json"),options:.atomic) }
  }
  #endif
  if setupPending { probeSetupPermissions() } else { checkMenuDataAccess() }
  if setupPending || !isInstalled { showSettings(destination:"permissions") }
  else { updatePermissionRecovery() }
 }
 func installGlobalMonitor() {
  if let monitor { NSEvent.removeMonitor(monitor) }; monitor=nil
  var mask:NSEvent.EventTypeMask=[.leftMouseDown,.rightMouseDown,.leftMouseUp,.rightMouseUp]
  if trusted { mask.insert(.keyDown) }
  monitor=NSEvent.addGlobalMonitorForEvents(matching:mask) { [weak self] event in
   guard let self else { return }
   if event.type == .keyDown {
    if event.keyCode == 53 { self.closeActiveMenu(); self.panel.orderOut(nil) }
    return
   }
   if event.type == .leftMouseUp,let bundle=self.activeMenuBundle,let point=event.cgEvent?.location ?? CGEvent(source:nil)?.location {
    // Native AX frames can differ from drawing positions. Verify the item
    // actually under the pointer, just as we do before forwarding a click.
    let owner=statusItemOwner(at:point)
    let matched=owner.flatMap { NSRunningApplication(processIdentifier:$0)?.bundleIdentifier } == bundle
    // Bounded interaction diagnostics: no coordinates, keys or app content.
    UserDefaults.standard.set(Date().timeIntervalSince1970,forKey:"lastMenuMouseUpTime")
    UserDefaults.standard.set(matched,forKey:"lastSourceClickMatched")
    if matched { DispatchQueue.main.asyncAfter(deadline:.now()+0.05) {
     if self.activeMenuBundle == bundle { self.closeActiveMenu() }
    } }
   }
   // Dismiss on an outside press, not the release that just opened the tray.
   // MenuBarAgent owns the status item, so its mouse-up is a global event here.
   guard event.type == .leftMouseDown || event.type == .rightMouseDown else { return }
   guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
   if let point=event.cgEvent?.location,
      barSlots().contains(where: { $0.pid == ProcessInfo.processInfo.processIdentifier && $0.frame.contains(point) }) { return }
   self.panel.orderOut(nil)
  }
  UserDefaults.standard.set(monitor != nil,forKey:"globalMonitorReady")
 }
 @objc func statusClicked() {
  guard !ordering.isMoving else { return }
  if NSApp.currentEvent?.type == .rightMouseUp,let button=status.button {
   panel.orderOut(nil)
   let menu=commandMenu(); menu.popUp(positioning:nil,at:NSPoint(x:0,y:button.bounds.height),in:button); return
  }
  toggle()
 }
 @objc func toggle() {
  if panel.isVisible { panel.orderOut(nil); return }
  guard canManageVisibility else { showSettings(destination:setupPending && accessReady ? "apps" : "permissions"); return }
  if activeMenuBundle != nil { closeActiveMenu() }
  let anchors=barSlots().filter { $0.pid == ProcessInfo.processInfo.processIdentifier }
  let displays=NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
  let point=NSApp.currentEvent?.cgEvent?.location ?? CGEvent(source:nil)?.location
  guard let index=TrayGeometry.anchorIndex(frames:anchors.map(\.frame),screens:displays.map(CGDisplayBounds),point:point) else {
   visibilityMessage="SideTray’s menu bar button is unavailable. Check Permissions and installation."; showSettings(); return
  }
  let slot=anchors[index]
  guard
        let screen=NSScreen.screens.first(where: { screen in
         guard let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
         return CGDisplayBounds(id).contains(slot.frame)
        }),let display=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
   visibilityMessage="SideTray’s menu bar button is unavailable. Check Permissions and installation."; showSettings(); return
  }
  let bounds=CGDisplayBounds(display)
  trayDisplay=display
  let anchor=CGRect(x:screen.frame.minX+slot.frame.minX-bounds.minX,
                    y:screen.frame.maxY-(slot.frame.maxY-bounds.minY),
                    width:slot.frame.width,height:slot.frame.height)
  current=availableEntries().filter { entry in entry.app.bundleIdentifier.map(hiddenBundles.contains) ?? false }
  let frame=TrayGeometry.frame(anchor:anchor,screen:screen.frame,count:current.count)
  renderTray(frame:frame)
 }
 func renderTray(frame:CGRect) {
  let height=frame.height
  let width=frame.width
  let visual=NSVisualEffectView(frame:NSRect(x:0,y:0,width:width,height:height))
  visual.material = .popover; visual.state = .active; visual.wantsLayer=true; visual.layer?.cornerRadius=min(8,height/3)
  let itemWidth=TrayGeometry.itemWidth(rowHeight:height)
  // App artwork includes transparent padding; use more of the compact row.
  let iconSize=min(24,max(1,height-4))
  let scroll=NSScrollView(frame:visual.bounds.insetBy(dx:8,dy:0)); scroll.drawsBackground=false; scroll.hasHorizontalScroller=false; scroll.hasVerticalScroller=false
  let content=NSView(frame:NSRect(x:0,y:0,width:max(width-16,CGFloat(current.count)*itemWidth),height:height))
  panel.keyboardItems=[]; trayErrorBundle=nil
  for (index,entry) in current.enumerated() {
   let icon=TrayButton(frame:NSRect(x:CGFloat(index)*itemWidth,y:0,width:itemWidth,height:height))
   let image=entry.app.icon?.copy() as? NSImage
   image?.size=NSSize(width:iconSize,height:iconSize)
   icon.image=image; icon.imageScaling = .scaleProportionallyDown; icon.isBordered=false
   icon.toolTip=entry.app.localizedName; icon.setAccessibilityLabel(entry.app.localizedName ?? "App")
   let menu=NSMenu()
   let keep=NSMenuItem(title:"Show in Menu Bar",action:#selector(removeFromTray(_:)),keyEquivalent:"")
   keep.target=self; keep.representedObject=entry.app.bundleIdentifier; menu.addItem(keep)
   let settingsItem=NSMenuItem(title:"Manage Apps…",action:#selector(manageApps),keyEquivalent:"")
   settingsItem.target=self; menu.addItem(settingsItem); icon.menu=menu
   icon.tag=index; icon.target=self; icon.action=#selector(activate(_:)); content.addSubview(icon); panel.keyboardItems.append(icon)
  }
  if current.isEmpty {
   let label=NSTextField(labelWithString:"No hidden apps")
   label.font = .systemFont(ofSize:12); label.textColor = .secondaryLabelColor
   label.frame=NSRect(x:4,y:(height-18)/2,width:max(1,width-155),height:18); content.addSubview(label)
   let manage=TrayButton(title:"Manage Apps…",target:self,action:#selector(manageApps))
   manage.frame=NSRect(x:max(4,width-145),y:0,width:125,height:height); manage.isBordered=false
   content.addSubview(manage); panel.keyboardItems=[manage]
  }
  scroll.documentView=content; visual.addSubview(scroll); panel.contentView=visual
  panel.setFrame(frame,display:true)
  panel.makeKeyAndOrderFront(nil)
  panel.makeFirstResponder(nil)
  if content.frame.width > scroll.contentSize.width+1 {
   // Reserve an independent click target; the cue must not cover the last icon.
   let moreWidth:CGFloat=22
   scroll.setFrameSize(NSSize(width:max(1,width-8-moreWidth),height:height))
   let more=TrayButton(title:"›",target:self,action:#selector(scrollTrayForward))
   more.frame=NSRect(x:width-moreWidth,y:0,width:moreWidth,height:height); more.isBordered=false; more.setAccessibilityLabel("More apps")
   visual.addSubview(more)
  }
 }
 @objc func scrollTrayForward() {
  guard let scroll=panel.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first else { return }
  let maxX=max(0,(scroll.documentView?.bounds.width ?? 0)-scroll.contentSize.width)
  let x=scroll.contentView.bounds.minX >= maxX-1 ? 0 : min(maxX,scroll.contentView.bounds.minX+scroll.contentSize.width*0.75)
  scroll.contentView.scroll(to:NSPoint(x:x,y:0)); scroll.reflectScrolledClipView(scroll.contentView)
 }
 @objc func manageApps() { showSettings(destination:"apps") }
 func showMenuFailure(_ bundle:String) {
  guard !suspended else { return }
  trayErrorBundle=bundle
  let name=placement.names[bundle] ?? "App"
  var frame=panel.frame
  let width=min(380,max(1,frame.maxX-(panel.screen?.frame.minX ?? 0)-12))
  frame.origin.x=frame.maxX-width; frame.size.width=width
  let view=NSVisualEffectView(frame:NSRect(origin:.zero,size:frame.size)); view.material = .popover; view.state = .active
  view.wantsLayer=true; view.layer?.cornerRadius=8
  let message=NSTextField(labelWithString:"\(name) didn’t open.")
  message.font = .systemFont(ofSize:12); message.lineBreakMode = .byTruncatingTail; message.toolTip="\(name) didn’t open. Try again."
  message.frame=NSRect(x:10,y:(frame.height-18)/2,width:max(1,width-85),height:18)
  let retry=TrayButton(title:"Retry",target:self,action:#selector(retryMenu))
  retry.frame=NSRect(x:width-70,y:0,width:60,height:frame.height); retry.isBordered=false
  view.addSubview(message); view.addSubview(retry); panel.contentView=view; panel.keyboardItems=[retry]
  panel.setFrame(frame,display:true); panel.makeKeyAndOrderFront(nil)
 }
 @objc func retryMenu() { if let bundle=trayErrorBundle { revealAndOpen(bundle) } }
 @objc func activate(_ sender: NSButton) {
  guard current.indices.contains(sender.tag) else { return }
  let selected=current[sender.tag].app.processIdentifier
  guard !openingMenu,!ordering.isMoving else { return }
  if let bundle=current[sender.tag].app.bundleIdentifier,hiddenBundles.contains(bundle) {
   revealAndOpen(bundle); return
  }
  guard AXIsProcessTrusted(),let fresh=entries().first(where: { $0.app.processIdentifier == selected }) else {
   showSettings(); return
  }
  forwardClick(fresh)
 }
 func forwardClick(_ fresh:Entry,completion: @escaping () -> Void = {}) {
  guard let bundle=fresh.app.bundleIdentifier else { completion(); return }
  panel.orderOut(nil)
  activation.open(bundle:bundle,display:trayDisplay) { observed in
   if !observed { self.showMenuFailure(bundle) }
   completion()
  }
 }
 func availableEntries() -> [Entry] {
  #if SIDETRAY_UX_FIXTURE
  return [] // Presentation tests must never query other apps through Accessibility.
  #else
  guard controlAccessGranted else { return [] }
  var found=entries()
  for bundle in hiddenBundles {
   guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:bundle).first,
         !found.contains(where: { $0.app.processIdentifier == app.processIdentifier }) else { continue }
   let root=AXUIElementCreateApplication(app.processIdentifier)
   if placement.names[bundle] != nil {
    // A known menu app stays reachable even if hiding removes AXExtrasMenuBar.
    // This is an identity only; activation resolves a real button after reveal.
    found.append(Entry(app:app,element:root,frame:nil))
   } else {
    // Ordinary running apps and helpers are not automatically menu bar apps.
    AXUIElementSetMessagingTimeout(root,0.15)
    if let value=attribute(root,kAXExtrasMenuBarAttribute),CFGetTypeID(value) == AXUIElementGetTypeID(),let item=children(value as! AXUIElement).first {
     found.append(Entry(app:app,element:item,frame:nil))
    }
   }
  }
  var seen=Set<String>()
  return found.filter { entry in
   guard let bundle=entry.app.bundleIdentifier else { return false }
   guard !bundle.hasPrefix("com.apple."),bundle != Bundle.main.bundleIdentifier else { return false }
   return seen.insert(bundle).inserted
  }.sorted { ($0.app.localizedName ?? "") < ($1.app.localizedName ?? "") }
  #endif
 }
 func allowedBundles(reveal:String?=nil) -> [String] {
  var allowed=placement.visible
  allowed.formUnion(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { $0.hasPrefix("com.apple.") })
  // Include ourselves explicitly: NSWorkspace may not yet list us during launch.
  if let own=Bundle.main.bundleIdentifier { allowed.insert(own) }
  allowed.insert("io.sidetray.prototype")
  if let reveal { allowed.insert(reveal) }
  for app in NSWorkspace.shared.runningApplications {
   if let bundle=app.bundleIdentifier,allowed.contains(bundle),let identifier=menuSigningIdentifier(app) { allowed.insert(identifier) }
  }
  return allowed.sorted()
 }
 func rememberMenuApps(_ slots:[BarSlot]) {
  for slot in slots where !slot.bundle.hasPrefix("com.apple.") && slot.bundle != Bundle.main.bundleIdentifier {
   if let app=NSRunningApplication(processIdentifier:slot.pid) {
    placement.remember(app.localizedName ?? slot.bundle,for:slot.bundle)
   }
  }
 }
 func applyVisibility(reveal:String?=nil,wakeToken:Int?=nil,completion:@escaping(Bool)->Void={_ in}) {
  visibilityPipeline.submit { finish in
   self.applyVisibilityNow(reveal:reveal,wakeToken:wakeToken) { ok in
    completion(ok)
    finish()
   }
  }
 }
 private func applyVisibilityNow(reveal:String?,wakeToken:Int?,completion:@escaping(Bool)->Void) {
  if let token=wakeToken {
   guard wakeRecovery.accepts(token) else { completion(false); return }
  } else if wakeRecovery.isActive { completion(false); return }
  guard !visibilityPaused,!setupPending,permissionRecovery.state != .needsAttention else { completion(false); return }
  guard startupRecoveryComplete,!recoveryBlocked else {
   visibilityMessage="Recovery must finish before SideTray can hide icons. Open Permissions and use Retry."
   completion(false); return
  }
  guard !suspended,AXIsProcessTrusted() else {
   visibilityMessage=suspended ? "Menu bar visibility is temporarily suspended." : "Control access is needed before placement can be applied."
   restoreVisibility(); completion(false); return
  }
  guard isInstalled else {
   visibilityMessage="Move SideTray to Applications, then open it there to manage your menu bar."
   STRestoreVisibility(); completion(false); return
  }
  if useMenuSwitches {
   STRestoreVisibility()
   guard recoveryWatcher?.isRunning == true else {
    visibilityMessage="Menu bar recovery is not running. Check settings access in Permissions before changing placement."
    completion(false); return
   }
   var visible=placement.visible; visible.insert(Bundle.main.bundleIdentifier ?? "io.sidetray.prototype")
   if let reveal { visible.insert(reveal) }
   let slots=barSlots()
   // Remember an app before hiding its only discoverable native button.
   rememberMenuApps(slots)
   let known=Set(placement.names.keys).union(slots.map(\.bundle))
   let aliases=menuPreferenceAliases(NSWorkspace.shared.runningApplications)
   visibilityQueue.async {
    do {
     try self.menuSwitches.applyVisible(visible,known:known,aliases:aliases)
     DispatchQueue.main.async {
      self.verifyMenuBarUpdate(visible:visible,known:known,wakeToken:wakeToken) { ok in
       if let token=wakeToken,!self.wakeRecovery.accepts(token) { completion(false); return }
       if !ok { self.pauseAfterVisibilityFailure() }
       completion(ok)
      }
     }
    } catch {
     var restoreFailure:Error?
     do { try self.menuSwitches.restore() } catch { restoreFailure=error }
     DispatchQueue.main.async {
      self.menuDataReadable=false
      self.menuDataAccess=MenuDataAccess.failure(error)
      self.recoveryBlocked=true
      self.visibilityMessage=restoreFailure.map(recoveryExplanation) ?? "Menu bar settings could not be updated. Your original settings were restored. Choose Retry to try again."
      completion(false)
     }
    }
   }
   return
  }
  if hiddenBundles.isEmpty { STRestoreVisibility(); completion(true); return }
  let started=STSetVisibleBundles(allowedBundles(reveal:reveal)) { error in
   if let error,(error as NSError).code != NSUserCancelledError { self.visibilityMessage="Visibility could not be updated. Your icons have been restored."; NSLog("Visibility failure: %@",error.localizedDescription); STRestoreVisibility() }
   completion(error == nil)
  }
  if !started { visibilityMessage="This macOS version does not support hiding."; STRestoreVisibility(); completion(false) }
 }
 func verifyMenuBarUpdate(visible:Set<String>,known:Set<String>,wakeToken:Int?=nil,completion:@escaping(Bool)->Void) {
  let running=Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
  let own=Bundle.main.bundleIdentifier ?? "io.sidetray.prototype"
  let shown=visible.intersection(known).intersection(running).union([own])
  let hidden=known.subtracting(visible).filter { !$0.hasPrefix("com.apple.") }
  var deadline=Date().addingTimeInterval(2)
  var refreshed=false
  func poll() {
   if let token=wakeToken,!self.wakeRecovery.accepts(token) { completion(false); return }
   guard !self.suspended,AXIsProcessTrusted() else { completion(false); return }
   let slots=barSlots(); let present=Set(slots.map(\.bundle))
   if shown.isSubset(of:present),hidden.isDisjoint(with:present) { completion(true); return }
   if Date()<deadline { DispatchQueue.main.asyncAfter(deadline:.now()+0.15,execute:poll); return }
   // A stale MenuBarAgent can acknowledge preference writes without applying
   // them. Refresh that exact system process once, only after observing a
   // mismatch, and never while dragging, opening a menu or tracking a popup.
   let popupOpen=self.externalMenuOpen
   if !refreshed,!self.wakeRecovery.isActive,!self.openingMenu,self.activeMenuBundle == nil,!self.ordering.isMoving,
      NSEvent.pressedMouseButtons == 0,!popupOpen,present.contains(own),
      self.lastMenuBarRefresh.map({ Date().timeIntervalSince($0)>=60 }) ?? true,
      let agent=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.MenuBarAgent").first,
      agent.bundleURL?.path == "/System/Library/CoreServices/MenuBarAgent.app",agent.processIdentifier>1 {
    refreshed=true; self.lastMenuBarRefresh=Date()
    guard kill(agent.processIdentifier,SIGTERM) == 0 else { completion(false); return }
    self.visibilityMessage="Refreshing the menu bar…"
    deadline=Date().addingTimeInterval(3)
    DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:poll)
   } else { completion(false) }
  }
  poll()
 }
 func pauseAfterVisibilityFailure() {
  // Sleep and permission loss are handled by their own automatic recovery.
  guard !suspended,controlAccessGranted else { restoreVisibility(); return }
  visibilityPaused=true // Set before restoration or queued transactions can run.
  restoreVisibility()
  visibilityMessage="SideTray paused after the menu bar did not update. Original icon settings are being restored. Choose Retry to try again."
  refreshSettingsUI()
 }
 func restoreVisibility() {
  #if SIDETRAY_UX_FIXTURE
  if let restore=fixtureRestoreVisibility { restore(); return }
  #endif
  STRestoreVisibility()
  guard useMenuSwitches else { return }
  // Serialize recovery after previously queued writes. The suspended/trust
  // guards prevent new writes while sleep or permission loss is being handled.
  visibilityQueue.async {
   do { try self.menuSwitches.restore() }
   catch {
    DispatchQueue.main.async {
     self.recoveryBlocked=true
     self.visibilityMessage=recoveryExplanation(error)
    }
   }
  }
 }
 func arrangeControl() {
  DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {
   guard !self.suspended,!self.openingMenu,self.activeMenuBundle == nil else { return }
   self.ordering.arrange(visible:self.placement.visible) { ok in
    if !ok { self.visibilityMessage="SideTray’s button could not be positioned. If the menu bar is full, uncheck an app above." }
    else if self.visibilityMessage.hasPrefix("SideTray’s button could not") { self.visibilityMessage="" }
   }
  }
 }
 @objc func openMenuDataPermissions() { openPrivacySettings("Privacy_AllFiles") }
 // Permission checks never display an alert or open another app.
 func probeSetupPermissions() {
  guard setupPending,!suspended,!terminating,!checkingPermissions,!setupReadiness.isActive else { return }
  checkingPermissions=true
  visibilityQueue.async {
   let access=self.menuSwitches.accessStatus()
   DispatchQueue.main.async {
    self.checkingPermissions=false
    guard self.setupPending,!self.suspended,!self.terminating else { return }
    self.menuDataAccess=access; self.menuDataReadable=access == .available
    self.advancePermissionSetup()
   }
  }
 }
 func advancePermissionSetup() {
  guard setupPending,!suspended,!terminating,!wakeRecovery.isActive else { return }
  let granted=controlAccessGranted && menuDataAccess == .available
  if granted != setupPermissionsWereReady {
   setupPermissionsWereReady=granted; setupReadiness.cancel()
  }
  if granted && isInstalled && setupReadiness.state == .idle { beginSetupReadiness() }
  refreshSettingsUI()
 }
 func beginSetupReadiness() {
  setupReadiness.start(attempt:{ [weak self] token,done in
   guard let self,self.setupReadiness.accepts(token),self.setupPending,!self.suspended,!self.terminating else { done(false); return }
   let checked:()->Void = { [weak self] in
    guard let self,self.setupReadiness.accepts(token) else { return }
    done(self.accessReady)
   }
   #if SIDETRAY_UX_FIXTURE
   if let check=self.fixtureReadinessCheck { check(checked); return }
   #endif
   self.checkMenuDataAccess(completion:{ DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:checked) })
  },finished:{ [weak self] ok in
   guard let self else { return }
   if ok { self.visibilityMessage="" }
   else if self.controlAccessGranted && self.menuDataAccess == .available {
    self.visibilityMessage="SideTray could not finish connecting to the menu bar. Your permissions are granted. Choose Retry."
   }
   self.refreshSettingsUI()
  })
  refreshSettingsUI()
 }
 // Returns true while access recovery owns resuming the saved layout.
 @discardableResult func updatePermissionRecovery() -> Bool {
  guard !wakeRecovery.isActive else { return false }
  let action=permissionRecovery.evaluate(setupPending:setupPending,installed:isInstalled,
   controlGranted:controlAccessGranted,dataPermissionMissing:menuDataAccess == .permissionRequired,ready:accessReady && !visibilityPaused && !wakeRecovery.isActive)
  switch action {
  case .present:
   showSettings(destination:"permissions")
  case .resume:
   placementBusy=true; refreshSettingsUI()
   resumeAfterPermissions { ok in
    self.placementBusy=false
    self.permissionRecovery.finished(success:ok)
    if ok {
     self.visibilityMessage=""
     #if SIDETRAY_UX_FIXTURE
     if self.fixtureResumeVisibility == nil { self.arrangeControl() }
     #else
     self.arrangeControl()
     #endif
    }
    self.refreshSettingsUI()
   }
  case .none: break
  }
  return action == .resume || permissionRecovery.isActive
 }
 private func resumeAfterPermissions(_ completion:@escaping(Bool)->Void) {
  #if SIDETRAY_UX_FIXTURE
  if let action=fixtureResumeVisibility { action(completion); return }
  #endif
  applyVisibility(completion:completion)
 }
 @objc func checkMenuDataAccess() { checkMenuDataAccess(completion:nil) }
 func checkMenuDataAccess(completion:(()->Void)?) {
  guard !checkingPermissions,!terminating else { completion?(); return }; checkingPermissions=true
  let recover = !startupRecoveryComplete || recoveryBlocked || visibilityPaused
  visibilityQueue.async {
   let access=self.menuSwitches.accessStatus()
   let available=access == .available
   var recoveryFailure:Error?
   if available && recover {
    do { try self.menuSwitches.restore() } catch { recoveryFailure=error }
   }
   DispatchQueue.main.async {
    self.checkingPermissions=false
    defer { completion?() }
    guard !self.terminating,!self.suspended else { return }
    self.menuDataAccess=access
    let changed=self.menuDataReadable != available
    self.menuDataReadable=available
    guard available else {
     if changed || self.permissionCheckRequested {
      self.visibilityMessage=access == .unsupported ? "This macOS version is not supported. SideTray will not change menu bar settings."
       : access == .permissionRequired
       ? (self.menuSwitches.hasRecoveryRecord ? "Restore Full Disk Access to recover your hidden icons." : "Full Disk Access is needed. Open Permissions to continue.")
       : "Menu bar settings could not be read. Choose Retry; changing permissions may not be necessary."
     }
     self.permissionCheckRequested=false
     self.updatePermissionRecovery()
     self.refreshSettingsUI()
     return
    }
    if let recoveryFailure {
     self.recoveryBlocked=true
     self.visibilityMessage=recoveryExplanation(recoveryFailure)
     self.permissionCheckRequested=false
     self.refreshSettingsUI()
     if !self.wakeRecovery.isActive && !self.setupReadiness.isActive { self.showSettings(destination:"permissions") }
     return
    }
    self.startupRecoveryComplete=true; self.recoveryBlocked=false
    if self.recoveryWatcher?.isRunning != true {
     let watcher=Process(); watcher.executableURL=Bundle.main.executableURL
     watcher.arguments=["--watch-visibility",String(ProcessInfo.processInfo.processIdentifier)]
     watcher.standardOutput=FileHandle.nullDevice; watcher.standardError=FileHandle.nullDevice
     do { try watcher.run(); self.recoveryWatcher=watcher }
     catch { self.visibilityMessage="Menu bar recovery could not start. Choose Retry."; self.refreshSettingsUI(); return }
    }
    UserDefaults.standard.set(true,forKey:"useMenuSwitches")
    let requested=self.permissionCheckRequested; self.permissionCheckRequested=false
    if requested { self.visibilityPaused=false }
    if self.wakeRecovery.isActive { self.refreshSettingsUI(); return }
    if self.setupPending { self.visibilityMessage=""; self.refreshSettingsUI(); return }
    if self.updatePermissionRecovery() { self.refreshSettingsUI(); return }
    if changed || requested {
     self.applyVisibility { ok in
      if ok { self.visibilityMessage=""; self.arrangeControl() }
      self.refreshSettingsUI()
     }
    } else { self.refreshSettingsUI() }
   }
  }
 }
 @objc func recheckPermissions() {
  wakeRecovery.cancel()
  if setupPending { setupReadiness.cancel(); setupPermissionsWereReady=false; probeSetupPermissions(); return }
  #if SIDETRAY_UX_FIXTURE
  fixtureCheckPermissions?(); return
  #else
  permissionRecovery.retry(); permissionCheckRequested=true; checkMenuDataAccess(); refreshSettingsUI()
  #endif
 }
 @objc func finishSetup() {
  guard accessReady,!setupReadiness.isActive,!placementBusy else { showSettings(destination:"permissions"); return }
  // Completing onboarding is durable even if the first layout needs recovery.
  setupReadiness.cancel()
  setupPending=false; UserDefaults.standard.set(true,forKey:"setupComplete")
  placementBusy=true; refreshSettingsUI()
  let completed:(Bool)->Void = { ok in
   self.placementBusy=false
   if ok {
    self.visibilityMessage=""
    #if SIDETRAY_UX_FIXTURE
    if self.fixtureInitialLayout == nil { self.arrangeControl(); self.settings?.orderOut(nil); self.toggle() }
    #else
    self.arrangeControl(); self.settings?.orderOut(nil); self.toggle()
    #endif
   } else {
    self.visibilityPaused=true
    if self.visibilityMessage.isEmpty { self.visibilityMessage="Setup is complete, but the menu bar could not be updated. Your choices are saved. Choose Retry in Permissions." }
    self.showSettings(destination:"permissions")
   }
   self.refreshSettingsUI()
  }
  #if SIDETRAY_UX_FIXTURE
  if let action=fixtureInitialLayout { action(completed); return }
  #endif
  applyVisibility(completion:completed)
 }
 @objc func changeVisibility(_ sender:NSButton) {
  guard accessReady,!visibilityPaused,!wakeRecovery.isActive,!placementBusy,!openingMenu,listBundles.indices.contains(sender.tag) else { refreshSettingsUI(); return }
  let bundle=listBundles[sender.tag]
  placementBusy=true
  let previous=placement.visible
  var next=previous
  if sender.state == .on { next.insert(bundle) } else { next.remove(bundle) }
  placement.commit(next)
  if setupPending { placementBusy=false; refreshSettingsUI(); return }
  visibilityMessage="Updating app placement…"; refreshSettingsUI()
  applyVisibility { ok in
   self.placementBusy=false
   if !ok { self.placement.commit(previous) }
   else { self.visibilityMessage=""; self.arrangeControl() }
   self.refreshSettingsUI(); self.settingsUI?.restoreFocus(bundle)
  }
 }
 @objc func closeActiveMenu() {
  guard let bundle=activeMenuBundle else { return }
  visibilityMessage="Closing the app menu…"
  activation.close(bundle:bundle) {
   // The watcher verifies disappearance before hiding the source icon.
   DispatchQueue.main.asyncAfter(deadline:.now()+0.6) {
    if self.activeMenuBundle == bundle { self.visibilityMessage="The menu is still open. Try Escape or click outside." }
    else if self.visibilityMessage == "Closing the app menu…" { self.visibilityMessage="" }
   }
  }
 }
 func stopMenuWatch() { menuWatcher?.invalidate(); menuWatcher=nil; activeMenuBundle=nil }
 func watchMenu(_ bundle:String) {
  stopMenuWatch(); activeMenuBundle=bundle
  guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:bundle).first else { stopMenuWatch(); applyVisibility(); return }
  var surfaces=MenuSurfaceWatch(opened:activation.surfaceWindows)
  menuWatcher=Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { [weak self] _ in
   guard let self else { return }
   // Watch the actual surfaces opened by the click. A normal window opened
   // later (for example by selecting Settings) must not keep the icon revealed.
   if surfaces.isClosed(visible:MenuEvidence.windows(for:app.processIdentifier),mousePressed:NSEvent.pressedMouseButtons != 0) {
    self.stopMenuWatch()
    if self.visibilityMessage == "Closing the app menu…" || self.visibilityMessage == "The menu is still open. Try Escape or click outside." { self.visibilityMessage="" }
    self.applyVisibility { ok in if ok { self.arrangeControl() } }
   }
  }
 }
 func revealAndOpen(_ bundle:String) {
  openingMenu=true
  stopMenuWatch()
  panel.orderOut(nil)
  let start=Date()
  applyVisibility(reveal:bundle) { ok in
   guard ok else { self.openingMenu=false; self.showSettings(); return }
   self.activation.open(bundle:bundle,display:self.trayDisplay) { observed in
    guard !self.suspended else { self.openingMenu=false; return }
    UserDefaults.standard.set(Date().timeIntervalSince(start),forKey:"lastOpenDuration")
    if observed {
     self.openingMenu=false
     // Keep the actual source icon reachable for a second click while the
     // native menu is open. Rehide only after the menu closes.
     self.watchMenu(bundle)
    } else {
     self.applyVisibility { restored in
      self.openingMenu=false
      if restored { self.showMenuFailure(bundle) }
      else { self.showSettings(destination:"permissions") }
     }
    }
   }
  }
 }
 @objc func removeFromTray(_ sender:NSMenuItem) {
  guard canManageVisibility,!openingMenu,!placementBusy,let bundle=sender.representedObject as? String else { return }
  panel.orderOut(nil)
  let previous=placement.visible; var next=previous; next.insert(bundle)
  placement.commit(next); placementBusy=true
  applyVisibility { ok in
   self.placementBusy=false
   if ok { self.visibilityMessage=""; self.arrangeControl() }
   else { self.placement.commit(previous); self.showSettings(destination:"permissions") }
   self.refreshSettingsUI()
  }
 }
 @objc func openSettingsAction() { showSettings() }
 func registerShortcut() {
  shortcutRegistered=shortcut.register(ShortcutChoice.load())
  UserDefaults.standard.set(shortcutRegistered,forKey:"shortcutRegistered")
  settingsUI?.updateShortcut()
 }
 @objc func checkUpdates() { showSettings(destination:"general"); updates.check() }
 func commandMenu() -> NSMenu {
  let menu=NSMenu()
  for (title,action,key) in [("Settings…",#selector(openSettingsAction),","),(updates.candidate == nil ? "Check for Updates…" : "Update Ready…",#selector(checkUpdates),""),("About SideTray",#selector(openAbout),"")] {
   let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; menu.addItem(item)
  }
  menu.addItem(.separator())
  menu.addItem(withTitle:"Quit SideTray",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q").target=NSApp
  return menu
 }
 func installAppMenu() {
  let main=NSMenu(); let item=NSMenuItem(); item.submenu=commandMenu(); main.addItem(item); NSApp.mainMenu=main
 }
 func applicationDidBecomeActive(_ notification:Notification) {
  if setupPending { probeSetupPermissions() }
  else if !canManageVisibility || settings?.isVisible == true { checkMenuDataAccess() }
 }
 func handleSleep() {
  setupReadiness.cancel()
  suspended=true; wakeRecovery.cancel()
  stopMenuWatch(); panel?.orderOut(nil); activation.cancel(); ordering.cancel(); restoreVisibility()
 }
 func handleWake() {
  guard suspended else { return } // Duplicate wake notifications do not reset the budget.
  suspended=false
  guard !terminating,!setupPending,isInstalled else { return }
  visibilityMessage="Waiting for the menu bar after wake…"
  wakeRecovery.start(attempt:{ [weak self] token,done in
   self?.attemptWakeRecovery(token:token,completion:done)
  },finished:{ [weak self] ok in
   guard let self else { return }
   if ok {
    self.visibilityPaused=false; self.visibilityMessage=""
    if self.permissionRecovery.isActive { self.permissionRecovery.finished(success:true) }
    #if SIDETRAY_UX_FIXTURE
    if self.fixtureWakeAttempt == nil { self.arrangeControl() }
    #else
    self.arrangeControl()
    #endif
   } else if !self.controlAccessGranted || self.menuDataAccess == .permissionRequired {
    self.visibilityPaused=false; self.updatePermissionRecovery()
   } else {
    self.visibilityPaused=true
    self.visibilityMessage="SideTray could not restore the layout after waking and has stopped retrying. Use Retry to try again."
   }
   NSLog("SideTray wake recovery: %@ after %d attempts",ok ? "restored" : "stopped",self.wakeRecovery.attempts)
   self.refreshSettingsUI()
  })
  refreshSettingsUI()
 }
 var externalMenuOpen:Bool {
  (CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []).contains {
   $0[kCGWindowLayer as String] as? Int == 101 && $0[kCGWindowOwnerPID as String] as? Int != Int(ProcessInfo.processInfo.processIdentifier)
  }
 }
 func attemptWakeRecovery(token:Int,completion:@escaping(Bool)->Void) {
  guard wakeRecovery.accepts(token),!suspended,!terminating,!setupPending else { completion(false); return }
  guard !openingMenu,!placementBusy,!ordering.isMoving,activeMenuBundle == nil,NSEvent.pressedMouseButtons == 0 else { completion(false); return }
  #if SIDETRAY_UX_FIXTURE
  if let attempt=fixtureWakeAttempt { attempt(token,completion); return }
  #endif
  guard !checkingPermissions,!externalMenuOpen else { completion(false); return }
  // A missing own button means the menu service is not ready for a write yet.
  guard barSlots().contains(where:{ $0.bundle == Bundle.main.bundleIdentifier }) else { completion(false); return }
  // Re-probe protected settings and restart a stopped recovery helper before
  // applying anything. This does not request or reset OS permissions.
  checkMenuDataAccess(completion:{ [weak self] in
   guard let self,self.wakeRecovery.accepts(token),!self.suspended,!self.terminating else { completion(false); return }
   guard self.accessReady,!self.openingMenu,!self.placementBusy,!self.ordering.isMoving,
         self.activeMenuBundle == nil,NSEvent.pressedMouseButtons == 0,!self.externalMenuOpen else { completion(false); return }
   self.visibilityPaused=false; self.permissionRecovery.retry()
   self.applyVisibility(wakeToken:token,completion:completion)
  })
 }
 func installLifecycle() {
  func observe(_ center:NotificationCenter,_ name:Notification.Name,_ action:@escaping()->Void) {
   observers.append((center,center.addObserver(forName:name,object:nil,queue:.main) { _ in action() }))
  }
  let workspace=NSWorkspace.shared.notificationCenter
  for name in [NSWorkspace.didLaunchApplicationNotification,NSWorkspace.didTerminateApplicationNotification] {
   observe(workspace,name) { [weak self] in
    DispatchQueue.main.asyncAfter(deadline:.now()+0.3) {
     guard let self else { return }
     self.refreshSettingsUI()
     guard !self.openingMenu,!self.placementBusy,self.activeMenuBundle == nil else { return }; self.applyVisibility()
    }
   }
  }
  observe(workspace,NSWorkspace.didWakeNotification) { [weak self] in self?.handleWake() }
  observe(workspace,NSWorkspace.willSleepNotification) { [weak self] in self?.handleSleep() }
  observe(workspace,NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.panel.orderOut(nil) }
  observe(NotificationCenter.default,NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.panel.orderOut(nil); self?.trayDisplay=nil; self?.activation.cancel() }
  permissionTimer=Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in
   guard let self else { return }
   if let watcher=self.recoveryWatcher,!watcher.isRunning,!self.recoveryBlocked {
    self.recoveryBlocked=true; self.restoreVisibility()
    self.visibilityMessage="The recovery helper stopped. SideTray is restoring icons. Use Retry to restart it."
    self.refreshSettingsUI()
   }
   if self.setupPending {
    let control=self.controlAccessGranted
    if control != self.trusted { self.trusted=control; self.installGlobalMonitor() }
    self.probeSetupPermissions(); return
   }
   if !self.menuDataReadable && !self.recoveryBlocked && (self.setupPending || self.permissionRecovery.isActive || self.settings?.isVisible == true) { self.checkMenuDataAccess() }
   let next=self.controlAccessGranted
   if next != self.trusted {
    self.trusted=next
    self.installGlobalMonitor()
    if !next {
     self.stopMenuWatch(); self.activation.cancel(); self.ordering.cancel(); self.restoreVisibility(); self.panel.orderOut(nil)
     if self.settings?.isVisible == true { self.refreshSettingsUI() }
    } else if self.permissionRecovery.isActive {
     self.updatePermissionRecovery(); self.refreshSettingsUI()
    } else if self.canManageVisibility {
     self.applyVisibility { ok in
      if ok { self.visibilityMessage=""; self.arrangeControl() }
      if self.settings?.isVisible == true { self.refreshSettingsUI() }
     }
    } else { self.visibilityMessage=""; self.refreshSettingsUI() }
   }
   self.updatePermissionRecovery()
   self.advancePermissionSetup()
   // Applications can create their status item long after their launch event.
   // Reconcile actual menu items, not all running apps or helper processes.
   if self.canManageVisibility,!self.suspended,!self.openingMenu,!self.placementBusy,
      !self.discoveringApps,!self.ordering.isMoving,self.activeMenuBundle == nil {
    let slots=barSlots()
    let unexpected=slots.contains { !$0.bundle.hasPrefix("com.apple.") && $0.bundle != Bundle.main.bundleIdentifier && !self.placement.visible.contains($0.bundle) }
    if unexpected {
     self.rememberMenuApps(slots)
     self.discoveringApps=true
     self.applyVisibility { ok in
      self.discoveringApps=false
      if ok { self.arrangeControl() }
      if self.settings?.isVisible == true { self.refreshSettingsUI() }
     }
    }
   }
  }
 }
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { showSettings(); return true }
 @objc func openStrip() { toggle() }
 @objc func refreshSettings() { refreshSettingsUI() }
 @objc func openPermissions() {
  guard isInstalled else { showSettings(destination:"permissions"); return }
  openPrivacySettings("Privacy_Accessibility")
 }
 private func openPrivacySettings(_ pane:String) {
  #if SIDETRAY_UX_FIXTURE
  if let open=fixtureOpenSettings { open(pane); return }
  #endif
  #if !SIDETRAY_UX_FIXTURE || SIDETRAY_PERMISSION_JOURNEY
  if let url=URL(string:"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?"+pane) { NSWorkspace.shared.open(url) }
  #endif
 }
 @objc func showPermissionApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
 @objc func changeLogin(_ sender:NSButton) {
  do {
   if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
   if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
  } catch {
   let alert=NSAlert(); alert.messageText="Launch at login could not be changed"; alert.informativeText=error.localizedDescription; alert.runModal()
  }
  refreshSettingsUI()
 }
 func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
  guard !terminating else { return .terminateLater }
  terminating=true; suspended=true; wakeRecovery.cancel(); setupReadiness.cancel()
  stopMenuWatch(); panel?.orderOut(nil); activation.cancel(); ordering.cancel()
  visibilityQueue.async {
   var failure:Error?
   do { try self.menuSwitches.restore() } catch { failure=error }
   DispatchQueue.main.async {
    if let failure {
     self.recoveryBlocked=true
     self.visibilityMessage=recoveryExplanation(failure)
     if self.updates.installing {
      self.terminating=false; self.suspended=false
      sender.reply(toApplicationShouldTerminate:false)
      self.showSettings(destination:"permissions"); return
     }
     let alert=self.quitRecoveryAlert(failure)
     NSApp.activate(ignoringOtherApps:true)
     if alert.runModal() == .alertFirstButtonReturn {
      self.terminating=false; self.suspended=false
      sender.reply(toApplicationShouldTerminate:false)
      self.showSettings(destination:"permissions"); return
     }
    }
    if self.updates.installing,let watcher=self.recoveryWatcher,watcher.isRunning {
     watcher.terminate()
     self.visibilityQueue.async {
      let deadline=Date().addingTimeInterval(3)
      while watcher.isRunning && Date() < deadline { usleep(20_000) }
      DispatchQueue.main.async {
       if watcher.isRunning {
        self.terminating=false; self.suspended=false; self.recoveryBlocked=true
        self.visibilityMessage="The recovery helper is still stopping. Try the update again in a moment."
        sender.reply(toApplicationShouldTerminate:false)
       } else { sender.reply(toApplicationShouldTerminate:true) }
      }
     }
    } else { sender.reply(toApplicationShouldTerminate:true) }
   }
  }
  return .terminateLater
 }
 func quitRecoveryAlert(_ failure:Error) -> NSAlert {
  let alert=NSAlert(); alert.alertStyle = .warning
  alert.messageText="Some menu bar icons could not be restored"
  alert.informativeText=recoveryExplanation(failure)+" Quitting now may leave icons hidden until access is restored and SideTray is opened again."
  alert.addButton(withTitle:"Keep SideTray Open"); alert.addButton(withTitle:"Quit Anyway")
  return alert
 }
 func applicationWillTerminate(_ notification: Notification) { wakeRecovery.cancel(); setupReadiness.cancel(); suspended=true; stopMenuWatch(); permissionTimer?.invalidate();
  activation.cancel(); ordering.cancel(); shortcut.unregister(); for (center,token) in observers { center.removeObserver(token) }; STRestoreVisibility(); if let monitor { NSEvent.removeMonitor(monitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) } }
}
#if !SIDETRAY_UX_FIXTURE
@main struct SideTrayApp {
 static func main() {
  if let index=CommandLine.arguments.firstIndex(of:"--watch-visibility"),CommandLine.arguments.indices.contains(index+1),let pid=Int32(CommandLine.arguments[index+1]),pid>1 {
   exit(MenuSwitches.watchExit(of:pid) ? EXIT_SUCCESS : EXIT_FAILURE)
  }
  if CommandLine.arguments.contains("--diagnostics") {
   print("bundle=\(Bundle.main.bundleIdentifier ?? "unavailable")")
   print("trusted=\(AXIsProcessTrusted())")
   print("nativeBackend=\(NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.MenuBarAgent").isEmpty ? "unavailable" : "present")")
   return
  }
  let app=NSApplication.shared
  guard let ownership=SideTrayInstanceLock(directory:MenuSwitches.supportDirectory,wait:5) else {
   let alert=NSAlert(); alert.messageText="SideTray is already running or finishing recovery"
   alert.informativeText="Wait a moment, then open the installed copy again."; alert.runModal(); return
  }
  let controller=Controller()
  app.setActivationPolicy(.accessory); app.delegate=controller
  withExtendedLifetime(ownership) { app.run() }
 }
}

#endif

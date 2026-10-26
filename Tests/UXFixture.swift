import AppKit
import ApplicationServices
import Darwin

private struct FixtureFailure: Error { let message: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed", line: UInt = #line) throws {
 if !condition() { throw FixtureFailure(message: "line \(line): \(message)") }
}

private final class PermissionDragTarget:NSView {
 let result=NSTextField(labelWithString:"Drop the app icon here")
 override init(frame:NSRect) {
  super.init(frame:frame); registerForDraggedTypes([.fileURL])
  wantsLayer=true; layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor
  result.frame=NSRect(x:12,y:45,width:280,height:24); addSubview(result)
 }
 required init?(coder:NSCoder) { fatalError("init(coder:) is unused") }
 override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { .copy }
 override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
  let urls=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]
  let valid=urls == [Bundle.main.bundleURL]
  result.stringValue=valid ? "PASS: exact current app URL received" : "FAIL: incorrect drag payload"
  return valid
 }
}

// Isolated bundle/preferences; never starts Controller's lifecycle, status item,
// permission requests, recovery watcher or native visibility mutations.
final class UXFixture:NSObject {
 let owner=Controller()
 var controls:NSWindow!
 var dragWindow:NSWindow?
 override init() {
  super.init()
  owner.setupPending=true
  owner.panel=TrayPanel(contentRect:NSRect(x:850,y:650,width:330,height:33),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  controls=NSWindow(contentRect:NSRect(x:100,y:200,width:240,height:260),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  controls.title="SideTray UX Test"
  let stack=NSStackView(); stack.orientation = .vertical; stack.spacing=12
  for (title,action) in [("Show Setup",#selector(setup)),("Show Access Recovery",#selector(accessRecovery)),("Show Failure",#selector(failure)),("Show Empty State",#selector(empty)),("Show Overflow",#selector(overflow)),("Test Permission Drag",#selector(testPermissionDrag)),("Quit Fixture",#selector(quit))] {
   stack.addArrangedSubview(NSButton(title:title,target:self,action:action))
  }
  stack.frame=NSRect(x:10,y:10,width:220,height:240); controls.contentView=stack
 }
 @objc func testPermissionDrag() {
  let window=NSWindow(contentRect:NSRect(x:100,y:200,width:500,height:180),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  window.title="SideTray Permission Drag Test"; window.isReleasedWhenClosed=false
  let icon=PermissionAppIcon(frame:NSRect(x:30,y:60,width:64,height:64))
  icon.image=NSWorkspace.shared.icon(forFile:Bundle.main.bundlePath); icon.imageScaling = .scaleProportionallyDown
  window.contentView?.addSubview(icon)
  window.contentView?.addSubview(PermissionDragTarget(frame:NSRect(x:155,y:30,width:320,height:120)))
  dragWindow=window; window.makeKeyAndOrderFront(nil)
 }
 @objc func setup() { owner.setupPending=true; owner.permissionRecovery=PermissionRecovery(); owner.fixtureInstalled=true; owner.fixtureControlAccess=false; owner.controlRequestSent=false; owner.menuDataAccess = .permissionRequired; owner.showSettings(destination:"permissions") }
 @objc func accessRecovery() {
  owner.setupPending=false; owner.fixtureInstalled=true; owner.fixtureControlAccess=false
  owner.menuDataReadable=false; owner.menuDataAccess = .permissionRequired
  owner.permissionRecovery=PermissionRecovery()
  owner.updatePermissionRecovery()
 }
 @objc func failure() { owner.showMenuFailure("test.example") }
 @objc func empty() {
  owner.current=[]; owner.renderTray(frame:NSRect(x:850,y:650,width:330,height:33))
 }
 @objc func overflow() {
  let sample=Entry(app:NSRunningApplication.current,element:AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier),frame:nil)
  owner.current=Array(repeating:sample,count:30)
  owner.renderTray(frame:NSRect(x:850,y:650,width:330,height:33))
  // Sample icons exercise layout only; do not invoke native menus or placement.
  for button in owner.panel.keyboardItems { button.target=nil; button.action=nil; button.menu=nil }
 }
 @objc func quit() { NSApp.terminate(nil) }
 func selfTest() throws {
  let first=TrayShortcut(), second=TrayShortcut()
  defer { first.unregister(); second.unregister(); owner.settings?.orderOut(nil); owner.panel.orderOut(nil) }
  let choice=ShortcutChoice(keyCode:40,modifiers:ShortcutChoice.command|ShortcutChoice.control|ShortcutChoice.shift)
  try check(first.register(choice),"Test combination already occupied")
  try check(!second.register(choice)); try check(second.error != nil)
  first.unregister()
  try check(second.register(choice)); try check(second.error == nil)
  try check(!second.register(nil)); try check(second.error == nil)
  owner.showSettings(destination:"general")
  let original=owner.settings?.contentView
  owner.showSettings(destination:"permissions")
  try check(owner.settingsTab == "permissions")
  owner.refreshSettingsUI()
  try check(owner.settings?.contentView === original)
  func views(_ root:NSView) -> [NSView] { [root]+root.subviews.flatMap { views($0) } }
  func visibleText() -> String {
   views(owner.settings!.contentView!).compactMap { view in
    guard let field=view as? NSTextField,!field.isHiddenOrHasHiddenAncestor else { return nil }
    return field.stringValue
   }.joined(separator:"\n")
  }
  owner.fixtureInstalled=true; owner.fixtureControlAccess=true; owner.fixtureHelperRunning=true
  owner.setupPending=false; owner.menuDataReadable=true; owner.menuDataAccess = .available; owner.startupRecoveryComplete=true
  var restorations=0
  owner.fixtureRestoreVisibility={ restorations += 1 }
  owner.pauseAfterVisibilityFailure()
  try check(restorations == 1 && !owner.canManageVisibility,"Failed visibility must restore once and disable automatic management")
  var rejected=0
  for _ in 0..<20 { owner.applyVisibility { ok in if !ok { rejected += 1 } } }
  owner.updatePermissionRecovery(); owner.refreshSettingsUI()
  try check(rejected == 20 && restorations == 1 && owner.visibilityPaused,"Queued/discovery attempts must not restart a failed layout")
  try check(visibleText().contains("Menu bar management paused") && !visibleText().contains("SideTray is ready"),"Paused UI must not claim readiness or missing permission")
  owner.visibilityPaused=false; owner.fixtureControlAccess=false
  owner.pauseAfterVisibilityFailure()
  try check(!owner.visibilityPaused && restorations == 2,"Permission loss must retain its own automatic recovery")
  owner.fixtureControlAccess=true; owner.suspended=true
  owner.pauseAfterVisibilityFailure()
  try check(!owner.visibilityPaused && restorations == 3,"Sleep must not latch a visibility failure")
  owner.suspended=false; owner.fixtureRestoreVisibility=nil; owner.menuDataReadable=false
  print("PASS: failed visibility restores once, blocks repeated attempts and shows accurate paused status")
  // Drive real lifecycle handlers with a fake clock; no sleep or native writes.
  var wakeTasks=[()->Void](), wakeDelays=[TimeInterval](), wakeAttempts=0
  owner.wakeRecovery=WakeRecovery(schedule:{ delay,work in wakeDelays.append(delay); wakeTasks.append(work) })
  owner.fixtureInstalled=true; owner.fixtureControlAccess=true; owner.fixtureHelperRunning=true
  owner.menuDataReadable=true; owner.menuDataAccess = .available; owner.setupPending=false
  owner.fixtureRestoreVisibility={ restorations += 1 }
  owner.fixtureWakeAttempt={ _,done in wakeAttempts += 1; self.owner.pauseAfterVisibilityFailure(); done(false) }
  owner.handleSleep(); owner.handleWake(); owner.handleWake()
  try check(wakeTasks.count == 1 && wakeAttempts == 0 && !owner.canManageVisibility,"Wake must settle and coalesce duplicate notifications")
  var ordinaryResult:Bool?
  owner.applyVisibility { ordinaryResult=$0 }
  try check(ordinaryResult == false,"App-change transactions must not bypass wake delays")
  owner.refreshSettingsUI()
  try check(visibleText().contains("Restoring your menu bar…"),"Wake UI must describe automatic recovery")
  wakeTasks.removeFirst()(); wakeTasks.removeFirst()(); wakeTasks.removeFirst()()
  try check(wakeAttempts == 3 && wakeTasks.isEmpty && owner.visibilityPaused && !owner.canManageVisibility,"Exhaustion must preserve the anti-flicker pause")
  try check(wakeDelays == [2,5,15])
  owner.fixtureWakeAttempt={ _,done in wakeAttempts += 1; done(true) }
  owner.handleSleep(); owner.handleWake(); wakeTasks.removeFirst()()
  try check(!owner.visibilityPaused && owner.canManageVisibility && wakeTasks.isEmpty,"A later wake must recover a previously paused layout")
  owner.handleSleep(); owner.handleWake(); owner.handleSleep(); wakeTasks.removeFirst()()
  try check(wakeAttempts == 4 && !owner.wakeRecovery.isActive,"Sleeping again cancels delayed writes")
  owner.handleWake(); owner.recheckPermissions(); wakeTasks.removeFirst()()
  try check(wakeAttempts == 4 && !owner.wakeRecovery.isActive,"Explicit retry cancels the wake scheduler")
  var heldWakeToken:Int?, heldWakeCompletion:((Bool)->Void)?
  owner.fixtureWakeAttempt={ token,done in heldWakeToken=token; heldWakeCompletion=done }
  owner.handleSleep(); owner.handleWake(); wakeTasks.removeFirst()()
  var releasePipeline:(()->Void)?, staleResult:Bool?
  owner.visibilityPipeline.submit { releasePipeline=$0 }
  owner.applyVisibility(wakeToken:heldWakeToken!) { staleResult=$0 }
  owner.handleSleep(); releasePipeline?(); heldWakeCompletion?(true)
  try check(staleResult == false && !owner.wakeRecovery.isActive && owner.suspended,"Queued work and completions from the previous wake must be ignored")
  owner.fixtureWakeAttempt=nil; owner.fixtureRestoreVisibility=nil
  owner.wakeRecovery=WakeRecovery(); owner.visibilityPaused=false; owner.suspended=false; owner.menuDataReadable=false
  print("PASS: controller wake delay, blocked competing updates, bounded failure, next-cycle recovery, sleep/manual cancellation and recovery UI")
  owner.fixtureInstalled=true; owner.fixtureControlAccess=false
  owner.setupPending=true; owner.menuDataAccess = .permissionRequired
  owner.refreshSettingsUI()
  try check(visibleText().contains("Set Up SideTray") && !visibleText().contains("again"),"First setup must never imply previous approval")
  let accessButtons=views(owner.settings!.contentView!).compactMap { $0 as? NSButton }.filter { $0.title == "Request Access…" }
  try check(accessButtons.count == 2,"Both missing permissions must use Request Access")
  var requests=0; var openedPanes:[String]=[]
  owner.fixtureRequestControl={ requests += 1 }
  owner.fixtureOpenSettings={ openedPanes.append($0) }
  owner.openPermissions()
  try check(requests == 1 && openedPanes.isEmpty,"First click requests natively without racing Settings")
  owner.openPermissions()
  try check(requests == 1 && openedPanes == ["Privacy_Accessibility"],"Second click provides Settings fallback without another alert")
  owner.fixtureControlAccess=true; owner.controlRequestSent=false
  owner.openPermissions()
  try check(requests == 1,"Working grants must not request again")
  owner.openMenuDataPermissions()
  try check(openedPanes.last == "Privacy_AllFiles")
  requests=0; openedPanes=[]; owner.controlRequestSent=false; owner.dataSetupOpened=false
  owner.fixtureControlAccess=false; owner.showSettings(destination:"permissions")
  owner.advancePermissionSetup(); owner.advancePermissionSetup()
  try check(requests == 1 && openedPanes.isEmpty,"Setup must request Device Control automatically once, without racing Settings")
  owner.fixtureControlAccess=true
  owner.advancePermissionSetup(); owner.advancePermissionSetup()
  try check(openedPanes == ["Privacy_AllFiles"],"Advance to Full Disk Access once after control approval")
  owner.dataSetupOpened=false; owner.showSettings(destination:"general")
  owner.advancePermissionSetup()
  try check(openedPanes.count == 1,"Never steal focus from Updates")
  owner.showSettings(destination:"permissions"); owner.settings?.orderOut(nil)
  owner.advancePermissionSetup()
  try check(openedPanes.count == 1,"Never reopen Settings after setup is dismissed")
  owner.fixtureInstalled=false; owner.showSettings(destination:"permissions")
  owner.advancePermissionSetup()
  try check(openedPanes.count == 1,"Do not request access for an uninstalled copy")
  owner.fixtureInstalled=true; owner.menuDataAccess = .available; owner.menuDataReadable=true
  owner.advancePermissionSetup()
  try check(openedPanes.count == 1,"Do not request working Full Disk Access")
  let dragIcon=views(owner.settings!.contentView!).compactMap { $0 as? PermissionAppIcon }.first
  try check(dragIcon?.appURL == Bundle.main.bundleURL,"Drag must identify the current app, not another copy")
  print("PASS: automatic sequential permission setup, no repeated prompts, update/dismissal guards and exact dragged bundle")
  owner.fixtureRequestControl=nil; owner.fixtureOpenSettings=nil; owner.controlRequestSent=false
  // Production controller/presentation with injected access and resume results.
  // No permission requests, preferences writes, helpers or native icon changes.
  owner.setupPending=false; owner.fixtureInstalled=true; owner.fixtureControlAccess=true
  owner.fixtureHelperRunning=true; owner.startupRecoveryComplete=true
  owner.menuDataAccess = .permissionRequired; owner.menuDataReadable=false
  let choices=owner.placement.visible
  try check(owner.updatePermissionRecovery())
  try check(owner.settingsTab == "permissions" && owner.settings!.isVisible)
  try check(!owner.settingsUI!.navigation.isHidden && !owner.settingsUI!.navigation.isEnabled(forSegment:0))
  try check(visibleText().contains("Restore access to SideTray"))
  // Exercise the exact menu target, not only direct Settings navigation.
  owner.checkUpdates()
  try check(owner.settingsTab == "general","Update Ready must reach General without permissions")
  owner.refreshSettingsUI(); owner.updatePermissionRecovery()
  try check(owner.settingsTab == "general","Polling must not redirect an update back to Permissions")
  try check(visibleText().contains("Updates"))
  try check(owner.settingsUI!.navigation.isEnabled(forSegment:1))
  owner.showSettings(destination:"apps")
  try check(owner.settingsTab == "permissions","Placement stays gated during recovery")

  let missingButtons=views(owner.settings!.contentView!).compactMap { $0 as? NSButton }.filter { $0.title == "Request Access…" && !$0.isHiddenOrHasHiddenAncestor }
  try check(missingButtons.count == 1,"Only the missing grant should offer an action")
  owner.menuDataAccess = .unavailable; owner.refreshSettingsUI()
  try check(visibleText().contains("Menu bar settings unavailable"))
  try check(!views(owner.settings!.contentView!).contains { view in
   guard let button=view as? NSButton else { return false }
   return button.title == "Request Access…" && !button.isHiddenOrHasHiddenAncestor
  },"Unknown access failures must not request new grants")
  owner.menuDataAccess = .permissionRequired
  owner.settings?.orderOut(nil)
  owner.updatePermissionRecovery()
  try check(owner.settings?.isVisible == false,"Polling must not steal focus again")
  var resumeCount=0; var finishResume:((Bool)->Void)?
  owner.fixtureResumeVisibility={ callback in resumeCount += 1; finishResume=callback }
  owner.menuDataAccess = .available; owner.menuDataReadable=true
  owner.updatePermissionRecovery(); owner.updatePermissionRecovery()
  try check(resumeCount == 1 && owner.permissionRecovery.state == .resuming)
  finishResume?(false)
  try check(owner.permissionRecovery.state == .needsAttention && !owner.canManageVisibility)
  owner.updatePermissionRecovery()
  try check(resumeCount == 1,"Failed resume must not loop")
  owner.permissionRecovery.retry(); owner.updatePermissionRecovery()
  try check(resumeCount == 2)
  finishResume?(true)
  try check(owner.permissionRecovery.state == .complete)
  try check(owner.placement.visible == choices,"Permission recovery must preserve choices")
  owner.showSettings(destination:"permissions")
  try check(visibleText().contains("Your saved app choices have been restored"))
  try check(!owner.settingsUI!.navigation.isHidden && owner.settingsUI!.navigation.isEnabled(forSegment:0))
  owner.permissionRecovery=PermissionRecovery()
  owner.fixtureInstalled=nil; owner.fixtureControlAccess=nil; owner.fixtureHelperRunning=nil; owner.fixtureResumeVisibility=nil
  owner.startupRecoveryComplete=false; owner.menuDataReadable=false
  owner.setupPending=false; owner.menuDataAccess = .unavailable
  owner.refreshSettingsUI()
  try check(visibleText().contains("Settings unavailable"))
  try check(visibleText().contains("does not establish that permission is missing"))
  owner.menuDataAccess = .available; owner.menuDataReadable=true
  owner.refreshSettingsUI()
  try check(visibleText().contains("✓ Full Disk Access"),"A missing helper must not be described as a missing permission")
  try check(visibleText().contains("recovery helper is not running"))
  try check(views(owner.settings!.contentView!).contains { ($0 as? NSImageView)?.image != nil },"Settings must show the bundled app icon")
  owner.menuDataReadable=false; owner.menuDataAccess = .permissionRequired
  owner.refreshSettingsUI()
  try check(visibleText().contains("Remove SideTray from the affected list"))
  owner.setupPending=true; owner.refreshSettingsUI()
  try check(visibleText().contains("Missing from the list? Drag this icon into Full Disk Access"))
  owner.setupPending=false; owner.menuDataAccess = .unsupported; owner.refreshSettingsUI()
  try check(visibleText().contains("macOS not supported"))
  owner.recoveryBlocked=true; owner.refreshSettingsUI()
  try check(visibleText().contains("Recovery needs attention"))
  var blockedResult:Bool?
  owner.applyVisibility { blockedResult=$0 }
  try check(blockedResult == false,"No hiding while startup recovery is incomplete")
  owner.startupRecoveryComplete=true; blockedResult=nil
  owner.applyVisibility { blockedResult=$0 }
  try check(blockedResult == false,"No hiding while recovery is blocked")
  let warning=owner.quitRecoveryAlert(MenuSwitchError.commandFailed)
  try check(warning.buttons.map(\.title) == ["Keep SideTray Open","Quit Anyway"],"Safe default for failed quit recovery")
  try check(warning.informativeText.contains("may leave icons hidden"))
  owner.settings?.orderOut(nil)
  overflow()
  let scroll=owner.panel.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
  let more=owner.panel.contentView!.subviews.compactMap { $0 as? NSButton }.first!
  try check(!scroll.hasHorizontalScroller && !scroll.hasVerticalScroller)
  try check(owner.panel.keyboardItems.count == 30)
  try check(scroll.frame.maxX <= more.frame.minX,"Overflow control must not cover the final app's click target")
  owner.scrollTrayForward()
  try check(scroll.contentView.bounds.minX>0,"More apps must advance the viewport")
  let maxX=scroll.documentView!.bounds.width-scroll.contentSize.width
  for _ in 0..<20 where scroll.contentView.bounds.minX<maxX-1 { owner.scrollTrayForward() }
  try check(abs(scroll.contentView.bounds.minX-maxX)<1)
  owner.scrollTrayForward()
  try check(scroll.contentView.bounds.minX == 0,"Paging past the end must wrap to the first app")
  let end=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:owner.panel.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:119)!
  try check(owner.panel.handleKey(end))
  let last=owner.panel.keyboardItems.last!
  try check(owner.panel.firstResponder === last)
  try check(scroll.documentVisibleRect.contains(last.frame),"Keyboard End must expose the whole last icon")
  empty()
  try check(owner.panel.keyboardItems.count == 1 && owner.panel.keyboardItems[0].title == "Manage Apps…")
  owner.panel.orderOut(nil)
  print("PASS: native request first, Settings fallback, working grants retained, and first-run copy")
  print("PASS: actual shortcut collision and recovery, Off clears error, explicit pane routing, stable Settings hierarchy")
  print("PASS: production empty/overflow views, no scrollbar, unobscured targets, forward paging and keyboard End")
  print("PASS: permission failures distinct from settings errors, helper failure distinct from grants, first-run and update recovery guidance, bundled Settings icon")
  print("PASS: automatic FDA-only recovery screen, missing-grant actions, no repeated focus, single resume and saved choices")
  print("PASS: startup/recovery write gates, unsupported-OS presentation and safe quit-warning default")
 }
}
@main struct UXMain {
 static func main() {
  let app=NSApplication.shared
  let fixture=UXFixture()
  do {
   if CommandLine.arguments.contains("--verify-failure-reporting") { try check(false,"Expected test-runner failure") }
   if CommandLine.arguments.contains("--self-test") { try fixture.selfTest(); return }
  } catch {
   let message=(error as? FixtureFailure)?.message ?? String(describing:error)
   FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
   exit(EXIT_FAILURE)
  }
  app.setActivationPolicy(.regular)
  fixture.controls.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
  withExtendedLifetime(fixture) { app.run() }
 }
}

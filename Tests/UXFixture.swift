import AppKit
import ApplicationServices
import Darwin

private struct FixtureFailure: Error { let message: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed", line: UInt = #line) throws {
 if !condition() { throw FixtureFailure(message: "line \(line): \(message)") }
}

// Isolated bundle/preferences; never starts Controller's lifecycle, status item,
// permission requests, recovery watcher or native visibility mutations.
final class UXFixture:NSObject {
 let owner=Controller()
 var controls:NSWindow!
 override init() {
  super.init()
  owner.setupPending=true
  owner.panel=TrayPanel(contentRect:NSRect(x:850,y:650,width:330,height:33),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  controls=NSWindow(contentRect:NSRect(x:100,y:200,width:240,height:220),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  controls.title="SideTray UX Test"
  let stack=NSStackView(); stack.orientation = .vertical; stack.spacing=12
  for (title,action) in [("Show Setup",#selector(setup)),("Show Failure",#selector(failure)),("Show Empty State",#selector(empty)),("Show Overflow",#selector(overflow)),("Quit Fixture",#selector(quit))] {
   stack.addArrangedSubview(NSButton(title:title,target:self,action:action))
  }
  stack.frame=NSRect(x:10,y:10,width:220,height:200); controls.contentView=stack
 }
 @objc func setup() { owner.showSettings(destination:"permissions") }
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
  try check(visibleText().contains("If it is missing, use +"))
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
  print("PASS: actual shortcut collision and recovery, Off clears error, explicit pane routing, stable Settings hierarchy")
  print("PASS: production empty/overflow views, no scrollbar, unobscured targets, forward paging and keyboard End")
  print("PASS: permission failures distinct from settings errors, helper failure distinct from grants, first-run and update recovery guidance, bundled Settings icon")
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

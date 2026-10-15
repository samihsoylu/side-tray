import AppKit

/// Manual integration fixture: creates its first status item six seconds after
/// launch, later than an ordinary application-launch notification handler.
final class Fixture:NSObject,NSApplicationDelegate {
 var item:NSStatusItem?
 func applicationDidFinishLaunching(_ notification:Notification) {
  DispatchQueue.main.asyncAfter(deadline:.now()+6) {
   let item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
   item.button?.title="ST Test"
   item.button?.setAccessibilityLabel("SideTray Test Fixture")
   let menu=NSMenu()
   let label=NSMenuItem(title:"Delayed menu test",action:nil,keyEquivalent:"")
   menu.addItem(label)
   let quit=NSMenuItem(title:"Quit Test Fixture",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"")
   quit.target=NSApp; menu.addItem(quit)
   item.menu=menu; self.item=item
  }
 }
}
let app=NSApplication.shared
let fixture=Fixture()
app.delegate=fixture
app.setActivationPolicy(.accessory)
app.run()

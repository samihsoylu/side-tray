import AppKit
// Isolated update integration app. No menu discovery, permission requests,
// hiding, recovery helper, login items or production preferences are loaded.
final class UpdateFixture:NSObject,NSApplicationDelegate {
 let updates=Updates()
 let status=NSTextField(wrappingLabelWithString:"")
 let install=NSButton(title:"Install and Relaunch",target:nil,action:nil)
 var window:NSWindow!
 func applicationDidFinishLaunching(_ notification:Notification) {
  let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as! String
  window=NSWindow(contentRect:NSRect(x:100,y:100,width:500,height:220),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  window.title="SideTray Update Test — Build \(version)"
  let check=NSButton(title:"Check for Updates",target:self,action:#selector(checkUpdate))
  install.target=self; install.action=#selector(installUpdate)
  let quit=NSButton(title:"Quit Test",target:NSApp,action:#selector(NSApplication.terminate(_:)))
  let stack=NSStackView(views:[NSTextField(labelWithString:"Isolated updater integration test"),status,check,install,quit]); stack.orientation = .vertical; stack.spacing=12
  stack.frame=NSRect(x:20,y:20,width:460,height:180); window.contentView?.addSubview(stack)
  updates.changed={ [weak self] in
   guard let self else { return }; self.status.stringValue=self.updates.message
   self.install.isEnabled=self.updates.candidate != nil && !self.updates.installing
   print("UPDATE_STATE: \(self.updates.message)"); fflush(stdout)
   if CommandLine.arguments.contains("--quit-when-ready"),self.updates.candidate != nil { NSApp.terminate(nil) }
   if CommandLine.arguments.contains("--quit-on-result"),!self.updates.busy,self.updates.message != "Updates are checked daily. Installation always waits for you." { NSApp.terminate(nil) }
  }
  updates.automatic=false; updates.start()
  window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
  print("FIXTURE_BUILD: \(version)"); fflush(stdout)
  if version == "1" { updates.check() }
 }
 @objc func checkUpdate() { updates.check() }
 @objc func installUpdate() { updates.install() }
}
@main struct TestApp {
 static func main() {
  let app=NSApplication.shared; let delegate=UpdateFixture()
  app.delegate=delegate; app.setActivationPolicy(.regular)
  withExtendedLifetime(delegate) { app.run() }
 }
}

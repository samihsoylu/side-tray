import AppKit
import ApplicationServices

// Opt-in real OS approval test. Uses production permission actions and Settings,
// but never starts menu management, the updater, login items, or a recovery helper.
final class PermissionJourney:NSObject {
 let owner=Controller()
 var timer:Timer?
 var checking=false
 func start() {
  owner.setupPending=true
  owner.fixtureInstalled=true; owner.fixtureHelperRunning=true
  owner.startupRecoveryComplete=true
  owner.fixtureResumeVisibility={ completion in completion(true) }
  owner.fixtureCheckPermissions={ [weak self] in self?.checkAccess() }
  owner.panel=TrayPanel(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
  owner.showSettings(destination:"permissions")
  // Choosing apps/starting the production manager is outside this approval test.
  owner.settingsUI?.nextForPermissionTestDisabled()
  checkAccess()
  timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.checkAccess() }
 }
 func checkAccess() {
  guard !checking else { return }; checking=true
  DispatchQueue.global().async {
   let result=self.owner.menuSwitches.accessStatus() // Read-only production FDA probe.
   DispatchQueue.main.async {
    self.checking=false
    self.owner.menuDataAccess=result; self.owner.menuDataReadable=result == .available
    self.owner.refreshSettingsUI()
    self.owner.settings?.title="SideTray Permission Test — Set Up SideTray"
    self.owner.settingsUI?.nextForPermissionTestDisabled()
    let evidence=["controlGranted":self.owner.controlAccessGranted,"dataGranted":self.owner.menuDataReadable]
    if let data=try? JSONSerialization.data(withJSONObject:evidence,options:.sortedKeys) {
     try? data.write(to:Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("permission-journey-status.json"),options:.atomic)
    }
   }
  }
 }
}
@main struct PermissionJourneyMain {
 static func main() {
  let app=NSApplication.shared; app.setActivationPolicy(.regular)
  let menu=NSMenu(); let entry=NSMenuItem(); menu.addItem(entry)
  let submenu=NSMenu(); submenu.addItem(withTitle:"Quit Permission Test",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); entry.submenu=submenu; app.mainMenu=menu
  let journey=PermissionJourney(); journey.start()
  withExtendedLifetime(journey) { app.run() }
 }
}

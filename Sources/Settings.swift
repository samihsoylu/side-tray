import AppKit
import ApplicationServices
import ServiceManagement

private final class AppListDocument:NSView { override var isFlipped:Bool { true } }

private func label(_ text:String,heading:Bool=false) -> NSTextField {
 let field=NSTextField(wrappingLabelWithString:text)
 field.font = .systemFont(ofSize:heading ? 14 : 13,weight:heading ? .semibold : .regular)
 if !heading { field.textColor = .secondaryLabelColor }
 return field
}
private func stack(_ views:[NSView],horizontal:Bool=false,spacing:CGFloat=12) -> NSStackView {
 let view=NSStackView(views:views); view.orientation=horizontal ? .horizontal : .vertical
 view.alignment=horizontal ? .centerY : .leading; view.spacing=spacing
 view.translatesAutoresizingMaskIntoConstraints=false
 return view
}
private func spacer() -> NSView { let view=NSView(); view.setContentHuggingPriority(.defaultLow,for:.horizontal); return view }

private final class AppRow {
 let view:NSStackView
 let check:NSButton
 let state=label("")
 let forget:NSButton
 var widthConstraint:NSLayoutConstraint?
 init(bundle:String,owner:Controller) {
  let icon=NSImageView(); icon.imageScaling = .scaleProportionallyDown; icon.setAccessibilityElement(false)
  icon.image=NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle).map { NSWorkspace.shared.icon(forFile:$0.path) }
  icon.translatesAutoresizingMaskIntoConstraints=false
  NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant:20),icon.heightAnchor.constraint(equalToConstant:20)])
  check=NSButton(checkboxWithTitle:owner.placement.names[bundle] ?? bundle,target:owner,action:#selector(Controller.changeVisibility(_:)))
  check.identifier=NSUserInterfaceItemIdentifier(bundle)
  check.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
  check.toolTip="Checked: visible in the menu bar. Unchecked: in SideTray."
  state.font = .systemFont(ofSize:11)
  forget=NSButton(title:"Forget",target:owner,action:#selector(Controller.forgetApp(_:)))
  forget.identifier=NSUserInterfaceItemIdentifier(bundle); forget.bezelStyle = .inline
  forget.setAccessibilityLabel("Forget \(check.title)")
  view=stack([icon,check,spacer(),state,forget],horizontal:true,spacing:8)
  view.edgeInsets=NSEdgeInsets(top:6,left:10,bottom:6,right:10)
 }
}

final class SettingsUI:NSObject {
 unowned let owner:Controller
 let window:NSWindow
 let tabs=NSTabView()
 let navigation=NSSegmentedControl(labels:["Apps","General","Permissions"],trackingMode:.selectOne,target:nil,action:nil)
 private let appRows=stack([],spacing:0)
 private var rows=[String:AppRow]()
 private var lastBundles=[String]()
 private let scroll=NSScrollView()
 private let appHelp=label("Choose which apps stay in the menu bar. Everything else appears in SideTray.")
 private let setupHelp=label("New apps are hidden by default. Check the apps you want to keep visible, then start SideTray.")
 private let empty=label("No menu bar apps found. Open one and it will appear here.")
 private let refresh=NSButton(title:"Refresh Apps",target:nil,action:nil)
 private let checkPermissions=NSButton(title:"Check Permissions",target:nil,action:nil)
 private let start=NSButton(title:"Start SideTray",target:nil,action:nil)
 let recorder=ShortcutRecorder()
 private let clear=NSButton(title:"Clear",target:nil,action:nil)
 private let shortcutHelp=label("")
 private let login=NSButton(checkboxWithTitle:"Launch at login",target:nil,action:nil)
 private let loginHelp=label("")
 private let updateStatus=label("")
 private let updateCheck=NSButton(title:"Check for Updates…",target:nil,action:nil)
 private let updateInstall=NSButton(title:"Install and Relaunch",target:nil,action:nil)
 private let updateCancel=NSButton(title:"Cancel Download",target:nil,action:nil)
 private let updateAutomatic=NSButton(checkboxWithTitle:"Automatically check and download updates",target:nil,action:nil)
 private let setupTitle=label("",heading:true)
 private let setupDescription=label("")
 private let controlHelp=label("")
 private let revealApp=NSButton(title:"Show App in Finder",target:nil,action:nil)
 private let controlState=label("",heading:true)
 private let dataState=label("",heading:true)
 private let controlOpen=NSButton(title:"Open System Settings…",target:nil,action:nil)
 private let dataOpen=NSButton(title:"Open System Settings…",target:nil,action:nil)
 private let dataHelp=label("")
 private let accessHelp=label("")
 private let permissionDetail=label("Full Disk Access grants broader access to protected files. SideTray uses it for menu bar visibility preferences and saves their original values for recovery. App icons come from the apps themselves; Screen Recording is not required.")
 private let details=NSButton(checkboxWithTitle:"Permission details",target:nil,action:nil)
 private let next=NSButton(title:"Choose Apps…",target:nil,action:nil)
 private let message=label("")
 private var selected="apps"

 init(owner:Controller) {
  self.owner=owner
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:480),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  super.init()
  window.title="SideTray Settings"; window.isReleasedWhenClosed=false; window.center()
  let root=NSView(); window.contentView=root
  navigation.target=self; navigation.action=#selector(selectPane); navigation.selectedSegment=0; navigation.segmentStyle = .texturedRounded
  tabs.tabViewType = .noTabsNoBorder; tabs.translatesAutoresizingMaskIntoConstraints=false
  func page(_ id:String,_ content:NSView) {
   let wrapper=NSView(); wrapper.addSubview(content); content.translatesAutoresizingMaskIntoConstraints=false
   NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:wrapper.leadingAnchor),content.trailingAnchor.constraint(equalTo:wrapper.trailingAnchor),content.topAnchor.constraint(equalTo:wrapper.topAnchor)])
   if id == "general" { content.bottomAnchor.constraint(lessThanOrEqualTo:wrapper.bottomAnchor).isActive=true }
   else { content.bottomAnchor.constraint(equalTo:wrapper.bottomAnchor).isActive=true }
   let item=NSTabViewItem(identifier:id); item.view=wrapper; tabs.addTabViewItem(item)
  }
  func column(_ views:[NSView]) -> NSStackView {
   let result=stack(views)
   for view in views where !(view is NSButton) { view.widthAnchor.constraint(equalTo:result.widthAnchor).isActive=true }
   return result
  }
  scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true; scroll.drawsBackground=false
  let document=AppListDocument(); document.translatesAutoresizingMaskIntoConstraints=false
  document.addSubview(appRows); scroll.documentView=document
  NSLayoutConstraint.activate([
   document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
   appRows.leadingAnchor.constraint(equalTo:document.leadingAnchor),appRows.trailingAnchor.constraint(equalTo:document.trailingAnchor),
   appRows.topAnchor.constraint(equalTo:document.topAnchor),appRows.bottomAnchor.constraint(equalTo:document.bottomAnchor)
  ])
  refresh.target=owner; refresh.action=#selector(Controller.refreshSettings)
  start.target=owner; start.action=#selector(Controller.finishSetup)
  let apps=column([label("Show in Menu Bar",heading:true),appHelp,setupHelp,scroll,empty,stack([spacer(),refresh,start],horizontal:true)])
  scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:185).isActive=true
  let fill=scroll.heightAnchor.constraint(equalTo:apps.heightAnchor,constant:-100); fill.priority = .defaultLow; fill.isActive=true
  page("apps",apps)

  recorder.began={ [weak owner,weak self] in owner?.shortcut.unregister(); self?.shortcutHelp.stringValue="Press your combination. Escape cancels." }
  recorder.validation={ [weak self] text in self?.shortcutHelp.stringValue=text }
  recorder.finished={ [weak owner,weak self] choice in
   if let choice { ShortcutChoice.save(choice) }
   owner?.registerShortcut(); self?.updateShortcut()
  }
  recorder.widthAnchor.constraint(equalToConstant:170).isActive=true
  clear.target=self; clear.action=#selector(clearShortcut); clear.bezelStyle = .inline
  login.target=owner; login.action=#selector(Controller.changeLogin(_:))
  updateCheck.target=self; updateCheck.action=#selector(checkUpdates)
  updateInstall.target=self; updateInstall.action=#selector(installUpdate)
  updateCancel.target=self; updateCancel.action=#selector(cancelUpdate)
  updateAutomatic.target=self; updateAutomatic.action=#selector(changeAutomaticUpdates)
  page("general",column([label("Keyboard Shortcut",heading:true),stack([NSTextField(labelWithString:"Open SideTray"),spacer(),recorder,clear],horizontal:true),shortcutHelp,NSBox.separator(),login,loginHelp,NSBox.separator(),label("Updates",heading:true),updateAutomatic,updateStatus,stack([spacer(),updateCancel,updateCheck,updateInstall],horizontal:true)]))

  controlOpen.target=owner; controlOpen.action=#selector(Controller.openPermissions)
  revealApp.target=owner; revealApp.action=#selector(Controller.showPermissionApp)
  dataOpen.target=owner; dataOpen.action=#selector(Controller.openMenuDataPermissions)
  details.target=self; details.action=#selector(toggleDetails); details.bezelStyle = .disclosure; details.setAccessibilityLabel("Permission details")
  next.target=self; next.action=#selector(chooseApps)
  checkPermissions.target=owner; checkPermissions.action=#selector(Controller.recheckPermissions)
  let permissions=column([setupTitle,setupDescription,stack([controlState,spacer(),controlOpen],horizontal:true),controlHelp,NSBox.separator(),stack([dataState,spacer(),dataOpen],horizontal:true),dataHelp,revealApp,accessHelp,details,permissionDetail,stack([next,spacer(),checkPermissions],horizontal:true)])
  let permissionScroll=NSScrollView(); permissionScroll.hasVerticalScroller=true; permissionScroll.autohidesScrollers=true; permissionScroll.drawsBackground=false
  let permissionDoc=AppListDocument(); permissionDoc.translatesAutoresizingMaskIntoConstraints=false
  permissionDoc.addSubview(permissions); permissionScroll.documentView=permissionDoc
  NSLayoutConstraint.activate([permissionDoc.widthAnchor.constraint(equalTo:permissionScroll.contentView.widthAnchor),permissions.leadingAnchor.constraint(equalTo:permissionDoc.leadingAnchor),permissions.trailingAnchor.constraint(equalTo:permissionDoc.trailingAnchor),permissions.topAnchor.constraint(equalTo:permissionDoc.topAnchor),permissions.bottomAnchor.constraint(equalTo:permissionDoc.bottomAnchor)])
  page("permissions",permissionScroll)

  let about=NSButton(image:NSImage(systemSymbolName:"info.circle",accessibilityDescription:"About SideTray")!,target:owner,action:#selector(Controller.openAbout)); about.isBordered=false; about.toolTip="About SideTray"; about.setAccessibilityLabel("About SideTray")
  let footer=stack([about,spacer()],horizontal:true)
  let appIcon=NSImageView(); appIcon.imageScaling = .scaleProportionallyDown
  if let url=Bundle.main.url(forResource:"SideTray",withExtension:"icns") { appIcon.image=NSImage(contentsOf:url) }
  appIcon.setAccessibilityElement(false)
  appIcon.translatesAutoresizingMaskIntoConstraints=false
  NSLayoutConstraint.activate([appIcon.widthAnchor.constraint(equalToConstant:28),appIcon.heightAnchor.constraint(equalToConstant:28)])
  let header=stack([appIcon,navigation,spacer()],horizontal:true)
  let body=column([header,tabs,message,footer]); root.addSubview(body)
  NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),body.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),body.topAnchor.constraint(equalTo:root.topAnchor,constant:18),body.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16)])
  tabs.setContentHuggingPriority(.defaultLow,for:.vertical)
  tabs.heightAnchor.constraint(greaterThanOrEqualToConstant:330).isActive=true
  message.setContentCompressionResistancePriority(.required,for:.vertical)
 }
 #if SIDETRAY_PERMISSION_JOURNEY
 func nextForPermissionTestDisabled() { next.isHidden=true; navigation.isHidden=true; start.isEnabled=false }
 #endif
 func select(_ requested:String?) {
  selected=SetupProgress.pane(requested:requested,remembered:selected)
  navigation.selectedSegment=["apps","general","permissions"].firstIndex(of:selected) ?? 0
  tabs.selectTabViewItem(withIdentifier:selected)
  owner.settingsTab=selected
  recorder.cancel()
 }
 @objc private func selectPane() { select(["apps","general","permissions"][navigation.selectedSegment]); update() }
 @objc private func chooseApps() { select("apps"); update() }
 @objc private func clearShortcut() { recorder.cancel(); ShortcutChoice.save(nil); owner.registerShortcut(); updateShortcut() }
 @objc private func toggleDetails() { update() }
 func restoreFocus(_ bundle:String) { if window.isKeyWindow,let row=rows[bundle] { window.makeFirstResponder(row.check) } }
 @objc private func checkUpdates() { owner.updates.check() }
 @objc private func installUpdate() { owner.updates.install() }
 @objc private func cancelUpdate() { owner.updates.cancelDownload() }
 @objc private func changeAutomaticUpdates() { owner.updates.automatic=updateAutomatic.state == .on }
 func updateUpdates() {
  let updater=owner.updates
  updateStatus.stringValue=updater.message
  updateAutomatic.state=updater.automatic ? .on : .off
  updateCheck.isHidden=updater.candidate != nil || updater.installing
  updateCheck.isEnabled = !updater.busy
  updateInstall.isHidden=updater.candidate == nil
  updateInstall.isEnabled = !updater.installing && !updater.busy
  updateCancel.isHidden = !updater.busy || !updater.message.hasPrefix("Downloading")
 }
 func updateMessage() { message.stringValue=owner.visibilityMessage; message.isHidden=owner.visibilityMessage.isEmpty }
 func updateShortcut() {
  guard !recorder.recording else { return }
  let choice=ShortcutChoice.load(); recorder.title=shortcutTitle(choice)
  clear.isEnabled=choice != nil
  shortcutHelp.stringValue=owner.shortcut.error ?? (choice == nil ? "Shortcut off. Click Record Shortcut to set one." : "Click the shortcut to change it. Escape closes the tray.")
 }
 func update() {
  updateMessage(); updateShortcut(); updateUpdates()
  login.state=SMAppService.mainApp.status == .enabled ? .on : .off
  loginHelp.stringValue=SMAppService.mainApp.status == .requiresApproval ? "Approve SideTray in macOS Login Items to finish enabling it." : "Start SideTray automatically when you sign in."
  let granted=owner.controlAccessGranted, dataReady=owner.menuDataReadable
  let needsPermission = !granted || owner.menuDataAccess == .permissionRequired
  let recovering = !owner.setupPending && owner.permissionRecovery.isActive
  // Recovery gates menu placement, not maintenance such as installing updates.
  navigation.isHidden=false
  navigation.setEnabled(!recovering,forSegment:0)
  if recovering && selected == "apps" { select("permissions") }
  window.title=owner.setupPending ? "Set Up SideTray" : recovering && selected == "permissions" ? "Restore access to SideTray" : "SideTray Settings"
  setupTitle.stringValue=owner.setupPending ? "Set Up SideTray" : (owner.accessReady ? "SideTray is ready" : needsPermission ? "Access needed" : "Connecting to menu bar settings")
  if owner.recoveryBlocked { setupTitle.stringValue="Recovery needs attention" }
  setupDescription.stringValue = !owner.isInstalled ? "Move SideTray to Applications and open it there to continue." : owner.setupPending ? "Allow these two permissions, then choose which apps stay visible. Your menu bar stays unchanged until you start SideTray." : "Restore the missing access below. Your app choices are saved."
  setupDescription.isHidden = !owner.setupPending && owner.accessReady
  controlState.stringValue=granted ? "✓ Device Control" : "1. Device Control"
  dataState.stringValue=dataReady ? "✓ Full Disk Access" : owner.menuDataAccess == .checking ? "Checking settings access…" : owner.menuDataAccess == .unavailable ? "Settings unavailable" : "2. Full Disk Access"
  if owner.menuDataAccess == .unsupported { dataState.stringValue="macOS not supported" }
  controlState.textColor=granted ? .secondaryLabelColor : .labelColor
  dataState.textColor=dataReady ? .secondaryLabelColor : .labelColor
  controlOpen.title = granted || owner.controlRequestSent ? "Open System Settings…" : "Request Access…"
  controlOpen.isEnabled=owner.isInstalled
  controlHelp.stringValue = !granted && owner.controlRequestSent
   ? "Approve SideTray in the macOS prompt. If no prompt appears, open System Settings and enable SideTray."
   : "Allow SideTray to find and open your apps’ menu bar items."
  revealApp.isHidden = dataReady || owner.menuDataAccess != .permissionRequired
  controlOpen.isHidden=recovering ? granted : granted && details.state != .on
  dataOpen.isHidden=recovering ? owner.menuDataAccess != .permissionRequired : dataReady && details.state != .on
  dataHelp.stringValue=dataReady ? "Menu bar visibility settings are connected." : owner.menuSwitches.hasRecoveryRecord ? "Allow Full Disk Access, then use Quit & Reopen. SideTray needs this access to restore your hidden icons." : "Required to hide icons. macOS grants broader file access; SideTray uses it for menu bar settings."
  if owner.menuDataAccess == .unavailable {
   dataHelp.stringValue="Menu bar settings could not be read. This can be a temporary error or an unsupported macOS format; it does not establish that permission is missing. Try Check Permissions again."
  } else if owner.menuDataAccess == .checking { dataHelp.stringValue="Checking access to macOS menu bar settings." }
  else if owner.menuDataAccess == .unsupported { dataHelp.stringValue="This build supports macOS 27. SideTray will not change menu bar settings on another major version. Install a compatible SideTray update." }
  if dataReady && !owner.recoveryHelperRunning { dataHelp.stringValue="Access is granted. The recovery helper is not running; use Check Permissions to retry." }
  accessHelp.isHidden = !needsPermission
  accessHelp.stringValue=owner.setupPending
   ? "If it is missing from Full Disk Access, use + to add SideTray from Applications. Choose Quit & Reopen if macOS asks."
   : "Already enabled? An updated beta may need a new grant. Remove SideTray from the affected list with −, then use + to add it from Applications. Quit and reopen SideTray. Your app choices are kept."
  if !needsPermission && !owner.accessReady { setupDescription.stringValue="Your app choices are saved. Check the status below before changing permissions." }
  if recovering {
   setupTitle.stringValue="Restore access to SideTray"
   setupDescription.isHidden=false
   setupDescription.stringValue="macOS needs you to approve SideTray again. Your app choices are saved and will resume when access is ready."
   accessHelp.stringValue="If SideTray is already enabled, remove it with − and add it from Applications with +. Choose Quit & Reopen if macOS asks."
   if owner.menuDataAccess == .permissionRequired && !owner.menuSwitches.hasRecoveryRecord {
    dataHelp.stringValue="Required to hide icons. macOS grants broader file access; SideTray uses it for menu bar settings."
   }
   if !needsPermission {
    let needsAttention=owner.permissionRecovery.state == .needsAttention || owner.recoveryBlocked || !owner.recoveryHelperRunning
    setupTitle.stringValue = !dataReady ? "Menu bar settings unavailable" : needsAttention ? "Your menu bar needs attention" : "Restoring your menu bar…"
    setupDescription.stringValue = !dataReady
     ? "Your app choices are saved. Check the settings status below, then try again."
     : needsAttention ? "Access is restored, but the saved layout could not be applied. Check the message below, then try again."
     : "Access is restored. SideTray is reconnecting and applying your saved app choices."
   }
  } else if !owner.setupPending && owner.permissionRecovery.state == .complete && owner.accessReady {
   setupDescription.isHidden=false
   setupDescription.stringValue="Your saved app choices have been restored. SideTray is ready to use."
  }
  permissionDetail.isHidden=details.state != .on
  next.isHidden = !owner.setupPending; next.isEnabled=owner.accessReady
  setupHelp.isHidden = !owner.setupPending
  appHelp.stringValue=owner.accessReady ? "Choose which apps stay in the menu bar. Everything else appears in SideTray." : "Finish the permissions in the Permissions tab to choose your apps."
  start.isHidden = !owner.setupPending; start.isEnabled=owner.accessReady && !owner.placementBusy
  refresh.isHidden=owner.setupPending; refresh.isEnabled = !owner.placementBusy
  checkPermissions.title=recovering ? "Check Again" : "Check Permissions"
  checkPermissions.isEnabled = !owner.checkingPermissions && owner.permissionRecovery.state != .resuming
  let entries=owner.availableEntries()
  for e in entries { if let bundle=e.app.bundleIdentifier { owner.placement.remember(e.app.localizedName ?? bundle,for:bundle) } }
  let bundles=Set(entries.compactMap { $0.app.bundleIdentifier }).union(owner.placement.names.keys).union(owner.placement.visible).filter { !$0.hasPrefix("com.apple.") && $0 != Bundle.main.bundleIdentifier }.sorted { (owner.placement.names[$0] ?? $0).localizedStandardCompare(owner.placement.names[$1] ?? $1) == .orderedAscending }
  owner.listBundles=bundles
  if bundles != lastBundles {
   let oldPosition=scroll.contentView.bounds.origin
   let focused=(window.firstResponder as? NSView)?.identifier
   for view in appRows.arrangedSubviews { appRows.removeArrangedSubview(view); view.removeFromSuperview() }
   rows=rows.filter { bundles.contains($0.key) }
   for bundle in bundles {
    let row=rows[bundle] ?? AppRow(bundle:bundle,owner:owner); rows[bundle]=row
    appRows.addArrangedSubview(row.view)
    if row.widthConstraint == nil { row.widthConstraint=row.view.widthAnchor.constraint(equalTo:appRows.widthAnchor) }
    row.widthConstraint?.isActive=true
   }
   lastBundles=bundles
   scroll.contentView.scroll(to:oldPosition); scroll.reflectScrolledClipView(scroll.contentView)
   if let focused,let row=rows[focused.rawValue] { window.makeFirstResponder(row.check) }
  }
  for (index,bundle) in bundles.enumerated() {
   guard let row=rows[bundle] else { continue }
   let running=NSRunningApplication.runningApplications(withBundleIdentifier:bundle).first != nil
   let installed=NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) != nil
   row.check.title=owner.placement.names[bundle] ?? bundle
   row.check.tag=index; row.check.state=owner.placement.visible.contains(bundle) ? .on : .off
   row.check.isEnabled=owner.accessReady && !owner.placementBusy && !owner.openingMenu
   row.state.stringValue=running ? "" : installed ? "Not running" : "Unavailable"
   row.forget.isHidden=running || installed; row.forget.isEnabled = !owner.placementBusy
  }
  empty.isHidden = !bundles.isEmpty
 }

}

private extension NSBox {
 static func separator() -> NSBox { let box=NSBox(); box.boxType = .separator; return box }
}

extension Controller {
 @objc func openAbout() {
  let paragraph=NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineSpacing=2
  let credits=NSMutableAttributedString(string:"Author\nSamih Soylu\nmail@samihsoylu.nl",attributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph])
  credits.addAttribute(.font,value:NSFont.systemFont(ofSize:15,weight:.semibold),range:NSRange(location:0,length:6))
  var options:[NSApplication.AboutPanelOptionKey:Any]=[
   .applicationName:"SideTray",
   .credits:credits
  ]
  if let url=Bundle.main.url(forResource:"SideTray",withExtension:"icns"),let image=NSImage(contentsOf:url) {
   options[.applicationIcon]=image
  }
  NSApp.activate(ignoringOtherApps:true)
  NSApp.orderFrontStandardAboutPanel(options:options)
 }
 func showSettings(destination:String?=nil) {
  panel.orderOut(nil)
  if settingsUI == nil { settingsUI=SettingsUI(owner:self); settings=settingsUI?.window }
  settingsUI?.select(destination ?? (permissionRecovery.isActive ? "permissions" : nil)); settingsUI?.update()
  settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
 }
 func refreshSettingsUI() { settingsUI?.update() }
 @objc func forgetApp(_ sender:NSButton) {
  guard !placementBusy,let bundle=sender.identifier?.rawValue,
    NSRunningApplication.runningApplications(withBundleIdentifier:bundle).isEmpty,
    NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) == nil else { return }
  placement.forget(bundle); refreshSettingsUI()
 }
}

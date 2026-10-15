import AppKit

/// A disposable native window for real macOS full-screen Space transitions.
/// No synthetic workspace notifications, menu items, user data or permissions.
final class SpaceFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
 var window: NSWindow!
 var observer: NSObjectProtocol?
 var timer: Timer?
 var armed = false
 var lastState = ""
 let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SideTray-SpaceFixture.jsonl")
 func trayPopups() -> [[String: Any]] {
  (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).filter {
   $0[kCGWindowOwnerName as String] as? String == "SideTray" && $0[kCGWindowLayer as String] as? Int == 101
  }.map { ["id": $0[kCGWindowNumber as String] ?? 0, "bounds": $0[kCGWindowBounds as String] ?? [:]] }
 }
 func record(_ event: String) {
  let popups = trayPopups()
  let state = "\(window.styleMask.contains(.fullScreen)):\(popups)"
  if event == "sample" && state == lastState { return }
  lastState = state
  let entry: [String: Any] = ["time": Date().timeIntervalSince1970, "event": event,
                            "fullScreen": window.styleMask.contains(.fullScreen), "trayPopups": popups]
  guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
        let file = try? FileHandle(forWritingTo: logURL) else { return }
  defer { try? file.close() }
  _ = try? file.seekToEnd(); try? file.write(contentsOf: data + Data([10]))
 }
 func applicationDidFinishLaunching(_ notification: Notification) {
  window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                    backing: .buffered, defer: false)
  window.title = "SideTray Space Test"
  window.delegate = self
  window.collectionBehavior = [.fullScreenPrimary]
  let message = NSTextField(labelWithString: "Temporary window for testing SideTray across a full-screen Space.")
  let toggle = NSButton(title: "Toggle Full Screen", target: self, action: #selector(toggleFullScreen))
  let delayed = NSButton(title: "Test Space in 12 Seconds", target: self, action: #selector(delayedTransition))
  let onTray = NSButton(title: "Test When Tray Opens", target: self, action: #selector(transitionWhenTrayOpens))
  let quit = NSButton(title: "Quit Test Window", target: NSApp, action: #selector(NSApplication.terminate(_:)))
  let stack = NSStackView(views: [message, toggle, delayed, onTray, quit])
  stack.orientation = .vertical; stack.spacing = 20
  stack.translatesAutoresizingMaskIntoConstraints = false
  let content = window.contentView!
  content.addSubview(stack)
  NSLayoutConstraint.activate([
   stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
   stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
  ])
  window.center(); window.makeKeyAndOrderFront(nil)
  NSApp.activate(ignoringOtherApps: true)
  try? Data().write(to: logURL, options: .atomic)
  observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.record("spaceChanged") }
  record("launched")
 }
 @objc func toggleFullScreen() { record("toggle"); window.toggleFullScreen(nil) }
 @objc func transitionWhenTrayOpens() {
  guard timer == nil, !window.styleMask.contains(.fullScreen) else { return }
  armed = true; record("armed")
  timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
   guard let self else { return }
   self.record("sample")
   guard self.armed, !self.trayPopups().isEmpty else { return }
   self.armed = false; self.record("trayDetected"); self.toggleFullScreen()
   DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
    if self.window.styleMask.contains(.fullScreen) { self.toggleFullScreen() }
   }
   DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
    self.record("finished"); self.timer?.invalidate(); self.timer = nil
   }
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
   if self.armed { self.armed = false; self.record("timedOut"); self.timer?.invalidate(); self.timer = nil }
  }
 }
 @objc func delayedTransition() {
  guard timer == nil, !window.styleMask.contains(.fullScreen) else { return }
  record("scheduled")
  timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.record("sample") }
  DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.toggleFullScreen() }
  DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
   if self.window.styleMask.contains(.fullScreen) { self.toggleFullScreen() }
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 24) {
   self.record("finished"); self.timer?.invalidate(); self.timer = nil
  }
 }
 func windowDidEnterFullScreen(_ notification: Notification) { record("enteredFullScreen") }
 func windowDidExitFullScreen(_ notification: Notification) { record("exitedFullScreen") }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let fixture = SpaceFixture()
app.setActivationPolicy(.regular)
app.delegate = fixture
app.run()

import Foundation
@main struct Tests {
 static func main() {
  let suite="SideTrayTests.\(UUID().uuidString)"
  let defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite) }
  // Old default-visible state must not accidentally opt newly found apps in.
  defaults.set(["io.tailscale.ipn.macsys"],forKey:"hiddenBundles")
  let store=PlacementStore(defaults:defaults)
  assert(store.visible.isEmpty)
  store.remember("Tailscale",for:"io.tailscale.ipn.macsys")
  store.commit(["io.tailscale.ipn.macsys","example.stopped"])
  let reopened=PlacementStore(defaults:defaults)
  assert(reopened.visible == ["io.tailscale.ipn.macsys","example.stopped"])
  assert(reopened.names["io.tailscale.ipn.macsys"] == "Tailscale")
  assert(!reopened.visible.contains("example.new"))
  var visible=reopened.visible; visible.remove("example.stopped"); reopened.commit(visible)
  assert(PlacementStore(defaults:defaults).visible == ["io.tailscale.ipn.macsys"])
  reopened.commit([])
  assert(PlacementStore(defaults:defaults,initiallyVisible:["app.tuple.app"]).visible.isEmpty)
  reopened.remember("Removed app",for:"example.removed")
  reopened.commit(["example.removed","example.stopped"])
  reopened.forget("example.removed")
  let afterForget=PlacementStore(defaults:defaults)
  assert(afterForget.names["example.removed"] == nil)
  assert(afterForget.visible == ["example.stopped"])
  afterForget.remember("Removed app",for:"example.removed")
  assert(!afterForget.visible.contains("example.removed"))
  assert(afterForget.names["app.tuple.app"] == nil)
  print("PASS: default hidden, saved show choices, relaunch, stopped choice, removal, empty state and policy migration")
 }
}

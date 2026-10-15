@main struct MenuSurfaceTests {
 static func main() {
  var watch=MenuSurfaceWatch(opened:[101])
  assert(!watch.isClosed(visible:[101],mousePressed:false))
  // A transient missing popup must not hide the icon underneath a menu.
  assert(!watch.isClosed(visible:[],mousePressed:false))
  assert(!watch.isClosed(visible:[],mousePressed:false))
  assert(!watch.isClosed(visible:[101,102],mousePressed:false))
  // Selecting Preferences may create a normal app window. It must not keep
  // the status icon revealed after the original menu has gone away.
  assert(!watch.isClosed(visible:[200],mousePressed:false))
  assert(!watch.isClosed(visible:[200],mousePressed:false))
  assert(watch.isClosed(visible:[200],mousePressed:false))
  // Wait for mouse-up before changing menu bar layout.
  var held=MenuSurfaceWatch(opened:[301,302])
  assert(!held.isClosed(visible:[302],mousePressed:false))
  for _ in 0..<4 { assert(!held.isClosed(visible:[],mousePressed:true)) }
  assert(held.isClosed(visible:[],mousePressed:false))
  print("PASS: menu redraw grace, opened surface identity, unrelated app windows, multiple surfaces and mouse-up safety")
 }
}

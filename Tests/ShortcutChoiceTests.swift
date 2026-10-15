import Foundation
@main struct Tests {
 static func main() {
  let suite="SideTrayUXTests.\(UUID().uuidString)"; let d=UserDefaults(suiteName:suite)!
  defer { d.removePersistentDomain(forName:suite) }
  assert(ShortcutChoice.load(from:d) == ShortcutChoice(keyCode:1,modifiers:2304))
  d.set(1,forKey:"shortcutChoice"); assert(ShortcutChoice.load(from:d)?.keyCode == 11)
  d.set(2,forKey:"shortcutChoice"); assert(ShortcutChoice.load(from:d) == nil)
  let custom=ShortcutChoice(keyCode:40,modifiers:ShortcutChoice.command|ShortcutChoice.shift)
  assert(custom.validationMessage == nil)
  ShortcutChoice.save(custom,to:d); assert(ShortcutChoice.load(from:d) == custom)
  d.set(0,forKey:"shortcutChoice"); assert(ShortcutChoice.load(from:d) == custom)
  ShortcutChoice.save(nil,to:d); assert(ShortcutChoice.load(from:d) == nil)
  assert(ShortcutChoice(keyCode:40,modifiers:0).validationMessage != nil)
  assert(ShortcutChoice(keyCode:12,modifiers:ShortcutChoice.command).validationMessage != nil)
  assert(ShortcutChoice(keyCode:40,modifiers:ShortcutChoice.control|ShortcutChoice.option).validationMessage != nil)
  assert(ShortcutChoice(keyCode:49,modifiers:2304).validationMessage != nil)
  assert(SetupProgress.needsSetup(d))
  d.set(true,forKey:"useMenuSwitches"); assert(SetupProgress.needsSetup(d)) // Interrupted setup stays pending.
  d.removeObject(forKey:"setupComplete"); assert(!SetupProgress.needsSetup(d)) // Existing installation migration.
  assert(SetupProgress.pane(requested:"permissions",remembered:"apps") == "permissions")
  assert(SetupProgress.pane(requested:nil,remembered:"general") == "general")
  print("PASS: shortcut migration, custom persistence, clear, reserved keys, setup continuation and explicit repair routing")
 }
}

import Foundation

struct ShortcutChoice: Codable, Equatable {
 var keyCode:UInt32
 var modifiers:UInt32
 static let command:UInt32=256, shift:UInt32=512, option:UInt32=2048, control:UInt32=4096
 static let supported:UInt32=command|shift|option|control
 static func load(from defaults:UserDefaults = .standard) -> ShortcutChoice? {
  if defaults.bool(forKey:"customShortcutSaved") {
   guard let data=defaults.data(forKey:"customShortcut") else { return nil }
   return try? JSONDecoder().decode(Self.self,from:data)
  }
  let old=defaults.integer(forKey:"shortcutChoice")
  return old == 2 ? nil : Self(keyCode:old == 1 ? 11 : 1,modifiers:command|option)
 }
 static func save(_ choice:Self?,to defaults:UserDefaults = .standard) {
  defaults.set(true,forKey:"customShortcutSaved")
  if let choice,let data=try? JSONEncoder().encode(choice) { defaults.set(data,forKey:"customShortcut") }
  else { defaults.removeObject(forKey:"customShortcut") }
 }
 var validationMessage:String? {
  guard modifiers & (Self.command|Self.control) != 0 else { return "Include Command or Control with another key." }
  guard modifiers & ~Self.supported == 0, keyCode<128 else { return "Choose another key combination." }
  if keyCode == 48 || keyCode == 53 || keyCode == 36 || keyCode == 49 || (54...63).contains(keyCode) {
   return "That key is reserved. Choose a letter, number or function key."
  }
  if modifiers == Self.command && [12,13,43,4,46,9,8,7,0,6].contains(keyCode) {
   return "That combination is a standard Mac command. Add another modifier or choose another key."
  }
  if modifiers & (Self.control|Self.option) == Self.control|Self.option {
   return "Control–Option is used by VoiceOver. Choose another combination."
  }
  return nil
 }
}

struct SetupProgress {
 static func needsSetup(_ defaults:UserDefaults = .standard) -> Bool {
  if defaults.object(forKey:"setupComplete") == nil {
   // Existing configured installations continue without a new setup interruption.
   defaults.set(defaults.bool(forKey:"useMenuSwitches"),forKey:"setupComplete")
  }
  return !defaults.bool(forKey:"setupComplete")
 }
 static func pane(requested:String?,remembered:String) -> String { requested ?? remembered }
}

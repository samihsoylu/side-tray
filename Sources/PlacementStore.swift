import Foundation

final class PlacementStore {
 private let defaults: UserDefaults
 private(set) var visible: Set<String>
 private(set) var names: [String:String]
 init(defaults: UserDefaults = .standard,initiallyVisible:Set<String> = []) {
  self.defaults=defaults
  if let saved=defaults.stringArray(forKey:"visibleBundles") { visible=Set(saved) }
  else {
   // The user changed the policy: former default-visible apps become hidden.
   // Retain only choices explicitly supplied for the new show-list.
   visible=initiallyVisible
   defaults.set(visible.sorted(),forKey:"visibleBundles")
  }
  names=defaults.dictionary(forKey:"knownApps") as? [String:String] ?? [:]
 }
 func remember(_ name:String,for bundle:String) {
  guard names[bundle] != name else { return }
  names[bundle]=name; defaults.set(names,forKey:"knownApps")
 }
 func forget(_ bundle:String) {
  names.removeValue(forKey:bundle); visible.remove(bundle)
  defaults.set(names,forKey:"knownApps"); defaults.set(visible.sorted(),forKey:"visibleBundles")
 }
 func commit(_ bundles:Set<String>) {
  visible=bundles; defaults.set(bundles.sorted(),forKey:"visibleBundles")
 }
}

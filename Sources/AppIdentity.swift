import AppKit
import Security

/// Some apps draw their status item from a separately signed helper executable.
/// Keep its signing identity alongside the owning application's bundle identity.
func menuSigningIdentifier(_ app:NSRunningApplication) -> String? {
 var code:SecCode?
 let attributes=[kSecGuestAttributePid as String:NSNumber(value:app.processIdentifier)] as CFDictionary
 guard SecCodeCopyGuestWithAttributes(nil,attributes,SecCSFlags(rawValue:0),&code) == errSecSuccess,let code else { return nil }
 var staticCode:SecStaticCode?
 guard SecCodeCopyStaticCode(code,SecCSFlags(rawValue:0),&staticCode) == errSecSuccess,let staticCode else { return nil }
 var information:CFDictionary?
 guard SecCodeCopySigningInformation(staticCode,SecCSFlags(rawValue:kSecCSSigningInformation),&information) == errSecSuccess else { return nil }
 return (information as? [String:Any])?[kSecCodeInfoIdentifier as String] as? String
}

/// Resolve only real enclosing app bundles, never infer ownership from ID prefixes.
func menuPreferenceAliases(_ apps:[NSRunningApplication]) -> [String:[String]] {
 var aliases=[String:[String]]()
 for app in apps {
  guard let id=app.bundleIdentifier,let url=app.bundleURL else { continue }
  var parents=[String](), cursor=url.deletingLastPathComponent()
  while cursor.path != "/" {
   if cursor.pathExtension == "app",let parent=Bundle(url:cursor)?.bundleIdentifier,parent != id { parents.append(parent) }
   cursor=cursor.deletingLastPathComponent()
  }
  if !parents.isEmpty { aliases[id]=parents }
 }
 return aliases
}

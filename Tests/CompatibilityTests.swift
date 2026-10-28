import Foundation

@main struct CompatibilityTests {
 static func main() throws {
  let policy=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"Compatibility.json"))) as! [String:Any]
  let supported=(10...40).filter { PlatformCompatibility.backend(for:$0) != nil }
  precondition(supported == policy["validatedMenuMajors"] as! [Int])
  precondition(supported == [27],"Do not enable untested backends")
  precondition(PlatformCompatibility.canUpdate(bundleURL:URL(fileURLWithPath:"/Applications/SideTray.app")))
  precondition(!PlatformCompatibility.canUpdate(bundleURL:URL(fileURLWithPath:"/Volumes/SideTray/SideTray.app")))
  precondition(!PlatformCompatibility.canUpdate(bundleURL:URL(fileURLWithPath:"/tmp/SideTray.app")))
  print("PASS: backend allowlist and update-location policy are independent")
 }
}

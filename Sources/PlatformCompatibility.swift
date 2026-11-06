import Foundation

/// Launch/update eligibility is separate from cross-app menu management.
/// macOS 26 is enabled for user testing; runtime schema/ownership checks still apply.
enum PlatformCompatibility {
 enum Backend:String {
  case controlCenter26 = "controlcenter26-v1"
  case controlCenter27 = "controlcenter27-v1"
 }
 static let journalSchema = "trackedApplications-isAllowed-v1"
 static func backend(for major:Int) -> Backend? {
  switch major { case 26: return .controlCenter26; case 27: return .controlCenter27; default: return nil }
 }
 static var currentBackend:Backend? { backend(for:ProcessInfo.processInfo.operatingSystemVersion.majorVersion) }
 static func canUpdate(bundleURL:URL) -> Bool { bundleURL.deletingLastPathComponent().path == "/Applications" }
 static let unsupportedMessage = "Menu bar management is not yet supported on this macOS version. Your app choices are saved. Check for a compatible update in General."
}

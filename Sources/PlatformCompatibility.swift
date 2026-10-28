import Foundation

/// Launch/update eligibility is separate from cross-app menu management.
/// A new OS needs a tested backend, not just a successful preference read.
enum PlatformCompatibility {
 enum Backend:String { case controlCenter27 = "controlcenter27-v1" }
 static let journalSchema = "trackedApplications-isAllowed-v1"
 static func backend(for major:Int) -> Backend? { major == 27 ? .controlCenter27 : nil }
 static var currentBackend:Backend? { backend(for:ProcessInfo.processInfo.operatingSystemVersion.majorVersion) }
 static func canUpdate(bundleURL:URL) -> Bool { bundleURL.deletingLastPathComponent().path == "/Applications" }
 static let unsupportedMessage = "Menu bar management is not yet supported on this macOS version. Your app choices are saved. Check for a compatible update in General."
}

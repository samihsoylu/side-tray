import Foundation
import CryptoKit

// A downloaded archive is inert until an explicit Install and Relaunch action.
struct UpdateCandidate:Equatable,Codable {
 let build:String
 let version:String
 let url:URL
 let length:UInt64
 let signature:Data
 static let maximumBytes:UInt64 = 100 * 1024 * 1024
 init(build:String,version:String,url:URL,length:UInt64,signature:String,repository:String) throws {
  let trustedURL:Bool
  #if SIDETRAY_UPDATE_FIXTURE
  trustedURL=url.scheme == "http" && url.host == "127.0.0.1" && url.port == 18743
  #else
  trustedURL=url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/\(repository)/releases/download/")
  #endif
  guard !build.isEmpty, build.allSatisfy({ $0.isNumber || $0 == "." }),
        trustedURL, url.user == nil, url.password == nil,
        url.query == nil, url.fragment == nil,
        url.pathExtension == "zip",
        length > 0, length <= Self.maximumBytes,
        let decoded=Data(base64Encoded:signature), decoded.count == 64 else { throw UpdateFailure.invalidRelease }
  self.build=build; self.version=version; self.url=url; self.length=length; self.signature=decoded
 }
 func verify(_ data:Data,publicKey:String) throws {
  guard data.count == length,let keyData=Data(base64Encoded:publicKey),
        let key=try? Curve25519.Signing.PublicKey(rawRepresentation:keyData),
        key.isValidSignature(signature,for:data) else { throw UpdateFailure.invalidSignature }
 }
}
enum UpdateFailure:Error,LocalizedError {
 case invalidRelease, invalidSignature, releaseChanged, unsupported, download
 var errorDescription:String? {
  switch self {
  case .invalidRelease: return "The release information could not be verified. Your installed app is unchanged."
  case .invalidSignature: return "The update failed its security check. Your installed app is unchanged."
  case .releaseChanged: return "The release changed. Check again to download and approve the new version."
  case .unsupported: return "Updates require the installed Applications copy on a supported macOS version."
  case .download: return "The update could not be downloaded. Check your connection and try again."
  }
 }
}

import Foundation
import CryptoKit
@main struct UpdatePolicyTests {
 static func main() throws {
  func expect(_ test:Bool,_ message:String) { if !test { fputs(message+"\n",stderr); exit(1) } }
  let key=Curve25519.Signing.PrivateKey(), data=Data("verified update bytes".utf8)
  let signature=try key.signature(for:data).base64EncodedString()
  let publicKey=key.publicKey.rawRepresentation.base64EncodedString()
  let url=URL(string:"https://github.com/samihsoylu/side-tray/releases/download/v0.2.1/SideTray.zip")!
  let candidate=try UpdateCandidate(build:"6",version:"0.2.1",url:url,length:UInt64(data.count),signature:signature,repository:"samihsoylu/side-tray")
  try candidate.verify(data,publicKey:publicKey)
  let disk=try UpdateCandidate(build:"11",version:"0.2.6",url:url.deletingPathExtension().appendingPathExtension("dmg"),length:UInt64(data.count),signature:signature,repository:"samihsoylu/side-tray")
  try disk.verify(data,publicKey:publicKey)
  expect(disk.cacheFilename == "update.dmg" && disk.contentType == "application/x-apple-diskimage","DMG cache type mismatch")
  expect(candidate.cacheFilename == "update.zip","Legacy ZIP cache compatibility lost")
  for ext in ["pkg","exe","html"] {
   do { _=try UpdateCandidate(build:"11",version:"0.2.6",url:url.deletingPathExtension().appendingPathExtension(ext),length:UInt64(data.count),signature:signature,repository:"samihsoylu/side-tray"); expect(false,"Accepted unsupported format") } catch {}
  }
  for bytes in [Data("tampered update bytes".utf8),Data(data.dropLast()),data+Data([0])] {
   do { try candidate.verify(bytes,publicKey:publicKey); expect(false,"Accepted tampered archive") } catch {}
  }
  do { try candidate.verify(data,publicKey:Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()); expect(false,"Accepted wrong key") } catch {}
  for link in ["http://github.com/samihsoylu/side-tray/releases/download/v6/a.zip","https://github.com/other/repo/releases/download/v6/a.zip","https://github.com.evil.example/samihsoylu/side-tray/releases/download/v6/a.zip","https://user:password@github.com/samihsoylu/side-tray/releases/download/v6/a.zip","https://github.com/samihsoylu/side-tray/releases/download/v6/a.pkg"] {
   do { _=try UpdateCandidate(build:"6",version:"0.2.1",url:URL(string:link)!,length:UInt64(data.count),signature:signature,repository:"samihsoylu/side-tray"); expect(false,"Accepted foreign/insecure release URL") } catch {}
  }
  for length:UInt64 in [0,UpdateCandidate.maximumBytes+1] {
   do { _=try UpdateCandidate(build:"6",version:"0.2.1",url:url,length:length,signature:signature,repository:"samihsoylu/side-tray"); expect(false,"Accepted invalid download length") } catch {}
  }
  for sig in ["",Data(repeating:0,count:63).base64EncodedString()] {
   do { _=try UpdateCandidate(build:"6",version:"0.2.1",url:url,length:1,signature:sig,repository:"samihsoylu/side-tray"); expect(false,"Accepted invalid signature length") } catch {}
  }
  let base="https://raw.githubusercontent.com/example/app/main/appcast.xml?channel=beta&sidetray_check=old"
  let first=UpdateFeedRequest.url(base,token:"first")!, second=UpdateFeedRequest.url(base,token:"second")!
  expect(first != second,"Fresh checks reused a feed URL")
  let parts=URLComponents(string:first)!
  expect(parts.host == "raw.githubusercontent.com" && parts.path == "/example/app/main/appcast.xml","Changed feed destination")
  expect(parts.queryItems!.filter { $0.name == "sidetray_check" }.map(\.value) == ["first"],"Duplicated stale request token")
  expect(parts.queryItems!.contains(URLQueryItem(name:"channel",value:"beta")),"Removed existing feed parameters")
  print("Update policy tests passed")
 }
}

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
  print("Update policy tests passed")
 }
}

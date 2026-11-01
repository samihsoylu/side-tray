import Foundation

@main struct RecoveryDiagnosticsTests {
 static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("sidetray-diagnostics-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at:root) }
  let log=RecoveryDiagnostics(directory:root,limit:600)
  for number in 1...30 { log.record(.ownButtonMissing,attempt:number,token:2,metrics:[.slots:3]) }
  log.flush()
  let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
  precondition(files.count == 2,"History must rotate instead of growing indefinitely")
  for url in files {
   let data=try Data(contentsOf:url); precondition(data.count<=600)
   let permissions=try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as! NSNumber
   precondition(permissions.intValue == 0o600)
   for line in data.split(separator:10) {
    let row=try JSONSerialization.jsonObject(with:Data(line)) as! [String:Any]
    precondition(Set(row.keys) == Set(["time","event","attempt","cycle","pid","slots"]))
    precondition(row["event"] as? String == "ownButtonMissing" && row["cycle"] as? Int == 2)
   }
  }
  // A filesystem problem must not escape into app recovery.
  let blocked=root.appendingPathComponent("blocked"); try Data().write(to:blocked)
  let broken=RecoveryDiagnostics(directory:blocked); broken.record(.sleep); broken.flush()
  print("PASS: bounded diagnostics, cycle/reason fields, private files and harmless write failure")
 }
}

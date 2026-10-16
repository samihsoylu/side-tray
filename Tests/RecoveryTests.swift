import Foundation
import Darwin

struct TestFailure:Error { let message:String }
func check(_ condition:@autoclosure () throws -> Bool,_ message:String) throws {
 if try !condition() { throw TestFailure(message:message) }
}
func rejects(_ operation:() throws -> Void) throws {
 do { try operation() } catch { return }
 throw TestFailure(message:"Unsafe operation was accepted")
}
func domain(_ states:[String:Bool],extra:String="keep") throws -> Data {
 let rows:[Any]=states.keys.sorted().flatMap { id -> [Any] in
  [["bundle":["_0":id]],["isAllowed":states[id]!,"opaque":"keep"]]
 }
 return try encoded(rows,extra:extra)
}
func encoded(_ rows:[Any],extra:String="keep") throws -> Data {
 let inner=try PropertyListSerialization.data(fromPropertyList:rows,format:.binary,options:0)
 return try PropertyListSerialization.data(fromPropertyList:["trackedApplications":inner,"unrelated":extra],format:.binary,options:0)
}
final class FakeDomain {
 var data:Data
 var writes=0
 var reads=0
 var failRead=false
 var failAfterWrite=false
 var onRead:((FakeDomain)->Void)?
 init(_ states:[String:Bool]) throws { data=try domain(states) }
 func read() throws -> Data {
  if failRead { throw NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoPermissionError) }
  reads+=1; onRead?(self); return data
 }
 func write(_ value:Data) throws {
  writes+=1; data=value
  if failAfterWrite { throw MenuSwitchError.commandFailed }
 }
 func states() throws -> [String:Bool] { try MenuSwitchCodec.states(data) }
}
@main struct RecoveryTests {
 static func main() {
  do { try run(); print("PASS: strict schema, unsupported OS, journal recovery, write interruption, permission loss, conflict preservation, legacy journal and process ownership") }
  catch { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1) }
 }
 static func run() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("SideTray-Recovery-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at:root) }
  func store(_ fake:FakeDomain,_ name:String,major:Int=27) -> MenuSwitches {
   MenuSwitches(journalURL:root.appendingPathComponent(name+"/menu-visibility.json"),osMajor:major,readDomain:fake.read,writeDomain:fake.write)
  }
  let key:[String:Any]=["bundle":["_0":"app.a"]]
  for invalid:Any in ["true",1,0,NSNull()] {
   if invalid is NSNull { continue }
   let data=try encoded([key,["isAllowed":invalid]])
   try rejects { _=try MenuSwitchCodec.states(data) }
  }
  for rows:[Any] in [[key,[:]], [key,["isAllowed":true],key,["isAllowed":false]], [["bundle":"changed"],["isAllowed":true]], [key]] {
   let data=try encoded(rows); try rejects { _=try MenuSwitchCodec.states(data) }
  }
  let fake=try FakeDomain(["app.a":true,"app.b":false,"com.apple.system":true])
  let normal=store(fake,"normal")
  try normal.apply(["app.a":false,"app.b":true])
  try check(normal.hasRecoveryRecord,"Must journal before writes")
  try check(try fake.states() == ["app.a":false,"app.b":true,"com.apple.system":true],"Apply flags")
  try normal.restore()
  try check(try fake.states()["app.a"] == true,"Restore original")
  try check(!normal.hasRecoveryRecord,"Clear journal after verified restoration")
  try rejects { try normal.apply(["com.apple.system":false]) }
  try check(MenuSwitches.supports(major:27) && !MenuSwitches.supports(major:28),"OS compatibility gate")
  let unsupported=store(fake,"unsupported",major:28)
  try check(unsupported.accessStatus() == .unsupported,"Unsupported is not missing permission")
  let oldWrites=fake.writes
  try rejects { try unsupported.apply(["app.a":false]) }
  try check(fake.writes == oldWrites,"No unsupported OS writes")

  let helperDomain=try FakeDomain(["app.parent":true,"unrelated":true])
  let helperStore=store(helperDomain,"helper")
  let aliases=["app.parent.helper":["app.parent"]]
  try helperStore.applyVisible([],known:["app.parent.helper"],aliases:aliases)
  try check(try helperDomain.states()["app.parent"] == false,"Hide the helper through the registered parent")
  try helperStore.applyVisible(["app.parent.helper"],known:["app.parent.helper"],aliases:aliases)
  try check(try helperDomain.states()["app.parent"] == true,"Reveal helper through the same parent")
  try helperStore.applyVisible([],known:["app.parent.helper"],aliases:aliases)
  try helperStore.restore()
  try check(try helperDomain.states() == ["app.parent":true,"unrelated":true],"Restore parent and preserve unrelated records")

  let interrupted=store(fake,"interrupted")
  fake.failAfterWrite=true
  try rejects { try interrupted.apply(["app.a":false]) }
  try check(interrupted.hasRecoveryRecord,"Failure after import keeps recovery intent")
  fake.failAfterWrite=false
  let reopened=store(fake,"interrupted")
  fake.failRead=true
  try rejects { try reopened.restore() }
  try check(reopened.hasRecoveryRecord && reopened.recoveryIssue != nil,"Permission loss keeps recovery and explains it")
  fake.failRead=false
  try reopened.restore()
  try check(try fake.states()["app.a"] == true,"Recovery after access returns")
  try check(reopened.recoveryIssue == nil,"Clear recovered failure")
  try reopened.apply(["app.a":false])
  fake.failAfterWrite=true
  try rejects { try reopened.restore() }
  try check(reopened.hasRecoveryRecord,"Interrupted restoration keeps its journal")
  fake.failAfterWrite=false
  try store(fake,"interrupted").restore()
  try check(try fake.states()["app.a"] == true,"Repeat restoration is safe after a partial success")

  let conflict=store(fake,"conflict")
  let conflictWrites=fake.writes
  fake.reads=0
  fake.onRead={ model in
   if model.reads == 2 { model.data=try! domain(["app.a":true,"app.b":false,"com.apple.system":true],extra:"external edit") }
  }
  try rejects { try conflict.apply(["app.a":false]) }
  try check(fake.writes == conflictWrites && !conflict.hasRecoveryRecord,"Conflict must not import or retain unexecuted intent")
  fake.onRead=nil
  try conflict.apply(["app.a":false])
  let outer=try PropertyListSerialization.propertyList(from:fake.data,format:nil) as! [String:Any]
  try check(outer["unrelated"] as? String == "external edit","Retry preserves external metadata")
  // Another actor changed a managed value. Recovery must retain that choice.
  fake.data=try domain(["app.a":true,"app.b":false,"com.apple.system":true],extra:"external edit")
  let beforeRestore=fake.writes
  try conflict.restore()
  try check(fake.writes == beforeRestore,"Do not overwrite later user choice")

  let restoreConflict=store(fake,"restore-conflict")
  try restoreConflict.apply(["app.a":false])
  fake.reads=0
  fake.onRead={ model in
   if model.reads == 2 { model.data=try! domain(["app.a":false,"app.b":true,"com.apple.system":true],extra:"newer") }
  }
  try rejects { try restoreConflict.restore() }
  try check(restoreConflict.hasRecoveryRecord,"Keep journal after restoration conflict")
  fake.onRead=nil
  try restoreConflict.restore()
  try check(try fake.states()["app.b"] == true,"Preserve unrelated app's concurrent edit")

  let corrupt=store(fake,"corrupt")
  let corruptDir=root.appendingPathComponent("corrupt")
  try FileManager.default.createDirectory(at:corruptDir,withIntermediateDirectories:true)
  let journal=corruptDir.appendingPathComponent("menu-visibility.json")
  let bad=Data("{\"original\":{\"app.a\":true},\"written\":{}}".utf8)
  try bad.write(to:journal)
  let beforeBad=fake.writes
  try rejects { try corrupt.restore() }
  try check(fake.writes == beforeBad && (try Data(contentsOf:journal)) == bad,"Corrupt journal retained without writes")
  // Old beta journals omitted version. Keep them recoverable.
  try Data("{\"original\":{\"app.a\":true},\"written\":{\"app.a\":false}}".utf8).write(to:journal)
  fake.data=try domain(["app.a":false])
  try corrupt.restore()
  try check(try fake.states()["app.a"] == true,"Legacy journal recovery")
  // Deleted native rows stay deleted; never invent a replacement during recovery.
  try corrupt.apply(["app.a":false]); fake.data=try domain([:])
  try corrupt.restore(); try check(try fake.states().isEmpty,"Preserve deleted native row")

  let lockDir=root.appendingPathComponent("ownership")
  var owner=SideTrayInstanceLock(directory:lockDir)
  try check(owner != nil,"Acquire app ownership")
  try check(SideTrayInstanceLock(directory:lockDir) == nil,"Late helper/second app must not acquire ownership")
  let child=Process(); child.executableURL=URL(fileURLWithPath:"/bin/sleep"); child.arguments=["1"]
  try child.run()
  owner=nil
  try check(SideTrayInstanceLock(directory:lockDir) != nil,"A child process must not inherit app ownership")
  child.waitUntilExit()
 }
}

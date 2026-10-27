import Foundation
import Darwin
import CoreFoundation

enum MenuSwitchError:Error { case unexpectedFormat,commandFailed,concurrentChange,lockBusy,invalidJournal,unsupportedSystem }

func recoveryExplanation(_ error:Error) -> String {
 if MenuDataAccess.failure(error) == .permissionRequired { return "Restore Full Disk Access in Permissions, then try again." }
 switch error {
 case MenuSwitchError.unexpectedFormat, MenuSwitchError.unsupportedSystem:
  return "This macOS menu bar format is not supported. The recovery record has been kept; an app update is needed."
 case MenuSwitchError.invalidJournal:
  return "The recovery record could not be read safely. It has been kept for recovery; no new icons will be hidden."
 case MenuSwitchError.concurrentChange, MenuSwitchError.lockBusy:
  return "Menu bar settings are busy or changed elsewhere. Try again when other menu bar tools are idle."
 default: return "Menu bar settings could not be restored. The recovery record has been kept. Try again in Permissions."
 }
}

/// Both the app and its exit helper hold this while they own menu-bar state.
/// A late helper must never restore a newer running app's journal.
final class SideTrayInstanceLock {
 private let fd:Int32
 init?(directory:URL,wait:TimeInterval=0) {
  do { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) } catch { return nil }
  fd=open(directory.appendingPathComponent("instance.lock").path,O_CREAT|O_RDWR|O_CLOEXEC,0o600)
  guard fd>=0 else { return nil }
  let deadline=ProcessInfo.processInfo.systemUptime+wait
  while flock(fd,LOCK_EX|LOCK_NB) != 0 {
   guard errno == EWOULDBLOCK,ProcessInfo.processInfo.systemUptime<deadline else { Darwin.close(fd); return nil }
   Thread.sleep(forTimeInterval:0.05)
  }
 }
 deinit { flock(fd,LOCK_UN); Darwin.close(fd) }
}

enum MenuDataAccess:Equatable {
 case checking, available, permissionRequired, unavailable, unsupported
 static func failure(_ error:Error) -> MenuDataAccess {
  if case MenuSwitchError.unsupportedSystem=error { return .unsupported }
  let error=error as NSError
  if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return .permissionRequired }
  if error.domain == NSPOSIXErrorDomain && [Int(EACCES),Int(EPERM)].contains(error.code) { return .permissionRequired }
  if let underlying=error.userInfo[NSUnderlyingErrorKey] as? Error { return failure(underlying) }
  return .unavailable
 }
}

/// The macOS menu-bar switches are a binary plist embedded in another plist.
/// Change only requested app flags; retain unknown fields and other controls.
enum MenuSwitchCodec {
 static func rows(_ domain:Data) throws -> [Any] {
  guard domain.count <= 4*1024*1024,let outer=try PropertyListSerialization.propertyList(from:domain,format:nil) as? [String:Any],
        let data=outer["trackedApplications"] as? Data,
        let rows=try PropertyListSerialization.propertyList(from:data,format:nil) as? [Any],rows.count%2 == 0 else { throw MenuSwitchError.unexpectedFormat }
  var seen=Set<String>()
  for index in stride(from:0,to:rows.count,by:2) {
   guard let key=rows[index] as? [String:Any] else { throw MenuSwitchError.unexpectedFormat }
   // Preserve opaque non-app rows, but never guess a changed app schema.
   if key["bundle"] != nil {
    guard let id=bundle(key),!id.isEmpty,seen.insert(id).inserted,
          let value=rows[index+1] as? [String:Any],let flag=value["isAllowed"] as? NSNumber,
          CFGetTypeID(flag) == CFBooleanGetTypeID() else { throw MenuSwitchError.unexpectedFormat }
   }
  }
  return rows
 }
 static func bundle(_ key:Any) -> String? { ((key as? [String:Any])?["bundle"] as? [String:Any])?["_0"] as? String }
 static func states(_ domain:Data) throws -> [String:Bool] {
  let list=try rows(domain); var states=[String:Bool]()
  for index in stride(from:0,to:list.count,by:2) {
   if let id=bundle(list[index]),let value=list[index+1] as? [String:Any] { states[id]=value["isAllowed"] as? Bool }
  }
  return states
 }
 static func updatedValue(_ domain:Data,changes:[String:Bool]) throws -> Data {
  var list=try rows(domain); var remaining=changes
  for index in stride(from:0,to:list.count,by:2) {
   guard let id=bundle(list[index]),let state=remaining.removeValue(forKey:id),var value=list[index+1] as? [String:Any] else { continue }
   value["isAllowed"]=state; list[index+1]=value
  }
  // Only macOS creates native records. Do not invent a future schema.
  guard remaining.isEmpty else { throw MenuSwitchError.unexpectedFormat }
  return try PropertyListSerialization.data(fromPropertyList:list,format:.binary,options:0)
 }
 static func restoration(original:[String:Bool],written:[String:Bool],current:[String:Bool]) -> [String:Bool] {
  original.filter { id,_ in current[id] != nil && current[id] == written[id] }
 }
 // A helper can own the AX button while its enclosing app owns the native switch.
 // Exact records win. Shared owners remain visible if any selected helper needs them.
 static func visibilityChanges(states:[String:Bool],visible:Set<String>,known:Set<String>,aliases:[String:[String]]) -> [String:Bool] {
  var changes=[String:Bool]()
  for id in known.union(visible) where !id.hasPrefix("com.apple.") {
   guard let owner=([id]+(aliases[id] ?? [])).first(where:{ states[$0] != nil && !$0.hasPrefix("com.apple.") }) else { continue }
   changes[owner]=(changes[owner] ?? false) || visible.contains(id)
  }
  return changes
 }
 static func updatedDomain(_ domain:Data,changes:[String:Bool]) throws -> Data {
  guard var outer=try PropertyListSerialization.propertyList(from:domain,format:nil) as? [String:Any] else { throw MenuSwitchError.unexpectedFormat }
  outer["trackedApplications"]=try updatedValue(domain,changes:changes)
  return try PropertyListSerialization.data(fromPropertyList:outer,format:.binary,options:0)
 }
}

/// This path is protected by macOS. No fallback bypasses a denied read.
final class MenuSwitches {
 #if SIDETRAY_FIRST_RUN_TEST
 static let supportDirectory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!.appendingPathComponent("SideTray First Run Test")
 #else
 static let supportDirectory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!.appendingPathComponent("SideTray")
 #endif
 private let domain=NSHomeDirectory()+"/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter"
 private let journal:URL
 private let readOverride:(() throws -> Data)?
 private let writeOverride:((Data) throws -> Void)?
 private let osMajor:Int
 private var issueURL:URL { journal.deletingLastPathComponent().appendingPathComponent("recovery-error.txt") }
 private struct Journal:Codable {
  var version:Int?=1 // Missing means the previous beta's format.
  var original:[String:Bool]=[:]
  var written:[String:Bool]=[:]
 }
 init(journalURL:URL?=nil,osMajor:Int=ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
      readDomain:(() throws -> Data)?=nil,writeDomain:((Data) throws -> Void)?=nil) {
  journal=journalURL ?? Self.supportDirectory.appendingPathComponent("menu-visibility.json")
  self.osMajor=osMajor; readOverride=readDomain; writeOverride=writeDomain
 }
 static func supports(major:Int) -> Bool { major == 27 }
 private func checkCompatibility() throws {
  guard Self.supports(major:osMajor) else { throw MenuSwitchError.unsupportedSystem }
 }
 var recoveryIssue:String? { try? String(contentsOf:issueURL,encoding:.utf8) }
 private func recordFailure(_ error:Error) {
  let text=recoveryExplanation(error)
  do {
   try FileManager.default.createDirectory(at:issueURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
   try Data(text.utf8).write(to:issueURL,options:.atomic)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:issueURL.path)
  } catch { NSLog("SideTray could not save its recovery status.") }
  NSLog("SideTray recovery: %@",text)
 }
 private func command(_ arguments:[String]) throws -> Data {
  let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/defaults"); process.arguments=arguments
  let output=Pipe(); process.standardOutput=output; process.standardError=FileHandle.nullDevice
  let lock=NSLock(); var collected=Data(); let finished=DispatchSemaphore(value:0); let readFinished=DispatchSemaphore(value:0)
  process.terminationHandler={ _ in finished.signal() }
  try process.run()
  DispatchQueue.global(qos:.userInitiated).async {
   let data=output.fileHandleForReading.readDataToEndOfFile()
   lock.lock(); collected=data; lock.unlock(); readFinished.signal()
  }
  if finished.wait(timeout:.now()+3) == .timedOut {
   process.terminate()
   if finished.wait(timeout:.now()+1) == .timedOut { kill(process.processIdentifier,SIGKILL) }
   throw MenuSwitchError.commandFailed
  }
  guard readFinished.wait(timeout:.now()+1) == .success else { throw MenuSwitchError.commandFailed }
  lock.lock(); let result=collected; lock.unlock()
  guard process.terminationStatus == 0 else { throw MenuSwitchError.commandFailed }
  return result
 }
 private func read() throws -> Data {
  try checkCompatibility()
  let data=try readOverride?() ?? command(["export",domain,"-"])
  _ = try MenuSwitchCodec.states(data)
  return data
 }
 func accessStatus() -> MenuDataAccess {
  do {
   // Probe the same protected preferences file so a denied read can be
   // distinguished from a defaults timeout or an unsupported plist format.
   try checkCompatibility()
   if readOverride == nil { _ = try Data(contentsOf:URL(fileURLWithPath:domain+".plist")) }
   _ = try read()
   return .available
  } catch { return MenuDataAccess.failure(error) }
 }
 var hasRecoveryRecord:Bool { FileManager.default.fileExists(atPath:journal.path) }
 func applyVisible(_ visible:Set<String>,known:Set<String>,aliases:[String:[String]]=[:]) throws {
  let states=try MenuSwitchCodec.states(read())
  try apply(MenuSwitchCodec.visibilityChanges(states:states,visible:visible,known:known,aliases:aliases))
 }
 private func write(_ changes:[String:Bool],basedOn snapshot:Data) throws {
  let data=try MenuSwitchCodec.updatedDomain(snapshot,changes:changes)
  // macOS offers no compare-and-swap here. Detect intervening changes as late
  // as possible; preserve all unknown fields from the checked snapshot.
  func checkSnapshot() throws {
   let before=try PropertyListSerialization.propertyList(from:snapshot,format:nil) as! NSDictionary
   let latest=try PropertyListSerialization.propertyList(from:read(),format:nil) as! NSDictionary
   guard before.isEqual(latest) else { throw MenuSwitchError.concurrentChange }
  }
  if let writeOverride { try checkSnapshot(); try writeOverride(data); return }
  let file=journal.deletingLastPathComponent().appendingPathComponent("menu-import-\(UUID().uuidString).plist")
  defer { try? FileManager.default.removeItem(at:file) }
  try data.write(to:file)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
  try checkSnapshot()
  _ = try command(["import",domain,file.path])
 }
 private func locked<T>(_ work:() throws -> T) throws -> T {
  let directory=journal.deletingLastPathComponent()
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  let fd=open(directory.appendingPathComponent("visibility.lock").path,O_CREAT|O_RDWR|O_CLOEXEC,0o600)
  guard fd>=0 else { throw MenuSwitchError.commandFailed }
  defer { flock(fd,LOCK_UN); Darwin.close(fd) }
  let deadline=ProcessInfo.processInfo.systemUptime+3
  while flock(fd,LOCK_EX|LOCK_NB) != 0 {
   guard errno == EWOULDBLOCK,ProcessInfo.processInfo.systemUptime<deadline else { throw MenuSwitchError.lockBusy }
   Thread.sleep(forTimeInterval:0.02)
  }
  return try work()
 }
 private func loadJournal() throws -> Journal {
  if !FileManager.default.fileExists(atPath:journal.path) { return Journal() }
  do {
   let data=try Data(contentsOf:journal)
   guard data.count<=1024*1024 else { throw MenuSwitchError.invalidJournal }
   let record=try JSONDecoder().decode(Journal.self,from:data)
   guard record.version == nil || record.version == 1,
         Set(record.original.keys) == Set(record.written.keys),
         record.original.keys.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("com.apple.") }) else { throw MenuSwitchError.invalidJournal }
   return record
  } catch { throw MenuSwitchError.invalidJournal }
 }
 private func save(_ record:Journal) throws {
  try JSONEncoder().encode(record).write(to:journal,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:journal.path)
 }
 func apply(_ desired:[String:Bool]) throws {
  try locked {
   let data=try read(); let current=try MenuSwitchCodec.states(data)
   guard desired.keys.allSatisfy({ !$0.hasPrefix("com.apple.") && current[$0] != nil }) else { throw MenuSwitchError.unexpectedFormat }
   let changes=desired.filter { current[$0.key] != $0.value }
   guard !changes.isEmpty else { return }
   let previous=try loadJournal()
   var record=previous
   for (id,state) in changes {
    if record.original[id] == nil { record.original[id]=current[id] }
    record.written[id]=state
   }
   try save(record)
   do { try write(changes,basedOn:data) }
   catch MenuSwitchError.concurrentChange {
    // No import was attempted, so discard only this unexecuted intent.
    if previous.original.isEmpty { try FileManager.default.removeItem(at:journal) }
    else { try save(previous) }
    throw MenuSwitchError.concurrentChange
   }
   let actual=try MenuSwitchCodec.states(read())
   guard changes.allSatisfy({ actual[$0.key] == $0.value }) else { throw MenuSwitchError.commandFailed }
  }
 }
 func restore() throws {
  do {
   try locked {
    let record=try loadJournal()
    if !record.original.isEmpty {
     let data=try read(); let current=try MenuSwitchCodec.states(data)
     let changes=MenuSwitchCodec.restoration(original:record.original,written:record.written,current:current)
     if !changes.isEmpty {
      try write(changes,basedOn:data)
      let actual=try MenuSwitchCodec.states(read())
      guard changes.allSatisfy({ actual[$0.key] == $0.value }) else { throw MenuSwitchError.commandFailed }
     }
    }
    if FileManager.default.fileExists(atPath:issueURL.path) { try FileManager.default.removeItem(at:issueURL) }
    if hasRecoveryRecord { try FileManager.default.removeItem(at:journal) }
   }
  } catch { recordFailure(error); throw error }
 }
 static func watchExit(of pid:pid_t) -> Bool {
  let queue=kqueue()
  if queue>=0 {
   defer { Darwin.close(queue) }
   var event=kevent(ident:UInt(pid),filter:Int16(EVFILT_PROC),flags:UInt16(EV_ADD|EV_ENABLE),fflags:UInt32(NOTE_EXIT),data:0,udata:nil)
   var result=kevent()
   // Retry interrupted waits. Fall back to a passive process-liveness check.
   while kevent(queue,&event,1,&result,1,nil)<0 {
    if errno == EINTR { continue }
    while kill(pid,0) == 0 { Thread.sleep(forTimeInterval:1) }
    break
   }
  } else {
   while kill(pid,0) == 0 { Thread.sleep(forTimeInterval:1) }
  }
  // A replacement app owns recovery itself. Never touch its active journal.
  guard let ownership=SideTrayInstanceLock(directory:supportDirectory) else { return true }
  return withExtendedLifetime(ownership) {
   do { try MenuSwitches().restore(); return true }
   catch { return false } // restore persists a human-readable failure for next launch.
  }
 }
}

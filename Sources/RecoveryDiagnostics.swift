import Foundation

/// Small local history of recovery decisions. Only fixed event/metric names and
/// integer values are accepted: never icon titles, bundle IDs, paths or errors.
final class RecoveryDiagnostics {
 enum Event:String {
  case sleep, wakeStarted, wakeIgnored, attemptStarted, cancelled
  case menuOpening, placementBusy, orderingBusy, activeMenu, mouseDown
  case checkingAccess, externalPopup, ownButtonMissing, accessNotReady
  case applyingLayout, layoutSucceeded, layoutFailed, wakeSucceeded, wakeExhausted
  case visibilityVerificationFailed, visibilityVerified, preferenceWriteFailed, restorationFailed, paused, manualRetry
 }
 enum Metric:String { case deferrals, slots, missingShown, unexpectedVisible, controlGranted, dataReadable, startupRecovered, recoveryBlocked, helperRunning }
 private let directory:URL
 private let limit:Int
 private let queue=DispatchQueue(label:"io.sidetray.recovery-diagnostics")
 init(directory:URL,limit:Int=256*1024) { self.directory=directory; self.limit=limit }
 func record(_ event:Event,attempt:Int=0,token:Int=0,metrics:[Metric:Int]=[:]) {
  let timestamp=Date()
  queue.async {
   var row:[String:Any] = ["time":ISO8601DateFormatter().string(from:timestamp),"event":event.rawValue,"attempt":attempt,"cycle":token,"pid":ProcessInfo.processInfo.processIdentifier]
   for (key,value) in metrics { row[key.rawValue]=value }
   do {
    var data=try JSONSerialization.data(withJSONObject:row,options:.sortedKeys); data.append(10)
    try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    let current=self.directory.appendingPathComponent("recovery.jsonl")
    let previous=self.directory.appendingPathComponent("recovery.previous.jsonl")
    let size=(try? current.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
    if size+data.count>self.limit && size>0 {
     if FileManager.default.fileExists(atPath:previous.path) { try FileManager.default.removeItem(at:previous) }
     try FileManager.default.moveItem(at:current,to:previous)
    }
    if !FileManager.default.fileExists(atPath:current.path) {
     guard FileManager.default.createFile(atPath:current.path,contents:nil,attributes:[.posixPermissions:0o600]) else { return }
    }
    let handle=try FileHandle(forWritingTo:current); defer { try? handle.close() }
    try handle.seekToEnd(); try handle.write(contentsOf:data)
   } catch { /* Diagnostics must never block or change recovery behavior. */ }
  }
 }
 func flush() { queue.sync {} }
}

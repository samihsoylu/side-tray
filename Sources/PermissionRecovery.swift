import Foundation

// Per-launch recovery: present once, keep checking without repeatedly taking
// focus, and resume only after permissions and native recovery are both ready.
struct PermissionRecovery {
 enum State { case idle, waiting, resuming, needsAttention, complete }
 enum Action { case none, present, resume }
 private(set) var state:State = .idle
 var isActive:Bool { state == .waiting || state == .resuming || state == .needsAttention }
 mutating func evaluate(setupPending:Bool,installed:Bool,controlGranted:Bool,dataPermissionMissing:Bool,ready:Bool)->Action {
  guard !setupPending,installed else { return .none }
  let missing = !controlGranted || dataPermissionMissing
  if (state == .idle || state == .complete) && missing {
   state = .waiting
   return .present
  }
  if state == .waiting && ready {
   state = .resuming
   return .resume
  }
  return .none
 }
 mutating func finished(success:Bool) { state = success ? .complete : .needsAttention }
 mutating func retry() { if state == .needsAttention { state = .waiting } }
}

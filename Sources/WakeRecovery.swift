import Foundation

/// Readiness deferrals have their own finite budget. They must not consume the
/// limited number of actual layout attempts or permit unbounded wake polling.
final class WakeRecovery {
 enum State { case idle, waiting, attempting, succeeded, exhausted }
 enum Result { case deferred, failed, succeeded }
 typealias Schedule = (TimeInterval,@escaping () -> Void) -> Void
 private(set) var state:State = .idle
 private(set) var attempts=0
 private(set) var deferrals=0
 private var generation=0
 var diagnosticCycle:Int { generation }
 var readinessExpired:Bool { state == .exhausted && deferrals == maxDeferrals }
 private let delays:[TimeInterval]
 private let maxDeferrals:Int
 private let schedule:Schedule
 var isActive:Bool { state == .waiting || state == .attempting }
 init(delays:[TimeInterval]=[2,5,15],maxDeferrals:Int=30,schedule:@escaping Schedule={ delay,work in
  DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work)
 }) {
  precondition(!delays.isEmpty && delays.allSatisfy { $0>0 } && maxDeferrals>0)
  self.delays=delays; self.maxDeferrals=maxDeferrals; self.schedule=schedule
 }
 func accepts(_ token:Int)->Bool { generation == token && isActive }
 func cancel() { generation += 1; state = .idle; attempts=0; deferrals=0 }
 // Existing Boolean callers represent real application attempts.
 func start(attempt:@escaping(Int,@escaping(Bool)->Void)->Void,finished:@escaping(Bool)->Void) {
  startEvaluating(attempt:{ token,done in attempt(token) { done($0 ? .succeeded : .failed) } },finished:finished)
 }
 func startEvaluating(attempt:@escaping(Int,@escaping(Result)->Void)->Void,finished:@escaping(Bool)->Void) {
  guard state == .idle else { return }
  generation += 1; let token=generation
  var check=0
  state = .waiting
  func enqueue(_ delay:TimeInterval) {
   schedule(delay) { [weak self] in
    guard let self,self.accepts(token),self.state == .waiting else { return }
    self.state = .attempting; check += 1
    let number=check
    attempt(token) { [weak self] result in
     guard let self,self.accepts(token),self.state == .attempting,check == number else { return }
     switch result {
     case .succeeded: self.attempts += 1; self.state = .succeeded; finished(true)
     case .failed:
      self.attempts += 1
      if self.attempts == self.delays.count { self.state = .exhausted; finished(false) }
      else { self.state = .waiting; enqueue(self.delays[self.attempts]) }
     case .deferred:
      self.deferrals += 1
      if self.deferrals == self.maxDeferrals { self.state = .exhausted; finished(false) }
      else { self.state = .waiting; enqueue(2) }
     }
    }
   }
  }
  enqueue(delays[0])
 }
}

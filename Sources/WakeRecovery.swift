import Foundation

/// One bounded recovery episode per sleep/wake cycle. Scheduling is injectable
/// so delays and stale callbacks can be tested without sleeping or changing macOS.
final class WakeRecovery {
 enum State { case idle, waiting, attempting, succeeded, exhausted }
 typealias Schedule = (TimeInterval,@escaping () -> Void) -> Void
 private(set) var state:State = .idle
 private(set) var attempts=0
 private var generation=0
 private let delays:[TimeInterval]
 private let schedule:Schedule
 var isActive:Bool { state == .waiting || state == .attempting }
 init(delays:[TimeInterval]=[2,5,15],schedule:@escaping Schedule={ delay,work in
  DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work)
 }) {
  precondition(!delays.isEmpty && delays.allSatisfy { $0>0 })
  self.delays=delays; self.schedule=schedule
 }
 func accepts(_ token:Int)->Bool { generation == token && isActive }
 func cancel() { generation += 1; state = .idle; attempts=0 }
 func start(attempt:@escaping(Int,@escaping(Bool)->Void)->Void,finished:@escaping(Bool)->Void) {
  guard state == .idle else { return }
  generation += 1; let token=generation
  state = .waiting
  func enqueue() {
   schedule(delays[attempts]) { [weak self] in
    guard let self,self.accepts(token),self.state == .waiting else { return }
    self.state = .attempting; self.attempts += 1
    let number=self.attempts
    attempt(token) { [weak self] ok in
     guard let self,self.accepts(token),self.state == .attempting,self.attempts == number else { return }
     if ok { self.state = .succeeded; finished(true) }
     else if self.attempts == self.delays.count { self.state = .exhausted; finished(false) }
     else { self.state = .waiting; enqueue() }
    }
   }
  }
  enqueue()
 }
}

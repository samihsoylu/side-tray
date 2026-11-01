import Foundation

final class Clock {
 var queued=[(TimeInterval,()->Void)]()
 var delays=[TimeInterval]()
 func schedule(_ delay:TimeInterval,_ action:@escaping()->Void) { delays.append(delay); queued.append((delay,action)) }
 func fire() { precondition(!queued.isEmpty); queued.removeFirst().1() }
}
@main struct WakeRecoveryTests {
 static func main() {
  let clock=Clock()
  let wake=WakeRecovery(schedule:clock.schedule)
  var calls=0, finishes=[Bool](), pending:((Bool)->Void)?
  let attempt:(Int,@escaping(Bool)->Void)->Void={ _,done in calls += 1; pending=done }
  wake.start(attempt:attempt,finished:{ finishes.append($0) })
  precondition(calls == 0 && clock.delays == [2] && wake.isActive)
  wake.start(attempt:attempt,finished:{ _ in fatalError("Duplicate wake restarted budget") })
  precondition(clock.queued.count == 1)
  clock.fire(); precondition(calls == 1 && wake.state == .attempting)
  let first=pending!; first(false)
  precondition(clock.delays == [2,5])
  first(false); precondition(clock.queued.count == 1,"Duplicate completion schedules no extra retry")
  clock.fire(); pending?(false)
  precondition(clock.delays == [2,5,15])
  clock.fire(); pending?(false)
  precondition(wake.state == .exhausted && calls == 3 && finishes == [false] && clock.queued.isEmpty)
  wake.start(attempt:attempt,finished:{ _ in fatalError("Exhausted budget restarted") })
  precondition(clock.queued.isEmpty)

  wake.cancel(); wake.start(attempt:attempt,finished:{ finishes.append($0) })
  clock.fire(); let stale=pending!
  wake.cancel(); wake.start(attempt:attempt,finished:{ finishes.append($0) })
  stale(true); precondition(wake.state == .waiting && finishes == [false])
  clock.fire(); pending?(true)
  precondition(wake.state == .succeeded && finishes == [false,true] && clock.queued.isEmpty)

  wake.cancel(); wake.start(attempt:attempt,finished:{ _ in fatalError("Cancelled delay completed") })
  let before=calls; wake.cancel(); clock.fire()
  precondition(calls == before && !wake.isActive)
  // Readiness skips can outlast the old three-check window without spending
  // a real layout attempt. They still stop after a separate finite budget.
  let settlingClock=Clock(), settling=WakeRecovery(maxDeferrals:5,schedule: { delay,work in settlingClock.schedule(delay,work) })
  var results=[Bool](), evaluated:((WakeRecovery.Result)->Void)?
  settling.startEvaluating(attempt:{ _,done in evaluated=done },finished:{ results.append($0) })
  for _ in 0..<4 { settlingClock.fire(); evaluated?(.deferred) }
  precondition(settling.attempts == 0 && settling.deferrals == 4 && settling.isActive && results.isEmpty)
  settlingClock.fire(); evaluated?(.succeeded)
  precondition(settling.attempts == 1 && results == [true])
  settling.cancel(); results=[]
  settling.startEvaluating(attempt:{ _,done in evaluated=done },finished:{ results.append($0) })
  for _ in 0..<5 { settlingClock.fire(); evaluated?(.deferred) }
  precondition(settling.attempts == 0 && results == [false] && settlingClock.queued.isEmpty)
  settling.cancel(); results=[]
  settling.startEvaluating(attempt:{ _,done in evaluated=done },finished:{ results.append($0) })
  settlingClock.fire(); let duplicate=evaluated!; duplicate(.deferred); duplicate(.failed)
  precondition(settling.attempts == 0 && settlingClock.queued.count == 1)
  settlingClock.fire(); evaluated?(.failed)
  settlingClock.fire(); evaluated?(.deferred)
  settlingClock.fire(); evaluated?(.failed)
  settlingClock.fire(); evaluated?(.failed)
  precondition(settling.attempts == 3 && results == [false] && settlingClock.queued.isEmpty)
  print("PASS: readiness deferrals preserve real-attempt budget; settling cap, mixed failures and duplicate callbacks")
  print("PASS: delayed wake recovery, three-attempt cap, no overlapping attempts, duplicate-event/completion guards, success stop and stale callback cancellation")
 }
}

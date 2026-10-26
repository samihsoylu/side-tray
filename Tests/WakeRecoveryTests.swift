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
  print("PASS: delayed wake recovery, three-attempt cap, no overlapping attempts, duplicate-event/completion guards, success stop and stale callback cancellation")
 }
}

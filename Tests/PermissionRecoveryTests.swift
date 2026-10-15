import Foundation
@main struct PermissionRecoveryTests {
 static func main() {
  var flow=PermissionRecovery()
  func evaluate(_ control:Bool=true,_ diskMissing:Bool=false,_ ready:Bool=false)->PermissionRecovery.Action {
   flow.evaluate(setupPending:false,installed:true,controlGranted:control,dataPermissionMissing:diskMissing,ready:ready)
  }
  assert(flow.evaluate(setupPending:true,installed:true,controlGranted:false,dataPermissionMissing:true,ready:false) == .none)
  assert(flow.evaluate(setupPending:false,installed:false,controlGranted:false,dataPermissionMissing:true,ready:false) == .none)
  assert(evaluate(true,false,true) == .none) // Working grants do not interrupt startup.
  assert(evaluate(true,false,false) == .none) // Checking/unavailable is not denied access.
  assert(evaluate(true,true) == .present) // Full Disk Access alone must open recovery.
  assert(evaluate(true,true) == .none) // No repeated foregrounding after dismissal.
  assert(evaluate(false,false) == .none) // Partial grants never resume.
  assert(evaluate(true,false,false) == .none) // Wait for journal/helper readiness too.
  assert(evaluate(true,false,true) == .resume)
  assert(evaluate(true,false,true) == .none) // Only one resume job.
  flow.finished(success:false)
  assert(flow.state == .needsAttention && flow.isActive)
  assert(evaluate(true,false,true) == .none) // No failing retry loop.
  flow.retry()
  assert(evaluate(true,false,true) == .resume)
  flow.finished(success:true)
  assert(flow.state == .complete && !flow.isActive)
  assert(evaluate(true,false,true) == .none)
  assert(evaluate(false,false) == .present) // A later genuine access loss is actionable.
  print("PASS: post-update access recovery, FDA-only loss, partial grants, quiet waiting, readiness gate, single resume and explicit failure retry")
 }
}

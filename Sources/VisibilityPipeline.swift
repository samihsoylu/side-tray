import Foundation

/// Serializes each complete visibility transaction, including asynchronous
/// verification and its completion, rather than only the preference writes.
/// All submissions and completions occur on the main thread.
final class VisibilityPipeline {
 typealias Work = (@escaping () -> Void) -> Void
 private var pending = [Work]()
 private var running = false
 func submit(_ work: @escaping Work) {
  precondition(Thread.isMainThread)
  pending.append(work)
  startNext()
 }
 private func startNext() {
  guard !running, !pending.isEmpty else { return }
  running = true
  let work = pending.removeFirst()
  var finished = false
  work { [weak self] in
   precondition(Thread.isMainThread)
   guard let self, !finished else { return }
   finished = true
   self.running = false
   self.startNext()
  }
 }
}

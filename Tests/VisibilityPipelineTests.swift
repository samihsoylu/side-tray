import Foundation

@main struct VisibilityPipelineTests {
 static func main() {
  let pipeline = VisibilityPipeline()
  var events = [String]()
  var finishFirst: (() -> Void)?
  var finishSecond: (() -> Void)?
  pipeline.submit { done in events.append("write-first"); finishFirst = done }
  pipeline.submit { done in events.append("write-second"); finishSecond = done }
  precondition(events == ["write-first"], "A second write must wait for first verification")
  // Model failed verification and restoration being queued before the next write.
  events.append("restore-first")
  finishFirst?()
  precondition(events == ["write-first", "restore-first", "write-second"])
  finishFirst?()
  pipeline.submit { done in events.append("third"); done() }
  precondition(events.last == "write-second", "Duplicate completion must not release another transaction")
  finishSecond?()
  precondition(events.last == "third")
  pipeline.submit { done in
   events.append("outer")
   pipeline.submit { next in events.append("nested"); next() }
   precondition(events.last == "outer", "Reentrant submission must wait")
   events.append("outer-complete"); done()
  }
  precondition(Array(events.suffix(3)) == ["outer", "outer-complete", "nested"])
  print("PASS: visibility verification serialization, recovery order, duplicate completion and reentrant submission")
 }
}

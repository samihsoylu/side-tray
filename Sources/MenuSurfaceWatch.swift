/// Track the surfaces opened by one menu interaction, not every window the app
/// might open afterwards. Three absent samples tolerate brief redraws.
struct MenuSurfaceWatch {
 let opened:Set<UInt32>
 private var absentSamples=0

 init(opened:Set<UInt32>) { self.opened=opened }

 mutating func isClosed(visible:Set<UInt32>,mousePressed:Bool) -> Bool {
  absentSamples=visible.isDisjoint(with:opened) ? min(absentSamples+1,3) : 0
  return absentSamples>=3 && !mousePressed
 }
}

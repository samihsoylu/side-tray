import AppKit
import ApplicationServices

// Read-only discovery. No AX actions, input events, permission requests,
// protected preference reads or menu-bar changes. Reports stay local.
func attribute(_ element:AXUIElement,_ key:String) -> CFTypeRef? {
 var result:CFTypeRef?
 guard AXUIElementCopyAttributeValue(element,key as CFString,&result) == .success else { return nil }
 return result
}
func frame(_ element:AXUIElement) -> [String:Double]? {
 guard let position=attribute(element,kAXPositionAttribute),CFGetTypeID(position) == AXValueGetTypeID(),
       let size=attribute(element,kAXSizeAttribute),CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
 var point=CGPoint.zero,dimensions=CGSize.zero
 guard AXValueGetValue(position as! AXValue,.cgPoint,&point),AXValueGetValue(size as! AXValue,.cgSize,&dimensions) else { return nil }
 return ["x":point.x,"y":point.y,"width":dimensions.width,"height":dimensions.height]
}

let trusted=AXIsProcessTrusted()
let deadline=Date().addingTimeInterval(15)
var remaining=500
var roots=[[String:Any]]()
for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier != nil {
 guard trusted,remaining>0,Date()<deadline else { break }
 let root=AXUIElementCreateApplication(app.processIdentifier)
 AXUIElementSetMessagingTimeout(root,0.1)
 let bundle=app.bundleIdentifier!
 let isService=["com.apple.MenuBarAgent","com.apple.controlcenter"].contains(bundle)
 let extras=attribute(root,kAXExtrasMenuBarAttribute)
 var nodes=[[String:Any]]()
 func visit(_ element:AXUIElement,_ depth:Int) {
  guard depth<=4,remaining>0,Date()<deadline else { return }; remaining-=1
  var pid:pid_t=0; AXUIElementGetPid(element,&pid)
  var actions:CFArray?
  AXUIElementCopyActionNames(element,&actions)
  var node:[String:Any] = ["depth":depth,"role":attribute(element,kAXRoleAttribute) as? String ?? "unknown",
                           "ownerBundle":NSRunningApplication(processIdentifier:pid)?.bundleIdentifier ?? "unknown",
                           "actions":actions as? [String] ?? []]
  if let rect=frame(element) { node["frame"]=rect }
  nodes.append(node)
  for child in (attribute(element,kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(40) { visit(child,depth+1) }
 }
 if let extras,CFGetTypeID(extras) == AXUIElementGetTypeID() { visit(extras as! AXUIElement,0) }
 if isService {
  for window in (attribute(root,kAXWindowsAttribute) as? [AXUIElement] ?? []).prefix(12) { visit(window,0) }
 }
 if extras != nil || isService { roots.append(["bundle":bundle,"extrasMenuBarPresent":extras != nil,"nodes":nodes]) }
}
var report:[String:Any] = ["format":1,"osVersion":ProcessInfo.processInfo.operatingSystemVersionString,
 "architecture":{
 #if arch(arm64)
 return "arm64"
 #else
 return "x86_64"
 #endif
 }(),"accessibilityGranted":trusted,"truncated":remaining<=0 || Date()>=deadline,
 "menuServices":NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { ["com.apple.MenuBarAgent","com.apple.controlcenter"].contains($0) },
 "roots":roots,"note":"Discovery only; this does not prove hiding or real-menu activation. No icon titles or window contents are collected."]
let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
if let index=CommandLine.arguments.firstIndex(of:"--output"),CommandLine.arguments.indices.contains(index+1) {
 let url=URL(fileURLWithPath:CommandLine.arguments[index+1])
 try data.write(to:url,options:.atomic)
 try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
} else { FileHandle.standardOutput.write(data); print("") }

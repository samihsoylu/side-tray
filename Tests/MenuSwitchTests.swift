import Foundation
@main struct Tests {
 static func main() throws {
  assert(MenuDataAccess.failure(NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoPermissionError)) == .permissionRequired)
  assert(MenuDataAccess.failure(NSError(domain:NSPOSIXErrorDomain,code:1)) == .permissionRequired)
  assert(MenuDataAccess.failure(NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoSuchFileError)) == .unavailable)
  assert(MenuDataAccess.failure(MenuSwitchError.unexpectedFormat) == .unavailable)
  assert(MenuDataAccess.failure(MenuSwitchError.commandFailed) == .unavailable)
  assert(MenuDataAccess.failure(NSError(domain:"wrapper",code:0,userInfo:[NSUnderlyingErrorKey:NSError(domain:NSPOSIXErrorDomain,code:13)])) == .permissionRequired)
  let aliases=["app.helper":["app.parent"],"app.otherHelper":["app.parent"]]
  assert(MenuSwitchCodec.visibilityChanges(states:["app.parent":true],visible:[],known:["app.helper"],aliases:aliases) == ["app.parent":false])
  assert(MenuSwitchCodec.visibilityChanges(states:["app.parent":false],visible:["app.helper"],known:["app.helper"],aliases:aliases) == ["app.parent":true])
  assert(MenuSwitchCodec.visibilityChanges(states:["app.parent":true,"app.helper":true],visible:[],known:["app.helper"],aliases:aliases) == ["app.helper":false])
  assert(MenuSwitchCodec.visibilityChanges(states:["app.parent":true],visible:["app.otherHelper"],known:["app.helper","app.otherHelper"],aliases:aliases) == ["app.parent":true])
  assert(MenuSwitchCodec.visibilityChanges(states:["unrelated.app":true],visible:[],known:["app.helper"],aliases:aliases).isEmpty)
  let keyA:[String:Any]=["bundle":["_0":"app.a"]]
  let keyB:[String:Any]=["bundle":["_0":"app.b"]]
  let rows:[Any]=[keyA,["isAllowed":false,"other":"retain"],keyB,["isAllowed":true],["unmanaged":"retain"],["opaque":7]]
  let nested=try PropertyListSerialization.data(fromPropertyList:rows,format:.binary,options:0)
  let domain=try PropertyListSerialization.data(fromPropertyList:["trackedApplications":nested,"unrelated":"retain"],format:.binary,options:0)
  let result=try MenuSwitchCodec.updatedValue(domain,changes:["app.a":true])
  let decoded=try PropertyListSerialization.propertyList(from:result,format:nil) as! [Any]
  assert((decoded[1] as! [String:Any])["other"] as? String == "retain")
  assert((decoded[3] as! [String:Any])["isAllowed"] as? Bool == true)
  assert((decoded[4] as! [String:Any])["unmanaged"] as? String == "retain")
  let newDomain=try PropertyListSerialization.data(fromPropertyList:["trackedApplications":result],format:.binary,options:0)
  let states=try MenuSwitchCodec.states(newDomain)
  assert(states == ["app.a":true,"app.b":true])
  let imported=try MenuSwitchCodec.updatedDomain(domain,changes:["app.a":true])
  let outer=try PropertyListSerialization.propertyList(from:imported,format:nil) as! [String:Any]
  assert(outer["unrelated"] as? String == "retain")
  let importedStates=try MenuSwitchCodec.states(imported)
  assert(importedStates == ["app.a":true,"app.b":true])
  let restoration=MenuSwitchCodec.restoration(original:["app.a":false,"app.b":true,"app.c":true],written:["app.a":true,"app.b":false,"app.c":false],current:["app.a":false,"app.b":false,"app.c":true])
  assert(restoration == ["app.b":true])
  let broken=try PropertyListSerialization.data(fromPropertyList:["trackedApplications":Data()],format:.binary,options:0)
  do { _=try MenuSwitchCodec.states(broken); assertionFailure("Malformed preferences accepted") } catch { }
  do { _=try MenuSwitchCodec.updatedValue(domain,changes:["new.app":false]); assertionFailure("Unknown app schema invented") } catch { }
  print("PASS: targeted menu flags, unrelated rows and metadata retained, unknown app rejection, malformed data and restoration preserving later user choices")
 }
}

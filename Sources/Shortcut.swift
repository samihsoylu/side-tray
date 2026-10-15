import AppKit
import Carbon

final class TrayShortcut {
 private var hotkey: EventHotKeyRef?
 private var handler: EventHandlerRef?
 var action: (() -> Void)?
 private(set) var error:String?
 func register(_ choice:ShortcutChoice?) -> Bool {
  unregister(); error=nil
  guard let choice else { return false }
  if let invalid=choice.validationMessage { error=invalid; return false }
  var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
  let install=InstallEventHandler(GetApplicationEventTarget(), { _,_,context in
   guard let context else { return OSStatus(eventNotHandledErr) }
   Unmanaged<TrayShortcut>.fromOpaque(context).takeUnretainedValue().action?(); return noErr
  },1,&type,Unmanaged.passUnretained(self).toOpaque(),&handler)
  guard install == noErr else { error="The shortcut could not be enabled. Try recording it again."; return false }
  let result=RegisterEventHotKey(choice.keyCode,choice.modifiers,EventHotKeyID(signature:0x53545259,id:1),GetApplicationEventTarget(),0,&hotkey)
  if result != noErr {
   unregister()
   error=result == OSStatus(eventHotKeyExistsErr) ? "This shortcut is already in use. Record a different combination." : "The shortcut could not be enabled. Record another combination or turn it off."
  }
  return result == noErr
 }
 func unregister() {
  if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey=nil
  if let handler { RemoveEventHandler(handler) }; handler=nil
 }
 deinit { unregister() }
}

func shortcutTitle(_ choice:ShortcutChoice?) -> String {
 guard let choice else { return "Record Shortcut…" }
 var prefix=""
 if choice.modifiers & ShortcutChoice.control != 0 { prefix+="⌃" }
 if choice.modifiers & ShortcutChoice.option != 0 { prefix+="⌥" }
 if choice.modifiers & ShortcutChoice.shift != 0 { prefix+="⇧" }
 if choice.modifiers & ShortcutChoice.command != 0 { prefix+="⌘" }
 let special:[UInt32:String]=[122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",123:"←",124:"→",125:"↓",126:"↑",51:"⌫",117:"⌦",115:"↖",119:"↘",116:"⇞",121:"⇟"]
 if let label=special[choice.keyCode] { return prefix+label }
 let source=TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
 if let property=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) {
  let data=Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
  let layout=UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to:UCKeyboardLayout.self)
  var dead:UInt32=0, count=0
  var chars=[UniChar](repeating:0,count:8)
  let result=UCKeyTranslate(layout,UInt16(choice.keyCode),UInt16(kUCKeyActionDisplay),0,UInt32(LMGetKbdType()),OptionBits(kUCKeyTranslateNoDeadKeysBit),&dead,8,&count,&chars)
  if result == noErr,count>0 { return prefix+String(utf16CodeUnits:chars,count:count).uppercased() }
 }
 return prefix+"Key \(choice.keyCode)"
}

final class ShortcutRecorder:NSButton {
 var began:(()->Void)?
 var finished:((ShortcutChoice?)->Void)?
 var validation:((String)->Void)?
 var recording=false
 override var acceptsFirstResponder:Bool { true }
 init() {
  super.init(frame:.zero); bezelStyle = .rounded; target=self; action=#selector(begin)
  setAccessibilityLabel("Keyboard shortcut")
 }
 required init?(coder:NSCoder) { fatalError() }
 @objc func begin() {
  guard !recording else { cancel(); return }
  recording=true; began?(); title="Press shortcut…"; window?.makeFirstResponder(self)
 }
 func cancel() { guard recording else { return }; recording=false; finished?(nil) }
 override func resignFirstResponder() -> Bool { cancel(); return super.resignFirstResponder() }
 override func performKeyEquivalent(with event:NSEvent) -> Bool {
  if recording { keyDown(with:event); return true }; return super.performKeyEquivalent(with:event)
 }
 override func keyDown(with event:NSEvent) {
  guard recording else { super.keyDown(with:event); return }
  if event.keyCode == 53 { cancel(); return }
  let f=event.modifierFlags; var mods:UInt32=0
  if f.contains(.command) { mods|=ShortcutChoice.command }
  if f.contains(.option) { mods|=ShortcutChoice.option }
  if f.contains(.shift) { mods|=ShortcutChoice.shift }
  if f.contains(.control) { mods|=ShortcutChoice.control }
  let choice=ShortcutChoice(keyCode:UInt32(event.keyCode),modifiers:mods)
  if let message=choice.validationMessage { validation?(message); return }
  recording=false; finished?(choice)
 }
}

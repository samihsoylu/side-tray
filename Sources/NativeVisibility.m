#import "NativeVisibility.h"
#import <dlfcn.h>
#import <objc/message.h>
static id activeAssertion;
static id pendingAssertion;
static void *library;
static NSUInteger generation;
static void invalidateAssertion(id value) {
 @try { if(value) ((void(*)(id,SEL))objc_msgSend)(value,NSSelectorFromString(@"invalidate")); } @catch(NSException *e) { NSLog(@"SideTray assertion cleanup failed: %@",e.name); }
}
void STRestoreVisibility(void) {
 generation++;
 invalidateAssertion(activeAssertion);
 invalidateAssertion(pendingAssertion);
 activeAssertion=nil;
 pendingAssertion=nil;
}
BOOL STSetVisibleBundles(NSArray<NSString *> *bundles, void (^finished)(NSError *)) {
 if(!library) library=dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",RTLD_LAZY);
 Class configClass=NSClassFromString(@"MBAssessmentModeConfiguration");
 Class assertionClass=NSClassFromString(@"MBAssessmentModeAssertion");
 SEL configSelector=NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
 SEL activateSelector=NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
 if(!library || ![configClass instancesRespondToSelector:configSelector] || ![assertionClass instancesRespondToSelector:activateSelector]) return NO;
 NSUInteger request=++generation;
 invalidateAssertion(pendingAssertion);
 pendingAssertion=nil;
 @try {
  id configuration=((id(*)(id,SEL,id,id))objc_msgSend)([configClass alloc],configSelector,@[@0,@1,@2,@3,@4,@5,@6,@7,@8],bundles);
  id candidate=[[assertionClass alloc] init];
  pendingAssertion=candidate;
  __block BOOL completed=NO;
  ((void(*)(id,SEL,id,void(^)(NSError*)))objc_msgSend)(candidate,activateSelector,configuration,^(NSError *error){
   dispatch_async(dispatch_get_main_queue(),^{
    if(completed) return;
    completed=YES;
    if(pendingAssertion==candidate) pendingAssertion=nil;
    if(request!=generation) {
     invalidateAssertion(candidate);
     finished([NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
     return;
    }
    if(!error) { invalidateAssertion(activeAssertion); activeAssertion=candidate; }
    else { invalidateAssertion(candidate); }
    finished(error);
   });
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
   if(completed) return;
   completed=YES;
   invalidateAssertion(candidate);
   if(pendingAssertion==candidate) pendingAssertion=nil;
   if(request!=generation) {
    finished([NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
   } else {
    STRestoreVisibility();
    finished([NSError errorWithDomain:@"SideTray.Visibility" code:1 userInfo:@{NSLocalizedDescriptionKey:@"macOS did not confirm the menu bar visibility change."}]);
   }
  });
  return YES;
 } @catch(NSException *e) { return NO; }
}

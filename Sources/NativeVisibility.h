#import <Foundation/Foundation.h>
BOOL STSetVisibleBundles(NSArray<NSString *> *bundles, void (^finished)(NSError *error));
void STRestoreVisibility(void);

#import "StdPatch/StdPatch.h"

static inline NSArray *DPScriptTabs(id scriptSpace) {
    id tabs = DPValueForKey(scriptSpace, @"appleScriptTabs");
    return [tabs isKindOfClass:NSArray.class] ? tabs : nil;
}

id DPScriptWindow(NSWindow *window);
id DPScriptTab(NSWindow *window, NSString *tabID);
id DPScriptTabIn(id scriptWindow, NSString *tabID);
id DPScriptTabInAnyProfile(id scriptWindow, NSString *tabID);
id DPScriptProfileHolding(id scriptWindow, NSString *tabID);
NSInteger DPTabListing(id scriptWindow, NSString *tabID);
NSString *DPTabID(id tab);
NSString *DPActiveTabID(NSWindow *window);
NSString *DPActiveTabIDIn(id scriptWindow);
void DPFocusTab(id tab);
void DPCloseTab(id tab);
void DPMarkOwnClose(void);
BOOL DPTakeOwnClose(void);

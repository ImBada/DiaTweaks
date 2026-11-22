#import "StdPatch/StdPatch.h"

id DPScriptWindow(NSWindow *window);
id DPScriptTab(NSWindow *window, NSString *tabID);
id DPScriptTabIn(id scriptWindow, NSString *tabID);
id DPScriptTabInAnyProfile(id scriptWindow, NSString *tabID);
id DPScriptProfileHolding(id scriptWindow, NSString *tabID);
NSString *DPTabID(id tab);
NSString *DPActiveTabID(NSWindow *window);
NSString *DPActiveTabIDIn(id scriptWindow);
void DPFocusTab(id tab);
void DPCloseTab(id tab);
// Marks our own closes so the closing-page hook ignores them.
void DPMarkOwnClose(void);
BOOL DPTakeOwnClose(void);

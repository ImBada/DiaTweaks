#import "StdPatch/StdPatch.h"

extern DPPatch DPPinnedTabCloseButton, DPPinnedTabMinusButton;  // The minus button is an option of the close button.

// The view model's delegate of a TabView (its TabController) or a TabContentView (its TabContentController).
id DPViewModelDelegate(NSView *view);
NSView *DPEnclosingTab(NSView *view);
void DPRelayoutTabContents(void);  // Each tab's page row picks its close button as it's laid out.

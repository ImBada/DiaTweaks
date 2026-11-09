#import "StdPatch/StdPatch.h"

extern DPPatch DPPinnedTabCloseButton, DPPinnedTabMinusButton;

// The view model's delegate of a TabView (its TabController) or a TabContentView (its TabContentController).
id DPViewModelDelegate(NSView *view);
NSView *DPEnclosingTab(NSView *view);
NSView *DPTrackedTab(id hoverTracker);  // The TabView a hover tracker watches, if it watches one.

// Dia hides the close button on a pinned tab outside a folder by setting suppressesCloseButton on its tab controller,
// and reads it again each time the pointer enters the tab. Both patches clear it, and set it back once both are off.
void DPAllowClose(id tabController);
void DPRestoreSuppressedCloseButtons(void);

#import "StdPatch/StdPatch.h"

extern DPPatch DPPinnedTabCloseButton, DPPinnedTabMinusButton;  // The minus button is an option of the close button.

// The view model's delegate of a TabView (its TabController) or a TabContentView (its TabContentController).
id DPViewModelDelegate(NSView *view);
NSView *DPEnclosingTab(NSView *view);
void DPRelayoutTabContents(void);

enum { DPCloseKeepingTabStyle = 1 };  // TabUI.TabCloseButtonStyle.closeKeepingTab.
id DPAttributes(NSView *content);
BOOL DPIsOpenPinned(NSView *content);  // Takes a TabContentView.
// Closes an open pinned tab's page and keeps the tab pinned, as Dia's minus under a folded folder does.
void DPCloseKeepingTab(NSView *content);  // Each tab's page row picks its close button as it's laid out.

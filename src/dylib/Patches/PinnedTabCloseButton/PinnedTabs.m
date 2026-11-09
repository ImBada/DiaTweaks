#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

extern void *swift_unknownObjectWeakLoadStrong(void *reference);

static NSHashTable *DPCleared;  // Tab controllers whose flag a patch cleared.

// viewModel.delegate is a Swift weak reference, which DPSwiftValue can't read.
id DPViewModelDelegate(NSView *view) {
    void **viewModel = DPIvar(view, "viewModel");
    void *delegate = viewModel && *viewModel ? DPIvar((__bridge id)*viewModel, "delegate") : NULL;
    return delegate ? (__bridge_transfer id)swift_unknownObjectWeakLoadStrong(delegate) : nil;
}

NSView *DPEnclosingTab(NSView *view) {
    while (view && !DPIsKind(view, DPDiaTabView)) view = view.superview;
    return view;
}

NSView *DPTrackedTab(id hoverTracker) {
    __autoreleasing id *view = (__autoreleasing id *)DPIvar(hoverTracker, "view");
    return view ? DPEnclosingTab(objc_loadWeak(view)) : nil;
}

void DPAllowClose(id tabController) {
    BOOL *suppress = DPIvar(tabController, "suppressesCloseButton");
    if (!suppress || !*suppress) return;
    *suppress = NO;
    if (!DPCleared) DPCleared = [NSHashTable weakObjectsHashTable];
    [DPCleared addObject:tabController];
}

void DPRestoreSuppressedCloseButtons(void) {
    if (DPPinnedTabCloseButton.on || DPPinnedTabMinusButton.on) return;
    for (id controller in DPCleared.allObjects) {
        BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
        if (suppress) *suppress = YES;
    }
    [DPCleared removeAllObjects];
}

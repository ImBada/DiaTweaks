#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

// Dia hides the close button on a pinned tab outside a folder by setting suppressesCloseButton on its tab controller,
// and reads it again each time the pointer enters the tab. Clearing it first shows the button as on tabs in a folder.

static NSHashTable *DPCleared;  // Tab controllers whose flag this patch cleared.

static void DPAllowClose(NSView *tab) {
    id controller = DPViewModelDelegate(tab);
    BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
    if (!suppress || !*suppress) return;
    *suppress = NO;
    [DPCleared addObject:controller];
}

static void DPTracker_mouseEntered(id self, SEL _cmd, NSEvent *event) {
    __autoreleasing id *view = DPPinnedTabCloseButton.on ? (__autoreleasing id *)DPIvar(self, "view") : NULL;
    if (view) DPAllowClose(DPEnclosingTab(objc_loadWeak(view)));
    DPCallOriginal(DPTracker_mouseEntered, self, event);
}

// Dia sets the flag again when it reconfigures a tab, which lays it out.
static void DPTab_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTab_layout, self);
    if (DPPinnedTabCloseButton.on) DPAllowClose(self);
}

// The button follows on the next hover. The minus button option goes with it.
static void DPApplyPinnedTabCloseButton(DPPatch *patch) {
    DPRelayoutTabContents();
    if (patch->on) {
        for (NSView *tab in DPFindViews(DPDiaTabView)) DPAllowClose(tab);
        return;
    }
    for (id controller in DPCleared.allObjects) {
        BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
        if (suppress) *suppress = YES;
    }
    [DPCleared removeAllObjects];
}

// Off, Dia owns the flag again, so only the on state is checked.
static NSString *DPVerifyPinnedTabCloseButton(DPPatch *patch) {
    for (NSView *tab in DPFindViews(DPDiaTabView)) {
        id controller = DPViewModelDelegate(tab);
        if (!controller || tab.needsLayout) continue;  // Torn down, or about to be cleared.
        BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
        if (!suppress) return @"tab has no close button setting";
        if (patch->on && *suppress) return @"pinned tab hides its close button";
    }
    return nil;
}

static void DPInstallPinnedTabCloseButton(void) {
    DPCleared = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaHoverTracker, @selector(mouseEntered:), (IMP)DPTracker_mouseEntered);
    DPHook(DPDiaTabView, @selector(layout), (IMP)DPTab_layout);
}

DP_PATCH(DPPinnedTabCloseButton) {
    .key = @"pinnedTabCloseButton",
    .order = 86,
    .section = @"Tabs",
    .title = @"Close Button on Pinned Tabs",
    .detail = @"Show the close button when you point at a pinned tab outside a folder, as Dia does for tabs in a pinned folder.",
    .symbol = @"xmark.circle.fill",
    .tint = @"systemPinkColor",
    .classes = DPClasses(DPDiaTabView, DPDiaHoverTracker),
    .install = DPInstallPinnedTabCloseButton,
    .apply = DPApplyPinnedTabCloseButton,
    .verify = DPVerifyPinnedTabCloseButton,
};

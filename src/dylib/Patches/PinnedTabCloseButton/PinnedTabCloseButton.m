#import "StdPatch/StdPatch.h"

// Dia hides the close button on a pinned tab outside a folder by setting suppressesCloseButton on its tab controller,
// and reads it again each time the pointer enters the tab. Clearing it first shows the button as on tabs in a folder.

extern DPPatch DPPinnedTabCloseButton;
extern void *swift_unknownObjectWeakLoadStrong(void *reference);

static NSHashTable *DPCleared;  // Tab controllers whose flag this patch cleared.

// TabView.viewModel.delegate is a Swift weak reference, which DPSwiftValue can't read.
static id DPTabController(NSView *tab) {
    void **viewModel = DPIvar(tab, "viewModel");
    void *delegate = viewModel && *viewModel ? DPIvar((__bridge id)*viewModel, "delegate") : NULL;
    return delegate ? (__bridge_transfer id)swift_unknownObjectWeakLoadStrong(delegate) : nil;
}

static BOOL *DPSuppressFlag(id controller) { return DPIvar(controller, "suppressesCloseButton"); }

static void DPAllowClose(NSView *tab) {
    id controller = DPTabController(tab);
    BOOL *suppress = DPSuppressFlag(controller);
    if (!suppress || !*suppress) return;
    *suppress = NO;
    [DPCleared addObject:controller];
}

static void DPTracker_mouseEntered(id self, SEL _cmd, NSEvent *event) {
    if (DPPinnedTabCloseButton.on) {
        NSView *view = objc_loadWeak((__autoreleasing id *)DPIvar(self, "view"));
        while (view && !DPIsKind(view, DPDiaTabView)) view = view.superview;
        if (view) DPAllowClose(view);
    }
    DPCallOriginal(DPTracker_mouseEntered, self, event);
}

// Dia sets the flag again when it reconfigures a tab, which lays it out.
static void DPTab_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTab_layout, self);
    if (DPPinnedTabCloseButton.on) DPAllowClose(self);
}

// The button follows on the next hover.
static void DPApplyPinnedTabCloseButton(DPPatch *patch) {
    if (patch->on) {
        for (NSView *tab in DPFindViews(DPDiaTabView)) DPAllowClose(tab);
        return;
    }
    for (id controller in DPCleared.allObjects) {
        BOOL *suppress = DPSuppressFlag(controller);
        if (suppress) *suppress = YES;
    }
    [DPCleared removeAllObjects];
}

static NSString *DPVerifyPinnedTabCloseButton(DPPatch *patch) {
    for (NSView *tab in DPFindViews(DPDiaTabView)) {
        id controller = DPTabController(tab);
        if (!controller) continue;  // A tab being torn down.
        BOOL *suppress = DPSuppressFlag(controller);
        if (!suppress) return @"tab has no close button setting";
        if (patch->on && *suppress) return @"pinned tab hides its close button";
        if (!patch->on && !*suppress && [DPCleared containsObject:controller]) return @"pinned tab keeps its close button";
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

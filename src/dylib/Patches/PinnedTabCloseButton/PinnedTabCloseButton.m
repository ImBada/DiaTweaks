#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

static NSHashTable *DPCleared;

static void DPAllowClose(NSView *tab) {
    __attribute__((objc_precise_lifetime)) id controller = DPViewModelDelegate(tab);
    BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
    if (!suppress || !*suppress) return;
    *suppress = NO;
    [DPCleared addObject:controller];
}

static void DPTracker_mouseEntered(id self, SEL _cmd, NSEvent *event) {
    if (DPPinnedTabCloseButton.on) {
        __autoreleasing id *view = (__autoreleasing id *)DPIvar(self, "view");
        if (view) DPAllowClose(DPEnclosingTab(objc_loadWeak(view)));
    }
    DPCallOriginal(DPTracker_mouseEntered, self, event);
}

static void DPTab_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTab_layout, self);
    if (DPPinnedTabCloseButton.on) DPAllowClose(self);
}

static void DPCollectViewsIn(NSView *view, Class cls, NSMutableArray<NSView *> *out, NSHashTable *seen) {
    if ([view isKindOfClass:cls] && ![seen containsObject:view]) {
        [seen addObject:view];
        [out addObject:view];
    }
    for (NSView *sub in view.subviews) DPCollectViewsIn(sub, cls, out, seen);
}

static NSArray<NSView *> *DPAllWindowViews(const char *className) {
    NSMutableArray<NSView *> *out = [DPFindViews(className) mutableCopy];
    Class cls = objc_getClass(className);
    if (!cls) return out;
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NSView *v in out) [seen addObject:v];
    for (NSWindow *window in NSApp.windows) DPCollectViewsIn(window.contentView, cls, out, seen);
    return out;
}

static void DPApplyPinnedTabCloseButton(DPPatch *patch) {
    DPRelayoutTabContents();
    if (patch->on) {
        for (NSView *tab in DPAllWindowViews(DPDiaTabView)) DPAllowClose(tab);
        return;
    }
    if (!DPCleared.count) return;
    NSMutableSet *unpinned = [NSMutableSet set];
    for (NSView *content in DPAllWindowViews(DPDiaTabContentView)) {
        __attribute__((objc_precise_lifetime)) id attributes = DPAttributes(content);
        BOOL *pinned = DPIvar(attributes, "isInFavoritesOrPinnedContainer");
        id controller = pinned && !*pinned ? DPViewModelDelegate(DPEnclosingTab(content)) : nil;
        if (controller) [unpinned addObject:controller];
    }
    for (id controller in DPCleared.allObjects) {
        BOOL *suppress = [unpinned containsObject:controller] ? NULL : DPIvar(controller, "suppressesCloseButton");
        if (suppress) *suppress = YES;
    }
    [DPCleared removeAllObjects];
}

static NSString *DPVerifyPinnedTabCloseButton(DPPatch *patch) {
    for (NSView *tab in DPFindViews(DPDiaTabView)) {
        __attribute__((objc_precise_lifetime)) id controller = DPViewModelDelegate(tab);
        if (!controller || tab.needsLayout) continue;
        BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
        if (suppress) {
            if (patch->on && *suppress) return @"pinned tab hides its close button";
        } else if (!DPIvar(controller, "requestedCloseButtonStyle")) {
            // Dia 1.59 removed suppressesCloseButton and shows close buttons on all pinned tabs.
            return @"tab has no close button setting";
        }
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
    .order = 83,
    .section = @"Sidebar & Tab Bar",
    .group = @"pinnedTabs",
    .title = @"Close Button on Pinned Tabs",
    .detail = @"Show the close button when you point at a pinned tab outside a folder, as Dia does for tabs in a pinned folder.",
    .symbol = @"xmark.circle.fill",
    .tint = @"systemTealColor",
    .classes = DPClasses(DPDiaTabView, DPDiaHoverTracker),
    .install = DPInstallPinnedTabCloseButton,
    .apply = DPApplyPinnedTabCloseButton,
    .verify = DPVerifyPinnedTabCloseButton,
};

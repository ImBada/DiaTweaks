#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

// Clearing Dia's flag before the pointer enters a pinned tab outside a folder shows the button as on tabs in a folder.

static void DPTracker_mouseEntered(id self, SEL _cmd, NSEvent *event) {
    if (DPPinnedTabCloseButton.on)
        DPAllowClose(DPViewModelDelegate(DPTrackedTab(self)));
    DPCallOriginal(DPTracker_mouseEntered, self, event);
}

// Dia sets the flag again when it reconfigures a tab, which lays it out.
static void DPTab_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTab_layout, self);
    if (DPPinnedTabCloseButton.on) DPAllowClose(DPViewModelDelegate(self));
}

// The button follows on the next hover.
static void DPApplyPinnedTabCloseButton(DPPatch *patch) {
    if (!patch->on) DPRestoreSuppressedCloseButtons();
    else for (NSView *tab in DPFindViews(DPDiaTabView)) DPAllowClose(DPViewModelDelegate(tab));
}

static NSString *DPVerifyPinnedTabCloseButton(DPPatch *patch) {
    if (!patch->on) return nil;  // Dia sets the flag back as it pleases.
    for (NSView *tab in DPFindViews(DPDiaTabView)) {
        id controller = DPViewModelDelegate(tab);
        if (!controller) continue;  // A tab being torn down.
        BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
        if (!suppress) return @"tab has no close button setting";
        if (*suppress) return @"pinned tab hides its close button";
    }
    return nil;
}

static void DPInstallPinnedTabCloseButton(void) {
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

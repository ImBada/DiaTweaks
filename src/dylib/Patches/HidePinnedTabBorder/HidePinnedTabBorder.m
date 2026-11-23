#import "StdPatch/Hide.h"

extern DPPatch DPHidePinnedTabBorder;

static BOOL DPIsPinnedTabOutline(NSView *view) { return DPIsKind(view, DPDiaPinnedTabOutline); }

static void DPPinnedTab_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPPinnedTab_layout, self);
    if (DPHidePinnedTabBorder.on) DPEnforceHides(self);
}

static void DPInstallHidePinnedTabBorder(void) { DPHook(DPDiaPinnedTab, @selector(layout), (IMP)DPPinnedTab_layout); }

DP_PATCH(DPHidePinnedTabBorder) {
    .key = @"hidePinnedTabBorder",
    .order = 82,
    .title = @"Hide Pinned Tab Border",
    .detail = @"Remove the colored border around the selected pinned tab.",
    .symbol = @"pin.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .group = @"pinnedTabs",
    .classes = DPClasses(DPDiaPinnedTab, DPDiaPinnedTabOutline),
    .hides = DPIsPinnedTabOutline,
    .install = DPInstallHidePinnedTabBorder,
};

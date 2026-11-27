#import "Toolbar.h"

// Dia replaced Hide Toolbar's copy peek and toast (upstream #431), so the toolbar never peeks for a copy.
BOOL DPSidebarToolbarIsPeeking(NSView *pane) { return NO; }

BOOL DPSidebarUsesToolbarCopyFeedback(NSWindow *window) { return NO; }

void DPSidebarStopToolbarHover(DPToolbarHover *hover) {
    if (!hover) return;
    [hover.animation invalidate]; [hover.hideTimer invalidate];
    [hover.inPlaceAnimation invalidate];
    hover.animation = hover.hideTimer = hover.inPlaceAnimation = nil;
    // These are the implementation's own state flags; avoid setters that start timers.
    for (NSString *name in @[@"_revealed", @"_inPlace"])
        if (DPIvar(hover, name.UTF8String)) *(BOOL *)DPIvar(hover, name.UTF8String) = NO;
    hover.progress = hover.inPlaceProgress = 0;
    if (hover.tracking) [hover.pane removeTrackingArea:hover.tracking];
    hover.tracking = nil;
}

static void DPSidebarHover_update(DPToolbarHover *self, SEL _cmd, NSView *bar, NSView *bookmarks) {
    DPCallOriginal(DPSidebarHover_update, self, bar, bookmarks);
    if (DPSidebarReplacesToolbar(self.pane)) DPSidebarStopToolbarHover(self);
}

static void DPSidebarHover_reset(DPToolbarHover *self, SEL _cmd) {
    DPSidebarRestoreToolbar(self.pane);
    DPCallOriginal(DPSidebarHover_reset, self);
    DPSidebarApplyToolbar(self.pane);
}

void DPSidebarInstallToolbarHover(void) {
    DPHookClass(DPToolbarHover.class, @selector(updateForBar:bookmarks:), (IMP)DPSidebarHover_update);
    DPHookClass(DPToolbarHover.class, NSSelectorFromString(@"reset"), (IMP)DPSidebarHover_reset);
}

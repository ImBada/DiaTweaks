#import "Toolbar.h"

void DPSidebarStopToolbarHover(DPToolbarHover *hover) {
    if (!hover) return;
    [hover.animation invalidate]; [hover.hideTimer invalidate];
    [hover.inPlaceAnimation invalidate]; [hover.peekTimer invalidate];
    hover.animation = hover.hideTimer = hover.inPlaceAnimation = hover.peekTimer = nil;
    // These are the implementation's own state flags; avoid setters that start timers.
    for (NSString *name in @[@"_revealed", @"_peeking", @"_inPlace"])
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

static void DPSidebarHover_peek(DPToolbarHover *self, SEL _cmd) {
    if (!DPSidebarReplacesToolbar(self.pane)) DPCallOriginal(DPSidebarHover_peek, self);
}

static void DPSidebarToast_show(id self, SEL _cmd, NSString *message, NSView *pane) {
    if (!DPSidebarReplacesToolbar(pane)) DPCallOriginal(DPSidebarToast_show, self, message, pane);
}

void DPSidebarInstallToolbarHover(void) {
    DPHookClass(DPToolbarHover.class, @selector(updateForBar:bookmarks:), (IMP)DPSidebarHover_update);
    DPHookClass(DPToolbarHover.class, NSSelectorFromString(@"reset"), (IMP)DPSidebarHover_reset);
    DPHookClass(DPToolbarHover.class, @selector(peek), (IMP)DPSidebarHover_peek);
    DPHookClass(objc_getClass("DPCopyToastView"), NSSelectorFromString(@"showMessage:inPane:"), (IMP)DPSidebarToast_show);
}

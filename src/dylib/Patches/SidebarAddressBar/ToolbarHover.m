#import "Toolbar.h"

static char DPCopyPeekTimerKey;

BOOL DPSidebarToolbarIsPeeking(NSView *pane) {
    return DPHideToolbar.on && DPPeekToolbarOnCopy.on && DPGet(pane, &DPCopyPeekTimerKey) != nil;
}

BOOL DPSidebarUsesToolbarCopyFeedback(NSWindow *window) {
    if (!DPHideToolbar.on || (!DPPeekToolbarOnCopy.on && !DPCopyToast.on)) return NO;
    NSView *first = nil;
    NSResponder *responder = window.firstResponder;
    for (NSView *pane in DPPanes) {
        if (pane.window != window || pane.hiddenOrHasHiddenAncestor) continue;
        if ([responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:pane])
            return DPSidebarReplacesToolbar(pane) && [DPToolbarHover forPane:pane] != nil;
        first = first ?: pane;
    }
    return first && DPSidebarReplacesToolbar(first) && [DPToolbarHover forPane:first] != nil;
}

static void DPSidebarEndCopyPeek(NSView *pane) {
    if (!pane) return;
    NSTimer *timer = DPGet(pane, &DPCopyPeekTimerKey);
    [timer invalidate];
    DPSet(pane, &DPCopyPeekTimerKey, nil);
}

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
    DPSidebarEndCopyPeek(self.pane);
    DPSidebarRestoreToolbar(self.pane);
    DPCallOriginal(DPSidebarHover_reset, self);
    DPSidebarApplyToolbar(self.pane);
}

static void DPSidebarHover_peek(DPToolbarHover *self, SEL _cmd) {
    NSView *pane = self.pane;
    if (!DPSidebarReplacesToolbar(pane)) {
        DPCallOriginal(DPSidebarHover_peek, self);
        return;
    }
    DPSidebarEndCopyPeek(pane);
    __weak NSView *weakPane = pane;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.6 repeats:NO block:^(NSTimer *timer) {
        NSView *pane = weakPane;
        if (!pane) return;
        DPSidebarEndCopyPeek(pane);
        DPSidebarApplyToolbar(pane);
    }];
    DPSet(pane, &DPCopyPeekTimerKey, timer);
    DPSidebarApplyToolbar(pane);
}

static void DPSidebarHover_endPeek(DPToolbarHover *self, SEL _cmd) {
    NSView *pane = self.pane;
    if (DPGet(pane, &DPCopyPeekTimerKey)) {
        DPSidebarEndCopyPeek(pane);
        DPSidebarApplyToolbar(pane);
    }
    DPCallOriginal(DPSidebarHover_endPeek, self);
}

void DPSidebarInstallToolbarHover(void) {
    DPHookClass(DPToolbarHover.class, @selector(updateForBar:bookmarks:), (IMP)DPSidebarHover_update);
    DPHookClass(DPToolbarHover.class, NSSelectorFromString(@"reset"), (IMP)DPSidebarHover_reset);
    DPHookClass(DPToolbarHover.class, @selector(peek), (IMP)DPSidebarHover_peek);
    DPHookClass(DPToolbarHover.class, @selector(endPeek), (IMP)DPSidebarHover_endPeek);
}

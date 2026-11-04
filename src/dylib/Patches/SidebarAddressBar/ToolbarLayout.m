#import "Toolbar.h"
#import "Patches/EdgeToEdge/EdgeToEdge.h"

static char DPReplacementFrameKey, DPReplacementBaseKey, DPReplacementAppliedKey;

NSRect DPSidebarToolbarBase(NSView *view) {
    NSValue *applied = DPGet(view, &DPReplacementAppliedKey);
    return applied ?
        [DPGet(view, &DPReplacementBaseKey) rectValue] : DPLaidOutFrame(view);
}

BOOL DPSidebarReplacesToolbar(NSView *pane) {
    if (!DPSidebarHideTopToolbar.on || !DPSidebarAddressRowAvailable(pane.window)) return NO;
    for (NSView *view = pane.superview; view; view = view.superview)
        if (DPIsKind(view, DPDiaContentContainer)) return DPBesideSidebar(view);
    return NO;
}

static void DPReplacementFrame(NSView *view, NSRect frame) {
    DPSet(view, &DPReplacementBaseKey, @(DPSidebarToolbarBase(view)));
    DPSet(view, &DPReplacementAppliedKey, @(frame));
    DPOverride(view, &DPReplacementFrameKey, DPDiaValue(view, &DPReplacementFrameKey, @(view.frame)), @(frame));
    if (!NSEqualRects(view.frame, frame)) view.frame = frame;
}

static void DPRestoreReplacementFrame(NSView *view) {
    if (!DPGet(view, &DPReplacementAppliedKey)) return;
    NSRect frame = [DPDiaValue(view, &DPReplacementFrameKey, @(view.frame)) rectValue];
    if (!NSEqualRects(view.frame, frame)) view.frame = frame;
    DPSet(view, &DPReplacementAppliedKey, nil);
    DPSet(view, &DPReplacementFrameKey, nil);
}

void DPSidebarRestoreToolbar(NSView *pane) {
    for (NSView *view in pane.subviews) {
        DPRestoreReplacementFrame(view);
        for (NSView *child in view.subviews) DPRestoreReplacementFrame(child);
    }
}

void DPSidebarApplyToolbar(NSView *pane) {
    if (!DPSidebarReplacesToolbar(pane)) return;
    NSView *bar = DPSubview(pane, DPDiaToolbar);
    if (!bar) return;
    DPSidebarStopToolbarHover([DPToolbarHover forPane:pane]);
    NSRect base = DPSidebarToolbarBase(bar), frame = base;
    CGFloat height = NSHeight(base), edge = DPBottom(pane, base);
    frame.origin.y += pane.isFlipped ? -edge : edge;
    DPReplacementFrame(bar, frame);
    bar.alphaValue = 0;
    NSMutableArray<NSView *> *stack = [NSMutableArray new];
    for (NSView *view in pane.subviews) if (view != bar) [stack addObject:view];
    [stack sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        return [@(DPTop(pane, DPSidebarToolbarBase(a))) compare:@(DPTop(pane, DPSidebarToolbarBase(b)))];
    }];
    for (NSView *view in stack) {
        NSRect laidOut = DPSidebarToolbarBase(view);
        if (fabs(DPTop(pane, laidOut) - edge) > 0.5) continue;
        BOOL fills = fabs(DPBottom(pane, laidOut) - NSHeight(pane.bounds)) < 0.5;
        if (!fills) edge = DPBottom(pane, laidOut);
        frame = laidOut;
        if (fills) frame.size.height += height;
        if (pane.isFlipped) frame.origin.y -= height;
        else if (!fills) frame.origin.y += height;
        NSMutableArray<NSView *> *fillers = [NSMutableArray new];
        for (NSView *child in view.subviews)
            if (NSEqualRects(DPSidebarToolbarBase(child), (NSRect){NSZeroPoint, laidOut.size})) [fillers addObject:child];
        DPReplacementFrame(view, frame);
        if (DPIsKind(view, DPDiaBookmarksBar)) view.alphaValue = 1;
        for (NSView *child in fillers) DPReplacementFrame(child, view.bounds);
    }
    DPRepaintTabs(pane.window);
}

void DPSidebarRefreshToolbar(void) {
    static BOOL refreshing;
    if (refreshing) return;
    refreshing = YES;
    @try {
        for (NSView *pane in DPFindViews(DPDiaContentPane)) {
            DPSidebarRestoreToolbar(pane);
            DPApplyToolbar(pane);
            DPSidebarApplyToolbar(pane);
        }
    } @finally { refreshing = NO; }
}

static void DPApplySidebarHideTopToolbar(DPPatch *patch) { DPSidebarRefreshToolbar(); }
DP_PATCH(DPSidebarHideTopToolbar) {
    .key = @"sidebarHideTopToolbar", .order = 88, .defaultOn = YES,
    .title = @"Hide top address bar",
    .detail = @"Use the sidebar address bar in place of the top toolbar.",
    .symbol = @"menubar.rectangle", .section = @"Sidebar & Tab Bar",
    .requires = @"sidebarAddressBar", .apply = DPApplySidebarHideTopToolbar,
};

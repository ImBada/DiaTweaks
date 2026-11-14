#import "Toolbar.h"

// The replacement owns these invariants only while it occupies a docked sidebar.
// Other panes still satisfy Hide Toolbar's existing layout and hover contract.
NSString *DPSidebarVerifyToolbar(void) {
    NSArray<NSView *> *panes = DPFindViews(DPDiaContentPane);
    if (!panes.count) return @"no toolbar found";
    for (NSView *pane in panes) {
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        if (!bar) return @"no toolbar found";
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        BOOL replaced = DPSidebarReplacesToolbar(pane);
        if (replaced) {
            if (hover.tracking || hover.animation || hover.inPlaceAnimation || hover.peeking)
                return @"replacement still has toolbar hover or animation";
        } else if (hover.progress > 0 || hover.inPlaceProgress > 0) continue;
        if (replaced && DPSidebarToolbarIsPeeking(pane)) {
            if (bar.alphaValue < 0.99 || !NSEqualRects(bar.frame, DPSidebarToolbarBase(bar)))
                return @"toolbar did not reveal for copy feedback";
            continue;
        }
        NSView *bookmarks = replaced ? nil : DPBookmarksUnder(pane, bar);
        NSArray *bars = bookmarks ? @[bar, bookmarks] : @[bar];
        BOOL hidden = replaced || DPHideToolbar.on, found = NO;
        for (NSView *view in bars) {
            if (fabs(view.alphaValue - (hidden ? 0 : 1)) > 0.01) return @"toolbar opacity is wrong";
            if (hidden && [view hitTest:NSMakePoint(NSMidX(view.frame), NSMidY(view.frame))])
                return @"hidden toolbar still takes clicks";
            if (hidden && DPBottom(pane, view.frame) > 0.5) return @"hidden toolbar still sets the cursor";
        }
        CGFloat edge = DPBottom(pane, DPSidebarToolbarBase(bars.lastObject));
        NSArray *stack = [pane.subviews sortedArrayUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
            return [@(DPTop(pane, DPSidebarToolbarBase(a))) compare:@(DPTop(pane, DPSidebarToolbarBase(b)))];
        }];
        CGFloat shift = hidden ? edge - DPTop(pane, DPSidebarToolbarBase(bar)) : 0;
        for (NSView *view in stack) {
            NSRect laidOut = DPSidebarToolbarBase(view);
            if ([bars containsObject:view] || view.hidden || fabs(DPTop(pane, laidOut) - edge) > 0.5) continue;
            found = YES;
            if (fabs(DPTop(pane, view.frame) - (DPTop(pane, laidOut) - shift)) > 0.5)
                return @"page isn't in the toolbar's expected place";
            if (replaced && DPIsKind(view, DPDiaBookmarksBar) && view.alphaValue < 0.99)
                return @"replacement hides the bookmarks bar";
            if (fabs(DPBottom(pane, laidOut) - NSHeight(pane.bounds)) > 0.5) edge = DPBottom(pane, laidOut);
        }
        if (!found) return @"no page found below toolbar";
    }
    return nil;
}

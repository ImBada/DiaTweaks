#import "HideToolbar.h"
#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import "Patches/LittleDia/LittleDia.h"

NSHashTable<NSView *> *DPPanes;
static char DPFrameKey, DPFillsKey;

NSRect DPLaidOutFrame(NSView *view) {
    return [DPDiaValue(view, &DPFrameKey, @(view.frame)) rectValue];
}

static void DPAssignFrame(NSView *view, NSRect laidOut, NSRect frame) {
    DPOverride(view, &DPFrameKey, @(laidOut), @(frame));
    if (!NSEqualRects(view.frame, frame)) view.frame = frame;
}

CGFloat DPTop(NSView *pane, NSRect r) { return pane.isFlipped ? NSMinY(r) : NSHeight(pane.bounds) - NSMaxY(r); }
CGFloat DPBottom(NSView *pane, NSRect r) { return pane.isFlipped ? NSMaxY(r) : NSHeight(pane.bounds) - NSMinY(r); }

NSView *DPBookmarksUnder(NSView *pane, NSView *bar) {
    CGFloat barBottom = DPBottom(pane, DPLaidOutFrame(bar));
    for (NSView *sub in pane.subviews)
        if (DPIsKind(sub, DPDiaBookmarksBar) && !sub.hidden && fabs(DPTop(pane, DPLaidOutFrame(sub)) - barBottom) < 0.5) return sub;
    return nil;
}

static BOOL DPSidebarDocked(NSView *pane) {
    for (NSView *view = pane.superview; view; view = view.superview)
        if (DPIsKind(view, DPDiaContentContainer)) return DPBesideSidebar(view);
    return NO;
}

static BOOL DPShowsNewTab(NSView *pane) {
    for (NSView *sub in pane.subviews)
        for (NSView *page in sub.subviews)
            if (DPIsKind(page, DPDiaNewTabPage) && !page.hiddenOrHasHiddenAncestor) return YES;
    return NO;
}

// Only the sidebar layout has a footer, even with the sidebar hidden.
BOOL DPTabsAtTop(NSWindow *window) {
    return window && !DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSidebarFooter); });
}

BOOL DPKeptInPlace(NSView *pane) {
    return (DPShowToolbarWithSidebar.on && DPSidebarDocked(pane)) || (DPShowToolbarOnNewTab.on && DPShowsNewTab(pane)) ||
           (DPShowToolbarWithTopTabs.on && DPTabsAtTop(pane.window));
}

NSString *DPVerifyKeptInPlace(DPPatch *patch) {
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        if (!DPHideToolbar.on || !bar || bar.hiddenOrHasHiddenAncestor || hover.revealed || DPToolbarHasPermissionRequest(hover)) continue;
        BOOL kept = DPKeptInPlace(pane);
        if (kept && bar.alphaValue < 0.99) return @"toolbar stays hidden where an option keeps it";
        if (!kept && bar.alphaValue > 0.01) return @"toolbar shows where nothing keeps it";
    }
    return nil;
}

static CGFloat DPHidden(DPToolbarHover *hover) {
    return DPToolbarHasPermissionRequest(hover) ? 0 : DPHideToolbar.progress * (1 - hover.inPlaceProgress);
}

void DPApplyToolbarOpacity(DPToolbarHover *hover) {
    BOOL over = DPLittleDiaIsOver(hover.pane.window);
    CGFloat alpha = over ? 0 : 1 - DPHidden(hover) * (1 - hover.progress);
    CGFloat bookmarks = alpha;
    if (over) bookmarks = 0;
    else if (DPKeepBookmarksBar.on) bookmarks = 1;
    if (hover.bar && hover.bar.alphaValue != alpha) hover.bar.alphaValue = alpha;
    if (hover.bookmarks && hover.bookmarks.alphaValue != bookmarks) hover.bookmarks.alphaValue = bookmarks;
    DPRepaintTabs(hover.pane.window);
}

void DPApplyToolbar(NSView *pane) {
    BOOL active = DPHideToolbar.on || DPHideToolbar.progress > 0;
    DPToolbarHover *hover = [DPToolbarHover forPane:pane];
    if (!active && !hover.touched && !DPLittleDiaIsOver(pane.window)) return;
    NSView *bar = DPSubview(pane, DPDiaToolbar);
    if (!bar) return;
    if (!active && !hover.touched) {
        if (bar.alphaValue != 0) bar.alphaValue = 0;
        NSView *bookmarks = DPBookmarksUnder(pane, bar);
        if (bookmarks && bookmarks.alphaValue != 0) bookmarks.alphaValue = 0;
        return;
    }

    NSView *bookmarks = DPBookmarksUnder(pane, bar);
    BOOL keep = DPKeepBookmarksBar.on && bookmarks;
    NSView *bars[2] = {bar, bookmarks};
    NSUInteger barCount = bookmarks && !keep ? 2 : 1;
    hover = [DPToolbarHover attachToPane:pane];
    [hover updateForBar:bar bookmarks:bookmarks];

    CGFloat progress = active ? DPHidden(hover) : 0;
    DPApplyToolbarOpacity(hover);
    NSArray<NSView *> *subviews = pane.subviews;
    NSMutableArray<NSView *> *stack = [NSMutableArray arrayWithCapacity:subviews.count];
    NSUInteger firstSlot = NSNotFound, lastSlot = NSNotFound;
    for (NSUInteger i = 0; i < subviews.count; i++) {
        NSView *sub = subviews[i];
        BOOL managed = NO;
        for (NSUInteger j = 0; j < barCount; j++) if (sub == bars[j]) { managed = YES; break; }
        if (!managed) { [stack addObject:sub]; continue; }
        if (firstSlot == NSNotFound) firstSlot = i;
        lastSlot = i;
    }
    BOOL onTop = firstSlot == subviews.count - barCount, atBottom = lastSlot == barCount - 1;
    if (hover.revealed || hover.progress > 0) {
        if (!onTop) for (NSUInteger i = 0; i < barCount; i++) [pane addSubview:bars[i] positioned:NSWindowAbove relativeTo:nil];
        hover.barsLowered = NO;
    } else if (progress > 0) {
        if (!atBottom) for (NSUInteger i = barCount; i-- > 0;) [pane addSubview:bars[i] positioned:NSWindowBelow relativeTo:nil];
        hover.barsLowered = YES;
    } else if (hover.barsLowered) {
        for (NSUInteger i = 0; i < barCount; i++) [pane addSubview:bars[i] positioned:NSWindowAbove relativeTo:nil];
        hover.barsLowered = NO;
    }

    CGFloat edge = DPBottom(pane, DPLaidOutFrame(bars[barCount - 1])), shift = (edge - DPTop(pane, DPLaidOutFrame(bar))) * progress;
    // Hidden bars wait above the pane so the address field's text cursor can't reach the page.
    CGFloat lift = progress == 1 && !hover.revealed && hover.progress == 0 ? edge : 0;
    BOOL flipped = pane.isFlipped;
    for (NSUInteger i = 0; i < barCount; i++) {
        NSRect laidOut = DPLaidOutFrame(bars[i]), frame = laidOut;
        frame.origin.y += flipped ? -lift : lift;
        if (active) DPAssignFrame(bars[i], laidOut, frame);
        else {
            if (!NSEqualRects(bars[i].frame, laidOut)) bars[i].frame = laidOut;
            DPSet(bars[i], &DPFrameKey, nil);
        }
    }
    if (stack.count > 1) {
        [stack sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
            CGFloat at = DPTop(pane, DPLaidOutFrame(a)), bt = DPTop(pane, DPLaidOutFrame(b));
            if (at == bt) return NSOrderedSame;
            return at < bt ? NSOrderedAscending : NSOrderedDescending;
        }];
    }
    CGFloat paneHeight = NSHeight(pane.bounds);
    for (NSView *view in stack) {
        NSRect laidOut = DPLaidOutFrame(view);
        BOOL inColumn = fabs(DPTop(pane, laidOut) - edge) <= 0.5;
        if (!inColumn && !DPGet(view, &DPFrameKey)) continue;
        BOOL reachesBottom = inColumn && fabs(DPBottom(pane, laidOut) - paneHeight) < 0.5;
        if (inColumn && !reachesBottom) edge = DPBottom(pane, laidOut);
        NSRect frame = laidOut;
        if (inColumn && shift != 0) {
            if (reachesBottom) frame.size.height += shift;
            if (flipped) frame.origin.y -= shift;
            else if (!reachesBottom) frame.origin.y += shift;
        }
        if (active) DPAssignFrame(view, laidOut, frame);
        else {
            if (!NSEqualRects(view.frame, laidOut)) view.frame = laidOut;
            DPSet(view, &DPFrameKey, nil);
        }
        NSRect bounds = view.bounds;
        for (NSView *child in view.subviews) {
            if (active) {
                if (!DPGet(child, &DPFillsKey)) {
                    if (!NSEqualRects(child.frame, (NSRect){NSZeroPoint, laidOut.size})) continue;
                    DPSet(child, &DPFillsKey, @YES);
                }
                if (!NSEqualRects(child.frame, bounds)) child.frame = bounds;
            } else if (DPGet(child, &DPFillsKey)) {
                if (!NSEqualRects(child.frame, bounds)) child.frame = bounds;
                DPSet(child, &DPFillsKey, nil);
            }
        }
    }
    hover.touched = active;
    if (!active && !DPToolbarHasPermissionRequest(hover)) [hover detach];
}

void DPRelayoutPanes(void) { DPRelayoutViews(DPPanes); }

void DPApplyRelayoutPanes(DPPatch *patch) { DPRelayoutPanes(); }

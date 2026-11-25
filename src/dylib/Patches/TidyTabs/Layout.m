#import "TidyTabs.h"

static const CGFloat DPTidyRowHeight = 24;
static NSHashTable<NSView *> *DPTidyLists;
static char DPScrollFrameKey, DPActiveKey, DPTrackedKey;

NSScrollView *DPTidyListScroll(NSView *list) {
    for (NSView *sub in list.subviews) if ([sub isKindOfClass:NSScrollView.class]) return (NSScrollView *)sub;
    return nil;
}

static void DPTabList_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabList_layout, self);
    if (!DPGet(self, &DPTrackedKey)) {
        DPSet(self, &DPTrackedKey, @YES);
        [DPTidyLists addObject:self];
    }
    BOOL on = DPTidyTabs.on;
    if (on) {
        if (!DPGet(self, &DPActiveKey)) DPSet(self, &DPActiveKey, @YES);
    } else {
        if (!DPGet(self, &DPActiveKey)) return;
        [[DPTidyHover forList:self] detach];
        DPSet(self, &DPActiveKey, nil);
    }
    CGFloat progress = on ? [DPTidyHover attachToList:self].progress : 0;
    NSView *separator = DPTidySeparatorIn(self);
    if (separator) DPPlaceSeparatorBrush(separator);
    CGFloat inset = separator ? 0 : round(DPTidyRowHeight * progress);
    NSScrollView *scroll = DPTidyListScroll(self);
    if (!scroll) return;
    NSRect laidOut = [DPDiaValue(scroll, &DPScrollFrameKey, @(scroll.frame)) rectValue], frame = laidOut;
    inset = MIN(inset, NSHeight(laidOut));
    frame.size.height -= inset;
    if (self.isFlipped) frame.origin.y += inset;
    BOOL adjusted = NSEqualRects(scroll.frame, frame);
    if (!adjusted && DPMayAdjust(scroll)) {
        scroll.frame = frame;
        adjusted = YES;
    }
    if (inset > 0 && adjusted) DPOverride(scroll, &DPScrollFrameKey, @(laidOut), @(frame));
    else if (DPGet(scroll, &DPScrollFrameKey)) DPSet(scroll, &DPScrollFrameKey, nil);

    DPTidyRowView *row = DPTidyRowIn(self, inset > 0);
    if (!row) return;
    if (!on) return [row removeFromSuperview];
    CGFloat y = self.isFlipped ? NSMinY(laidOut) : NSMaxY(laidOut) - inset;
    row.frame = NSMakeRect(NSMinX(laidOut), y, NSWidth(laidOut), inset);
    row.alphaValue = progress;
    row.hidden = inset < 1;
}

NSArray<NSView *> *DPTidyTrackedLists(void) { return DPTidyLists.allObjects ?: @[]; }

NSRect DPTidyHoverZone(NSView *list) {
    NSScrollView *scroll = DPTidyListScroll(list);
    if (!scroll || DPTidySeparatorIn(list)) return NSZeroRect;
    NSRect laidOut = [DPDiaValue(scroll, &DPScrollFrameKey, @(scroll.frame)) rectValue];
    DPTidyRowView *row = DPTidyRowIn(list, NO);
    CGFloat open = row && !row.hidden ? NSHeight(row.frame) : 0;
    NSRect zone = NSMakeRect(NSMinX(laidOut), NSMinY(laidOut) - 6, NSWidth(laidOut), 10 + open);
    if (!list.isFlipped) zone.origin.y = NSMaxY(laidOut) - 4 - open;
    return [list convertRect:zone toView:nil];
}

void DPRelayoutTidyLists(void) { DPRelayoutViews(DPTidyLists); }

void DPInstallTidyLayout(void) {
    DPTidyLists = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaTabList, @selector(layout), (IMP)DPTabList_layout);
    DPInstallTidySeparator();
}

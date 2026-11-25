#import "TidyTabs.h"

static char DPLineFrameKey;
static const CGFloat DPCloseAllGap = 4;
static Class DPHookedCloseAll;

static CALayer *DPSeparatorLine(NSView *separator) {
    for (CALayer *layer in separator.layer.sublayers)
        if (NSHeight(layer.frame) <= 1.5 && NSWidth(layer.frame) > 20) return layer;
    return nil;
}

static NSView *DPCloseAll(NSView *separator) {
    for (NSView *sub in separator.subviews)
        if ([sub isKindOfClass:NSButton.class] && ![sub isKindOfClass:DPTidyBrush.class]) return sub;
    return nil;
}

static DPTidyBrush *DPBrushIn(NSView *separator, BOOL create) {
    for (NSView *sub in separator.subviews) if ([sub isKindOfClass:DPTidyBrush.class]) return (DPTidyBrush *)sub;
    if (!create) return nil;
    DPTidyBrush *brush = [DPTidyBrush new];
    brush.plain = YES;
    [separator addSubview:brush];
    return brush;
}

NSView *DPTidySeparatorIn(NSView *list) {
    NSScrollView *scroll = DPTidyListScroll(list);
    return scroll ? DPFindView(scroll.documentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaTabListSeparator) && !view.hiddenOrHasHiddenAncestor;
    }) : nil;
}

static void DPCloseAll_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    DPCallOriginal(DPCloseAll_setHidden, self, hidden);
    if (![self isKindOfClass:DPTidyBrush.class] && DPIsKind(self.superview, DPDiaTabListSeparator)) DPPlaceSeparatorBrush(self.superview);
}

typedef struct { NSRect frame; char kind; } DPTidyRow;
enum { DPTidyRowNoCell, DPTidyRowTab, DPTidyRowOther };

static NSInteger DPTidyLooseRows(const DPTidyRow *rows, NSUInteger count, NSInteger limit) {
    NSMutableData *scratch = [NSMutableData dataWithLength:(count + 1) * (sizeof(double) + sizeof(NSInteger) + sizeof(NSUInteger))];
    double *heights = scratch.mutableBytes;
    NSInteger *counts = (NSInteger *)(heights + count + 1);
    NSUInteger *holders = (NSUInteger *)(counts + count + 1), distinct = 0, holderCount = 0;
    CGFloat shortest = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < count; i++) {
        shortest = MIN(shortest, NSHeight(rows[i].frame));
        if (rows[i].kind != DPTidyRowTab) continue;
        double height = round(NSHeight(rows[i].frame));
        NSUInteger at = 0;
        while (at < distinct && heights[at] != height) at++;
        if (at == distinct) heights[distinct++] = height;
        counts[at]++;
    }
    if (!distinct) return 0;
    NSUInteger best = 0;
    for (NSUInteger i = 1; i < distinct; i++) if (counts[i] > counts[best]) best = i;
    // Only a row taller than the shortest one can hold another.
    for (NSUInteger i = 0; i < count; i++) if (NSHeight(rows[i].frame) > shortest + 1) holders[holderCount++] = i;
    NSInteger loose = 0;
    for (NSUInteger i = 0; i < count && loose < limit; i++) {
        NSRect frame = rows[i].frame;
        if (rows[i].kind == DPTidyRowNoCell ? fabs(NSHeight(frame) - heights[best]) > 1 : rows[i].kind != DPTidyRowTab) continue;
        NSPoint middle = NSMakePoint(NSMidX(frame), NSMidY(frame));
        BOOL inside = NO;
        for (NSUInteger h = 0; h < holderCount && !inside; h++) {
            NSRect other = rows[holders[h]].frame;
            inside = NSHeight(other) > NSHeight(frame) + 1 && NSPointInRect(middle, other);
        }
        loose += !inside;
    }
    return loose;
}

static BOOL DPRowHeldBy(NSRect frame, const DPTidyRow *rows, const NSUInteger *holders, NSUInteger holderCount) {
    NSPoint middle = NSMakePoint(NSMidX(frame), NSMidY(frame));
    for (NSUInteger h = 0; h < holderCount; h++) {
        NSRect other = rows[holders[h]].frame;
        if (NSHeight(other) > NSHeight(frame) + 1 && NSPointInRect(middle, other)) return YES;
    }
    return NO;
}

static NSInteger DPTidyConfirmedTabs(const NSRect *tabs, NSUInteger tabCount, const DPTidyRow *rows, const NSUInteger *holders,
                                     NSUInteger holderCount, CGFloat nextMinY) {
    NSInteger loose = 0;
    for (NSUInteger i = 0; i < tabCount && loose < DPTidyMinimumTabs; i++)
        if (NSMidY(tabs[i]) < nextMinY && !DPRowHeldBy(tabs[i], rows, holders, holderCount)) loose++;
    return loose;
}

// Stops counting at DPTidyMinimumTabs, which is all either caller asks.
NSInteger DPTidyTabsBelowLine(NSView *list) {
    NSCollectionView *collection = (NSCollectionView *)DPTidyListScroll(list).documentView;
    if (![collection isKindOfClass:NSCollectionView.class]) return 0;
    NSView *separator = DPTidySeparatorIn(list);
    CGFloat line = separator ? NSMaxY([collection convertRect:separator.bounds fromView:separator]) - 0.5 : -CGFLOAT_MAX;
    NSCollectionViewLayout *layout = collection.collectionViewLayout;
    NSInteger sections = collection.numberOfSections;
    NSMutableData *storage = [NSMutableData data], *holderData = [NSMutableData data];
    NSUInteger count = 0, holderCount = 0, candidateCount = 0;
    NSRect candidates[32];
    BOOL monotonic = YES;
    CGFloat lastMinY = -CGFLOAT_MAX, minSeenHeight = CGFLOAT_MAX;
    for (NSInteger section = 0; section < sections; section++) {
        NSInteger items = [collection numberOfItemsInSection:section];
        if (items <= 0) continue;
        [storage setLength:(count + (NSUInteger)items) * sizeof(DPTidyRow)];
        [holderData setLength:(holderCount + (NSUInteger)items) * sizeof(NSUInteger)];
        DPTidyRow *rows = storage.mutableBytes;
        NSUInteger *holders = holderData.mutableBytes;
        for (NSInteger item = 0; item < items; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
            NSCollectionViewLayoutAttributes *attrs = [layout layoutAttributesForItemAtIndexPath:path];
            NSRect frame = attrs.frame;
            // Folded pinned tabs move below the line hidden/fading.
            if (attrs.hidden || attrs.alpha < 1 || NSMinY(frame) < line || NSHeight(frame) <= 0) continue;
            if (NSMinY(frame) < lastMinY) monotonic = NO;
            else lastMinY = NSMinY(frame);
            if (monotonic && candidateCount >= (NSUInteger)DPTidyMinimumTabs
                && DPTidyConfirmedTabs(candidates, candidateCount, rows, holders, holderCount, NSMinY(frame)) >= DPTidyMinimumTabs)
                return DPTidyMinimumTabs;
            NSView *cell = [collection itemAtIndexPath:path].view;
            // Exclude the trailing New Tab row when off screen.
            if (!cell && section == sections - 1 && item == items - 1) continue;
            char kind = !cell ? DPTidyRowNoCell : strstr(object_getClassName(cell), "TabUI7TabView") ? DPTidyRowTab : DPTidyRowOther;
            if (NSHeight(frame) < minSeenHeight) {
                CGFloat oldMin = minSeenHeight;
                minSeenHeight = NSHeight(frame);
                for (NSUInteger prev = 0; prev < count; prev++)
                    if (NSHeight(rows[prev].frame) <= oldMin + 1 && NSHeight(rows[prev].frame) > minSeenHeight + 1) holders[holderCount++] = prev;
            }
            if (NSHeight(frame) > minSeenHeight + 1) holders[holderCount++] = count;
            rows[count++] = (DPTidyRow){frame, kind};
            if (kind == DPTidyRowTab && candidateCount < sizeof(candidates) / sizeof(*candidates)
                && !DPRowHeldBy(frame, rows, holders, holderCount))
                candidates[candidateCount++] = frame;
        }
    }
    if (monotonic && candidateCount >= (NSUInteger)DPTidyMinimumTabs
        && DPTidyConfirmedTabs(candidates, candidateCount, storage.bytes, holderData.bytes, holderCount, CGFLOAT_MAX) >= DPTidyMinimumTabs)
        return DPTidyMinimumTabs;
    return DPTidyLooseRows(storage.bytes, count, DPTidyMinimumTabs);
}

static NSView *DPListOf(NSView *view) {
    for (; view; view = view.superview) if (DPIsKind(view, DPDiaTabList)) return view;
    return nil;
}

void DPPlaceSeparatorBrush(NSView *separator) {
    DPTidyBrush *existing = DPBrushIn(separator, NO);
    if (!DPTidyTabs.on && !existing) return;
    NSView *closeAll = DPCloseAll(separator);
    if (DPTidyTabs.on && closeAll && object_getClass(closeAll) != DPHookedCloseAll) {
        DPHookedCloseAll = object_getClass(closeAll);
        DPHookClass(DPHookedCloseAll, @selector(setHidden:), (IMP)DPCloseAll_setHidden);
    }
    BOOL shown = DPTidyTabs.on && closeAll && !closeAll.hidden && (DPTidyIsBusy() || DPTidyTabsBelowLine(DPListOf(separator)) >= DPTidyMinimumTabs);
    DPTidyBrush *brush = existing ?: DPBrushIn(separator, shown);
    CALayer *line = DPSeparatorLine(separator);
    if (!brush && !line) return;
    CGFloat right = closeAll ? NSMinX(closeAll.frame) - DPCloseAllGap : NSMaxX(separator.bounds) - 7;
    if (DPTidyTabs.on) {
        NSRect target = NSMakeRect(right - DPTidyBrushSize, round(NSMidY(separator.bounds) - DPTidyBrushSize / 2), DPTidyBrushSize, DPTidyBrushSize);
        if (brush && !NSEqualRects(brush.frame, target) && DPMayAdjust(brush)) brush.frame = target;
        if (brush.hidden != !shown) brush.hidden = !shown;
    } else {
        [brush removeFromSuperview];
    }
    if (!line) return;
    NSRect dia = [DPDiaValue(line, &DPLineFrameKey, [NSValue valueWithRect:line.frame]) rectValue], frame = dia;
    CGFloat trimmed = MIN(NSWidth(dia), MAX(0, right - DPTidyBrushSize - DPTidyLineGap - NSMinX(dia)));
    if (shown) frame.size.width = trimmed;
    BOOL adjusted = NSEqualRects(line.frame, frame);
    if (!adjusted && DPMayAdjust(separator)) {
        DPWithoutAnimation(^{ line.frame = frame; });
        adjusted = YES;
    }
    if (shown && adjusted) DPOverride(line, &DPLineFrameKey, [NSValue valueWithRect:dia], [NSValue valueWithRect:frame]);
    else if (DPGet(line, &DPLineFrameKey)) DPSet(line, &DPLineFrameKey, nil);
    DPTidyWave(separator.layer, line, line.backgroundColor, DPTidyTabs.on && DPTidyIsBusy());
}

static void DPSeparator_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSeparator_layout, self);
    DPPlaceSeparatorBrush(self);
}

static void DPSeparator_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSeparator_updateLayer, self);
    CALayer *line = DPSeparatorLine(self);
    if (line) DPTidyWave(self.layer, line, line.backgroundColor, DPTidyTabs.on && DPTidyIsBusy());
}

static NSView *DPCollection_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    if (!DPTidyTabs.on) return DPCallOriginal(DPCollection_hitTest, self, point);
    for (DPTidyBrush *brush in DPTidyBrushes()) {
        if (brush.hiddenOrHasHiddenAncestor || ![brush isDescendantOf:self]) continue;
        if (NSPointInRect([brush convertPoint:point fromView:self.superview], brush.bounds)) return brush;
    }
    return DPCallOriginal(DPCollection_hitTest, self, point);
}

void DPInstallTidySeparator(void) {
    DPHook(DPDiaTabListCollection, @selector(hitTest:), (IMP)DPCollection_hitTest);
    DPHook(DPDiaTabListSeparator, @selector(layout), (IMP)DPSeparator_layout);
    DPHook(DPDiaTabListSeparator, @selector(updateLayer), (IMP)DPSeparator_updateLayer);
}

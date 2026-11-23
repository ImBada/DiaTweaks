#import "TidyTabs.h"

static char DPLineFrameKey;
static const CGFloat DPCloseAllGap = 4;

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

NSInteger DPTidyTabsBelowLine(NSView *list) {
    NSCollectionView *collection = (NSCollectionView *)DPTidyListScroll(list).documentView;
    if (![collection isKindOfClass:NSCollectionView.class]) return 0;
    NSView *separator = DPTidySeparatorIn(list);
    CGFloat line = separator ? NSMaxY([collection convertRect:separator.bounds fromView:separator]) - 0.5 : -CGFLOAT_MAX;
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    NSMutableArray<NSNumber *> *isTab = [NSMutableArray array];
    NSCountedSet<NSNumber *> *heights = [NSCountedSet set];
    for (NSInteger section = 0; section < collection.numberOfSections; section++)
        for (NSInteger item = 0; item < [collection numberOfItemsInSection:section]; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
            NSCollectionViewLayoutAttributes *attrs = [collection.collectionViewLayout layoutAttributesForItemAtIndexPath:path];
            NSRect frame = attrs.frame;
            // Folded pinned tabs move below the line hidden/fading.
            if (attrs.hidden || attrs.alpha < 1 || NSMinY(frame) < line || NSHeight(frame) <= 0) continue;
            NSView *cell = [collection itemAtIndexPath:path].view;
            BOOL tab = cell && strstr(object_getClassName(cell), "TabUI7TabView");
            // Exclude the trailing New Tab row when off screen.
            if (!cell && section == collection.numberOfSections - 1 && item == [collection numberOfItemsInSection:section] - 1) continue;
            [frames addObject:[NSValue valueWithRect:frame]];
            [isTab addObject:cell ? @(tab) : (id)NSNull.null];
            if (tab) [heights addObject:@(round(NSHeight(frame)))];
        }
    NSNumber *height = nil;
    for (NSNumber *each in heights) if (!height || [heights countForObject:each] > [heights countForObject:height]) height = each;
    if (!height) return 0;
    NSInteger loose = 0;
    for (NSUInteger i = 0; i < frames.count; i++) {
        NSRect frame = frames[i].rectValue;
        if (isTab[i] == (id)NSNull.null ? fabs(NSHeight(frame) - height.doubleValue) > 1 : !isTab[i].boolValue) continue;
        BOOL inside = NO;
        for (NSValue *other in frames)
            inside |= NSHeight(other.rectValue) > NSHeight(frame) + 1 && NSPointInRect(NSMakePoint(NSMidX(frame), NSMidY(frame)), other.rectValue);
        loose += !inside;
    }
    return loose;
}

static NSView *DPListOf(NSView *view) {
    for (; view; view = view.superview) if (DPIsKind(view, DPDiaTabList)) return view;
    return nil;
}

void DPPlaceSeparatorBrush(NSView *separator) {
    DPTidyBrush *existing = DPBrushIn(separator, NO);
    if (!DPTidyTabs.on && !existing) return;
    NSView *closeAll = DPCloseAll(separator);
    if (DPTidyTabs.on && closeAll) DPHookClass(object_getClass(closeAll), @selector(setHidden:), (IMP)DPCloseAll_setHidden);
    BOOL shown = DPTidyTabs.on && closeAll && !closeAll.hidden && (DPTidyIsBusy() || DPTidyTabsBelowLine(DPListOf(separator)) >= DPTidyMinimumTabs);
    DPTidyBrush *brush = existing ?: DPBrushIn(separator, shown);
    CALayer *line = DPSeparatorLine(separator);
    if (!brush && !line) return;
    CGFloat right = closeAll ? NSMinX(closeAll.frame) - DPCloseAllGap : NSMaxX(separator.bounds) - 7;
    if (DPTidyTabs.on) {
        NSRect target = NSMakeRect(right - DPTidyBrushSize, round(NSMidY(separator.bounds) - DPTidyBrushSize / 2), DPTidyBrushSize, DPTidyBrushSize);
        if (!NSEqualRects(brush.frame, target)) brush.frame = target;
        if (brush.hidden != !shown) brush.hidden = !shown;
    } else {
        [brush removeFromSuperview];
    }
    if (!line) return;
    NSRect dia = [DPDiaValue(line, &DPLineFrameKey, [NSValue valueWithRect:line.frame]) rectValue], frame = dia;
    CGFloat trimmed = MIN(NSWidth(dia), MAX(0, right - DPTidyBrushSize - DPTidyLineGap - NSMinX(dia)));
    if (shown) {
        frame.size.width = trimmed;
        DPOverride(line, &DPLineFrameKey, [NSValue valueWithRect:dia], [NSValue valueWithRect:frame]);
    } else if (DPGet(line, &DPLineFrameKey)) {
        DPSet(line, &DPLineFrameKey, nil);
    }
    if (!NSEqualRects(line.frame, frame)) {
        DPWithoutAnimation(^{ line.frame = frame; });
    }
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

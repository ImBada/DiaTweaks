#import "Patches/CompactTabRows/CompactTabRows.h"
#import <dlfcn.h>

extern DPPatch DPCompactTabRows;

static NSString *const DPSmallRows = @"small";
static const CGFloat DPOldRowHeight = 37, DPSmallRowHeight = 30;

static BOOL DPSmall(void) { return DPCompactTabRows.on && [DPChoice(&DPCompactTabRows) isEqual:DPSmallRows]; }

CGFloat DPCompactRowHeight(void) { return DPSmall() ? DPSmallRowHeight : DPOldRowHeight; }

// Dia's own attributes, not the moved copies Collapse Pinned Tabs returns.
static NSArray<NSCollectionViewLayoutAttributes *> *DPKeptAttributes(NSCollectionViewLayout *layout) {
    NSArray *(*elements)(id, SEL, NSRect) = (void *)DPDiaIMP(objc_getClass(DPDiaTabListLayout), @selector(layoutAttributesForElementsInRect:));
    return elements(layout, @selector(layoutAttributesForElementsInRect:), NSMakeRect(-1e5, -1e5, 2e5, 1e7));
}

CGFloat DPModalItemHeight(NSArray<NSCollectionViewLayoutAttributes *> *attributes, CGFloat minimum) {
    enum { DPKinds = 32 };
    CGFloat heights[DPKinds];
    NSUInteger counts[DPKinds], kinds = 0, best = 0;
    for (NSCollectionViewLayoutAttributes *item in attributes) {
        if (item.representedElementCategory != NSCollectionElementCategoryItem || NSHeight(item.frame) < minimum) continue;
        CGFloat height = round(NSHeight(item.frame) * 2) / 2;
        NSUInteger index = 0;
        while (index < kinds && heights[index] != height) index++;
        if (index == kinds) {
            if (kinds == DPKinds) continue;
            heights[kinds] = height;
            counts[kinds++] = 0;
        }
        if (++counts[index] > counts[best]) best = index;
    }
    return kinds ? heights[best] : 0;
}

static CGFloat DPRowHeight(NSArray<NSCollectionViewLayoutAttributes *> *all) { return DPModalItemHeight(all, 0); }

static char DPMovesKey;

typedef void (*DPHeightHandler)(double height, void *context __attribute__((swift_context))) __attribute__((swiftcall));

// Group cards size from this callback, which Dia only fires when it sets contentHeight itself.
static void DPReportHeight(NSCollectionViewLayout *layout, double height) {
    NSView *list = layout.collectionView;
    while (list && !DPIsKind(list, DPDiaTabList)) list = list.superview;
    void **handler = list ? DPIvar(list, "onPreferredHeightUpdated") : NULL;
    if (!handler || !handler[0]) return;
    static void *(*retainFn)(void *);
    static void (*releaseFn)(void *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        retainFn = dlsym(RTLD_DEFAULT, "swift_retain");
        releaseFn = dlsym(RTLD_DEFAULT, "swift_release");
    });
    void *fn = handler[0], *ctx = handler[1];
    if (ctx && retainFn) retainFn(ctx);
    ((DPHeightHandler)fn)(height + layout.collectionView.enclosingScrollView.contentInsets.top, ctx);
    if (ctx && releaseFn) releaseFn(ctx);
}

static void DPLayout_prepareLayout(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepareLayout, self);
    if (!DPCompactTabRows.on) return DPSet(self, &DPMovesKey, nil);
    double *contentHeight = DPIvar(self, "contentHeight");
    NSArray<NSCollectionViewLayoutAttributes *> *all = DPKeptAttributes(self);
    CGFloat height = DPRowHeight(all), cut = height - DPCompactRowHeight();
    if (!contentHeight || cut < 0.5) return DPSet(self, &DPMovesKey, nil);
    NSMutableArray<NSValue *> *rows = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem && NSHeight(a.frame) >= height - 0.5)
            [rows addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(a.frame), NSMinY(a.frame), NSWidth(a.frame), height)]];
    NSMutableArray<NSArray<NSValue *> *> *moves = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all) {
        NSRect frame = a.frame;
        for (NSValue *value in rows) {
            NSRect row = value.rectValue;
            // A folder's first row starts 3 pt up into its header.
            if (NSMaxY(row) <= NSMinY(a.frame) + 3.5) frame.origin.y -= cut;
            else if (NSMinY(row) >= NSMinY(a.frame) - 0.5 && NSMaxY(row) <= NSMaxY(a.frame) + 0.5) frame.size.height -= cut;
        }
        if (a.representedElementCategory == NSCollectionElementCategoryItem)
            [moves addObject:@[ [NSValue valueWithRect:frame], [NSValue valueWithRect:a.frame] ]];
        a.frame = frame;
    }
    *contentHeight -= cut * rows.count;
    DPSet(self, &DPMovesKey, moves);
    DPReportHeight(self, *contentHeight);
}

CGFloat DPTabListDiaY(NSArray<NSArray<NSValue *> *> *moves, CGFloat y) {
    NSArray<NSValue *> *inside = nil, *above = nil;
    for (NSArray<NSValue *> *move in moves) {
        NSRect now = move[0].rectValue;
        if (y >= NSMinY(now) && y < NSMaxY(now) && (!inside || NSHeight(now) < NSHeight(inside[0].rectValue))) inside = move;
        if (NSMaxY(now) <= y && (!above || NSMaxY(now) > NSMaxY(above[0].rectValue))) above = move;
    }
    if (inside) {
        NSRect now = inside[0].rectValue, then = inside[1].rectValue;
        return NSMinY(then) + (y - NSMinY(now)) * NSHeight(then) / NSHeight(now);
    }
    return above ? y - NSMaxY(above[0].rectValue) + NSMaxY(above[1].rectValue) : y;
}

@interface DPCompactDrag : NSProxy
@property (nonatomic, strong) id<NSDraggingInfo> info;
@property (nonatomic) NSPoint location;
@end

@implementation DPCompactDrag
- (NSPoint)draggingLocation { return self.location; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [(NSObject *)self.info methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.info]; }
- (BOOL)respondsToSelector:(SEL)sel { return [(NSObject *)self.info respondsToSelector:sel]; }
- (BOOL)conformsToProtocol:(Protocol *)protocol { return [(NSObject *)self.info conformsToProtocol:protocol]; }
- (BOOL)isKindOfClass:(Class)cls { return [(NSObject *)self.info isKindOfClass:cls]; }
@end

static NSPoint DPDragPointer, DPDragHanded;
static BOOL DPDragHandedSet;

id<NSDraggingInfo> DPDraggingInfoAt(id<NSDraggingInfo> info, NSPoint location) {
    DPCompactDrag *drag = [DPCompactDrag alloc];
    drag.info = info;
    drag.location = location;
    id<NSDraggingInfo> pointer = info;
    while (object_getClass(pointer) == DPCompactDrag.class) pointer = ((DPCompactDrag *)pointer).info;
    DPDragPointer = pointer.draggingLocation;
    DPDragHanded = location;
    DPDragHandedSet = YES;
    return (id<NSDraggingInfo>)drag;
}

// Dia draws the dragged tab at the proxied point; shift it back under the pointer.
void DPPlaceDraggedTab(void) {
    if (!DPDragHandedSet) return;
    DPDragHandedSet = NO;
    CGFloat up = DPDragPointer.y - DPDragHanded.y;
    if (fabs(up) < 0.5) return;
    for (NSWindow *window in NSApp.windows) {
        if (!window.visible || !strstr(object_getClassName(window), "ArcDraggingWindow")) continue;
        for (NSView *tab in window.contentView.subviews)
            [tab setFrameOrigin:NSMakePoint(NSMinX(tab.frame), NSMinY(tab.frame) + (tab.superview.isFlipped ? -up : up))];
    }
}

void DPClearDraggedTab(void) { DPDragHandedSet = NO; }

static id<NSDraggingInfo> DPDiaDrag(NSView *tabList, id<NSDraggingInfo> info) {
    if (!DPCompactTabRows.on) return info;
    NSCollectionView *list = (NSCollectionView *)DPFindView(tabList, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabListCollection); });
    NSArray *moves = DPGet(list.collectionViewLayout, &DPMovesKey);
    if (!moves) return info;
    NSPoint point = [list convertPoint:info.draggingLocation fromView:nil];
    point.y = DPTabListDiaY(moves, point.y);
    return DPDraggingInfoAt(info, [list convertPoint:point toView:nil]);
}

static NSDragOperation DPTabList_entered(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    NSDragOperation operation = DPCallOriginal(DPTabList_entered, self, DPDiaDrag(self, info));
    if (DPCompactTabRows.on) DPPlaceDraggedTab();
    return operation;
}
static NSDragOperation DPTabList_updated(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    NSDragOperation operation = DPCallOriginal(DPTabList_updated, self, DPDiaDrag(self, info));
    if (DPCompactTabRows.on) DPPlaceDraggedTab();
    return operation;
}

// Clear before a drop so its proxied point isn't applied to the next drag.
static BOOL DPDropped(BOOL result) {
    DPClearDraggedTab();
    return result;
}
static BOOL DPTabList_prepare(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPDropped(DPCallOriginal(DPTabList_prepare, self, DPDiaDrag(self, info))); }
static BOOL DPTabList_perform(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPDropped(DPCallOriginal(DPTabList_perform, self, DPDiaDrag(self, info))); }

static char DPDiaFontKey;

static BOOL DPIsRowTitle(NSView *label) {
    if (DPIsKind(label.superview, DPDiaTransitioningLabel)) return NO;
    for (NSView *view = label.superview; view; view = view.superview) if (DPIsKind(view, DPDiaTabListCollection)) return YES;
    return NO;
}

static void DPLabel_layout(NSTextField *self, SEL _cmd) {
    DPCallOriginal(DPLabel_layout, self);
    BOOL small = DPSmall();
    if ((!small && !DPGet(self, &DPDiaFontKey)) || !DPIsRowTitle(self) || !DPMayAdjust(self)) return;
    NSFont *dia = DPDiaValue(self, &DPDiaFontKey, self.font);
    if (!dia) {
        if (!small) DPSet(self, &DPDiaFontKey, nil);
        return;
    }
    NSFont *shown = small ? [NSFont fontWithDescriptor:dia.fontDescriptor size:dia.pointSize - 1] : dia;
    if ([self.font isEqual:shown]) {
        if (!small) DPSet(self, &DPDiaFontKey, nil);
        return;
    }
    DPSet(self, &DPDiaFontKey, nil);
    if (small) DPOverride(self, &DPDiaFontKey, dia, shown);
    self.font = shown;
    self.superview.needsLayout = YES;
}

static char DPHeaderYKey;

static void DPGroupCell_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGroupCell_layout, self);
    CGFloat target = DPCompactRowHeight();
    BOOL active = DPCompactTabRows.on && NSHeight(self.bounds) > target + 0.5;
    for (NSView *header in self.subviews) {
        if (DPIsKind(header, DPDiaTabGroupBackground)) continue;
        if (!active && !DPGet(header, &DPHeaderYKey)) continue;
        CGFloat diaY = [DPDiaValue(header, &DPHeaderYKey, @(NSMinY(header.frame))) doubleValue];
        CGFloat extra = NSHeight(header.frame) - (target - 3);
        BOOL shift = active && extra > 0.5 && NSHeight(header.frame) < DPOldRowHeight + 1.5 && diaY > 1;
        CGFloat wantY = shift ? diaY - extra / 2 : diaY;
        if (shift) DPOverride(header, &DPHeaderYKey, @(diaY), @(wantY));
        else if (DPGet(header, &DPHeaderYKey)) DPSet(header, &DPHeaderYKey, nil);
        if (fabs(NSMinY(header.frame) - wantY) > 0.01 && DPMayAdjust(header))
            [header setFrameOrigin:NSMakePoint(NSMinX(header.frame), wantY)];
    }
}

static id DPIvarObject(id object, const char *name) {
    void **slot = DPIvar(object, name);
    return slot ? (__bridge id)*slot : nil;
}

static CAShapeLayer *DPShapeLayerIvar(id object, const char *name) {
    id layer = DPIvarObject(object, name);
    return [layer isKindOfClass:CAShapeLayer.class] ? layer : nil;
}

static CGPathRef DPFitTabPath(CGPathRef source, CGRect box, CGFloat height) {
    CGFloat from = CGRectGetHeight(box), cut = from - height;
    if (height < from * 0.7) {
        CGRect rect = CGRectMake(CGRectGetMinX(box), CGRectGetMinY(box), CGRectGetWidth(box), height);
        CGFloat radius = MIN(10, MIN(CGRectGetWidth(rect), height) / 2);
        return CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
    }
    CGFloat midFrom = CGRectGetMinY(box) + from / 2, midTo = CGRectGetMinY(box) + height / 2;
    CGPoint (^fit)(CGPoint) = ^CGPoint(CGPoint p) {
        if (p.y < midFrom - 0.001) return CGPointMake(p.x, MIN(p.y, midTo));
        if (p.y > midFrom + 0.001) return CGPointMake(p.x, MAX(p.y - cut, midTo));
        return CGPointMake(p.x, midTo);
    };
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathApplyWithBlock(source, ^(const CGPathElement *element) {
        CGPoint *pts = element->points;
        switch (element->type) {
            case kCGPathElementMoveToPoint: {
                CGPoint p = fit(pts[0]);
                CGPathMoveToPoint(path, NULL, p.x, p.y);
                break;
            }
            case kCGPathElementAddLineToPoint: {
                CGPoint p = fit(pts[0]);
                CGPathAddLineToPoint(path, NULL, p.x, p.y);
                break;
            }
            case kCGPathElementAddQuadCurveToPoint: {
                CGPoint c = fit(pts[0]), e = fit(pts[1]);
                CGPathAddQuadCurveToPoint(path, NULL, c.x, c.y, e.x, e.y);
                break;
            }
            case kCGPathElementAddCurveToPoint: {
                CGPoint c1 = fit(pts[0]), c2 = fit(pts[1]), e = fit(pts[2]);
                CGPathAddCurveToPoint(path, NULL, c1.x, c1.y, c2.x, c2.y, e.x, e.y);
                break;
            }
            case kCGPathElementCloseSubpath:
                CGPathCloseSubpath(path);
                break;
        }
    });
    return path;
}

// TabShapeView clamps its path to 30 pt tall even inside a 27 pt Small row, clipping the bottom.
static void DPTabShape_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabShape_layout, self);
    if (!DPCompactTabRows.on) return;
    uint8_t *shape = DPIvar(self, "shape");
    if (!shape || *shape != 0) return;
    CGFloat height = NSHeight(self.bounds);
    if (height < 0.5) return;
    CAShapeLayer *shapeLayer = DPShapeLayerIvar(self, "$__lazy_storage_$_shapeLayer");
    if (!shapeLayer.path || CGPathIsEmpty(shapeLayer.path)) return;
    CGRect box = CGPathGetPathBoundingBox(shapeLayer.path);
    if (CGRectGetHeight(box) <= height + 0.5) return;
    CGPathRef path = DPFitTabPath(shapeLayer.path, box, height);
    if (!path) return;
    DPWithoutAnimation(^{
        shapeLayer.path = path;
        DPShapeLayerIvar(self, "$__lazy_storage_$_gradientBorderMaskLayer").path = path;
        CALayer *shadow = DPIvarObject(self, "$__lazy_storage_$_shadowLayer");
        if ([shadow isKindOfClass:CALayer.class]) {
            NSEdgeInsets *outsets = DPIvar(self, "horizontalShadowOutsets");
            CGAffineTransform shift = CGAffineTransformMakeTranslation(outsets ? outsets->left : 0, 0);
            CGPathRef shifted = CGPathCreateCopyByTransformingPath(path, &shift);
            shadow.shadowPath = shifted;
            CGPathRelease(shifted);
        }
        CAShapeLayer *bottomMask = DPShapeLayerIvar(self, "bottomShadowMaskLayer");
        if (bottomMask) {
            CGMutablePathRef cutout = CGPathCreateMutable();
            CGPathAddRect(cutout, NULL, bottomMask.bounds);
            CGAffineTransform shift = CGAffineTransformMakeTranslation(20, 20);
            CGPathAddPath(cutout, &shift, path);
            bottomMask.path = cutout;
            CGPathRelease(cutout);
        }
        NSView *rim = DPIvarObject(self, "rimHighlightView");
        if (rim) {
            void **slot = DPIvar(rim, "path");
            CFTypeRef old = slot ? *slot : NULL;
            if (slot && (!old || CFGetTypeID(old) == CGPathGetTypeID())) {
                *slot = (void *)CGPathRetain(path);
                if (old) CFRelease(old);
            }
            DPShapeLayerIvar(rim, "$__lazy_storage_$_shapeLayer").path = path;
            rim.needsLayout = YES;
        }
    });
    CGPathRelease(path);
}

static void DPInstallCompactTabRows(void) {
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepareLayout);
    DPHook(DPDiaTabGroupCell, @selector(layout), (IMP)DPGroupCell_layout);
    DPHook(DPDiaTabShape, @selector(layout), (IMP)DPTabShape_layout);
    DPHook(DPDiaFeatheredLabel, @selector(layout), (IMP)DPLabel_layout);
    DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
    DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
    DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
    DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);
}

static void DPCollectEvery(NSView *view, Class cls, NSMutableArray<NSView *> *out) {
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (NSView *sub in view.subviews) DPCollectEvery(sub, cls, out);
}

// Unlike DPFindViews, also hidden and minimized windows, so a toggle reaches every list.
NSArray *DPEveryView(const char *className) {
    Class cls = objc_getClass(className);
    if (!cls) return @[];
    NSMutableArray<NSView *> *out = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows) DPCollectEvery(window.contentView, cls, out);
    return out;
}

static void DPApplyCompactTabRows(DPPatch *patch) {
    for (NSCollectionView *list in DPEveryView(DPDiaTabListCollection)) [list.collectionViewLayout invalidateLayout];
    for (NSView *cell in DPEveryView(DPDiaTabGroupCell)) cell.needsLayout = YES;
    for (NSView *shape in DPEveryView(DPDiaTabShape)) shape.needsLayout = YES;
    for (NSView *label in DPEveryView(DPDiaFeatheredLabel)) {
        label.needsLayout = YES;
        [label layoutSubtreeIfNeeded];
    }
}

static NSString *DPVerifyCompactTabRows(DPPatch *patch) {
    CGFloat target = DPCompactRowHeight();
    for (NSView *view in DPFindViews(DPDiaTabListCollection)) {
        NSArray *all = DPKeptAttributes(((NSCollectionView *)view).collectionViewLayout);
        if (patch->on && DPRowHeight(all) > target + 0.5) return [NSString stringWithFormat:@"tab rows are taller than %g pt", target];
    }
    if (patch->on) {
        const char *const layers[] = { "$__lazy_storage_$_shapeLayer", "$__lazy_storage_$_gradientBorderMaskLayer", NULL };
        for (NSView *shape in DPFindViews(DPDiaTabShape)) {
            if (shape.hiddenOrHasHiddenAncestor || NSHeight(shape.bounds) < 0.5) continue;
            uint8_t *kind = DPIvar(shape, "shape");
            if (!kind || *kind != 0) continue;
            for (const char *const *name = layers; *name; name++) {
                CAShapeLayer *layer = DPShapeLayerIvar(shape, *name);
                if (layer.path && !CGPathIsEmpty(layer.path) && CGRectGetHeight(CGPathGetPathBoundingBox(layer.path)) > NSHeight(shape.bounds) + 0.5)
                    return @"a tab's shape is clipped by its row";
            }
        }
    }
    for (NSTextField *label in DPFindViews(DPDiaFeatheredLabel)) {
        if (!DPIsRowTitle(label) || label.hiddenOrHasHiddenAncestor) continue;
        if ((label.font.pointSize < ((NSFont *)DPDiaValue(label, &DPDiaFontKey, label.font)).pointSize) != DPSmall()) return @"a row's title has the wrong size";
    }
    return nil;
}

static NSMenu *DPRowSizeChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Row Size"];
    [menu addItemWithTitle:@"Compact" action:nil keyEquivalent:@""].representedObject = @"compact";
    [menu addItemWithTitle:@"Small" action:nil keyEquivalent:@""].representedObject = DPSmallRows;
    return menu;
}

DP_PATCH(DPCompactTabRows) {
    .key = @"compactTabRows",
    .order = 77,
    .section = @"Sidebar & Tab Bar",
    .title = @"Compact Tab Rows",
    .detail = @"Make the sidebar’s tabs and folders as short as before Dia 1.57, so more fit. Choose Small for rows shorter still, with smaller titles.",
    .symbol = @"rectangle.compress.vertical",
    .tint = @"systemTealColor",
    .choice = @"compactTabRowsSize",
    .defaultChoice = @"compact",
    .choices = DPRowSizeChoices,
    .classes = DPClasses(DPDiaTabListLayout, DPDiaTabListCollection, DPDiaTabList, DPDiaTabGroupCell, DPDiaTabGroupBackground, DPDiaTabShape, DPDiaFeatheredLabel, DPDiaTransitioningLabel),
    .install = DPInstallCompactTabRows,
    .apply = DPApplyCompactTabRows,
    .verify = DPVerifyCompactTabRows,
};

#import "StdPatch/StdPatch.h"
#import <objc/message.h>
#import "Patches/CompactTabRows/CompactTabRows.h"

extern DPPatch DPCollapsePinned;

static NSString *const DPCollapsedKey = @"collapsedPinned";
static const CGFloat DPRowHeight = 37, DPHeaderHeight = 28, DPRowInset = 15, DPTitleInset = 36, DPChevronInset = 11, DPGap = 8;
static NSUserDefaults *DPCollapseDefaults;
static char DPHeaderKey, DPShiftedKey, DPLastShiftKey;

static NSView *DPTabListAbove(NSView *view) {
    Class tabList = objc_getClass(DPDiaTabList);
    while (view && ![view isKindOfClass:tabList]) view = view.superview;
    return view;
}

static NSString *DPSpaceOf(NSView *list) {
    return [DPSwiftValue(DPSwiftValue(DPSwiftValue(DPTabListAbove(list), @"viewModel"), @"delegate"), @"spaceID") description];
}

static BOOL DPIsCollapsed(NSString *space) { return space && [[DPCollapseDefaults arrayForKey:DPCollapsedKey] containsObject:space]; }

static NSImage *DPSmallSymbol(NSString *name) {
    NSImageSymbolConfiguration *small = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightSemibold];
    return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:small];
}

@interface DPPinnedHeader : NSView
@property (nonatomic, copy) NSString *space;
@property (nonatomic) BOOL shown, collapsed, hovered, folding;
@property (nonatomic, strong) NSDate *springSince;
@property (nonatomic) NSInteger rows;
@property (nonatomic) CGFloat top, end, below, row;
@property (nonatomic, strong) NSImageView *pin, *chevron;
@property (nonatomic, strong) NSTextField *title;
@property (nonatomic, strong) CALayer *line;
@end

static void DPFold(NSString *space, BOOL collapsed);

@implementation DPPinnedHeader

- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.wantsLayer = YES;
    self.pin = [NSImageView imageViewWithImage:DPSmallSymbol(@"pin.fill")];
    self.chevron = [NSImageView new];
    self.title = [NSTextField labelWithString:@"Pinned"];
    self.title.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.line = [CALayer layer];
    for (NSView *view in @[ self.pin, self.title, self.chevron ]) [self addSubview:view];
    [self.layer addSublayer:self.line];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityDisclosureTriangleRole;
    self.accessibilityLabel = @"Pinned";
    self.collapsed = NO;
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)restyle {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *ink = self.hovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;
        self.pin.contentTintColor = self.chevron.contentTintColor = ink;
        self.title.textColor = ink;
        DPWithoutAnimation(^{ self.line.backgroundColor = NSColor.separatorColor.CGColor; });
    }];
    self.accessibilityValue = self.collapsed ? @0 : @1;
}

- (void)layout {
    [super layout];
    NSRect bounds = self.bounds;
    CGFloat middle = round(NSMidY(bounds));
    [self.title sizeToFit];
    self.pin.frame = NSMakeRect(DPRowInset, middle - 8, 16, 16);
    self.title.frame = NSMakeRect(DPTitleInset - 2, middle - round(NSHeight(self.title.frame) / 2), NSWidth(self.title.frame), NSHeight(self.title.frame));
    self.chevron.frame = NSMakeRect(NSMaxX(bounds) - DPChevronInset - 12, middle - 6, 12, 12);
    CGFloat left = NSMaxX(self.title.frame) + DPGap, right = NSMinX(self.chevron.frame) - DPGap;
    DPWithoutAnimation(^{ self.line.frame = NSMakeRect(left, middle - 0.5, MAX(0, right - left), 1); });
    [self restyle];
}

- (void)setCollapsed:(BOOL)collapsed {
    if (_collapsed == collapsed && self.chevron.image) return;
    _collapsed = collapsed;
    self.chevron.image = DPSmallSymbol(collapsed ? @"chevron.right" : @"chevron.down");
    DPWithoutAnimation(^{ self.line.opacity = collapsed ? 0 : 1; });
    [self restyle];
}

- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {
    if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds)) DPFold(self.space, !self.collapsed);
}
- (BOOL)accessibilityPerformPress { DPFold(self.space, !self.collapsed); return YES; }
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; [self restyle]; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; [self restyle]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self restyle]; }
@end

static void DPHideHeader(DPPinnedHeader *header) {
    header.shown = NO;
    header.hidden = YES;
}

typedef NSCollectionViewLayoutAttributes *(*DPItemIMP)(id, SEL, NSIndexPath *);

static DPItemIMP DPDiaItemIMP(void) {
    return (DPItemIMP)DPDiaIMP(objc_getClass(DPDiaTabListLayout), @selector(layoutAttributesForItemAtIndexPath:));
}

static void DPMeasure(NSCollectionViewLayout *layout) {
    NSCollectionView *list = layout.collectionView;
    DPPinnedHeader *header = DPGet(list, &DPHeaderKey);
    if (!DPCollapsePinned.on) {
        DPHideHeader(header);
        header.springSince = nil;
        return;
    }
    if (!DPIsKind(list, DPDiaTabListCollection)) return;
    NSInteger rows = list.numberOfSections ? [list numberOfItemsInSection:0] - 1 : 0;
    BOOL shown = rows > 0;
    NSRect first = NSZeroRect, line = NSZeroRect;
    CGFloat row = DPRowHeight;
    if (shown) {
        // Dia's own IMPs, so frozen or parked rows never feed shifted frames back into header.top.
        SEL itemSel = @selector(layoutAttributesForItemAtIndexPath:), elementsSel = @selector(layoutAttributesForElementsInRect:);
        DPItemIMP rawItem = DPDiaItemIMP();
        NSArray *(*rawElements)(id, SEL, NSRect) = (void *)DPDiaIMP(objc_getClass(DPDiaTabListLayout), elementsSel);
        first = rawItem ? rawItem(layout, itemSel, [NSIndexPath indexPathForItem:0 inSection:0]).frame : NSZeroRect;
        line = rawItem ? rawItem(layout, itemSel, [NSIndexPath indexPathForItem:rows inSection:0]).frame : NSZeroRect;
        CGFloat common = rawElements ? DPModalItemHeight(rawElements(layout, elementsSel, NSMakeRect(-1e5, -1e5, 2e5, 1e7)), 20) : 0;
        if (common) row = common;
        shown = NSHeight(line) > 0 && NSHeight(line) < 20;
    }
    if (!shown) return DPHideHeader(header);
    if (!header) {
        header = [DPPinnedHeader new];
        DPSet(list, &DPHeaderKey, header);
    }
    if (header.superview != list) [list addSubview:header];
    NSString *space = DPSpaceOf(list);
    if (space) header.space = space;
    header.collapsed = DPIsCollapsed(header.space);
    header.shown = YES;
    header.hidden = NO;
    header.rows = rows;
    header.top = NSMinY(first);
    header.end = NSMinY(line);
    header.below = NSMaxY(line);
    header.row = row;
    header.frame = NSMakeRect(0, header.top, NSWidth(list.bounds), DPHeaderHeight);
    header.needsLayout = YES;
}

static DPPinnedHeader *DPShownHeader(NSCollectionViewLayout *layout) {
    if (!DPCollapsePinned.on) return nil;
    DPPinnedHeader *header = DPGet(layout.collectionView, &DPHeaderKey);
    return header.shown ? header : nil;
}

static CGFloat DPShift(DPPinnedHeader *header, BOOL pinned) {
    return pinned || !header.collapsed ? DPHeaderHeight : DPHeaderHeight - (header.end - header.top);
}

static NSCollectionViewLayoutAttributes *DPDiaItem(NSCollectionViewLayout *layout, NSIndexPath *path) {
    DPItemIMP item = DPDiaItemIMP();
    return item ? item(layout, @selector(layoutAttributesForItemAtIndexPath:), path) : nil;
}

// Dia can rebuild its cache without our hooks, so a shifted row carries a mark.
static BOOL DPIsShifted(NSCollectionViewLayoutAttributes *attributes) { return DPGet(attributes, &DPShiftedKey) != nil; }

static BOOL DPIsAligned(NSCollectionViewLayout *layout) { return DPIsShifted(DPDiaItem(layout, [NSIndexPath indexPathForItem:0 inSection:0])); }

static void DPNudgeOverflow(NSCollectionView *list) {
    NSView *tabList = DPTabListAbove(list);
    SEL scrolled = NSSelectorFromString(@"scrollViewDidScroll");
    if (!tabList || ![tabList respondsToSelector:scrolled]) return;
    __weak NSView *weak = tabList;
    dispatch_async(dispatch_get_main_queue(), ^{ if (weak) ((void (*)(id, SEL))objc_msgSend)(weak, scrolled); });
}

// Dia reads its cached rows directly rather than through our hooks, so the cache moves with the list, as Compact Tab Rows does.
static NSNumber *DPAlign(NSCollectionViewLayout *layout) {
    DPPinnedHeader *header = DPShownHeader(layout);
    double *height = DPIvar(layout, "contentHeight");
    if (!header || !height) return nil;
    NSCollectionView *list = layout.collectionView;
    if (!DPIsAligned(layout)) {
        DPItemIMP item = DPDiaItemIMP();
        for (NSInteger section = 0; section < list.numberOfSections; section++)
            for (NSInteger row = 0, count = [list numberOfItemsInSection:section]; row < count; row++) {
                NSCollectionViewLayoutAttributes *attributes = item ? item(layout, @selector(layoutAttributesForItemAtIndexPath:), [NSIndexPath indexPathForItem:row inSection:section]) : nil;
                if (!attributes) continue;
                attributes.frame = NSOffsetRect(attributes.frame, 0, DPShift(header, section == 0 && row < header.rows));
                DPSet(attributes, &DPShiftedKey, @YES);
            }
        *height = MAX(0, *height + DPShift(header, NO));
    }
    return @(DPShift(header, NO));
}

static NSCollectionViewLayoutAttributes *DPMoved(DPPinnedHeader *header, NSCollectionViewLayoutAttributes *attributes) {
    if (!attributes) return nil;
    BOOL pinned = attributes.indexPath.section == 0 && attributes.indexPath.item < header.rows, shifted = DPIsShifted(attributes);
    attributes = [attributes copy];
    if (!shifted) {
        NSRect frame = attributes.frame;
        frame.origin.y += DPShift(header, pinned);
        attributes.frame = frame;
    }
    if (pinned && header.collapsed) {
        attributes.alpha = 0;
        attributes.hidden = !header.folding;
    }
    return attributes;
}

static void DPLayout_prepare(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepare, self);
    DPMeasure(self);
    NSNumber *was = DPGet(self, &DPLastShiftKey), *now = DPAlign(self);
    DPSet(self, &DPLastShiftKey, now);
    // Dia judged the active tab against the rows before the shift, and judges again only when something moves.
    if ((was || now) && ![was isEqual:now]) DPNudgeOverflow(self.collectionView);
}

static NSCollectionViewLayoutAttributes *DPLayout_item(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    DPPinnedHeader *header = DPShownHeader(self);
    NSCollectionViewLayoutAttributes *attributes = DPCallOriginal(DPLayout_item, self, path);
    return header ? DPMoved(header, attributes) : attributes;
}

static NSArray *DPLayout_elements(NSCollectionViewLayout *self, SEL _cmd, NSRect rect) {
    DPPinnedHeader *header = DPShownHeader(self);
    if (!header) return DPCallOriginal(DPLayout_elements, self, rect);
    CGFloat reach = DPIsAligned(self) ? 0 : header.end - header.top + DPHeaderHeight;
    NSMutableArray *moved = [NSMutableArray array];
    for (NSCollectionViewLayoutAttributes *attributes in DPCallOriginal(DPLayout_elements, self, NSInsetRect(rect, 0, -reach))) {
        NSCollectionViewLayoutAttributes *each = DPMoved(header, attributes);
        // The list keeps a view for a hidden row, still under the pointer, unless the row is left out.
        if (NSIntersectsRect(each.frame, rect) && !each.hidden) [moved addObject:each];
    }
    return moved;
}

static NSSize DPLayout_size(NSCollectionViewLayout *self, SEL _cmd) {
    DPPinnedHeader *header = DPShownHeader(self);
    NSSize size = DPCallOriginal(DPLayout_size, self);
    if (header && !DPIsAligned(self)) size.height += DPShift(header, NO);
    return size;
}

static NSView *DPList_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    if (!DPCollapsePinned.on) return DPCallOriginal(DPList_hitTest, self, point);
    DPPinnedHeader *header = DPGet(self, &DPHeaderKey);
    if (header.shown && !header.hidden && NSPointInRect([self convertPoint:point fromView:self.superview], header.frame)) return header;
    return DPCallOriginal(DPList_hitTest, self, point);
}

// Dia pins a tab dropped above the middle of the first tab after its line, so folded, that band and the header take no drops.
static BOOL DPDiaPoint(NSCollectionView *list, NSPoint *inWindow) {
    DPPinnedHeader *header = DPGet(list, &DPHeaderKey);
    if (!header.shown || header.hidden) return YES;
    NSPoint point = [list convertPoint:*inWindow fromView:nil];
    BOOL onHeader = point.y >= header.top && point.y < header.top + DPHeaderHeight;
    if (onHeader && !header.collapsed) point.y = header.top;
    else if (point.y >= header.top) point.y -= DPShift(header, NO);
    if (header.collapsed && (onHeader || (point.y >= header.end && point.y < header.below + header.row / 2))) return NO;
    *inWindow = [list convertPoint:point toView:nil];
    return YES;
}

static NSCollectionView *DPListIn(NSView *tabList) {
    return (NSCollectionView *)DPFindView(tabList, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabListCollection); });
}

static id<NSDraggingInfo> DPDiaDragOf(NSView *tabList, id<NSDraggingInfo> info) {
    NSCollectionView *list = DPListIn(tabList);
    NSPoint location = info.draggingLocation;
    if (list && !DPDiaPoint(list, &location)) return nil;
    if (NSEqualPoints(location, info.draggingLocation)) return info;
    return DPDraggingInfoAt(info, location);
}

static void DPSpringOpen(NSView *tabList, id<NSDraggingInfo> info) {
    NSCollectionView *list = DPListIn(tabList);
    DPPinnedHeader *header = DPGet(list, &DPHeaderKey);
    NSPoint point = [list convertPoint:info.draggingLocation fromView:nil];
    BOOL over = header.shown && header.collapsed && point.y >= header.top && point.y < header.top + DPHeaderHeight;
    if (!over) header.springSince = nil;
    else if (!header.springSince) header.springSince = NSDate.date;
    else if (-header.springSince.timeIntervalSinceNow > 0.6) {
        header.springSince = nil;
        DPFold(header.space, NO);
    }
}

static char DPRefusedKey;

static NSDragOperation DPTabList_entered(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    if (!DPCollapsePinned.on) {
        if (DPGet(self, &DPRefusedKey)) DPSet(self, &DPRefusedKey, nil);
        return DPCallOriginal(DPTabList_entered, self, info);
    }
    id<NSDraggingInfo> dia = DPDiaDragOf(self, info);
    DPSet(self, &DPRefusedKey, dia ? nil : @YES);
    if (!dia) return NSDragOperationNone;
    NSDragOperation operation = DPCallOriginal(DPTabList_entered, self, dia);
    DPPlaceDraggedTab();
    return operation;
}

static NSDragOperation DPTabList_updated(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    if (!DPCollapsePinned.on) {
        if (!DPGet(self, &DPRefusedKey)) return DPCallOriginal(DPTabList_updated, self, info);
        DPSet(self, &DPRefusedKey, nil);
        return [(id<NSDraggingDestination>)self draggingEntered:info];
    }
    DPSpringOpen(self, info);
    id<NSDraggingInfo> dia = DPDiaDragOf(self, info);
    BOOL refused = [DPGet(self, &DPRefusedKey) boolValue];
    if (!dia) {
        if (!refused) [(id<NSDraggingDestination>)self draggingExited:info];
        DPSet(self, &DPRefusedKey, @YES);
        return NSDragOperationNone;
    }
    if (refused) return [(id<NSDraggingDestination>)self draggingEntered:info];
    NSDragOperation operation = DPCallOriginal(DPTabList_updated, self, dia);
    DPPlaceDraggedTab();
    return operation;
}

static void DPTabList_exited(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    BOOL refused = [DPGet(self, &DPRefusedKey) boolValue];
    if (refused) DPSet(self, &DPRefusedKey, nil);
    DPPinnedHeader *header = DPGet(DPListIn(self), &DPHeaderKey);
    if (header) header.springSince = nil;
    if (!refused) DPCallOriginal(DPTabList_exited, self, info);
    DPClearDraggedTab();
}

static BOOL DPTabList_prepare(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    if (DPGet(self, &DPRefusedKey)) DPSet(self, &DPRefusedKey, nil);
    if (!DPCollapsePinned.on) return DPCallOriginal(DPTabList_prepare, self, info);
    id<NSDraggingInfo> dia = DPDiaDragOf(self, info);
    BOOL ok = dia && DPCallOriginal(DPTabList_prepare, self, dia);
    DPClearDraggedTab();
    return ok;
}

static BOOL DPTabList_perform(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    if (DPGet(self, &DPRefusedKey)) DPSet(self, &DPRefusedKey, nil);
    if (!DPCollapsePinned.on) return DPCallOriginal(DPTabList_perform, self, info);
    id<NSDraggingInfo> dia = DPDiaDragOf(self, info);
    BOOL ok = dia && DPCallOriginal(DPTabList_perform, self, dia);
    DPClearDraggedTab();
    return ok;
}

static void DPTabList_backgroundDoubleClick(NSView *self, SEL _cmd, NSGestureRecognizer *click) {
    if (DPCollapsePinned.on) {
        DPPinnedHeader *header = DPGet(DPListIn(self), &DPHeaderKey);
        if (header.shown && !header.hidden && NSPointInRect([click locationInView:header.superview], header.frame)) return;
    }
    DPCallOriginal(DPTabList_backgroundDoubleClick, self, click);
}

static NSArray<NSCollectionView *> *DPListsOf(NSString *space) {
    return (NSArray<NSCollectionView *> *)[DPFindViews(DPDiaTabListCollection) filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSView *list, id _) {
        return [[DPGet(list, &DPHeaderKey) space] isEqual:space];
    }]];
}

static void DPFold(NSString *space, BOOL collapsed) {
    if (!space) return;
    NSArray<NSCollectionView *> *lists = DPListsOf(space);
    // The folded rows get views first, unseen where they fold to, so they can animate out from there.
    for (NSCollectionView *list in lists) {
        [DPGet(list, &DPHeaderKey) setFolding:YES];
        [list.collectionViewLayout invalidateLayout];
        [list layoutSubtreeIfNeeded];
    }
    NSMutableArray *folded = [[DPCollapseDefaults arrayForKey:DPCollapsedKey] ?: @[] mutableCopy];
    [folded removeObject:space];
    if (collapsed) [folded addObject:space];
    [DPCollapseDefaults setObject:folded forKey:DPCollapsedKey];
    for (NSCollectionView *list in lists)
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.25;
            context.allowsImplicitAnimation = YES;
            [list.animator performBatchUpdates:^{ [list.collectionViewLayout invalidateLayout]; } completionHandler:^(BOOL _) {
                [DPGet(list, &DPHeaderKey) setFolding:NO];
                [list.collectionViewLayout invalidateLayout];
            }];
        }];
}

static void DPCollectAllLists(NSView *view, Class cls, NSMutableArray<NSCollectionView *> *out) {
    if ([view isKindOfClass:cls]) [out addObject:(NSCollectionView *)view];
    for (NSView *sub in view.subviews) DPCollectAllLists(sub, cls, out);
}

static NSArray<NSCollectionView *> *DPAllTabLists(void) {
    Class cls = objc_getClass(DPDiaTabListCollection);
    if (!cls) return @[];
    NSMutableArray<NSCollectionView *> *out = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows) DPCollectAllLists(window.contentView, cls, out);
    return out;
}

static void DPApplyCollapsePinned(DPPatch *patch) {
    for (NSCollectionView *list in DPAllTabLists()) {
        [list.collectionViewLayout invalidateLayout];
        if (!patch->on) {
            DPPinnedHeader *header = DPGet(list, &DPHeaderKey);
            DPHideHeader(header);
            header.springSince = nil;
        }
    }
}

static NSString *DPVerifyCollapsePinned(DPPatch *patch) {
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        if (list.hiddenOrHasHiddenAncestor || !list.numberOfSections) continue;
        DPPinnedHeader *header = DPGet(list, &DPHeaderKey);
        BOOL showing = header.superview == list && !header.hidden;
        if (!patch->on && showing) return @"a Pinned header is showing";
        if (!patch->on || !header.shown) continue;
        if (!showing) return @"the Pinned header is missing";
        NSRect first = [list.collectionViewLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame;
        if (!header.collapsed && NSMinY(first) < NSMaxY(header.frame) - 0.5) return @"a pinned row is under the Pinned header";
        NSCollectionViewLayoutAttributes *line = DPDiaItem(list.collectionViewLayout, [NSIndexPath indexPathForItem:header.rows inSection:0]);
        if (line && DPIsAligned(list.collectionViewLayout) && fabs(NSMinY(line.frame) - (header.end + DPShift(header, NO))) > 0.5) return @"Dia's own rows aren't where the list shows them";
    }
    return nil;
}

static void DPInstallCollapsePinned(void) {
    DPCollapseDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepare);
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForItemAtIndexPath:), (IMP)DPLayout_item);
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForElementsInRect:), (IMP)DPLayout_elements);
    DPHook(DPDiaTabListLayout, @selector(collectionViewContentSize), (IMP)DPLayout_size);
    DPHook(DPDiaTabListCollection, @selector(hitTest:), (IMP)DPList_hitTest);
    DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
    DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
    DPHook(DPDiaTabList, @selector(draggingExited:), (IMP)DPTabList_exited);
    DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
    DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);
    DPHook(DPDiaTabList, @selector(handleBackgroundDoubleClick:), (IMP)DPTabList_backgroundDoubleClick);
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidDeminiaturizeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (DPCollapsePinned.on) for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) [list.collectionViewLayout invalidateLayout];
    }];
}

DP_PATCH(DPCollapsePinned) {
    .key = @"collapsePinned",
    .order = 83,
    .title = @"Collapse Pinned Tabs",
    .detail = @"Add a Pinned line above your pinned tabs and folders in the sidebar. Click it to fold them away, like in Arc, and again to bring them back. Each profile remembers which way you left it.",
    .symbol = @"pin.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .group = @"pinnedTabs",
    .classes = DPClasses(DPDiaTabListCollection, DPDiaTabListLayout),
    .install = DPInstallCollapsePinned,
    .apply = DPApplyCollapsePinned,
    .verify = DPVerifyCollapsePinned,
};

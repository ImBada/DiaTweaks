#import "StdPatch/StdPatch.h"

extern DPPatch DPHideSleepingTabs;

static id DPState(id viewModel) { return DPSwiftValue(DPSwiftValue(viewModel, @"stateSubject"), @"currentValue"); }

static NSArray<NSString *> *DPSwitcherItems(id viewModel) {
    return DPUUIDsIn([DPSwiftValue(DPState(viewModel), @"items") description]);
}

static NSSet<NSString *> *DPSleepingTabs(id viewModel) {
    NSDictionary *tabs = DPSwiftValue(DPSwiftValue(viewModel, @"delegate"), @"recentTabControllers");
    NSMutableSet *sleeping = [NSMutableSet new];
    for (id tab in tabs) {
        NSString *state = [DPState(DPSwiftValue(tabs[tab], @"viewModel")) description];
        if (state && ![state containsString:@"snapshot: Optional("]) [sleeping addObject:[tab description]];
    }
    return sleeping;
}

static __weak id DPShownList;
static NSArray<NSNumber *> *DPShownCache;

// Reading the switcher's Swift state is slow and Dia asks once per cell, so a count or a resize reads it and the cells in that run loop turn reuse it.
static NSArray<NSNumber *> *DPShownItems(id list, BOOL reread) {
    if (!reread && DPShownList == list && DPShownCache) return DPShownCache.count ? DPShownCache : nil;
    id viewModel = DPSwiftValue(list, @"viewModel");
    NSSet *sleeping = DPHideSleepingTabs.on ? DPSleepingTabs(viewModel) : nil;
    NSMutableArray *shown = [NSMutableArray new];
    [DPSwitcherItems(viewModel) enumerateObjectsUsingBlock:^(NSString *tab, NSUInteger i, BOOL *stop) {
        if (![sleeping containsObject:tab]) [shown addObject:@(i)];
    }];
    if (!DPShownCache) dispatch_async(dispatch_get_main_queue(), ^{ DPShownCache = nil; });
    DPShownList = list;
    DPShownCache = shown;
    return shown.count ? shown : nil;
}

static NSIndexPath *DPDiaIndexPath(id list, NSIndexPath *path) {
    NSArray<NSNumber *> *shown = DPShownItems(list, NO);
    return shown && path.item < (NSInteger)shown.count ? [NSIndexPath indexPathForItem:shown[path.item].integerValue inSection:path.section] : path;
}

static void DPWatchSwitcherSize(id list);
static void DPHookGlobals(void);

static NSInteger DPList_count(id self, SEL _cmd, NSCollectionView *view, NSInteger section) {
    if (!DPHideSleepingTabs.on) return DPCallOriginal(DPList_count, self, view, section);
    DPHookGlobals();
    DPWatchSwitcherSize(self);
    NSArray *shown = DPShownItems(self, YES);
    return shown ? (NSInteger)shown.count : DPCallOriginal(DPList_count, self, view, section);
}

// Dia requests cells at its own index, which can be past the end of the shorter grid.
static NSCollectionView *DPShownGrid;
static NSIndexPath *DPShownPath;

static NSCollectionViewItem *DPList_item(id self, SEL _cmd, NSCollectionView *view, NSIndexPath *path) {
    if (!DPHideSleepingTabs.on) return DPCallOriginal(DPList_item, self, view, path);
    DPHookGlobals();
    NSCollectionView *prevGrid = DPShownGrid;
    NSIndexPath *prevPath = DPShownPath;
    DPShownGrid = view;
    DPShownPath = path;
    NSCollectionViewItem *item = DPCallOriginal(DPList_item, self, view, DPDiaIndexPath(self, path));
    DPShownGrid = prevGrid;
    DPShownPath = prevPath;
    return item;
}

static NSCollectionViewItem *DPGrid_makeItem(NSCollectionView *self, SEL _cmd, NSUserInterfaceItemIdentifier identifier, NSIndexPath *path) {
    return DPCallOriginal(DPGrid_makeItem, self, identifier, self == DPShownGrid && DPShownPath ? DPShownPath : path);
}

static NSSize DPList_size(id self, SEL _cmd, NSCollectionView *view, NSCollectionViewLayout *layout, NSIndexPath *path) {
    if (!DPHideSleepingTabs.on) return DPCallOriginal(DPList_size, self, view, layout, path);
    return DPCallOriginal(DPList_size, self, view, layout, DPDiaIndexPath(self, path));
}

static void DPList_select(id self, SEL _cmd, NSCollectionView *view, NSSet<NSIndexPath *> *paths) {
    if (!DPHideSleepingTabs.on) return DPCallOriginal(DPList_select, self, view, paths);
    NSMutableSet *dia = [NSMutableSet new];
    for (NSIndexPath *path in paths) [dia addObject:DPDiaIndexPath(self, path)];
    DPCallOriginal(DPList_select, self, view, dia);
}

static const CGFloat DPSwitcherChrome = 152;
static NSMapTable<NSLayoutConstraint *, id> *DPWatchedSizes;
static BOOL DPFitting;

static CGFloat DPFittedConstant(NSLayoutConstraint *size, CGFloat proposed, id list) {
    NSCollectionView *grid = DPSwiftValue(list, @"collectionView");
    NSArray *shown = DPHideSleepingTabs.on ? DPShownItems(list, YES) : nil;
    if (!grid || !shown) return proposed;
    NSSize cell = [list collectionView:grid layout:grid.collectionViewLayout sizeForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    BOOL width = size.firstAttribute == NSLayoutAttributeWidth;
    CGFloat step = width ? cell.width : cell.height;
    if (step <= 0) return proposed;
    NSInteger dia = MAX(1, lround((proposed - DPSwitcherChrome) / step));
    NSInteger maxColumns = dia;
    if (!width && cell.width > 0) {
        NSView *content = size.firstItem;
        for (NSLayoutConstraint *other in content.constraints) {
            if (other.firstItem == content && !other.secondItem && other.firstAttribute == NSLayoutAttributeWidth) {
                maxColumns = MAX(1, lround((other.constant - DPSwitcherChrome) / cell.width));
                break;
            }
        }
    }
    NSInteger columns = MIN((NSInteger)shown.count, maxColumns);
    NSInteger fit = width ? columns : MIN(dia, ((NSInteger)shown.count + columns - 1) / columns);
    return DPSwitcherChrome + fit * step;
}

static void DPFitSwitcherSize(NSLayoutConstraint *size, id list) {
    if (DPFitting || !DPHideSleepingTabs.on) return;
    CGFloat fitted = DPFittedConstant(size, size.constant, list);
    if (fabs(fitted - size.constant) < 0.5) return;
    DPFitting = YES;
    size.constant = fitted;
    DPFitting = NO;
}

static void DPConstraint_setConstant(NSLayoutConstraint *self, SEL _cmd, CGFloat constant) {
    id list = !DPFitting && DPHideSleepingTabs.on && DPWatchedSizes.count ? [DPWatchedSizes objectForKey:self] : nil;
    if (list) {
        DPFitting = YES;
        constant = DPFittedConstant(self, constant, list);
        DPFitting = NO;
    }
    DPCallOriginal(DPConstraint_setConstant, self, constant);
    if (list && self.firstAttribute == NSLayoutAttributeWidth) {
        NSView *content = self.firstItem;
        for (NSLayoutConstraint *other in content.constraints)
            if (other.firstItem == content && !other.secondItem && other.firstAttribute == NSLayoutAttributeHeight && [DPWatchedSizes objectForKey:other])
                DPFitSwitcherSize(other, list);
    }
}

static void DPWatchSwitcherSize(id list) {
    NSView *content = [list view];
    for (NSLayoutConstraint *size in content.constraints) {
        BOOL dimension = size.firstAttribute == NSLayoutAttributeWidth || size.firstAttribute == NSLayoutAttributeHeight;
        if (size.firstItem != content || size.secondItem || !dimension || [DPWatchedSizes objectForKey:size]) continue;
        [DPWatchedSizes setObject:list forKey:size];
        __weak NSLayoutConstraint *weakSize = size;
        __weak id weakList = list;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLayoutConstraint *s = weakSize;
            id l = weakList;
            if (s && l) DPFitSwitcherSize(s, l);
        });
    }
}

static int DPStepsLeft;
static const int64_t DPOwnKey = 0x44505353;

static void DPStepPastSleeping(void);

static void DPStepSoon(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPStepPastSleeping(); });
}

static void DPStepPastSleeping(void) {
    if (!DPHideSleepingTabs.on || !(NSEvent.modifierFlags & NSEventModifierFlagControl) || DPStepsLeft <= 0) {
        DPStepsLeft = 0;
        return;
    }
    NSWindowController *switcher = DPOpenTabSwitcher();
    id viewModel = DPSwiftValue(switcher, @"viewModel");
    NSString *focused = [DPSwiftValue(DPState(viewModel), @"focusedItemID") description];
    BOOL sleeping = focused && [DPSleepingTabs(viewModel) containsObject:focused];
    if (sleeping) {
        NSEventModifierFlags mods = NSEventModifierFlagControl | (NSEvent.modifierFlags & NSEventModifierFlagShift);
        NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:switcher.window.windowNumber context:nil characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48];
        CGEventRef tagged = key.CGEvent ? CGEventCreateCopy(key.CGEvent) : NULL;
        if (tagged) CGEventSetIntegerValueField(tagged, kCGEventSourceUserData, DPOwnKey);
        [NSApp postEvent:tagged ? [NSEvent eventWithCGEvent:tagged] : key atStart:NO];
        if (tagged) CFRelease(tagged);
    }
    DPStepsLeft = focused && !sleeping ? 0 : DPStepsLeft - 1;
    if (DPStepsLeft > 0) DPStepSoon();
}

// Every collection view and constraint in Dia passes through these, so they hook once the switcher first needs them.
static void DPHookGlobals(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DPHookClass(NSCollectionView.class, @selector(makeItemWithIdentifier:forIndexPath:), (IMP)DPGrid_makeItem);
        DPHookClass(NSLayoutConstraint.class, @selector(setConstant:), (IMP)DPConstraint_setConstant);
    });
}

static id DPTabKeyMonitor;

static void DPApplyHideSleepingTabs(DPPatch *patch) {
    DPSyncMonitor(&DPTabKeyMonitor, patch->on, NSEventMaskKeyDown, ^NSEvent *(NSEvent *event) {
        if (!DPHideSleepingTabs.on || event.keyCode != 48 || !(event.modifierFlags & NSEventModifierFlagControl)) return event;
        if (event.CGEvent && CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceUserData) == DPOwnKey) return event;
        BOOL running = DPStepsLeft > 0;
        DPStepsLeft = 20;
        if (!running) DPStepSoon();
        return event;
    });
}

static void DPInstallHideSleepingTabs(void) {
    DPWatchedSizes = [NSMapTable weakToWeakObjectsMapTable];
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:numberOfItemsInSection:), (IMP)DPList_count);
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:itemForRepresentedObjectAtIndexPath:), (IMP)DPList_item);
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:layout:sizeForItemAtIndexPath:), (IMP)DPList_size);
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:didSelectItemsAtIndexPaths:), (IMP)DPList_select);
    DPApplyHideSleepingTabs(&DPHideSleepingTabs);
}

DP_PATCH(DPHideSleepingTabs) {
    .key = @"hideSleepingTabs",
    .order = 86,
    .title = @"Hide Sleeping Tabs",
    .detail = @"Leave tabs with nothing loaded, like a pinned tab you closed, out of the tab switcher (⌃⇥) instead of showing them as empty pictures.",
    .symbol = @"moon.zzz.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabSwitcher, DPDiaTabSwitcherList),
    .install = DPInstallHideSleepingTabs,
    .apply = DPApplyHideSleepingTabs,
};

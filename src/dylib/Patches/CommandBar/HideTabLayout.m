#import "Patches/CommandBar/HideTab.h"

static char DPFrozenKey, DPFrozenSizeKey, DPFrozenCountKey;
static _Thread_local BOOL DPInTransition;

static NSCollectionViewLayoutAttributes *DPLayout_item(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path);

NSRect DPDiaRowFrame(NSCollectionViewLayout *layout, NSIndexPath *path) {
    SEL sel = @selector(layoutAttributesForItemAtIndexPath:);
    return ((NSCollectionViewLayoutAttributes * (*)(id, SEL, NSIndexPath *)) DPOriginalIMP(layout, sel, (IMP)DPLayout_item))(layout, sel, path).frame;
}

static NSInteger DPItemCount(NSCollectionView *list) {
    NSInteger count = 0;
    for (NSInteger section = 0; section < list.numberOfSections; section++) count += [list numberOfItemsInSection:section];
    return count;
}

void DPFreezeLists(NSWindow *window) {
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        if (list.window != window || DPGet(list, &DPFrozenKey)) continue;
        NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
        for (NSInteger section = 0; section < list.numberOfSections; section++)
            for (NSInteger item = 0; item < [list numberOfItemsInSection:section]; item++) {
                NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
                NSString *name = DPRowName(list, path);
                NSRect frame = DPDiaRowFrame(list.collectionViewLayout, path);
                if (name && !DPIsLeftOutRow(list, path)) frames[name] = [NSValue valueWithRect:NSOffsetRect(frame, 0, -DPClosedUp(list.collectionViewLayout, frame))];
            }
        DPSet(list, &DPFrozenSizeKey, [NSValue valueWithSize:list.collectionViewLayout.collectionViewContentSize]);
        DPSet(list, &DPFrozenCountKey, @(DPItemCount(list)));
        DPSet(list, &DPFrozenKey, frames);
    }
}

// A row added is what the frozen frames hold the list for; a row taken away leaves them describing rows that are no longer there.
static NSDictionary<NSString *, NSValue *> *DPFrozen(NSCollectionView *list) {
    NSDictionary *frames = DPGet(list, &DPFrozenKey);
    if (!frames) return nil;
    NSInteger count = DPItemCount(list), before = [DPGet(list, &DPFrozenCountKey) integerValue];
    if (count != before) DPSet(list, &DPFrozenCountKey, @(count));
    if (count < before || !DPHidingATab(list.window)) DPSet(list, &DPFrozenKey, frames = nil);
    return frames;
}

void DPRelayoutLists(void) {
    Class listCls = objc_getClass(DPDiaTabListCollection), stripCls = objc_getClass(DPDiaTabStripTabs);
    for (NSWindow *window in NSApp.windows)
        DPFindView(window.contentView, ^BOOL(NSView *view) {
            if (listCls && [view isKindOfClass:listCls]) {
                DPFrozen((NSCollectionView *)view);
                [((NSCollectionView *)view).collectionViewLayout invalidateLayout];
            } else if (stripCls && [view isKindOfClass:stripCls]) {
                view.needsLayout = YES;
            }
            return NO;
        });
}

static NSCollectionViewLayoutAttributes *DPFrozenAttributes(NSCollectionViewLayout *layout, NSCollectionViewLayoutAttributes *attributes) {
    NSDictionary *frames = attributes ? DPFrozen(layout.collectionView) : nil;
    if (!frames) return DPClosedAttributes(layout, attributes);
    NSString *name = DPRowName(layout.collectionView, attributes.indexPath);
    NSValue *frame = DPHidesTab(DPTabIn(name)) ? nil : frames[name ?: @""];
    attributes = [attributes copy];
    attributes.frame = frame ? frame.rectValue : NSMakeRect(NSMinX(attributes.frame), NSMinY(attributes.frame), NSWidth(attributes.frame), 0);
    attributes.hidden = !frame;
    attributes.alpha = frame ? attributes.alpha : 0;
    return attributes;
}

static NSArray *DPLayout_elements(NSCollectionViewLayout *self, SEL _cmd, NSRect rect) {
    if (!DPFrozen(self.collectionView)) {
        CGFloat up = DPParkedHeight(self);
        if (!up) return DPCallOriginal(DPLayout_elements, self, rect);
        NSMutableArray *shown = [NSMutableArray array];
        for (NSCollectionViewLayoutAttributes *each in DPCallOriginal(DPLayout_elements, self, NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), NSHeight(rect) + up))) {
            NSCollectionViewLayoutAttributes *closed = DPClosedAttributes(self, each);
            if (!closed.hidden && NSIntersectsRect(closed.frame, rect)) [shown addObject:closed];
        }
        return shown;
    }
    NSMutableArray *kept = [NSMutableArray array];
    for (NSCollectionViewLayoutAttributes *each in DPCallOriginal(DPLayout_elements, self, NSInsetRect(rect, 0, -600))) {
        NSCollectionViewLayoutAttributes *frozen = DPFrozenAttributes(self, each);
        if (!frozen.hidden && NSIntersectsRect(frozen.frame, rect)) [kept addObject:frozen];
    }
    return kept;
}

// Dia builds a row's appearing and disappearing attributes from its item attributes, so those are left for the one shift made on the way out.
static NSCollectionViewLayoutAttributes *DPLayout_item(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    NSCollectionViewLayoutAttributes *attributes = DPCallOriginal(DPLayout_item, self, path);
    return DPInTransition ? attributes : DPFrozenAttributes(self, attributes);
}

static void DPEndTransition(BOOL *outer) { DPInTransition = *outer; }

#define DPDuringTransition(hook, self, path)                                                    \
    ({                                                                                          \
        BOOL dp_outer __attribute__((cleanup(DPEndTransition))) = DPInTransition;               \
        DPInTransition = YES;                                                                   \
        DPCallOriginal(hook, self, path);                                                       \
    })

static NSCollectionViewLayoutAttributes *DPLayout_appearing(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    return DPFrozenAttributes(self, DPDuringTransition(DPLayout_appearing, self, path));
}

static NSCollectionViewLayoutAttributes *DPLayout_disappearing(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    return DPFrozenAttributes(self, DPDuringTransition(DPLayout_disappearing, self, path));
}

static NSSize DPLayout_size(NSCollectionViewLayout *self, SEL _cmd) {
    NSSize size = DPCallOriginal(DPLayout_size, self);
    if (DPFrozen(self.collectionView)) return [DPGet(self.collectionView, &DPFrozenSizeKey) sizeValue];
    return NSMakeSize(size.width, MAX(0, size.height - DPParkedHeight(self)));
}

void DPInstallFrozenLists(void) {
    DPInstallParkedRows();
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForItemAtIndexPath:), (IMP)DPLayout_item);
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForElementsInRect:), (IMP)DPLayout_elements);
    DPHook(DPDiaTabListLayout, @selector(collectionViewContentSize), (IMP)DPLayout_size);
    DPHook(DPDiaTabListLayout, @selector(initialLayoutAttributesForAppearingItemAtIndexPath:), (IMP)DPLayout_appearing);
    DPHook(DPDiaTabListLayout, @selector(finalLayoutAttributesForDisappearingItemAtIndexPath:), (IMP)DPLayout_disappearing);
}

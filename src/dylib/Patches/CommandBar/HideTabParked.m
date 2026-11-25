#import "Patches/CommandBar/HideTab.h"

static char DPParkedRowsKey, DPClosedKey;

BOOL DPIsLeftOutRow(NSCollectionView *list, NSIndexPath *path) { return DPHidesTab(DPTabIn(DPRowName(list, path))); }

CGFloat DPClosedUp(NSCollectionViewLayout *layout, NSRect frame) {
    if (!DPHiding()) {
        if (DPGet(layout, &DPParkedRowsKey)) DPSet(layout, &DPParkedRowsKey, nil);
        return 0;
    }
    CGFloat up = 0;
    for (NSValue *row in DPGet(layout, &DPParkedRowsKey))
        if (NSMinY(row.rectValue) < NSMinY(frame)) up += NSHeight(row.rectValue);
    return up;
}

CGFloat DPParkedHeight(NSCollectionViewLayout *layout) { return DPClosedUp(layout, NSMakeRect(0, CGFLOAT_MAX, 0, 0)); }

NSCollectionViewLayoutAttributes *DPClosedAttributes(NSCollectionViewLayout *layout, NSCollectionViewLayoutAttributes *attributes) {
    if (!attributes || DPGet(attributes, &DPClosedKey) || !DPGet(layout, &DPParkedRowsKey)) return attributes;
    if (!DPHiding()) {
        DPSet(layout, &DPParkedRowsKey, nil);
        return attributes;
    }
    attributes = [attributes copy];
    NSRect frame = attributes.frame;
    if (attributes.representedElementCategory == NSCollectionElementCategoryItem && DPIsLeftOutRow(layout.collectionView, attributes.indexPath)) {
        attributes.frame = NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), 0);
        attributes.hidden = YES;
        attributes.alpha = 0;
    } else {
        attributes.frame = NSOffsetRect(frame, 0, -DPClosedUp(layout, frame));
    }
    DPSet(attributes, &DPClosedKey, @YES);
    return attributes;
}

static void DPLayout_prepare(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepare, self);
    if (!DPParkingAny() && !DPHidingATab(self.collectionView.window) && !DPGet(self, &DPParkedRowsKey)) return;
    NSCollectionView *list = self.collectionView;
    NSMutableArray<NSValue *> *rows = [NSMutableArray array];
    for (NSInteger section = 0; section < list.numberOfSections; section++)
        for (NSInteger item = 0; item < [list numberOfItemsInSection:section]; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
            if (DPIsLeftOutRow(list, path)) [rows addObject:[NSValue valueWithRect:DPDiaRowFrame(self, path)]];
        }
    DPSet(self, &DPParkedRowsKey, rows.count ? rows : nil);
}

void DPInstallParkedRows(void) { DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepare); }

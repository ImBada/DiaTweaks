#import "Patches/CompactTabRows/CompactTabRows.h"

@interface _TtC7TabList11TabListView : NSView
@end
@implementation _TtC7TabList11TabListView
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info { return YES; }
@end

@interface _TtCC7TabList11TabListView14CollectionView : NSCollectionView
@end
@implementation _TtCC7TabList11TabListView14CollectionView
@end

@interface ArcDraggingWindow : NSWindow
@end
@implementation ArcDraggingWindow
- (BOOL)isVisible { return YES; }
@end

@interface Drag : NSObject
@property NSPoint draggingLocation;
@end
@implementation Drag
@end

NSString *DPChoice(DPPatch *patch) { return patch->defaultChoice; }

#import "Patches/CompactTabRows/CompactTabRows.m"

static id<NSDraggingDestination> DPList(NSArray<NSArray<NSValue *> *> *moves) {
    NSView *tabList = [[NSClassFromString(@(DPDiaTabList)) alloc] initWithFrame:NSMakeRect(0, 0, 200, 600)];
    NSCollectionView *list = [[NSClassFromString(@(DPDiaTabListCollection)) alloc] initWithFrame:NSMakeRect(0, 0, 200, 600)];
    list.collectionViewLayout = [NSCollectionViewFlowLayout new];
    DPSet(list.collectionViewLayout, &DPMovesKey, moves ? DPPackedMoves(moves) : nil);
    [tabList addSubview:list];
    return (id<NSDraggingDestination>)tabList;
}


static NSArray<NSCollectionViewLayoutAttributes *> *gAttributes;
static int rectValues;

static NSArray *elementsIn(id self, SEL _cmd, NSRect rect) { return gAttributes; }

static id DPCount_valueWithRect(id self, SEL _cmd, NSRect rect) {
    rectValues++;
    return DPCallOriginal(DPCount_valueWithRect, self, rect);
}

static uint32_t seed = 4242;
static uint32_t roll(uint32_t n) { seed = seed * 1664525u + 1013904223u; return (seed >> 8) % n; }

static NSArray<NSCollectionViewLayoutAttributes *> *makeAttributes(NSUInteger tabs, BOOL folders, BOOL tenths) {
    NSMutableArray *made = [NSMutableArray array];
    CGFloat y = 0.25 * roll(3);
    NSInteger item = 0;
    for (NSUInteger i = 0; i < tabs; i++) {
        BOOL folder = folders && roll(7) == 0;
        NSInteger children = folder ? (NSInteger)(1 + roll(4)) : 0;
        NSCollectionViewLayoutAttributes *each = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:[NSIndexPath indexPathForItem:item++ inSection:0]];
        each.frame = NSMakeRect(0, y, 200, folder ? 28 + 51 * children + (CGFloat)((int)roll(3) - 1) * 0.5 : 51);
        [made addObject:each];
        if (roll(9) == 0) {
            NSCollectionViewLayoutAttributes *header = [NSCollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:@"header" withIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            header.frame = NSMakeRect(0, y, 200, 20 + roll(10));
            [made addObject:header];
        }
        if (folder) {
            for (NSInteger child = 0; child < children; child++) {
                NSCollectionViewLayoutAttributes *row = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:[NSIndexPath indexPathForItem:item++ inSection:0]];
                row.frame = NSMakeRect(8, y + 25 + 51 * child + (child == 0 && roll(4) == 0 ? -25.5 : 0), 184, 51);
                [made addObject:row];
            }
            y += 28 + 51 * children;
        } else {
            y += 51;
        }
        y += i % 11 == 5 ? -3.5 : roll(4) * 0.5 + (tenths && roll(3) == 0 ? 0.1 : 0);
    }
    return made;
}

static NSArray<NSCollectionViewLayoutAttributes *> *copiesOf(NSArray<NSCollectionViewLayoutAttributes *> *attributes) {
    NSMutableArray *copies = [NSMutableArray array];
    for (NSCollectionViewLayoutAttributes *each in attributes) [copies addObject:[each copy]];
    return copies;
}

// The nested scan prepareLayout used before it walked sorted rows.
static void referencePrepare(NSArray<NSCollectionViewLayoutAttributes *> *all, CGFloat height, CGFloat cut, double *contentHeight, NSMutableArray<NSArray<NSValue *> *> *moves) {
    NSMutableArray<NSValue *> *rows = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem && NSHeight(a.frame) >= height - 0.5)
            [rows addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(a.frame), NSMinY(a.frame), NSWidth(a.frame), height)]];
    for (NSCollectionViewLayoutAttributes *a in all) {
        NSRect frame = a.frame;
        for (NSValue *value in rows) {
            NSRect row = value.rectValue;
            if (NSMaxY(row) <= NSMinY(a.frame) + 3.5) frame.origin.y -= cut;
            else if (NSMinY(row) >= NSMinY(a.frame) - 0.5 && NSMaxY(row) <= NSMaxY(a.frame) + 0.5) frame.size.height -= cut;
        }
        if (a.representedElementCategory == NSCollectionElementCategoryItem)
            [moves addObject:@[ [NSValue valueWithRect:frame], [NSValue valueWithRect:a.frame] ]];
        a.frame = frame;
    }
    *contentHeight -= cut * rows.count;
}

static BOOL nearRect(NSRect a, NSRect b) {
    return fabs(NSMinX(a) - NSMinX(b)) < 1e-9 && fabs(NSMinY(a) - NSMinY(b)) < 1e-9
        && fabs(NSWidth(a) - NSWidth(b)) < 1e-9 && fabs(NSHeight(a) - NSHeight(b)) < 1e-9;
}

static void checkPrepareLayout(void) {
    Class layoutClass = objc_allocateClassPair(NSCollectionViewLayout.class, DPDiaTabListLayout, 0);
    class_addIvar(layoutClass, "contentHeight", sizeof(double), 3, "d");
    class_addMethod(layoutClass, @selector(layoutAttributesForElementsInRect:), (IMP)elementsIn, "@@:{CGRect={CGPoint=dd}{CGSize=dd}}");
    objc_registerClassPair(layoutClass);
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepareLayout);
    DPHookClass(object_getClass(NSValue.class), @selector(valueWithRect:), (IMP)DPCount_valueWithRect);
    DPCompactTabRows.on = YES;

    int same = 0, differ = 0;
    for (int round = 0; round < 40; round++) {
        NSUInteger tabs = round < 10 ? 1 + roll(8) : 20 + roll(180);
        NSArray *template = makeAttributes(tabs, round % 3 != 0, round % 4 == 3);
        NSCollectionViewLayout *layout = [layoutClass new];
        double *contentHeight = DPIvar(layout, "contentHeight");
        *contentHeight = 9000;

        NSArray<NSCollectionViewLayoutAttributes *> *expected = copiesOf(template);
        NSMutableArray<NSArray<NSValue *> *> *expectedMoves = [NSMutableArray array];
        double expectedHeight = 9000;
        CGFloat height = DPRowHeight(expected), cut = height - DPCompactRowHeight();
        referencePrepare(expected, height, cut, &expectedHeight, expectedMoves);

        gAttributes = copiesOf(template);
        rectValues = 0;
        [layout prepareLayout];
        NSData *moves = DPGet(layout, &DPMovesKey);
        BOOL match = gAttributes.count == expected.count && moves.length == expectedMoves.count * sizeof(DPMove)
            && fabs(*contentHeight - expectedHeight) < 1e-9;
        for (NSUInteger i = 0; match && i < expected.count; i++)
            match = nearRect(gAttributes[i].frame, expected[i].frame);
        const DPMove *move = moves.bytes;
        for (NSUInteger i = 0; match && i < expectedMoves.count; i++)
            match = nearRect(move[i].now, expectedMoves[i][0].rectValue) && nearRect(move[i].then, expectedMoves[i][1].rectValue);
        match ? same++ : differ++;
        NSCAssert(rectValues == 0, @"preparing the layout boxes no rects");
        for (CGFloat y = -5; y < 400; y += 7.3) {
            NSArray *moveArrays = expectedMoves;
            NSCAssert(fabs(DPDiaYIn(moves.bytes, moves.length / sizeof(DPMove), y) - DPTabListDiaY(moveArrays, y)) < 1e-9,
                      @"packed and boxed moves find the same Dia y");
        }
    }
    NSCAssert(same == 40 && differ == 0, @"the sorted scan moves every row exactly as the nested scan did");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
        DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
        DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
        DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);

        NSArray *moves = @[ @[ [NSValue valueWithRect:NSMakeRect(0, 100, 200, 37)], [NSValue valueWithRect:NSMakeRect(0, 100, 200, 51)] ] ];
        id<NSDraggingDestination> compacted = DPList(moves), plain = DPList(nil);

        NSWindow *dragging = [[ArcDraggingWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskBorderless
                                                                    backing:NSBackingStoreBuffered defer:YES];
        NSView *tab = [[NSView alloc] initWithFrame:NSMakeRect(10, 20, 100, 30)];
        [dragging.contentView addSubview:tab];
        Drag *drag = [Drag new];
        drag.draggingLocation = NSMakePoint(50, 480);
        id<NSDraggingInfo> info = (id<NSDraggingInfo>)drag;
        NSPoint home = tab.frame.origin;

        DPCompactTabRows.on = NO;
        [compacted draggingUpdated:info];
        NSCAssert(NSEqualPoints(tab.frame.origin, home), @"disabled patch leaves dragged tab untouched even with stale moves");

        DPCompactTabRows.on = YES;
        [compacted draggingUpdated:info];
        NSCAssert(NSMinY(tab.frame) != home.y, @"over compacted rows the tab is put back under the pointer");
        tab.frame = NSMakeRect(home.x, home.y, 100, 30);

        NSCAssert([compacted prepareForDragOperation:info] && [compacted performDragOperation:info], @"drops go through");
        [plain draggingEntered:info];
        NSCAssert(NSEqualPoints(tab.frame.origin, home), @"a drop's offset isn't applied to the next drag");

        [compacted draggingUpdated:info];
        tab.frame = NSMakeRect(home.x, home.y, 100, 30);
        [compacted prepareForDragOperation:info];
        [plain draggingUpdated:info];
        NSCAssert(NSEqualPoints(tab.frame.origin, home), @"nor one a drop left after its first step");

        NSArray *small = @[ @[ [NSValue valueWithRect:NSMakeRect(0, 100, 200, 30)], [NSValue valueWithRect:NSMakeRect(0, 100, 200, 41)] ] ];
        NSCAssert(fabs(DPTabListDiaY(small, 115) - 120.5) < 0.01, @"inside a smaller row");
        NSCAssert(fabs(DPTabListDiaY(small, 140) - 151) < 0.01, @"below a smaller row");
        checkPrepareLayout();
        puts("all drag offset checks passed");
    }
}

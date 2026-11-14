#import "NativeControls.h"

@interface DPAddressGridLayout : NSCollectionViewLayout
@property NSUInteger columns;
@property CGFloat tileWidth;
@end
@implementation DPAddressGridLayout
- (NSSize)collectionViewContentSize {
    NSInteger count = self.collectionView.numberOfSections ? [self.collectionView numberOfItemsInSection:0] : 0;
    return NSMakeSize(NSWidth(self.collectionView.bounds), MAX(0, ceil((CGFloat)count / MAX(1,self.columns))*32-5));
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    NSUInteger columns = MAX(1,self.columns);
    NSCollectionViewLayoutAttributes *item = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:path];
    item.frame = NSMakeRect((path.item%columns)*(self.tileWidth+5), (path.item/columns)*32, self.tileWidth,27);
    return item;
}
- (NSArray<NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect {
    NSMutableArray *items = [NSMutableArray new];
    NSInteger count = self.collectionView.numberOfSections ? [self.collectionView numberOfItemsInSection:0] : 0;
    for (NSInteger i = 0; i < count; i++) {
        NSCollectionViewLayoutAttributes *item = [self layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
        if (NSIntersectsRect(rect,item.frame)) [items addObject:item];
    }
    return items;
}
@end

@interface DPAddressTileBackground : NSView
@property(weak) DPAddressGridLayout *grid;
@end
@implementation DPAddressTileBackground
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor.labelColor colorWithAlphaComponent:0.08] setFill];
    for (NSCollectionViewLayoutAttributes *tile in [self.grid layoutAttributesForElementsInRect:dirtyRect])
        [[NSBezierPath bezierPathWithRoundedRect:tile.frame xRadius:9 yRadius:9] fill];
}
@end

CGFloat DPAddressLayoutGrid(DPAddressNativeControls *state, DPSidebarAddressRow *row, NSUInteger count) {
    NSCollectionView *collection = (NSCollectionView *)DPFindView(state.extensions.view, ^BOOL(NSView *v) {
        return [v isKindOfClass:NSCollectionView.class];
    });
    BOOL active = DPSidebarExtensionTiles.on && count > 2 && collection.numberOfSections == 1 && row.superview;
    if (!active || state.gridCollection != collection) DPAddressRestoreGrid(state);
    if (!active) return 0;

    CGFloat width = NSWidth(row.bounds);
    NSUInteger columns = width >= 150 ? 3 : 2;
    CGFloat tileWidth = floor(MAX(28, (width - 5 * (columns - 1)) / columns));
    CGFloat height = ceil((CGFloat)count / columns) * 32 - 5;
    DPAddressGridLayout *layout = (DPAddressGridLayout *)collection.collectionViewLayout;
    if (![layout isKindOfClass:DPAddressGridLayout.class]) {
        state.gridCollection = collection;
        state.nativeGridLayout = collection.collectionViewLayout;
        state.nativeGridFrame = collection.frame;
        layout = [DPAddressGridLayout new];
        layout.columns = columns;
        layout.tileWidth = tileWidth;
        state.nativeGridBackground = collection.backgroundView;
        DPAddressTileBackground *background = [DPAddressTileBackground new];
        background.grid = layout;
        collection.backgroundView = background;
        collection.collectionViewLayout = layout;
    } else if (layout.tileWidth != tileWidth || layout.columns != columns) {
        layout.columns = columns;
        layout.tileWidth = tileWidth;
        [layout invalidateLayout];
    }
    NSRect frame = NSMakeRect(NSMinX(row.frame),NSMaxY(row.frame)+5,width,height);
    if (state.scroll.superview != row.superview) {
        [state.scroll removeFromSuperview];
        [row.superview addSubview:state.scroll positioned:NSWindowAbove relativeTo:row];
    }
    if (!NSEqualRects(state.scroll.frame,frame)) state.scroll.frame = frame;
    if (state.scroll.hasHorizontalScroller) state.scroll.hasHorizontalScroller = NO;
    [state.scroll.contentView scrollToPoint:NSZeroPoint];
    state.extensions.fixedPinnedWidth = YES;
    DPLayoutAddressNative(state.extensions,NSMakeRect(0,0,width,height));
    NSRect collectionFrame = NSMakeRect(0,0,width,height);
    if (!NSEqualRects(collection.frame,collectionFrame)) collection.frame = collectionFrame;
    if (height != state.gridHeight || !NSEqualRects(collection.backgroundView.frame, collection.bounds))
        collection.backgroundView.needsDisplay = YES;
    state.scroll.hidden = NO;
    state.scroll.accessibilityHidden = NO;
    if (DPSidebarExtensionDivider.on) {
        if (!state.gridDivider) {
            state.gridDivider = [[NSBox alloc] initWithFrame:NSZeroRect];
            state.gridDivider.boxType = NSBoxSeparator;
            state.gridDivider.accessibilityHidden = YES;
        }
        if (state.gridDivider.superview != row.superview) {
            [row.superview addSubview:state.gridDivider];
            row.superview.needsLayout = YES;
        }
        state.gridDivider.frame = NSMakeRect(NSMinX(frame) + 10, NSMaxY(frame) + DPAddressGridDividerPadding, MAX(0, NSWidth(frame) - 20), 1);
    } else if (state.gridDivider.superview) {
        [state.gridDivider removeFromSuperview];
        row.superview.needsLayout = YES;
    }
    return height;
}

void DPAddressRestoreGrid(DPAddressNativeControls *state) {
    state.extensions.fixedPinnedWidth = NO;
    [state.gridDivider removeFromSuperview];
    NSCollectionView *collection = state.gridCollection;
    if (!collection) return;
    collection.collectionViewLayout = state.nativeGridLayout;
    collection.backgroundView = state.nativeGridBackground;
    state.nativeGridBackground = nil;
    collection.frame = state.nativeGridFrame;
    state.nativeGridLayout = nil;
    state.gridCollection = nil;
}

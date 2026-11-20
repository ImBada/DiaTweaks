#import "NativeControls.h"

@implementation DPAddressNativeControls (ExtensionsMenu)
- (void)openExtensions:(NSButton *)sender {
    NSMenu *menu = [NSApp.mainMenu itemWithTitle:@"Extensions"].submenu;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.isFlipped ? NSHeight(sender.bounds) : 0) inView:sender];
}
@end

void DPCreateAddressExtensionsHost(DPAddressNativeControls *state) {
    if (state.scroll) return;
    state.scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    state.scroll.drawsBackground = NO;
    state.scroll.borderType = NSNoBorder;
    state.scroll.hasHorizontalScroller = YES;
    state.scroll.autohidesScrollers = YES;
    state.scroll.scrollerStyle = NSScrollerStyleOverlay;
    state.scroll.accessibilityLabel = @"Pinned extensions";
    NSImage *image = [[NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:nil]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium]];
    state.extensionsButton = [NSButton buttonWithImage:image target:state action:@selector(openExtensions:)];
    state.extensionsButton.bordered = NO;
    state.extensionsButton.hidden = YES;
    state.extensionsButton.contentTintColor = NSColor.secondaryLabelColor;
    state.extensionsButton.accessibilityLabel = @"Extensions";
    state.extensionsButton.toolTip = @"Show Dia’s Extensions menu";
    state.extensionsButton.wantsLayer = YES;
    state.extensionsButton.layer.cornerRadius = 5;
}

static void DPCollectExtensionEdges(NSView *root, NSView *view, NSMutableArray<NSNumber *> *edges) {
    if (view.hidden) return;
    if (DPIsKind(view, "_TtC16PinnedExtensions19PinnedExtensionView")) {
        [edges addObject:@(ceil(NSMaxX([root convertRect:view.bounds fromView:view])))];
        return;
    }
    for (NSView *child in view.subviews) DPCollectExtensionEdges(root, child, edges);
}

void DPSidebarLayoutNativeControls(NSView *view) {
    DPSidebarAddressRow *row = (DPSidebarAddressRow *)view;
    DPAddressNativeControls *state = DPAddressControlsFor(row, NO);
    CGFloat width = NSWidth(row.bounds);
    NSString *url = row.URLString;
    BOOL loaded = url.length && ![url isEqual:@"about:blank"] && ![url hasPrefix:@"chrome://newtab"];
    NSView *focus = [row.window.firstResponder isKindOfClass:NSView.class] ? (NSView *)row.window.firstResponder : nil;
    BOOL revealed = DPSidebarRowIsHovered(row) || [focus isDescendantOf:row];
    BOOL showActions = !row.isEditingAddress && (!DPSidebarExtensionsOnHover.on || revealed);
    state.more.forcedHidden = !loaded || !showActions;
    CGFloat moreX = MAX(0,width-32);
    DPLayoutAddressNative(state.more, NSMakeRect(moreX,4,28,28));
    CGFloat edge = loaded && state.more.view ? moreX - 2 : width - 4;
    NSMutableArray<NSNumber *> *edges = [NSMutableArray new];
    DPCollectExtensionEdges(state.extensions.view, state.extensions.view, edges);
    [edges sortUsingSelector:@selector(compare:)];
    NSUInteger count = state.gridCollection.numberOfSections == 1 ? [state.gridCollection numberOfItemsInSection:0] : edges.count;
    BOOL menuOnly = DPSidebarExtensionsMenuOnly.on && state.extensionsButton.superview && [NSApp.mainMenu itemWithTitle:@"Extensions"].submenu;
    state.extensionsButton.hidden = !menuOnly || !showActions;
    if (menuOnly) state.extensionsButton.frame = NSMakeRect(MAX(0,edge-28),4,28,28);
    CGFloat height = DPAddressLayoutGrid(state, row, menuOnly ? 0 : count);
    state.extensions.fixedPinnedWidth = height > 0;
    if (height != state.gridHeight) { state.gridHeight = height; row.superview.needsLayout = YES; }
    if (height) {
        [row layoutAddressBefore:showActions ? edge : width - 4];
        return;
    }
    if (state.scroll.superview && state.scroll.superview != row) {
        [state.scroll removeFromSuperview];
        [row addSubview:state.scroll];
    }
    DPLayoutAddressNative(state.extensions, NSMakeRect(0,0,state.extensions.naturalWidth,42));
    NSUInteger limit = menuOnly ? 0 : MIN(3,edges.count);
    CGFloat available = MAX(0, edge - 60), visible = 0;
    for (NSUInteger i = 0; i < limit && edges[i].doubleValue <= available; i++) visible = edges[i].doubleValue;
    state.scroll.hidden = !visible || !showActions;
    state.scroll.accessibilityHidden = state.scroll.hidden;
    if (visible) {
        NSRect frame = NSMakeRect(edge-visible,-2,visible,42);
        if (!NSEqualRects(state.scroll.frame,frame)) state.scroll.frame = frame;
    }
    if (state.scroll.hasHorizontalScroller) state.scroll.hasHorizontalScroller = NO;
    if (NSMinX(state.scroll.contentView.bounds) != 0) [state.scroll.contentView scrollToPoint:NSZeroPoint];
    CGFloat remaining = edge - visible - (menuOnly ? 30 : 0);
    [row layoutAddressBefore:showActions ? remaining : width - 4];
}

static void DPApplyExtensionsOnHover(DPPatch *patch) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader))
        for (NSView *view in header.superview.subviews)
            if ([view isKindOfClass:DPSidebarAddressRow.class]) DPSidebarLayoutNativeControls(view);
}

DP_PATCH(DPSidebarExtensionsOnHover) {
    .key = @"sidebarExtensionsOnHover",
    .defaultOn = YES,
    .order = 87, .title = @"Reveal actions on hover",
    .detail = @"Reveal page actions and inline extensions on hover or focus.",
    .symbol = @"puzzlepiece.extension",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .requires = @"sidebarAddressBar",
    .apply = DPApplyExtensionsOnHover,
};

DP_PATCH(DPSidebarExtensionTiles) {
    .key = @"sidebarExtensionTiles",
    .order = 89, .title = @"Use extension tiles",
    .detail = @"With three or more pins, show extensions in tiles below the address.",
    .symbol = @"square.grid.3x2",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .requires = @"sidebarAddressBar",
    .apply = DPApplyExtensionsOnHover,
};


DP_PATCH(DPSidebarExtensionsMenuOnly) {
    .key = @"sidebarExtensionsMenuOnly",
    .order = 90, .title = @"Extensions button only",
    .detail = @"Use one Extensions button instead of inline pins or tiles.",
    .symbol = @"puzzlepiece.extension",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .requires = @"sidebarAddressBar",
    .apply = DPApplyExtensionsOnHover,
};

DP_PATCH(DPSidebarExtensionDivider) {
    .key = @"sidebarExtensionDivider",
    .defaultOn = NO,
    .order = 91, .title = @"Divider below extensions",
    .detail = @"Separate extension tiles from pinned tabs.",
    .symbol = @"minus",
    .section = @"Sidebar & Tab Bar",
    .requires = @"sidebarAddressBar",
    .apply = DPApplyExtensionsOnHover,
};

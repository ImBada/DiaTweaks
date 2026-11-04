#import "NativeControls.h"

static char DPRowKey, DPBodyKey, DPBodyFrameKey;
static const CGFloat DPAddressSpace = 42;

static void DPRestoreBody(NSView *body) {
    if (!body) return;
    NSRect frame = [DPDiaValue(body, &DPBodyFrameKey, [NSValue valueWithRect:body.frame]) rectValue];
    body.frame = frame;
    DPOverride(body, &DPBodyFrameKey, [NSValue valueWithRect:frame], [NSValue valueWithRect:frame]);
}

BOOL DPSidebarUsesVerticalTabs(NSView *root) {
    return DPSubview(root, DPDiaSidebarFooter) != nil;
}

static BOOL DPVisibleAddressSidebarHeader(NSView *view) {
    return DPIsKind(view, DPDiaSidebarHeader) && !view.hiddenOrHasHiddenAncestor &&
        DPSidebarUsesVerticalTabs(view.superview);
}

BOOL DPSidebarAddressRowAvailable(NSWindow *window) {
    if (!DPSidebarAddressBar.on) return NO;
    return DPFindView(window.contentView, ^BOOL(NSView *view) {
        if (!DPVisibleAddressSidebarHeader(view)) return NO;
        DPSidebarAddressRow *row = DPGet(view, &DPRowKey);
        return row.superview == view.superview && !row.hiddenOrHasHiddenAncestor;
    }) != nil;
}

static void DPPlaceSidebarRow(NSView *header) {
    NSView *root = header.superview, *body = DPGet(header, &DPBodyKey);
    DPSidebarAddressRow *row = DPGet(header, &DPRowKey);
    if (body.superview == root) DPRestoreBody(body);
    if (!DPSidebarAddressBar.on || !DPSidebarUsesVerticalTabs(root) || header.hiddenOrHasHiddenAncestor || !root.isFlipped) {
        DPSidebarRestoreNativeControls(row);
        [row removeFromSuperview];
        return;
    }
    // Floating sidebars can inset the tab host. Identify it by its scroll
    // view and position between the header and footer, rather than its width.
    NSView *footer = DPSubview(root, DPDiaSidebarFooter);
    NSView *tabHost = nil;
    DPAddressNativeControls *controls = DPAddressControlsFor(row, NO);
    CGFloat headerBottom = NSMaxY(header.frame);
    for (NSView *view in root.subviews) {
        if (view == row || view == header || view == footer || view.hidden ||
            view == controls.scroll || view == controls.gridDivider) continue;
        NSRect frame = view.frame;
        if (NSHeight(frame) <= DPAddressSpace || NSMinY(frame) < headerBottom - 1 ||
            NSMaxY(frame) > NSMinY(footer.frame) + 1) continue;
        if (DPFindView(view, ^BOOL(NSView *child) { return [child isKindOfClass:NSScrollView.class]; })) {
            tabHost = view;
            break;
        }
        if (fabs(NSMinY(frame) - headerBottom) < 1 && fabs(NSWidth(frame) - NSWidth(root.bounds)) < 1)
            tabHost = view;
    }
    body = tabHost;
    if (!body) {
        DPSidebarRestoreNativeControls(row);
        [row removeFromSuperview];
        return;
    }
    DPSet(header, &DPBodyKey, body);
    if (!row) DPSet(header, &DPRowKey, row = [[DPSidebarAddressRow alloc] initWithFrame:NSZeroRect]);
    BOOL comfortable = DPSidebarComfortableSpacing.on;
    CGFloat margin = comfortable ? 2 : 0;
    row.frame = NSMakeRect(6 + margin, NSMaxY(header.frame) + margin, MAX(0, NSWidth(root.bounds) - 12 - margin * 2), [row preferredHeight]);
    if (row.superview != root) [root addSubview:row positioned:NSWindowAbove relativeTo:header];
    [row refresh];
    NSRect before = body.frame, after = before;
    CGFloat grid = DPAddressControlsFor(row, NO).gridHeight;
    CGFloat gridBottomGap = DPSidebarExtensionDivider.on ? 2 * DPAddressGridDividerPadding + 1 : 5;
    CGFloat space = grid ? 36 + margin + 5 + grid + gridBottomGap : DPAddressSpace + margin * 2;
    CGFloat shift = MIN(NSHeight(before), MAX(0, headerBottom + space - NSMinY(before)));
    after.origin.y += shift;
    after.size.height -= shift;
    after.origin.x += margin;
    after.size.width -= margin * 2;
    DPOverride(body, &DPBodyFrameKey, [NSValue valueWithRect:before], [NSValue valueWithRect:after]);
    body.frame = after;
    DPSidebarLayoutNativeControls(row);
}

static void DPSidebarRoot_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarRoot_layout, self);
    NSView *header = DPSubview(self, DPDiaSidebarHeader);
    DPPatch *compact = DPPatchNamed(@"compactSidebarHeader");
    // Its controller finishes the header geometry after this root layout.
    if (header && !(compact && compact->on && self.isFlipped)) DPPlaceSidebarRow(header);
}

// Dia can reveal an already laid-out sidebar by unhiding an ancestor.
static void DPSidebarRoot_unhidden(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarRoot_unhidden, self);
    NSView *header = DPSubview(self, DPDiaSidebarHeader);
    if (header && DPSidebarAddressBar.on) DPPlaceSidebarRow(header);
}

// The floating container can lay out independently of its sidebar root.
static void DPFloatingAddressSidebar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFloatingAddressSidebar_layout, self);
    if (!DPSidebarAddressBar.on || self.hiddenOrHasHiddenAncestor) return;
    NSView *header = DPFindView(self, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaSidebarHeader);
    });
    if (header && !header.hiddenOrHasHiddenAncestor) DPPlaceSidebarRow(header);
}

static void DPHookAddressSidebarRoot(NSView *root) {
    DPHookClass(root.class, @selector(layout), (IMP)DPSidebarRoot_layout);
    DPHookClass(root.class, @selector(viewDidUnhide), (IMP)DPSidebarRoot_unhidden);
}

static void DPSidebarHeader_attached(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarHeader_attached, self);
    if (!self.window || !self.superview) return;
    DPHookAddressSidebarRoot(self.superview);
    self.superview.needsLayout = YES;
}

static void DPSidebarToolbar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarToolbar_layout, self);
    if (!DPSidebarAddressBar.on || !self.window || self.hiddenOrHasHiddenAncestor) return;
    // A space change can rebuild the active toolbar without laying out the
    // sidebar root. Refresh its row during the same layout pass.
    static BOOL refreshing;
    if (refreshing) return;
    refreshing = YES;
    @try {
        NSView *header = DPFindView(self.window.contentView, ^BOOL(NSView *view) {
            return DPVisibleAddressSidebarHeader(view);
        });
        if (!header) return;
        DPSidebarAddressRow *row = DPGet(header, &DPRowKey);
        if (row.superview != header.superview) DPPlaceSidebarRow(header);
        else [row refresh];
    } @finally {
        refreshing = NO;
    }
}

void DPSidebarInstallLayout(void) {
    DPHookClass(objc_getClass(DPDiaToolbar), @selector(layout), (IMP)DPSidebarToolbar_layout);
    DPHook(DPDiaSidebarHeader, @selector(viewDidMoveToWindow), (IMP)DPSidebarHeader_attached);
    DPHookClass(objc_getClass(DPDiaFloatingSidebar), @selector(layout), (IMP)DPFloatingAddressSidebar_layout);
}

void DPSidebarApplyLayout(void) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        DPHookAddressSidebarRoot(header.superview);
        DPPlaceSidebarRow(header);
    }
}

void DPSidebarRefreshLayout(void) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        DPSidebarAddressRow *row = DPGet(header, &DPRowKey);
        if (!row.superview || row.superview != header.superview ||
            !DPSidebarUsesVerticalTabs(header.superview) || header.hiddenOrHasHiddenAncestor) {
            if (row.superview || (!header.hiddenOrHasHiddenAncestor && DPSidebarUsesVerticalTabs(header.superview)))
                DPPlaceSidebarRow(header);
        } else {
            [row refresh];
        }
    }
}

NSString *DPSidebarVerifyLayout(DPPatch *patch) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        if (header.hiddenOrHasHiddenAncestor) continue;
        DPSidebarAddressRow *row = DPGet(header, &DPRowKey);
        BOOL expected = patch->on && DPSidebarUsesVerticalTabs(header.superview);
        if (expected && !row.superview) return @"sidebar address row is missing";
        if (!expected && row.superview) return @"sidebar address row remains while off";
        NSView *body = DPGet(header, &DPBodyKey);
        NSRect headerFrame = row.frame; headerFrame.size.height = 36;
        if (expected && NSIntersectsRect(headerFrame, body.frame)) return @"sidebar address overlaps the tabs";
    }
    return nil;
}

void DPSidebarLayoutHeader(NSView *header) { DPPlaceSidebarRow(header); }

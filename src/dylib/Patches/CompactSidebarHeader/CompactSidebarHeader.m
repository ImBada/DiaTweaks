#import "StdPatch/StdPatch.h"

extern DPPatch DPCompactSidebarHeader;
static const CGFloat DPHeaderTrim = 10;
static const CGFloat DPTopTabsButtonInset = 14;
static NSHashTable<NSView *> *DPSidebars;
static NSHashTable *DPFramedClasses, *DPButtonsRowClasses;
static Class DPHeaderClass;
static char DPHeaderFrameKey, DPButtonsKey, DPRetriesKey, DPSidebarKey, DPSidebarChildKey;

static NSRect DPLaidOutHeader(NSView *header) {
    return [DPDiaValue(header, &DPHeaderFrameKey, @(header.frame)) rectValue];
}

static NSRect DPCloseButtonInWindow(NSView *lights) {
    NSView *close = DPFindView(lights, ^BOOL(NSView *v) { return [v isKindOfClass:NSButton.class] && v == [v.window standardWindowButton:NSWindowCloseButton]; });
    if (!close || !lights.window) return NSZeroRect;
    NSRect r = [close convertRect:close.bounds toView:nil];
    r.origin.y = NSHeight(lights.window.contentView.superview.bounds) - NSMaxY(r);
    return r;
}

static NSRect DPCorneredRow(NSView *row, NSRect frame) {
    if (!DPCompactSidebarHeader.on) return frame;
    NSView *lights = DPGet(row, &DPButtonsKey);
    NSWindow *window = row.window;
    if (lights.superview != row || lights.hiddenOrHasHiddenAncestor || !window || (window.styleMask & NSWindowStyleMaskFullScreen)) return frame;
    NSRect old = row.frame, close = DPCloseButtonInWindow(lights);
    BOOL flipped = row.superview.isFlipped;
    close.origin.x += frame.origin.x - NSMinX(old);
    close.origin.y += flipped ? frame.origin.y - NSMinY(old) : NSMinY(old) - frame.origin.y;
    CGFloat dx = DPTopTabsButtonInset - NSMinX(close), dy = DPTopTabsButtonInset - NSMinY(close);
    if (!NSIsEmptyRect(close) && fabs(dx) <= 6 && fabs(dy) <= 6) {
        frame.origin.x += dx;
        frame.origin.y += flipped ? dy : -dy;
    }
    return frame;
}

static void DPButtonsRow_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (DPCompactSidebarHeader.on && DPGet(self, &DPButtonsKey)) frame = DPCorneredRow(self, frame);
    DPCallOriginal(DPButtonsRow_setFrame, self, frame);
}

static NSView *DPNoteButtons(NSView *header) {
    NSView *lights = DPFindView(header, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTrafficLights); });
    NSView *row = lights.superview;
    if (lights && row && row != header) {
        DPSet(row, &DPButtonsKey, lights);
        Class cls = row.class;
        if (![DPButtonsRowClasses containsObject:cls]) {
            [DPButtonsRowClasses addObject:cls];
            DPHookClass(cls, @selector(setFrame:), (IMP)DPButtonsRow_setFrame);
        }
    }
    return lights;
}

static void DPHeader_layout(NSView *self, SEL _cmd) {
    if (!DPCompactSidebarHeader.on) {
        if (DPGet(self, &DPRetriesKey)) DPSet(self, &DPRetriesKey, nil);
        return DPCallOriginal(DPHeader_layout, self);
    }
    DPNoteButtons(self);
    DPCallOriginal(DPHeader_layout, self);
    NSView *lights = DPNoteButtons(self), *row = lights.superview;
    if (!lights || lights.hiddenOrHasHiddenAncestor || row == self) return;
    NSRect cornered = DPCorneredRow(row, row.frame);
    if (!NSEqualRects(cornered, row.frame) && DPMayAdjust(row)) row.frame = cornered;
    // At launch Dia lays the header out before the buttons are in it, then not again until the sidebar changes.
    NSUInteger retries = [DPGet(self, &DPRetriesKey) unsignedIntegerValue];
    if (NSIsEmptyRect(DPCloseButtonInWindow(lights)) && self.window && retries < 8) {
        DPSet(self, &DPRetriesKey, @(retries + 1));
        __weak NSView *header = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ header.needsLayout = YES; });
    }
}

static void DPHeader_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (!DPCompactSidebarHeader.on) {
        if (DPGet(self, &DPHeaderFrameKey)) DPSet(self, &DPHeaderFrameKey, nil);
        return DPCallOriginal(DPHeader_setFrame, self, frame);
    }
    NSArray *values = DPGet(self, &DPHeaderFrameKey);
    if (!values || ![values[1] isEqual:[NSValue valueWithRect:frame]]) {
        NSRect laidOut = frame;
        frame.size.height = MAX(0, NSHeight(laidOut) - DPHeaderTrim);
        DPOverride(self, &DPHeaderFrameKey, [NSValue valueWithRect:laidOut], [NSValue valueWithRect:frame]);
    }
    DPCallOriginal(DPHeader_setFrame, self, frame);
}

// Rewritten in setFrame:, not after layout, to avoid a second pass that jitters during resize. Unrelated views of a hooked
// sidebar subview class bail out before messaging superview or touching a weak table.
static void DPCompactFrame_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (DPCompactSidebarHeader.on && DPGet(self, &DPSidebarChildKey)) {
        NSView *sidebar = self.superview;
        if (DPGet(sidebar, &DPSidebarKey)) {
            NSView *header = DPSubview(sidebar, DPDiaSidebarHeader);
            NSRect laidOut = header ? DPLaidOutHeader(header) : NSZeroRect;
            if (header && !NSIsEmptyRect(laidOut) && fabs(NSMinY(frame) - NSMaxY(laidOut)) < 0.5) {
                frame.origin.y = MAX(0, NSMaxY(laidOut) - DPHeaderTrim);
                frame.size.height += DPHeaderTrim;
            }
        } else {
            DPSet(self, &DPSidebarChildKey, nil);
        }
    }
    DPCallOriginal(DPCompactFrame_setFrame, self, frame);
}

static void DPHookSidebarChildren(NSView *sidebar) {
    if (!sidebar) return;
    DPSet(sidebar, &DPSidebarKey, @YES);
    for (NSView *sub in sidebar.subviews) {
        if (DPHeaderClass && [sub isKindOfClass:DPHeaderClass]) continue;
        DPSet(sub, &DPSidebarChildKey, @YES);
        Class cls = sub.class;
        if ([DPFramedClasses containsObject:cls]) continue;
        [DPFramedClasses addObject:cls];
        DPHookClass(cls, @selector(setFrame:), (IMP)DPCompactFrame_setFrame);
    }
}

static void DPSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    if (!DPGet(self.view, &DPSidebarKey)) {
        DPSet(self.view, &DPSidebarKey, @YES);
        [DPSidebars addObject:self.view];
    }
    if (DPCompactSidebarHeader.on) DPHookSidebarChildren(self.view);
    DPCallOriginal(DPSidebar_viewWillLayout, self);
}

static void DPInstallCompactSidebarHeader(void) {
    DPSidebars = [NSHashTable weakObjectsHashTable];
    NSPointerFunctionsOptions opaque = NSPointerFunctionsOpaqueMemory | NSPointerFunctionsObjectPointerPersonality;
    DPFramedClasses = [NSHashTable hashTableWithOptions:opaque];
    DPButtonsRowClasses = [NSHashTable hashTableWithOptions:opaque];
    DPHeaderClass = objc_getClass(DPDiaSidebarHeader);
    DPHook(DPDiaSidebarController, @selector(viewWillLayout), (IMP)DPSidebar_viewWillLayout);
    DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPHeader_layout);
    DPHook(DPDiaSidebarHeader, @selector(setFrame:), (IMP)DPHeader_setFrame);
}

static void DPApplyCompactSidebarHeader(DPPatch *patch) {
    for (NSView *sidebar in DPSidebars.allObjects) {
        if (patch->on) DPHookSidebarChildren(sidebar);
        DPSubview(sidebar, DPDiaSidebarHeader).needsLayout = YES;
    }
    DPRelayoutViews(DPSidebars);
}

static NSString *DPVerifyCompactSidebarHeader(DPPatch *patch) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        if (header.hiddenOrHasHiddenAncestor || !header.superview.isFlipped) continue;
        CGFloat trimmed = NSHeight(DPLaidOutHeader(header)) - NSHeight(header.frame);
        if (fabs(trimmed - (patch->on ? DPHeaderTrim : 0)) > 0.5) return patch->on ? @"header is full height" : @"header is still trimmed";
        NSView *lights = DPFindView(header, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTrafficLights); });
        NSRect close = lights && !lights.hiddenOrHasHiddenAncestor ? DPCloseButtonInWindow(lights) : NSZeroRect;
        BOOL cornered = fabs(NSMinX(close) - DPTopTabsButtonInset) < 0.5 && fabs(NSMinY(close) - DPTopTabsButtonInset) < 0.5;
        BOOL fullScreen = (header.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
        if (patch->on && !fullScreen && !NSIsEmptyRect(close) && !cornered) return @"window buttons aren't where top tabs put them";
    }
    return nil;
}

DP_PATCH(DPCompactSidebarHeader) {
    .key = @"compactSidebarHeader",
    .order = 76,
    .section = @"Sidebar & Tab Bar",
    .title = @"Compact Sidebar Header",
    .detail = @"Move the pinned tabs up into the empty space under the window buttons.",
    .symbol = @"arrow.up.to.line.square.fill",
    .tint = @"systemTealColor",
    .classes = DPClasses(DPDiaSidebarController, DPDiaSidebarHeader, DPDiaTrafficLights),
    .install = DPInstallCompactSidebarHeader,
    .apply = DPApplyCompactSidebarHeader,
    .verify = DPVerifyCompactSidebarHeader,
};

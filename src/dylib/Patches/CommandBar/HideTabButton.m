#import "Patches/CommandBar/HideTab.h"

static char DPTabKey, DPSavedKey;

BOOL DPIsNewTabButton(NSView *view) {
    return DPIsKind(view, DPDiaNewTabButton) || (DPIsKind(view, DPDiaTabSurfaceButton) && DPIsKind(view.superview, DPDiaTabStripTabs));
}

static BOOL DPStandingIn(NSWindow *window) { return DPHidesTab(DPGet(window, &DPTabKey)); }

// Only in the hidden tab's own space, not the next one a swipe slides in.
static BOOL DPStandingInHere(NSView *background) {
    return DPStandingIn(background.window) && DPListsTab(background, DPGet(background.window, &DPTabKey));
}

static void DPRedraw(NSView *background) {
    DPTabShapeView(background).needsLayout = YES;
    background.needsLayout = background.needsDisplay = YES;
}

static void DPSelectButton(NSView *background, BOOL selected) {
    uintptr_t *style = DPSelectionStyle(background);
    uint8_t *shape = DPTabShape(background);
    NSArray *saved = DPGet(background, &DPSavedKey);
    if (!style || !shape || selected == (saved != nil)) return;
    if (selected) {
        NSArray *look = DPSelectedLook(background.superview);
        if (!look || DPStyleSelected(*style)) return;
        uintptr_t original = *style;
        *style = look[0] == NSNull.null ? 0 : (uintptr_t)CFBridgingRetain(look[0]);
        uint8_t was = *shape;
        *shape = [look[1] unsignedCharValue];
        // Holding look[0] keeps its address from being reused before the restore compares it.
        DPSet(background, &DPSavedKey, @[ @(original), @(was), @(*style), @(*shape), look[0] ]);
    } else {
        DPSet(background, &DPSavedKey, nil);
        uintptr_t ours = [saved[2] unsignedLongValue];
        // The slot owns the +1 we gave it: Dia releases it when it writes over the style, so release it only when taking it back out.
        if (*style == ours) {
            *style = [saved[0] unsignedLongValue];
            if (ours >= DPFirstFill) CFRelease((CFTypeRef)(void *)ours);
        }
        if (*shape == [saved[3] unsignedCharValue]) *shape = [saved[1] unsignedCharValue];
    }
    DPRedraw(background);
}

static void DPSelectButtons(NSWindow *window) {
    for (NSView *background in DPFindViews(DPDiaTabBackground))
        if (background.window == window && DPIsNewTabButton(background.superview)) DPSelectButton(background, DPStandingInHere(background));
}

static void DPHideFrontTab(NSView *background) {
    BOOL standingIn = DPStandingInHere(background), front = standingIn && DPDrawnSelected(background) && DPIsKind(background.superview, DPDiaTabView);
    if (DPSwitchingTo(background)) return;
    DPUnselectFrontTab(background, standingIn);
    if (front) DPSelectButtons(background.window);
}

static void DPRefresh(NSWindow *window) {
    Class cls = objc_getClass(DPDiaTabBackground);
    if (!cls || !window.contentView) return;
    NSMutableArray<NSView *> *backgrounds = [NSMutableArray array];
    DPFindView(window.contentView, ^BOOL(NSView *view) {
        if ([view isKindOfClass:cls]) [backgrounds addObject:view];
        return NO;
    });
    for (NSView *background in backgrounds)
        if (DPIsNewTabButton(background.superview)) DPSelectButton(background, DPStandingInHere(background));
    for (NSView *background in backgrounds) {
        if (!DPIsKind(background.superview, DPDiaTabView)) continue;
        if (!DPStandingInHere(background)) DPGiveBackSelection(background);
        else if (DPDrawnSelected(background)) {
            DPHideFrontTab(background);
            DPRedraw(background);
        }
    }
}

void DPStandInFor(NSWindow *window, NSString *tabID) {
    if (!window) return;
    DPSet(window, &DPTabKey, tabID);
    DPRefresh(window);
}

void DPStandInForTab(NSWindow *window, NSString *tabID) {
    if (window && [DPGet(window, &DPTabKey) isEqual:tabID]) DPStandInFor(window, nil);
}

void DPRefreshStandIns(void) {
    for (NSWindow *window in NSApp.windows) DPRefresh(window);
}

static void DPRestoreBackground(NSView *background) {
    if (DPGet(background, &DPSavedKey)) DPSelectButton(background, NO);
    if (DPHoldsSelection(background)) DPGiveBackSelection(background);
}

static void DPTabBackground_updateLayer(NSView *self, SEL _cmd) {
    if (!DPHiding()) {
        DPRestoreBackground(self);
        return DPCallOriginal(DPTabBackground_updateLayer, self);
    }
    DPNoteLook(self);
    if (DPSwitchingTo(self)) DPEndSwitch(self.window);
    DPHideFrontTab(self);
    DPCallOriginal(DPTabBackground_updateLayer, self);
}

static void DPTabBackground_layout(NSView *self, SEL _cmd) {
    if (!DPHiding()) {
        DPRestoreBackground(self);
        return DPCallOriginal(DPTabBackground_layout, self);
    }
    DPHideFrontTab(self);
    DPCallOriginal(DPTabBackground_layout, self);
    if (DPIsNewTabButton(self.superview)) DPSelectButton(self, DPStandingInHere(self));
}

NSString *DPVerifyStandIn(NSWindow *window, NSString *tabID) {
    for (NSView *background in DPFindViews(DPDiaTabBackground)) {
        if (background.window != window || background.isHiddenOrHasHiddenAncestor) continue;
        BOOL standingIn = DPHidesTab(tabID) && DPListsTab(background, tabID);
        if (DPIsNewTabButton(background.superview)) {
            if (standingIn && !DPDrawnSelected(background) && DPSelectedLook(background.superview)) return @"the New Tab button isn't selected while the new tab is hidden";
            if (!standingIn && DPGet(background, &DPSavedKey)) return @"the New Tab button stays selected once the bar closes";
        } else if (DPIsKind(background.superview, DPDiaTabView)) {
            if (standingIn && DPDrawnSelected(background)) return @"the tab in front still looks selected behind the bar";
            if (!standingIn && DPHoldsSelection(background)) return @"the tab in front doesn't look selected once the bar closes";
        }
    }
    return nil;
}

void DPInstallStandIn(void) {
    DPHook(DPDiaTabBackground, @selector(updateLayer), (IMP)DPTabBackground_updateLayer);
    DPHook(DPDiaTabBackground, @selector(layout), (IMP)DPTabBackground_layout);
    DPInstallFrontTab();
}

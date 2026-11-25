#import "HideToolbar.h"

static char DPFillKey, DPAppearanceKey, DPPlainAppliedKey, DPShowingKey;
static NSHashTable<NSView *> *DPTabFills;

static BOOL DPIsTabFill(NSView *view) {
    if (!DPIsKind(view.superview.superview, DPDiaTabShape)) return NO;
    for (NSView *up = view.superview; up; up = up.superview)
        if (DPIsKind(up, DPDiaTabStrip)) return YES;
    return NO;
}

static CGFloat DPToolbarShowing(NSWindow *window) {
    CGFloat showing = 0;
    for (NSView *pane in DPPanes) {
        NSView *bar = pane.window == window ? DPSubview(pane, DPDiaToolbar) : nil;
        if (bar && !bar.hiddenOrHasHiddenAncestor) showing = MAX(showing, bar.alphaValue);
    }
    return showing;
}

static BOOL DPPlainActive(void) { return DPPlainSelectedTab.on && DPHideToolbar.on; }

static BOOL DPPlain(NSView *fill) { return DPPlainActive() && DPToolbarShowing(fill.window) < 0.01; }

static void DPPlainAppearance(NSView *fill, BOOL plain) {
    NSView *tab = fill.superview.superview.superview.superview;
    if (!DPIsKind(tab, DPDiaTabView)) return;
    for (NSView *part in tab.subviews) {
        NSAppearance *dia = DPGet(part, &DPAppearanceKey);
        if (plain && part.appearance) {
            DPSet(part, &DPAppearanceKey, part.appearance);
            part.appearance = nil;
        } else if (!plain && dia) {
            if (!part.appearance && !fill.hiddenOrHasHiddenAncestor && fill.layer.backgroundColor) part.appearance = dia;
            DPSet(part, &DPAppearanceKey, nil);
        }
    }
}

static void DPFill_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFill_updateLayer, self);
    BOOL active = DPPlainActive();
    if ((!active && !DPGet(self, &DPPlainAppliedKey)) || !DPIsTabFill(self)) return;
    CGColorRef current = self.layer.backgroundColor;
    if (!current) {
        if (DPGet(self, &DPPlainAppliedKey)) {
            DPPlainAppearance(self, NO);
            DPSet(self, &DPPlainAppliedKey, nil);
        }
        return;
    }
    [DPTabFills addObject:self];
    NSColor *dia = DPGet(self, &DPFillKey);
    if (!CGColorEqualToColor(dia.CGColor, current)) DPSet(self, &DPFillKey, dia = [NSColor colorWithCGColor:current]);
    CGFloat plain = active ? 1 - DPToolbarShowing(self.window) : 0;
    if (plain > 0.5 || DPGet(self, &DPPlainAppliedKey)) DPPlainAppearance(self, plain > 0.5);
    DPSet(self, &DPPlainAppliedKey, plain > 0 ? @YES : nil);
    if (plain <= 0) return;
    NSView *strip = self;
    while (strip && !DPIsKind(strip, DPDiaTabStrip)) strip = strip.superview;
    __block NSColor *page;
    [(strip ?: self).effectiveAppearance performAsCurrentDrawingAppearance:^{ page = [NSColor.textBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; }];
    NSColor *fill = page ? [[dia colorUsingColorSpace:NSColorSpace.sRGBColorSpace] blendedColorWithFraction:plain ofColor:page] : nil;
    if (fill) self.layer.backgroundColor = fill.CGColor;
}

// Hide Toolbar calls this on every pane layout and ease step; only a change in how plain the tabs should be repaints them.
void DPRepaintTabs(NSWindow *window) {
    BOOL active = DPPlainActive();
    if (!window || (!active && !DPTabFills.count)) return;
    NSNumber *state = @(active ? DPToolbarShowing(window) : -1);
    if ([DPGet(window, &DPShowingKey) isEqual:state]) return;
    DPSet(window, &DPShowingKey, state);
    for (NSView *fill in DPTabFills)
        if (fill.window == window && (active || DPGet(fill, &DPPlainAppliedKey))) fill.needsDisplay = YES;
}

static void DPInstallPlainSelectedTab(void) {
    DPTabFills = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaColorView, @selector(updateLayer), (IMP)DPFill_updateLayer);
}

static void DPCollectTabFills(NSView *view, Class cls, NSMutableArray<NSView *> *out) {
    if ([view isKindOfClass:cls] && DPIsTabFill(view)) [out addObject:view];
    for (NSView *sub in view.subviews) DPCollectTabFills(sub, cls, out);
}

static void DPApplyPlainSelectedTab(DPPatch *patch) {
    NSMutableSet<NSView *> *fills = [NSMutableSet setWithArray:DPTabFills.allObjects ?: @[]];
    Class cls = objc_getClass(DPDiaColorView);
    if (cls) {
        NSMutableArray<NSView *> *all = [NSMutableArray new];
        for (NSWindow *window in NSApp.windows) DPCollectTabFills(window.contentView, cls, all);
        [fills addObjectsFromArray:all];
    }
    for (NSView *fill in fills) {
        if (!patch->on && DPGet(fill, &DPPlainAppliedKey)) {
            DPPlainAppearance(fill, NO);
            DPSet(fill, &DPPlainAppliedKey, nil);
            NSColor *dia = DPGet(fill, &DPFillKey);
            if (dia && fill.layer.backgroundColor) {
                DPWithoutAnimation(^{ fill.layer.backgroundColor = dia.CGColor; });
            }
        }
        fill.needsDisplay = YES;
    }
}

static NSString *DPVerifyPlainSelectedTab(DPPatch *patch) {
    for (NSView *fill in DPFindViews(DPDiaColorView)) {
        if (!DPIsTabFill(fill) || fill.hiddenOrHasHiddenAncestor || !fill.layer.backgroundColor) continue;
        if (!DPPlainActive()) {
            if (DPGet(fill, &DPPlainAppliedKey)) return @"selected tab is still plain";
            continue;
        }
        NSColor *dia = DPGet(fill, &DPFillKey);
        if (!dia) return @"selected tab's fill isn't watched";
        if (!DPPlain(fill) && !CGColorEqualToColor(dia.CGColor, fill.layer.backgroundColor)) return @"selected tab lost the site's color";
    }
    return nil;
}

DP_PATCH(DPPlainSelectedTab) {
    .key = @"plainSelectedTab",
    .order = 46,
    .title = @"Hide Site Color in Tab Bar",
    .detail = @"While the toolbar is hidden, show the selected tab in the page color instead of the site’s.",
    .symbol = @"paintbrush.fill",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"While It’s Hidden",
    .classes = DPClasses(DPDiaColorView, DPDiaTabShape, DPDiaTabStrip),
    .install = DPInstallPlainSelectedTab,
    .apply = DPApplyPlainSelectedTab,
    .verify = DPVerifyPlainSelectedTab,
};

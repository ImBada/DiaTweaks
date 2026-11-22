#import "HideToolbar.h"

static char DPFillKey, DPAppearanceKey, DPPlainAppliedKey;
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

static BOOL DPPlain(NSView *fill) { return DPPlainSelectedTab.on && DPHideToolbar.on && DPToolbarShowing(fill.window) < 0.01; }

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
    if (!DPIsTabFill(self)) return;
    if (!self.layer.backgroundColor) {
        if (DPGet(self, &DPPlainAppliedKey)) {
            DPPlainAppearance(self, NO);
            DPSet(self, &DPPlainAppliedKey, nil);
        }
        return;
    }
    [DPTabFills addObject:self];
    NSColor *dia = [NSColor colorWithCGColor:self.layer.backgroundColor];
    DPSet(self, &DPFillKey, dia);
    CGFloat plain = DPPlainSelectedTab.on && DPHideToolbar.on ? 1 - DPToolbarShowing(self.window) : 0;
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

void DPRepaintTabs(NSWindow *window) {
    BOOL active = DPPlainSelectedTab.on && DPHideToolbar.on;
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
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                fill.layer.backgroundColor = dia.CGColor;
                [CATransaction commit];
            }
        }
        fill.needsDisplay = YES;
    }
}

static NSString *DPVerifyPlainSelectedTab(DPPatch *patch) {
    for (NSView *fill in DPFindViews(DPDiaColorView)) {
        if (!DPIsTabFill(fill) || fill.hiddenOrHasHiddenAncestor || !fill.layer.backgroundColor) continue;
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
    .detail = @"While the toolbar is hidden, show the selected tab in the page color instead of the site's.",
    .symbol = @"paintbrush.fill",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"While It's Hidden",
    .classes = DPClasses(DPDiaColorView, DPDiaTabShape, DPDiaTabStrip),
    .install = DPInstallPlainSelectedTab,
    .apply = DPApplyPlainSelectedTab,
    .verify = DPVerifyPlainSelectedTab,
};

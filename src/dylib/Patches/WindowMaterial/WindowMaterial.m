#import "StdPatch/StdPatch.h"

extern DPPatch DPWindowMaterial, DPTranslucentSidebar;
static char DPHiddenKey, DPDiaHiddenKey, DPMaterialKey, DPGlassKey, DPOpaqueKey, DPAppliedKey, DPPendingMaterialKey;

static NSString *const DPMaterials[] = {
    [NSVisualEffectMaterialSidebar] = @"Sidebar",
    [NSVisualEffectMaterialUnderWindowBackground] = @"Under Window Background",
    [NSVisualEffectMaterialHeaderView] = @"Header",
    [NSVisualEffectMaterialTitlebar] = @"Titlebar",
    [NSVisualEffectMaterialMenu] = @"Menu",
    [NSVisualEffectMaterialPopover] = @"Popover",
    [NSVisualEffectMaterialHUDWindow] = @"HUD Window",
    [NSVisualEffectMaterialFullScreenUI] = @"Full Screen UI",
    [NSVisualEffectMaterialToolTip] = @"Tooltip",
};

// Index is AppKit's `_variant` value: don't reorder.
static NSString *const DPGlasses[] = {
    @"Regular", @"Clear", @"Dock", @"App Icons", @"Widgets", @"Text", @"AV Player", @"FaceTime", @"Control Center",
    @"Notification Center", @"Monogram", @"Bubbles", @"Identity", @"Focus Border", @"Focus Platter", @"Keyboard",
    @"Sidebar", @"Abutted Sidebar", @"Inspector", @"Control", @"Loupe", @"Slider", @"Camera", @"Cartouche Popover",
};

static Class DPGlassEffectView(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"NSGlassEffectView"); });
    return cls;
}

static NSMenu *DPMaterialChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Material"];
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"Materials"]];
    for (NSUInteger i = 0; i < sizeof DPMaterials / sizeof *DPMaterials; i++)
        if (DPMaterials[i]) [menu addItemWithTitle:DPMaterials[i] action:nil keyEquivalent:@""].representedObject = [NSString stringWithFormat:@"material.%lu", i];
    if (!DPGlassEffectView()) return menu;
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"Liquid Glass"]];
    for (NSUInteger i = 0; i < sizeof DPGlasses / sizeof *DPGlasses; i++)
        [menu addItemWithTitle:DPGlasses[i] action:nil keyEquivalent:@""].representedObject = [NSString stringWithFormat:@"glass.%lu", i];
    return menu;
}

static NSString *DPWindowMaterialChoice(void) {
    NSString *choice = DPChoice(&DPWindowMaterial);
    BOOL unsupported = [choice hasPrefix:@"glass."] && !DPGlassEffectView();
    return unsupported ? [NSString stringWithFormat:@"material.%ld", (long)NSVisualEffectMaterialSidebar] : choice;
}

static void DPView_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    if (![DPGet(self, &DPHiddenKey) boolValue]) return DPCallOriginal(DPView_setHidden, self, hidden);
    DPSet(self, &DPDiaHiddenKey, @(hidden));
    DPCallOriginal(DPView_setHidden, self, YES);
}

static void DPHide(NSView *view, BOOL hide) {
    if (!view) return;
    if (!hide && !DPGet(view, &DPHiddenKey)) return;
    if (hide) {
        if ([DPGet(view, &DPHiddenKey) boolValue] && view.hidden) return;
        BOOL dia = DPGet(view, &DPDiaHiddenKey) ? [DPGet(view, &DPDiaHiddenKey) boolValue] : view.hidden;
        DPHookClass(view.class, @selector(setHidden:), (IMP)DPView_setHidden);
        DPSet(view, &DPHiddenKey, @YES);
        view.hidden = dia;
    } else {
        BOOL dia = [DPGet(view, &DPDiaHiddenKey) boolValue];
        DPSet(view, &DPHiddenKey, nil);
        DPSet(view, &DPDiaHiddenKey, nil);
        view.hidden = dia;
    }
}

static void DPCollectEffects(NSView *view, NSMutableArray<NSVisualEffectView *> *effects) {
    if ([view isKindOfClass:NSVisualEffectView.class]) [effects addObject:(NSVisualEffectView *)view];
    for (NSView *sub in view.subviews) DPCollectEffects(sub, effects);
}

// Not the selected tab's own copy, which sits deeper.
static NSView *DPTintIn(NSView *view) {
    for (NSView *sub in view.subviews)
        for (NSView *inner in sub.subviews) if (DPIsKind(inner, DPDiaWindowTint)) return inner;
    return nil;
}

static NSView *DPWashIn(NSView *tint) {
    for (NSView *view in tint.subviews) if (DPIsKind(view, DPDiaColorView)) return view;
    return nil;
}

static NSVisualEffectMaterial DPWindowBackgroundMaterial(NSWindow *window) {
    NSView *effect = DPFindView(DPTintIn(window.contentView.superview).superview, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSVisualEffectView.class] && !view.isHiddenOrHasHiddenAncestor;
    });
    return effect ? ((NSVisualEffectView *)effect).material : NSVisualEffectMaterialUnderWindowBackground;
}

static void DPApplyMaterialUnder(NSView *tint, BOOL floating) {
    NSView *content = tint.superview;
    if (!content) return;
    NSString *choice = DPWindowMaterial.on ? DPWindowMaterialChoice() : nil;
    BOOL translucent = choice || (floating && DPTranslucentSidebar.on), glass = [choice hasPrefix:@"glass."];
    if (!translucent && !DPGet(tint, &DPAppliedKey)) return;
    DPSet(tint, &DPAppliedKey, translucent ? @YES : nil);
    NSInteger value = choice.pathExtension.integerValue;

    NSMutableArray<NSView *> *backgrounds = [NSMutableArray array];
    if (!floating) for (NSView *view in content.superview.subviews) if ([view isKindOfClass:NSVisualEffectView.class]) [backgrounds addObject:view];
    NSView *glassView = DPGet(content, &DPGlassKey);
    for (NSView *view in content.subviews) {
        if (view == tint) break;
        if (view != glassView) [backgrounds addObject:view];
    }
    NSMutableArray<NSVisualEffectView *> *effects = [NSMutableArray array];
    for (NSView *view in backgrounds) DPCollectEffects(view, effects);
    NSVisualEffectBlendingMode blending = floating ? NSVisualEffectBlendingModeWithinWindow : NSVisualEffectBlendingModeBehindWindow;
    BOOL restoring = !translucent || glass;
    for (NSVisualEffectView *effect in effects) {
        if (restoring && !DPGet(effect, &DPMaterialKey)) continue;
        NSArray *dia = DPDiaValue(effect, &DPMaterialKey, @[ @(effect.material), @(effect.blendingMode), @(effect.state) ]);
        if (restoring) {
            DPSet(effect, &DPMaterialKey, nil);
            NSVisualEffectMaterial diaMat = [dia[0] integerValue];
            NSVisualEffectBlendingMode diaBlend = [dia[1] integerValue];
            NSVisualEffectState diaState = [dia[2] integerValue];
            if (effect.material != diaMat) effect.material = diaMat;
            if (effect.blendingMode != diaBlend) effect.blendingMode = diaBlend;
            if (effect.state != diaState) effect.state = diaState;
            continue;
        }
        NSVisualEffectMaterial wantMat = choice ? value : DPWindowBackgroundMaterial(tint.window);
        if (effect.material != wantMat) effect.material = wantMat;
        if (effect.blendingMode != blending) effect.blendingMode = blending;
        if (effect.state != NSVisualEffectStateActive) effect.state = NSVisualEffectStateActive;
        // Record AppKit's accepted values (e.g. Sidebar clamps WithinWindow to BehindWindow) so restore recognizes them.
        DPOverride(effect, &DPMaterialKey, dia, @[ @(effect.material), @(effect.blendingMode), @(effect.state) ]);
    }
    DPHide(DPWashIn(tint), translucent);
    for (NSView *view in backgrounds) DPHide(view, glass);

    // A drawn glass view ignores a new variant.
    id currentVariant = glassView ? DPValueForKey(glassView, @"_variant") : nil;
    if (glassView && (!glass || (currentVariant && [currentVariant integerValue] != value))) {
        [glassView removeFromSuperview];
        DPSet(content, &DPGlassKey, glassView = nil);
    }
    if (glass && !glassView) {
        glassView = [[DPGlassEffectView() alloc] initWithFrame:content.bounds];
        glassView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        DPSetValueForKey(glassView, @"cornerRadius", @(content.layer.cornerRadius));
        [content addSubview:glassView positioned:NSWindowBelow relativeTo:nil];
        DPSet(content, &DPGlassKey, glassView);
        DPSetValueForKey(glassView, @"_variant", @(value));
    } else if (glassView) {
        id currentRadius = DPValueForKey(glassView, @"cornerRadius");
        if (currentRadius && [currentRadius doubleValue] != content.layer.cornerRadius)
            DPSetValueForKey(glassView, @"cornerRadius", @(content.layer.cornerRadius));
    }
    if (floating) return;

    NSWindow *window = tint.window;
    if (!window) return;
    if (!translucent && !DPGet(window, &DPOpaqueKey)) return;
    id currentBG = window.backgroundColor ?: NSNull.null;
    NSArray *dia = DPDiaValue(window, &DPOpaqueKey, @[ @(window.opaque), currentBG ]);
    NSArray *ours = translucent ? @[ @NO, NSColor.clearColor ] : dia;
    if (translucent) DPOverride(window, &DPOpaqueKey, dia, ours);
    else DPSet(window, &DPOpaqueKey, nil);
    if (window.opaque != [ours[0] boolValue]) window.opaque = [ours[0] boolValue];
    NSColor *targetBG = ours[1] == NSNull.null ? nil : ours[1];
    if (window.backgroundColor != targetBG && ![window.backgroundColor isEqual:targetBG]) window.backgroundColor = targetBG;
}

static NSArray<NSView *> *DPWindowFrames(void) {
    NSMutableArray *frames = [NSMutableArray array];
    for (NSWindow *window in NSApp.windows) if (DPIsKind(window.contentView.superview, DPDiaWindowFrame)) [frames addObject:window.contentView.superview];
    return frames;
}

// A hidden tint stops laying out, the theme frame doesn't.
static void DPWindowFrame_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPWindowFrame_layout, self);
    NSView *tint = DPTintIn(self);
    if (DPWindowMaterial.on || DPGet(tint, &DPAppliedKey)) DPApplyMaterialUnder(tint, NO);
}

static void DPFloatingSidebar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFloatingSidebar_layout, self);
    NSView *tint = DPTintIn(self);
    if (DPWindowMaterial.on || DPTranslucentSidebar.on || DPGet(tint, &DPAppliedKey)) DPApplyMaterialUnder(tint, YES);
}

static void DPBackgroundTile_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPBackgroundTile_updateLayer, self);
    if (!DPWindowMaterial.on && !DPTranslucentSidebar.on) return;
    for (NSView *host = self.superview; host; host = host.superview) {
        NSView *tint = DPTintIn(host);
        if (!tint) continue;
        if ([DPGet(tint, &DPPendingMaterialKey) boolValue]) return;
        DPSet(tint, &DPPendingMaterialKey, @YES);
        BOOL floating = DPIsKind(host, DPDiaFloatingSidebar);
        __weak NSView *weakTint = tint;
        // Defer subview and window mutations out of AppKit's updateLayer display pass.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSView *strongTint = weakTint;
            if (!strongTint) return;
            DPSet(strongTint, &DPPendingMaterialKey, nil);
            DPApplyMaterialUnder(strongTint, floating);
        });
        return;
    }
}

void DPApplyWindowMaterial(DPPatch *patch) {
    for (NSView *frame in DPWindowFrames()) DPApplyMaterialUnder(DPTintIn(frame), NO);
    Class floatingCls = objc_getClass(DPDiaFloatingSidebar);
    if (!floatingCls) return;
    for (NSWindow *window in NSApp.windows)
        DPFindView(window.contentView, ^BOOL(NSView *view) {
            if ([view isKindOfClass:floatingCls]) DPApplyMaterialUnder(DPTintIn(view), YES);
            return NO;
        });
}

NSString *DPVerifyWindowMaterial(DPPatch *patch) {
    BOOL glass = DPWindowMaterial.on && [DPWindowMaterialChoice() hasPrefix:@"glass."];
    NSArray<NSView *> *floating = DPFindViews(DPDiaFloatingSidebar);
    for (NSView *host in [DPWindowFrames() arrayByAddingObjectsFromArray:floating]) {
        NSView *tint = DPTintIn(host);
        BOOL translucent = DPWindowMaterial.on || (DPTranslucentSidebar.on && [floating containsObject:host]);
        NSView *wash = DPWashIn(tint);
        if (!wash) return @"no theme color to replace";
        if (tint.hidden) return @"profile color hidden";
        if (wash.hidden != translucent) return translucent ? @"theme color still shows" : @"theme color still hidden";
        if ((DPGet(tint.superview, &DPGlassKey) != nil) != glass) return glass ? @"no glass behind the window" : @"glass left behind";
        NSVisualEffectView *effect = (NSVisualEffectView *)DPFindView(tint.superview, ^BOOL(NSView *view) {
            return [view isKindOfClass:NSVisualEffectView.class] && !view.isHiddenOrHasHiddenAncestor;
        });
        if (DPWindowMaterial.on && !glass && effect.material != DPWindowMaterialChoice().pathExtension.integerValue) return @"Dia's material came back";
    }
    return nil;
}

static void DPInstallWindowMaterial(void) {
    DPHook(DPDiaWindowFrame, @selector(layout), (IMP)DPWindowFrame_layout);
    DPHook(DPDiaFloatingSidebar, @selector(layout), (IMP)DPFloatingSidebar_layout);
    DPHook(DPDiaWindowBackgroundTile, @selector(updateLayer), (IMP)DPBackgroundTile_updateLayer);
}

DP_PATCH(DPWindowMaterial) {
    .key = @"windowMaterial",
    .order = 84,
    .title = @"Window Material",
    .detail = @"Show a material or Liquid Glass behind the tabs and sidebar, still tinted with the profile’s color.",
    .symbol = @"circle.on.app.liquid.glass.fill square.2.layers.3d.top.filled",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaWindowFrame, DPDiaWindowTint, DPDiaWindowBackgroundTile, DPDiaFloatingSidebar),
    .choice = @"windowMaterialChoice",
    .defaultChoice = @"glass.17",
    .choices = DPMaterialChoices,
    .installLate = YES,
    .install = DPInstallWindowMaterial,
    .apply = DPApplyWindowMaterial,
    .verify = DPVerifyWindowMaterial,
};

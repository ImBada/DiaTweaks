#import "ProfileColorPicker.h"
#import "Commands/GroupTabs/GroupTabs.h"

static char DPColorsKey, DPAlphaKey, DPLastSpaceKey, DPOverrideSpaceKey, DPWindowCacheKey;

@interface DPWindowColorCache : NSObject {
@public
    NSHashTable<NSView *> *gradients;
    __weak NSView *switcher, *dot, *tabList;
    BOOL scannedSpace, hadIndicator;
}
@end

@implementation DPWindowColorCache
- (instancetype)init {
    if ((self = [super init])) gradients = [NSHashTable weakObjectsHashTable];
    return self;
}
@end

static DPWindowColorCache *DPColorCacheFor(NSWindow *window, BOOL create) {
    if (!window) return nil;
    DPWindowColorCache *cache = DPGet(window, &DPWindowCacheKey);
    if (!cache && create) DPSet(window, &DPWindowCacheKey, cache = [DPWindowColorCache new]);
    return cache;
}

static void DPInvalidateWindowColorCache(NSWindow *window) {
    DPWindowColorCache *cache = DPColorCacheFor(window, NO);
    if (!cache) return;
    [cache->gradients removeAllObjects];
    cache->scannedSpace = NO;
}

static BOOL DPIsPrivateWindow(NSWindow *window) {
    id browser = DPBrowserOfWindow(window);
    id context = [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
    id contextID = [context respondsToSelector:@selector(id)] ? DPMsg(context, @selector(id)) : nil;
    return [contextID respondsToSelector:@selector(isIncognito)] && DPMsgBool(contextID, @selector(isIncognito));
}

static BOOL DPIsTintGradient(NSView *view) { return DPIsKind(view, DPDiaGradientView) && DPIsKind(view.superview, DPDiaWindowTint); }

static CAGradientLayer *DPGradientLayer(NSView *gradient) {
    for (CALayer *layer in gradient.layer.sublayers)
        if ([layer isKindOfClass:CAGradientLayer.class]) return (CAGradientLayer *)layer;
    return nil;
}

static NSString *DPSpaceFromSwitcher(NSView *switcher) {
    NSDictionary *items = DPSwiftValue(switcher, @"itemViews");
    for (id key in items) if ([DPSwiftValue(items[key], @"isSelected") boolValue]) return DPNormalizedSpaceID(key);
    return nil;
}

static NSString *DPWindowSpaceID(NSWindow *window) {
    if (!window) return nil;
    if (DPIsKind(window, DPDiaAnchoredPanel)) return DPAnchoredPanelSpaceID(window);
    if (DPIsPrivateWindow(window)) return nil;
    DPWindowColorCache *cache = DPColorCacheFor(window, YES);
    if (!cache->scannedSpace || (cache->hadIndicator && cache->switcher.window != window && cache->dot.window != window)) {
        cache->switcher = nil;
        cache->dot = nil;
        cache->tabList = nil;
        DPFindView(window.contentView, ^BOOL(NSView *view) {
            if (!cache->switcher && DPIsKind(view, DPDiaSpaceSwitcher)) cache->switcher = view;
            else if (!cache->dot && DPIsKind(view, DPDiaPageIndicatorDot)) cache->dot = view;
            else if (!cache->tabList && DPIsKind(view, DPDiaTabList)) cache->tabList = view;
            return NO;
        });
        cache->scannedSpace = YES;
        cache->hadIndicator = cache->switcher != nil || cache->dot != nil;
    }
    NSString *space = cache->switcher.window == window ? DPSpaceFromSwitcher(cache->switcher) : nil;
    if (!space && cache->dot.window == window) space = DPNormalizedSpaceID(DPSwiftValue(cache->dot.superview, @"focusedSpaceID"));
    if (space) return space;
    id delegate = DPSwiftValue(DPSwiftValue(window, @"viewModel"), @"delegate");
    space = DPNormalizedSpaceID(DPSwiftValue(delegate, @"committedFocusedSpaceID"))
        ?: DPNormalizedSpaceID(DPSwiftValue(delegate, @"initialFocusedSpaceID"));
    if (space) return space;
    NSView *tabList = cache->tabList.window == window ? cache->tabList : nil;
    return DPNormalizedSpaceID(DPSwiftValue(DPSwiftValue(DPSwiftValue(tabList, @"viewModel"), @"delegate"), @"spaceID"));
}

static double DPTintIntensityOf(NSView *tintView) {
    static ptrdiff_t tintOffset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = objc_getClass(DPDiaWindowTint);
        Ivar ivar = cls ? class_getInstanceVariable(cls, "tint") : NULL;
        ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : -1;
        if (cls && offset >= 0 && (size_t)offset + 0x20 <= class_getInstanceSize(cls)) tintOffset = offset;
    });
    if (!tintView || tintOffset < 0) return 0.0;
    double value = 0.0;
    memcpy(&value, (const uint8_t *)(__bridge const void *)tintView + tintOffset + 0x18, sizeof value);
    return isfinite(value) && value >= -1.0 && value <= 1.25 ? value : 0.0;
}

static BOOL DPSetLayerColors(CAGradientLayer *layer, NSArray *colors) {
    if (layer.colors == colors || [layer.colors isEqual:colors]) return NO;
    DPWithoutAnimation(^{ layer.colors = colors; });
    return YES;
}

static CGFloat DPNeutralFallbackAlpha(BOOL dark, double intensity) {
    if (!isfinite(intensity)) intensity = 0.0;
    if (intensity >= 1.0) return dark ? 0.90 : 1.0;
    CGFloat base = dark ? 0.50 : 0.75;
    CGFloat edge = intensity < 0.0 ? (dark ? 0.15 : 0.45) : (dark ? 0.75 : 1.0);
    return base + (edge - base) * MIN(fabs(intensity), 1.0);
}

static void DPNotifyProfileColorChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:@"DPProfileColorDidChange" object:nil];
}

static BOOL DPRestoreGradient(NSView *gradient, CAGradientLayer *layer, NSString *spaceID) {
    BOOL changed = NO;
    NSString *savedSpace = DPGet(gradient, &DPOverrideSpaceKey);
    BOOL sameSpace = !savedSpace || !spaceID || [savedSpace isEqualToString:spaceID];
    DPSet(gradient, &DPOverrideSpaceKey, nil);
    if (DPGet(layer, &DPColorsKey)) {
        id dia = DPDiaValue(layer, &DPColorsKey, layer.colors ?: NSNull.null);
        BOOL stillOurs = !sameSpace && [((NSArray *)DPGet(layer, &DPColorsKey))[1] isEqual:(layer.colors ?: NSNull.null)];
        DPSet(layer, &DPColorsKey, nil);
        if (sameSpace || stillOurs) changed = DPSetLayerColors(layer, dia == NSNull.null ? nil : dia);
        if (stillOurs) {
            gradient.needsDisplay = YES;
            gradient.superview.needsDisplay = YES;
        }
    }
    if (DPGet(gradient, &DPAlphaKey)) {
        NSNumber *diaAlpha = DPDiaValue(gradient, &DPAlphaKey, @(gradient.alphaValue));
        DPSet(gradient, &DPAlphaKey, nil);
        // Only restore Neutral's 0 alpha on the same space; switching spaces must not wipe another space's tint.
        if (sameSpace) gradient.alphaValue = diaAlpha.doubleValue;
        else gradient.superview.needsDisplay = YES;
    }
    return changed;
}

static BOOL DPApplyGradientInSpace(NSView *gradient, NSString *spaceID) {
    if (!DPIsKind(gradient.superview, DPDiaWindowTint)) return NO;
    CAGradientLayer *layer = DPGradientLayer(gradient);
    if (!layer) return NO;
    NSString *hex = DPProfileHexForSpace(spaceID);
    if (!hex) return DPRestoreGradient(gradient, layer, spaceID);
    BOOL dark = [[gradient.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
        isEqual:NSAppearanceNameDarkAqua];
    double intensity = DPTintIntensityOf(gradient.superview);
    NSArray *ours = DPProfileGradientColorsForHex(hex, dark, intensity);
    if (!ours) return DPRestoreGradient(gradient, layer, spaceID);
    DPSet(gradient, &DPOverrideSpaceKey, spaceID);
    id dia = DPDiaValue(layer, &DPColorsKey, layer.colors ?: NSNull.null);
    DPOverride(layer, &DPColorsKey, dia, ours);
    BOOL changed = DPSetLayerColors(layer, ours);
    if (gradient.alphaValue < 0.01 || DPGet(gradient, &DPAlphaKey)) {
        NSNumber *diaAlpha = DPDiaValue(gradient, &DPAlphaKey, @(gradient.alphaValue));
        if (diaAlpha.doubleValue < 0.01) {
            CGFloat targetAlpha = DPNeutralFallbackAlpha(dark, intensity);
            DPOverride(gradient, &DPAlphaKey, diaAlpha, @(targetAlpha));
            gradient.alphaValue = targetAlpha;
        } else {
            DPSet(gradient, &DPAlphaKey, nil);
        }
    }
    return changed;
}

static BOOL DPApplyGradient(NSView *gradient) {
    return DPApplyGradientInSpace(gradient, DPProfileColorPicker.on ? DPWindowSpaceID(gradient.window) : nil);
}

static NSArray<NSView *> *DPWindowTintGradients(NSWindow *window) {
    NSView *root = window.contentView.superview ?: window.contentView;
    if (!root) return @[];
    DPWindowColorCache *cache = DPColorCacheFor(window, YES);
    NSMutableArray<NSView *> *live = [NSMutableArray new];
    for (NSView *view in cache->gradients.allObjects)
        if (view.window == window && DPIsTintGradient(view)) [live addObject:view];
    if (live.count) return live;
    DPFindView(root, ^BOOL(NSView *view) {
        if (DPIsTintGradient(view)) {
            [cache->gradients addObject:view];
            [live addObject:view];
        }
        return NO;
    });
    return live;
}

static BOOL DPApplyWindowProfileColor(NSWindow *window) {
    NSArray<NSView *> *gradients = DPWindowTintGradients(window);
    if (!gradients.count) return NO;
    NSString *spaceID = DPProfileColorPicker.on ? DPWindowSpaceID(window) : nil;
    if (DPProfileColorPicker.on) DPSet(window, &DPLastSpaceKey, spaceID ?: @"");
    BOOL changed = NO;
    for (NSView *gradient in gradients) changed = DPApplyGradientInSpace(gradient, spaceID) || changed;
    return changed;
}

void DPRefreshProfileColorForWindow(NSWindow *window) {
    if (DPApplyWindowProfileColor(window) && !DPIsPrivateWindow(window)) DPNotifyProfileColorChanged();
}

void DPRefreshProfileColors(void) {
    BOOL changed = NO;
    NSMutableArray<NSWindow *> *privateWindows = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows) {
        if (!DPProfileColorPicker.on) {
            DPSet(window, &DPLastSpaceKey, nil);
            DPInvalidateWindowColorCache(window);
        }
        if (DPIsKind(window, DPDiaWindow) && DPIsPrivateWindow(window)) [privateWindows addObject:window];
        else changed = DPApplyWindowProfileColor(window) || changed;
    }
    if (changed) DPNotifyProfileColorChanged();
    for (NSWindow *window in privateWindows)
        for (NSView *view in DPWindowTintGradients(window)) view.needsDisplay = YES;
}

static void DPMaybeRefreshWindowSpace(NSWindow *window) {
    if (!DPProfileColorPicker.on || !window) return;
    NSString *space = DPWindowSpaceID(window) ?: @"", *last = DPGet(window, &DPLastSpaceKey);
    if (last && [last isEqualToString:space]) return;
    DPSet(window, &DPLastSpaceKey, space);
    DPInvalidateWindowColorCache(window);
    DPRefreshProfileColorForWindow(window);
}

static void DPColorGradient_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorGradient_updateLayer, self);
    if (!DPIsKind(self.superview, DPDiaWindowTint)) return;
    if (self.window) [DPColorCacheFor(self.window, YES)->gradients addObject:self];
    CAGradientLayer *layer = DPGradientLayer(self);
    if ((DPProfileColorPicker.on || DPGet(layer, &DPColorsKey) || DPGet(self, &DPAlphaKey)) && DPApplyGradient(self) && !DPIsPrivateWindow(self.window))
        DPNotifyProfileColorChanged();
}

static void DPColorTint_updateLayer(NSView *self, SEL _cmd) {
    // Restore overridden alpha before Dia updates the layer so Dia's fresh alpha isn't confused with our override.
    for (NSView *sub in self.subviews) {
        if (!DPIsKind(sub, DPDiaGradientView)) continue;
        NSArray *saved = DPGet(sub, &DPAlphaKey);
        if (saved) {
            if (fabs(sub.alphaValue - [saved[1] doubleValue]) < 1e-4) sub.alphaValue = [saved[0] doubleValue];
            DPSet(sub, &DPAlphaKey, nil);
        }
    }
    DPCallOriginal(DPColorTint_updateLayer, self);
    BOOL changed = NO;
    NSWindow *window = self.window;
    NSString *spaceID = DPProfileColorPicker.on ? DPWindowSpaceID(window) : nil;
    for (NSView *sub in self.subviews) {
        if (!DPIsKind(sub, DPDiaGradientView)) continue;
        if (window) [DPColorCacheFor(window, YES)->gradients addObject:sub];
        CAGradientLayer *layer = DPGradientLayer(sub);
        if (DPProfileColorPicker.on || DPGet(layer, &DPColorsKey) || DPGet(sub, &DPAlphaKey))
            changed = DPApplyGradientInSpace(sub, spaceID) || changed;
    }
    if (changed && !DPIsPrivateWindow(window)) DPNotifyProfileColorChanged();
}

static void DPColorSwitcher_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorSwitcher_updateLayer, self);
    if (!DPProfileColorPicker.on || !self.window) return;
    if (DPIsKind(self.superview, DPDiaSpaceSwitcher)) {
        DPWindowColorCache *cache = DPColorCacheFor(self.window, YES);
        cache->switcher = self.superview;
        cache->hadIndicator = YES;
    }
    if ([DPSwiftValue(self, @"isSelected") boolValue]) DPRefreshProfileColorForWindow(self.window);
}

static void DPColorDot_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorDot_layout, self);
    if (!DPProfileColorPicker.on || !self.window) return;
    DPWindowColorCache *cache = DPColorCacheFor(self.window, YES);
    cache->dot = self;
    cache->hadIndicator = YES;
    DPMaybeRefreshWindowSpace(self.window);
}

static void DPColorDot_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorDot_updateLayer, self);
    if (!DPProfileColorPicker.on || !self.window) return;
    DPWindowColorCache *cache = DPColorCacheFor(self.window, YES);
    cache->dot = self;
    cache->hadIndicator = YES;
    if ([DPSwiftValue(self, @"isSelected") boolValue]) DPRefreshProfileColorForWindow(self.window);
}

static void DPColorController_viewDidLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPColorController_viewDidLayout, self);
    DPMaybeRefreshWindowSpace(self.view.window);
}

NSString *DPVerifyProfileColorTint(DPPatch *patch) {
    if (!DPIsHooked(objc_getClass(DPDiaWindowTint), @selector(updateLayer), (IMP)DPColorTint_updateLayer))
        return @"window tint hook didn't install";
    for (NSWindow *window in NSApp.windows) {
        if (!window.isVisible || !DPIsKind(window, DPDiaWindow) || DPIsPrivateWindow(window)) continue;
        BOOL hasCustom = patch->on && DPProfileHexForSpace(DPWindowSpaceID(window)) != nil;
        __block NSString *problem = nil;
        DPFindView(window.contentView.superview ?: window.contentView, ^BOOL(NSView *view) {
            if (!DPIsTintGradient(view)) return NO;
            CAGradientLayer *layer = DPGradientLayer(view);
            if ((layer && DPGet(layer, &DPColorsKey) != nil) != hasCustom) {
                problem = hasCustom ? @"window missed custom profile color" : @"custom profile color stayed applied";
                return YES;
            }
            return NO;
        });
        if (problem) return problem;
    }
    return nil;
}

void DPInstallProfileColorTint(void) {
    DPHook(DPDiaGradientView, @selector(updateLayer), (IMP)DPColorGradient_updateLayer);
    DPHook(DPDiaWindowTint, @selector(updateLayer), (IMP)DPColorTint_updateLayer);
    if (objc_getClass(DPDiaSpaceSwitcherItem)) DPHook(DPDiaSpaceSwitcherItem, @selector(updateLayer), (IMP)DPColorSwitcher_updateLayer);
    if (objc_getClass(DPDiaPageIndicatorDot)) {
        DPHook(DPDiaPageIndicatorDot, @selector(layout), (IMP)DPColorDot_layout);
        DPHook(DPDiaPageIndicatorDot, @selector(updateLayer), (IMP)DPColorDot_updateLayer);
    }
    if (objc_getClass(DPDiaSidebarController)) DPHook(DPDiaSidebarController, @selector(viewDidLayout), (IMP)DPColorController_viewDidLayout);
    if (objc_getClass(DPDiaTabStripController)) DPHook(DPDiaTabStripController, @selector(viewDidLayout), (IMP)DPColorController_viewDidLayout);
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (![note.object isKindOfClass:NSWindow.class]) return;
        DPInvalidateWindowColorCache(note.object);
        if (DPProfileColorPicker.on) DPRefreshProfileColorForWindow(note.object);
    }];
}

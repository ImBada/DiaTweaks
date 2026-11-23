#import "ProfileColorPicker.h"
#import "Commands/GroupTabs/GroupTabs.h"

static char DPColorsKey, DPAlphaKey, DPLastSpaceKey, DPOverrideSpaceKey;

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

static NSString *DPWindowSpaceID(NSWindow *window) {
    if (!window) return nil;
    if (DPIsKind(window, DPDiaAnchoredPanel)) return DPAnchoredPanelSpaceID(window);
    if (DPIsPrivateWindow(window)) return nil;
    __block NSString *space = nil;
    DPFindView(window.contentView, ^BOOL(NSView *view) {
        if (DPIsKind(view, DPDiaSpaceSwitcher)) {
            NSDictionary *items = DPSwiftValue(view, @"itemViews");
            for (id key in items) if ([DPSwiftValue(items[key], @"isSelected") boolValue]) { space = DPNormalizedSpaceID(key); break; }
        } else if (DPIsKind(view, DPDiaPageIndicatorDot)) {
            space = DPNormalizedSpaceID(DPSwiftValue(view.superview, @"focusedSpaceID"));
        }
        return space != nil;
    });
    if (space) return space;
    id delegate = DPSwiftValue(DPSwiftValue(window, @"viewModel"), @"delegate");
    space = DPNormalizedSpaceID(DPSwiftValue(delegate, @"committedFocusedSpaceID"))
        ?: DPNormalizedSpaceID(DPSwiftValue(delegate, @"initialFocusedSpaceID"));
    if (space) return space;
    NSView *tabList = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabList); });
    return DPNormalizedSpaceID(DPSwiftValue(DPSwiftValue(DPSwiftValue(tabList, @"viewModel"), @"delegate"), @"spaceID"));
}

static double DPTintIntensityOf(NSView *tintView) {
    Class cls = tintView ? object_getClass(tintView) : Nil;
    Ivar ivar = cls ? class_getInstanceVariable(cls, "tint") : NULL;
    if (!ivar) return 0.0;
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset < 0 || (size_t)offset + 0x20 > class_getInstanceSize(cls)) return 0.0;
    double value = 0.0;
    memcpy(&value, (const uint8_t *)(__bridge const void *)tintView + offset + 0x18, sizeof value);
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

static BOOL DPApplyGradient(NSView *gradient) {
    if (!DPIsKind(gradient.superview, DPDiaWindowTint)) return NO;
    CAGradientLayer *layer = DPGradientLayer(gradient);
    if (!layer) return NO;
    NSString *spaceID = DPProfileColorPicker.on ? DPWindowSpaceID(gradient.window) : nil;
    NSColor *custom = DPColorFromHex(DPProfileHexForSpace(spaceID), NULL);
    if (!custom) return DPRestoreGradient(gradient, layer, spaceID);
    BOOL dark = [[gradient.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
        isEqual:NSAppearanceNameDarkAqua];
    double intensity = DPTintIntensityOf(gradient.superview);
    NSArray *ours = DPProfileGradientColors(custom, dark, intensity);
    if (!ours) return NO;
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

static BOOL DPApplyWindowProfileColor(NSWindow *window) {
    NSView *root = window.contentView.superview ?: window.contentView;
    if (!root) return NO;
    __block BOOL changed = NO;
    DPFindView(root, ^BOOL(NSView *view) {
        if (DPIsTintGradient(view)) changed = DPApplyGradient(view) || changed;
        return NO;
    });
    return changed;
}

void DPRefreshProfileColorForWindow(NSWindow *window) {
    if (DPApplyWindowProfileColor(window) && !DPIsPrivateWindow(window)) DPNotifyProfileColorChanged();
}

void DPRefreshProfileColors(void) {
    BOOL changed = NO;
    NSMutableArray<NSWindow *> *privateWindows = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows) {
        if (!DPProfileColorPicker.on) DPSet(window, &DPLastSpaceKey, nil);
        if (DPIsKind(window, DPDiaWindow) && DPIsPrivateWindow(window)) [privateWindows addObject:window];
        else changed = DPApplyWindowProfileColor(window) || changed;
    }
    if (changed) DPNotifyProfileColorChanged();
    for (NSWindow *window in privateWindows) {
        DPFindView(window.contentView.superview ?: window.contentView, ^BOOL(NSView *view) {
            if (DPIsTintGradient(view)) view.needsDisplay = YES;
            return NO;
        });
    }
}

static void DPMaybeRefreshWindowSpace(NSWindow *window) {
    if (!DPProfileColorPicker.on || !window) return;
    NSString *space = DPWindowSpaceID(window) ?: @"", *last = DPGet(window, &DPLastSpaceKey);
    if (last && [last isEqualToString:space]) return;
    DPSet(window, &DPLastSpaceKey, space);
    DPRefreshProfileColorForWindow(window);
}

static void DPColorGradient_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorGradient_updateLayer, self);
    if (!DPIsKind(self.superview, DPDiaWindowTint)) return;
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
    for (NSView *sub in self.subviews) {
        if (!DPIsKind(sub, DPDiaGradientView)) continue;
        CAGradientLayer *layer = DPGradientLayer(sub);
        if (DPProfileColorPicker.on || DPGet(layer, &DPColorsKey) || DPGet(sub, &DPAlphaKey)) changed = DPApplyGradient(sub) || changed;
    }
    if (changed && !DPIsPrivateWindow(self.window)) DPNotifyProfileColorChanged();
}

static void DPColorSwitcher_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorSwitcher_updateLayer, self);
    if (DPProfileColorPicker.on && [DPSwiftValue(self, @"isSelected") boolValue]) DPRefreshProfileColorForWindow(self.window);
}

static void DPColorDot_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorDot_layout, self);
    if (DPProfileColorPicker.on) DPMaybeRefreshWindowSpace(self.window);
}

static void DPColorDot_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPColorDot_updateLayer, self);
    if (DPProfileColorPicker.on && [DPSwiftValue(self, @"isSelected") boolValue]) DPRefreshProfileColorForWindow(self.window);
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
        if (DPProfileColorPicker.on && [note.object isKindOfClass:NSWindow.class]) DPRefreshProfileColorForWindow(note.object);
    }];
}

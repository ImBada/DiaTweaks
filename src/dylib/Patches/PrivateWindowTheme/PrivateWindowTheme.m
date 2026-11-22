#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPPrivateWindowTheme;
static char DPColorsKey;

static BOOL DPIsPrivate(NSWindow *window) {
    id browser = DPBrowserOfWindow(window);
    id context = [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
    id contextID = [context respondsToSelector:@selector(id)] ? DPMsg(context, @selector(id)) : nil;
    return [contextID respondsToSelector:@selector(isIncognito)] && DPMsgBool(contextID, @selector(isIncognito));
}

static NSView *DPWindowGradient(NSWindow *window) {
    return DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaGradientView) && DPIsKind(view.superview, DPDiaWindowTint); });
}

static CAGradientLayer *DPGradientLayer(NSView *gradient) {
    for (CALayer *layer in gradient.layer.sublayers) if ([layer isKindOfClass:CAGradientLayer.class]) return (CAGradientLayer *)layer;
    return nil;
}

static CAGradientLayer *DPThemeSource(void) {
    for (NSWindow *window in NSApp.orderedWindows) {
        CAGradientLayer *layer = DPIsKind(window, DPDiaWindow) && !DPIsPrivate(window) ? DPGradientLayer(DPWindowGradient(window)) : nil;
        if (layer) return layer;
    }
    return nil;
}

static void DPThemePrivate(NSView *gradient) {
    CAGradientLayer *layer = DPGradientLayer(gradient), *source = DPPrivateWindowTheme.on ? DPThemeSource() : nil;
    if (!layer || (!source.colors && !DPGet(layer, &DPColorsKey))) return;
    id current = layer.colors ?: NSNull.null;
    id dia = DPDiaValue(layer, &DPColorsKey, current), ours = source.colors ?: dia;
    if (source.colors) DPOverride(layer, &DPColorsKey, dia, ours);
    else DPSet(layer, &DPColorsKey, nil);
    NSArray *target = ours == NSNull.null ? nil : ours;
    if (layer.colors == target || [layer.colors isEqual:target]) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.colors = target;
    [CATransaction commit];
}

static void DPThemePrivateWindows(void) {
    for (NSWindow *window in NSApp.windows) {
        if (!DPIsKind(window, DPDiaWindow) || !DPIsPrivate(window)) continue;
        DPFindView(window.contentView.superview, ^BOOL(NSView *view) {
            if (DPIsKind(view, DPDiaGradientView) && DPIsKind(view.superview, DPDiaWindowTint)) DPThemePrivate(view);
            return NO;
        });
    }
}

static void DPGradient_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGradient_updateLayer, self);
    if (!DPIsKind(self.superview, DPDiaWindowTint)) return;
    CAGradientLayer *layer = DPGradientLayer(self);
    if (!layer) return;
    if (!DPPrivateWindowTheme.on) {
        if (DPGet(layer, &DPColorsKey)) DPThemePrivate(self);
        return;
    }
    if (self.window && DPIsPrivate(self.window)) DPThemePrivate(self);
    else DPThemePrivateWindows();
}

static void DPApplyPrivateTheme(DPPatch *patch) { DPThemePrivateWindows(); }

static NSString *DPVerifyPrivateTheme(DPPatch *patch) {
    if (!DPIsHooked(objc_getClass(DPDiaGradientView), @selector(updateLayer), (IMP)DPGradient_updateLayer)) return @"window colors don't reach it";
    NSArray *source = DPThemeSource().colors;
    for (NSWindow *window in NSApp.windows) {
        NSView *gradient = DPIsKind(window, DPDiaWindow) && DPIsPrivate(window) ? DPWindowGradient(window) : nil;
        if (source && gradient && [DPGradientLayer(gradient).colors isEqual:source] != patch->on)
            return patch->on ? @"a private window keeps Dia's color" : @"a private window still has the other windows' color";
    }
    return nil;
}

static void DPInstallPrivateTheme(void) {
    DPHook(DPDiaGradientView, @selector(updateLayer), (IMP)DPGradient_updateLayer);
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil usingBlock:^(NSNotification *_) {
        if (DPPrivateWindowTheme.on) DPThemePrivateWindows();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:@"DPProfileColorDidChange" object:nil queue:nil usingBlock:^(NSNotification *_) {
        if (DPPrivateWindowTheme.on) DPThemePrivateWindows();
    }];
}

DP_PATCH(DPPrivateWindowTheme) {
    .key = @"privateWindowTheme",
    .order = 100,
    .title = @"Private Window Theme",
    .detail = @"Give private windows the theme of your other windows instead of Dia’s blue. The Incognito label stays. Experimental.",
    .symbol = @"theatermasks.fill",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaWindow, DPDiaWindowTint, DPDiaGradientView),
    .install = DPInstallPrivateTheme,
    .apply = DPApplyPrivateTheme,
    .verify = DPVerifyPrivateTheme,
};

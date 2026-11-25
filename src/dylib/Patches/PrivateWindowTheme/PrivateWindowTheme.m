#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPPrivateWindowTheme;
static char DPColorsKey, DPPendingThemeKey;

static id DPContextOf(NSWindow *window) {
    id browser = DPBrowserOfWindow(window);
    return [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
}

static NSString *DPProfileOf(NSWindow *window) {
    id context = DPContextOf(window);
    id name = [context respondsToSelector:@selector(userVisibleName)] ? DPMsg(context, @selector(userVisibleName)) : nil;
    return [name isKindOfClass:NSString.class] ? name : nil;
}

static BOOL DPIsPrivate(NSWindow *window) {
    id context = DPContextOf(window);
    id contextID = [context respondsToSelector:@selector(id)] ? DPMsg(context, @selector(id)) : nil;
    return [contextID respondsToSelector:@selector(isIncognito)] && DPMsgBool(contextID, @selector(isIncognito));
}

static BOOL DPIsWindowGradient(NSView *view) { return DPIsKind(view, DPDiaGradientView) && DPIsKind(view.superview, DPDiaWindowTint); }

static NSView *DPWindowGradient(NSWindow *window) { return DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPIsWindowGradient(view); }); }

static CAGradientLayer *DPGradientLayer(NSView *gradient) {
    for (CALayer *layer in gradient.layer.sublayers) if ([layer isKindOfClass:CAGradientLayer.class]) return (CAGradientLayer *)layer;
    return nil;
}

static CAGradientLayer *DPThemeSource(NSWindow *incognito) {
    NSString *profile = DPProfileOf(incognito);
    CAGradientLayer *front = nil;
    for (NSWindow *window in NSApp.orderedWindows) {
        CAGradientLayer *layer = DPIsKind(window, DPDiaWindow) && !DPIsPrivate(window) ? DPGradientLayer(DPWindowGradient(window)) : nil;
        if (!layer) continue;
        if (!profile || [DPProfileOf(window) isEqualToString:profile]) return layer;
        front = front ?: layer;
    }
    return front;
}

static void DPThemePrivate(NSView *gradient) {
    CAGradientLayer *layer = DPGradientLayer(gradient), *source = DPPrivateWindowTheme.on ? DPThemeSource(gradient.window) : nil;
    if (!layer || (!source.colors && !DPGet(layer, &DPColorsKey))) return;
    id current = layer.colors ?: NSNull.null;
    id dia = DPDiaValue(layer, &DPColorsKey, current), ours = source.colors ?: dia;
    if (source.colors) DPOverride(layer, &DPColorsKey, dia, ours);
    else DPSet(layer, &DPColorsKey, nil);
    NSArray *target = ours == NSNull.null ? nil : ours;
    if (layer.colors == target || [layer.colors isEqual:target]) return;
    DPWithoutAnimation(^{ layer.colors = target; });
}

static void DPThemePrivateWindows(void) {
    for (NSWindow *window in NSApp.windows) {
        if (!DPIsKind(window, DPDiaWindow) || !DPIsPrivate(window)) continue;
        DPFindView(window.contentView.superview, ^BOOL(NSView *view) {
            if (DPIsWindowGradient(view)) DPThemePrivate(view);
            return NO;
        });
    }
}

static void DPGradient_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGradient_updateLayer, self);
    NSWindow *window = self.window;
    if (!DPIsKind(self.superview, DPDiaWindowTint) || !window) return;
    CAGradientLayer *layer = DPGradientLayer(self);
    if (!layer || (!DPPrivateWindowTheme.on && !DPGet(layer, &DPColorsKey))) return;
    // updateLayer is AppKit's display pass: theme on the next turn, once per window, instead of changing other windows' layers now.
    if ([DPGet(window, &DPPendingThemeKey) boolValue]) return;
    DPSet(window, &DPPendingThemeKey, @YES);
    dispatch_async(dispatch_get_main_queue(), ^{
        DPSet(window, &DPPendingThemeKey, nil);
        if (DPPrivateWindowTheme.on) return DPThemePrivateWindows();
        for (NSWindow *other in NSApp.windows) {   // hand back anything we changed after the tweak went off
            NSView *gradient = DPIsKind(other, DPDiaWindow) ? DPWindowGradient(other) : nil;
            if (gradient && DPGet(DPGradientLayer(gradient), &DPColorsKey)) DPThemePrivate(gradient);
        }
    });
}

static void DPApplyPrivateTheme(DPPatch *patch) { DPThemePrivateWindows(); }

static NSString *DPVerifyPrivateTheme(DPPatch *patch) {
    if (!DPIsHooked(objc_getClass(DPDiaGradientView), @selector(updateLayer), (IMP)DPGradient_updateLayer)) return @"window colors don't reach it";
    for (NSWindow *window in NSApp.windows) {
        NSView *gradient = DPIsKind(window, DPDiaWindow) && DPIsPrivate(window) ? DPWindowGradient(window) : nil;
        NSArray *source = gradient ? DPThemeSource(window).colors : nil;
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
    .experimental = YES,
    .order = 85,
    .title = @"Private Window Theme",
    .detail = @"Give private windows the theme of your other windows instead of Dia’s blue. The Incognito label stays.",
    .symbol = @"theatermasks.fill",
    .tint = @"systemRedColor",
    .section = @"Profiles",
    .classes = DPClasses(DPDiaWindow, DPDiaWindowTint, DPDiaGradientView),
    .install = DPInstallPrivateTheme,
    .apply = DPApplyPrivateTheme,
    .verify = DPVerifyPrivateTheme,
};

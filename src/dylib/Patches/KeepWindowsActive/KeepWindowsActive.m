#import "StdPatch/StdPatch.h"
#import "SafeMode/SafeMode.h"

@interface NSWindow (DPPrivate)
- (BOOL)_hasActiveAppearance;
- (BOOL)hasKeyAppearance;
- (void)_setShadowParameters;
@end

@interface NSView (DPPrivate)
- (void)_windowChangedKeyState;
@end

extern DPPatch DPKeepWindowsActive;

static BOOL DPSettingsIsKey, DPPendingKeyRefresh;
static NSMapTable<NSWindow *, NSNumber *> *DPAppliedKept;

static BOOL DPRunning(void) {
    return !DPSafeMode && !DPPaused && !DPPausedAtLaunch;
}

static BOOL DPIsSettingsWindow(NSWindow *window) {
    return DPIsKind(window.contentViewController, DPDiaSettingsController) || DPIsKind(window.toolbar.delegate, DPDiaSettingsController);
}

static BOOL DPIsBrowserWindow(NSWindow *window) {
    return (window.styleMask & NSWindowStyleMaskTitled) && ![window isKindOfClass:NSPanel.class] && !DPIsSettingsWindow(window);
}

// AppKit asks on every draw: with the tweak off and no Settings window key, this answers from two flags.
static BOOL DPKeptActive(NSWindow *window) {
    BOOL on = DPKeepWindowsActive.on;
    if (!on && !(DPSettingsIsKey && DPRunning())) return NO;
    return (on || window.visible) && DPIsBrowserWindow(window);
}

static BOOL DPWindow_hasActiveAppearance(NSWindow *self, SEL _cmd) {
    return DPKeptActive(self) || DPCallOriginal(DPWindow_hasActiveAppearance, self);
}

static BOOL DPWindow_hasKeyAppearance(NSWindow *self, SEL _cmd) {
    return DPKeptActive(self) || DPCallOriginal(DPWindow_hasKeyAppearance, self);
}

static void DPRefreshKeyState(NSView *view) {
    if ([view respondsToSelector:@selector(_windowChangedKeyState)]) [view _windowChangedKeyState];
    view.needsDisplay = YES;
    for (NSView *subview in view.subviews) DPRefreshKeyState(subview);
}

static void DPApplyKeepWindowsActive(DPPatch *patch) {
    if (!DPAppliedKept) DPAppliedKept = [NSMapTable weakToStrongObjectsMapTable];
    for (NSWindow *window in NSApp.windows) {
        if (!DPIsBrowserWindow(window)) continue;
        NSNumber *kept = @(DPKeptActive(window));
        if ([kept isEqual:[DPAppliedKept objectForKey:window]]) continue;
        [DPAppliedKept setObject:kept forKey:window];
        if ([window respondsToSelector:@selector(_setShadowParameters)]) [window _setShadowParameters];
        DPRefreshKeyState(window.contentView.superview);
    }
}

static BOOL DPAppKitAnswer(NSWindow *window, SEL sel) {
    return ((BOOL (*)(id, SEL))DPDiaIMP(NSWindow.class, sel))(window, sel);
}

// The pool frees the unshown probe window before other checks enumerate NSApp.windows.
static NSString *DPProbeProblem(BOOL on) {
    @autoreleasepool {
        NSWindow *probe = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered defer:YES];
        probe.releasedWhenClosed = NO;
        BOOL active = probe._hasActiveAppearance, key = probe.hasKeyAppearance;
        if (on) return active && key ? nil : @"a window looks inactive";
        return active == DPAppKitAnswer(probe, @selector(_hasActiveAppearance)) && key == DPAppKitAnswer(probe, @selector(hasKeyAppearance))
            ? nil : @"a background window looks active";
    }
}

static NSString *DPVerifyKeepWindowsActive(DPPatch *patch) {
    NSString *problem = DPProbeProblem(patch->on);
    if (problem || !patch->on) return problem;
    for (NSWindow *window in NSApp.windows)
        if (DPIsBrowserWindow(window) && window.visible && !window._hasActiveAppearance) return @"a window looks inactive";
    return nil;
}

static void DPScheduleKeyRefresh(void) {
    if (DPPendingKeyRefresh) return;
    DPPendingKeyRefresh = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        DPPendingKeyRefresh = NO;
        DPSettingsIsKey = DPRunning() && DPIsSettingsWindow(NSApp.keyWindow);
        DPApplyKeepWindowsActive(&DPKeepWindowsActive);
    });
}

static void DPSettingsKeyChanged(NSNotification *note) {
    if (![note.object isKindOfClass:NSWindow.class] || !DPIsSettingsWindow(note.object)) return;
    DPSettingsIsKey = DPRunning() && [note.name isEqualToString:NSWindowDidBecomeKeyNotification];
    if (!DPKeepWindowsActive.on && DPRunning()) DPScheduleKeyRefresh();
}

static void DPInstallKeepWindowsActive(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DPHookClass(NSWindow.class, @selector(_hasActiveAppearance), (IMP)DPWindow_hasActiveAppearance);
        DPHookClass(NSWindow.class, @selector(hasKeyAppearance), (IMP)DPWindow_hasKeyAppearance);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification])
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                DPSettingsKeyChanged(note);
            }];
        [center addObserverForName:DPPatchesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (!DPKeepWindowsActive.on) DPScheduleKeyRefresh();
        }];
    });
}

DP_PATCH(DPKeepWindowsActive) {
    .key = @"keepWindowsActive",
    .experimental = YES,
    .order = 96,
    .title = @"Keep Windows Active",
    .detail = @"Keep windows looking active, with their shadow, sidebar color and window buttons, when you switch to another app.",
    .symbol = @"rectangle.fill.on.rectangle.fill",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .install = DPInstallKeepWindowsActive,
    .apply = DPApplyKeepWindowsActive,
    .verify = DPVerifyKeepWindowsActive,
};

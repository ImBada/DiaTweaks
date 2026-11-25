#import "Patches/DeleteProfileMenu/DeleteProfileMenu.h"

// What hiding Settings changed, so it can be put back. Dia reuses the window, so none of it may stay.
static char DPHiddenKey;

// Settings, if Dia has made it. With visibleOnly, only if it's on screen or in the Dock; a hidden one is ours, not the user's.
NSWindow *DPSettingsWindow(BOOL visibleOnly) {
    for (NSWindow *window in NSApp.windows)
        if (DPIsKind(window, DPDiaSettingsWindow) && (!visibleOnly || (!DPSettingsHidden(window) && (window.isVisible || window.isMiniaturized))))
            return window;
    return nil;
}

BOOL DPSettingsHidden(NSWindow *settings) { return DPGet(settings, &DPHiddenKey) != nil; }

void DPHideSettings(NSWindow *settings) {
    if (!settings || DPSettingsHidden(settings)) return;
    DPSet(settings, &DPHiddenKey, @{ @"animationBehavior" : @(settings.animationBehavior),
                                     @"alphaValue" : @(settings.alphaValue),
                                     @"ignoresMouseEvents" : @(settings.ignoresMouseEvents) });
    settings.animationBehavior = NSWindowAnimationBehaviorNone;  // No open animation to flash.
    settings.alphaValue = 0;
    settings.ignoresMouseEvents = YES;
}

void DPShowSettings(NSWindow *settings) {
    NSDictionary *saved = DPGet(settings, &DPHiddenKey);
    if (!saved) return;
    DPSet(settings, &DPHiddenKey, nil);
    settings.animationBehavior = [saved[@"animationBehavior"] integerValue];
    settings.alphaValue = [saved[@"alphaValue"] doubleValue];
    settings.ignoresMouseEvents = [saved[@"ignoresMouseEvents"] boolValue];
}

// On the first open in a session Dia makes Settings inside sendAction:, so it has to be hidden before it's ordered in.
static void DPSettings_makeKeyAndOrderFront(NSWindow *self, SEL _cmd, id sender) {
    if (DPOpeningHiddenSettings) DPHideSettings(self);
    DPCallOriginal(DPSettings_makeKeyAndOrderFront, self, sender);
}

static void DPSettings_orderWindow(NSWindow *self, SEL _cmd, NSWindowOrderingMode place, NSInteger other) {
    if (DPOpeningHiddenSettings) DPHideSettings(self);
    DPCallOriginal(DPSettings_orderWindow, self, place, other);
}

void DPInstallSettingsHooks(void) {
    DPHook(DPDiaSettingsWindow, @selector(makeKeyAndOrderFront:), (IMP)DPSettings_makeKeyAndOrderFront);
    DPHook(DPDiaSettingsWindow, @selector(orderWindow:relativeTo:), (IMP)DPSettings_orderWindow);
}

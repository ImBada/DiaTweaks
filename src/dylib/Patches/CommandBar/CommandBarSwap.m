#import "Patches/CommandBar/CommandBarOverlay.h"

static char DPHandingOverKey;

void DPFinishHandOver(NSWindow *window) {
    DPCommandBarOverlay *old = DPGet(window, &DPHandingOverKey);
    if (!old) return;
    DPSet(window, &DPHandingOverKey, nil);
    DPCancelCommandBar(old);
}

DPCommandBarOverlay *DPTakeHandOver(NSWindow *window) {
    DPCommandBarOverlay *old = DPGet(window, &DPHandingOverKey);
    if (old) DPSet(window, &DPHandingOverKey, nil);
    return old;
}

void DPHandOver(DPCommandBarOverlay *overlay) {
    NSWindow *window = overlay.host;
    DPFinishHandOver(window);
    DPStopWatching(overlay);
    DPSet(window, &DPOverlayKey, nil);
    DPSet(window, &DPHandingOverKey, overlay);
    __weak NSWindow *weak = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPFinishHandOver(weak); });
}

static char DPCatchingUpKey, DPWantKey, DPPressedKey, DPNewTabPressKey, DPAddressPressKey;

typedef NS_ENUM(NSInteger, DPBar) { DPNoBar, DPNewTabBar, DPAddressBar };

static DPBar DPBarIn(NSWindow *window) {
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    return !overlay ? DPNoBar : overlay.openedTab ? DPNewTabBar : DPAddressBar;
}

static void DPNotePress(NSWindow *window, NSEvent *event, BOOL newTab) { DPSet(window, newTab ? &DPNewTabPressKey : &DPAddressPressKey, event); }

NSEvent *DPHandToDia(NSWindow *window, NSEvent *event, BOOL newTab) {
    NSObject *token = [NSObject new];
    DPSet(window, &DPCatchingUpKey, token);
    DPSet(window, &DPWantKey, @(newTab ? DPNewTabBar : DPAddressBar));
    DPSet(window, &DPPressedKey, nil);
    DPNotePress(window, event, newTab);
    __weak NSWindow *weak = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (DPGet(weak, &DPCatchingUpKey) == token) DPDiaCaughtUp(weak);
    });
    return event;
}

BOOL DPWaitForDia(NSWindow *window, NSEvent *event, BOOL newTab) {
    if (!DPGet(window, &DPCatchingUpKey)) return NO;
    DPBar bar = newTab ? DPNewTabBar : DPAddressBar;
    DPSet(window, &DPWantKey, @([DPGet(window, &DPWantKey) integerValue] == bar ? DPNoBar : bar));
    DPSet(window, &DPPressedKey, @YES);
    DPNotePress(window, event, newTab);
    return YES;
}

void DPClearCatchUp(NSWindow *window) {
    if (!window) return;
    char *keys[] = {&DPCatchingUpKey, &DPWantKey, &DPPressedKey, &DPNewTabPressKey, &DPAddressPressKey};
    for (size_t i = 0; i < sizeof(keys) / sizeof(*keys); i++) DPSet(window, keys[i], nil);
}

void DPDiaCaughtUp(NSWindow *window) {
    if (!window || !DPGet(window, &DPCatchingUpKey)) return;
    BOOL pressed = DPGet(window, &DPPressedKey) != nil;
    DPBar want = [DPGet(window, &DPWantKey) integerValue], have = DPBarIn(window);
    NSEvent *press = DPGet(window, want == DPNewTabBar ? &DPNewTabPressKey : &DPAddressPressKey);
    DPClearCatchUp(window);
    // Replay only if another press arrived while waiting, so a bar Dia never shows cannot loop.
    if (!DPCommandBar.on || !pressed || want == have) return;
    if (want == DPNoBar) return DPCancelCommandBar(DPGet(window, &DPOverlayKey));
    if (!press || !window.isKeyWindow) return;
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:press.modifierFlags timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:window.windowNumber context:nil characters:press.characters charactersIgnoringModifiers:press.charactersIgnoringModifiers
                                     isARepeat:NO keyCode:press.keyCode] atStart:NO];
}

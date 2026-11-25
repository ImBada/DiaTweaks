#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/AutoPip.h"

extern DPPatch DPNewTabNextToCurrent, DPCommandBarSpare;
static NSMapTable<NSWindow *, NSNumber *> *DPSpareAttempts;
static BOOL DPWanted = YES;
static NSTimer *DPSpareTimer;

void DPWantSpare(void) { DPWanted = YES; }
void DPNotMakingSpare(void) { [DPSpareAttempts removeAllObjects]; }

static BOOL DPMakingSpareIn(NSWindow *window) {
    return window && [[DPSpareAttempts objectForKey:window] doubleValue] > CACurrentMediaTime();
}

static BOOL DPMakingAnySpare(void) {
    CFTimeInterval now = CACurrentMediaTime();
    for (NSNumber *until in DPSpareAttempts.objectEnumerator)
        if (until.doubleValue > now) return YES;
    return NO;
}

void DPDropUnwantedSpares(void) {
    for (NSWindow *window in NSApp.windows)
        if (DPSpareIn(window) && (!DPSparesOn() || DPHasStrip(window))) DPDropSpare(window);
}

// Never in full screen: the spare's tab switch exits it.
static void DPMakeSpare(void) {
    DPDropUnwantedSpares();
    if (!DPSparesOn()) return DPUpdateSpareTimer();
    NSWindow *window = NSApp.keyWindow;
    if (DPTesting || !NSApp.isActive || NSApp.modalWindow || !window || window.attachedSheet) return;
    if (CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType) < 2 || NSEvent.pressedMouseButtons) return;
    if (window.styleMask & NSWindowStyleMaskFullScreen) return;
    static CFTimeInterval lookedAt;
    DPCommandBarOverlay *spare = DPSpareIn(window);
    if (spare && CACurrentMediaTime() - lookedAt > 3) {
        lookedAt = CACurrentMediaTime();
        if (!DPScriptTab(window, DPTabID(spare.openedTab))) DPDropSpare(window);
    }
    BOOL anySpare = NO;
    for (NSWindow *other in NSApp.windows)
        if (DPSpareIn(other)) { anySpare = YES; break; }
    if (!DPWanted && !anySpare && !DPMakingAnySpare()) DPWanted = YES;
    if (!DPWanted) return;
    if (DPSpareIn(window) || DPGet(window, &DPOverlayKey) || DPHidingATab(window) || DPHasStrip(window) || DPVisiblePeek(window)) return;
    id scriptWindow = DPScriptWindow(window);
    if (!scriptWindow) return;
    for (NSWindow *child in window.childWindows) if (child.visible) return;
    id frontTab = DPValueForKey(scriptWindow, @"activeTab");
    NSString *front = DPTabID(frontTab);
    if (!front || [DPSplits(window) containsObject:front] || [DPBlanks(window) containsObject:front] || DPBlankPage(window)) return;
    if (![DPValueForKey(frontTab, @"URL") description].length) return;
    if (!DPIsKind(window.firstResponder, "RenderWidgetHostViewCocoa")) return;
    NSMenuItem *item = DPMenuItemTitled(NSApp.mainMenu, @"New Tab");
    if (!item.action) return;
    if (!DPSpareAttempts) DPSpareAttempts = [NSMapTable weakToStrongObjectsMapTable];
    [DPSpareAttempts setObject:@(CACurrentMediaTime() + 1) forKey:window];
    DPWanted = NO;
    DPExpectNewTab(window);
    __weak NSResponder *typing = window.firstResponder;
    // sendAction: bypasses menu/shortcut PiP hooks, so hold PiP explicitly.
    DPHoldAutoPip();
    if (![NSApp sendAction:item.action to:item.target from:item]) {
        [DPSpareAttempts removeObjectForKey:window];
        DPStopExpecting();
        return DPWantSpare();
    }
    for (int ms = 0; ms <= 300; ms += 300)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            NSView *view = (NSView *)typing, *now = (NSView *)window.firstResponder;
            BOOL typingElsewhere = [now isKindOfClass:NSTextView.class] && !now.isHiddenOrHasHiddenAncestor;
            if (view.window == window && now != view && !typingElsewhere && !DPGet(window, &DPOverlayKey) && !DPVisiblePeek(window)) [window makeFirstResponder:view];
        });
}

void DPParkIfSpare(DPCommandBarOverlay *overlay) {
    NSWindow *window = overlay.host;
    if (!DPMakingSpareIn(window)) return;
    [DPSpareAttempts removeObjectForKey:window];
    overlay.hidden = YES;
    if (DPParkSpare(overlay)) return;
    DPCancelCommandBar(overlay);
    DPWantSpare();
}

BOOL DPSparesOn(void) { return DPHiding() && DPCommandBarSpare.on && !DPNewTabNextToCurrent.on; }

void DPUpdateSpareTimer(void) {
    if (DPSparesOn()) {
        if (!DPSpareTimer) DPSpareTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { DPMakeSpare(); }];
    } else {
        [DPSpareTimer invalidate];
        DPSpareTimer = nil;
    }
}

static void DPRefreshSpares(void) {
    DPDropUnwantedSpares();
    DPUpdateSpareTimer();
}

static void DPInstallSpares(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:DPPatchesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPRefreshSpares(); }];
    DPOnLaunch(^{
        DPUpdateSpareTimer();
        DPCloseLeftBarTabs();
    });
}

static void DPApplySpares(DPPatch *patch) { DPRefreshSpares(); }

static NSString *DPVerifySpares(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows)
        if (DPSpareIn(window) && !DPSparesOn()) return @"a spare is still kept with the option off";
    return nil;
}

DP_PATCH(DPCommandBarSpare) {
    .key = @"commandBarSpare",
    .experimental = YES,
    .order = 89,
    .title = @"Open the Bar Instantly",
    .detail = @"Keep a new tab ready, hidden, so the command bar opens at once instead of waiting for Dia to make one. Needs tabs in the sidebar, and isn’t used with Open New Tabs Next to Current.",
    .symbol = @"bolt.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBarHideTab",
    .section = @"Behavior",
    .classes = DPClasses(DPDiaNewTabPage, DPDiaTabListCollection, DPDiaTabListLayout),
    .install = DPInstallSpares,
    .apply = DPApplySpares,
    .verify = DPVerifySpares,
};

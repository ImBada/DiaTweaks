#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/CommandBarOverlay.h"

extern DPPatch DPCommandBar;

static NSMutableSet<NSString *> *DPHidden, *DPParked;
static NSMapTable<NSString *, NSWindow *> *DPOwner;
static __weak NSWindow *DPExpectWindow;
static CFTimeInterval DPExpectUntil;
static NSSet<NSString *> *DPKnown;

BOOL DPHiding(void) { return DPCommandBar.on && DPCommandBarHideTab.on && !DPCommandBarHideTab.unavailable; }
static BOOL DPExpecting(void) { return CACurrentMediaTime() < DPExpectUntil; }

static BOOL DPOwned(NSString *tab) {
    if ([DPOwner objectForKey:tab]) return YES;
    [DPHidden removeObject:tab];
    [DPParked removeObject:tab];
    return NO;
}

BOOL DPHidingATab(NSWindow *window) {
    if (!DPHiding()) return NO;
    if (DPHidden.count)
        for (NSString *tab in DPHidden.allObjects)
            if (DPOwned(tab) && ![DPParked containsObject:tab] && (!window || [DPOwner objectForKey:tab] == window)) return YES;
    return DPExpecting() && (!window || DPExpectWindow == window);
}

BOOL DPParksTab(NSString *tab) { return DPHidesTab(tab) && [DPParked containsObject:tab]; }

BOOL DPParkingAny(void) {
    if (!DPHiding() || !DPParked.count) return NO;
    for (NSString *tab in DPParked.allObjects) if (DPOwned(tab)) return YES;
    return NO;
}

void DPHideBlank(NSString *tabID, BOOL hidden, NSWindow *window) {
    if (!tabID || !window || (hidden ? !DPHiding() : ![DPHidden containsObject:tabID])) return;
    if (hidden) {
        [DPHidden addObject:tabID];
        [DPOwner setObject:window forKey:tabID];
    } else {
        [DPHidden removeObject:tabID];
        [DPOwner removeObjectForKey:tabID];
    }
    DPParkTab(tabID, hidden);
}

void DPParkTab(NSString *tabID, BOOL parked) {
    if (!tabID) return;
    if (parked) [DPParked addObject:tabID];
    else [DPParked removeObject:tabID];
    DPRelayoutLists();
}

BOOL DPHiddenTab(NSString *tab) { return DPHiding() && tab && [DPHidden containsObject:tab] && DPOwned(tab); }

BOOL DPHidesTab(NSString *tab) {
    if (!DPHiding() || !tab) return NO;
    if ([DPHidden containsObject:tab]) return DPOwned(tab);
    return DPExpecting() && DPKnown && ![DPKnown containsObject:tab];
}

void DPExpectNewTab(NSWindow *window) {
    if (!DPHiding() || (DPExpecting() && DPExpectWindow == window)) return;
    // Snapshot every window's tabs so another window's existing tabs aren't mistaken for the new one.
    NSMutableSet *known = [NSMutableSet setWithArray:DPListedTabs(nil)];
    id windows = DPValueForKey(NSApp.delegate, @"appleScriptWindows");
    if ([windows isKindOfClass:NSArray.class])
        for (id scripted in windows) {
            id tabs = DPValueForKey(scripted, @"appleScriptTabs");
            if ([tabs isKindOfClass:NSArray.class])
                for (id tab in tabs) [known addObject:DPTabID(tab) ?: @""];
        }
    for (NSView *tab in DPFindViews(DPDiaTabView)) [known addObject:DPStripTabID(tab) ?: @""];
    DPKnown = known;
    DPExpectWindow = window;
    CFTimeInterval until = DPExpectUntil = CACurrentMediaTime() + 1;
    DPFreezeLists(window);
    DPHoldStrips(window);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC + 10 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (DPExpectUntil == until) DPStopExpecting();
    });
}

void DPStopExpecting(void) {
    if (!DPExpectUntil) return;
    DPExpectUntil = 0;
    DPKnown = nil;
    DPRelayoutLists();
}

void DPHideTabRow(NSString *tabID, NSWindow *window) {
    if (!tabID || !window || !DPHiding() || !DPExpecting() || DPExpectWindow != window || !DPKnown || [DPKnown containsObject:tabID]) return;
    [DPHidden addObject:tabID];
    [DPOwner setObject:window forKey:tabID];
    DPExpectUntil = 0;
    DPKnown = nil;
    DPFreezeLists(window);
    DPHoldStrips(window);
    DPRelayoutLists();
}

void DPShowTabRow(NSString *tabID, BOOL closing) {
    if (!tabID || ![DPHidden containsObject:tabID]) return;
    // Keep a closing tab hidden for 1 s so it doesn't flash in the list on its way out.
    if (closing) return (void)dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPShowTabRow(tabID, NO); });
    [DPHidden removeObject:tabID];
    [DPParked removeObject:tabID];
    [DPOwner removeObjectForKey:tabID];
    DPRelayoutLists();
}

void DPForgetWindow(NSWindow *window) {
    BOOL had = DPExpectWindow == window && DPExpectUntil;
    if (had) DPExpectUntil = 0, DPKnown = nil;
    if (DPOwner.count)
        for (NSString *tab in DPOwner.keyEnumerator.allObjects) {
            if ([DPOwner objectForKey:tab] != window) continue;
            [DPHidden removeObject:tab];
            [DPParked removeObject:tab];
            [DPOwner removeObjectForKey:tab];
            had = YES;
        }
    if (had) DPRelayoutLists();
}

void DPCleanHideTab(void) {
    DPExpectUntil = 0;
    DPKnown = nil;
    [DPHidden removeAllObjects];
    [DPParked removeAllObjects];
    [DPOwner removeAllObjects];
    DPReleaseStrips();
    DPShowHiddenBars();
    DPRelayoutLists();
    DPRefreshStandIns();
}

static void DPApplyHideTab(DPPatch *patch) {
    for (NSView *background in DPFindViews(DPDiaTabBackground)) DPNoteLook(background);
    if (!DPHiding()) {
        DPDropUnwantedSpares();
        DPUpdateSpareTimer();
        DPCleanHideTab();
        return;
    }
    DPRelayoutLists();
    DPRefreshStandIns();
}

static NSString *DPVerifyHideTab(DPPatch *patch) { return DPVerifyHiddenRows(); }

// Full-screen transitions rebuild the tab list, so close any bar over a hidden tab first.
static void DPCloseBar(NSWindow *window) {
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (overlay.openedTab && DPHidesTab(DPTabID(overlay.openedTab))) DPCancelCommandBar(overlay);
}

static void DPInstallHideTab(void) {
    if (!DPSelectionLayoutKnown()) {
        DPCommandBarHideTab.unavailable = YES;
        DPCommandBarHideTab.on = NO;
        NSLog(@"DiaPatches: Hide New Tab Until Opened doesn't know how this Dia lays out a tab's selection, so it stays off");
        return;
    }
    DPHidden = [NSMutableSet set];
    DPParked = [NSMutableSet set];
    DPOwner = [NSMapTable strongToWeakObjectsMapTable];
    DPInstallFrozenLists();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSMenuWillSendActionNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!DPHiding()) return;
        NSMenuItem *item = note.userInfo[@"MenuItem"];
        if ([item.title isEqualToString:@"New Tab"] && NSApp.keyWindow) DPExpectNewTab(NSApp.keyWindow);
    }];
    [center addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPForgetWindow(note.object); }];
    for (NSNotificationName name in @[ NSWindowWillEnterFullScreenNotification, NSWindowWillExitFullScreenNotification ])
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) { if (DPHiding()) DPCloseBar(note.object); }];
    DPInstallHiddenStripTab();
    DPInstallStandIn();
    DPInstallPress();
}

DP_PATCH(DPCommandBarHideTab) {
    .key = @"commandBarHideTab",
    .order = 94,
    .title = @"Hide New Tab Until Opened",
    .detail = @"Keep the new tab out of the sidebar and the tab bar while the command bar is open. The New Tab button shows as selected instead, and clicking it again closes the bar. The tab shows once you choose a result. Experimental.",
    .symbol = @"eye.slash.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabListCollection, DPDiaTabListLayout, DPDiaTabStripTabs, DPDiaTabView, DPDiaTabContentView, DPDiaTabBackground, DPDiaNewTabButton, DPDiaTabSurfaceButton),
    .install = DPInstallHideTab,
    .apply = DPApplyHideTab,
    .verify = DPVerifyHideTab,
};

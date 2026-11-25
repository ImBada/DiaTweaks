#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/CommandBarOverlay.h"

extern DPPatch DPCommandBar;

@interface DPExpectation : NSObject
@property CFTimeInterval until;
@property(strong) NSSet<NSString *> *known;
@end

@implementation DPExpectation
@end

static NSMutableSet<NSString *> *DPHidden, *DPParked;
static NSMutableDictionary<NSString *, NSNumber *> *DPPresence;
static NSMapTable<NSString *, NSWindow *> *DPOwner;
static NSMapTable<NSWindow *, DPExpectation *> *DPExpectations;

// Spares install first, so a launch-time hide can land before DPInstallHideTab runs.
static void DPEnsureHideSets(void) {
    if (DPHidden) return;
    DPHidden = [NSMutableSet set];
    DPParked = [NSMutableSet set];
    DPPresence = [NSMutableDictionary dictionary];
    DPOwner = [NSMapTable strongToWeakObjectsMapTable];
}

static void DPDrop(NSString *tab) {
    [DPHidden removeObject:tab];
    [DPParked removeObject:tab];
    [DPPresence removeObjectForKey:tab];
    [DPOwner removeObjectForKey:tab];
}

BOOL DPHiding(void) { return DPCommandBar.on && DPCommandBarHideTab.on && !DPCommandBarHideTab.unavailable; }

static DPExpectation *DPExpectationIn(NSWindow *window) {
    DPExpectation *expectation = window ? [DPExpectations objectForKey:window] : nil;
    return expectation.until > CACurrentMediaTime() ? expectation : nil;
}

static BOOL DPExpectsUnknown(NSString *tab) {
    if (!DPExpectations.count) return NO;
    CFTimeInterval now = CACurrentMediaTime();
    for (DPExpectation *expectation in DPExpectations.objectEnumerator)
        if (expectation.until > now && (!tab || ![expectation.known containsObject:tab])) return YES;
    return NO;
}

// A tab closed by any route but the bar leaves its entry behind, and a hidden tab nobody can show again would hold the list for good.
// One never yet seen listed gets two seconds to appear first.
static void DPReapHidden(void) {
    static CFTimeInterval last;
    CFTimeInterval now = CACurrentMediaTime();
    if ((!DPHidden.count && !DPParked.count) || now - last < 0.2) return;
    last = now;
    BOOL reaped = NO;
    for (NSString *tab in [DPHidden setByAddingObjectsFromSet:DPParked]) {
        NSWindow *window = [DPOwner objectForKey:tab];
        NSInteger listing = window ? DPTabListing(DPScriptWindow(window), tab) : 0;
        NSNumber *state = DPPresence[tab];
        BOOL seen = state && state.doubleValue < 0;
        if (listing == 1) DPPresence[tab] = @-1;
        else if (listing == 0 && (!window || seen || (state && now - state.doubleValue > 2))) reaped = YES, DPDrop(tab);
        else if (listing == 0 && !state) DPPresence[tab] = @(now);
    }
    if (reaped) dispatch_async(dispatch_get_main_queue(), ^{ DPRelayoutLists(); });
}

BOOL DPHidingATab(NSWindow *window) {
    if (!DPHiding()) return NO;
    DPReapHidden();
    for (NSString *tab in DPHidden) {
        NSWindow *owner = [DPOwner objectForKey:tab];
        if (owner && ![DPParked containsObject:tab] && (!window || owner == window)) return YES;
    }
    return window ? DPExpectationIn(window) != nil : DPExpectsUnknown(nil);
}

BOOL DPParksTab(NSString *tab) { return DPHidesTab(tab) && [DPParked containsObject:tab]; }

BOOL DPParkingAny(void) {
    if (!DPHiding() || !DPParked.count) return NO;
    DPReapHidden();
    for (NSString *tab in DPParked) if ([DPOwner objectForKey:tab]) return YES;
    return NO;
}

void DPHideBlank(NSString *tabID, BOOL hidden, NSWindow *window) {
    DPEnsureHideSets();
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

// The sidebar can still be mounting, or filling in its rows, when a tab is hidden; each look finds a row the last one couldn't name.
static void DPRelayoutWhileMounting(NSString *tab) {
    DPRelayoutLists();
    for (int ms = 50; ms < 1000; ms *= 3)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if ([DPHidden containsObject:tab] || [DPParked containsObject:tab]) DPRelayoutLists();
        });
}

void DPParkTab(NSString *tabID, BOOL parked) {
    DPEnsureHideSets();
    if (!tabID) return;
    if (parked) [DPParked addObject:tabID];
    else [DPParked removeObject:tabID];
    if (parked) DPRelayoutWhileMounting(tabID);
    else DPRelayoutLists();
}

BOOL DPHiddenTab(NSString *tab) { return DPHiding() && tab && [DPHidden containsObject:tab] && [DPOwner objectForKey:tab]; }

BOOL DPHidesTab(NSString *tab) {
    if (!DPHiding() || !tab) return NO;
    if ([DPHidden containsObject:tab]) return [DPOwner objectForKey:tab] != nil;
    return DPExpectsUnknown(tab);
}

static void DPStopExpectingIn(NSWindow *window) {
    if (!window || ![DPExpectations objectForKey:window]) return;
    [DPExpectations removeObjectForKey:window];
    DPRelayoutLists();
}

void DPExpectNewTab(NSWindow *window) {
    if (!window || !DPHiding() || DPExpectationIn(window)) return;
    NSMutableSet *known = [NSMutableSet setWithArray:DPListedTabs(nil)];
    id windows = DPValueForKey(NSApp.delegate, @"appleScriptWindows");
    if ([windows isKindOfClass:NSArray.class])
        for (id scripted in windows)
            for (id tab in DPScriptTabs(scripted)) if (DPTabID(tab)) [known addObject:DPTabID(tab)];
    for (NSView *tab in DPFindViews(DPDiaTabView)) if (DPStripTabID(tab)) [known addObject:DPStripTabID(tab)];
    DPExpectation *expectation = [DPExpectation new];
    expectation.known = known;
    expectation.until = CACurrentMediaTime() + 1;
    if (!DPExpectations) DPExpectations = [NSMapTable weakToStrongObjectsMapTable];
    [DPExpectations setObject:expectation forKey:window];
    DPFreezeLists(window);
    DPHoldStrips(window);
    __weak NSWindow *weak = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC + 10 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSWindow *expecting = weak;
        if (expecting && [DPExpectations objectForKey:expecting] == expectation) DPStopExpectingIn(expecting);
    });
}

void DPStopExpecting(void) {
    if (!DPExpectations.count) return;
    [DPExpectations removeAllObjects];
    DPRelayoutLists();
}

// A tab the list already held isn't the one being waited for, but a bar open over it still hides it once the wait is over.
static void DPHideTabRowAfter(DPExpectation *expectation, NSString *tabID, NSWindow *window) {
    __weak NSWindow *weak = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((expectation.until - CACurrentMediaTime() + 0.02) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPCommandBarOverlay *overlay = DPGet(weak, &DPOverlayKey);
        if ([DPTabID(overlay.openedTab) isEqual:tabID]) DPHideTabRow(tabID, weak);
    });
}

// A tab no ⌘T announced (launch, or one Dia took over a second to open) has no layout from before it to hold, so its row just closes up.
void DPHideTabRow(NSString *tabID, NSWindow *window) {
    DPEnsureHideSets();
    if (!tabID.length || !window || !DPHiding()) return;
    DPExpectation *expectation = DPExpectationIn(window);
    BOOL expected = expectation && ![expectation.known containsObject:tabID];
    if (expectation && !expected) return DPHideTabRowAfter(expectation, tabID, window);
    [DPHidden addObject:tabID];
    [DPOwner setObject:window forKey:tabID];
    if (expected) {
        [DPExpectations removeObjectForKey:window];
        DPFreezeLists(window);
        DPHoldStrips(window);
    }
    DPRelayoutWhileMounting(tabID);
}

void DPShowTabRow(NSString *tabID, BOOL closing) {
    if (!tabID || ![DPHidden containsObject:tabID]) return;
    // Keep a closing tab hidden for 1 s so it doesn't flash in the list on its way out.
    if (closing) return (void)dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPShowTabRow(tabID, NO); });
    DPDrop(tabID);
    DPRelayoutLists();
}

void DPForgetWindow(NSWindow *window) {
    BOOL had = window && [DPExpectations objectForKey:window];
    if (had) [DPExpectations removeObjectForKey:window];
    if (DPOwner.count)
        for (NSString *tab in DPOwner.keyEnumerator.allObjects) {
            if ([DPOwner objectForKey:tab] != window) continue;
            DPDrop(tab);
            had = YES;
        }
    if (had) DPRelayoutLists();
}

void DPCleanHideTab(void) {
    [DPExpectations removeAllObjects];
    [DPHidden removeAllObjects];
    [DPParked removeAllObjects];
    [DPPresence removeAllObjects];
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
    DPEnsureHideSets();
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
    .experimental = YES,
    .order = 88,
    .title = @"Hide New Tab Until Opened",
    .detail = @"Keep the new tab out of the sidebar and the tab bar while the command bar is open. The New Tab button shows as selected instead, and clicking it again closes the bar. The tab shows once you choose a result.",
    .symbol = @"eye.slash.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Behavior",
    .classes = DPClasses(DPDiaTabListCollection, DPDiaTabListLayout, DPDiaTabStripTabs, DPDiaTabView, DPDiaTabContentView, DPDiaTabBackground, DPDiaNewTabButton, DPDiaTabSurfaceButton),
    .install = DPInstallHideTab,
    .apply = DPApplyHideTab,
    .verify = DPVerifyHideTab,
};

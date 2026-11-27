#import "StdPatch/StdPatch.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

extern DPPatch DPNewTabNextToCurrent;
static char DPStateKey, DPRelayKey;

@interface DPNextTabs : NSObject
@property(strong) NSSet<NSString *> *knownIDs;
@property(copy) NSString *lastFrontID;
@property BOOL moving;
@property(strong) NSMutableDictionary<NSString *, NSString *> *originOf;
@property(strong) NSMutableDictionary<NSString *, NSString *> *barOrigin;
@property(copy) NSString *fromTabID;
@property long long fromSession;
@end

@implementation DPNextTabs
@end

static NSArray<NSString *> *DPTabIDsIn(NSArray *tabs) {
    if (!tabs.count) return @[];
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:tabs.count];
    for (id tab in tabs) {
        id tabID = DPTabID(tab);
        if (tabID) [ids addObject:tabID];
    }
    return ids;
}

static NSArray<NSString *> *DPTabIDs(NSWindow *window) {
    return DPTabIDsIn(DPScriptTabs(DPScriptWindow(window)));
}

static BOOL DPIsBlankTab(id tab) {
    NSString *url = [DPValueForKey(tab, @"URL") description];
    return !url.length || !([url hasPrefix:@"http:"] || [url hasPrefix:@"https:"] || [url hasPrefix:@"file:"]);
}

static BOOL DPIsBlankIn(NSArray *tabs, NSString *tabID) {
    for (id tab in tabs) if ([DPTabID(tab) isEqual:tabID]) return DPIsBlankTab(tab);
    return YES;
}

static BOOL DPIsBlank(NSWindow *window, NSString *tabID) {
    return DPIsBlankTab(DPScriptTab(window, tabID));
}

static DPNextTabs *DPStateWith(NSWindow *window, NSString *active, NSArray<NSString *> *ids) {
    DPNextTabs *state = DPGet(window, &DPStateKey);
    if (state || !active) return state;
    state = [DPNextTabs new];
    state.originOf = [NSMutableDictionary dictionary];
    state.barOrigin = [NSMutableDictionary dictionary];
    state.knownIDs = [NSSet setWithArray:ids];
    state.lastFrontID = active;
    DPSet(window, &DPStateKey, state);
    return state;
}

static DPNextTabs *DPStateFor(NSWindow *window) {
    DPNextTabs *state = DPGet(window, &DPStateKey);
    if (state) return state;
    id scripted = DPScriptWindow(window);
    NSString *active = DPActiveTabIDIn(scripted);
    return active ? DPStateWith(window, active, DPTabIDsIn(DPScriptTabs(scripted))) : nil;
}

static void DPAskGroups(id delegate, id browser, void (^done)(NSArray *groups)) {
    void (*ask)(id, SEL, id, void (^)(NSArray *)) = (void *)objc_msgSend;
    if (![delegate respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) return done(@[]);
    ask(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *groups) {
        dispatch_async(dispatch_get_main_queue(), ^{ done([groups isKindOfClass:NSArray.class] ? groups : @[]); });
    });
}

static NSInteger DPTabsLeftInFolder(NSArray *groups, long long session) {
    for (id info in groups) {
        NSArray *raw = [info respondsToSelector:@selector(tabSessionIds)] ? DPMsg(info, @selector(tabSessionIds)) : nil;
        if (![raw isKindOfClass:NSArray.class]) continue;
        for (NSUInteger i = 0; i < raw.count; i++)
            if (DPLongID(raw[i]) == session) return (NSInteger)(raw.count - 1 - i);
    }
    return 0;
}

static NSSet<NSNumber *> *DPSessions(id browser) {
    NSMutableSet *sessions = [NSMutableSet set];
    for (id contents in DPTrackedContents(browser)) {
        long long sid = DPSessionOf(contents);
        if (sid > 0) [sessions addObject:@(sid)];
    }
    return sessions;
}

// The one page open at an address, or 0 when none or several are.
static long long DPSessionAt(id browser, NSString *url, long long except) {
    long long found = 0;
    for (id contents in DPTrackedContents(browser)) {
        long long sid = DPSessionOf(contents);
        if (sid <= 0 || sid == except || ![contents respondsToSelector:@selector(url)] || ![DPText(DPMsg(contents, @selector(url))) isEqual:url]) continue;
        if (found) return 0;
        found = sid;
    }
    return found;
}

static NSString *DPAddressOf(id tab) {
    NSString *url = [DPValueForKey(tab, @"URL") description];
    return url.length ? url : nil;
}

static void DPNote(NSWindow *window);

static void DPDoneMoving(NSWindow *window, DPNextTabs *state) {
    state.moving = NO;
    state.knownIDs = [NSSet setWithArray:DPTabIDs(window)];
    state.lastFrontID = DPActiveTabID(window);
    // A bar kept while this move ran went unseen.
    dispatch_async(dispatch_get_main_queue(), ^{ if (DPNewTabNextToCurrent.on) DPNote(window); });
}

static void DPMoveNextTo(NSWindow *window, NSString *newID, NSString *fromID, long long fromSession, NSNumber *sid, DPNextTabs *state) {
    id browser = DPBrowserOfWindow(window), delegate = DPGroupingDelegate(browser);
    if (!DPNewTabNextToCurrent.on || !DPScriptTab(window, newID) || !delegate) return DPDoneMoving(window, state);
    NSMutableArray<NSString *> *others = [DPTabIDs(window) mutableCopy];
    NSUInteger newIndex = [others indexOfObject:newID];
    [others removeObject:newID];
    NSUInteger fromIndex = [others indexOfObject:fromID];
    if (newIndex == NSNotFound || fromIndex == NSNotFound || newIndex == fromIndex + 1) return DPDoneMoving(window, state);

    void (^finish)(void) = ^{ DPDoneMoving(window, state); };
    // Move to index 0 to find where unpinned tabs begin.
    DPMoveTab(delegate, browser, sid, 0, ^{
        if (!DPNewTabNextToCurrent.on) return finish();
        NSMutableArray<NSString *> *after = [DPTabIDs(window) mutableCopy];
        NSUInteger start = [after indexOfObject:newID];
        [after removeObject:newID];
        NSUInteger currentFrom = [after indexOfObject:fromID];
        if (start == NSNotFound || currentFrom == NSNotFound || currentFrom < start) return finish();
        DPAskGroups(delegate, browser, ^(NSArray *groups) {
            if (!DPNewTabNextToCurrent.on) return finish();
            NSInteger to = (NSInteger)(currentFrom - start) + 1 + (fromSession > 0 ? DPTabsLeftInFolder(groups, fromSession) : 0);
            DPMoveTab(delegate, browser, sid, to, finish, finish);
        });
    }, finish);
}

static void DPPlace(NSWindow *window, NSString *newID, NSString *fromID, long long fromSession, NSSet<NSNumber *> *before, DPNextTabs *state, int tries) {
    id browser = DPBrowserOfWindow(window), delegate = DPGroupingDelegate(browser);
    if (!DPNewTabNextToCurrent.on || !DPScriptTab(window, newID) || !delegate) return DPDoneMoving(window, state);
    NSMutableSet<NSNumber *> *gained = [DPSessions(browser) mutableCopy];
    [gained minusSet:before];
    if (gained.count != 1) {
        if (tries <= 0) return DPDoneMoving(window, state);
        return (void)dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            DPPlace(window, newID, fromID, fromSession, before, state, tries - 1);
        });
    }
    DPMoveNextTo(window, newID, fromID, fromSession, gained.anyObject, state);
}

// A tab the command bar opened has no page to move until a result loads in it, so it's placed once the bar keeps it.
static void DPPlaceKept(NSWindow *window, NSString *tabID, NSString *originID, DPNextTabs *state, int tries) {
    id browser = DPBrowserOfWindow(window), tab = DPScriptTab(window, tabID), origin = DPScriptTab(window, originID);
    if (!DPNewTabNextToCurrent.on || DPGet(window, &DPStateKey) != state || !DPGroupingDelegate(browser) || !tab || !origin) return;
    NSString *url = DPAddressOf(tab), *originURL = DPAddressOf(origin);
    // Another tab at the same address would be moved in its place.
    for (id other in DPScriptTabs(DPScriptWindow(window)))
        if (![DPTabID(other) isEqual:tabID] && url && [DPAddressOf(other) isEqual:url]) return;
    long long fromSession = [state.fromTabID isEqual:originID] ? state.fromSession : (originURL ? DPSessionAt(browser, originURL, 0) : 0);
    long long sid = url && !state.moving ? DPSessionAt(browser, url, fromSession) : 0;
    if (sid <= 0) {
        if (tries <= 0) return;
        return (void)dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            DPPlaceKept(window, tabID, originID, state, tries - 1);
        });
    }
    state.originOf[tabID] = originID;
    state.moving = YES;
    DPMoveNextTo(window, tabID, originID, fromSession, @(sid), state);
}

static BOOL DPOpenNextToCurrent(NSWindow *window) {
    if (!DPNewTabNextToCurrent.on) return NO;
    id scripted = DPScriptWindow(window), browser = DPBrowserOfWindow(window);
    NSString *from = DPActiveTabID(window);
    Class tabClass = NSClassFromString(@"DiaAppleScriptTab");
    SEL make = NSSelectorFromString(@"newScriptingObjectOfClass:forValueForKey:withContentsValue:properties:");
    if (!from || !browser || !DPGroupingDelegate(browser)) return NO;
    if (DPIsBlank(window, from)) return NO;
    DPNextTabs *state = DPStateFor(window);
    if (state.moving) return NO;
    long long fromSession = DPActiveSession(browser);
    // The bar opens over Dia's own new tab, not a scripted one; it's placed once the bar keeps it.
    if (DPCommandBar.on && ![DPSplits(window) containsObject:from]) {
        state.fromTabID = from;
        state.fromSession = fromSession;
        // Dia mounts its new tab page inside this same event; a script window read above would still call this tab the front one.
        DPClearScriptWindowCache();
        return NO;
    }
    if (!tabClass || ![scripted respondsToSelector:make]) return NO;
    NSSet<NSNumber *> *before = DPSessions(browser);
    NSArray<NSString *> *tabsBefore = DPTabIDs(window);
    id tab = ((id (*)(id, SEL, Class, NSString *, id, id))objc_msgSend)(scripted, make, tabClass, @"appleScriptTabs", nil, @{});
    NSMutableArray<NSString *> *added = [DPTabIDs(window) mutableCopy];
    [added removeObjectsInArray:tabsBefore];
    NSString *created = tab && added.count == 1 ? added.firstObject : nil;
    if (!created) return tab != nil;
    state.originOf[created] = from;
    state.moving = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPlace(window, created, from, fromSession, before, state, 20); });
    return YES;
}

@interface DPNewTabRelay : NSObject
@property(weak) id target;
@property SEL action;
@end

@implementation DPNewTabRelay
- (void)open:(NSMenuItem *)sender {
    NSWindow *window = NSApp.keyWindow;
    if (window && DPOpenNextToCurrent(window)) return;
    if (self.action) [NSApp sendAction:self.action to:self.target from:sender];
}
@end

static NSMenuItem *DPNewTabItem(void) {
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        for (NSMenuItem *item in top.submenu.itemArray)
            if ([item.title isEqualToString:@"New Tab"] && item.keyEquivalent.length) return item;
    return nil;
}

static void DPRelayMenuItem(BOOL on) {
    NSMenuItem *item = DPNewTabItem();
    DPNewTabRelay *relay = DPGet(item, &DPRelayKey);
    if (!item || on == (relay != nil)) return;
    if (on) {
        relay = [DPNewTabRelay new];
        relay.target = item.target;
        relay.action = item.action;
        DPSet(item, &DPRelayKey, relay);
        item.target = relay;
        item.action = @selector(open:);
    } else {
        item.target = relay.target;
        item.action = relay.action;
        DPSet(item, &DPRelayKey, nil);
    }
}

static void DPNewTabButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand);
    if (!mods && self.window && DPOpenNextToCurrent(self.window)) return;
    DPCallOriginal(DPNewTabButton_mouseDown, self, event);
}

static void DPReturnTo(NSWindow *window, NSString *originID, NSString *expectedFront) {
    if (!DPNewTabNextToCurrent.on) return;
    id origin = DPScriptTab(window, originID);
    if (origin && [DPActiveTabID(window) isEqual:expectedFront]) DPFocusTab(origin);
}

static void DPNoteBar(NSWindow *window, DPNextTabs *state, NSString *active, NSSet<NSString *> *now) {
    DPCommandBarOverlay *bar = DPCommandBar.on ? DPGet(window, &DPOverlayKey) : nil;
    NSString *open = DPTabID(bar.openedTab), *over = DPTabID(bar.returnTab);
    if (open && over) state.barOrigin[open] = over;
    for (NSString *tab in state.barOrigin.allKeys)
        if (![now containsObject:tab] || ![now containsObject:state.barOrigin[tab]]) [state.barOrigin removeObjectForKey:tab];
    // Dia may keep showing the tab the bar came from while it keeps the bar's tab, so a bar that is gone is enough to go on.
    for (NSString *tab in state.barOrigin.allKeys) {
        NSString *origin = state.barOrigin[tab];
        if ([open isEqual:tab]) continue;
        [state.barOrigin removeObjectForKey:tab];
        if ([active isEqual:tab]) state.originOf[tab] = origin;
        dispatch_async(dispatch_get_main_queue(), ^{ DPPlaceKept(window, tab, origin, state, 30); });
    }
}

static void DPNote(NSWindow *window) {
    DPNextTabs *state = DPGet(window, &DPStateKey);
    if (state.moving) return;
    id scripted = DPScriptWindow(window);
    NSString *active = DPActiveTabIDIn(scripted);
    NSArray *tabs = active ? DPScriptTabs(scripted) : nil;
    NSArray<NSString *> *ids = tabs ? DPTabIDsIn(tabs) : nil;
    if (!ids.count) return;
    if (!state) return (void)DPStateWith(window, active, ids);
    NSSet<NSString *> *now = [NSSet setWithArray:ids];
    BOOL switched = ![active isEqual:state.lastFrontID];

    if (state.lastFrontID && switched && ![state.knownIDs containsObject:active] && [now containsObject:state.lastFrontID] && DPIsBlankIn(tabs, active))
        state.originOf[active] = state.lastFrontID;
    DPNoteBar(window, state, active, now);

    for (NSString *tab in state.originOf.allKeys) {
        NSString *origin = state.originOf[tab];
        if (![now containsObject:origin]) {
            [state.originOf removeObjectForKey:tab];
        } else if (![now containsObject:tab]) {
            [state.originOf removeObjectForKey:tab];
            if ([state.lastFrontID isEqual:tab] && ![active isEqual:origin])
                dispatch_async(dispatch_get_main_queue(), ^{ DPReturnTo(window, origin, active); });
        } else if (![active isEqual:tab] && ![active isEqual:origin]) {
            [state.originOf removeObjectForKey:tab];
            // Dia may activate the next tab before removing the closing one.
            if ([state.lastFrontID isEqual:tab])
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    if (!DPScriptTab(window, tab)) DPReturnTo(window, origin, active);
                });
        }
    }
    state.knownIDs = now;
    state.lastFrontID = active;
}

static void DPNoteWindowOf(NSView *view) {
    if (DPNewTabNextToCurrent.on && view.window) DPNote(view.window);
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    DPNoteWindowOf(self);
}

static void DPNewTabPage_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPNewTabPage_viewDidMoveToWindow, self);
    DPNoteWindowOf(self);
}

static void DPInstallNewTabNextToCurrent(void) {
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
    DPHook(DPDiaNewTabPage, @selector(viewDidMoveToWindow), (IMP)DPNewTabPage_viewDidMoveToWindow);
    DPHook(DPDiaNewTabButton, @selector(mouseDown:), (IMP)DPNewTabButton_mouseDown);
    DPOnLaunch(^{ if (DPNewTabNextToCurrent.on) DPRelayMenuItem(YES); });
}

static void DPApplyNewTabNextToCurrent(DPPatch *patch) {
    DPRelayMenuItem(patch->on);
    for (NSWindow *window in NSApp.windows) {
        DPSet(window, &DPStateKey, nil);
        if (patch->on) DPNote(window);
    }
}

static NSString *DPVerifyNewTabNextToCurrent(DPPatch *patch) {
    NSMenuItem *item = DPNewTabItem();
    if (!item) return patch->on ? @"Dia has no New Tab menu item" : nil;
    if (patch->on && !DPGet(item, &DPRelayKey)) return @"New Tab doesn't open next to the current tab";
    if (!patch->on && DPGet(item, &DPRelayKey)) return @"New Tab is still changed";
    return nil;
}

DP_PATCH(DPNewTabNextToCurrent) {
    .key = @"newTabNextToCurrent",
    .order = 86,
    .title = @"Open New Tabs Next to Current",
    .detail = @"A new tab opens right after the tab you’re on, not at the end, as in Arc and Chrome. Close it and you’re back on the tab you came from. On a pinned tab, it opens at the top of the unpinned tabs.",
    .symbol = @"rectangle.badge.plus",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaContentPane, DPDiaNewTabPage, DPDiaNewTabButton),
    .install = DPInstallNewTabNextToCurrent,
    .apply = DPApplyNewTabNextToCurrent,
    .verify = DPVerifyNewTabNextToCurrent,
};


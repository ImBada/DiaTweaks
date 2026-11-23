#import "Patches/Peek/Peek.h"
#import "Patches/CommandBar/Tabs.h"

enum { DPPeekPageVisible = 2 };

static char DPPeekLastActiveKey;
static BOOL DPPeekSyncing;
static NSTimer *DPPeekSyncTimer;

static void DPPeekAddTabIDs(NSMutableSet<NSString *> *ids, id owner) {
    NSArray *tabs = DPValueForKey(owner, @"appleScriptTabs");
    if (![tabs isKindOfClass:NSArray.class]) return;
    for (id tab in tabs) {
        NSString *tabID = DPTabID(tab);
        if (tabID) [ids addObject:tabID];
    }
}

static NSSet<NSString *> *DPPeekOpenTabIDs(id scriptWindow, NSString *active) {
    if (!scriptWindow || !active) return nil;
    NSMutableSet<NSString *> *openIDs = [NSMutableSet set];
    DPPeekAddTabIDs(openIDs, scriptWindow);
    NSArray *profiles = DPValueForKey(scriptWindow, @"appleScriptProfiles");
    if ([profiles isKindOfClass:NSArray.class])
        for (id profile in profiles) DPPeekAddTabIDs(openIDs, profile);
    return [openIDs containsObject:active] ? openIDs : nil;
}

static void DPPeekSyncAllWindows(void) {
    NSArray<DPPeekCard *> *all = DPPeekAllCards(nil);
    if (!all.count) {
        DPPeekHandoffSync();
        return DPPeekUpdateSyncTimer();
    }
    NSMutableArray<NSWindow *> *windows = [NSMutableArray array];
    for (DPPeekCard *peek in all) {
        if (peek.closing) continue;
        NSWindow *owner = peek.window ?: peek.originWindow;
        if (!owner) [peek close:DPPeekClose];
        else if (![windows containsObject:owner]) [windows addObject:owner];
    }
    for (NSWindow *window in windows) DPPeekSyncTabs(window);
    DPPeekHandoffSync();
    DPPeekUpdateSyncTimer();
}

void DPPeekUpdateSyncTimer(void) {
    BOOL live = DPPeekHandoffActive();
    if (!live) for (DPPeekCard *peek in DPPeekAllCards(nil))
        if (!peek.closing) { live = YES; break; }
    if (!live) {
        [DPPeekSyncTimer invalidate];
        DPPeekSyncTimer = nil;
        return;
    }
    if (DPPeekSyncTimer) return;
    DPPeekSyncTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { DPPeekSyncAllWindows(); }];
    [NSRunLoop.mainRunLoop addTimer:DPPeekSyncTimer forMode:NSRunLoopCommonModes];
}

void DPPeekCloseForSource(id source) {
    if (!source) return;
    for (DPPeekCard *peek in DPPeekAllCards(nil))
        if (!peek.closing && peek.source == source) {
            DPPeekChatDetachQuiet(peek);
            [peek close:DPPeekClose];
        }
    DPPeekUpdateSyncTimer();
}

void DPPeekSyncTabs(NSWindow *window) {
    if (!window || DPPeekSyncing) return;
    NSArray<DPPeekCard *> *cards = DPPeekAllCards(window);
    if (!cards.count && !DPPeekHandoffActive()) return DPPeekUpdateSyncTimer();
    DPPeekSyncing = YES;
    @try {
        id scriptWindow = DPScriptWindow(window);
        NSString *active = scriptWindow ? DPActiveTabIDIn(scriptWindow) : DPActiveTabID(window);
        if (active) DPPeekHandoffSelectionChanged(window, active);
        // A cover outliving its card only needs the selection check; its own dismissal stops the timer.
        if (!cards.count) return;
        NSString *lastActive = DPGet(window, &DPPeekLastActiveKey);
        if (active && ![active isEqual:lastActive]) {
            DPSet(window, &DPPeekLastActiveKey, active);
            if (lastActive) DPPeekCoolIn(window);
        }
        NSSet<NSString *> *openIDs = (scriptWindow && active) ? DPPeekOpenTabIDs(scriptWindow, active) : nil;
        DPPeekCard *toShow = nil;
        for (DPPeekCard *peek in cards) {
            if (peek.closing) continue;
            if (peek.hadSource && !peek.source) {
                [peek close:DPPeekClose];
                continue;
            }
            if (peek.originTabID && openIDs && ![openIDs containsObject:peek.originTabID]) {
                [peek close:DPPeekClose];
                continue;
            }
            BOOL visible;
            if (peek.originTabID) {
                visible = active && [active isEqual:peek.originTabID];
            } else {
                BOOL known = NO;
                BOOL selected = DPPeekTabBadgeSelected(peek, &known);
                visible = known ? selected : !peek.hidden;
            }
            if (visible && !toShow) {
                toShow = peek;
            } else {
                [peek setOriginVisible:NO];
                DPPeekRefreshTabBadge(peek);
            }
        }
        if (toShow && !toShow.closing) {
            [toShow setOriginVisible:YES];
            DPPeekRefreshTabBadge(toShow);
        }
    } @finally {
        DPPeekSyncing = NO;
    }
    DPPeekUpdateSyncTimer();
}

static void DPPeekHookIfPresent(const char *className, SEL sel, IMP imp) {
    Class cls = className ? objc_getClass(className) : Nil;
    if (cls && class_getInstanceMethod(cls, sel)) DPHookClass(cls, sel, imp);
}

static void DPPeekSyncWindowOf(NSView *view) {
    if (DPPeek.on && view.window && DPPeekHasCards()) DPPeekSyncTabs(view.window);
}

static void DPPeekPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPeekPane_viewDidMoveToWindow, self);
    DPPeekSyncWindowOf(self);
}

static void DPPeekNewTab_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPeekNewTab_viewDidMoveToWindow, self);
    DPPeekSyncWindowOf(self);
}

static void DPPeekRunMain(void (^work)(void)) {
    if (NSThread.isMainThread) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

static BOOL DPPeekIsVisibleSource(id page) {
    for (DPPeekCard *peek in DPPeekAllCards(nil))
        if (!peek.closing && !peek.isHiddenOrHasHiddenAncestor && peek.source == page) return YES;
    return NO;
}

static void DPPeekPage_setVisibility(id self, SEL _cmd, NSInteger visibility) {
    DPCallOriginal(DPPeekPage_setVisibility, self, visibility);
    if (!DPPeek.on || !DPPeekHasCards()) return;
    __weak id weak = self;
    BOOL appeared = visibility == DPPeekPageVisible;
    DPPeekRunMain(^{
        if (!DPPeek.on || !DPPeekHasCards() || !weak) return;
        BOOL stale = appeared ? !DPPeekCardForPage(weak) : DPPeekIsVisibleSource(weak);
        if (stale) DPPeekSyncAllWindows();
    });
}

static void DPPeekCloseForPageOrSource(id page) {
    if (!page) return;
    DPPeekCloseForSource(page);
    DPPeekCard *own = DPPeekCardForPage(page);
    if (own && !own.closing) [own close:DPPeekClose];
}

static void DPPeekPage_close(id self, SEL _cmd) {
    DPCallOriginal(DPPeekPage_close, self);
    if (!DPPeek.on) return;
    __weak id weak = self;
    DPPeekRunMain(^{ if (DPPeek.on && DPPeekHasCards() && weak) DPPeekCloseForPageOrSource(weak); });
}

static void DPPeekPage_closeTiming(id self, SEL _cmd, NSInteger timing) {
    DPCallOriginal(DPPeekPage_closeTiming, self, timing);
    if (!DPPeek.on) return;
    __weak id weak = self;
    DPPeekRunMain(^{ if (DPPeek.on && DPPeekHasCards() && weak) DPPeekCloseForPageOrSource(weak); });
}

static void DPPeekWebContent_finalizeDiscard(id self, SEL _cmd, id page, BOOL discarded) {
    DPCallOriginal(DPPeekWebContent_finalizeDiscard, self, page, discarded);
    if (!DPPeek.on || !discarded || !page) return;
    __weak id weak = page;
    DPPeekRunMain(^{ if (DPPeek.on && DPPeekHasCards() && weak) DPPeekCloseForSource(weak); });
}

void DPPeekInstallSelection(void) {
    DPPeekHookIfPresent(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPPeekPane_viewDidMoveToWindow);
    DPPeekHookIfPresent(DPDiaNewTabPage, @selector(viewDidMoveToWindow), (IMP)DPPeekNewTab_viewDidMoveToWindow);
    DPPeekHookIfPresent(DPDiaWebContents, @selector(setVisibility:), (IMP)DPPeekPage_setVisibility);
    DPPeekHookIfPresent(DPDiaWebContents, @selector(closeWithForegroundCommitTiming:), (IMP)DPPeekPage_closeTiming);
    DPPeekHookIfPresent(DPDiaWebContents, @selector(close), (IMP)DPPeekPage_close);
    DPOnLaunch(^{
        DPPeekHookIfPresent(DPDiaWebContent, @selector(webContents:finalizeDiscardRequest:), (IMP)DPPeekWebContent_finalizeDiscard);
    });
}

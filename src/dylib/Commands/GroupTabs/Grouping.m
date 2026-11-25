#import "GroupTabs.h"
#import <objc/message.h>

static void DPCollectPinned(NSMutableSet<NSNumber *> *sessions, NSMutableSet<NSString *> *pinnedURLs, NSMutableSet<NSString *> *openURLs) {
    for (id window in DPAppleScriptWindows()) {
        for (id tab in DPAppleScriptTabs(window)) {
            NSString *url = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
            BOOL pinned = [tab respondsToSelector:@selector(isPinned)] && DPMsgBool(tab, @selector(isPinned));
            if (url.length) [pinned ? pinnedURLs : openURLs addObject:url];
            if (!pinned) continue;
            long long sid = [tab respondsToSelector:@selector(tabId)] ? DPLongID(DPMsg(tab, @selector(tabId))) : 0;
            if (sid > 0) [sessions addObject:@(sid)];
        }
    }
}

static BOOL DPPinned(long long sid, NSString *url, NSSet<NSNumber *> *sessions, NSSet<NSString *> *urls, NSSet<NSString *> *openURLs) {
    if ([sessions containsObject:@(sid)]) return YES;
    return url.length && [urls containsObject:url] && ![openURLs containsObject:url];
}

static id DPGroupProperties(NSString *title) {
    id props = [objc_getClass(DPDiaTabGroupProperties) new];
    if (title.length && [props respondsToSelector:@selector(setTitle:)]) [props setTitle:title];
    return props;
}

static void (^DPUndoGrouping)(void);
static id DPUndoMonitor;

BOOL DPCanUndoGrouping(void) { return DPUndoGrouping != nil; }

void DPForgetGroupingUndo(void) {
    DPUndoGrouping = nil;
    if (DPUndoMonitor) [NSEvent removeMonitor:DPUndoMonitor];
    DPUndoMonitor = nil;
}

static NSEvent *DPUndoKey(NSEvent *event) {
    void (^undo)(void) = DPUndoGrouping;
    DPForgetGroupingUndo();
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if (!undo || DPShortcutRecording() || mods != NSEventModifierFlagCommand || !DPEventIsKey(event, @"z")) return event;
    undo();
    return nil;
}

static void DPArmUndo(void (^undo)(void)) {
    DPForgetGroupingUndo();
    if (!DPGroupTabs.on) return;
    DPUndoGrouping = undo;
    DPUndoMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPUndoKey(event); }];
}

void DPOfferUndo(id delegate, id browser, NSArray *ids, NSDictionary *places) {
    __weak id weakDelegate = delegate, weakBrowser = browser;
    DPArmUndo(^{
        id delegate = weakDelegate, browser = weakBrowser;
        if (delegate && browser) DPRemoveFromGroups(delegate, browser, ids, ^{ if (places) DPRestorePlaces(delegate, browser, places); });
    });
}

void DPOfferRegroup(id delegate, id browser, NSArray<NSDictionary *> *ops) {
    __weak id weakDelegate = delegate, weakBrowser = browser;
    DPArmUndo(^{
        id delegate = weakDelegate, browser = weakBrowser;
        if (delegate && browser) DPRunOps(delegate, browser, ops, 0, ^{});
    });
}

void DPRunOps(id delegate, id browser, NSArray<NSDictionary *> *ops, NSUInteger index, void (^done)(void)) {
    if (index >= ops.count) return done();
    NSDictionary *op = ops[index];
    BOOL create = [op[@"op"] isEqual:@"create"];
    NSArray *ids = op[@"ids"];
    id target = create ? DPGroupProperties(op[@"title"]) : op[@"group"];
    if (!target || ![ids isKindOfClass:NSArray.class] || !ids.count) return DPRunOps(delegate, browser, ops, index + 1, done);
    void (^next)(id) = ^(id _) {
        dispatch_async(dispatch_get_main_queue(), ^{ DPRunOps(delegate, browser, ops, index + 1, done); });
    };
    void (*send)(id, SEL, id, id, id, void (^)(id)) = (void *)objc_msgSend;
    if (create) send(delegate, @selector(browser:createTabGroupWithSessionIds:properties:completion:), browser, ids, target, next);
    else send(delegate, @selector(browser:addTabsToGroupWithId:sessionIds:completion:), browser, target, ids, next);
}

static void DPGroupBrowser(id browser, NSSet<NSNumber *> *only) {
    if (!browser) return;
    id delegate = DPGroupingDelegate(browser);
    if (![delegate respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) return;
    NSMutableSet<NSNumber *> *pinnedSessions = [NSMutableSet set];
    NSMutableSet<NSString *> *pinnedURLs = [NSMutableSet set], *openURLs = [NSMutableSet set];
    DPCollectPinned(pinnedSessions, pinnedURLs, openURLs);
    NSMutableArray<NSDictionary *> *tabs = [NSMutableArray array];
    for (id contents in DPTrackedContents(browser)) {
        long long sid = DPSessionOf(contents);
        NSString *url = DPText(DPMsg(contents, @selector(url)));
        NSString *domain = DPDomainKey(url);
        if (domain && DPGroupTabsMergeSubdomains.on) domain = DPRegistrableDomain(domain);
        if (sid <= 0 || !domain || (only && ![only containsObject:@(sid)]) || DPPinned(sid, url, pinnedSessions, pinnedURLs, openURLs)) continue;
        [tabs addObject:@{@"session": @(sid), @"domain": domain, @"url": url}];
    }
    DPLoadTabGroups(delegate, browser, ^(NSArray *groups) {
        NSArray *ops = DPOps(tabs, groups);
        NSArray *ids = [ops valueForKeyPath:@"@unionOfArrays.ids"];
        if (!ids.count) return;
        NSSet *idSet = [NSSet setWithArray:ids];
        NSMutableDictionary *urls = [NSMutableDictionary new];
        for (NSDictionary *tab in tabs) if ([idSet containsObject:tab[@"session"]]) urls[tab[@"session"]] = tab[@"url"];
        NSDictionary *places = DPTabPlaces(urls);
        DPRunOps(delegate, browser, ops, 0, ^{ DPOfferUndo(delegate, browser, ids, places); });
    });
}

void DPGroupTabsOnce(void) { DPGroupBrowser(DPCommandBrowser(), nil); }

void DPGroupSelectedTabsOnce(void) {
    id browser = DPCommandBrowser();
    NSSet<NSNumber *> *only = browser ? DPSelectedSessions(browser) : nil;
    if (only.count >= 2) DPGroupBrowser(browser, only);
}

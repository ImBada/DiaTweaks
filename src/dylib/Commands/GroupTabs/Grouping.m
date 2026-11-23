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
    Class cls = objc_getClass(DPDiaTabGroupProperties);
    id props = cls ? [cls new] : nil;
    if (title.length && [props respondsToSelector:@selector(setTitle:)]) [props setTitle:title];
    return props;
}

static void (^DPUndoGrouping)(void);

BOOL DPCanUndoGrouping(void) { return DPUndoGrouping != nil; }
void DPForgetGroupingUndo(void) { DPUndoGrouping = nil; }

static void DPArmUndo(void (^undo)(void)) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            void (^undo)(void) = DPUndoGrouping;
            if (!undo) return event;
            DPUndoGrouping = nil;
            if (!DPGroupTabs.on) return event;
            NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
            if (DPShortcutRecording() || mods != NSEventModifierFlagCommand || !DPEventIsKey(event, @"z")) return event;
            undo();
            return nil;
        }];
    });
    DPUndoGrouping = undo;
}

void DPOfferUndo(id delegate, id browser, NSArray *ids, NSDictionary *places) {
    __weak id weakDelegate = delegate, weakBrowser = browser;
    DPArmUndo(^{
        id delegate = weakDelegate, browser = weakBrowser;
        if (!delegate || !browser) return;
        void (*ungroup)(id, SEL, id, NSArray *, void (^)(id)) = (void *)objc_msgSend;
        ungroup(delegate, @selector(browser:removeTabsFromGroupWithSessionIds:completion:), browser, ids, ^(id _) {
            if (places) dispatch_async(dispatch_get_main_queue(), ^{ DPRestorePlaces(delegate, browser, places); });
        });
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
    void (^next)(id) = ^(id result) {
        dispatch_async(dispatch_get_main_queue(), ^{ DPRunOps(delegate, browser, ops, index + 1, done); });
    };
    void (*create)(id, SEL, id, NSArray *, id, void (^)(id)) = (void *)objc_msgSend;
    void (*add)(id, SEL, id, NSString *, NSArray *, void (^)(id)) = (void *)objc_msgSend;
    if ([op[@"op"] isEqual:@"create"]) {
        id props = DPGroupProperties(op[@"title"]);
        if (!props) return DPRunOps(delegate, browser, ops, index + 1, done);
        create(delegate, @selector(browser:createTabGroupWithSessionIds:properties:completion:), browser, op[@"ids"], props, next);
    } else {
        add(delegate, @selector(browser:addTabsToGroupWithId:sessionIds:completion:), browser, op[@"group"], op[@"ids"], next);
    }
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
    void (*ask)(id, SEL, id, void (^)(NSArray *)) = (void *)objc_msgSend;
    ask(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *groups) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![groups isKindOfClass:NSArray.class]) return;
            NSArray *ops = DPOps(tabs, groups);
            NSArray *ids = [ops valueForKeyPath:@"@unionOfArrays.ids"];
            if (!ids.count) return;
            NSSet *idSet = [NSSet setWithArray:ids];
            NSMutableDictionary *urls = [NSMutableDictionary new];
            for (NSDictionary *tab in tabs) if ([idSet containsObject:tab[@"session"]]) urls[tab[@"session"]] = tab[@"url"];
            NSDictionary *places = DPTabPlaces(urls);
            DPRunOps(delegate, browser, ops, 0, ^{ DPOfferUndo(delegate, browser, ids, places); });
        });
    });
}

void DPGroupTabsOnce(void) { DPGroupBrowser(DPCommandBrowser(), nil); }

void DPGroupSelectedTabsOnce(void) {
    id browser = DPCommandBrowser();
    NSSet<NSNumber *> *only = browser ? DPSelectedSessions(browser) : nil;
    if (only.count >= 2) DPGroupBrowser(browser, only);
}

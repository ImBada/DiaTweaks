// Nothing reports where unpinned tabs start and Dia can only move groups, so a tab moves alone in a scratch group and where it lands is the offset.
#import "GroupTabs.h"
#import <objc/message.h>

static NSString *DPURLOf(id tab) { return DPText(DPMsg(tab, @selector(URL))); }

static NSArray *DPWindowTabsMatching(BOOL (^match)(id tab)) {
    NSArray *best = nil;
    NSUInteger most = 0;
    for (id window in DPAppleScriptWindows()) {
        NSArray *tabs = DPAppleScriptTabs(window);
        NSUInteger count = 0;
        for (id tab in tabs) if (match(tab)) count++;
        if (count > most) { best = tabs; most = count; }
    }
    return best;
}

static NSMutableArray *DPTabIDsOf(NSArray *tabs) {
    if (!tabs) return nil;
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:tabs.count];
    for (id tab in tabs) [ids addObject:DPValueForKey(tab, @"tabId") ?: NSNull.null];
    return ids;
}

NSDictionary *DPTabPlaces(NSDictionary<NSNumber *, NSString *> *urls) {
    NSSet *wanted = [NSSet setWithArray:urls.allValues];
    NSArray *tabs = DPWindowTabsMatching(^BOOL(id tab) { return [wanted containsObject:DPURLOf(tab)]; });
    NSMutableDictionary<NSString *, NSNumber *> *sessions = [NSMutableDictionary new];
    for (NSNumber *sid in urls)
        for (id tab in tabs) {
            id tabID = DPValueForKey(tab, @"tabId");
            if (tabID && !sessions[tabID] && [DPURLOf(tab) isEqualToString:urls[sid]]) {
                sessions[tabID] = sid;
                break;
            }
        }
    return tabs && sessions.count == urls.count ? @{@"order": DPTabIDsOf(tabs), @"sessions": sessions} : nil;
}

void DPMoveTab(id delegate, id browser, NSNumber *sid, NSInteger index, void (^done)(void), void (^failed)(void)) {
    id props = [objc_getClass(DPDiaTabGroupProperties) new];
    if (!delegate || !browser || !sid || !props) return failed ? failed() : (void)0;
    void (*create)(id, SEL, id, NSArray *, id, void (^)(id)) = (void *)objc_msgSend;
    void (*move)(id, SEL, id, id, NSInteger, void (^)(id)) = (void *)objc_msgSend;
    void (*ungroup)(id, SEL, id, NSArray *, void (^)(id)) = (void *)objc_msgSend;
    create(delegate, @selector(browser:createTabGroupWithSessionIds:properties:completion:), browser, @[sid], props, ^(id result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            id group = [result respondsToSelector:@selector(groupId)] ? DPMsg(result, @selector(groupId)) : nil;
            if (!group) return failed ? failed() : (void)0;
            move(delegate, @selector(browser:moveTabGroupWithId:toNewIndex:completion:), browser, group, index, ^(id _) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ungroup(delegate, @selector(browser:removeTabsFromGroupWithSessionIds:completion:), browser, @[sid], ^(id _) {
                        if (done) dispatch_async(dispatch_get_main_queue(), done);
                    });
                });
            });
        });
    });
}

static void DPRunMoves(id delegate, id browser, NSArray<NSArray *> *moves, NSUInteger index) {
    if (index >= moves.count) return;
    DPMoveTab(delegate, browser, moves[index][0], [moves[index][1] integerValue], ^{ DPRunMoves(delegate, browser, moves, index + 1); }, nil);
}

static NSArray<NSArray *> *DPPlanMoves(NSArray<NSString *> *target, NSMutableArray<NSString *> *now, NSDictionary<NSString *, NSNumber *> *sessions, NSUInteger start) {
    NSMutableArray *moves = [NSMutableArray new];
    if (![[NSSet setWithArray:now] isEqualToSet:[NSSet setWithArray:target]]) return moves;
    for (NSUInteger i = 0; i < target.count; i++) {
        while (![now[i] isEqualToString:target[i]]) {
            BOOL due = sessions[target[i]] != nil;
            NSString *tab = due ? target[i] : now[i];
            NSUInteger to = due ? i : now.count - 1;
            if (!sessions[tab] || to < start) return moves;
            [now removeObject:tab];
            [now insertObject:tab atIndex:to];
            [moves addObject:@[sessions[tab], @(to - start)]];
        }
    }
    return moves;
}

void DPRestorePlaces(id delegate, id browser, NSDictionary *places) {
    NSDictionary<NSString *, NSNumber *> *sessions = places[@"sessions"];
    NSString *first = sessions.allKeys.firstObject;
    if (!first) return;
    DPMoveTab(delegate, browser, sessions[first], 0, ^{
        NSArray *tabs = DPWindowTabsMatching(^BOOL(id tab) { return [DPValueForKey(tab, @"tabId") isEqual:first]; });
        NSMutableArray *now = DPTabIDsOf(tabs);
        NSUInteger start = now ? [now indexOfObject:first] : NSNotFound;
        if (start != NSNotFound) DPRunMoves(delegate, browser, DPPlanMoves(places[@"order"], now, sessions, start), 0);
    }, nil);
}

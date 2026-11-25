#import "TidyTabs.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

static const NSUInteger DPTidyMaxTabs = 50;
static NSUInteger DPTidyRun;

void DPTidyAskModel(NSArray *tabs, void (^done)(NSArray *groups, NSString *error));

static void DPTidyFail(NSString *message) {
    NSLog(@"DiaPatches: Tidy Tabs: %@", message);
}

static NSArray<NSDictionary *> *DPTidyOps(NSArray *groups, NSArray<NSDictionary *> *tabs) {
    NSMutableArray *ops = [NSMutableArray array];
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    for (NSArray *group in groups) {
        if (![group isKindOfClass:NSArray.class]) continue;
        NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
        for (NSNumber *number in group) {
            NSInteger index = number.integerValue - 1;
            if (index < 0 || index >= (NSInteger)tabs.count) continue;
            NSNumber *sid = tabs[index][@"session"];
            if ([used containsObject:sid]) continue;
            [used addObject:sid];
            [ids addObject:sid];
        }
        if (ids.count >= 2) [ops addObject:@{@"op": @"create", @"ids": ids}];
    }
    return ops;
}

static void DPTidyGroup(id browser, id delegate, NSArray<NSDictionary *> *tabs, NSUInteger run) {
    NSMutableArray *prompt = [NSMutableArray array];
    for (NSDictionary *tab in tabs) [prompt addObject:@{@"title": tab[@"title"], @"address": tab[@"address"]}];
    DPTidyAskModel(prompt, ^(NSArray *groups, NSString *error) {
        if (run != DPTidyRun) return;
        if (error) { DPTidySetBusy(NO); return DPTidyFail(error); }
        NSArray *ops = DPTidyOps(groups, tabs);
        NSLog(@"DiaPatches: Tidy Tabs made %lu groups from %lu tabs", (unsigned long)ops.count, (unsigned long)tabs.count);
        if (!ops.count) { DPTidySetBusy(NO); return DPTidyFail(@"No tabs clearly belonged together."); }
        NSArray *ids = [ops valueForKeyPath:@"@unionOfArrays.ids"];
        NSSet *idSet = [NSSet setWithArray:ids];
        NSMutableDictionary *urls = [NSMutableDictionary dictionary];
        for (NSDictionary *tab in tabs) if ([idSet containsObject:tab[@"session"]]) urls[tab[@"session"]] = tab[@"url"];
        NSDictionary *places = DPTabPlaces(urls);
        DPRunOps(delegate, browser, ops, 0, ^{
            if (run == DPTidyRun) DPTidySetBusy(NO);
            DPOfferUndo(delegate, browser, ids, places);
        });
    });
}

void DPTidyTabsNow(NSWindow *window) {
    if (DPTidyIsBusy()) return;
    window = window ?: NSApp.keyWindow;
    id browser = DPBrowserOfWindow(window);
    id delegate = browser ? DPGroupingDelegate(browser) : nil;
    if (![delegate respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) return DPTidyFail(@"Dia’s tabs aren’t ready yet.");
    NSDictionary<NSString *, NSString *> *loose = DPTidyLooseTabs(window);
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (id contents in DPTrackedContents(browser)) {
        long long sid = DPSessionOf(contents);
        NSString *url = DPText(DPMsg(contents, @selector(url)));
        NSString *host = DPDomainKey(url);
        if (sid <= 0 || !host || !loose[url]) continue;
        [candidates addObject:@{@"session": @(sid), @"url": url, @"address": DPTidyAddress(url, host), @"title": loose[url]}];
    }
    if (candidates.count < 2) return DPTidyFail(@"There are no loose tabs to tidy.");
    DPTidySetBusy(YES);
    NSUInteger run = ++DPTidyRun;
    // A completion Dia or the model drops would otherwise leave the brooms busy until relaunch.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (run != DPTidyRun || !DPTidyIsBusy()) return;
        DPTidyRun++;
        DPTidySetBusy(NO);
        DPTidyFail(@"Gave up waiting for an answer.");
    });
    void (*ask)(id, SEL, id, void (^)(NSArray *)) = (void *)objc_msgSend;
    ask(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *groups) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (run != DPTidyRun) return;
            NSMutableSet<NSNumber *> *grouped = [NSMutableSet set];
            for (id info in [groups isKindOfClass:NSArray.class] ? groups : @[]) {
                NSArray *rawIDs = [info respondsToSelector:@selector(tabSessionIds)] ? DPMsg(info, @selector(tabSessionIds)) : nil;
                if ([rawIDs isKindOfClass:NSArray.class]) for (id raw in rawIDs) [grouped addObject:@(DPLongID(raw))];
            }
            NSMutableArray<NSDictionary *> *tabs = [NSMutableArray array];
            for (NSDictionary *tab in candidates)
                if (![grouped containsObject:tab[@"session"]] && tabs.count < DPTidyMaxTabs) [tabs addObject:tab];
            if (tabs.count < 2) { DPTidySetBusy(NO); return DPTidyFail(@"There are no loose tabs to tidy."); }
            DPTidyGroup(browser, delegate, tabs, run);
        });
    });
}

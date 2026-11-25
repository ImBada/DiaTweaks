#import "GroupTabs.h"

NSArray<NSString *> *DPSelectionIDKeys(id selection);
NSString *DPIDKey(id value);
void DPEachValue(id collection, void (^visit)(id value));

static NSArray<NSString *> *DPWalkKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"contentViewController", @"tabSidebarViewController", @"tabStripContainerViewController", @"delegate", @"viewModel",
                  @"presenter", @"sidebarStorage", @"storage", @"sidebarControllerStorage", @"controllerStorage", @"tabListController",
                  @"tabStripController" ];
    });
    return keys;
}

static BOOL DPIsTabList(id obj) {
    const char *name = object_getClassName(obj);
    return name && (strstr(name, "TabListController") || strstr(name, "TabStripController"));
}

static BOOL DPMayHoldTabs(id obj) {
    const char *name = object_getClassName(obj);
    return name && (strstr(name, "Tab") || strstr(name, "Window") || strstr(name, "Sidebar") || strstr(name, "Strip"));
}

static void DPWalk(id obj, NSMutableArray *found, NSMutableSet *seen, NSInteger depth) {
    if (!obj || depth > 8 || [seen containsObject:obj]) return;
    if ([obj isKindOfClass:NSArray.class]) {
        for (id each in obj) DPWalk(each, found, seen, depth + 1);
        return;
    }
    if ([obj isKindOfClass:NSDictionary.class]) {
        for (id each in [obj allValues]) DPWalk(each, found, seen, depth + 1);
        return;
    }
    [seen addObject:obj];
    if (DPIsTabList(obj)) [found addObject:obj];
    if ([obj isKindOfClass:NSWindow.class]) DPWalk([(NSWindow *)obj contentViewController], found, seen, depth + 1);
    if ([obj isKindOfClass:NSViewController.class] && [obj respondsToSelector:@selector(childViewControllers)])
        DPWalk([(NSViewController *)obj childViewControllers], found, seen, depth + 1);
    if (!DPMayHoldTabs(obj)) return;
    for (NSString *key in DPWalkKeys()) DPWalk(DPSwiftValue(obj, key), found, seen, depth + 1);
}

static void DPAddUnique(NSMutableDictionary *lists, NSString *key, id value) {
    NSMutableArray *list = lists[key] ?: (lists[key] = [NSMutableArray array]);
    if (![list containsObject:value]) [list addObject:value];
}

static void DPReadObject(id obj, NSString *key, NSSet<NSNumber *> *tracked,
                         NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *sessions,
                         NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *urls) {
    if (!obj || !key.length) return;
    long long sid = DPLongID(DPSwiftValue(obj, @"tabSessionID"));
    if (sid <= 0) sid = DPLongID(DPSwiftValue(obj, @"sessionId"));
    if (sid > 0 && [tracked containsObject:@(sid)]) DPAddUnique(sessions, key, @(sid));
    NSString *url = DPText(DPSwiftValue(obj, @"webContentURL")) ?: DPText(DPSwiftValue(obj, @"url"));
    if (url.length) DPAddUnique(urls, key, url);
}

static void DPReadContent(id content, NSString *key, NSSet<NSNumber *> *tracked,
                          NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *sessions,
                          NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *urls) {
    id model = DPSwiftValue(content, @"viewModel");
    id objs[] = { content, DPSwiftValue(content, @"delegate"), DPSwiftValue(content, @"webContent"), model, DPSwiftValue(model, @"delegate") };
    for (NSUInteger i = 0; i < 5; i++) DPReadObject(objs[i], key, tracked, sessions, urls);
}

static void DPReadTab(id tab, NSSet<NSNumber *> *tracked, NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *sessions,
                      NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *urls) {
    NSString *key = DPIDKey(DPSwiftValue(tab, @"tabID") ?: DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"tabID"));
    if (!key.length) return;
    DPReadContent(tab, key, tracked, sessions, urls);
    DPEachValue(DPSwiftValue(tab, @"contentControllers") ?: DPSwiftValue(tab, @"contentViews"), ^(id content) {
        DPReadContent(content, key, tracked, sessions, urls);
    });
}

static id DPSelection(NSWindow *window, NSArray *controllers) {
    id state = DPSwiftValue(DPSwiftValue(DPSwiftValue(window, @"viewModel"), @"stateSubject"), @"currentValue");
    id selection = DPSwiftValue(state, @"tabSelectionState");
    if (selection) return selection;
    for (id controller in controllers) {
        selection = DPSwiftValue(controller, @"selectionState") ?: DPSwiftValue(controller, @"tabSelectionState") ?: DPSwiftValue(controller, @"sidebarSelectionState");
        if (selection) return selection;
    }
    return nil;
}

static NSArray<NSView *> *DPViewsInWindow(NSWindow *window, const char *first, const char *second) {
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    for (NSView *view in [DPFindViews(first) arrayByAddingObjectsFromArray:DPFindViews(second)])
        if (view.window == window) [views addObject:view];
    return views;
}

static NSArray *DPTabControllers(NSWindow *window) {
    NSMutableArray *controllers = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    DPWalk(window, controllers, seen, 0);
    for (NSView *view in DPViewsInWindow(window, DPDiaTabList, DPDiaTabStrip))
        DPWalk(DPSwiftValue(DPSwiftValue(view, @"viewModel"), @"presenter"), controllers, seen, 0);
    return controllers;
}

BOOL DPCanReadSelection(id browser) {
    static __weak NSWindow *readable;
    NSWindow *window = DPBrowserWindow(browser);
    if (!window || window == readable) return YES;
    if (!DPSelection(window, nil) && !DPSelection(window, DPTabControllers(window))) return NO;
    readable = window;
    return YES;
}

NSSet<NSNumber *> *DPSelectedSessions(id browser) {
    NSWindow *window = DPBrowserWindow(browser);
    if (!window) return nil;
    NSArray *controllers = DPTabControllers(window);
    NSArray<NSString *> *keys = DPSelectionIDKeys(DPSelection(window, controllers));
    if (keys.count < 2) return nil;

    NSMutableSet<NSNumber *> *tracked = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *byURL = [NSMutableDictionary dictionary];
    for (id contents in DPTrackedContents(browser)) {
        long long sid = DPSessionOf(contents);
        NSString *url = DPText(DPMsg(contents, @selector(url)));
        if (sid <= 0) continue;
        [tracked addObject:@(sid)];
        if (!url.length) continue;
        NSMutableArray *list = byURL[url] ?: (byURL[url] = [NSMutableArray array]);
        [list addObject:@(sid)];
    }
    NSMutableDictionary *sessions = [NSMutableDictionary dictionary], *urls = [NSMutableDictionary dictionary];
    for (id controller in controllers) DPEachValue(DPSwiftValue(controller, @"tabControllers"), ^(id tab) { DPReadTab(tab, tracked, sessions, urls); });
    for (NSView *tab in DPViewsInWindow(window, DPDiaTabView, DPDiaPinnedTab)) DPReadTab(tab, tracked, sessions, urls);

    NSMutableSet<NSNumber *> *chosen = [NSMutableSet set];
    for (NSString *key in keys) {
        if ([sessions[key] count]) {
            [chosen addObjectsFromArray:sessions[key]];
            continue;
        }
        for (NSString *url in urls[key]) {
            NSMutableArray<NSNumber *> *list = byURL[url];
            if (!list.count) continue;
            [chosen addObject:list.firstObject];
            [list removeObjectAtIndex:0];
        }
    }
    return chosen.count >= 2 ? [chosen copy] : nil;
}

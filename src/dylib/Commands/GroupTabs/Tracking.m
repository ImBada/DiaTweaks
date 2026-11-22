#import "GroupTabs.h"

static NSHashTable *DPContents, *DPBrowsers;
static NSMapTable *DPBrowserByContents, *DPDelegateByBrowser, *DPWindowByBrowser;
static char DPSessionKey;

static long long DPContentsSession(id contents) {
    return [contents respondsToSelector:@selector(sessionId)] ? DPLongID(DPMsg(contents, @selector(sessionId))) : 0;
}

static void DPRemember(id contents, id session, id browser, id delegate) {
    if (browser) [DPBrowsers addObject:browser];
    if (browser && delegate) [DPDelegateByBrowser setObject:delegate forKey:browser];
    if (!contents || !browser) return;
    [DPBrowserByContents setObject:browser forKey:contents];
    [DPContents addObject:contents];
    long long sid = DPLongID(session);
    if (sid <= 0 && !DPGet(contents, &DPSessionKey)) sid = DPContentsSession(contents);
    if (sid > 0) DPSet(contents, &DPSessionKey, @(sid));
}

static void DPBrowser_setDelegate(id self, SEL _cmd, id delegate) {
    DPCallOriginal(DPBrowser_setDelegate, self, delegate);
    [DPBrowsers addObject:self];
    if (delegate) [DPDelegateByBrowser setObject:delegate forKey:self];
    else [DPDelegateByBrowser removeObjectForKey:self];
}

static void DPBrowser_setWindow(id self, SEL _cmd, NSWindow *window) {
    DPCallOriginal(DPBrowser_setWindow, self, window);
    [DPBrowsers addObject:self];
    if (window) [DPWindowByBrowser setObject:window forKey:self];
    else [DPWindowByBrowser removeObjectForKey:self];
}

static void DPBrowser_didRestore(id self, SEL _cmd, id browser, id contents, id session) {
    DPCallOriginal(DPBrowser_didRestore, self, browser, contents, session);
    if (browser) DPRemember(contents, session, browser, [self respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)] ? self : nil);
}

static void DPBrowser_didCreate(id self, SEL _cmd, id browser, id contents, BOOL active) {
    DPCallOriginal(DPBrowser_didCreate, self, browser, contents, active);
    if (browser && contents) DPRemember(contents, nil, browser, [self respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)] ? self : nil);
}

// Tabs opened from Dia's UI arrive only here; the delegate callbacks miss them.
static id DPBrowser_createWebContents(id self, SEL _cmd, id params) {
    id contents = DPCallOriginal(DPBrowser_createWebContents, self, params);
    DPRemember(contents, nil, self, nil);
    return contents;
}

// Link/script tabs bypass Dia's browser callbacks and inherit their opener's browser.
static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newContents, NSURL *url, NSInteger disposition) {
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newContents, url, disposition);
    if (disposition != 0) DPRemember(newContents, nil, DPBrowserOfContents(webContents), nil);
}

static id DPContents_clone(id self, SEL _cmd) {
    id clone = DPCallOriginal(DPContents_clone, self);
    DPRemember(clone, nil, DPBrowserOfContents(self), nil);
    return clone;
}

static void DPBrowser_takeOwnership(id self, SEL _cmd, id contents) {
    DPCallOriginal(DPBrowser_takeOwnership, self, contents);
    DPRemember(contents, nil, self, nil);
}

NSWindow *DPBrowserWindow(id browser) { return [DPWindowByBrowser objectForKey:browser]; }

static NSString *DPBrowserProfile(id browser) {
    id context = [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
    id contextID = [context respondsToSelector:@selector(id)] ? DPMsg(context, @selector(id)) : nil;
    return [contextID respondsToSelector:@selector(directoryBasename)] ? DPText(DPMsg(contextID, @selector(directoryBasename))) : nil;
}

static NSString *DPFocusedProfile(NSWindow *window) {
    id controller = DPSwiftValue(DPSwiftValue(window.windowController, @"viewModel"), @"delegate");
    id focused = DPSwiftValue(controller, @"committedFocusedBrowserContextID");
    return DPText(DPSwiftValue(DPSwiftValue(focused, @"profileID"), @"directoryBasename"));
}

static id DPFrontBrowser(NSWindow *window, NSArray *browsers) {
    NSMutableArray *shown = [NSMutableArray new];
    for (id browser in browsers)
        if (window && [DPWindowByBrowser objectForKey:browser] == window) [shown addObject:browser];
    if (shown.count < 2) return shown.firstObject;
    NSString *focused = DPFocusedProfile(window);
    for (id browser in shown)
        if ([DPBrowserProfile(browser) isEqual:focused]) return browser;
    return shown.firstObject;
}

id DPBrowserOfWindow(NSWindow *window) { return DPFrontBrowser(window, DPBrowsers.allObjects); }

id DPBrowserOfContents(id contents) { return [DPBrowserByContents objectForKey:contents]; }

id DPCommandBrowser(void) {
    NSMutableArray *ready = [NSMutableArray new];
    for (id browser in DPBrowsers.allObjects)
        if ([[DPDelegateByBrowser objectForKey:browser] respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) [ready addObject:browser];
    for (NSWindow *window in NSApp.orderedWindows) {
        id browser = DPFrontBrowser(window, ready);
        if (browser) return browser;
    }
    return ready.count == 1 ? ready[0] : nil;
}

id DPGroupingDelegate(id browser) { return [DPDelegateByBrowser objectForKey:browser]; }

NSArray *DPTrackedContents(id browser) {
    NSMutableArray *contents = [NSMutableArray new];
    for (id each in DPContents.allObjects) if ([DPBrowserByContents objectForKey:each] == browser) [contents addObject:each];
    return contents;
}

// Discarding a page gives it a new session, but Dia's tabs keep the one it had when it opened.
long long DPSessionOf(id contents) {
    long long sid = DPLongID(DPGet(contents, &DPSessionKey));
    return sid > 0 ? sid : DPContentsSession(contents);
}

void DPInstallGroupTabs(void) {
    DPContents = [NSHashTable weakObjectsHashTable];
    DPBrowsers = [NSHashTable weakObjectsHashTable];
    DPBrowserByContents = [NSMapTable weakToWeakObjectsMapTable];
    DPDelegateByBrowser = [NSMapTable weakToWeakObjectsMapTable];
    DPWindowByBrowser = [NSMapTable weakToWeakObjectsMapTable];

    DPHook(DPDiaBrowser, @selector(setDelegate:), (IMP)DPBrowser_setDelegate);
    DPHook(DPDiaBrowser, @selector(setWindow:), (IMP)DPBrowser_setWindow);
    DPHook(DPDiaBrowser, @selector(createWebContents:), (IMP)DPBrowser_createWebContents);
    DPHook(DPDiaBrowser, @selector(takeOwnershipOfWebContents:), (IMP)DPBrowser_takeOwnership);
    DPHook(DPDiaBrowserDelegate, @selector(browser:didRestoreWebContents:withSessionId:), (IMP)DPBrowser_didRestore);
    DPHook(DPDiaBrowserDelegate, @selector(browser:didCreateNewWebContents:isActive:), (IMP)DPBrowser_didCreate);
    DPHook(DPDiaWebContents, @selector(clone), (IMP)DPContents_clone);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate);
    });
    DPInstallGroupMenus();
    DPInstallGroupTabsShortcut();
}

#import "LittleDia.h"
#import "Commands/GroupTabs/GroupTabs.h"

static NSString *const DPFromAllTabs = @"all", *const DPFromPinnedTabs = @"pinned";

static NSArray *DPList(id object, SEL sel) {
    NSArray *list = [object respondsToSelector:sel] ? DPMsg(object, sel) : nil;
    return [list isKindOfClass:NSArray.class] ? list : @[];
}

static NSURL *DPPageURL(id page) {
    id url = [page respondsToSelector:@selector(url)] ? DPMsg(page, @selector(url)) : nil;
    return [url isKindOfClass:NSURL.class] ? url : nil;
}

// Pages expose no scripting tab id, so match the URL uniquely to a pinned icon.
static BOOL DPOnPinnedIcon(id page) {
    NSString *url = DPPageURL(page).absoluteString;
    if (!url.length) return NO;
    BOOL pinnedHere = NO;
    for (id window in DPList(NSApp.delegate, @selector(appleScriptWindows)))
        for (id tab in DPList(window, @selector(appleScriptTabs))) {
            NSString *address = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
            if (![address isEqual:url]) continue;
            if (![tab respondsToSelector:@selector(isPinned)] || !DPMsgBool(tab, @selector(isPinned))) return NO;
            pinnedHere = YES;
        }
    return pinnedHere;
}

// Scripting calls only the icons pinned; a pinned row says so in its menu. Ask the page's own window, not the key one.
static BOOL DPFromPinnedTab(id page, NSWindow *window) { return (window && DPPageInPinnedRow(window, page)) || DPOnPinnedIcon(page); }

static BOOL DPInLittleDia(id page) {
    for (NSWindow *window in NSApp.windows)
        if (DPIsLittleDiaWindow(window) && DPLittleDiaPage(window) == page) return YES;
    return NO;
}

static BOOL DPPlainClick(void) {
    NSEventModifierFlags held = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagControl;
    return !(NSEvent.modifierFlags & held);
}

// Little Dia opens via the front browser, which must match the clicked page and never be private.
static BOOL DPOpensInOwnProfile(id browser) {
    id context = [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
    id contextID = [context respondsToSelector:@selector(id)] ? DPMsg(context, @selector(id)) : nil;
    return browser && browser == DPCommandBrowser() && [contextID respondsToSelector:@selector(isIncognito)] && !DPMsgBool(contextID, @selector(isIncognito));
}

static BOOL DPInPeek(id page) {
    for (NSView *card in DPFindViews("DPPeekCard"))
        if (DPValueForKey(card, @"page") == page) return YES;
    return NO;
}

static BOOL DPTakesTabLink(id page, NSURL *url, BOOL leavesPinned) {
    if (!DPIsWebURL(url) || !DPLittleDiaReady() || !page || DPInLittleDia(page) || DPInPeek(page) || !DPIsWebURL(DPPageURL(page))) return NO;
    id browser = DPBrowserOfContents(page);
    if (!DPOpensInOwnProfile(browser)) return NO;
    NSWindow *source = DPBrowserWindow(browser);
    if (!leavesPinned && ![DPChoice(&DPLittleDiaTabLinks) isEqual:DPFromAllTabs] && !DPFromPinnedTab(page, source)) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenTabLinkInLittleDia(url, source); });  // Not from inside Chromium's callback.
    return YES;
}

static NSString *DPHovered, *DPPressed;
static __weak id DPHoveredPage, DPPressedPage;
static NSTimeInterval DPPressedAt;
static id DPPressMonitor;

// Pages clear status text on mouse-down before decidePolicy runs, so the link hovered at mouse-down stands in.
static BOOL DPOverLink(id page, NSURL *url) {
    NSString *key = url ? DPLittleDiaLinkKey(url.absoluteString) : nil;
    if (!page || !key) return NO;
    if (page == DPHoveredPage && [key isEqual:DPHovered]) return YES;
    return page == DPPressedPage && [key isEqual:DPPressed] && NSProcessInfo.processInfo.systemUptime - DPPressedAt < 2;
}

static BOOL DPLeavesPinnedSite(id page, id action, NSInteger disposition) {
    NSInteger type = [DPValueForKey(action, @"navigationType") integerValue];
    // navigationType 0 is a link activation; 4 is how Dia reports target=_blank clicks.
    BOOL stays = disposition == DPCurrentTab || disposition == DPForegroundTab;
    if (!stays || (type != 0 && !(type == 4 && disposition == DPForegroundTab))) return NO;
    NSString *from = DPDomainKey([DPValueForKey(page, @"url") absoluteString]), *to = DPDomainKey([DPValueForKey(action, @"url") absoluteString]);
    if (!from || !to || [DPRegistrableDomain(from) isEqual:DPRegistrableDomain(to)]) return NO;
    NSWindow *window = DPBrowserWindow(DPBrowserOfContents(page));
    return window && DPPageInPinnedRow(window, page);
}

static NSInteger DPTabLinks_decidePolicy(id self, SEL _cmd, id webContents, id action) {
    NSInteger policy = DPCallOriginal(DPTabLinks_decidePolicy, self, webContents, action);
    if (!DPLittleDia.on || !DPLittleDiaTabLinks.on || !DPPlainClick()) return policy;
    NSURL *url = DPValueForKey(action, @"url");
    NSInteger disposition = [DPValueForKey(action, @"navigationDisposition") integerValue];
    // Script-opened tabs have no link under the pointer and would lose their opener in Little Dia.
    BOOL clicked = disposition != DPForegroundTab || DPOverLink(webContents, url);
    BOOL leaves = clicked && policy == DPCurrentTab && DPLeavesPinnedSite(webContents, action, disposition);
    if (!leaves && policy == DPForegroundTab) {
        // Ask Dia as if the link stayed in the tab: only an icon-only pinned tab turns that into a new tab.
        leaves = disposition == DPCurrentTab;
        if (disposition == DPForegroundTab) leaves = DPCallOriginal(DPTabLinks_decidePolicy, self, webContents, DPActionStayingInTab(action)) == DPForegroundTab;
    }
    return (policy == DPForegroundTab || leaves) && clicked && DPTakesTabLink(webContents, url, leaves) ? DPIgnoreAction : policy;
}

static void DPTabLinks_status(id self, SEL _cmd, id webContents, NSString *text) {
    DPCallOriginal(DPTabLinks_status, self, webContents, text);
    if (!DPLittleDia.on || !DPLittleDiaTabLinks.on) return;
    DPHovered = text.length ? DPLittleDiaLinkKey(text) : nil;
    DPHoveredPage = webContents;
}

static void DPApplyTabLinks(DPPatch *patch) {
    DPSyncMonitor(&DPPressMonitor, patch->on, NSEventMaskLeftMouseDown, ^NSEvent *(NSEvent *event) {
        DPPressed = DPHovered;
        DPPressedPage = DPHoveredPage;
        DPPressedAt = event.timestamp;
        return event;
    });
}

static void DPInstallTabLinks(void) {
    DPApplyTabLinks(&DPLittleDiaTabLinks);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPTabLinks_decidePolicy);
        DPHook(DPDiaWebContent, @selector(webContents:didChangeStatusText:), (IMP)DPTabLinks_status);
    });
}

static NSMenu *DPTabLinksChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Open Links From"];
    [menu addItemWithTitle:@"Pinned Tabs" action:nil keyEquivalent:@""].representedObject = DPFromPinnedTabs;
    [menu addItemWithTitle:@"All Tabs" action:nil keyEquivalent:@""].representedObject = DPFromAllTabs;
    return menu;
}

static NSString *DPVerifyTabLinks(DPPatch *patch) {
    Class delegate = objc_getClass(DPDiaWebContent);
    if (!DPIsHooked(delegate, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPTabLinks_decidePolicy)) return @"link clicks don’t reach Little Dia";
    if (!DPIsHooked(delegate, @selector(webContents:didChangeStatusText:), (IMP)DPTabLinks_status)) return @"hovered links don’t reach Little Dia";
    return nil;
}

DP_PATCH(DPLittleDiaTabLinks) {
    .key = @"littleDiaTabLinks",
    .experimental = YES,
    .order = 104,
    .title = @"Open Links from Tabs",
    .detail = @"Links that would open a new tab open in Little Dia over the page instead. "
              @"Choose pinned tabs only, including links that leave a pinned tab’s site, or every tab. Clicks with Option, Command, Shift or Control held keep their usual meaning.",
    .symbol = @"arrow.up.forward.app arrow.up.right.square",
    .tint = @"systemMintColor",
    .requires = @"littleDia",
    .choice = @"littleDiaTabLinksFrom",
    .defaultChoice = @"pinned",
    .choices = DPTabLinksChoices,
    .classes = DPClasses(DPDiaBrowserContext, DPDiaWebContents, DPDiaWebContentsConfiguration, DPDiaContentPane),
    .install = DPInstallTabLinks,
    .apply = DPApplyTabLinks,
    .verify = DPVerifyTabLinks,
};

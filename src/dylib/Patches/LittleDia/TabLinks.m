#import "LittleDia.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Patches/Peek/Peek.h"

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

// Scripting calls only the icons pinned; a pinned row says so in its menu.
static BOOL DPFromPinnedTab(id page) { return DPPeekInPinnedRow(NSApp.keyWindow, page) || DPOnPinnedIcon(page); }

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

BOOL DPLittleDiaTakesTabLink(id page, NSURL *url, BOOL leavesPinned) {
    if (!DPLittleDia.on || !DPLittleDiaTabLinks.on || !DPPeekIsWeb(url) || !DPPlainClick() || !DPLittleDiaReady()) return NO;
    if (!page || DPInLittleDia(page) || DPPeekShows(page) || !DPPeekIsWeb(DPPageURL(page))) return NO;
    id browser = DPBrowserOfContents(page);
    if (!DPOpensInOwnProfile(browser)) return NO;
    if (!leavesPinned && ![DPChoice(&DPLittleDiaTabLinks) isEqual:DPFromAllTabs] && !DPFromPinnedTab(page)) return NO;
    NSWindow *source = DPBrowserWindow(browser);
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenTabLinkInLittleDia(url, source); });  // Not from inside Chromium's callback.
    return YES;
}

static NSMenu *DPTabLinksChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Open Links From"];
    [menu addItemWithTitle:@"Pinned Tabs" action:nil keyEquivalent:@""].representedObject = DPFromPinnedTabs;
    [menu addItemWithTitle:@"All Tabs" action:nil keyEquivalent:@""].representedObject = DPFromAllTabs;
    return menu;
}

// Peek owns the link hooks and asks Little Dia first, so check those are in place rather than adding a second hook.
static NSString *DPVerifyTabLinks(DPPatch *patch) {
    Class delegate = objc_getClass(DPDiaWebContent);
    SEL decide = @selector(webContents:decidePolicyForNavigationAction:);
    SEL created = @selector(webContents:didCreateNewWebContent:targetURL:disposition:);
    if (class_getMethodImplementation(delegate, decide) == DPDiaIMP(delegate, decide)) return @"link clicks don't reach Little Dia";
    if (class_getMethodImplementation(delegate, created) == DPDiaIMP(delegate, created)) return @"new tabs don't reach Little Dia";
    return nil;
}

DP_PATCH(DPLittleDiaTabLinks) {
    .key = @"littleDiaTabLinks",
    .order = 104,
    .title = @"Open Links from Tabs",
    .detail = @"Links that would open a new tab open in Little Dia over the page instead. "
              @"Choose pinned tabs only, including links that leave a pinned tab’s site, or every tab. Clicks with Option, Command, Shift or Control held keep their usual meaning. Experimental.",
    .symbol = @"arrow.up.forward.app arrow.up.right.square",
    .tint = @"systemMintColor",
    .requires = @"littleDia",
    .choice = @"littleDiaTabLinksFrom",
    .defaultChoice = @"pinned",
    .choices = DPTabLinksChoices,
    .classes = DPClasses(DPDiaBrowserContext, DPDiaWebContents, DPDiaWebContentsConfiguration, DPDiaContentPane),
    .verify = DPVerifyTabLinks,
};

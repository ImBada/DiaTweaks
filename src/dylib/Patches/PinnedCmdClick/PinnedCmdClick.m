#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPPinnedCmdClick;

static NSArray *DPPinnedCmdClickList(id object, SEL sel) {
    NSArray *list = [object respondsToSelector:sel] ? DPMsg(object, sel) : nil;
    return [list isKindOfClass:NSArray.class] ? list : @[];
}

// Favorite icons aren't pinned rows, so ask the scripting tabs whether the page is pinned. The page's own window
// answers if it lists the address; another window's copy only counts when the own window doesn't say.
static BOOL DPPinnedCmdClickOnIcon(id page) {
    NSURL *pageURL = DPValueForKey(page, @"url");
    NSString *url = [pageURL isKindOfClass:NSURL.class] ? pageURL.absoluteString : nil;
    if (!url.length) return NO;
    NSString *own = DPBrowserWindow(DPBrowserOfContents(page)).identifier;
    BOOL ownListed = NO, ownPinned = NO, pinned = NO;
    for (id window in DPPinnedCmdClickList(NSApp.delegate, @selector(appleScriptWindows))) {
        BOOL mine = own && [DPValueForKey(window, @"windowId") isEqual:own];
        for (id tab in DPPinnedCmdClickList(window, @selector(appleScriptTabs))) {
            NSString *address = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
            if (![address isEqual:url]) continue;
            BOOL isPinned = [tab respondsToSelector:@selector(isPinned)] && DPMsgBool(tab, @selector(isPinned));
            pinned |= isPinned;
            ownListed |= mine;
            ownPinned |= mine && isPinned;
        }
    }
    return ownListed ? ownPinned : pinned;
}

// The page's own window, not the key one: another window's selected pinned row would answer for it.
static BOOL DPPinnedCmdClickSourcePinned(id page) {
    NSWindow *window = page ? DPBrowserWindow(DPBrowserOfContents(page)) : nil;
    return page && ((window && DPPageInPinnedRow(window, page)) || DPPinnedCmdClickOnIcon(page));
}

static BOOL DPPinnedCmdClickWanted(NSInteger disposition) {
    if (disposition == DPBackgroundTab) return YES;
    if (disposition != DPForegroundTab) return NO;
    NSEventModifierFlags mods = NSEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (mods & NSEventModifierFlagCommand) return YES;
    if ((NSEvent.pressedMouseButtons & 4) != 0) return YES;
    // The click's modifiers can already be cleared by the time the tab is created, so ask the event too.
    NSEvent *event = NSApp.currentEvent;
    if (!event) return NO;
    if ((event.modifierFlags & NSEventModifierFlagCommand) != 0) return YES;
    return (event.type == NSEventTypeOtherMouseDown || event.type == NSEventTypeOtherMouseUp) && event.buttonNumber == 2;
}

static NSView *DPPinnedCmdClickTabForPage(NSWindow *window, id page) {
    NSString *pageID = DPPageID(page);
    if (!pageID) return nil;
    return DPFindTabIn(window, ^BOOL(NSView *tab) { return [[DPTabState(tab) description] containsString:pageID]; });
}

static NSView *DPPinnedCmdClickTabInAnyWindow(id page, NSWindow **owner) {
    NSWindow *own = page ? DPBrowserWindow(DPBrowserOfContents(page)) : nil;
    NSView *tab = own ? DPPinnedCmdClickTabForPage(own, page) : nil;
    if (tab) {
        if (owner) *owner = own;
        return tab;
    }
    NSWindow *key = NSApp.keyWindow;
    if (key && key != own) {
        tab = DPPinnedCmdClickTabForPage(key, page);
        if (tab) {
            if (owner) *owner = key;
            return tab;
        }
    }
    for (NSWindow *window in NSApp.orderedWindows) {
        if (window == own || window == key) continue;
        tab = DPPinnedCmdClickTabForPage(window, page);
        if (tab) {
            if (owner) *owner = window;
            return tab;
        }
    }
    return nil;
}

static NSMenuItem *DPPinnedCmdClickUnpinItem(NSView *tab) {
    NSMenu *menu = tab ? DPTabContextMenu(tab) : nil;
    NSMenuItem *item = [menu itemWithTitle:@"Unpin"];
    // A nil-target item runs down the responder chain and could unpin whichever pinned tab is selected.
    return item && item.target && !item.hidden && item.enabled ? item : nil;
}

// The sidebar builds the new row a moment after the tab exists.
static void DPPinnedCmdClickUnpin(id page, int tries) {
    if (!DPPinnedCmdClick.on) return;
    NSWindow *owner = nil;
    NSView *tab = DPPinnedCmdClickTabInAnyWindow(page, &owner);
    NSMenuItem *item = DPPinnedCmdClickUnpinItem(tab);
    if (item && DPPinnedCmdClickTabForPage(owner, page) == tab)
        return (void)[item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
    if (tries <= 0) return;
    __weak id weakPage = page;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
        id live = weakPage;
        if (live) DPPinnedCmdClickUnpin(live, tries - 1);
    });
}

static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    BOOL wanted = DPPinnedCmdClick.on && DPPinnedCmdClickWanted(disposition) && DPIsWebURL(url)
        && DPPinnedCmdClickSourcePinned(webContents);
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    if (!wanted) return;
    __weak id weakNew = newWebContent;
    dispatch_async(dispatch_get_main_queue(), ^{
        id live = weakNew;
        if (live) DPPinnedCmdClickUnpin(live, 5);
    });
}

static void DPInstallPinnedCmdClick(void) {
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate);
    });
}

static NSString *DPVerifyPinnedCmdClick(DPPatch *patch) {
    Class delegate = objc_getClass(DPDiaWebContent);
    SEL created = @selector(webContents:didCreateNewWebContent:targetURL:disposition:);
    if (!delegate || class_getMethodImplementation(delegate, created) == DPDiaIMP(delegate, created)) return @"new tabs don’t reach Pinned Tabs";
    return nil;
}

DP_PATCH(DPPinnedCmdClick) {
    .key = @"openPinnedCmdClicksUnpinned",
    .order = 68,
    .title = @"Open ⌘-Clicked Links as Regular Tabs",
    .detail = @"When you ⌘-click or middle-click a link in a pinned tab, open the new tab in your regular tab list instead of pinning it too.",
    .symbol = @"pin.slash",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .group = @"pinnedTabs",
    .classes = DPClasses(DPDiaWebContents, DPDiaTabView),
    .install = DPInstallPinnedCmdClick,
    .verify = DPVerifyPinnedCmdClick,
};

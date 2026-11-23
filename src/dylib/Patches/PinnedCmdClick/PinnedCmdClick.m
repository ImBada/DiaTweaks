#import "StdPatch/StdPatch.h"
#import "Patches/Peek/Peek.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPPinnedCmdClick;

static NSArray *DPPinnedCmdClickList(id object, SEL sel) {
    NSArray *list = [object respondsToSelector:sel] ? DPMsg(object, sel) : nil;
    return [list isKindOfClass:NSArray.class] ? list : @[];
}

// Favorite icons aren't pinned rows, so ask the scripting tabs whether the page is pinned.
static BOOL DPPinnedCmdClickOnIcon(id page) {
    NSString *url = [DPValueForKey(page, @"url") absoluteString];
    if (!url.length) return NO;
    BOOL pinned = NO;
    for (id window in DPPinnedCmdClickList(NSApp.delegate, @selector(appleScriptWindows)))
        for (id tab in DPPinnedCmdClickList(window, @selector(appleScriptTabs))) {
            NSString *address = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
            if (![address isEqual:url]) continue;
            if (![tab respondsToSelector:@selector(isPinned)] || !DPMsgBool(tab, @selector(isPinned))) return NO;
            pinned = YES;
        }
    return pinned;
}

static BOOL DPPinnedCmdClickSourcePinned(id page) {
    return page && (DPPeekInPinnedRow(NSApp.keyWindow, page) || DPPinnedCmdClickOnIcon(page));
}

// A background tab is a ⌘- or middle-click; a foreground one only counts with ⌘ or the middle button held.
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

static NSString *DPPinnedCmdClickPageID(id page) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = @[@"identifier", @"id", @"contentID", @"contentId", @"uuid"]; });
    for (NSString *key in keys) {
        NSString *value = [DPSwiftValue((NSObject *)page, key) description];
        if (value.length >= 32 && [value containsString:@"-"]) return value;
    }
    return nil;
}

static NSView *DPPinnedCmdClickTabForPage(NSWindow *window, id page) {
    NSString *pageID = DPPinnedCmdClickPageID(page);
    if (!pageID) return nil;
    const char *kinds[2] = {DPDiaTabView, DPDiaPinnedTab};
    for (int i = 0; i < 2; i++)
        for (NSView *tab in DPFindViews(kinds[i]))
            if (tab.window == window && !tab.isHiddenOrHasHiddenAncestor
                && [[DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue") description] containsString:pageID])
                return tab;
    return nil;
}

static NSView *DPPinnedCmdClickTabInAnyWindow(id page, NSWindow **owner) {
    NSWindow *key = NSApp.keyWindow;
    NSView *tab = key ? DPPinnedCmdClickTabForPage(key, page) : nil;
    if (tab) {
        if (owner) *owner = key;
        return tab;
    }
    for (NSWindow *window in NSApp.orderedWindows) {
        if (window == key) continue;
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
        DPPinnedCmdClickUnpin(page, tries - 1);
    });
}

static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    BOOL wanted = DPPinnedCmdClick.on && DPPinnedCmdClickWanted(disposition) && DPPeekIsWeb(url)
        && DPPinnedCmdClickSourcePinned(webContents);
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    if (!wanted) return;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPinnedCmdClickUnpin(newWebContent, 20); });
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

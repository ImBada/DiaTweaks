#import "Patches/UnloadTab/Pages.h"
#import "Patches/UnloadTab/Recent.h"
#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

static id DPControllerOf(NSView *view) {
    return DPViewModelDelegate(view) ?: DPSwiftValue(DPSwiftValue(view, @"viewModel"), @"delegate");
}

static BOOL DPIsClosedPinned(NSView *content) {
    __attribute__((objc_precise_lifetime)) id attributes = DPAttributes(content);
    BOOL *pinned = DPIvar(attributes, "isInFavoritesOrPinnedContainer");
    void **activeURL = DPIvar(attributes, "activeURL");
    return pinned && *pinned && activeURL && !*activeURL;
}

static BOOL DPTabViewInfo(NSView *tab, NSString **outTabID, NSString **outContentID, NSURL **outURL) {
    id views = DPSwiftValue(tab, @"contentViews");
    if ([views isKindOfClass:NSDictionary.class]) {
        if ([views count] > 1) return NO;
        if ([views count] == 1) {
            id content = DPControllerOf([[views allValues] firstObject]);
            if (!content) return NO;
            *outTabID = DPUUIDsIn([DPSwiftValue(content, @"tabID") description]).firstObject;
            *outContentID = DPUUIDsIn([[[views allKeys] firstObject] description]).firstObject;
            if (!*outContentID && (DPIvar(content, "contentID") || [content respondsToSelector:NSSelectorFromString(@"contentID")]))
                *outContentID = DPUUIDsIn([DPSwiftValue(content, @"contentID") description]).firstObject;
            id rawURL = DPSwiftValue(content, @"webContentURL");
            *outURL = [rawURL isKindOfClass:NSURL.class] ? rawURL : nil;
            return *outTabID != nil || *outContentID != nil;
        }
    }
    id viewModel = DPSwiftValue(tab, @"viewModel");
    id state = DPSwiftValue(DPSwiftValue(viewModel, @"stateSubject"), @"currentValue");
    NSArray<NSString *> *ids = DPUUIDsIn([DPSwiftValue(state, @"contentIDs") description]);
    if (ids.count != 1) return NO;
    *outContentID = ids.firstObject;
    *outTabID = DPUUIDsIn([DPSwiftValue(viewModel, @"tabID") description]).firstObject;
    *outURL = *outTabID ? DPScriptTabURL(tab.window, *outTabID) : nil;
    return YES;
}

static BOOL DPPinnedTabInfo(NSView *dock, NSString **outTabID, NSString **outContentID) {
    id state = DPSwiftValue(DPSwiftValue(DPSwiftValue(dock, @"viewModel"), @"stateSubject"), @"currentValue");
    if ([[[DPSwiftValue(state, @"icon") description] lowercaseString] containsString:@"split"]) return NO;
    id controller = DPControllerOf(dock);
    NSString *itemDesc = controller ? [DPSwiftValue(controller, @"itemID") description] : nil;
    NSString *tabID = itemDesc && ![[itemDesc lowercaseString] containsString:@"group"] ? DPUUIDsIn(itemDesc).firstObject : nil;
    if (!tabID) return NO;
    NSString *contentID = nil;
    id controllers = DPSwiftValue(controller, @"contentControllers");
    if ([controllers isKindOfClass:NSDictionary.class]) {
        if ([controllers count] > 1) return NO;
        if ([controllers count] == 1)
            contentID = DPUUIDsIn([[[controllers allKeys] firstObject] description]).firstObject
                ?: DPUUIDsIn([DPSwiftValue([[controllers allValues] firstObject], @"contentPaneID") description]).firstObject;
    } else if (controllers) {
        NSOrderedSet<NSString *> *ids = [NSOrderedSet orderedSetWithArray:DPUUIDsIn([controllers description])];
        if (ids.count > 1) return NO;
        contentID = ids.firstObject;
    }
    *outTabID = tabID;
    *outContentID = contentID;
    return YES;
}

static BOOL DPTabOpen(NSView *tab, NSString *tabID) {
    id state = DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue");
    NSString *style = [[DPSwiftValue(state, @"selectionStyle") description] lowercaseString];
    if (style && ![style isEqualToString:@"nil"] && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"])
        return YES;
    return tabID && tab.window && [tabID isEqualToString:DPActiveTabID(tab.window)];
}

static char DPUnloadItemKey;

static void DPRemoveUnloadItems(NSMenu *menu) {
    for (NSMenuItem *item in [menu.itemArray copy])
        if (DPGet(item, &DPUnloadItemKey)) [menu removeItem:item];
}

static void DPAddUnloadMenuItem(NSMenu *menu, NSView *tab, NSString *tabID, id page, NSView *closePane) {
    BOOL open = DPTabOpen(tab, tabID);
    BOOL visible = page ? DPPageIsVisible(page) : open;
    NSWindow *window = tab.window;
    id before = visible && open ? DPTabBefore(window) : nil;
    NSString *tabIDCopy = [tabID copy];
    __weak NSWindow *weakWindow = window;
    __weak NSView *weakTab = tab, *weakClosePane = closePane;
    __weak id weakPage = page;
    NSMenuItem *item = DPMenuItem(@"Unload Tab", ^{
        if (!DPUnloadTab.on) return;
        NSWindow *win = weakWindow;
        NSView *targetTab = weakTab, *targetClose = weakClosePane;
        id targetPage = weakPage;
        BOOL isOpen = targetTab && DPTabOpen(targetTab, tabIDCopy);
        if (targetPage) {
            if (!DPPageIsTracked(targetPage) || DPPageIsDiscarded(targetPage)) return;
            BOOL isVisible = DPPageIsVisible(targetPage);
            id targetBefore = isVisible && isOpen && win ? DPTabBefore(win) : nil;
            if (isVisible && !targetBefore) return;
            if (targetBefore && win) DPForgetFrontTab(win);
            DPUnloadPage(targetPage, targetBefore);
            return;
        }
        if (!targetClose || !targetClose.window || DPIsClosedPinned(targetClose)) return;
        id targetBefore = isOpen && win ? DPTabBefore(win) : nil;
        if (targetBefore && win) DPForgetFrontTab(win);
        if (targetBefore) DPFocusTab(targetBefore);
        DPMarkOwnClose();
        DPCloseKeepingTab(targetClose);
    });
    DPSet(item, &DPUnloadItemKey, @YES);
    item.image = [NSImage imageWithSystemSymbolName:@"moon.zzz" accessibilityDescription:nil];
    // By name: CI's SDK predates macOS 27. 1 is NSMenuItemImageVisibilityVisible.
    if (@available(macOS 27, *)) DPSetValueForKey(item, @"preferredImageVisibility", @1);
    item.enabled = closePane != nil || !visible || before != nil;
    NSInteger index = [menu indexOfItemWithTitle:@"Close"];
    if (index < 0) index = [menu indexOfItemWithTitle:@"Close Tab"];
    if (index < 0) index = [menu indexOfItemWithTitle:@"Delete"];
    [menu insertItem:item atIndex:index < 0 ? menu.numberOfItems : index];
}

static NSMenu *DPTab_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPTab_menuForEvent, self, event);
    if (!menu) return nil;
    DPRemoveUnloadItems(menu);
    if (!DPUnloadTab.on || [menu itemWithTitle:@"Unload Tab"]) return menu;
    DPRecordVisiblePanePages();
    NSView *pane = DPFindView(self, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabContentView); });
    if (pane && DPIsClosedPinned(pane)) return menu;
    NSString *tabID = nil, *contentID = nil;
    NSURL *url = nil;
    if (!DPTabViewInfo(self, &tabID, &contentID, &url)) return menu;
    id page = DPPageForPane(self.window, contentID) ?: DPPageByURL(tabID, contentID, url);
    if (page && DPPageIsDiscarded(page)) return menu;
    NSView *closePane = !page && pane && DPIsOpenPinned(pane) && [pane respondsToSelector:NSSelectorFromString(@"closeButtonClicked")] ? pane : nil;
    if (!page && !closePane) return menu;
    DPAddUnloadMenuItem(menu, self, tabID, page, closePane);
    return menu;
}

static NSMenu *DPPinnedTab_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPPinnedTab_menuForEvent, self, event);
    if (!menu) return nil;
    DPRemoveUnloadItems(menu);
    if (!DPUnloadTab.on || [menu itemWithTitle:@"Unload Tab"]) return menu;
    DPRecordVisiblePanePages();
    NSString *tabID = nil, *contentID = nil;
    if (!DPPinnedTabInfo(self, &tabID, &contentID)) return menu;
    id page = DPPageForPane(self.window, contentID) ?: DPPageByURL(tabID, contentID, DPScriptTabURL(self.window, tabID));
    if (!page || DPPageIsDiscarded(page)) return menu;
    DPAddUnloadMenuItem(menu, self, tabID, page, nil);
    return menu;
}

static NSString *DPVerifyTab(NSView *tab, BOOL on, BOOL dock, NSCountedSet<NSURL *> *urls) {
    NSMenu *menu = DPTabContextMenu(tab);
    if (!menu) return nil;
    NSMenuItem *item = [menu itemWithTitle:@"Unload Tab"];
    if (!on) return item ? (dock ? @"pinned tab still offers Unload Tab" : @"tab still offers Unload Tab") : nil;
    NSString *tabID = nil, *contentID = nil;
    NSURL *url = nil;
    if (dock) {
        if (!DPPinnedTabInfo(tab, &tabID, &contentID)) return nil;
        url = DPScriptTabURL(tab.window, tabID);
    } else {
        NSView *pane = DPFindView(tab, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTabContentView); });
        if (pane && DPIsClosedPinned(pane)) return item ? @"closed pinned tab still offers Unload Tab" : nil;
        if (!DPTabViewInfo(tab, &tabID, &contentID, &url)) return nil;
    }
    id page = DPPageForPane(tab.window, contentID) ?: DPPageByURL(tabID, contentID, url);
    if (page && DPPageIsDiscarded(page)) return item ? @"unloaded tab still offers Unload Tab" : nil;
    BOOL front = DPTabOpen(tab, tabID);
    if (!page) {
        if (dock) return item ? @"unloaded pinned tab still offers Unload Tab" : nil;
        if (!front || ![url.scheme hasPrefix:@"http"] || [urls countForObject:url] > 1) return nil;
    }
    if (!item) return dock ? @"loaded pinned tab has no Unload Tab" : front ? @"tab in front has no Unload Tab" : @"loaded tab has no Unload Tab";
    id scriptTabs = DPValueForKey(DPScriptWindow(tab.window), @"appleScriptTabs");
    if (front && !item.enabled && [scriptTabs isKindOfClass:NSArray.class] && [scriptTabs count] > 1)
        return dock ? @"Unload Tab can't leave the pinned tab in front" : @"Unload Tab can't leave the tab in front";
    return nil;
}

static NSString *DPVerifyUnloadTab(DPPatch *patch) {
    DPRecordVisiblePanePages();
    NSCountedSet<NSURL *> *urls = DPScriptTabURLCounts();
    const char *kinds[2] = {DPDiaTabView, DPDiaPinnedTab};
    for (int i = 0; i < 2; i++)
        for (NSView *tab in DPFindViews(kinds[i]))
            if (tab.window && !tab.isHiddenOrHasHiddenAncestor) {
                NSString *err = DPVerifyTab(tab, patch->on, i == 1, urls);
                if (err) return err;
            }
    return nil;
}

static void DPInstallUnloadTab(void) {
    DPInstallUnloadPages();
    DPHook(DPDiaTabView, @selector(menuForEvent:), (IMP)DPTab_menuForEvent);
    DPHook(DPDiaPinnedTab, @selector(menuForEvent:), (IMP)DPPinnedTab_menuForEvent);
    DPWatchFrontTabs();
}

DP_PATCH(DPUnloadTab) {
    .key = @"unloadTab",
    .order = 86,
    .section = @"Tabs",
    .title = @"Unload Tabs",
    .detail = @"Right-click a tab or pinned tab and choose Unload Tab to free its memory. It stays where it is and loads again when you open it. Unloading the tab you’re on takes you back to the one you were on before.",
    .symbol = @"moon.zzz.fill",
    .tint = @"systemPinkColor",
    .classes = DPClasses(DPDiaWebContents, DPDiaTabView, DPDiaPinnedTab, DPDiaContentPane),
    .install = DPInstallUnloadTab,
    .verify = DPVerifyUnloadTab,
};

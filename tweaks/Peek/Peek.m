#import "Peek.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/HideToolbar/HideToolbar.h"

static NSURL *DPPeekHovered;
static __weak id DPPeekHoveredPage, DPPeekHoveredDelegate;
static NSUInteger DPPeekLookAheadTurn;

static NSEventModifierFlags DPPeekModifiers(void) {
    return NSEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask &
           ~(NSEventModifierFlagCapsLock | NSEventModifierFlagNumericPad | NSEventModifierFlagFunction);
}

static BOOL DPPeekWanted(NSInteger disposition) {
    if (!DPPeek.on || DPPeekGiving) return NO;
    BOOL elsewhere = disposition == DPForegroundTab || disposition == DPBackgroundTab || disposition == DPPopup || disposition == DPNewWindow;
    return elsewhere && DPPeekModifiers() == NSEventModifierFlagShift;
}

static void DPPeekOpenLater(id delegate, id source, NSURL *url) {
    DPPeekLookAheadTurn++;
    NSWindow *window = NSApp.keyWindow;
    NSString *originTabID = DPActiveTabID(window);
    NSPoint origin = NSEvent.mouseLocation;
    __weak NSWindow *weakWindow = window;
    __weak id weakDelegate = delegate, weakSource = source;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *win = weakWindow;
        id del = weakDelegate, src = weakSource;
        if (win && src) DPPeekOpen(win, originTabID, url, origin, del, src);
    });
}

static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    if (!DPPeekWanted(disposition) || !(DPPeekShows(webContents) || (DPIsWebURL(url) && DPPeekCanOpen(webContents))))
        return (void)DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, (NSInteger)DPIgnoreAction);
    if (DPPeekShows(webContents)) return DPPeekLoad(webContents, url);
    DPPeekOpenLater(self, webContents, url);
}

static BOOL DPPeekLeavesPinnedRow(id webContents, id action, NSInteger disposition, NSInteger policy) {
    BOOL stays = disposition == DPCurrentTab || disposition == DPForegroundTab;
    NSInteger type = [DPValueForKey(action, @"navigationType") integerValue];
    // navigationType 0 is a link activation; 4 is how Dia reports target=_blank clicks.
    BOOL clicked = type == 0 || (type == 4 && disposition == DPForegroundTab);
    if (DPPeekModifiers() || !stays || !clicked || (policy != DPCurrentTab && policy != DPForegroundTab)) return NO;
    NSString *from = DPDomainKey([DPValueForKey(webContents, @"url") absoluteString]), *to = DPDomainKey([DPValueForKey(action, @"url") absoluteString]);
    if (!from || !to || [DPRegistrableDomain(from) isEqual:DPRegistrableDomain(to)]) return NO;
    return !DPPeekShows(webContents) && DPPageInPinnedRow(NSApp.keyWindow, webContents);
}

static NSInteger DPWebContent_decidePolicy(id self, SEL _cmd, id webContents, id action) {
    if (!DPPeek.on) return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    NSInteger disposition = [DPValueForKey(action, @"navigationDisposition") integerValue];
    NSURL *url = DPValueForKey(action, @"url");
    if (DPPeekWanted(disposition)) {
        if (DPPeekShows(webContents)) return DPCurrentTab;
        if (!DPIsWebURL(url) || !DPPeekCanOpen(webContents)) return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
        DPPeekOpenLater(self, webContents, url);
        return DPIgnoreAction;
    }
    NSInteger policy = DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    if (!DPPeekPinnedLinks.on) return policy;
    BOOL leaves = DPPeekLeavesPinnedRow(webContents, action, disposition, policy);
    if (!leaves && policy == DPForegroundTab) {
        // Ask Dia as if the link stayed in the tab: only an icon-only pinned tab turns that into a new tab.
        leaves = disposition == DPCurrentTab;
        if (disposition == DPForegroundTab && !(NSEvent.modifierFlags & NSEventModifierFlagCommand))
            leaves = DPCallOriginal(DPWebContent_decidePolicy, self, webContents, DPActionStayingInTab(action)) == DPForegroundTab;
    }
    if (!leaves || !DPIsWebURL(url) || !DPPeekCanOpen(webContents)) return policy;
    DPPeekOpenLater(self, webContents, url);
    return DPIgnoreAction;
}

static BOOL DPPeekLookAheadWanted(id page, NSURL *url) {
    NSEventModifierFlags mods = NSEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~NSEventModifierFlagCapsLock;
    return DPPeek.on && mods == NSEventModifierFlagShift && url && page && !DPPeekShows(page) && DPPeekCanOpen(page);
}

// Shift also types capitals, so wait for it to stand alone; the recheck covers Shift released with nothing to cancel it.
static void DPPeekLookAhead(void) {
    id page = DPPeekHoveredPage;
    NSURL *url = DPPeekHovered;
    NSUInteger turn = ++DPPeekLookAheadTurn;
    if (!DPPeekLookAheadWanted(page, url)) return DPPeekCool();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (turn == DPPeekLookAheadTurn && page == DPPeekHoveredPage && [url isEqual:DPPeekHovered] && DPPeekLookAheadWanted(page, url))
            DPPeekWarm(NSApp.keyWindow, page, url);
    });
}

static void DPWebContent_status(id self, SEL _cmd, id webContents, NSString *text) {
    DPCallOriginal(DPWebContent_status, self, webContents, text);
    if (!DPPeek.on) return;
    NSURL *url = text.length ? [NSURL URLWithString:text] : nil;
    if (!url && webContents != DPPeekHoveredPage) return;
    DPPeekHovered = DPIsWebURL(url) ? url : nil;
    DPPeekHoveredPage = webContents;
    DPPeekHoveredDelegate = self;
    DPPeekLookAhead();
}

void DPPeekOpenDragged(NSURL *url, NSPoint origin) {
    if (!DPPeek.on) return;
    id page = DPPeekHoveredPage;
    if (DPPeekShows(page)) return DPPeekLoad(page, url);
    NSWindow *window = NSApp.keyWindow;
    if (DPPeekCanOpen(page)) DPPeekOpen(window, DPActiveTabID(window), url, origin, DPPeekHoveredDelegate, page);
}

static void DPInstallPeek(void) {
    DPSamplesProgressColors = DPPeek.on;
    DPPeekInstallPages();
    DPPeekInstallSelection();
    DPPeekInstallZoom();
    DPPeekInstallCursor();
    DPPeekInstallChat();
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate);
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPWebContent_decidePolicy);
        DPHook(DPDiaWebContent, @selector(webContents:didChangeStatusText:), (IMP)DPWebContent_status);
    });
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged | NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (!DPPeek.on) return event;
        if (event.type == NSEventTypeKeyDown) DPPeekLookAheadTurn++;
        else DPPeekLookAhead();
        return event;
    }];
}

static void DPApplyPeek(DPPatch *patch) {
    DPSamplesProgressColors = patch->on;
    if (!patch->on) DPPeekCloseAll();
}

static NSString *DPVerifyPeek(DPPatch *patch) {
    Class delegate = objc_getClass(DPDiaWebContent);
    if (!DPIsHooked(delegate, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPWebContent_decidePolicy))
        return @"link clicks don't reach Peek";
    if (!DPIsHooked(delegate, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate))
        return @"new windows don't reach Peek";
    if (!patch->on && DPPeekAllCards(nil).count) return @"Peek cards stayed open when turned off";
    if (patch->on) {
        NSCountedSet<NSWindow *> *visibleByWindow = [NSCountedSet set];
        for (DPPeekCard *peek in DPPeekAllCards(nil)) {
            if (peek.closing || peek.isHiddenOrHasHiddenAncestor || !peek.window) continue;
            [visibleByWindow addObject:peek.window];
            if ([visibleByWindow countForObject:peek.window] > 1) return @"multiple Peek cards are visible in one window";
        }
    }
    return DPPeekZoomProblem();
}

DP_PATCH(DPPeek) {
    .key = @"peek",
    .order = 104,
    .title = @"Peek on Shift-Click",
    .detail = @"Deprecated: Dia now includes its own Peek. Shift-click a link to preview it in DiaTweaks’ card over the page, with Escape or ⌘W to close, ⌘O to open as a tab, Genie animation, and drag-to-Peek.",
    .symbol = @"eye.fill",
    .tint = @"systemMintColor",
    .section = @"Links",
    .classes = DPClasses(DPDiaBrowserContext, DPDiaWebContents, DPDiaWebContentsConfiguration, DPDiaContentPane),
    .install = DPInstallPeek,
    .apply = DPApplyPeek,
    .verify = DPVerifyPeek,
    .settings = DPSettingList({DPSettingBool, @"peekToolbar", .defaultBool = YES}, {DPSettingBool, @"peekGenie", .defaultBool = YES},
                              {DPSettingNumber, @"peekDarkness", .defaultNumber = 0.45, .min = 0, .max = 1},
                              {DPSettingNumber, @"peekSpeed", .defaultNumber = 0.9, .min = 0.25, .max = 3}),
    .rows = DPPeekSettingsRows,
    .hint = @"Tip: right after Dia starts, open or switch to any tab once to start Peek.",
};

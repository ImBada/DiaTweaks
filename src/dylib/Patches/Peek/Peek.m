#import "Patches/Peek/Peek.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Patches/LittleDia/LittleDia.h"
#import "Patches/CommandBar/Tabs.h"

static NSURL *DPPeekHovered;
static __weak id DPPeekHoveredPage, DPPeekHoveredDelegate;
static NSUInteger DPPeekLookAheadTurn;
static NSString *DPPeekLink, *DPPeekPressed;
static __weak id DPPeekLinkPage, DPPeekPressedPage;
static NSTimeInterval DPPeekPressedAt;

static NSEventModifierFlags DPPeekModifiers(void) {
    return NSEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask &
           ~(NSEventModifierFlagCapsLock | NSEventModifierFlagNumericPad | NSEventModifierFlagFunction);
}

static BOOL DPPeekWanted(NSInteger disposition) {
    if (!DPPeek.on || DPPeekGiving) return NO;
    BOOL elsewhere = disposition == DPForegroundTab || disposition == DPBackgroundTab || disposition == DPPopup || disposition == DPNewWindow;
    return elsewhere && DPPeekModifiers() == NSEventModifierFlagShift;
}

// Pages clear status text on mouse-down before decidePolicy runs, so fall back to the hovered link at mouse-down.
BOOL DPPeekOverLink(id page, NSURL *url) {
    NSString *key = url ? DPPeekLinkKey(url.absoluteString) : nil;
    if (!page || !key) return NO;
    if (page == DPPeekLinkPage && [key isEqual:DPPeekLink]) return YES;
    return page == DPPeekPressedPage && [key isEqual:DPPeekPressed] && NSProcessInfo.processInfo.systemUptime - DPPeekPressedAt < 2;
}

BOOL DPPeekIsWeb(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return NO;
    NSString *scheme = url.scheme;
    return [scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame;
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
    if (!DPPeekWanted(disposition) || !(DPPeekShows(webContents) || (DPPeekIsWeb(url) && DPPeekCanOpen(webContents))))
        return (void)DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, (NSInteger)DPIgnoreAction);
    if (DPPeekShows(webContents)) return DPPeekLoad(webContents, url);
    DPPeekOpenLater(self, webContents, url);
}

@interface DPStayingAction : NSProxy
@property (nonatomic, strong) id action;
@end

@implementation DPStayingAction
- (NSInteger)navigationDisposition { return DPCurrentTab; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.action methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.action]; }
- (BOOL)respondsToSelector:(SEL)selector { return selector == @selector(navigationDisposition) || [self.action respondsToSelector:selector]; }
- (BOOL)conformsToProtocol:(Protocol *)protocol { return [self.action conformsToProtocol:protocol]; }
- (BOOL)isKindOfClass:(Class)cls { return [self.action isKindOfClass:cls]; }
@end

static BOOL DPPeekLeavesPinnedRow(id webContents, id action, NSInteger disposition, NSInteger policy) {
    BOOL stays = disposition == DPCurrentTab || disposition == DPForegroundTab;
    NSInteger type = [DPValueForKey(action, @"navigationType") integerValue];
    // navigationType: 0 = link activation, 4 = other (how Dia reports target=_blank clicks).
    BOOL clicked = type == 0 || (type == 4 && disposition == DPForegroundTab);
    if (DPPeekModifiers() || !stays || !clicked || (policy != DPCurrentTab && policy != DPForegroundTab)) return NO;
    NSString *from = DPDomainKey([DPValueForKey(webContents, @"url") absoluteString]), *to = DPDomainKey([DPValueForKey(action, @"url") absoluteString]);
    if (!from || !to || [DPRegistrableDomain(from) isEqual:DPRegistrableDomain(to)]) return NO;
    return !DPPeekShows(webContents) && DPPeekInPinnedRow(NSApp.keyWindow, webContents);
}

static NSInteger DPWebContent_decidePolicy(id self, SEL _cmd, id webContents, id action) {
    BOOL little = DPLittleDia.on && DPLittleDiaTabLinks.on;
    if (!DPPeek.on && !little) return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    NSInteger disposition = [DPValueForKey(action, @"navigationDisposition") integerValue];
    if (!DPPeekWanted(disposition)) {
        NSInteger policy = DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
        BOOL peeks = DPPeek.on && DPPeekPinnedLinks.on;
        if (!peeks && !little) return policy;
        NSURL *url = DPValueForKey(action, @"url");
        // Script-opened tabs have no link under the pointer and would lose their opener in Little Dia.
        BOOL clicked = disposition != DPForegroundTab || DPPeekOverLink(webContents, url);
        BOOL leaves = (peeks || (clicked && policy == DPCurrentTab)) && DPPeekLeavesPinnedRow(webContents, action, disposition, policy);
        if (!leaves && policy == DPForegroundTab) {
            // Ask Dia as if the link stayed in the tab: only an icon-only pinned tab turns that into a new tab.
            leaves = disposition == DPCurrentTab;
            if (disposition == DPForegroundTab && !(NSEvent.modifierFlags & NSEventModifierFlagCommand)) {
                DPStayingAction *staying = [DPStayingAction alloc];
                staying.action = action;
                leaves = DPCallOriginal(DPWebContent_decidePolicy, self, webContents, staying) == DPForegroundTab;
            }
        }
        if ((policy == DPForegroundTab || leaves) && clicked && DPLittleDiaTakesTabLink(webContents, url, leaves)) return DPIgnoreAction;
        if (!peeks || !leaves || !DPPeekIsWeb(url) || !DPPeekCanOpen(webContents)) return policy;
        DPPeekOpenLater(self, webContents, url);
        return DPIgnoreAction;
    }
    if (DPPeekShows(webContents)) return DPCurrentTab;
    NSURL *url = DPValueForKey(action, @"url");
    if (!DPPeekIsWeb(url) || !DPPeekCanOpen(webContents)) return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
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
    if (!DPPeek.on && !(DPLittleDia.on && DPLittleDiaTabLinks.on)) return;
    DPPeekLink = text.length ? DPPeekLinkKey(text) : nil;
    DPPeekLinkPage = webContents;
    if (!DPPeek.on) return;
    NSURL *url = text.length ? [NSURL URLWithString:text] : nil;
    if (!url && webContents != DPPeekHoveredPage) return;
    DPPeekHovered = DPPeekIsWeb(url) ? url : nil;
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
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
        if (!DPPeek.on && !(DPLittleDia.on && DPLittleDiaTabLinks.on)) return event;
        DPPeekPressed = DPPeekLink;
        DPPeekPressedPage = DPPeekLinkPage;
        DPPeekPressedAt = event.timestamp;
        return event;
    }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged | NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (!DPPeek.on) return event;
        if (event.type == NSEventTypeKeyDown) DPPeekLookAheadTurn++;
        else DPPeekLookAhead();
        return event;
    }];
}

static void DPApplyPeek(DPPatch *patch) {
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
    .detail = @"Shift-click a link to preview it in a card over the page, like Arc. Click outside, press Escape or ⌘W to close it, ⌘O to open it as a tab, or use the buttons beside it.",
    .symbol = @"eye.fill",
    .tint = @"systemMintColor",
    .section = @"Links",
    .classes = DPClasses(DPDiaBrowserContext, DPDiaWebContents, DPDiaWebContentsConfiguration, DPDiaContentPane),
    .install = DPInstallPeek,
    .apply = DPApplyPeek,
    .verify = DPVerifyPeek,
    .rows = DPPeekSettingsRows,
    .hint = @"Tip: right after Dia starts, open or switch to any tab once to start Peek.",
};

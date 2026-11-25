#import "LittleDia.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

static char DPLittleKey, DPNotLittleKey, DPPageKey, DPChromeKey, DPSourceKey, DPPromotedKey, DPClosedKey, DPOpenedKey, DPProfileKey, DPAwaitedKey;

static NSMutableArray<NSDictionary *> *DPExpected;
static NSMutableArray *DPPendingPages;
static NSPointerArray *DPWindowsAwaitingPage;
static NSMapTable *DPLittleWindowsByPage;

static void DPSetLittlePage(NSWindow *window, id page) {
    DPSet(window, &DPPageKey, page);
    if (!page) return;
    if (!DPLittleWindowsByPage) DPLittleWindowsByPage = [NSMapTable weakToWeakObjectsMapTable];
    [DPLittleWindowsByPage setObject:window forKey:page];
}

static NSString *DPAddressKey(id address) {
    NSString *text = [address isKindOfClass:NSURL.class] ? [address absoluteString] : address;
    NSURLComponents *parts = [text isKindOfClass:NSString.class] ? [NSURLComponents componentsWithString:text] : nil;
    if (!parts.host.length) return nil;
    parts.scheme = parts.scheme.lowercaseString;
    parts.host = parts.host.lowercaseString;
    parts.fragment = nil;
    if (!parts.path.length) parts.path = @"/";
    return parts.string;
}

static NSString *DPPageAddress(id page) { return [page respondsToSelector:@selector(url)] ? DPAddressKey(DPMsg(page, @selector(url))) : nil; }

static NSString *DPHostOf(NSString *key) { return key ? [NSURL URLWithString:key].host : nil; }

// A page has no address until its navigation starts and a request may carry none, so only two addresses that both exist can rule a pair out, by host in case the site redirects.
static BOOL DPCouldBe(NSString *requested, NSString *found) { return !requested || !found || [DPHostOf(requested) isEqualToString:DPHostOf(found)]; }

void DPExpectLittleDiaWindow(NSRect frame, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window)) {
    NSMutableDictionary *link = [@{@"frame" : [NSValue valueWithRect:frame], @"noted" : noted ?: @{}} mutableCopy];
    link[@"key"] = DPAddressKey(noted[@"url"]);
    if (missed) link[@"missed"] = [missed copy];
    if (claimed) link[@"claimed"] = [claimed copy];
    [DPExpected addObject:link];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPLittleDiaWait * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([DPExpected indexOfObjectIdenticalTo:link] == NSNotFound) return;
        [DPExpected removeObjectIdenticalTo:link];
        if (!DPExpected.count) [DPPendingPages removeAllObjects];
        void (^miss)(void) = link[@"missed"];
        if (miss) miss();
    });
}

BOOL DPIsLittleDiaWindow(NSWindow *window) { return window && [DPGet(window, &DPLittleKey) boolValue]; }

id DPLittleDiaPage(NSWindow *window) {
    id page = DPGet(window, &DPPageKey);
    BOOL usable = [page respondsToSelector:@selector(url)] && [page respondsToSelector:@selector(title)]
        && [page respondsToSelector:@selector(canGoBack)] && [page respondsToSelector:@selector(canGoForward)];
    return usable ? page : nil;
}

NSString *DPLittleDiaProfileName(NSWindow *window) { return DPGet(DPGet(window, &DPPageKey), &DPProfileKey); }

static NSString *DPProfileNameOf(id browser) {
    id context = [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
    return [context respondsToSelector:@selector(userVisibleName)] ? DPText(DPMsg(context, @selector(userVisibleName))) : nil;
}

static void DPSetChrome(NSWindow *window, BOOL little) {
    NSView *titlebar = [window standardWindowButton:NSWindowCloseButton].superview.superview;
    NSDictionary *saved = DPGet(window, &DPChromeKey);
    if (little == (saved != nil)) return;
    if (!little) {
        DPSet(window, &DPChromeKey, nil);
        window.styleMask = ([saved[@"mask"] unsignedIntegerValue] & ~NSWindowStyleMaskFullScreen) | (window.styleMask & NSWindowStyleMaskFullScreen);
        window.movableByWindowBackground = [saved[@"movable"] boolValue];
        window.titlebarAppearsTransparent = [saved[@"transparent"] boolValue];
        window.titleVisibility = [saved[@"title"] integerValue];
    } else {
        DPSet(window, &DPChromeKey, @{@"mask" : @(window.styleMask), @"movable" : @(window.movableByWindowBackground),
                                      @"transparent" : @(window.titlebarAppearsTransparent), @"title" : @(window.titleVisibility)});
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        window.movableByWindowBackground = YES;
        window.titlebarAppearsTransparent = YES;
        window.titleVisibility = NSWindowTitleHidden;
    }
    for (NSWindowButton kind = NSWindowCloseButton; kind <= NSWindowZoomButton; kind++) [window standardWindowButton:kind].hidden = little;
    titlebar.hidden = little;
}

// DPClaim makes the window key before Chromium adds its page view, so focus it explicitly.
static void DPFocusPage(NSWindow *window) {
    if (!DPLittleDia.on || !DPIsLittleDiaWindow(window) || DPGet(window, &DPPromotedKey) || !window.isKeyWindow) return;
    if (window.firstResponder && window.firstResponder != window) return;
    NSView *page = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaRenderWidget) && !view.isHiddenOrHasHiddenAncestor; });
    if (page) [window makeFirstResponder:page];
}

// An exact address wins, then a page that could still be the request's; a popup whose page is someone else's is left alone.
static BOOL DPPairRequest(NSUInteger *request, NSUInteger *page) {
    for (BOOL exact = YES;; exact = NO) {
        for (NSUInteger p = 0; p < DPPendingPages.count; p++) {
            NSString *found = DPPageAddress(DPPendingPages[p]);
            for (NSUInteger r = 0; r < DPExpected.count; r++) {
                NSString *requested = DPExpected[r][@"key"];
                if (exact ? (requested && [requested isEqualToString:found]) : DPCouldBe(requested, found)) {
                    *request = r;
                    *page = p;
                    return YES;
                }
            }
        }
        if (!exact) return NO;
    }
}

static void DPClaim(NSWindow *window) {
    if (!window || !DPIsKind(window, DPDiaPopupWindow) || DPGet(window, &DPLittleKey) || DPGet(window, &DPNotLittleKey) || !DPExpected.count) return;
    NSUInteger at = 0, pageAt = NSNotFound;
    if (DPPendingPages.count && !DPPairRequest(&at, &pageAt)) {
        DPSet(window, &DPNotLittleKey, @YES);
        return;
    }
    NSDictionary *link = DPExpected[at], *noted = link[@"noted"];
    [DPExpected removeObjectAtIndex:at];
    DPSet(window, &DPLittleKey, @YES);
    if ([noted[@"source"] intValue]) DPSet(window, &DPSourceKey, noted[@"source"]);
    if (pageAt != NSNotFound) {
        DPSetLittlePage(window, DPPendingPages[pageAt]);
        [DPPendingPages removeObjectAtIndex:pageAt];
    } else {
        DPSet(window, &DPAwaitedKey, link[@"key"]);
        [DPWindowsAwaitingPage addPointer:(__bridge void *)window];
    }
    // Discard unmatched pending pages so later popups don't inherit a non-Little-Dia page.
    if (!DPExpected.count) [DPPendingPages removeAllObjects];
    NSRect frame = [link[@"frame"] rectValue];
    DPSet(window, &DPOpenedKey, link[@"frame"]);
    [window setFrame:frame display:YES];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    DPRestoreStack(window, noted);
    // Chromium re-sizes and re-focuses ~300 ms later; reassert frame, stack order, and page focus.
    __weak NSWindow *weakWindow = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSWindow *w = weakWindow;
        if (!DPLittleDia.on || !w || w.miniaturized || DPGet(w, &DPPromotedKey) || DPGet(w, &DPClosedKey)) return;
        [w setFrame:frame display:YES];
        DPRestoreStack(w, noted);
        DPFocusPage(w);
    });
    DPRefreshLittleDiaWindows();
    DPFocusPage(window);
    if (link[@"claimed"]) ((void (^)(NSWindow *))link[@"claimed"])(window);
}

static void DPBrowser_didCreate(id self, SEL _cmd, id browser, id page, BOOL active) {
    DPCallOriginal(DPBrowser_didCreate, self, browser, page, active);
    if (!DPLittleDia.on || !page || (!DPExpected.count && !DPWindowsAwaitingPage.count)) return;
    long (*type)(id, SEL) = (void *)objc_msgSend;
    if (![browser respondsToSelector:@selector(type)] || type(browser, @selector(type)) != 2) return;
    DPSet(page, &DPProfileKey, DPProfileNameOf(browser));
    [DPWindowsAwaitingPage compact];
    NSString *found = DPPageAddress(page);
    for (NSUInteger i = 0; i < DPWindowsAwaitingPage.count; i++) {
        NSWindow *window = (__bridge NSWindow *)[DPWindowsAwaitingPage pointerAtIndex:i];
        if (!DPCouldBe(DPGet(window, &DPAwaitedKey), found)) continue;
        [DPWindowsAwaitingPage removePointerAtIndex:i];
        DPSetLittlePage(window, page);
        return DPRefreshLittleDiaWindows();
    }
    if (DPExpected.count) [DPPendingPages addObject:page];
}

static void DPPopupBar_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPopupBar_viewDidMoveToWindow, self);
    if (!self.window) return;
    if (DPLittleDia.on && DPExpected.count) DPClaim(self.window);
    else if (!DPGet(self.window, &DPLittleKey)) DPSet(self.window, &DPNotLittleKey, @YES);
}

static void DPPage_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPage_viewDidMoveToWindow, self);
    NSWindow *window = self.window;
    if (!DPLittleDia.on || !DPIsLittleDiaWindow(window)) return;
    __weak NSWindow *weakWindow = window;
    dispatch_async(dispatch_get_main_queue(), ^{ DPFocusPage(weakWindow); });
}

// Only plain new-tab links stay; sized popups keep their opener for sign-in flows.
static BOOL DPStaysInLittleDia(id page, NSInteger disposition) {
    if (!page || disposition != DPForegroundTab || (NSEvent.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift))) return NO;
    NSWindow *window = [DPLittleWindowsByPage objectForKey:page];
    return DPIsLittleDiaWindow(window) && DPLittleDiaPage(window) == page;
}

@interface DPStayingLink : NSProxy
@property (nonatomic, strong) id action;
@end

@implementation DPStayingLink
- (NSInteger)navigationDisposition { return DPCurrentTab; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.action methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.action]; }
- (BOOL)respondsToSelector:(SEL)selector { return selector == @selector(navigationDisposition) || [self.action respondsToSelector:selector]; }
- (BOOL)conformsToProtocol:(Protocol *)protocol { return [self.action conformsToProtocol:protocol]; }
- (BOOL)isKindOfClass:(Class)cls { return [self.action isKindOfClass:cls]; }
@end

static NSInteger DPPage_decidePolicy(id self, SEL _cmd, id page, id action) {
    if (!DPLittleDia.on || !DPStaysInLittleDia(page, [DPValueForKey(action, @"navigationDisposition") integerValue]))
        return DPCallOriginal(DPPage_decidePolicy, self, page, action);
    DPStayingLink *staying = [DPStayingLink alloc];
    staying.action = action;
    return DPCallOriginal(DPPage_decidePolicy, self, page, staying);
}

void DPPromoteLittleDiaWindow(NSWindow *window) { DPSet(window, &DPPromotedKey, @YES); }

static void DPShowMainWindow(void) {
    for (NSWindow *window in NSApp.orderedWindows)
        if (DPIsKind(window, DPDiaWindow) && window.visible && !window.miniaturized && window.level == NSNormalWindowLevel && window.alphaValue > 0.01) {
            [NSApp activateIgnoringOtherApps:YES];
            [window makeKeyAndOrderFront:nil];
            return;
        }
}

void DPRefreshLittleDiaWindows(void) {
    for (NSWindow *window in NSApp.windows)
        if (DPIsLittleDiaWindow(window)) DPSetChrome(window, DPLittleDia.on);
    DPRelayoutLittleDiaBars();
}

static void DPRememberFrame(NSWindow *window) {
    NSValue *opened = DPGet(window, &DPOpenedKey);
    if (!opened || NSEqualRects(window.frame, opened.rectValue) || (window.styleMask & NSWindowStyleMaskFullScreen)) return;
    DPSaveLittleDiaFrame(window.frame);
}

static void DPWindowWillClose(NSWindow *window) {
    if (!DPIsLittleDiaWindow(window)) return;
    DPSet(window, &DPClosedKey, @YES);
    if (!DPLittleDia.on) return;
    if (DPLittleDiaRemember.on) DPRememberFrame(window);
    pid_t source = [DPGet(window, &DPSourceKey) intValue];
    BOOL key = window.isKeyWindow, promoted = [DPGet(window, &DPPromotedKey) boolValue];
    NSArray<NSDictionary *> *stack = DPWindowStack();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (promoted) {
            DPBringBackPutAway(nil);
            DPShowMainWindow();
        } else if (!DPHideAgain() && key && source) DPReturnToSource(source, window, stack);
    });
}

void DPInstallLittleDiaWindows(void) {
    DPExpected = [NSMutableArray array];
    DPPendingPages = [NSMutableArray array];
    DPWindowsAwaitingPage = [NSPointerArray weakObjectsPointerArray];
    DPHook(DPDiaPopupBar, @selector(viewDidMoveToWindow), (IMP)DPPopupBar_viewDidMoveToWindow);
    DPHook(DPDiaRenderWidget, @selector(viewDidMoveToWindow), (IMP)DPPage_viewDidMoveToWindow);
    DPHook(DPDiaBrowserDelegate, @selector(browser:didCreateNewWebContents:isActive:), (IMP)DPBrowser_didCreate);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPPage_decidePolicy);
    });
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!DPLittleDia.on) return;
        if (DPExpected.count) DPClaim(note.object);
        else if (DPIsKind(note.object, DPDiaPopupWindow) && !DPGet(note.object, &DPLittleKey)) DPSet(note.object, &DPNotLittleKey, @YES);
        DPFocusPage(note.object);
    }];
    [center addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPWindowWillClose(note.object); }];
    DPInstallLittleDiaBar();
    DPInstallLittleDiaStack();
}

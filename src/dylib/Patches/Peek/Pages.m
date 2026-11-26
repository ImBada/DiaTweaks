#import "Patches/Peek/Peek.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Patches/CommandBar/Tabs.h"
#import <objc/message.h>

@interface DPPeekWarmSlot : NSObject
@property (nonatomic, strong) id page;
@property (nonatomic, strong) NSView *view;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, weak) id source;
@property (nonatomic) NSUInteger stamp;
@end

@implementation DPPeekWarmSlot
@end

static NSMapTable *DPPeekFactories;
static __weak id DPPeekLastFactory;
static NSMapTable<NSWindow *, DPPeekWarmSlot *> *DPPeekWarmSlots;
static char DPPeekWindowClosedKey;
NSTimeInterval DPPeekWarmIdle = 25;

static void DPPeekSend(id object, SEL sel) {
    if ([object respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(object, sel);
}

static void DPPeekMarkNonTab(id page, BOOL nonTab) {
    if (page) objc_setAssociatedObject(page, NSSelectorFromString(@"dp_nonTabWebContents"), nonTab ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DPPeekRemember(id factory, id page) {
    if (!page) return;
    [DPPeekFactories setObject:factory forKey:page];
    DPPeekLastFactory = factory;
}

static id DPContext_create(id self, SEL _cmd, id configuration) {
    id page = DPCallOriginal(DPContext_create, self, configuration);
    DPPeekRemember(self, page);
    return page;
}

static id DPBrowser_create(id self, SEL _cmd, id configuration) {
    id page = DPCallOriginal(DPBrowser_create, self, configuration);
    DPPeekRemember(self, page);
    return page;
}

static void DPPage_attach(id self, SEL _cmd, NSView *host) {
    DPPeekCard *peek = DPPeekCardForPage(self);
    BOOL ownHost = peek && host == peek.host;
    if (peek && !ownHost) [peek handOverTo:host attach:^{ DPCallOriginal(DPPage_attach, self, host); }];
    else DPCallOriginal(DPPage_attach, self, host);
    if (!ownHost && DPPeek.on && host.window && DPPeekHasCards()) DPPeekSyncTabs(host.window);
}

// Restored tabs' pages skip the hooked createWebContents, so they fall back to the window's browser for the profile in front.
static id DPPeekFactoryFor(id source, NSWindow *window) {
    if (!source) return nil;
    return [DPPeekFactories objectForKey:source] ?: DPBrowserOfWindow(window) ?: DPPeekLastFactory;
}

BOOL DPPeekCanOpen(id source) { return DPPeekFactoryFor(source, NSApp.keyWindow) != nil; }

BOOL DPPeekShows(id page) {
    DPPeekCard *peek = DPPeekCardForPage(page);
    return peek && !peek.closing;
}

void DPPeekLoad(id page, NSURL *url) {
    id navigation = DPValueForKey(page, @"navigationController");
    SEL load = @selector(load:initiatorOrigin:);
    if (url && [navigation respondsToSelector:load]) ((id (*)(id, SEL, NSURL *, NSURL *))objc_msgSend)(navigation, load, url, nil);
}

NSURL *DPPeekSearchURL(id page, NSString *text) {
    id factory = DPPeekFactoryFor(page, NSApp.keyWindow);
    id context = [factory respondsToSelector:@selector(preferences)] ? factory : DPValueForKey(factory, @"context");
    id preferences = DPValueForKey(context, @"preferences");
    id engine = [preferences respondsToSelector:@selector(getDefaultSearchEngine)] ? ((id (*)(id, SEL))objc_msgSend)(preferences, @selector(getDefaultSearchEngine)) : nil;
    NSString *query = [text stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    query = [query stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    query = [query stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    NSString *template = DPValueForKey(engine, @"url");
    if (![template isKindOfClass:NSString.class] || ![template containsString:@"{searchTerms}"] || [template containsString:@"{google:"])
        template = @"https://www.google.com/search?q={searchTerms}";
    template = [template stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:query];
    static NSRegularExpression *rest;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ rest = [NSRegularExpression regularExpressionWithPattern:@"\\{[^}]*\\}" options:0 error:nil]; });
    return [NSURL URLWithString:[rest stringByReplacingMatchesInString:template options:0 range:NSMakeRange(0, template.length) withTemplate:@""]];
}

BOOL DPPeekGiving;
BOOL DPPeekFindingLink;

static BOOL DPPeekGive(id page, id delegate, id source, NSURL *url, DPPeekExit exit) {
    SEL adopt = @selector(webContents:didCreateNewWebContent:targetURL:disposition:);
    if (!page || !source || ![url isKindOfClass:NSURL.class] || ![delegate respondsToSelector:adopt]) return NO;
    NSInteger disposition = exit == DPPeekSplit ? DPSplitView : DPForegroundTab;
    DPPeekMarkNonTab(page, NO);
    DPPeekGiving = YES;
    ((void (*)(id, SEL, id, id, NSURL *, NSInteger))objc_msgSend)(delegate, adopt, source, page, url, disposition);
    DPPeekGiving = NO;
    return YES;
}

static void DPPeekDetach(id page, NSView *host) {
    if (!host) return;
    [page detachFromPaneHostView:host];
    [host removeFromSuperview];
}

__attribute__((weak)) NSTimeInterval DPPeekBlankPollDelay(void) { return 0.05; }
__attribute__((weak)) NSTimeInterval DPPeekFindLinkDelay(void) { return 0.15; }

// Some extensions crash Dia when a page closes while still showing a site, so it goes blank first.
static void DPPeekCloseWhenBlank(id page, int checks) {
    if (!page) return;
    id rawURL = DPValueForKey(page, @"url");
    NSString *urlString = [rawURL isKindOfClass:NSURL.class] ? [rawURL absoluteString] : nil;
    if (checks && ![urlString isEqual:@"about:blank"])
        return (void)dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPPeekBlankPollDelay() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DPPeekCloseWhenBlank(page, checks - 1); });
    DPPeekSend(page, @selector(close));
}

static void DPPeekDiscard(id page, NSView *host) {
    if (!page) return;
    DPPeekDetach(page, host);
    DPPeekLoad(page, [NSURL URLWithString:@"about:blank"]);
    DPPeekCloseWhenBlank(page, 40);
}

static void DPPeekFindLink(NSWindow *window, id source, NSPoint origin, NSView *warmHost, void (^found)(NSRect link)) {
    NSRect fallback = NSMakeRect(origin.x - 40, origin.y - 10, 80, 20);
    NSPoint inWindow = [window convertPointFromScreen:origin];
    NSView *web = DPFindView(window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, "WebContentsHostView") && !view.isHiddenOrHasHiddenAncestor && ![view isDescendantOf:warmHost]
            && NSPointInRect([view convertPoint:inWindow fromView:nil], view.bounds);
    });
    if (!web || ![source respondsToSelector:@selector(executeJavascript:completion:)]) return found(fallback);
    NSPoint point = [web convertPoint:inWindow fromView:nil];
    NSString *script = [NSString stringWithFormat:@"(function(x, y, w) {"
        "var k = innerWidth / w, e = document.elementFromPoint(x * k, y * k); if (!e) return '';"
        "var a = e.closest('a') || e, r = a.getBoundingClientRect();"
        "for (var b of a.getClientRects()) if (x * k >= b.left && x * k <= b.right && y * k >= b.top && y * k <= b.bottom) r = b;"
        "return [r.left / k - x, r.top / k - y, r.width / k, r.height / k].join(',');"
        "})(%f, %f, %f)", point.x, web.isFlipped ? point.y : NSHeight(web.bounds) - point.y, NSWidth(web.bounds)];
    __block BOOL done = NO;
    void (^finish)(NSRect) = ^(NSRect link) {
        if (done) return;
        done = YES;
        found(link);
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPPeekFindLinkDelay() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ finish(fallback); });
    void (^answer)(NSString *, BOOL) = ^(NSString *result, BOOL ok) {
        NSString *box = [result stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        NSArray<NSString *> *parts = [box componentsSeparatedByString:@","];
        NSRect link = fallback;
        if (ok && parts.count == 4 && parts[2].doubleValue >= 1 && parts[3].doubleValue >= 1) {
            CGFloat dx = parts[0].doubleValue, dy = parts[1].doubleValue, w = parts[2].doubleValue, h = parts[3].doubleValue;
            link = NSMakeRect(origin.x + dx, origin.y - dy - h, w, h);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ finish(link); });
    };
    DPPeekFindingLink = YES;
    ((void (*)(id, SEL, NSString *, id))objc_msgSend)(source, @selector(executeJavascript:completion:), script, answer);
    DPPeekFindingLink = NO;
}

static id DPPeekMakePage(NSWindow *window, id source, void (^attach)(id page)) {
    id factory = DPPeekFactoryFor(source, window);
    Class configuration = objc_getClass(DPDiaWebContentsConfiguration);
    if (!window || !factory || !configuration) return nil;
    id page = ((id (*)(id, SEL, id))objc_msgSend)(factory, @selector(createWebContents:), [configuration new]);
    if (!page) return nil;
    DPPeekMarkNonTab(page, YES);
    DPPeekSend(page, @selector(bootstrapRendering));
    attach(page);
    DPPeekSend(page, @selector(bootstrapRenderingComplete));
    return page;
}

// A warmed page holds a hidden renderer, and Chromium only reports a link once, so leaving it unopened must not keep it alive.
static void DPPeekArmCool(NSWindow *window, DPPeekWarmSlot *slot) {
    NSUInteger stamp = ++slot.stamp;
    __weak NSWindow *weakWindow = window;
    __weak DPPeekWarmSlot *weakSlot = slot;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPPeekWarmIdle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSWindow *owner = weakWindow;
        DPPeekWarmSlot *held = weakSlot;
        if (owner && held && held.stamp == stamp && [DPPeekWarmSlots objectForKey:owner] == held) DPPeekCoolIn(owner);
    });
}

void DPPeekWarm(NSWindow *window, id source, NSURL *url) {
    if (!window || [DPGet(window, &DPPeekWindowClosedKey) boolValue]) return;
    if (DPPeekHasCards()) DPPeekSyncTabs(window);
    DPPeekWarmSlot *warm = [DPPeekWarmSlots objectForKey:window];
    if ([url isEqual:warm.url]) return DPPeekArmCool(window, warm);
    if (DPPeekCardIn(window)) return;
    DPPeekCoolIn(window);
    __block NSView *host = nil;
    id page = DPPeekMakePage(window, source, ^(id page) { host = DPPeekWarmHost(window, page); });
    if (!page) return;
    if (!host) return DPPeekDiscard(page, nil);
    DPPeekLoad(page, url);
    DPPeekWarmSlot *slot = [DPPeekWarmSlot new];
    slot.page = page;
    slot.view = host;
    slot.url = url;
    slot.source = source;
    if (!DPPeekWarmSlots) DPPeekWarmSlots = [NSMapTable weakToStrongObjectsMapTable];
    [DPPeekWarmSlots setObject:slot forKey:window];
    DPPeekArmCool(window, slot);
}

static DPPeekWarmSlot *DPPeekTakeWarm(NSWindow *window) {
    DPPeekWarmSlot *slot = window ? [DPPeekWarmSlots objectForKey:window] : nil;
    if (slot) [DPPeekWarmSlots removeObjectForKey:window];
    return slot;
}

void DPPeekCoolIn(NSWindow *window) {
    DPPeekWarmSlot *slot = DPPeekTakeWarm(window);
    if (slot) DPPeekDiscard(slot.page, slot.view);
}

void DPPeekCool(void) {
    for (NSWindow *window in DPPeekWarmSlots.keyEnumerator.allObjects) DPPeekCoolIn(window);
}

void DPPeekCoolForSource(id source) {
    if (!source) return;
    for (NSWindow *window in DPPeekWarmSlots.keyEnumerator.allObjects)
        if ([DPPeekWarmSlots objectForKey:window].source == source) DPPeekCoolIn(window);
}

BOOL DPPeekHasWarm(void) { return DPPeekWarmSlots.count > 0; }

static void DPPeekOpenFrom(NSWindow *window, NSString *originTabID, NSURL *url, NSRect link, id delegate, id source, id warmPage, NSView *warmHost) {
    if (DPPeekHasCards()) DPPeekSyncTabs(window);
    BOOL closed = !window || [DPGet(window, &DPPeekWindowClosedKey) boolValue];
    BOOL wrongTab = originTabID && !closed && ![originTabID isEqual:DPActiveTabID(window)];
    if (!DPPeek.on || closed || !url || wrongTab || DPPeekCardIn(window) || DPPeekCardForOrigin(window, originTabID, source)) {
        if (warmPage) DPPeekDiscard(warmPage, warmHost);
        return;
    }
    __block DPPeekCard *peek = nil;
    id page = warmPage ?: DPPeekMakePage(window, source, ^(id page) { peek = DPPeekShowCard(window, page, nil, link); });
    if (!page) return;
    if (warmPage) peek = DPPeekShowCard(window, page, warmHost, link);
    else DPPeekLoad(page, url);
    if (!peek) {
        DPPeekDetach(page, warmHost);
        if (!DPPeekGive(page, delegate, source, url, DPPeekTab)) DPPeekDiscard(page, nil);
        return;
    }
    peek.originTabID = originTabID;
    peek.sourceDelegate = delegate;
    peek.source = source;
    peek.requestedURL = url;
    DPPeekChatAttach(peek);
    DPPeekShowTabBadge(peek, source);
}

void DPPeekOpen(NSWindow *window, NSString *originTabID, NSURL *url, NSPoint origin, id delegate, id source) {
    // Taken now, before releasing Shift can cool it.
    DPPeekWarmSlot *slot = DPPeekTakeWarm(window);
    BOOL warm = slot && [url isEqual:slot.url] && slot.view.window == window;
    id warmPage = warm ? slot.page : nil;
    NSView *warmHost = warm ? slot.view : nil;
    if (slot && !warm) DPPeekDiscard(slot.page, slot.view);
    DPPeekFindLink(window, source, origin, warmHost, ^(NSRect link) { DPPeekOpenFrom(window, originTabID, url, link, delegate, source, warmPage, warmHost); });
}

void DPPeekCloseAll(void) {
    DPPeekCool();
    DPPeekHideDragZone();
    DPPeekCancelHandoffs();
    for (DPPeekCard *peek in DPPeekAllCards(nil)) {
        id page = peek.page;
        [peek handOverTo:nil attach:nil];
        DPPeekDiscard(page, nil);
    }
    DPPeekUpdateSyncTimer();
}

static NSURL *DPPeekLiveURL(NSObject *page) {
    NSURL *url = DPValueForKey(page, @"url");
    return [url isKindOfClass:NSURL.class] && url.scheme.length && ![url.absoluteString isEqualToString:@"about:blank"] ? url : nil;
}

@implementation DPPeekCard (Handoff)

- (void)finishExit:(DPPeekExit)exit {
    NSObject *page = (NSObject *)self.page;
    if (!page) {
        [self handOverTo:nil attach:nil];
        return;
    }
    if (!self.window) {
        [self handOverTo:nil attach:nil];
        return DPPeekDiscard(page, nil);
    }
    if (exit != DPPeekClose || !self.hidden) [self.window makeKeyWindow];
    NSURL *url = nil;
    // A preview still loading has no URL yet, so the tab opens the link that was clicked.
    if (exit == DPPeekTab) url = DPPeekLiveURL(page) ?: self.requestedURL;
    else if (exit != DPPeekClose) url = DPValueForKey(page, @"url");
    if (exit != DPPeekClose && DPPeekGive(page, self.sourceDelegate, self.source, url, exit)) {
        // DPPage_attach takes the card down once Dia shows the page.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (self.superview) [self handOverTo:nil attach:nil]; });
        return;
    }
    [self handOverTo:nil attach:nil];
    DPPeekDiscard(page, nil);
}

- (void)finish:(DPPeekExit)exit {
    if (exit == DPPeekTab) DPPeekPrepareHandoff(self, ^{ [self finishExit:exit]; });
    else [self finishExit:exit];
}

@end

void DPPeekInstallPages(void) {
    DPPeekFactories = [NSMapTable weakToWeakObjectsMapTable];
    DPHook(DPDiaBrowserContext, @selector(createWebContents:), (IMP)DPContext_create);
    DPHook(DPDiaBrowser, @selector(createWebContents:), (IMP)DPBrowser_create);
    DPHook(DPDiaWebContents, @selector(attachToPaneHostView:), (IMP)DPPage_attach);
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (note.object) DPSet(note.object, &DPPeekWindowClosedKey, @YES);
        DPPeekCoolIn(note.object);
        DPPeekHandoffSelectionChanged(note.object, nil);
        for (DPPeekCard *peek in DPPeekAllCards(note.object)) {
            id page = peek.page;
            DPPeekChatDetachQuiet(peek);
            [peek handOverTo:nil attach:nil];
            DPPeekDiscard(page, nil);
        }
        DPPeekUpdateSyncTimer();
    }];
}

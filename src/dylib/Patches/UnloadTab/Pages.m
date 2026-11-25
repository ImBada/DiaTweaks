#import "Patches/UnloadTab/Pages.h"
#import "Patches/CommandBar/Tabs.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

@interface NSObject (DPUnloadPrivate)
- (NSArray *)appleScriptWindows;
- (NSArray *)appleScriptProfiles;
- (NSArray *)appleScriptTabs;
- (id)URL;
- (NSURL *)url;
- (NSView *)nativeView;
- (NSInteger)visibility;
- (void)discard;
- (void)webContents:(id)contents finalizeDiscardRequest:(BOOL)discarded;
- (void)webContents:(id)contents didCloseWithSessionID:(id)sessionID;
@end

enum { DPPageVisible = 2 };

static NSHashTable *DPPages, *DPDiscarded, *DPUnloadOnHide;
static NSMapTable<NSWindow *, NSMapTable<NSString *, id> *> *DPPanePages;
static NSMapTable<id, NSString *> *DPPagePaneID;

static void DPForgetPage(id page);

static Class DPPeekCardClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"DPPeekCard"); });
    return cls;
}

static BOOL DPIsNonTabContainer(NSView *view) {
    Class peekCard = DPPeekCardClass();
    if (peekCard && [view isKindOfClass:peekCard]) return YES;
    if (DPIsKind(view, DPDiaAssistantPanel) || DPIsKind(view, DPDiaPopover)) return YES;
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"ExtensionSidePanel"] || [name containsString:@"AssistantPanel"];
}

static BOOL DPIsNonTabPage(id page) {
    if (!page) return YES;
    if ([objc_getAssociatedObject(page, NSSelectorFromString(@"dp_nonTabWebContents")) boolValue]) return YES;
    if (![page respondsToSelector:@selector(nativeView)]) return NO;
    NSView *view = ((NSView *(*)(id, SEL))objc_msgSend)(page, @selector(nativeView));
    if (![view isKindOfClass:NSView.class]) return NO;
    BOOL sawPane = NO;
    for (NSView *up = view; up; up = up.superview) {
        if (DPIsNonTabContainer(up)) return YES;
        if (DPIsKind(up, DPDiaContentPane)) { sawPane = YES; break; }
    }
    return view.window != nil && !sawPane;
}

static BOOL DPRecordPagePane(id page) {
    if (!page || ![page respondsToSelector:@selector(nativeView)]) return NO;
    if (DPIsNonTabPage(page)) {
        DPForgetPage(page);
        return NO;
    }
    NSView *view = ((NSView *(*)(id, SEL))objc_msgSend)(page, @selector(nativeView));
    if (![view isKindOfClass:NSView.class] || !view.window) return NO;
    NSView *pane = nil;
    for (NSView *up = view; up; up = up.superview) {
        if (DPIsNonTabContainer(up)) {
            DPForgetPage(page);
            return NO;
        }
        if (DPIsKind(up, DPDiaContentPane)) { pane = up; break; }
    }
    NSString *paneID = pane ? DPUUIDsIn([DPSwiftValue(pane, @"contentPaneID") description]).firstObject : nil;
    if (!paneID) return NO;
    NSMapTable<NSString *, id> *byPane = [DPPanePages objectForKey:view.window];
    if (!byPane) [DPPanePages setObject:(byPane = [NSMapTable strongToWeakObjectsMapTable]) forKey:view.window];
    [byPane setObject:page forKey:paneID];
    [DPPagePaneID setObject:paneID forKey:page];
    return YES;
}

void DPRecordVisiblePanePages(void) {
    for (id page in DPPages.allObjects) DPRecordPagePane(page);
}

static void DPForgetPage(id page) {
    if (!page) return;
    [DPPages removeObject:page];
    [DPDiscarded removeObject:page];
    [DPUnloadOnHide removeObject:page];
    NSString *paneID = [DPPagePaneID objectForKey:page];
    [DPPagePaneID removeObjectForKey:page];
    if (!paneID) return;
    for (NSWindow *window in DPPanePages.keyEnumerator.allObjects) {
        NSMapTable<NSString *, id> *byPane = [DPPanePages objectForKey:window];
        if ([byPane objectForKey:paneID] == page) [byPane removeObjectForKey:paneID];
    }
}

id DPPageForPane(NSWindow *window, NSString *contentID) {
    if (!contentID) return nil;
    id local = window ? [[DPPanePages objectForKey:window] objectForKey:contentID] : nil;
    if (local && [DPPages containsObject:local]) return local;
    id found = nil;
    for (NSWindow *other in DPPanePages.keyEnumerator.allObjects) {
        id candidate = [[DPPanePages objectForKey:other] objectForKey:contentID];
        if (!candidate || ![DPPages containsObject:candidate] || candidate == found) continue;
        if (found) return nil;
        found = candidate;
    }
    return found;
}

static NSURL *DPTabURLOf(id tab) {
    NSString *text = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
    return text.length ? [NSURL URLWithString:text] : nil;
}

static void DPEachScriptTab(void (^visit)(id tab)) {
    id windows = DPValueForKey(NSApp.delegate, @"appleScriptWindows");
    if (![windows isKindOfClass:NSArray.class]) return;
    for (id window in windows) {
        id rawProfiles = DPValueForKey(window, @"appleScriptProfiles");
        NSArray *profiles = [rawProfiles isKindOfClass:NSArray.class] ? rawProfiles : nil;
        for (id owner in profiles.count ? profiles : @[window]) {
            id tabs = DPValueForKey(owner, @"appleScriptTabs");
            if ([tabs isKindOfClass:NSArray.class]) for (id tab in tabs) visit(tab);
        }
    }
}

NSURL *DPScriptTabURL(NSWindow *window, NSString *tabID) {
    if (!tabID) return nil;
    id sw = DPScriptWindow(window);
    id tab = DPScriptTabIn(sw, tabID) ?: DPScriptTabInAnyProfile(sw, tabID);
    if (tab) return DPTabURLOf(tab);
    __block NSURL *found = nil;
    DPEachScriptTab(^(id candidate) { if (!found && [DPTabID(candidate) isEqual:tabID]) found = DPTabURLOf(candidate); });
    return found;
}

NSCountedSet<NSURL *> *DPScriptTabURLCounts(void) {
    NSCountedSet<NSURL *> *counts = [NSCountedSet set];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    DPEachScriptTab(^(id tab) {
        NSString *tid = DPTabID(tab);
        if (tid && [seen containsObject:tid]) return;
        if (tid) [seen addObject:tid];
        NSURL *url = DPTabURLOf(tab);
        if (url) [counts addObject:url];
    });
    return counts;
}

static BOOL DPIsAuxiliaryPage(id page) {
    if (!page || ![page respondsToSelector:@selector(nativeView)]) return NO;
    NSView *view = ((NSView *(*)(id, SEL))objc_msgSend)(page, @selector(nativeView));
    if (![view isKindOfClass:NSView.class]) return NO;
    if (DPIsKind(view.window, "_TtC5Popup19PlatformPopupWindow")) return YES;
    Class card = DPPeekCardClass();
    if (!card) return NO;
    for (NSView *up = view; up; up = up.superview)
        if ([up isKindOfClass:card]) return YES;
    return NO;
}

static id DPPageAt(NSURL *url, NSString *contentID) {
    id found = nil;
    for (id page in DPPages.allObjects) {
        if (DPIsNonTabPage(page)) {
            DPForgetPage(page);
            continue;
        }
        if (![DPValueForKey(page, @"url") isEqual:url]) continue;
        if (DPIsAuxiliaryPage(page)) continue;
        NSString *owner = [DPPagePaneID objectForKey:page];
        if (contentID && owner && ![owner isEqualToString:contentID]) continue;
        if (found) return nil;
        found = page;
    }
    return found;
}

// A tab with no page of its own would be taken for another tab's page at the same address.
id DPPageByURL(NSString *tabID, NSString *contentID, NSURL *url) {
    if (!url || !tabID) return nil;
    NSMutableSet<NSString *> *sharing = [NSMutableSet set];
    DPEachScriptTab(^(id tab) {
        if (![DPTabURLOf(tab) isEqual:url]) return;
        NSString *tid = DPTabID(tab);
        if (tid) [sharing addObject:tid];
    });
    return sharing.count == 1 && [sharing containsObject:tabID] ? DPPageAt(url, contentID) : nil;
}

BOOL DPPageIsDiscarded(id page) { return page && [DPDiscarded containsObject:page]; }

BOOL DPPageIsVisible(id page) {
    return page && [page respondsToSelector:@selector(visibility)]
        && ((NSInteger (*)(id, SEL))objc_msgSend)(page, @selector(visibility)) == DPPageVisible;
}

BOOL DPPageIsTracked(id page) { return page && [DPPages containsObject:page] && !DPIsNonTabPage(page); }

void DPUnloadPage(id page, id before) {
    if (!page || ![DPPages containsObject:page] || DPPageIsDiscarded(page)) return;
    if (!before) {
        if (!DPPageIsVisible(page) && [page respondsToSelector:@selector(discard)]) [page performSelector:@selector(discard)];
        return;
    }
    [DPUnloadOnHide addObject:page];
    DPFocusTab(before);
    __weak id weakPage = page;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        id shown = weakPage;
        if (shown) [DPUnloadOnHide removeObject:shown];
    });
}

static void DPPage_setVisibility(id self, SEL _cmd, NSInteger visibility) {
    if ([self respondsToSelector:@selector(visibility)] && [self respondsToSelector:@selector(discard)]) {
        if (DPIsNonTabPage(self)) DPForgetPage(self);
        else {
            [DPPages addObject:self];
            DPRecordPagePane(self);
        }
    }
    DPCallOriginal(DPPage_setVisibility, self, visibility);
    if (![DPPages containsObject:self]) return;
    if (DPIsNonTabPage(self)) return DPForgetPage(self);
    BOOL recorded = DPRecordPagePane(self);
    if (![DPPages containsObject:self]) return;
    if (visibility == DPPageVisible) {
        [DPDiscarded removeObject:self];
        if (!recorded && DPUnloadTab.on) {
            __weak id weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf) DPRecordPagePane(weakSelf); });
        }
    } else if ([DPUnloadOnHide containsObject:self]) {
        [DPUnloadOnHide removeObject:self];
        if (DPUnloadTab.on) {
            __weak id weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                id page = weakSelf;
                if (DPUnloadTab.on && page && [DPPages containsObject:page] && !DPPageIsVisible(page) && !DPPageIsDiscarded(page))
                    [page performSelector:@selector(discard)];
            });
        }
    }
}

// Discard can be declined (e.g. playing audio), so only the finalize callback marks it unloaded.
static void DPWebContent_finalizeDiscard(id self, SEL _cmd, id page, BOOL discarded) {
    DPCallOriginal(DPWebContent_finalizeDiscard, self, page, discarded);
    if (discarded && page) [DPDiscarded addObject:page];
}

static void DPWebContent_didClose(id self, SEL _cmd, id page, id sessionID) {
    __attribute__((objc_precise_lifetime)) id closing = page;
    DPCallOriginal(DPWebContent_didClose, self, closing, sessionID);
    DPForgetPage(closing);
}

void DPInstallUnloadPages(void) {
    DPPages = [NSHashTable weakObjectsHashTable];
    DPDiscarded = [NSHashTable weakObjectsHashTable];
    DPUnloadOnHide = [NSHashTable weakObjectsHashTable];
    DPPanePages = [NSMapTable weakToStrongObjectsMapTable];
    DPPagePaneID = [NSMapTable weakToStrongObjectsMapTable];
    DPHook(DPDiaWebContents, @selector(setVisibility:), (IMP)DPPage_setVisibility);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:finalizeDiscardRequest:), (IMP)DPWebContent_finalizeDiscard);
        DPHook(DPDiaWebContent, @selector(webContents:didCloseWithSessionID:), (IMP)DPWebContent_didClose);
    });
}

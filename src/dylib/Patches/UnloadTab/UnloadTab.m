#import "StdPatch/StdPatch.h"
#import <objc/message.h>

extern DPPatch DPUnloadTab;

enum { DPPageVisible = 2 };  // content::Visibility: hidden, occluded, visible.

static NSHashTable *DPPages;
static NSHashTable *DPDiscarded;  // Pages Chromium says it unloaded, until they're shown again.

// The tab's one page, as Dia's tab controller knows it. A split tab has more than one, and isn't offered.
static id DPTabContent(NSView *tab) {
    NSDictionary *views = DPSwiftValue(tab, @"contentViews");
    if (views.count != 1) return nil;
    return DPSwiftValue(DPSwiftValue(views.allValues.firstObject, @"viewModel"), @"delegate");
}

// Dia's tabs don't hold their page, so it's found by address, and only when no other loaded page shares it.
static id DPPageAt(NSURL *url) {
    id found = nil;
    for (id page in DPPages) {
        if (![[page valueForKey:@"url"] isEqual:url]) continue;
        if (found) return nil;
        found = page;
    }
    return found;
}

static void DPPage_setVisibility(id self, SEL _cmd, NSInteger visibility) {
    [DPPages addObject:self];
    DPCallOriginal(DPPage_setVisibility, self, visibility);
    if (visibility == DPPageVisible) [DPDiscarded removeObject:self];  // Showing it loads it again.
}

// Chromium may decline, as for a page playing audio, so a page only counts as unloaded once it says it went.
static void DPWebContent_finalizeDiscard(id self, SEL _cmd, id page, BOOL discarded) {
    DPCallOriginal(DPWebContent_finalizeDiscard, self, page, discarded);
    if (discarded && page) [DPDiscarded addObject:page];
}

static NSMenu *DPTab_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPTab_menuForEvent, self, event);
    id content = menu && DPUnloadTab.on ? DPTabContent(self) : nil;
    id page = content ? DPPageAt(DPSwiftValue(content, @"webContentURL")) : nil;
    if (!page || [DPDiscarded containsObject:page]) return menu;
    NSMenuItem *item = DPMenuItem(@"Unload Tab", ^{ [page performSelector:@selector(discard)]; });
    item.image = [NSImage imageWithSystemSymbolName:@"moon.zzz" accessibilityDescription:nil];
    // Hidden by default, unlike Dia's own items. By name: CI's SDK predates macOS 27. 1 is NSMenuItemImageVisibilityVisible.
    if (@available(macOS 27, *)) [item setValue:@1 forKey:@"preferredImageVisibility"];
    item.enabled = ((NSInteger (*)(id, SEL))objc_msgSend)(page, @selector(visibility)) != DPPageVisible;  // Chromium keeps the page on screen.
    NSUInteger close = [menu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *it, NSUInteger i, BOOL *stop) { return [it.title isEqual:@"Close"]; }];
    [menu insertItem:item atIndex:close == NSNotFound ? (NSUInteger)menu.numberOfItems : close];
    return menu;
}

static void DPInstallUnloadTab(void) {
    DPPages = [NSHashTable weakObjectsHashTable];
    DPDiscarded = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaWebContents, @selector(setVisibility:), (IMP)DPPage_setVisibility);
    DPHook(DPDiaTabView, @selector(menuForEvent:), (IMP)DPTab_menuForEvent);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:finalizeDiscardRequest:), (IMP)DPWebContent_finalizeDiscard);
    });
}

DP_PATCH(DPUnloadTab) {
    .key = @"unloadTab",
    .order = 86,
    .section = @"Tabs",
    .title = @"Unload Tabs",
    .detail = @"Right-click a tab and choose Unload Tab to free its memory. It stays in the sidebar and loads again when you open it.",
    .symbol = @"moon.zzz.fill",
    .tint = @"systemPinkColor",
    .classes = DPClasses(DPDiaWebContents, DPDiaTabView),
    .install = DPInstallUnloadTab,
};

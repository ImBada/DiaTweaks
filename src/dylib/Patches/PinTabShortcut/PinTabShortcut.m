#import "StdPatch/StdPatch.h"

extern DPPatch DPPinTabShortcut;

static NSDictionary *DPDefaultPinShortcut(void) { return @{ @"keyCode" : @2, @"modifiers" : @(NSEventModifierFlagCommand), @"key" : @"D" }; }

static id DPTabState(NSView *tab) { return DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue"); }

static BOOL DPTabSelected(NSView *tab) {
    NSString *style = [[DPSwiftValue(DPTabState(tab), @"selectionStyle") description] lowercaseString];
    return style && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"];
}

// Skip recycled hidden cells, but allow collapsed sidebars and auto-hidden strips.
static BOOL DPTabShown(NSView *tab) {
    for (NSView *view = tab; view && ![view isKindOfClass:NSCollectionView.class] && !DPIsKind(view, DPDiaTabStrip); view = view.superview)
        if (view.hidden) return NO;
    return YES;
}

static NSMenuItem *DPShownItem(NSMenuItem *item) { return item && !item.hidden && item.enabled ? item : nil; }

static NSMenuItem *DPPinItem(NSMenu *menu) {
    return DPShownItem([menu itemWithTitle:@"Pin as Tab"]) ?: DPShownItem([menu itemWithTitle:@"Unpin"]);
}

static NSMenuItem *DPFindShownItem(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.hidden) continue;
        NSMenuItem *found = [item.title isEqualToString:title] ? DPShownItem(item) : DPFindShownItem(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

#define DPHeld __attribute__((objc_precise_lifetime))
static void DPRunItem(NSMenuItem *item) { [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]]; }

static NSURL *DPTabURL(NSView *tab) {
    NSDictionary *views = DPSwiftValue(tab, @"contentViews");
    if (views.count != 1) return nil;
    return DPSwiftValue(DPSwiftValue(DPSwiftValue(views.allValues.firstObject, @"viewModel"), @"delegate"), @"webContentURL");
}

static NSView *DPSelectedTab(NSWindow *window) {
    for (NSView *tab in DPFindViews(DPDiaTabView))
        if (tab.window == window && DPTabShown(tab) && DPTabSelected(tab)) return tab;
    return nil;
}

// Pin as Tab reuses a tab's first-ever pinned URL; replace it with the current page once pinned.
static void DPPinCurrentURL(NSWindow *window, NSURL *url, int tries) {
    if (!DPPinTabShortcut.on) return;
    NSView *tab = DPSelectedTab(window);
    DPHeld NSMenu *menu = tab && [DPTabURL(tab) isEqual:url] ? DPTabContextMenu(tab) : nil;
    if (DPShownItem([menu itemWithTitle:@"Unpin"])) {
        NSMenuItem *replace = DPFindShownItem(menu, @"Replace Pinned URL with Current");
        if (replace) DPRunItem(replace);
    } else if (tries > 0) {
        __weak NSWindow *weakWindow = window;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
            if (weakWindow) DPPinCurrentURL(weakWindow, url, tries - 1);
        });
    }
}

static void DPInstallPinTabShortcut(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (!DPPinTabShortcut.on || !event.window || !DPShortcutMatches(event, &DPPinTabShortcut)) return event;
        NSView *tab = DPSelectedTab(event.window);
        DPHeld NSMenu *menu = tab ? DPTabContextMenu(tab) : nil;
        NSMenuItem *item = DPPinItem(menu);
        if (!item) return event;
        if (event.isARepeat) return nil;
        BOOL pinning = [item.title isEqualToString:@"Pin as Tab"];
        NSURL *url = DPTabURL(tab);
        DPRunItem(item);
        if (pinning && url) DPPinCurrentURL(event.window, url, 20);
        return nil;
    }];
}

static NSString *DPVerifyPinTabShortcut(DPPatch *patch) {
    if (!patch->on) return nil;
    BOOL any = NO;
    for (NSView *tab in DPFindViews(DPDiaTabView)) {
        if (!DPTabShown(tab)) continue;
        any = YES;
        if (DPPinItem(DPTabContextMenu(tab))) return nil;
    }
    return any ? @"no tab's menu has Pin as Tab or Unpin" : nil;
}

DP_PATCH(DPPinTabShortcut) {
    .key = @"pinTabShortcut",
    .order = 83,
    .title = @"Pin Tab Shortcut",
    .detail = @"Press a shortcut, ⌘D unless you set another, to move the tab you’re on to the bottom of your pinned tabs, as in Arc. Press it on a pinned tab to unpin it.",
    .symbol = @"pin.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .group = @"pinnedTabs",
    .classes = DPClasses(DPDiaTabView),
    .shortcut = @"pinTabShortcutKey",
    .defaultShortcut = DPDefaultPinShortcut,
    .install = DPInstallPinTabShortcut,
    .verify = DPVerifyPinTabShortcut,
};

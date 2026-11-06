#import "StdPatch/StdPatch.h"

extern DPPatch DPPinTabShortcut;

// Dia's Pin as Tab puts a tab at the bottom of the pinned tabs, and Unpin puts it back at the top of the rest. Dia only
// offers them in a tab's right-click menu; its Pin/Unpin Tab shortcut pins to the favorites at the top instead.
static NSString *const DPPinTitles[] = {@"Pin as Tab", @"Unpin"};

// ⌘D, as in Arc. Dia uses it for Bookmark This Page, which keeps it whenever there’s no tab to pin.
static NSDictionary *DPDefaultPinShortcut(void) { return @{ @"keyCode" : @2, @"modifiers" : @(NSEventModifierFlagCommand), @"key" : @"D" }; }

static id DPTabState(NSView *tab) { return DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue"); }

// selectionStyle is "none" when unselected, nil on an unselected pinned tab, and above/below on the selection's neighbours.
static BOOL DPTabSelected(NSView *tab) {
    NSString *style = [[DPSwiftValue(DPTabState(tab), @"selectionStyle") description] lowercaseString];
    return style && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"];
}

// The list keeps cells it isn't showing, hidden, so a hidden cell is skipped but a collapsed sidebar isn't.
static BOOL DPTabShown(NSView *tab) {
    for (NSView *view = tab; view && ![view isKindOfClass:NSCollectionView.class]; view = view.superview)
        if (view.hidden) return NO;
    return YES;
}

// The item doesn't keep its menu, so it runs before the menu goes.
static BOOL DPPinTab(NSView *tab, BOOL run) {
    NSPoint point = [tab convertPoint:NSMakePoint(NSMidX(tab.bounds), NSMidY(tab.bounds)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:tab.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSMenu *menu = [tab menuForEvent:click];
    for (NSUInteger i = 0; i < sizeof(DPPinTitles) / sizeof(DPPinTitles[0]); i++) {
        NSMenuItem *item = [menu itemWithTitle:DPPinTitles[i]];
        if (!item || item.hidden || !item.enabled) continue;
        if (run) [menu performActionForItemAtIndex:[menu indexOfItem:item]];
        return YES;
    }
    return NO;
}

static NSArray<NSView *> *DPShownTabs(NSWindow *window) {
    NSMutableArray<NSView *> *tabs = [NSMutableArray array];
    for (NSView *tab in DPFindViews(DPDiaTabView))
        if ((!window || tab.window == window) && DPTabShown(tab)) [tabs addObject:tab];
    return tabs;
}

static NSView *DPSelectedTab(NSWindow *window) {
    for (NSView *tab in DPShownTabs(window))
        if (DPTabSelected(tab)) return tab;
    return nil;
}

static void DPInstallPinTabShortcut(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (!DPPinTabShortcut.on || !event.window || !DPShortcutMatches(event, &DPPinTabShortcut)) return event;
        NSView *tab = DPSelectedTab(event.window);
        return tab && DPPinTab(tab, !event.isARepeat) ? nil : event;
    }];
}

static NSString *DPVerifyPinTabShortcut(DPPatch *patch) {
    NSArray<NSView *> *tabs = DPShownTabs(nil);
    if (!patch->on || !tabs.count) return nil;
    for (NSView *tab in tabs)
        if (DPPinTab(tab, NO)) return nil;
    return @"no tab's menu has Pin as Tab or Unpin";
}

DP_PATCH(DPPinTabShortcut) {
    .key = @"pinTabShortcut",
    .order = 86,
    .title = @"Pin Tab Shortcut",
    .detail = @"Press a shortcut, ⌘D unless you set another, to move the tab you’re on to the bottom of your pinned tabs, as in Arc. Press it on a pinned tab to unpin it.",
    .symbol = @"pin.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabView),
    .shortcut = @"pinTabShortcutKey",
    .defaultShortcut = DPDefaultPinShortcut,
    .install = DPInstallPinTabShortcut,
    .verify = DPVerifyPinTabShortcut,
};

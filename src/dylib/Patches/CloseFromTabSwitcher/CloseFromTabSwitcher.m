#import "StdPatch/StdPatch.h"

extern DPPatch DPCloseFromTabSwitcher;

static id DPSwitcherState(NSWindowController *switcher) {
    return DPSwiftValue(DPSwiftValue(DPSwiftValue(switcher, @"viewModel"), @"stateSubject"), @"currentValue");
}

static NSString *DPSwitcherFocus(NSWindowController *switcher) {
    return [DPSwiftValue(DPSwitcherState(switcher), @"focusedItemID") description];
}

static NSArray<NSString *> *DPSwitcherTabs(NSWindowController *switcher, NSString **focused) {
    id state = DPSwitcherState(switcher);
    if (focused) *focused = [DPSwiftValue(state, @"focusedItemID") description];
    return DPUUIDsIn([DPSwiftValue(state, @"items") description]);
}

static id DPSwitcherScriptTab(NSString *tabID) {
    id windows = DPValueForKey(NSApp.delegate, @"appleScriptWindows");
    if (![windows isKindOfClass:NSArray.class]) return nil;
    for (id window in windows) {
        id tabs = DPValueForKey(window, @"appleScriptTabs");
        if (![tabs isKindOfClass:NSArray.class]) continue;
        for (id tab in tabs)
            if ([DPValueForKey(tab, @"tabId") isEqual:tabID]) return tab;
    }
    return nil;
}

static NSMenuItem *DPCycleItem(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.keyEquivalent isEqualToString:@"\t"] && item.keyEquivalentModifierMask == NSEventModifierFlagControl) return item;
        NSMenuItem *found = DPCycleItem(item.submenu);
        if (found) return found;
    }
    return nil;
}

static void DPStep(void) {
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagControl timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:NSApp.keyWindow.windowNumber context:nil characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48]
             atStart:NO];
}

static NSUInteger DPFocusGeneration;

static void DPFocus(NSString *tabID, NSString *lastSeen, int tries, NSUInteger gen) {
    if (!DPCloseFromTabSwitcher.on || gen != DPFocusGeneration || !(NSEvent.modifierFlags & NSEventModifierFlagControl)) return;
    NSWindowController *switcher = DPOpenTabSwitcher();
    NSString *focused = switcher ? DPSwitcherFocus(switcher) : nil;
    if (!tries || [focused isEqual:tabID]) return;
    if (focused && ![focused isEqual:lastSeen]) DPStep();
    int left = switcher ? tries - 1 : MIN(tries - 1, 8);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        DPFocus(tabID, focused ?: lastSeen, left, gen);
    });
}

static void DPReopenOnceClosed(NSString *closed, NSString *focus, NSMenuItem *cycle, int tries, NSUInteger gen) {
    if (!DPCloseFromTabSwitcher.on || gen != DPFocusGeneration || !tries || !(NSEvent.modifierFlags & NSEventModifierFlagControl)) return;
    if (DPSwitcherScriptTab(closed)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            DPReopenOnceClosed(closed, focus, cycle, tries - 1, gen);
        });
        return;
    }
    [NSApp sendAction:cycle.action to:cycle.target from:cycle];
    DPFocus(focus, nil, 20, gen);
}

static BOOL DPCloseFocusedTab(NSWindowController *switcher) {
    NSString *focused = nil;
    NSMutableArray<NSString *> *tabs = [DPSwitcherTabs(switcher, &focused) mutableCopy];
    NSUInteger index = focused ? [tabs indexOfObject:focused] : NSNotFound;
    id tab = focused ? DPSwitcherScriptTab(focused) : nil;
    if (index == NSNotFound || !tab || ![tab respondsToSelector:@selector(close:)]) return NO;
    NSUInteger gen = ++DPFocusGeneration;
    [tab performSelector:@selector(close:) withObject:nil];
    [tabs removeObjectAtIndex:index];
    [switcher close];
    NSMenuItem *cycle = tabs.count > 1 ? DPCycleItem(NSApp.mainMenu) : nil;
    if (cycle) DPReopenOnceClosed(focused, tabs[MIN(index, tabs.count - 1)], cycle, 12, gen);
    return YES;
}

// The switcher picks the highlighted tab as soon as another modifier goes down, so it never sees ⌘.
static BOOL DPTakeEvent(NSEvent *event) {
    if (!(event.type == NSEventTypeKeyDown || event.type == NSEventTypeFlagsChanged) || !(event.modifierFlags & NSEventModifierFlagControl)) return NO;
    NSWindowController *switcher = DPOpenTabSwitcher();
    if (!switcher) return NO;
    if (event.type == NSEventTypeFlagsChanged) return event.keyCode == 54 || event.keyCode == 55;
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption);
    NSString *typed = event.charactersIgnoringModifiers.lowercaseString;
    BOOL isW = (typed.length && [typed characterAtIndex:0] > 0x7f) ? event.keyCode == 13 : [typed isEqualToString:@"w"];
    return (mods == NSEventModifierFlagCommand || !mods) && isW && DPCloseFocusedTab(switcher);
}

static NSEvent *DPApplication_nextEvent(NSApplication *self, SEL _cmd, NSEventMask mask, NSDate *until, NSRunLoopMode mode, BOOL dequeue) {
    if (!DPCloseFromTabSwitcher.on || !dequeue) return DPCallOriginal(DPApplication_nextEvent, self, mask, until, mode, dequeue);
    NSEvent *event;
    do event = DPCallOriginal(DPApplication_nextEvent, self, mask, until, mode, dequeue);
    while (event && DPTakeEvent(event));
    return event;
}

static void DPInstallCloseFromTabSwitcher(void) {
    DPHookClass(NSApplication.class, @selector(nextEventMatchingMask:untilDate:inMode:dequeue:), (IMP)DPApplication_nextEvent);
}

DP_PATCH(DPCloseFromTabSwitcher) {
    .key = @"closeFromTabSwitcher",
    .defaultOn = YES,
    .order = 86,
    .title = @"Close Tabs from Tab Switcher",
    .detail = @"Press W or ⌘W while the tab switcher (⌃⇥) is open to close the highlighted tab and keep switching.",
    .symbol = @"xmark.square.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabSwitcher),
    .install = DPInstallCloseFromTabSwitcher,
};

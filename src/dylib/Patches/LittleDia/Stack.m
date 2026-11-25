#import "LittleDia.h"

static NSArray<NSDictionary *> *DPBeforeActivating;
static NSDate *DPNotedAt, *DPUnhiddenAt;
static NSMutableArray<NSWindow *> *DPPutAway;
static NSMapTable<NSWindow *, NSNumber *> *DPVeiled;

NSArray<NSDictionary *> *DPWindowStack(void) {
    NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    NSMutableArray *stack = [NSMutableArray array];
    for (NSDictionary *info in list)
        if ([info[(id)kCGWindowLayer] integerValue] == 0) [stack addObject:@{@"number" : info[(id)kCGWindowNumber], @"pid" : info[(id)kCGWindowOwnerPID]}];
    return stack;
}

NSDictionary *DPNoteStackForLink(void) {
    NSArray<NSDictionary *> *stack = nil;
    if (!NSApp.active) stack = DPWindowStack();
    else if (DPNotedAt && DPNotedAt.timeIntervalSinceNow > -2) stack = DPBeforeActivating;
    NSNumber *me = @(getpid()), *source = @0;
    for (NSDictionary *window in stack)
        if (![window[@"pid"] isEqual:me]) {
            source = window[@"pid"];
            break;
        }
    return @{@"stack" : stack ?: @[], @"source" : source};
}

static void DPPutAwayWindow(NSWindow *window) {
    if (![DPPutAway containsObject:window]) [DPPutAway addObject:window];
    [window orderOut:nil];
}

static BOOL DPPutAwayIfHidden(void) {
    if (!DPLittleDia.on || !DPUnhiddenAt || DPUnhiddenAt.timeIntervalSinceNow < -2) return NO;
    for (NSWindow *window in NSApp.orderedWindows)
        if (!DPIsLittleDiaWindow(window) && window.visible && window.level == NSNormalWindowLevel) DPPutAwayWindow(window);
    return YES;
}

// macOS unhides Dia a moment before the link arrives, so its windows stay see-through until the link can put them away.
static void DPUnveil(void) {
    for (NSWindow *window in DPVeiled) window.alphaValue = [[DPVeiled objectForKey:window] doubleValue];
    [DPVeiled removeAllObjects];
}

void DPRestoreLittleDiaStack(void) {
    DPUnveil();
    DPBringBackPutAway(nil);
    DPUnhiddenAt = nil;
}

void DPLinkArrived(void) {
    for (NSWindow *window in NSApp.orderedWindows)
        if ([DPVeiled objectForKey:window] && window.visible) DPPutAwayWindow(window);
    for (NSWindow *window in DPVeiled)
        if (window.visible) DPPutAwayWindow(window);
    DPUnveil();
}

NSArray<NSWindow *> *DPPutAwayWindows(void) { return DPPutAway.copy ?: @[]; }

void DPBringBackPutAway(NSWindow *little) {
    for (NSWindow *window in DPPutAway) {
        if (little.visible) [window orderWindow:NSWindowBelow relativeTo:little.windowNumber];
        else [window orderFront:nil];
    }
    [DPPutAway removeAllObjects];
}

BOOL DPHideAgain(void) {
    if (!DPPutAway.count) return NO;
    for (NSWindow *window in NSApp.windows)
        if (DPIsLittleDiaWindow(window) && window.visible) return NO;
    for (NSWindow *window in NSApp.windows)
        if (window.visible && !window.miniaturized && window.level == NSNormalWindowLevel && window.canBecomeMainWindow) return NO;
    // Hiding notes which windows are showing, so they're shown first, behind everything, for unhiding to bring back.
    for (NSWindow *window in DPPutAway) [window orderBack:nil];
    [DPPutAway removeAllObjects];
    [NSApp hide:nil];
    return YES;
}

static void DPOrderBehind(NSWindow *little, NSArray<NSDictionary *> *stack) {
    NSNumber *me = @(getpid());
    NSUInteger front = [stack indexOfObjectPassingTest:^BOOL(NSDictionary *window, NSUInteger i, BOOL *stop) { return ![window[@"pid"] isEqual:me]; }];
    if (front == NSNotFound) return;
    // Back to front, so each lands just behind the closest window above it that isn't Dia's, and they keep their order.
    for (NSWindow *window in NSApp.orderedWindows.reverseObjectEnumerator) {
        if (window == little || !window.visible || window.level != NSNormalWindowLevel) continue;
        NSUInteger at = [stack indexOfObjectPassingTest:^BOOL(NSDictionary *each, NSUInteger i, BOOL *stop) { return [each[@"number"] integerValue] == window.windowNumber; }];
        if (at == NSNotFound || at <= front) continue;
        NSUInteger above = at - 1;
        while ([stack[above][@"pid"] isEqual:me]) above--;
        [window orderWindow:NSWindowBelow relativeTo:[stack[above][@"number"] integerValue]];
    }
}

void DPReturnToSource(pid_t pid, NSWindow *little, NSArray<NSDictionary *> *stack) {
    NSRunningApplication *app = pid ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid] : nil;
    if (!app || app.terminated) return;
    if (@available(macOS 14, *)) [app activateFromApplication:NSRunningApplication.currentApplication options:0];
    else [app activateWithOptions:0];
    DPOrderBehind(little, stack);  // Dia brings its next window forward as the key one closes.
}

void DPRestoreStack(NSWindow *little, NSDictionary *noted) {
    if (DPPutAwayIfHidden()) return;
    DPOrderBehind(little, noted[@"stack"]);
}

// Only an unhide that a link to Little Dia can follow; the unveil is queued before any window goes clear.
static void DPVeilWindows(void) {
    if (!DPLittleDia.on || DPLittleDiaFollowRules.on || !DPLittleDiaReady()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPUnveil(); });
    for (NSWindow *window in NSApp.windows)
        if (window.level == NSNormalWindowLevel && !DPIsLittleDiaWindow(window) && window.alphaValue > 0 && ![DPVeiled objectForKey:window]) {
            [DPVeiled setObject:@(window.alphaValue) forKey:window];
            window.alphaValue = 0;
        }
}

void DPInstallLittleDiaStack(void) {
    DPPutAway = [NSMutableArray array];
    DPVeiled = [NSMapTable weakToStrongObjectsMapTable];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSApplicationWillUnhideNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPVeilWindows(); }];
    [center addObserverForName:NSApplicationDidUnhideNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (DPLittleDia.on) DPUnhiddenAt = [NSDate date];
    }];
    [center addObserverForName:NSApplicationWillBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!DPLittleDia.on) return;
        DPBeforeActivating = DPWindowStack();
        DPNotedAt = [NSDate date];
    }];
    [center addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (DPPutAway.count) [DPPutAway removeObjectIdenticalTo:note.object];
    }];
}

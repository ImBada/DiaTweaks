#import "Patches/LittleDia/Stack.m"

DPPatch DPLittleDia, DPLittleDiaFollowRules;
static BOOL gReady = YES;
BOOL DPIsLittleDiaWindow(NSWindow *window) { return NO; }
BOOL DPLittleDiaReady(void) { return gReady; }

static int failures;

// Window prefixes: D = Dia, A/B = other apps; lists read front to back.
static NSWindow *invisibleWindow(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 1, 1) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    return window;
}

static NSString *order(NSDictionary<NSString *, NSWindow *> *windows) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSWindow *window in NSApp.orderedWindows)
        for (NSString *name in windows)
            if (windows[name] == window) [names addObject:name];
    return [names componentsJoinedByString:@" "];
}

static void makeStack(NSString *before, NSMutableDictionary<NSString *, NSWindow *> *windows, NSMutableArray<NSDictionary *> *stack, NSMutableArray<NSString *> *dia) {
    NSArray<NSString *> *names = [before componentsSeparatedByString:@" "];
    for (NSString *name in names) {
        windows[name] = invisibleWindow();
        BOOL mine = [name hasPrefix:@"D"];
        [stack addObject:@{@"number" : @(windows[name].windowNumber), @"pid" : @(getpid() + !mine)}];
        if (mine) [dia addObject:name];
    }
    for (NSString *name in names.reverseObjectEnumerator) [windows[name] orderFront:nil];
}

static void restores(NSString *before, NSString *opened) {
    NSMutableDictionary<NSString *, NSWindow *> *windows = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *stack = [NSMutableArray array];
    NSMutableArray<NSString *> *dia = [NSMutableArray array];
    makeStack(before, windows, stack, dia);
    NSArray<NSString *> *fresh = opened.length ? [opened componentsSeparatedByString:@" "] : @[];
    NSWindow *little = windows[@"L"] = invisibleWindow();
    for (NSString *name in fresh) windows[name] = invisibleWindow();
    for (NSString *name in dia.reverseObjectEnumerator) [windows[name] orderFront:nil];
    for (NSString *name in fresh.reverseObjectEnumerator) [windows[name] orderFront:nil];
    [little orderFront:nil];
    DPRestoreStack(little, @{@"stack" : stack, @"source" : @(getpid() + 1)});
    NSString *got = order(windows), *want = [NSString stringWithFormat:@"L %@%@", opened.length ? [opened stringByAppendingString:@" "] : @"", before];
    if (![got isEqual:want]) printf("FAIL %s, then %s opened: %s, want %s\n", before.UTF8String, opened.UTF8String, got.UTF8String, want.UTF8String), failures++;
    for (NSWindow *window in windows.allValues) [window orderOut:nil];
}

static void closes(NSString *before) {
    NSMutableDictionary<NSString *, NSWindow *> *windows = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *stack = [NSMutableArray array];
    makeStack(before, windows, stack, nil);
    [windows[@"D1"] orderFront:nil];
    [windows[@"A1"] orderFront:nil];
    DPOrderBehind(windows[@"D0"], stack);
    NSString *got = [order(windows) stringByReplacingOccurrencesOfString:@"D0 " withString:@""], *want = [before stringByReplacingOccurrencesOfString:@"D0 " withString:@""];
    got = [got stringByReplacingOccurrencesOfString:@" D0" withString:@""];
    if (![got isEqual:want]) printf("FAIL closing %s: %s, want %s\n", before.UTF8String, got.UTF8String, want.UTF8String), failures++;
    for (NSWindow *window in windows.allValues) [window orderOut:nil];
}

#define EXPECT(condition, what) do { if (!(condition)) printf("FAIL %s\n", what), failures++; } while (0)

static void unhide(void) { [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationWillUnhideNotification object:NSApp]; }

static void pump(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static void veils(void) {
    DPInstallLittleDiaStack();
    NSWindow *window = invisibleWindow();
    window.releasedWhenClosed = NO;
    window.alphaValue = 0.6;
    [window orderFront:nil];

    unhide();
    EXPECT(window.alphaValue == 0.6, "off: an unhide leaves Dia's windows alone");
    DPLittleDia.on = YES;
    DPLittleDiaFollowRules.on = YES;
    unhide();
    EXPECT(window.alphaValue == 0.6, "Follow Link Rules: links open as tabs, so nothing is veiled");
    DPLittleDiaFollowRules.on = NO;
    gReady = NO;
    unhide();
    EXPECT(window.alphaValue == 0.6, "no ready extension: nothing is veiled");
    gReady = YES;

    unhide();
    EXPECT(window.alphaValue == 0, "an unhide veils Dia's windows until the link arrives");
    unhide();
    pump(0.4);
    EXPECT(fabs(window.alphaValue - 0.6) < 0.001, "with no link, the veil lifts on its own and keeps the window's alpha");

    unhide();
    DPRestoreLittleDiaStack();
    EXPECT(fabs(window.alphaValue - 0.6) < 0.001, "turning Little Dia off lifts the veil at once");

    unhide();
    DPLinkArrived();
    EXPECT(!window.visible && fabs(window.alphaValue - 0.6) < 0.001, "a link puts the veiled window away and lifts the veil");
    EXPECT([DPPutAwayWindows() containsObject:window], "the put-away window is remembered");
    [window close];
    EXPECT(![DPPutAwayWindows() containsObject:window], "a put-away window that closes is let go, never brought back");
    DPLittleDia.on = NO;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        restores(@"A1 D1", @"");
        restores(@"A1 D1 D2", @"");
        restores(@"D1 A1 D2", @"");
        restores(@"A1 A2 D1", @"");
        restores(@"A1 D1 A2 D2", @"");
        restores(@"A1 A2 D1 D2 A3", @"");
        restores(@"A1 B1 D1", @"");
        restores(@"A1 A2 D1", @"D9");
        closes(@"D0 A1 D1");
        closes(@"D0 A1 A2 D1 D2");
        closes(@"D0 A1 A2 D1 A3 D2");
        veils();
        printf(failures ? "%d stack scenarios failed\n" : "all stack scenarios pass\n", failures);
        return failures != 0;
    }
}

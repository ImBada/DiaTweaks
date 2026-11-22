#import "Patches/LittleDia/Window.m"

DPPatch DPLittleDia, DPLittleDiaRemember;
static NSMapTable<NSWindow *, NSNumber *> *gRestoreCounts;
void DPRestoreStack(NSWindow *little, NSDictionary *noted) {
    if (!little) return;
    if (!gRestoreCounts) gRestoreCounts = [NSMapTable weakToStrongObjectsMapTable];
    NSInteger n = [[gRestoreCounts objectForKey:little] integerValue];
    [gRestoreCounts setObject:@(n + 1) forKey:little];
}
NSArray<NSDictionary *> *DPWindowStack(void) { return @[]; }
void DPReturnToSource(pid_t pid, NSWindow *little, NSArray<NSDictionary *> *stack) {}
void DPBringBackPutAway(NSWindow *little) {}
BOOL DPHideAgain(void) { return NO; }
void DPInstallLittleDiaBar(void) {}
void DPInstallLittleDiaStack(void) {}
void DPRelayoutLittleDiaBars(void) {}
void DPSaveLittleDiaFrame(NSRect frame) {}
void DPOnLaunch(void (^block)(void)) {}

@interface _TtC5Popup19PlatformPopupWindow : NSWindow
@property BOOL fakeKey;
@end
@implementation _TtC5Popup19PlatformPopupWindow
- (BOOL)isKeyWindow { return self.fakeKey; }
- (void)makeKeyAndOrderFront:(id)sender {}
@end

@interface _TtC5Popup22PopupNavigationBarView : NSView
@end
@implementation _TtC5Popup22PopupNavigationBarView
@end

@interface RenderWidgetHostViewCocoa : NSView
@end
@implementation RenderWidgetHostViewCocoa
- (BOOL)acceptsFirstResponder { return YES; }
@end

@interface _TtC3ADK15ChromiumBrowser : NSObject
- (void)browser:(id)browser didCreateNewWebContents:(id)page isActive:(BOOL)active;
@end
@implementation _TtC3ADK15ChromiumBrowser
- (void)browser:(id)browser didCreateNewWebContents:(id)page isActive:(BOOL)active {}
@end

static void DPApp_activate(NSApplication *self, SEL _cmd, BOOL flag) {}

static _TtC5Popup19PlatformPopupWindow *DPNewPopup(void) {
    _TtC5Popup19PlatformPopupWindow *window = [[_TtC5Popup19PlatformPopupWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300)
                                                                                                 styleMask:NSWindowStyleMaskBorderless
                                                                                                   backing:NSBackingStoreBuffered defer:NO];
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    return window;
}

static _TtC5Popup19PlatformPopupWindow *DPClaimedPopup(BOOL key) {
    _TtC5Popup19PlatformPopupWindow *window = DPNewPopup();
    window.fakeKey = key;
    DPExpectLittleDiaWindow(window.frame, @{}, ^{}, nil);
    [window.contentView addSubview:[[_TtC5Popup22PopupNavigationBarView alloc] initWithFrame:NSMakeRect(0, 260, 400, 40)]];
    return window;
}

// The main queue is FIFO, so once the sentinel runs, every block queued before it has run too, however long a slow runner stalls.
static void DPDrain(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!drained && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    [NSRunLoop.mainRunLoop runUntilDate:until];
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(NSApp.class, @selector(activateIgnoringOtherApps:), (IMP)DPApp_activate);
        DPLittleDia.on = YES;
        DPInstallLittleDiaWindows();

        _TtC5Popup19PlatformPopupWindow *w1 = DPClaimedPopup(YES);
        CHECK(DPIsLittleDiaWindow(w1) && w1.firstResponder == w1, "claimed popup starts with window as first responder");
        RenderWidgetHostViewCocoa *page1 = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)];
        [w1.contentView addSubview:page1];
        DPDrain(0.05);
        CHECK(w1.firstResponder == page1, "arriving RenderWidgetHostViewCocoa becomes first responder");

        _TtC5Popup19PlatformPopupWindow *w2 = DPClaimedPopup(YES);
        RenderWidgetHostViewCocoa *page2 = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)];
        page2.hidden = YES;
        [w2.contentView addSubview:page2];
        DPDrain(0.05);
        CHECK(w2.firstResponder == w2, "hidden page view is not focused");
        page2.hidden = NO;
        DPDrain(0.35);
        CHECK(w2.firstResponder == page2, "visible page view is focused on the 300 ms settle pass");

        _TtC5Popup19PlatformPopupWindow *w3 = DPClaimedPopup(YES);
        NSTextView *address = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 260, 300, 30)];
        [w3.contentView addSubview:address];
        CHECK([w3 makeFirstResponder:address] && w3.firstResponder == address, "address text view takes focus");
        [w3.contentView addSubview:[[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)]];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:w3];
        DPDrain(0.35);
        CHECK(w3.firstResponder == address, "existing text responder keeps focus");

        _TtC5Popup19PlatformPopupWindow *w4 = DPClaimedPopup(NO);
        RenderWidgetHostViewCocoa *page4 = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)];
        [w4.contentView addSubview:page4];
        DPDrain(0.05);
        CHECK(w4.firstResponder == w4, "non-key Little Dia window is left alone");
        w4.fakeKey = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:w4];
        CHECK(w4.firstResponder == page4, "becoming key focuses the waiting page view");

        _TtC5Popup19PlatformPopupWindow *nativePopup = DPNewPopup();
        nativePopup.fakeKey = YES;
        [nativePopup.contentView addSubview:[[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)]];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:nativePopup];
        DPDrain(0.05);
        CHECK(nativePopup.firstResponder == nativePopup, "unclaimed native popup is untouched");

        _TtC5Popup19PlatformPopupWindow *w5 = DPClaimedPopup(YES);
        DPPromoteLittleDiaWindow(w5);
        [w5.contentView addSubview:[[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)]];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:w5];
        DPDrain(0.05);
        CHECK(w5.firstResponder == w5, "promoted Little Dia window is untouched");

        _TtC5Popup19PlatformPopupWindow *w6 = DPClaimedPopup(YES);
        DPLittleDia.on = NO;
        [w6.contentView addSubview:[[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)]];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:w6];
        DPDrain(0.05);
        CHECK(w6.firstResponder == w6, "Little Dia off leaves focus untouched");

        // Regression: 300 ms DPClaim settle timer skips closed, promoted, or disabled Little Dia windows.
        DPLittleDia.on = YES;
        _TtC5Popup19PlatformPopupWindow *wClosed = DPClaimedPopup(YES);
        _TtC5Popup19PlatformPopupWindow *wPromoted = DPClaimedPopup(YES);
        CHECK([[gRestoreCounts objectForKey:wClosed] integerValue] == 1 && [[gRestoreCounts objectForKey:wPromoted] integerValue] == 1,
              "initial DPClaim invokes DPRestoreStack once per claimed popup");
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:wClosed];
        DPPromoteLittleDiaWindow(wPromoted);
        DPDrain(0.35);
        CHECK([[gRestoreCounts objectForKey:wClosed] integerValue] == 1 && [[gRestoreCounts objectForKey:wPromoted] integerValue] == 1,
              "300 ms DPClaim timer does not run DPRestoreStack after close or promote");

        _TtC5Popup19PlatformPopupWindow *wPaused = DPClaimedPopup(YES);
        CHECK([[gRestoreCounts objectForKey:wPaused] integerValue] == 1, "initial DPClaim invokes DPRestoreStack");
        DPLittleDia.on = NO;
        DPDrain(0.35);
        CHECK([[gRestoreCounts objectForKey:wPaused] integerValue] == 1,
              "300 ms DPClaim timer does not run DPRestoreStack when Little Dia is off/paused");

        // Regression: DPStayingLink NSProxy handles respondsToSelector:/isKindOfClass:/conformsToProtocol: safely with valid and nil targets.
        DPStayingLink *proxy = [DPStayingLink alloc];
        proxy.action = @"hello";
        CHECK([proxy respondsToSelector:@selector(navigationDisposition)], "DPStayingLink responds to navigationDisposition");
        CHECK([proxy respondsToSelector:@selector(length)], "DPStayingLink forwards respondsToSelector: to target");
        CHECK(![proxy respondsToSelector:@selector(nonexistentSelectorForProxyTest)], "DPStayingLink returns NO for unknown selectors");
        CHECK([proxy isKindOfClass:NSString.class], "DPStayingLink forwards isKindOfClass: to target");
        CHECK([proxy conformsToProtocol:@protocol(NSCopying)], "DPStayingLink forwards conformsToProtocol: to target");
        CHECK(proxy.navigationDisposition == DPCurrentTab, "DPStayingLink overrides navigationDisposition to DPCurrentTab");
        DPStayingLink *nilProxy = [DPStayingLink alloc];
        nilProxy.action = nil;
        CHECK([nilProxy respondsToSelector:@selector(navigationDisposition)], "nil-target DPStayingLink responds to navigationDisposition");
        CHECK(![nilProxy respondsToSelector:@selector(length)], "nil-target DPStayingLink does not abort on respondsToSelector:");
        CHECK(![nilProxy isKindOfClass:NSString.class] && ![nilProxy conformsToProtocol:@protocol(NSCopying)],
              "nil-target DPStayingLink safely returns NO for kind/protocol checks");

        if (failures) return 1;
        puts("PASS: Little Dia focuses the page view without stealing existing focus");
    }
    return 0;
}

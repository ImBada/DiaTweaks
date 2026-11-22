#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "StdPatch/StdPatch.h"
#import "Patches/EdgeToEdge/EdgeToEdge.h"

BOOL DPTesting = YES;
BOOL DPPaused, DPPausedAtLaunch;
DPPatch DPWindowCorners;
CGFloat DPWindowCornerGrowth(NSWindow *window) { return 0; }
BOOL DPAnimating(void) { return NO; }

// --- Fake Dia classes ---
@interface _TtC6Window14PlatformWindow : NSWindow
@property CGFloat fakeCornerRadius;
@property NSWindowStyleMask fakeStyleMask;
@property BOOL useFakeStyleMask;
@end
@implementation _TtC6Window14PlatformWindow
- (BOOL)isVisible { return YES; }
- (CGFloat)_cornerRadius { return self.fakeCornerRadius; }
- (void)_setCornerRadius:(CGFloat)radius { self.fakeCornerRadius = radius; }
- (void)_updateWindowCornerMask {}
- (NSWindowStyleMask)styleMask { return self.useFakeStyleMask ? self.fakeStyleMask : [super styleMask]; }
- (void)setStyleMask:(NSWindowStyleMask)mask {
    if (self.useFakeStyleMask) self.fakeStyleMask = mask;
    else [super setStyleMask:mask];
}
@end

@interface _TtC6Window20ContentContainerView : NSView {
@public
    CGFloat cornerRadius;
}
@end
@implementation _TtC6Window20ContentContainerView
- (void)layout {}
- (void)updateLayer {}
@end

@interface _TtC5ARCUI10ShadowView : NSView
@end
@implementation _TtC5ARCUI10ShadowView
- (void)layout {}
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView : NSView
@end
@implementation _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView
@end

// --- Test utilities ---
static int failures;

static void Check(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", what.UTF8String);
}

static void DrainMain(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (!done && until.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static _TtC6Window14PlatformWindow *MakeWindow(NSSize size, BOOL fullScreen) {
    _TtC6Window14PlatformWindow *window = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, size.width, size.height)
                                                                                         styleMask:NSWindowStyleMaskTitled
                                                                                           backing:NSBackingStoreBuffered
                                                                                             defer:NO];
    window.useFakeStyleMask = YES;
    window.fakeStyleMask = NSWindowStyleMaskTitled | (fullScreen ? NSWindowStyleMaskFullScreen : 0);
    window.fakeCornerRadius = 16;
    window.releasedWhenClosed = NO;
    return window;
}

static void SetFullScreen(_TtC6Window14PlatformWindow *window, BOOL fullScreen) {
    window.fakeStyleMask = NSWindowStyleMaskTitled | (fullScreen ? NSWindowStyleMaskFullScreen : 0);
}

typedef struct {
    _TtC6Window20ContentContainerView *container;
    NSView *rounded, *bar, *chatHost;
} Fixture;

static Fixture MakeFixture(_TtC6Window14PlatformWindow *window, NSRect frame) {
    Fixture f = {0};
    f.container = [[_TtC6Window20ContentContainerView alloc] initWithFrame:frame];
    f.container->cornerRadius = 10;
    f.rounded = [[NSView alloc] initWithFrame:f.container.bounds];
    f.rounded.wantsLayer = YES;
    f.rounded.layer.masksToBounds = YES;
    f.rounded.layer.cornerRadius = 10;
    f.rounded.layer.cornerCurve = kCACornerCurveCircular;
    f.bar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, NSHeight(f.container.bounds) - 40, NSWidth(f.container.bounds), 40)];
    [f.rounded addSubview:f.bar];
    NSView *chatRoot = [[NSView alloc] initWithFrame:f.rounded.bounds];
    f.chatHost = [[NSView alloc] initWithFrame:NSMakeRect(NSWidth(f.rounded.bounds) - 330, 10, 320, NSHeight(f.rounded.bounds) - 20)];
    f.chatHost.wantsLayer = YES;
    f.chatHost.layer.masksToBounds = YES;
    f.chatHost.layer.cornerRadius = 10;
    f.chatHost.hidden = YES;
    [chatRoot addSubview:f.chatHost];
    [f.rounded addSubview:chatRoot];
    [f.container addSubview:f.rounded];
    [window.contentView addSubview:f.container];
    f.container.frame = frame;
    return f;
}

static void Relayout(DPPatch *patch) {
    Check(patch->relayout != NULL, [NSString stringWithFormat:@"%@ re-applies the frame when it is toggled", patch->title]);
    if (patch->relayout) patch->relayout();
}

static void SetPatches(BOOL edgeToEdge, BOOL fullScreenOnly) {
    DPEdgeToEdge.on = edgeToEdge;
    DPEdgeToEdge.progress = edgeToEdge ? 1 : 0;
    DPFullScreenOnly.on = fullScreenOnly;
    DPFullScreenOnly.progress = fullScreenOnly ? 1 : 0;
    DPSquareSidebarCorners.on = YES;
    DPSquareSidebarCorners.progress = 1;
    DPWindowCorners.on = NO;
}

// --- Tests ---

// A full-screen window must not drag a windowed one along with it.
static void TestPerWindowIsolation(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *full = MakeWindow(NSMakeSize(1440, 900), YES);
    _TtC6Window14PlatformWindow *plain = MakeWindow(NSMakeSize(900, 600), NO);
    Fixture a = MakeFixture(full, NSMakeRect(220, 6, 1214, 888));
    Fixture b = MakeFixture(plain, NSMakeRect(220, 6, 674, 588));

    Check(DPWindowFullScreen(a.container.window) && !DPWindowFullScreen(b.container.window), @"windows report their own full-screen state");
    Check(DPEdgeToEdgeAmount(a.container) == 1, @"full-screen window is edge-to-edge");
    Check(DPEdgeToEdgeAmount(b.container) == 0, @"windowed window keeps Dia's padding");

    a.container.frame = NSMakeRect(220, 6, 1214, 888);
    b.container.frame = NSMakeRect(220, 6, 674, 588);
    Check(NSEqualRects(a.container.frame, NSMakeRect(220, 0, 1220, 900)), @"full-screen container reaches the edges");
    Check(NSEqualRects(b.container.frame, NSMakeRect(220, 6, 674, 588)), @"windowed container stays where Dia put it");

    // Entering full screen on one window must not touch the other.
    SetFullScreen(plain, YES);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEnterFullScreenNotification object:plain];
    DrainMain();
    Check(NSEqualRects(b.container.frame, NSMakeRect(220, 0, 680, 600)), @"entering full screen drops the padding");
    Check(NSEqualRects(a.container.frame, NSMakeRect(220, 0, 1220, 900)), @"the other window is untouched");

    SetFullScreen(plain, NO);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification object:plain];
    DrainMain();
    Check(NSEqualRects(b.container.frame, NSMakeRect(220, 6, 674, 588)), @"leaving full screen brings the padding back");
}

// A window that is already screen-sized still has to change when the mask flips.
static void TestScreenSizedWindowTransition(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(1440, 900), NO);
    Fixture f = MakeFixture(window, NSMakeRect(0, 6, 1440, 888));
    Check(NSEqualRects(f.container.frame, NSMakeRect(0, 6, 1440, 888)), @"windowed screen-sized window keeps its padding");

    SetFullScreen(window, YES);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEnterFullScreenNotification object:window];
    DrainMain();
    Check(NSEqualRects(f.container.frame, NSMakeRect(0, 0, 1440, 900)), @"a screen-sized window still goes edge-to-edge in full screen");

    SetFullScreen(window, NO);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification object:window];
    DrainMain();
    Check(NSEqualRects(f.container.frame, NSMakeRect(0, 6, 1440, 888)), @"and comes back when it leaves full screen");
}

// Toggling the option live has to re-apply the frame in both directions.
static void TestLiveToggle(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(900, 600), NO);
    Fixture f = MakeFixture(window, NSMakeRect(220, 6, 674, 588));
    Check(NSEqualRects(f.container.frame, NSMakeRect(220, 6, 674, 588)), @"starts padded with the option on");

    DPFullScreenOnly.on = NO;
    DPFullScreenOnly.progress = 0;
    Relayout(&DPFullScreenOnly);
    Check(NSEqualRects(f.container.frame, NSMakeRect(220, 0, 680, 600)), @"turning the option off goes edge-to-edge at once");

    DPFullScreenOnly.on = YES;
    DPFullScreenOnly.progress = 1;
    Relayout(&DPFullScreenOnly);
    Check(NSEqualRects(f.container.frame, NSMakeRect(220, 6, 674, 588)), @"turning it back on restores the padding at once");

    // Halfway through the ease the padding is half gone, and the corners follow the same amount.
    DPFullScreenOnly.progress = 0.5;
    Relayout(&DPFullScreenOnly);
    Check(NSEqualRects(f.container.frame, NSMakeRect(220, 3, 677, 594)), @"the ease moves the frame by the same amount");
    DPFullScreenOnly.progress = 1;
    Relayout(&DPFullScreenOnly);
}

// Corners follow the same per-window amount as the frame.
static void TestSquareCorners(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(900, 600), NO);
    Fixture f = MakeFixture(window, NSMakeRect(220, 6, 674, 588));
    DPRestyleContainer(f.container);
    Check(DPCornersRound(f.rounded.layer, NO) && DPCornersRound(f.rounded.layer, YES), @"windowed: all four corners stay round");

    SetFullScreen(window, YES);
    f.container.frame = NSMakeRect(220, 6, 674, 588);
    DPRestyleContainer(f.container);
    Check(!DPCornersRound(f.rounded.layer, NO) && !DPCornersRound(f.rounded.layer, YES), @"full screen: corners are square");

    SetFullScreen(window, NO);
    f.container.frame = NSMakeRect(220, 6, 674, 588);
    DPRestyleContainer(f.container);
    Check(DPCornersRound(f.rounded.layer, NO) && DPCornersRound(f.rounded.layer, YES), @"back to windowed: corners are round again");

    // With the option off, a windowed page keeps the square sidebar corners it always had.
    DPFullScreenOnly.on = NO;
    DPFullScreenOnly.progress = 0;
    f.container.frame = NSMakeRect(220, 6, 674, 588);
    DPRestyleContainer(f.container);
    Check(!DPCornersRound(f.rounded.layer, NO) && DPCornersRound(f.rounded.layer, YES), @"option off: sidebar corners are square again");
}

// The side chat is a card, so it never goes edge-to-edge and never counts as full screen.
static void TestChatCard(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(1440, 900), YES);
    Fixture f = MakeFixture(window, NSMakeRect(220, 6, 1214, 888));
    f.chatHost.hidden = NO;
    Check(DPChatCard(f.container) == f.chatHost, @"the side chat is found");
    Check(!DPFullScreen(f.container), @"a chat card container is never treated as full screen");
    f.container.frame = NSMakeRect(220, 6, 1214, 888);
    Check(NSEqualRects(f.container.frame, NSMakeRect(220, 6, 1214, 888)), @"the chat card keeps Dia's padding in full screen");
    DPRestyleContainer(f.container);
    Check(DPCornersRound(f.rounded.layer, NO) && DPCornersRound(f.rounded.layer, YES), @"the chat card keeps round corners in full screen");

    f.chatHost.hidden = YES;
    f.container.frame = NSMakeRect(220, 6, 1214, 888);
    Check(NSEqualRects(f.container.frame, NSMakeRect(220, 0, 1220, 900)), @"closing the chat goes edge-to-edge again");
}

// Popovers follow the page, and stay put while the page is padded.
static void TestPopover(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(900, 600), NO);
    Fixture f = MakeFixture(window, NSMakeRect(6, 6, 888, 588));
    _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView *popover =
        [[_TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView alloc] initWithFrame:NSMakeRect(100, 500, 200, 200)];
    [window.contentView addSubview:popover];

    popover.frame = NSMakeRect(100, 500, 200, 200);
    Check(NSEqualRects(popover.frame, NSMakeRect(100, 500, 200, 200)), @"windowed: the popover stays where Dia put it");

    SetFullScreen(window, YES);
    f.container.frame = NSMakeRect(6, 6, 888, 588);
    popover.frame = NSMakeRect(100, 500, 200, 200);
    Check(NSEqualRects(popover.frame, NSMakeRect(106, 494, 200, 200)), @"full screen: the popover follows the page");

    SetFullScreen(window, NO);
    f.container.frame = NSMakeRect(6, 6, 888, 588);
    popover.frame = NSMakeRect(106, 494, 200, 200);
    Check(NSEqualRects(popover.frame, NSMakeRect(100, 500, 200, 200)), @"back to windowed: the popover returns to Dia's origin");
}

// Pausing every tweak has to leave Dia exactly as it found it.
static void TestPauseTweaks(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(900, 600), NO);
    Fixture f = MakeFixture(window, NSMakeRect(220, 6, 674, 588));
    SetFullScreen(window, YES);
    f.container.frame = NSMakeRect(220, 6, 674, 588);
    DPRestyleContainer(f.container);
    Check(!DPCornersRound(f.rounded.layer, NO), @"full screen squares the corners before pausing");

    DPPaused = YES;
    DPEdgeToEdge.on = NO;
    DPEdgeToEdge.progress = 0;
    DPFullScreenOnly.on = NO;
    DPFullScreenOnly.progress = 0;
    DPSquareSidebarCorners.on = NO;
    DPSquareSidebarCorners.progress = 0;
    Relayout(&DPEdgeToEdge);
    Relayout(&DPFullScreenOnly);
    Check(NSEqualRects(f.container.frame, NSMakeRect(220, 6, 674, 588)), @"paused: the frame is Dia's again");
    Check(f.container->cornerRadius == 10, @"paused: the corner radius ivar is Dia's again");
    Check(f.rounded.layer.cornerCurve == kCACornerCurveCircular, @"paused: the corner curve is Dia's again");
    Check(DPCornersRound(f.rounded.layer, NO) && DPCornersRound(f.rounded.layer, YES), @"paused: all four corners are round again");
    DPPaused = NO;
}

// The option's own check: a windowed page must be exactly where Dia put it.
static void TestVerify(void) {
    SetPatches(YES, YES);
    _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(900, 600), NO);
    Fixture f = MakeFixture(window, NSMakeRect(220, 6, 674, 588));
    Check(DPFullScreenOnly.verify != NULL, @"the option has a check");
    if (!DPFullScreenOnly.verify) return;
    Check(DPFullScreenOnly.verify(&DPFullScreenOnly) == nil, @"windowed page passes the check");

    // Full screen expands the page, then the window leaves full screen before anything re-applies it.
    SetFullScreen(window, YES);
    f.container.frame = NSMakeRect(220, 6, 674, 588);
    SetFullScreen(window, NO);
    Check([DPFullScreenOnly.verify(&DPFullScreenOnly) isEqual:@"a windowed page is still edge-to-edge"],
          @"an inset windowed page fails the check");

    Relayout(&DPFullScreenOnly);
    Check(DPFullScreenOnly.verify(&DPFullScreenOnly) == nil, @"re-applying the frame clears the check");

    DPFullScreenOnly.on = NO;
    f.container.frame = NSMakeRect(220, 0, 680, 600);
    Check(DPFullScreenOnly.verify(&DPFullScreenOnly) == nil, @"the check stays quiet while the option is off");
    DPFullScreenOnly.on = YES;
    DPEdgeToEdge.on = NO;
    Check(DPFullScreenOnly.verify(&DPFullScreenOnly) == nil, @"the check stays quiet while edge-to-edge is off");
    DPEdgeToEdge.on = YES;
}

// A window that closes must not leave anything behind.
static void TestWindowClose(void) {
    SetPatches(YES, YES);
    NSUInteger before = DPContainers.allObjects.count;
    __weak NSView *weakContainer = nil;
    @autoreleasepool {
        _TtC6Window14PlatformWindow *window = MakeWindow(NSMakeSize(900, 600), YES);
        Fixture f = MakeFixture(window, NSMakeRect(220, 6, 674, 588));
        f.container.frame = NSMakeRect(220, 6, 674, 588);
        weakContainer = f.container;
        Check([DPContainers containsObject:f.container], @"the container is tracked");
        [window close];
        [f.container removeFromSuperview];
    }
    Check(weakContainer == nil, @"a closed window's container is released");
    Check(DPContainers.allObjects.count == before, @"and drops out of the weak table");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification object:nil];
    DrainMain();
    Check(DPContainers.allObjects.count == before, @"a late full-screen notification finds nothing to touch");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPEdgeToEdge.install();
        TestPerWindowIsolation();
        TestScreenSizedWindowTransition();
        TestLiveToggle();
        TestSquareCorners();
        TestChatCard();
        TestPopover();
        TestPauseTweaks();
        TestVerify();
        TestWindowClose();
    }
    if (failures) return 1;
    puts("PASS: per-window full-screen edge-to-edge, transitions, live toggles, corners, chat card, popover, pause, and verify");
    return 0;
}

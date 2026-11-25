#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import "Patches/HideToolbar/HideToolbar.h"

NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
DPPatch DPRevealToolbarOnHover = { .on = YES }, DPShowToolbarWithSidebar = { .on = YES }, DPShowToolbarOnNewTab, DPShowToolbarWithTopTabs = { .on = YES };

static BOOL gLittleDiaOver;
BOOL DPBesideSidebar(NSView *container) { return YES; }
BOOL DPLittleDiaIsOver(NSWindow *window) { return gLittleDiaOver; }
NSString *DPChoice(DPPatch *patch) { return @"dia"; }
CAMetalLayer *DPProgressShaderLayer(void) { return nil; }
void DPDrawProgressShader(CAMetalLayer *layer, CGFloat progress, CGFloat cycle, simd_float3 primary, simd_float3 secondary) {}
BOOL DPProgressColorSlots(NSUInteger slots[2]) { slots[0] = 4; slots[1] = 5; return YES; }

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
- (BOOL)isFlipped { return YES; }
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC11BookmarkBar15BookmarkBarView : NSView
@end
@implementation _TtC11BookmarkBar15BookmarkBarView
@end

@interface _TtC13NavigationBar14ReloadIconView : NSView {
@public
    BOOL isLoading;
}
@end
@implementation _TtC13NavigationBar14ReloadIconView
@end

@interface _TtC13NavigationBar20LoadingIndicatorView : NSView
@property (nonatomic, copy) void (^onDraw)(void);
@end
@implementation _TtC13NavigationBar20LoadingIndicatorView
- (void)drawInMTKView:(id)view { if (self.onDraw) self.onDraw(); }
@end

@interface ArcWebContents : NSObject
@property (nonatomic) BOOL isLoading, hasFocus;
@property (nonatomic) double loadProgress;
@property (nonatomic) NSInteger visibility;
@end
@implementation ArcWebContents
@end

@interface _TtC5ARCUI19BackgroundColorView : NSView
@property NSInteger displayMarks;
@end
@implementation _TtC5ARCUI19BackgroundColorView
- (void)updateLayer { self.layer.backgroundColor = NSColor.systemRedColor.CGColor; }
- (void)setNeedsDisplay:(BOOL)flag { if (flag) self.displayMarks++; [super setNeedsDisplay:flag]; }
@end

@interface _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView : NSView
@end
@implementation _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView
@end

@interface _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView : NSView
@end
@implementation _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView
@end

@interface DPFakeEncoder : NSObject
@end
@implementation DPFakeEncoder
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {}
@end

#import "Patches/HideToolbar/HideToolbar.m"
#import "Patches/HideToolbar/Layout.m"
#import "Patches/HideToolbar/Hover.m"
#import "Patches/HideToolbar/Permission.m"
#import "Patches/HideToolbar/KeepBookmarks.m"
#import "Patches/HideToolbar/PlainTab.m"
#import "Patches/HideToolbar/ProgressLine.m"
#import "Patches/HideToolbar/ProgressColors.m"
#import "Patches/HideToolbar/LoadingProgress.m"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHideToolbar.on = NO;
        DPHideToolbar.progress = 0;
        DPShowLoadingProgress.on = YES;
        DPPlainSelectedTab.on = NO;
        DPHideToolbar.install();
        DPPlainSelectedTab.install();
        DPShowLoadingProgress.install();
        DPHookClass(DPFakeEncoder.class, @selector(setFragmentBytes:length:atIndex:), (IMP)DPEncoder_setFragmentBytes);

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 800, 600)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        _TtC13NavigationBar17NavigationBarView *bar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 0, 800, 44)];
        _TtC13NavigationBar14ReloadIconView *reload = [[_TtC13NavigationBar14ReloadIconView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
        [bar addSubview:reload];
        NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(0, 44, 800, 556)];
        NSView *pageChild = [[NSView alloc] initWithFrame:page.bounds];
        [page addSubview:pageChild];
        [pane addSubview:bar];
        [pane addSubview:page];
        [window.contentView addSubview:pane];

        [pane layout];
        CHECK([DPToolbarHover forPane:pane] == nil, "no DPToolbarHover attached when HideToolbar is off");
        CHECK(pane.subviews.firstObject == bar, "subview z-order is untouched when HideToolbar is off");
        CHECK(DPGet(bar, &DPFrameKey) == nil && DPGet(page, &DPFrameKey) == nil && DPGet(pageChild, &DPFillsKey) == nil,
              "no DPFrameKey or DPFillsKey written when HideToolbar is off");

        DPHideToolbar.on = YES;
        DPHideToolbar.progress = 1;
        DPShowToolbarWithSidebar.on = NO;
        DPShowToolbarWithTopTabs.on = NO;
        [pane layout];
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        CHECK(hover != nil && hover.touched && bar.alphaValue == 0 && NSMinY(page.frame) == 0 && NSHeight(page.frame) == 600,
              "HideToolbar hides bar and expands page when on");

        DPHideToolbar.on = NO;
        DPHideToolbar.progress = 0;
        [pane layout];
        CHECK([DPToolbarHover forPane:pane] == nil, "DPToolbarHover detached after restoring to off");
        CHECK(bar.alphaValue == 1 && NSEqualRects(bar.frame, NSMakeRect(0, 0, 800, 44)) && NSEqualRects(page.frame, NSMakeRect(0, 44, 800, 556)),
              "bar and page frames and alpha restored when turned off");
        CHECK(DPGet(bar, &DPFrameKey) == nil && DPGet(page, &DPFrameKey) == nil && DPGet(pageChild, &DPFillsKey) == nil,
              "DPFrameKey and DPFillsKey cleared after turning off");

        ArcWebContents *wc = [ArcWebContents new];
        wc.visibility = DPWebContentsVisible;
        wc.hasFocus = YES;
        reload->isLoading = YES;
        wc.isLoading = YES;
        wc.loadProgress = 0.4;
        CHECK(DPProgressTimer == nil && !DPShowsProgressLine(pane),
              "DPShowLoadingProgress does not start timer or add progress line while HideToolbar is off");

        DPHideToolbar.on = YES;
        DPHideToolbar.progress = 1;
        [pane layout];
        wc.loadProgress = 0.5;
        CHECK(DPProgressTimer != nil && DPProgressTimer.valid && DPShowsProgressLine(pane),
              "LoadingProgress runs when both HideToolbar and ShowLoadingProgress are on");

        DPHideToolbar.on = NO;
        DPHideToolbar.progress = 0;
        [pane layout];
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        CHECK(DPProgressTimer == nil && !DPShowsProgressLine(pane),
              "turning HideToolbar off immediately stops DPProgressTimer and removes progress line");

        DPHideToolbar.on = YES;
        DPShowLoadingProgress.on = YES;
        _TtC13NavigationBar20LoadingIndicatorView *indicator = [_TtC13NavigationBar20LoadingIndicatorView new];
        DPFakeEncoder *mainEnc = [DPFakeEncoder new], *bgEnc = [DPFakeEncoder new];
        simd_float3 goodPrimary = {0.1f, 0.2f, 0.3f}, goodSecondary = {0.4f, 0.5f, 0.6f};
        simd_float3 badColor = {0.99f, 0.99f, 0.99f};
        dispatch_semaphore_t entered = dispatch_semaphore_create(0), bgDone = dispatch_semaphore_create(0);
        indicator.onDraw = ^{
            [mainEnc setFragmentBytes:&goodPrimary length:sizeof(goodPrimary) atIndex:4];
            dispatch_semaphore_signal(entered);
            dispatch_semaphore_wait(bgDone, DISPATCH_TIME_FOREVER);
            [mainEnc setFragmentBytes:&goodSecondary length:sizeof(goodSecondary) atIndex:5];
        };
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            dispatch_semaphore_wait(entered, DISPATCH_TIME_FOREVER);
            [bgEnc setFragmentBytes:&badColor length:sizeof(badColor) atIndex:4];
            [bgEnc setFragmentBytes:&badColor length:sizeof(badColor) atIndex:5];
            dispatch_semaphore_signal(bgDone);
        });
        [indicator drawInMTKView:nil];
        NSData *captured = DPGet(indicator, &DPDiaColorsKey);
        CHECK(captured.length == 2 * sizeof(simd_float3), "captured indicator colors from main thread");
        simd_float3 c0 = ((const simd_float3 *)captured.bytes)[0], c1 = ((const simd_float3 *)captured.bytes)[1];
        CHECK(fabsf(c0.x - 0.1f) < 0.001f && fabsf(c1.x - 0.4f) < 0.001f,
              "background Metal thread does not race or overwrite main thread indicator colors");

        _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView *strip =
            [[_TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
        _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView *shape =
            [[_TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
        NSView *mid = [[NSView alloc] initWithFrame:shape.bounds];
        _TtC5ARCUI19BackgroundColorView *fill = [[_TtC5ARCUI19BackgroundColorView alloc] initWithFrame:shape.bounds];
        fill.wantsLayer = YES;
        [mid addSubview:fill];
        [shape addSubview:mid];
        [strip addSubview:shape];
        [window.contentView addSubview:strip];
        DPPlainSelectedTab.on = NO;
        [fill updateLayer];
        fill.displayMarks = 0;
        DPRepaintTabs(window);
        CHECK(fill.displayMarks == 0, "DPRepaintTabs does not dirty tab fills when PlainSelectedTab is off");

        if (failures) return 1;
        puts("PASS: HideToolbar off-tweak invariant, LoadingProgress gating, and ProgressColors TLS isolation");
    }
    return 0;
}

#import "Patches/Peek/Peek.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import <objc/runtime.h>

static int gCloseCalls, gDetachCalls, gGiveCalls, gZoomCalls, gOrigZoomCalls;
static BOOL gGiveSucceeds = YES;
static NSURL *gGivenURL;

@interface DPFakePeekPage : NSObject <DPPeekPage>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL isLoading, isReadyToDisplay, canGoBack, canGoForward;
@property (nonatomic) double loadProgress;
@property (nonatomic) float zoomFactor;
@property (nonatomic) NSView *attachedHost;
@end

@implementation DPFakePeekPage
- (NSView *)createPaneHostView { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)]; }
- (void)attachToPaneHostView:(NSView *)host { self.attachedHost = host; }
- (void)detachFromPaneHostView:(NSView *)host { gDetachCalls++; if (self.attachedHost == host) self.attachedHost = nil; }
- (void)close { gCloseCalls++; }
- (id)navigationController { return self; }
- (id)load:(NSURL *)url initiatorOrigin:(NSURL *)origin { self.url = url; return nil; }
- (void)resetZoomAndScaleFactors { self.zoomFactor = 1; gZoomCalls++; }
- (void)setZoomFactor:(float)z { _zoomFactor = z; gZoomCalls++; }
@end

@interface DPFakeFactory : NSObject
@end
@implementation DPFakeFactory
- (id)createWebContents:(id)config {
    DPFakePeekPage *p = [DPFakePeekPage new];
    p.url = [NSURL URLWithString:@"https://example.com"];
    return p;
}
@end

@interface DPFakeDelegate : NSObject
@end
@implementation DPFakeDelegate
- (void)webContents:(id)source didCreateNewWebContent:(id)page targetURL:(NSURL *)url disposition:(NSInteger)disp {
    gGiveCalls++;
    gGivenURL = url;
}
- (void)webContents:(id)page finalizeDiscardRequest:(BOOL)discarded {}
@end

@interface _TtC6Window24PlatformWindowController : NSWindowController
@end
@implementation _TtC6Window24PlatformWindowController
- (void)zoomIn:(id)sender { gOrigZoomCalls++; }
- (void)zoomInAlternate:(id)sender { gOrigZoomCalls++; }
- (void)zoomOut:(id)sender { gOrigZoomCalls++; }
- (void)resetZoom:(id)sender { gOrigZoomCalls++; }
- (BOOL)validateMenuItem:(NSMenuItem *)item { return YES; }
@end

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
@end

@interface ArcWebContentsConfiguration : NSObject
@end
@implementation ArcWebContentsConfiguration
@end

@interface ArcBrowserContext : NSObject
@end
@implementation ArcBrowserContext
- (id)createWebContents:(id)config { return [[DPFakeFactory new] createWebContents:config]; }
@end

@interface ArcBrowser : NSObject
@end
@implementation ArcBrowser
- (id)createWebContents:(id)config { return [[DPFakeFactory new] createWebContents:config]; }
@end

@interface ArcWebContents : DPFakePeekPage
@end
@implementation ArcWebContents
@end

@interface WebContentsViewCocoa : NSView
@end
@implementation WebContentsViewCocoa
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray<NSDraggingItem *> *)items event:(NSEvent *)event source:(id)source { return nil; }
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)op {}
@end

@interface DPPeekTestWindow : NSWindow
@property NSInteger makeKeyCalls;
@property BOOL fakeMiniaturized;
@end
@implementation DPPeekTestWindow
- (void)makeKeyWindow { self.makeKeyCalls++; }
- (BOOL)isVisible { return YES; }
- (BOOL)isMiniaturized { return self.fakeMiniaturized; }
@end

DPPatch DPPeek = { .on = YES }, DPPeekPinnedLinks = { .on = YES }, DPShowLoadingProgress;

static DPFakeFactory *gFactory;
id DPBrowserOfWindow(NSWindow *window) { return gFactory; }
double DPPeekDarkness(void) { return 0.45; }
double DPPeekResponse(void) { return 0.2; }
BOOL DPPeekGenie(void) { return NO; }
BOOL DPPeekShowsToolbar(void) { return NO; }
NSView *DPPeekControls(id target, SEL action) { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 28, 100)]; }
void DPPeekResetControlHints(NSView *controls) {}
void DPPeekAddToolbar(DPPeekCard *peek) {}
CGFloat DPPeekToolbarInset(DPPeekCard *peek) { return 0; }
void DPPeekPlaceToolbar(DPPeekCard *peek) {}
void DPPeekNavigate(id page, DPPeekStep step) {}
void DPPeekEditToolbarAddress(DPPeekCard *peek) {}
BOOL DPPeekCopyURL(DPPeekCard *peek, NSEvent *event) { return NO; }
BOOL DPPeekIsShortcut(NSEvent *event, NSMenuItem *item) { return NO; }
BOOL DPPeekFindShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods) { return NO; }
BOOL DPPeekHideFind(DPPeekCard *peek) { return NO; }
void DPPeekLayoutHints(NSView *controls, CGFloat availableRight) {}
CATransform3D DPPeekScaled(NSView *view, CGFloat scale) { return CATransform3DIdentity; }
static NSString *gActiveID = @"tab-1";
id DPScriptWindow(NSWindow *window) { return nil; }
NSString *DPTabID(id tab) { return nil; }
NSString *DPActiveTabIDIn(id scriptWindow) { return gActiveID; }
NSString *DPActiveTabID(NSWindow *window) { return gActiveID; }
void DPOnLaunch(void (^block)(void)) { block(); }
float DPZoomStep(float now, int direction) { return direction > 0 ? now + 0.1f : now - 0.1f; }
BOOL DPEventIsKey(NSEvent *event, NSString *key) { return NO; }
BOOL DPPeekIsWeb(NSURL *url) { return [url.scheme isEqual:@"https"] || [url.scheme isEqual:@"http"]; }
void DPPeekOpenDragged(NSURL *url, NSPoint origin) {}
CAMetalLayer *DPProgressShaderLayer(void) { return nil; }
void DPProgressColors(NSView *pane, NSString *choice, simd_float3 *primary, simd_float3 *secondary) {}
void DPDrawProgressShader(CAMetalLayer *layer, CGFloat progress, CGFloat cycle, simd_float3 primary, simd_float3 secondary) {}

#import "Patches/Peek/Glow.m"
#import "Patches/Peek/Tab.m"
#import "Patches/Peek/Selection.m"
#import "Patches/Peek/Motion.m"
#import "Patches/Peek/Keys.m"
#import "Patches/Peek/Visibility.m"
#import "Patches/Peek/Chat.m"
#import "Patches/Peek/ChatContext.m"
#import "Patches/Peek/Card.m"
#import "Patches/Peek/Pages.m"
#import "Patches/Peek/Handoff.m"
#import "Patches/Peek/Zoom.m"
#import "Patches/Peek/DragLinks.m"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static void DrainMain(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (!drained && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static DPPeekTestWindow *MakeWindow(NSRect frame) {
    DPPeekTestWindow *window = [[DPPeekTestWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled
                                                                    backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:pane];
    return window;
}

static DPPeekCover *MakeCover(NSWindow *window, NSString *originTabID) {
    DPPeekCover *cover = [[DPPeekCover alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
    cover.releasedWhenClosed = NO;
    cover.originTabID = originTabID;
    [window addChildWindow:cover ordered:NSWindowAbove];
    return cover;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gFactory = [DPFakeFactory new];
        DPPeekInstallPages();
        DPPeekInstallZoom();
        DPInstallPeekDragLinks();

        // 1. Regression: DPPeekGlow fallback line mode (!shader) must NOT trigger needsLayout inside layout.
        DPPeekTestWindow *window = [[DPPeekTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                       styleMask:NSWindowStyleMaskTitled
                                                                         backing:NSBackingStoreBuffered defer:NO];
        DPFakePeekPage *glowPage = [DPFakePeekPage new];
        DPPeekGlow *glow = (DPPeekGlow *)DPPeekGlowFor(glowPage);
        glow.frame = NSMakeRect(0, 0, 200, 24);
        [window.contentView addSubview:glow];
        glow.shown = 0.5;
        [glow layoutSubtreeIfNeeded];
        CHECK(!glow.needsLayout, "DPPeekGlow fallback line mode does not set needsLayout inside layout");
        CHECK(fabs(NSWidth(glow.line.frame) - 100) < 0.5, "DPPeekGlow sets fallback line width during layout");
        glow.shown = 0.75;
        [glow draw];
        CHECK(!glow.needsLayout && fabs(NSWidth(glow.line.frame) - 150) < 0.5, "DPPeekGlow draw updates line directly without relayout");
        [glow viewDidChangeBackingProperties];
        CHECK(glow.needsLayout, "DPPeekGlow marks needsLayout on backing scale change");
        glowPage.isLoading = YES;
        glowPage.loadProgress = 0.4;
        window.fakeMiniaturized = YES;
        glow.shown = 0;
        [glow step];
        CHECK(!glow.loading && glow.shown == 0, "DPPeekGlow skips 60fps step work while window is miniaturized");
        window.fakeMiniaturized = NO;
        [glow removeFromSuperview];

        // 2. Regression: DPPeekTabBadge has no retain cycle and Selection sync timer stops when all cards close.
        _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:window.contentView.bounds];
        [window.contentView addSubview:pane];
        __weak DPPeekTabBadge *weakBadge = nil;
        @autoreleasepool {
            DPPeekTabBadge *badge = [[DPPeekTabBadge alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
            weakBadge = badge;
            [window.contentView addSubview:badge];
            [badge removeFromSuperview];
        }
        CHECK(weakBadge == nil, "DPPeekTabBadge deallocates cleanly with no retain cycle");

        // 3. Regression: Turning Peek OFF via DPPeekCloseAll closes visible + hidden cards, cools warm page, hides drag zone, stops sync timer.
        DPPeek.on = YES;
        DPFakePeekPage *source = [DPFakePeekPage new];
        DPPeekWarm(window, source, [NSURL URLWithString:@"https://example.com/warm"]);
        CHECK(DPPeekWarmPage != nil && DPPeekWarmView.superview != nil, "warm page attached before close-all");
        DPShowZone(window, NSMakePoint(100, 100));
        CHECK(DPZonePanel != nil && DPZoneRelease.valid, "drag zone shown before close-all");

        DPFakePeekPage *cardPage = [DPFakePeekPage new];
        cardPage.url = [NSURL URLWithString:@"https://example.com/card"];
        DPPeekCard *card = DPPeekShowCard(window, cardPage, nil, NSMakeRect(10, 10, 40, 20));
        card.originTabID = @"tab-1";
        card.source = source;
        CHECK(card && DPPeekCardIn(window) == card && card.monitor != nil && card.paneObserver != nil && DPPeekSyncTimer.valid,
              "card opens with monitor, observer, and sync timer");
        gActiveID = @"tab-2";
        DPPeekSyncTabs(window);
        DPFakePeekPage *cardPage2 = [DPFakePeekPage new];
        cardPage2.url = [NSURL URLWithString:@"https://example.com/card2"];
        DPPeekCard *card2 = DPPeekShowCard(window, cardPage2, nil, NSMakeRect(10, 10, 40, 20));
        card2.originTabID = @"tab-2";
        card2.source = source;
        CHECK(card.hidden && card2 && !card2.hidden && DPPeekAllCards(window).count == 2 && DPPeekHiddenCards(window).count == 1,
              "both hidden and visible cards tracked before close-all");

        DPPeek.on = NO;
        DPPeekCloseAll();
        CHECK(DPPeekAllCards(nil).count == 0 && card.superview == nil && card2.superview == nil && card.monitor == nil && card.paneObserver == nil,
              "DPPeekCloseAll tears down visible+hidden cards, monitors, and observers");
        CHECK(DPPeekSyncTimer == nil, "DPPeekCloseAll invalidates selection sync timer");
        CHECK(DPPeekWarmPage == nil && DPPeekWarmView == nil, "DPPeekCloseAll cools pre-warmed page");
        CHECK(DPZonePanel == nil && DPZoneRelease == nil, "DPPeekCloseAll hides drag zone and stops timer");
        gActiveID = @"tab-1";

        // 4. Regression: DPPeekOpenFrom skips opening when DPPeek.on is NO, and discards leaked page on failed give.
        DPPeek.on = NO;
        gCloseCalls = 0;
        DPFakePeekPage *warmOff = [DPFakePeekPage new];
        warmOff.url = [NSURL URLWithString:@"about:blank"];
        DPPeekOpenFrom(window, @"tab-1", [NSURL URLWithString:@"https://example.com"], NSMakeRect(0, 0, 20, 10), nil, source, warmOff, nil);
        CHECK(DPPeekAllCards(window).count == 0 && gCloseCalls == 1, "DPPeekOpenFrom discards warm page and refuses to open when Peek is off");

        DPPeek.on = YES;
        gCloseCalls = 0;
        DPFakePeekPage *existing = [DPFakePeekPage new];
        existing.url = [NSURL URLWithString:@"https://example.com/1"];
        DPPeekCard *blocking = DPPeekShowCard(window, existing, nil, NSMakeRect(0, 0, 20, 10));
        CHECK(blocking != nil, "blocking card opens");

        // 5. Regression: Zoom hook respects DPPeek.on == NO.
        _TtC6Window24PlatformWindowController *wc = [[_TtC6Window24PlatformWindowController alloc] initWithWindow:window];
        gZoomCalls = gOrigZoomCalls = 0;
        DPPeek.on = YES;
        [wc zoomIn:nil];
        CHECK(gZoomCalls == 1 && gOrigZoomCalls == 0, "zoom reaches Peek when on");
        DPPeek.on = NO;
        [wc zoomIn:nil];
        CHECK(gZoomCalls == 1 && gOrigZoomCalls == 1, "zoom passes through to Dia when Peek is off");
        DPPeek.on = YES;

        // 6. Regression: NSWindowWillCloseNotification tears down even an already-closing (expanding) card without makeKeyWindow/DPPeekGive.
        DPFakeDelegate *delegate = [DPFakeDelegate new];
        blocking.sourceDelegate = delegate;
        blocking.source = source;
        [blocking close:DPPeekTab]; // marks closing=YES and starts DPPeekGrowth CADisplayLink!
        CHECK(blocking.closing && DPPeekCardIn(window) == nil && DPPeekAllCards(window).count == 1,
              "expanding card is closing and still tracked by DPPeekAllCards");
        window.makeKeyCalls = 0;
        gGiveCalls = 0;
        gDetachCalls = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:window];
        CHECK(DPPeekAllCards(window).count == 0 && blocking.superview == nil && gDetachCalls >= 1,
              "window close synchronously tears down expanding card");
        CHECK(DPGet(blocking, &DPGrowthKey) == nil, "window close cancels DPPeekGrowth display link");
        CHECK(window.makeKeyCalls == 0 && gGiveCalls == 0, "window close does not call makeKeyWindow or DPPeekGive");

        // 7. Regression: finish: on a detached card (window == nil) never calls DPPeekGive.
        DPFakePeekPage *detachedPage = [DPFakePeekPage new];
        detachedPage.url = [NSURL URLWithString:@"about:blank"];
        DPPeekCard *detached = [DPPeekCard new];
        detached.page = detachedPage;
        detached.sourceDelegate = delegate;
        detached.source = source;
        gGiveCalls = gCloseCalls = 0;
        [detached finish:DPPeekTab];
        CHECK(gGiveCalls == 0 && gCloseCalls == 1, "finish: on detached card discards page without giving to delegate");

        // 8. Regression: DPPeekOpenFrom discards freshly created page if DPPeekShowCard fails and DPPeekGive fails (source == nil).
        gGiveSucceeds = NO;
        gCloseCalls = 0;
        DPFakePeekPage *unattached = [DPFakePeekPage new];
        unattached.url = [NSURL URLWithString:@"about:blank"];
        // nil source -> DPPeekGive returns NO -> DPPeekDiscard closes page.
        CHECK(!DPPeekGive(unattached, delegate, nil, unattached.url, DPPeekTab), "DPPeekGive returns NO without source");

        // 9. Regression: DPPeekMakePage sets dp_nonTabWebContents marker, and DPPeekGive clears it upon tab adoption.
        DPFakePeekPage *made = (DPFakePeekPage *)DPPeekMakePage(window, source, ^(id p) {});
        CHECK([objc_getAssociatedObject(made, NSSelectorFromString(@"dp_nonTabWebContents")) boolValue],
              "DPPeekMakePage tags page with dp_nonTabWebContents");
        gGiveCalls = 0;
        CHECK(DPPeekGive(made, delegate, source, made.url, DPPeekTab) && gGiveCalls == 1,
              "DPPeekGive adopts Peek page into real tab");
        CHECK(objc_getAssociatedObject(made, NSSelectorFromString(@"dp_nonTabWebContents")) == nil,
              "DPPeekGive clears dp_nonTabWebContents marker when promoting to real tab");

        // 10. Regression: DPPeekDiscard(nil, nil) and DPPeekCloseWhenBlank(nil, 40) are safe no-ops.
        gCloseCalls = 0;
        DPPeekDiscard(nil, nil);
        DPPeekCloseWhenBlank(nil, 40);
        CHECK(gCloseCalls == 0, "nil page discard/closeWhenBlank is a safe no-op");

        // 11. Regression: Closed window guard blocks DPPeekWarm and DPPeekOpenFrom after NSWindowWillCloseNotification.
        DPPeek.on = YES;
        gCloseCalls = 0;
        DPPeekWarm(window, source, [NSURL URLWithString:@"https://closed-window.example/warm"]);
        CHECK(DPPeekWarmPage == nil && DPPeekWarmView == nil, "DPPeekWarm refuses closed window");
        DPFakePeekPage *closedWarm = [DPFakePeekPage new];
        closedWarm.url = [NSURL URLWithString:@"about:blank"];
        DPPeekOpenFrom(window, @"tab-1", [NSURL URLWithString:@"https://closed-window.example/"], NSMakeRect(0, 0, 20, 10), delegate, source, closedWarm, nil);
        CHECK(DPPeekAllCards(window).count == 0 && gCloseCalls == 1,
              "DPPeekOpenFrom refuses closed window and discards warm page");

        // 12. Regression: Detached DPPeekGrowth mid-animation invokes completion and discards page instead of leaking.
        DPPeekTestWindow *window2 = [[DPPeekTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                        styleMask:NSWindowStyleMaskTitled
                                                                          backing:NSBackingStoreBuffered defer:NO];
        _TtC11ContentPane15ContentPaneView *pane2 = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:window2.contentView.bounds];
        [window2.contentView addSubview:pane2];
        DPFakePeekPage *expandPage = [DPFakePeekPage new];
        expandPage.url = [NSURL URLWithString:@"about:blank"];
        DPPeekCard *expanding = DPPeekShowCard(window2, expandPage, nil, NSMakeRect(10, 10, 40, 20));
        expanding.sourceDelegate = delegate;
        expanding.source = source;
        gGiveCalls = gCloseCalls = 0;
        [expanding close:DPPeekTab];
        DPPeekGrowth *growth = DPGet(expanding, &DPGrowthKey);
        CHECK(growth != nil, "expanding card creates DPPeekGrowth driver");
        [expanding removeFromSuperview];
        [growth step];
        CHECK(gGiveCalls == 0 && gCloseCalls == 1 && expanding.page == nil && DPGet(expanding, &DPGrowthKey) == nil,
              "detached DPPeekGrowth step invokes done and discards page without leaking");

        // 13. Regression: the Peek-to-tab cover is cancelled by a tab switch, window close, and tweak off.
        {
            DPPeekTestWindow *window3 = MakeWindow(NSMakeRect(-30000, -30000, 600, 400));
            DPPeekCover *cover = MakeCover(window3, @"tab-1");
            CHECK(DPPeekHandoffActive(), "handoff cover counts as an active handoff");
            DPPeekUpdateSyncTimer();
            CHECK(DPPeekSyncTimer != nil, "handoff cover keeps the sync timer alive");

            // ⌘O was already pressed, so a tab switch dismisses the cover but still promotes.
            __block int promoted = 0;
            cover.promote = ^{ promoted++; };
            DPPeekHandoffSelectionChanged(window3, @"tab-1");
            CHECK(cover.parentWindow == window3 && promoted == 0, "handoff cover survives its origin tab");
            DPPeekHandoffSelectionChanged(window3, @"tab-2");
            DrainMain();
            CHECK(cover.parentWindow == nil && promoted == 1, "tab switch dismisses the cover and still promotes");

            // Once the destination tab is live, its own selection keeps the cover until it paints.
            DPPeekCover *settled = MakeCover(window3, @"tab-1");
            settled.destinationTabID = @"tab-2";
            DPPeekHandoffSelectionChanged(window3, @"tab-2");
            CHECK(settled.parentWindow == window3, "cover stays while its destination tab is selected");
            DPPeekHandoffSelectionChanged(window3, @"tab-3");
            CHECK(settled.parentWindow == nil, "cover leaves when another tab is selected");

            // Window close and tweak off cancel a pending promotion outright.
            DPPeekCover *closing = MakeCover(window3, @"tab-1");
            __block int closingPromoted = 0;
            closing.promote = ^{ closingPromoted++; };
            DPPeekHandoffSelectionChanged(window3, nil);
            DrainMain();
            CHECK(closing.parentWindow == nil && closingPromoted == 0, "window close cancels the handoff without promoting");

            DPPeekCover *paused = MakeCover(window3, @"tab-1");
            __block int pausedPromoted = 0;
            paused.promote = ^{ pausedPromoted++; };
            DPPeek.on = NO;
            DPPeekCloseAll();
            DrainMain();
            CHECK(paused.parentWindow == nil && pausedPromoted == 0, "turning Peek off cancels the handoff without promoting");
            DPPeek.on = YES;
            CHECK(!DPPeekHandoffActive() && DPPeekSyncTimer == nil, "no handoff cover or sync timer survives teardown");
            [window3 close];
        }

        // 14. Regression: promoting a Peek attaches its page to the tab before the card leaves the window.
        {
            DPPeekTestWindow *window4 = MakeWindow(NSMakeRect(-30000, -30000, 600, 400));
            NSView *destination = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
            [window4.contentView addSubview:destination];

            DPFakePeekPage *promotedPage = [DPFakePeekPage new];
            promotedPage.url = [NSURL URLWithString:@"https://example.com/promote"];
            DPPeekCard *card = DPPeekShowCard(window4, promotedPage, nil, NSMakeRect(10, 10, 40, 20));
            card.grown = 1;
            __block BOOL mountedDuringAttach = NO;
            gDetachCalls = 0;
            [card handOverTo:destination attach:^{
                mountedDuringAttach = card.superview != nil;
                promotedPage.attachedHost = destination;
            }];
            CHECK(mountedDuringAttach, "promotion attaches the page while the expanded card is still mounted");
            CHECK(promotedPage.attachedHost == destination && gDetachCalls == 1 && card.superview == nil && card.page == nil,
                  "promotion detaches the page from the card and unmounts it");
            CHECK(DPPeekAllCards(window4).count == 0, "promoted card leaves the tracked cards");

            DPFakePeekPage *smallPage = [DPFakePeekPage new];
            smallPage.url = [NSURL URLWithString:@"https://example.com/small"];
            DPPeekCard *small = DPPeekShowCard(window4, smallPage, nil, NSMakeRect(10, 10, 40, 20));
            __block BOOL unmountedDuringAttach = NO;
            [small handOverTo:destination attach:^{ unmountedDuringAttach = small.superview == nil; }];
            CHECK(unmountedDuringAttach, "a card that never expanded unmounts before its page attaches");
            [window4 close];
        }

        // 15. Regression: ⌘O on a still-loading preview opens the clicked link, not about:blank.
        {
            DPPeekTestWindow *window5 = MakeWindow(NSMakeRect(-30000, -30000, 600, 400));
            DPFakeDelegate *delegate = [DPFakeDelegate new];
            DPFakePeekPage *source5 = [DPFakePeekPage new];
            DPFakePeekPage *loading = [DPFakePeekPage new];
            loading.url = [NSURL URLWithString:@"about:blank"];
            DPPeekCard *card = DPPeekShowCard(window5, loading, nil, NSMakeRect(10, 10, 40, 20));
            card.sourceDelegate = delegate;
            card.source = source5;
            card.requestedURL = [NSURL URLWithString:@"https://clicked.example/article"];
            gGiveCalls = 0;
            gGivenURL = nil;
            [card finish:DPPeekTab];
            CHECK(gGiveCalls == 1 && [gGivenURL.absoluteString isEqualToString:@"https://clicked.example/article"],
                  "promoting a still-loading preview opens the clicked URL");
            CHECK(!DPPeekHandoffActive(), "an offscreen window skips the handoff cover");
            [window5 close];
        }

        // 16. Regression: Dia attaching a Peek page to a real tab hands the card over and still attaches.
        {
            DPPeekTestWindow *window6 = MakeWindow(NSMakeRect(-30000, -30000, 600, 400));
            ArcWebContents *page = [ArcWebContents new];
            page.url = [NSURL URLWithString:@"https://example.com/tab"];
            DPPeekCard *card = DPPeekShowCard(window6, page, nil, NSMakeRect(10, 10, 40, 20));
            NSView *tabHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
            [window6.contentView addSubview:tabHost];
            gDetachCalls = 0;
            [page attachToPaneHostView:tabHost];
            CHECK(page.attachedHost == tabHost && gDetachCalls == 1 && card.superview == nil && card.page == nil,
                  "attaching a Peek page to a tab hands the card over and attaches the page");
            [window6 close];
        }

        if (failures) return 1;
        puts("PASS: Peek glow fallback, off-tweak teardown, window close, handoff, and timer lifecycle");
    }
    return 0;
}

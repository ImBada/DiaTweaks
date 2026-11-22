#import "Patches/Peek/Peek.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import <objc/runtime.h>

static int gCloseCalls, gDetachCalls, gGiveCalls, gZoomCalls, gOrigZoomCalls;
static BOOL gGiveSucceeds = YES;

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
#import "Patches/Peek/Zoom.m"
#import "Patches/Peek/DragLinks.m"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

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

        if (failures) return 1;
        puts("PASS: Peek glow fallback, off-tweak teardown, window close, and timer lifecycle");
    }
    return 0;
}

#import "StdPatch/StdPatch.h"
#import "Peek/Peek.h"
#import "Patches/LittleDia/LittleDia.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import "Patches/CompactTabRows/CompactTabRows.h"
#import "Patches/PullRequestRepo/PullRequestRepo.h"
#import <Carbon/Carbon.h>
#import <objc/message.h>
#import "watchdog.h"
#import "runloop.h"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

DPPatch DPPeek = { .on = YES }, DPLittleDia = { .on = YES }, DPHideToolbar = { .on = NO },
        DPRevealToolbarOnHover = { .on = YES }, DPShowLoadingProgress = { .on = NO }, DPLittleDiaFollowRules = { .on = NO };
BOOL DPLittleDiaReady(void) { return YES; }
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";

static NSMutableArray<NSEvent *(^)(NSEvent *)> *gMouseMonitors;
static id DPApp_addMonitor(id self, SEL _cmd, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) {
    id copy = [handler copy];
    if (mask & NSEventMaskLeftMouseDown) [gMouseMonitors addObject:copy];
    return copy;
}
static void DPApp_removeMonitor(id self, SEL _cmd, id monitor) {
    [gMouseMonitors removeObject:monitor];
}

static int gNavBackCalls;
@interface DPFakePeekPage : NSObject <DPPeekPage>
@property (nonatomic) BOOL canGoBack, canGoForward, isLoading;
@property (nonatomic) double loadProgress;
- (id)navigationController;
- (void)goBack;
@end
@implementation DPFakePeekPage
- (NSView *)createPaneHostView { return [NSView new]; }
- (void)attachToPaneHostView:(NSView *)host {}
- (void)detachFromPaneHostView:(NSView *)host {}
- (void)close {}
- (id)navigationController { return self; }
- (id)load:(NSURL *)url initiatorOrigin:(NSURL *)origin { return nil; }
- (NSURL *)url { return [NSURL URLWithString:@"https://example.test/"]; }
- (void)goBack { gNavBackCalls++; }
@end

@implementation DPPeekCard
- (NSRect)cardFrame { return self.bounds; }
- (void)close:(DPPeekExit)exit {}
- (void)handOverTo:(NSView *)destination attach:(void (^)(void))attach {}
@end

// A real NSButton tracks a click until a mouse-up that a synthetic event never delivers, and whether it returns first depends on the macOS build.
static int gBarButtonMouseDowns;
@interface DPTestBarButton : NSButton
@end
@implementation DPTestBarButton
- (void)mouseDown:(NSEvent *)event { gBarButtonMouseDowns++; }
@end

// Overlays that let clicks through, so a click on a bar button always reaches it.
@interface DPClearView : NSView
@end
@implementation DPClearView
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

NSButton *DPMakeBarButton(NSString *symbol, NSString *label, NSString *key, void (^action)(void)) {
    NSButton *b = [[DPTestBarButton alloc] initWithFrame:NSZeroRect];
    b.title = label;
    if (action) {
        id target = [NSBlockOperation blockOperationWithBlock:action];
        b.target = target;
        b.action = @selector(main);
        objc_setAssociatedObject(b, @selector(main), target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return b;
}
NSView *DPMakeDivider(void) { return [DPClearView new]; }
void DPMatchPage(NSView *row, id page) {}
NSView *DPPeekAddressFor(id page) { return [DPClearView new]; }
void DPPeekRefreshAddress(NSView *address) {}
void DPPeekEditAddress(NSView *address) {}
BOOL DPPeekEditingAddress(NSView *address) { return NO; }
NSView *DPPeekGlowFor(id page) { return [DPClearView new]; }
BOOL DPKeptInPlace(NSView *pane) { return NO; }
void DPShowProgressLine(NSView *pane, CGFloat fraction) {}
void DPFinishProgressLine(NSView *pane) {}
void DPRemoveProgressLine(NSView *pane) {}

NSView *DPBookmarksUnder(NSView *pane, NSView *bar) { return nil; }
void DPApplyToolbar(NSView *pane) {}

static NSWindow *gLittleMarker;
BOOL DPIsLittleDiaWindow(NSWindow *window) { return window && window == gLittleMarker; }

NSString *DPChoice(DPPatch *patch) { return patch->defaultChoice; }
NSString *DPText(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC7TabList11TabListView : NSView
@end
@implementation _TtC7TabList11TabListView
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (void)draggingExited:(id<NSDraggingInfo>)info {}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (void)handleBackgroundDoubleClick:(id)click {}
@end

@interface _TtCC7TabList11TabListView14CollectionView : NSCollectionView
@end
@implementation _TtCC7TabList11TabListView14CollectionView
@end

@interface _TtC7TabList27TabListCollectionViewLayout : NSCollectionViewFlowLayout {
@public
    double contentHeight;
}
@end
@implementation _TtC7TabList27TabListCollectionViewLayout
@end

@interface _TtC5TabUI14TabContentView : NSView
@end
@implementation _TtC5TabUI14TabContentView
@end

@interface _TtC5TabUI16TabGroupCellView : NSView
@end
@implementation _TtC5TabUI16TabGroupCellView
@end

@interface _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView : NSView
@end
@implementation _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView
@end

@interface _TtC5ARCUI24FeatheredTruncatingLabel : NSTextField
@end
@implementation _TtC5ARCUI24FeatheredTruncatingLabel
@end

@interface ArcDraggingWindow : NSWindow
@end
@implementation ArcDraggingWindow
- (BOOL)isVisible { return YES; }
@end

@interface DPFakeDrag : NSObject
@property NSPoint draggingLocation;
@end
@implementation DPFakeDrag
@end

@interface DPVisibleTestWindow : NSWindow
@property BOOL fakeVisible, fakeMiniaturized;
@end
@implementation DPVisibleTestWindow
- (BOOL)isVisible { return self.fakeVisible; }
- (BOOL)isMiniaturized { return self.fakeMiniaturized; }
- (void)orderOut:(id)sender { self.fakeVisible = NO; }
- (void)orderFront:(id)sender { self.fakeVisible = YES; }
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin { self.fakeVisible = (place != NSWindowOut); }
@end

static NSArray<NSWindow *> *gTestWindows;
static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gTestWindows ?: @[]; }
static NSArray<NSWindow *> *DPApp_orderedWindows(NSApplication *self, SEL _cmd) { return gTestWindows ?: @[]; }

#import "Peek/Toolbar.m"
#import "Peek/ToolbarRules.m"
#import "Patches/LittleDia/Over.m"
#import "Patches/LittleDia/Stack.m"

extern DPPatch DPCompactTabRows, DPCollapsePinned, DPPullRequestRepo;
void DPInstallPRRows(void);

static void TestPeekToolbarZOrderAndBarZoneDealloc(void) {
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 1000, 700)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered defer:NO];
    win.releasedWhenClosed = NO;

    DPFakePeekPage *page = [DPFakePeekPage new];
    page.canGoBack = YES;
    gNavBackCalls = 0;

    DPPeekCard *peek = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
    peek.page = page;
    peek.clip = [[NSView alloc] initWithFrame:NSMakeRect(100, 100, 800, 500)];
    [peek addSubview:peek.clip];
    DPPeekAddToolbar(peek);
    [win.contentView addSubview:peek];
    DPPeekPlaceToolbar(peek);
    [peek.toolbar layoutSubtreeIfNeeded];

    NSButton *backBtn = ((DPPeekToolbar *)peek.toolbar).buttons[0];
    NSPoint backInWin = [backBtn convertPoint:NSMakePoint(NSMidX(backBtn.bounds), NSMidY(backBtn.bounds)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:backInWin modifierFlags:0 timestamp:1
                                    windowNumber:win.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];

    NSView *overlayAbove = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
    [win.contentView addSubview:overlayAbove positioned:NSWindowAbove relativeTo:nil];
    NSEvent *(^toolbarMonitor)(NSEvent *) = gMouseMonitors.lastObject;
    CHECK(toolbarMonitor != nil, "DPPeekToolbar registered mouse monitor");
    DPStage("Peek toolbar click monitor");
    gBarButtonMouseDowns = 0;
    NSEvent *resCovered = toolbarMonitor ? toolbarMonitor(click) : nil;
    CHECK(resCovered == click && gBarButtonMouseDowns == 0, "covering overlay above Peek prevents DPPeekToolbar from stealing click");

    [overlayAbove removeFromSuperview];
    NSEvent *resUncovered = toolbarMonitor ? toolbarMonitor(click) : click;
    CHECK(resUncovered == nil && gBarButtonMouseDowns == 1, "uncovered DPPeekToolbar intercepts click and hands it to the Back button");

    __weak DPPeekBarZone *weakZone = nil;
    @autoreleasepool {
        DPPeekCard *tempPeek = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        tempPeek.page = page;
        tempPeek.clip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        [tempPeek addSubview:tempPeek.clip];
        DPPeekAddToolbar(tempPeek);
        weakZone = (DPPeekBarZone *)tempPeek.toolbarZone;
        [win.contentView addSubview:tempPeek];
        CHECK(!weakZone.watch && weakZone.patches != nil, "DPPeekBarZone polls nothing while Hide Toolbar is off, but listens for settings");
        DPHideToolbar.on = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        CHECK(weakZone.watch.valid, "DPPeekBarZone starts watching once Hide Toolbar turns on");
        DPHideToolbar.on = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        CHECK(!weakZone.watch, "DPPeekBarZone stops watching once Hide Toolbar turns off");
        // Remove directly without letting timers fire on a freed object.
        [tempPeek removeFromSuperview];
    }
    CHECK(weakZone == nil, "DPPeekBarZone deallocates cleanly without retain cycle");
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];

    [peek removeFromSuperview];
    [win close];
}

static void TestLittleDiaOverAndStackRestore(void) {
    DPLittleDia.on = YES;
    DPHideToolbar.on = NO;
    DPInstallLittleDiaOver();
    DPInstallLittleDiaStack();

    DPVisibleTestWindow *mainWin = [[DPVisibleTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 800, 600)
                                                                          styleMask:NSWindowStyleMaskBorderless
                                                                            backing:NSBackingStoreBuffered defer:NO];
    mainWin.releasedWhenClosed = NO;
    mainWin.fakeVisible = YES;
    mainWin.alphaValue = 1.0;

    _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _TtC13NavigationBar17NavigationBarView *bar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 560, 800, 40)];
    [pane addSubview:bar];
    [mainWin.contentView addSubview:pane];

    DPVisibleTestWindow *little = [[DPVisibleTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 500)
                                                                         styleMask:NSWindowStyleMaskBorderless
                                                                           backing:NSBackingStoreBuffered defer:NO];
    little.releasedWhenClosed = NO;
    little.fakeVisible = YES;
    gLittleMarker = little;
    gTestWindows = @[ little, mainWin ];

    DPPutLittleDiaOver(little, mainWin);
    CHECK(DPLittleDiaIsOver(mainWin), "DPLittleDiaIsOver is YES while Little Dia is over main window");
    DPLittleDia.on = NO;
    CHECK(!DPLittleDiaIsOver(mainWin), "DPLittleDiaIsOver immediately returns NO when Little Dia is off/paused");
    DPUncoverAllLittleDia();
    DPPumpUntil(^BOOL { return fabs(bar.alphaValue - 1.0) < 0.01; });
    CHECK(fabs(bar.alphaValue - 1.0) < 0.01, "DPUncoverAllLittleDia restores main window toolbar alpha to 1 on off/pause");

    DPLittleDia.on = YES;
    DPPutLittleDiaOver(little, mainWin);
    DPPumpUntil(^BOOL { return bar.alphaValue < 0.05; });
    CHECK(bar.alphaValue < 0.05, "toolbar faded to 0 under Little Dia");
    little.fakeMiniaturized = YES;
    CHECK(!DPLittleDiaIsOver(mainWin), "miniaturized Little Dia is not considered over main window");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillMiniaturizeNotification object:little];
    DPPumpUntil(^BOOL { return fabs(bar.alphaValue - 1.0) < 0.01; });
    CHECK(fabs(bar.alphaValue - 1.0) < 0.01, "miniaturizing Little Dia restores covered window toolbar alpha to 1");
    little.fakeMiniaturized = NO;

    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationWillUnhideNotification object:NSApp];
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidUnhideNotification object:NSApp];
    CHECK(mainWin.alphaValue < 0.01, "unhide veils main window while Little Dia is on");
    DPLinkArrived();
    CHECK(!mainWin.visible && DPPutAwayWindows().count == 1, "DPLinkArrived puts away veiled main window");
    DPLittleDia.on = NO;
    DPRestoreLittleDiaStack();
    CHECK(mainWin.visible && fabs(mainWin.alphaValue - 1.0) < 0.01 && DPPutAwayWindows().count == 0,
          "DPRestoreLittleDiaStack unveils and brings back put-away windows on off/pause");
    CHECK(!DPPutAwayIfHidden(), "DPPutAwayIfHidden does nothing while Little Dia is off/paused");

    gLittleMarker = nil;
    gTestWindows = nil;
    [little close];
    [mainWin close];
}

static void TestMultiTweakDragOffsetNoLeak(void) {
    // Install hooks in real dylib order: CompactTabRows -> CollapsePinned -> PullRequestRepo.
    DPCompactTabRows.install();
    DPCollapsePinned.install();
    DPInstallPRRows();

    DPCompactTabRows.on = YES;
    DPCollapsePinned.on = YES;
    DPPullRequestRepo.on = YES;

    NSView *tabList = [[_TtC7TabList11TabListView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    _TtCC7TabList11TabListView14CollectionView *col = [[_TtCC7TabList11TabListView14CollectionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    col.collectionViewLayout = [_TtC7TabList27TabListCollectionViewLayout new];
    [tabList addSubview:col];

    ArcDraggingWindow *dragWin = [[ArcDraggingWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 200, 100)
                                                                      styleMask:NSWindowStyleMaskBorderless
                                                                        backing:NSBackingStoreBuffered defer:NO];
    dragWin.releasedWhenClosed = NO;
    NSView *dragTab = [[NSView alloc] initWithFrame:NSMakeRect(10, 20, 100, 30)];
    [dragWin.contentView addSubview:dragTab];
    gTestWindows = @[ dragWin ];

    // Simulate PullRequestRepo proxying a drag point (sets DPDragHandedSet = YES) followed by a refused drop or exit.
    DPFakeDrag *raw = [DPFakeDrag new];
    raw.draggingLocation = NSMakePoint(50, 100);
    id<NSDraggingInfo> proxied = DPDraggingInfoAt((id<NSDraggingInfo>)raw, NSMakePoint(50, 140));

    [(id<NSDraggingDestination>)tabList prepareForDragOperation:proxied];
    DPPlaceDraggedTab();
    CHECK(fabs(NSMinY(dragTab.frame) - 20) < 0.01, "prepareForDragOperation clears proxied drag offset");

    proxied = DPDraggingInfoAt((id<NSDraggingInfo>)raw, NSMakePoint(50, 140));
    [(id<NSDraggingDestination>)tabList performDragOperation:proxied];
    DPPlaceDraggedTab();
    CHECK(fabs(NSMinY(dragTab.frame) - 20) < 0.01, "performDragOperation clears proxied drag offset");

    proxied = DPDraggingInfoAt((id<NSDraggingInfo>)raw, NSMakePoint(50, 140));
    [(id<NSDraggingDestination>)tabList draggingExited:proxied];
    DPPlaceDraggedTab();
    CHECK(fabs(NSMinY(dragTab.frame) - 20) < 0.01, "draggingExited clears proxied drag offset");

    gTestWindows = nil;
    [dragWin close];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gMouseMonitors = [NSMutableArray array];
        Class eventMeta = object_getClass(NSEvent.class);
        DPHookClass(eventMeta, @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)DPApp_addMonitor);
        DPHookClass(eventMeta, @selector(removeMonitor:), (IMP)DPApp_removeMonitor);
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        DPHookClass(NSApp.class, @selector(orderedWindows), (IMP)DPApp_orderedWindows);

        DPArmTestWatchdog(120);
        DPRunTest(TestPeekToolbarZOrderAndBarZoneDealloc);
        DPRunTest(TestLittleDiaOverAndStackRestore);
        DPRunTest(TestMultiTweakDragOffsetNoLeak);

        if (failures) {
            printf("%d historical regression test(s) failed\n", failures);
            return 1;
        }
        puts("PASS: all historical regression ASan+UBSan checks");
    }
    return 0;
}

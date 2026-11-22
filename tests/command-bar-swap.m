#import "Patches/CommandBar/CommandBarSwap.m"
#import "Patches/CommandBar/HideTabButton.m"
#import "Patches/CommandBar/HideTabRows.m"

DPPatch DPCommandBar = { .on = YES };
char DPOverlayKey;
const uintptr_t DPFirstFill = 4;

@implementation DPCommandBarOverlay
- (NSView *)viewUnder:(NSPoint)point { return nil; }
@end

static NSMutableSet<NSString *> *gHidden;
static NSMutableArray<DPCommandBarOverlay *> *gCancelled;
static NSMutableArray<NSEvent *> *gPosted;
static BOOL gHiding = YES, gHoldsSelection;
static int gGiveBackCalls;
static uintptr_t gStyle = 2;
static uint8_t gShape = 0;

BOOL DPHiding(void) { return gHiding; }
BOOL DPHidesTab(NSString *tabID) { return gHiding && tabID && [gHidden containsObject:tabID]; }
@interface TabUI_TabBackgroundView : NSView {
  @public
    uintptr_t style;
    uint8_t shape;
}
@end

uintptr_t *DPSelectionStyle(NSView *background) { return [background isKindOfClass:TabUI_TabBackgroundView.class] ? &((TabUI_TabBackgroundView *)background)->style : &gStyle; }
uint8_t *DPTabShape(NSView *background) { return [background isKindOfClass:TabUI_TabBackgroundView.class] ? &((TabUI_TabBackgroundView *)background)->shape : &gShape; }
NSView *DPTabShapeView(NSView *background) { return nil; }
BOOL DPStyleSelected(uintptr_t style) { return style == 0 || style >= DPFirstFill; }
BOOL DPDrawnSelected(NSView *background) { return DPStyleSelected(*DPSelectionStyle(background)); }
void DPNoteLook(NSView *background) {}
NSArray *DPSelectedLook(NSView *button) { return @[ NSNull.null, @(1) ]; }
BOOL DPSwitchingTo(NSView *background) { return NO; }
void DPEndSwitch(NSWindow *window) {}
static int gUnselectCalls;
void DPUnselectFrontTab(NSView *background, BOOL standingIn) {
    if (!standingIn || !DPDrawnSelected(background) || !DPIsKind(background.superview, DPDiaTabView)) return;
    *DPSelectionStyle(background) = 2;
    gUnselectCalls++;
}
void DPGiveBackSelection(NSView *background) { gGiveBackCalls++; gHoldsSelection = NO; }
BOOL DPHoldsSelection(NSView *background) { return gHoldsSelection; }
void DPInstallFrontTab(void) {}

@interface _TtC7TabList14NewTabCellView : NSView
@end
@implementation _TtC7TabList14NewTabCellView
@end

@implementation TabUI_TabBackgroundView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) style = 2;
    return self;
}
- (void)updateLayer {}
@end

void DPCancelCommandBar(DPCommandBarOverlay *overlay) {
    if (!overlay) return;
    [gCancelled addObject:overlay];
    if (overlay.openedTab) DPStandInForTab(overlay.host, overlay.openedTab);
    if (DPGet(overlay.host, &DPOverlayKey) == overlay) DPSet(overlay.host, &DPOverlayKey, nil);
}

@interface DPTestWindow : NSWindow
@property BOOL fakeKey, fakeVisible;
@end
@implementation DPTestWindow
- (BOOL)isKeyWindow { return self.fakeKey; }
- (BOOL)isVisible { return self.fakeVisible; }
@end

static NSArray<NSWindow *> *gWindows;
static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gWindows; }

static void DPApp_postEvent(NSApplication *self, SEL _cmd, NSEvent *event, BOOL atStart) {
    [gPosted addObject:event];
}

static NSEvent *DPKeyEvent(NSWindow *window, unsigned short keyCode, NSString *chars) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                           timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                             context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:keyCode];
}

static DPCommandBarOverlay *DPOverlay(NSWindow *window, id tab) {
    DPCommandBarOverlay *overlay = [DPCommandBarOverlay new];
    overlay.host = window;
    overlay.openedTab = tab;
    return overlay;
}

@interface DPFakeImpl : NSObject
@property(strong) NSArray<NSString *> *rows;
@end
@implementation DPFakeImpl
- (id)itemIdentifierForIndexPath:(NSIndexPath *)path { return (NSUInteger)path.item < self.rows.count ? self.rows[path.item] : nil; }
@end

@interface DPFakeSource : NSObject <NSCollectionViewDataSource> {
    DPFakeImpl *_impl;
}
- (instancetype)initWithRows:(NSArray<NSString *> *)rows;
- (DPFakeImpl *)impl;
@end
@implementation DPFakeSource
- (instancetype)initWithRows:(NSArray<NSString *> *)rows {
    if ((self = [super init])) {
        _impl = [DPFakeImpl new];
        _impl.rows = rows;
    }
    return self;
}
- (DPFakeImpl *)impl { return _impl; }
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)view { return 1; }
- (NSInteger)collectionView:(NSCollectionView *)view numberOfItemsInSection:(NSInteger)section { return _impl.rows.count; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)view itemForRepresentedObjectAtIndexPath:(NSIndexPath *)path { return nil; }
@end

@interface DPFakeList : NSCollectionView
@end
@implementation DPFakeList
- (NSInteger)numberOfSections { return [self.dataSource numberOfSectionsInCollectionView:self]; }
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return [self.dataSource collectionView:self numberOfItemsInSection:section]; }
@end

@interface DPFakeTabView : NSView
@end
@implementation DPFakeTabView
@end

static NSString *DPRow(NSString *tab) { return [NSString stringWithFormat:@"Item.tab(%@)", tab]; }

// One sidebar page: a list holding its tabs, a front tab drawn selected, and a New Tab button.
@interface DPPage : NSObject
@property(strong) DPFakeList *list;
@property(strong) DPFakeSource *source;
@property(strong) NSView *button, *front;
@property(strong) TabUI_TabBackgroundView *buttonBackground, *frontBackground;
- (void)setTabs:(NSArray<NSString *> *)tabs;
@end
@implementation DPPage
- (instancetype)initIn:(NSView *)parent listClass:(Class)listCls backgroundClass:(Class)bgCls buttonClass:(Class)buttonCls tabClass:(Class)tabCls {
    if ((self = [super init])) {
        _list = [[listCls alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        _button = [[buttonCls alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
        _front = [[tabCls alloc] initWithFrame:NSMakeRect(0, 40, 100, 30)];
        _buttonBackground = [[bgCls alloc] initWithFrame:_button.bounds];
        _frontBackground = [[bgCls alloc] initWithFrame:_front.bounds];
        _frontBackground->style = 0;
        [_button addSubview:_buttonBackground];
        [_front addSubview:_frontBackground];
        [_list addSubview:_button];
        [_list addSubview:_front];
        [parent addSubview:_list];
    }
    return self;
}
- (void)setTabs:(NSArray<NSString *> *)tabs {
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@"SectionID.pinned"];
    for (NSString *tab in tabs) [rows addObject:DPRow(tab)];
    self.source = [[DPFakeSource alloc] initWithRows:rows];
    self.list.dataSource = self.source;
}
- (BOOL)buttonSelected { return DPStyleSelected(self.buttonBackground->style); }
- (BOOL)frontSelected { return DPStyleSelected(self.frontBackground->style); }
@end

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(NSApp.class, @selector(postEvent:atStart:), (IMP)DPApp_postEvent);
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        gHidden = [NSMutableSet setWithObjects:@"tab-1", @"tab-2", nil];
        gCancelled = [NSMutableArray array];
        gPosted = [NSMutableArray array];

        DPTestWindow *window = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 100, 100)
                                                               styleMask:NSWindowStyleMaskBorderless
                                                                 backing:NSBackingStoreBuffered defer:NO];
        window.fakeKey = YES;

        DPCommandBarOverlay *first = DPOverlay(window, @"tab-1");
        DPSet(window, &DPOverlayKey, first);
        DPStandInFor(window, @"tab-1");
        DPHandOver(first);
        DPCommandBarOverlay *second = DPOverlay(window, @"tab-2");
        DPSet(window, &DPOverlayKey, second);
        DPStandInFor(window, @"tab-2");

        DPFinishHandOver(window);
        CHECK(gCancelled.count == 1 && gCancelled.firstObject == first, "hand-over finish cancels only the old bar");
        CHECK([DPGet(window, &DPTabKey) isEqual:@"tab-2"] && DPStandingIn(window), "late cancel preserves the newer bar's stand-in");
        CHECK(DPGet(window, &DPOverlayKey) == second, "late cancel preserves the newer bar overlay");

        DPStandInForTab(window, @"tab-2");
        CHECK(DPGet(window, &DPTabKey) == nil && !DPStandingIn(window), "clearing the active bar's own tab removes the stand-in");
        DPSet(window, &DPOverlayKey, nil);

        NSEvent *cmdT = DPKeyEvent(window, 17, @"t"), *cmdL = DPKeyEvent(window, 37, @"l");
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdL, NO), "press while catching up is swallowed");
        DPSet(window, &DPOverlayKey, DPOverlay(window, @"tab-1"));
        DPDiaCaughtUp(window);
        CHECK(gPosted.count == 1 && gPosted.firstObject.keyCode == 37, "key window replays the queued swap press");
        CHECK(DPGet(window, &DPCatchingUpKey) == nil && DPGet(window, &DPWantKey) == nil, "catching-up state and want key are cleared");

        [gPosted removeAllObjects];
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdL, NO), "second swap press is swallowed while catching up");
        window.fakeKey = NO;
        DPDiaCaughtUp(window);
        CHECK(gPosted.count == 0, "non-key window does not post a replayed key event");
        CHECK(DPGet(window, &DPCatchingUpKey) == nil && DPGet(window, &DPWantKey) == nil, "non-key catch-up still clears state");
        CHECK(!DPWaitForDia(window, cmdT, YES), "window is not stuck catching up after losing key focus");

        [gCancelled removeAllObjects];
        DPCommandBarOverlay *third = DPOverlay(window, @"tab-1");
        DPSet(window, &DPOverlayKey, third);
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdT, YES), "toggle press while catching up is swallowed");
        DPDiaCaughtUp(window);
        CHECK(gCancelled.count == 1 && gCancelled.firstObject == third && gPosted.count == 0, "wanted close cancels directly without posting");
        CHECK(DPGet(window, &DPWantKey) == nil, "close path clears want key");

        [gPosted removeAllObjects];
        [gCancelled removeAllObjects];
        window.fakeKey = YES;
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdL, NO), "swap press queued before turning off");
        DPCommandBar.on = NO;
        DPDiaCaughtUp(window);
        CHECK(gPosted.count == 0 && gCancelled.count == 0, "turning CommandBar off prevents queued swap replay");
        CHECK(DPGet(window, &DPCatchingUpKey) == nil && DPGet(window, &DPWantKey) == nil, "off catch-up clears all state");

        DPCommandBar.on = YES;
        DPCommandBarOverlay *handed = DPOverlay(window, @"tab-1");
        DPSet(window, &DPOverlayKey, handed);
        DPHandOver(handed);
        CHECK(DPTakeHandOver(window) == handed && DPTakeHandOver(window) == nil, "DPTakeHandOver returns and clears handed-over bar");

        // Regression: HideTabButton restores DPSavedKey & DPHoldsSelection on invisible window during layout/updateLayer when off.
        Class bgCls = objc_allocateClassPair(TabUI_TabBackgroundView.class, DPDiaTabBackground, 0);
        objc_registerClassPair(bgCls);
        DPInstallStandIn();
        _TtC7TabList14NewTabCellView *newTabBtn = [[_TtC7TabList14NewTabCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
        NSView *bg = [[bgCls alloc] initWithFrame:newTabBtn.bounds];
        [newTabBtn addSubview:bg];
        [window.contentView addSubview:newTabBtn];
        gHiding = YES;
        gStyle = 2;
        gShape = 0;
        DPStandInFor(window, @"tab-1");
        CHECK(DPSelectionStyle(bg)[0] == 0 && DPTabShape(bg)[0] == 1 && DPGet(bg, &DPSavedKey) != nil, "New Tab button selected on non-visible window");
        gHiding = NO;
        gHoldsSelection = YES;
        gGiveBackCalls = 0;
        [bg layout];
        CHECK(DPSelectionStyle(bg)[0] == 2 && DPTabShape(bg)[0] == 0 && DPGet(bg, &DPSavedKey) == nil && gGiveBackCalls == 1,
              "turning hiding off restores button selection and front-tab selection once on next layout");
        [bg layout];
        CHECK(gGiveBackCalls == 1, "subsequent layouts while off do nothing");

        // Regression: the stand-in shows only on the sidebar page listing the hidden tab, not the next space's page a swipe slides in.
        Class listCls = objc_allocateClassPair(DPFakeList.class, DPDiaTabListCollection, 0);
        objc_registerClassPair(listCls);
        Class tabCls = objc_allocateClassPair(DPFakeTabView.class, DPDiaTabView, 0);
        objc_registerClassPair(tabCls);
        DPTestWindow *pages = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 500, 300) styleMask:NSWindowStyleMaskBorderless
                                                                backing:NSBackingStoreBuffered defer:NO];
        pages.fakeVisible = YES;
        gWindows = @[ window, pages ];
        NSString *backA = NSUUID.UUID.UUIDString, *barA = NSUUID.UUID.UUIDString, *backB = NSUUID.UUID.UUIDString, *barB = NSUUID.UUID.UUIDString;
        DPPage *pageA = [[DPPage alloc] initIn:pages.contentView listClass:listCls backgroundClass:bgCls buttonClass:_TtC7TabList14NewTabCellView.class tabClass:tabCls];
        DPPage *pageB = [[DPPage alloc] initIn:pages.contentView listClass:listCls backgroundClass:bgCls buttonClass:_TtC7TabList14NewTabCellView.class tabClass:tabCls];
        [pageA setTabs:@[ backA, barA ]];
        [pageB setTabs:@[ backB, barB ]];
        CHECK(DPIsKind(pageA.list, DPDiaTabListCollection) && DPIsKind(pageA.front, DPDiaTabView), "fixture pages look like Dia's");
        [gHidden addObject:barA];
        gHiding = YES;
        DPStandInFor(pages, barA);
        CHECK(pageA.buttonSelected && !pageB.buttonSelected, "only the hidden tab's own page draws the New Tab button selected");
        CHECK(!pageA.frontSelected && pageB.frontSelected, "only the hidden tab's own page loses its front tab's selected look");
        CHECK(DPVerifyStandIn(pages, barA) == nil, "verify accepts a stand-in kept out of the next space's page");
        DPSelectionStyle(pageA.buttonBackground)[0] = 2;
        CHECK(DPVerifyStandIn(pages, barA) != nil, "verify still flags a missing stand-in on the hidden tab's own page");
        DPSelectionStyle(pageA.buttonBackground)[0] = 0;

        // The same swipe the other way, once the bar's tab is in the other space.
        [gHidden removeAllObjects];
        [gHidden addObject:barB];
        DPStandInFor(pages, barB);
        CHECK(!pageA.buttonSelected && pageB.buttonSelected, "the stand-in follows the hidden tab to its own page");
        CHECK(DPGet(pageA.buttonBackground, &DPSavedKey) == nil && DPGet(pageB.buttonBackground, &DPSavedKey) != nil, "the left page's New Tab button is restored");
        CHECK(gGiveBackCalls > 0, "the left page's front tab is given its selection back");

        // The cache follows the list: a tab arriving or leaving changes who is listed.
        [pageA setTabs:@[ backA, barA, barB ]];
        gGiveBackCalls = 0;
        DPStandInFor(pages, barB);
        CHECK(pageA.buttonSelected && pageB.buttonSelected, "a hidden tab listed on a page after being cached draws its stand-in there");
        [pageA setTabs:@[ backA ]];
        DPStandInFor(pages, barB);
        CHECK(!pageA.buttonSelected && pageB.buttonSelected, "a hidden tab that leaves a page takes its stand-in with it");

        // A button outside any list, such as the tab bar's, is the window's only stand-in.
        NSView *stripButton = [[_TtC7TabList14NewTabCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
        TabUI_TabBackgroundView *stripBackground = [[bgCls alloc] initWithFrame:stripButton.bounds];
        [stripButton addSubview:stripBackground];
        [pages.contentView addSubview:stripButton];
        DPStandInFor(pages, barB);
        CHECK(DPStyleSelected(stripBackground->style), "a New Tab button outside any sidebar page is the stand-in");

        // Turning hiding off, or closing the bar, restores every page.
        gHiding = NO;
        DPStandInFor(pages, nil);
        for (DPPage *page in @[ pageA, pageB ]) [page.buttonBackground layout];
        [stripBackground layout];
        CHECK(!pageA.buttonSelected && !pageB.buttonSelected && !DPStyleSelected(stripBackground->style), "no page keeps a stand-in once hiding is off");
        gHiding = YES;
        [gHidden removeAllObjects];
        DPStandInFor(pages, nil);
        CHECK(!pageA.buttonSelected && !pageB.buttonSelected && DPVerifyStandIn(pages, nil) == nil, "closing the bar leaves no stand-in on any page");

        if (failures) return 1;
        puts("PASS: command bar swap stand-in and key-focus guards");
    }
    return 0;
}

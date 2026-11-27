#import <AppKit/AppKit.h>

static CFTimeInterval gIdleSeconds = 10;
#define CGEventSourceSecondsSinceLastEventType(state, type) (gIdleSeconds)

#import "Patches/CommandBar/HideTab.m"
#import "Patches/CommandBar/HideTabButton.m"
#import "Patches/CommandBar/CommandBarSpare.m"
#import "Patches/CommandBar/CommandBarSpareMaker.m"
#import "runloop.h"

DPPatch DPCommandBar, DPCommandBarKeepText, DPNewTabNextToCurrent;
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
BOOL DPTesting;
char DPOverlayKey;
const uintptr_t DPFirstFill = 4;

@implementation DPCommandBarOverlay
- (NSView *)viewUnder:(NSPoint)point { return nil; }
@end

@interface DPFakeDefaults : NSObject
@property(strong) NSMutableDictionary<NSString *, id> *store;
@end
@implementation DPFakeDefaults
- (instancetype)init {
    if ((self = [super init])) _store = [NSMutableDictionary dictionary];
    return self;
}
- (NSArray *)arrayForKey:(NSString *)key { return self.store[key]; }
- (void)setObject:(id)value forKey:(NSString *)key {
    if (value) self.store[key] = value;
    else [self.store removeObjectForKey:key];
}
@end

@interface DPFakeTab : NSObject
@property(copy) NSString *tabId, *URL;
@property BOOL closed;
@end
@implementation DPFakeTab
- (void)close:(id)sender { self.closed = YES; }
@end

@interface DPFakeProfile : NSObject
@property(strong) NSMutableArray<DPFakeTab *> *appleScriptTabs;
@end
@implementation DPFakeProfile
@end

@interface DPFakeScriptWindow : NSObject
@property(copy) NSString *windowId;
@property(strong) DPFakeTab *activeTab;
@property(strong) NSMutableArray<DPFakeProfile *> *appleScriptProfiles;
- (NSArray<DPFakeTab *> *)appleScriptTabs;
@end
@implementation DPFakeScriptWindow
- (NSArray<DPFakeTab *> *)appleScriptTabs { return self.appleScriptProfiles.firstObject.appleScriptTabs ?: @[]; }
@end

@interface DPFakeAppDelegate : NSObject
@property(strong) NSMutableArray<DPFakeScriptWindow *> *appleScriptWindows;
@end
@implementation DPFakeAppDelegate
@end

@interface RenderWidgetHostViewCocoa : NSView
@end
@implementation RenderWidgetHostViewCocoa
- (BOOL)acceptsFirstResponder { return YES; }
@end

@interface DPPeekCard : NSView
@property(strong) NSView *host;
@end
@implementation DPPeekCard
@end

@interface DPTestWindow : NSWindow
@property(strong) NSResponder *fakeResponder;
@end
@implementation DPTestWindow
- (NSResponder *)firstResponder { return self.fakeResponder ?: super.firstResponder; }
- (BOOL)makeFirstResponder:(NSResponder *)responder {
    self.fakeResponder = responder;
    return [super makeFirstResponder:responder];
}
@end

static DPFakeDefaults *gDefaults;
static DPFakeAppDelegate *gDelegate;
static NSArray<NSWindow *> *gWindows;
static NSWindow *gKeyWindow;
static BOOL gAppActive = YES, gSendActionResult = YES;
static int gSendActionCalls;
static NSMutableDictionary<NSString *, NSTextView *> *gBarTexts;
static NSMutableArray<NSNumber *> *gDismissedHiddenStates;
static NSMutableArray<NSString *> *gClosedBarTabs;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *gBlanks, *gSplits;

static NSString *gSuiteAsked;
static id DPDefaults_initWithSuite(id self, SEL _cmd, NSString *suite) {
    if (![suite isEqualToString:@"com.diapatches.spare-domain"]) return DPCallOriginal(DPDefaults_initWithSuite, self, suite);
    gSuiteAsked = suite;
    return gDefaults;
}
NSTextView *DPBarText(DPCommandBarOverlay *overlay) { return overlay.openedTab ? gBarTexts[DPTabID(overlay.openedTab)] : nil; }
void DPFocusBar(DPCommandBarOverlay *overlay) {}
void DPShowShade(DPCommandBarOverlay *overlay) {}
id DPWatchKeys(DPCommandBarOverlay *overlay) { return nil; }
void DPWatch(DPCommandBarOverlay *overlay) {}
void DPCancelCommandBar(DPCommandBarOverlay *overlay) {}
void DPCloseBarTab(NSWindow *window, id tab) { [gClosedBarTabs addObject:DPTabID(tab) ?: @""]; DPCloseTab(tab); }
void DPShowHiddenBars(void) {}
BOOL DPHasStrip(NSWindow *window) { return NO; }
NSView *DPBlankPage(NSWindow *window) { return nil; }
void DPMakeBlank(NSView *page, NSString *tab, NSString *closing) { if (page.window && tab) [DPBlanks(page.window) addObject:tab]; }
void DPHoldAutoPip(void) {}
void DPOnLaunch(void (^block)(void)) {}

NSMutableSet<NSString *> *DPBlanks(NSWindow *window) {
    NSString *key = window.identifier ?: @"";
    return gBlanks[key] ?: (gBlanks[key] = [NSMutableSet set]);
}
NSMutableSet<NSString *> *DPSplits(NSWindow *window) {
    NSString *key = window.identifier ?: @"";
    return gSplits[key] ?: (gSplits[key] = [NSMutableSet set]);
}

NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = [item.title isEqual:title] ? item : DPMenuItemTitled(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

id DPDismiss(DPCommandBarOverlay *overlay, BOOL closing) {
    [gDismissedHiddenStates addObject:@(overlay.hidden)];
    if (overlay.openedTab) DPStandInForTab(overlay.host, DPTabID(overlay.openedTab));
    if (DPGet(overlay.host, &DPOverlayKey) == overlay) DPSet(overlay.host, &DPOverlayKey, nil);
    overlay.host = nil;
    return overlay.openedTab;
}

void DPInstallFrozenLists(void) {}
void DPFreezeLists(NSWindow *window) {}
NSArray<NSString *> *DPListedTabs(NSWindow *window) { return @[]; }
BOOL DPListsTab(NSView *view, NSString *tabID) { return YES; }
void DPRelayoutLists(void) {}
NSString *DPVerifyHiddenRows(void) { return nil; }
void DPInstallHiddenStripTab(void) {}
void DPHoldStrips(NSWindow *window) {}
void DPReleaseStrips(void) {}
NSString *DPStripTabID(NSView *tabView) { return nil; }
BOOL DPSelectionLayoutKnown(void) { return YES; }
static uintptr_t gStyle;
static uint8_t gShape;
static NSView *gStyled;
static NSArray *gLook;
uintptr_t *DPSelectionStyle(NSView *background) { return background && background == gStyled ? &gStyle : NULL; }
uint8_t *DPTabShape(NSView *background) { return background && background == gStyled ? &gShape : NULL; }
NSView *DPTabShapeView(NSView *background) { return nil; }
BOOL DPStyleSelected(uintptr_t style) { return style == 0 || style >= DPFirstFill; }
BOOL DPDrawnSelected(NSView *background) { return NO; }
void DPNoteLook(NSView *background) {}
NSArray *DPSelectedLook(NSView *button) { return gLook; }
BOOL DPSwitchingTo(NSView *background) { return NO; }
void DPEndSwitch(NSWindow *window) {}
void DPUnselectFrontTab(NSView *background, BOOL standingIn) {}
void DPGiveBackSelection(NSView *background) {}
BOOL DPHoldsSelection(NSView *background) { return NO; }
void DPInstallFrontTab(void) {}
void DPInstallPress(void) {}

static BOOL DPApp_isActive(NSApplication *self, SEL _cmd) { return gAppActive; }
static NSWindow *DPApp_keyWindow(NSApplication *self, SEL _cmd) { return gKeyWindow; }
static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gWindows; }
static NSUInteger DPEvent_pressedMouseButtons(id self, SEL _cmd) { return 0; }
static BOOL DPApp_sendAction(NSApplication *self, SEL _cmd, SEL action, id target, id sender) {
    gSendActionCalls++;
    return gSendActionResult;
}

static DPFakeTab *DPMakeTab(NSString *tabId, NSString *url) {
    DPFakeTab *tab = [DPFakeTab new];
    tab.tabId = tabId;
    tab.URL = url;
    return tab;
}

static DPFakeTab *DPAddHiddenTab(NSWindow *window, DPFakeProfile *profile, NSString *tabId) {
    DPExpectNewTab(window);
    DPFakeTab *tab = DPMakeTab(tabId, @"");
    [profile.appleScriptTabs addObject:tab];
    DPHideTabRow(tabId, window);
    return tab;
}

static DPTestWindow *DPMakeWindow(NSString *windowId) {
    DPTestWindow *window = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 100, 100)
                                                           styleMask:NSWindowStyleMaskBorderless
                                                             backing:NSBackingStoreBuffered defer:NO];
    window.identifier = windowId;
    return window;
}

static DPCommandBarOverlay *DPMakeOverlay(NSWindow *window, DPFakeTab *opened, DPFakeTab *ret) {
    DPCommandBarOverlay *overlay = [DPCommandBarOverlay new];
    overlay.host = window;
    overlay.openedTab = opened;
    overlay.returnTab = ret;
    return overlay;
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gDefaults = [DPFakeDefaults new];
        setenv("DIATWEAKS_DOMAIN", "com.diapatches.spare-domain", 1);
        DPHookClass(NSUserDefaults.class, @selector(initWithSuiteName:), (IMP)DPDefaults_initWithSuite);
        gDelegate = [DPFakeAppDelegate new];
        gDelegate.appleScriptWindows = [NSMutableArray array];
        gBarTexts = [NSMutableDictionary dictionary];
        gDismissedHiddenStates = [NSMutableArray array];
        gClosedBarTabs = [NSMutableArray array];
        gBlanks = [NSMutableDictionary dictionary];
        gSplits = [NSMutableDictionary dictionary];
        NSApp.delegate = (id)gDelegate;

        DPHookClass(object_getClass(NSEvent.class), @selector(pressedMouseButtons), (IMP)DPEvent_pressedMouseButtons);
        DPHookClass(NSApp.class, @selector(isActive), (IMP)DPApp_isActive);
        DPHookClass(NSApp.class, @selector(keyWindow), (IMP)DPApp_keyWindow);
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        DPHookClass(NSApp.class, @selector(sendAction:to:from:), (IMP)DPApp_sendAction);

        NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *fileRoot = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
        NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
        [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
        fileRoot.submenu = fileMenu;
        [mainMenu addItem:fileRoot];
        NSApp.mainMenu = mainMenu;

        DPHidden = [NSMutableSet set];
        DPParked = [NSMutableSet set];
        DPOwner = [NSMapTable strongToWeakObjectsMapTable];
        DPCommandBar.on = YES;
        DPCommandBarHideTab.on = YES;
        DPCommandBarHideTab.unavailable = NO;
        DPCommandBarSpare.on = YES;
        DPNewTabNextToCurrent.on = NO;

        DPTestWindow *winA = DPMakeWindow(@"win-A"), *winB = DPMakeWindow(@"win-B");
        gWindows = @[ winA, winB ];
        gKeyWindow = winA;

        DPFakeTab *pageA = DPMakeTab(@"page-A", @"http://127.0.0.1/a");
        DPFakeTab *pageB = DPMakeTab(@"page-B", @"http://127.0.0.1/b");
        DPFakeTab *unhiddenB = DPMakeTab(@"unhidden-B", @"");
        DPFakeProfile *profA = [DPFakeProfile new];
        profA.appleScriptTabs = [NSMutableArray arrayWithObjects:pageA, nil];
        DPFakeProfile *profB = [DPFakeProfile new];
        profB.appleScriptTabs = [NSMutableArray arrayWithObjects:pageB, unhiddenB, nil];
        DPFakeScriptWindow *swA = [DPFakeScriptWindow new];
        swA.windowId = @"win-A";
        swA.activeTab = pageA;
        swA.appleScriptProfiles = [NSMutableArray arrayWithObject:profA];
        DPFakeScriptWindow *swB = [DPFakeScriptWindow new];
        swB.windowId = @"win-B";
        swB.activeTab = pageB;
        swB.appleScriptProfiles = [NSMutableArray arrayWithObject:profB];
        [gDelegate.appleScriptWindows addObjectsFromArray:@[ swA, swB ]];

        DPExpectNewTab(winB);
        DPFakeTab *lateB = DPMakeTab(@"late-B", @"");
        [profB.appleScriptTabs addObject:lateB];
        CHECK(DPHidesTab(@"late-B"), "expected tab still matches DPHidesTab during the 1 s window");
        CHECK(!DPHiddenTab(@"late-B"), "a tab no bar has hidden yet is not DPHiddenTab");
        DPCommandBarOverlay *overlayB = DPMakeOverlay(winB, lateB, pageB);
        CHECK(!DPParkSpare(overlayB) && !DPSpareIn(winB), "DPParkSpare refuses to park an unhidden expected tab");
        DPStopExpecting();

        DPExpectNewTab(winA);
        DPExpectNewTab(winB);
        CHECK(DPHidingATab(winA) && DPHidingATab(winB), "⌘T in a second window keeps the first window's expectation");
        DPHideTabRow(@"new-A", winA);
        CHECK(DPHiddenTab(@"new-A") && DPHidingATab(winA), "the first window's new tab still hides after ⌘T in another window");
        CHECK(DPHidingATab(winB) && DPHidesTab(@"new-B"), "hiding a tab resolves only its own window's expectation");
        DPForgetWindow(winB);
        CHECK(!DPHidingATab(winB) && DPHiddenTab(@"new-A"), "closing a window forgets only its own expectation and tabs");
        DPShowTabRow(@"new-A", NO);
        DPStopExpecting();
        DPHideTabRow(@"unannounced-B", winB);
        CHECK(DPHiddenTab(@"unannounced-B") && DPHidingATab(winB) && !DPHidingATab(winA),
              "with no ⌘T pending, the bar's tab still hides, in its own window only (#606)");
        DPShowTabRow(@"unannounced-B", NO);

        DPFakeTab *spareA = DPAddHiddenTab(winA, profA, @"spare-A");
        CHECK(DPHiddenTab(@"spare-A"), "hidden tab in expected window is DPHiddenTab");
        DPStandInFor(winA, @"newer-bar");
        DPCommandBarOverlay *overlayOld = DPMakeOverlay(winA, spareA, pageA);
        CHECK(DPParkSpare(overlayOld) && DPSpareIn(winA) == overlayOld, "DPParkSpare parks an actually hidden tab");
        CHECK([DPGet(winA, &DPTabKey) isEqual:@"newer-bar"], "DPParkSpare preserves another bar's stand-in");
        DPDropSpare(winA);
        CHECK([gDismissedHiddenStates.lastObject boolValue] == YES, "DPDropSpare keeps spare hidden while dismissing");
        CHECK([DPGet(winA, &DPTabKey) isEqual:@"newer-bar"], "DPDropSpare preserves another bar's stand-in");

        DPFakeTab *spareA2 = DPAddHiddenTab(winA, profA, @"spare-A2");
        DPStandInFor(winA, @"spare-A2");
        DPCommandBarOverlay *overlaySelf = DPMakeOverlay(winA, spareA2, pageA);
        CHECK(DPParkSpare(overlaySelf), "DPParkSpare parks its own bar");
        CHECK(DPGet(winA, &DPTabKey) == nil, "DPParkSpare clears its own stand-in");

        NSView *pageView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [winA.contentView addSubview:pageView];
        swA.activeTab = spareA2;
        [gDismissedHiddenStates removeAllObjects];
        CHECK(DPAdoptSpare(winA, pageView), "DPAdoptSpare adopts the active spare");
        CHECK([gDismissedHiddenStates.lastObject boolValue] == YES, "DPAdoptSpare keeps spare hidden while dismissing");
        DPSet(winA, &DPOverlayKey, DPMakeOverlay(winA, spareA2, nil));
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.38]];
        CHECK(!spareA2.closed, "adopt timer does not close the tab while a command bar is open over it");
        DPSet(winA, &DPOverlayKey, nil);

        DPFakeTab *spareA3 = DPAddHiddenTab(winA, profA, @"spare-A3");
        CHECK(DPParkSpare(DPMakeOverlay(winA, spareA3, pageA)), "parks spareA3");
        swA.activeTab = spareA3;
        CHECK(DPAdoptSpare(winA, pageView), "adopts spareA3");
        DPPumpUntil(^BOOL { return spareA3.closed; });
        CHECK(spareA3.closed && [gClosedBarTabs containsObject:@"spare-A3"], "adopt timer closes an unused empty spare in a multi-tab space as a bar tab");
        [profA.appleScriptTabs removeObject:spareA2];
        [profA.appleScriptTabs removeObject:spareA3];
        swA.activeTab = pageA;

        RenderWidgetHostViewCocoa *webA = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [winA.contentView addSubview:webA];
        winA.fakeResponder = webA;
        gIdleSeconds = 10;
        gSendActionCalls = 0;
        gSendActionResult = NO;
        DPWanted = YES;
        [DPSpareAttempts removeAllObjects];
        DPMakeSpare();
        CHECK(gSendActionCalls == 1 && DPWanted && !DPMakingSpareIn(winA), "failed sendAction re-arms DPWanted and drops the attempt");

        gSendActionResult = YES;
        DPMakeSpare();
        CHECK(gSendActionCalls == 2 && !DPWanted && DPMakingSpareIn(winA) && !DPMakingSpareIn(winB), "successful sendAction starts the spare wait in its own window");
        DPStopExpecting();
        [DPSpareAttempts setObject:@(CACurrentMediaTime() - 1) forKey:winA];
        DPMakeSpare();
        CHECK(gSendActionCalls == 3, "lapsed attempt with no spare re-arms DPWanted on next tick");
        DPStopExpecting();

        DPFakeTab *spareKeep = DPAddHiddenTab(winA, profA, @"spare-keep");
        CHECK(DPParkSpare(DPMakeOverlay(winA, spareKeep, pageA)), "parks spareKeep in winA");
        DPWanted = NO;
        [DPSpareAttempts removeAllObjects];
        RenderWidgetHostViewCocoa *webB = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [winB.contentView addSubview:webB];
        winB.fakeResponder = webB;
        gKeyWindow = winB;
        gSendActionCalls = 0;
        DPMakeSpare();
        CHECK(gSendActionCalls == 0 && !DPWanted, "existing spare in another window keeps global single-spare limit");
        gKeyWindow = winA;

        DPFakeTab *leftActive = DPMakeTab(@"left-active", @""), *leftTyped = DPMakeTab(@"left-typed", @""), *leftBg = DPMakeTab(@"left-bg", @"");
        [profA.appleScriptTabs addObjectsFromArray:@[ leftActive, leftTyped, leftBg ]];
        gDefaults.store[DPSparesKey] = @[ @"left-active", @"left-typed", @"left-bg", @"spare-keep" ];

        DPCommandBarSpare.on = NO;
        DPCloseLeftSpares(@[ @"left-bg" ], YES);
        CHECK(!leftBg.closed, "DPCloseLeftSpares does nothing when the option is off");
        DPCommandBarSpare.on = YES;

        swA.activeTab = leftActive;
        gIdleSeconds = 1;
        DPCloseLeftSpares(@[ @"left-active", @"left-bg", @"spare-keep" ], NO);
        CHECK(!leftActive.closed, "active restored spare is not closed while user recently gave input");
        CHECK(leftBg.closed, "background restored spare is closed at launch");
        CHECK(!spareKeep.closed, "currently parked spare is not closed by launch cleanup");

        swA.activeTab = leftTyped;
        gIdleSeconds = 10;
        NSTextView *typedView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        typedView.string = @"hello";
        gBarTexts[@"left-typed"] = typedView;
        DPSet(winA, &DPOverlayKey, DPMakeOverlay(winA, leftTyped, nil));
        DPCloseLeftSpares(@[ @"left-typed" ], YES);
        CHECK(!leftTyped.closed, "active restored spare with text in the bar is not closed");
        DPSet(winA, &DPOverlayKey, nil);

        DPCommandBarHideTab.unavailable = YES;
        CHECK(!DPSparesOn(), "DPSparesOn is NO when Hide New Tab Until Opened is unavailable");
        DPApplySpares(&DPCommandBarSpare);
        CHECK(DPSpareTimer == nil, "timer stays nil when spares are effectively off");
        DPCommandBarHideTab.unavailable = NO;
        CHECK(DPSparesOn(), "DPSparesOn is YES when dependencies are on and available");
        DPNewTabNextToCurrent.on = YES;
        CHECK(!DPSparesOn(), "DPSparesOn is NO with Open New Tabs Next to Current, whose bar tab is placed when kept");
        DPNewTabNextToCurrent.on = NO;
        DPApplySpares(&DPCommandBarSpare);
        CHECK(DPSpareTimer != nil && DPSpareTimer.valid, "apply creates the 1 Hz timer when on");
        DPCommandBarSpare.on = NO;
        DPApplySpares(&DPCommandBarSpare);
        CHECK(DPSpareTimer == nil && !DPSpareIn(winA), "turning off invalidates the timer and drops any spare");

        DPCommandBarSpare.on = YES;
        DPFakeTab *onlySpare = DPAddHiddenTab(winA, profA, @"only-spare");
        [profA.appleScriptTabs removeAllObjects];
        [profA.appleScriptTabs addObject:onlySpare];
        DPSet(winA, &DPSpareKey, DPMakeOverlay(winA, onlySpare, pageA));
        DPDropSpare(winA);
        CHECK(!onlySpare.closed && !DPSpareIn(winA), "DPDropSpare does not close a profile's only tab");

        DPFakeTab *navSpare = DPAddHiddenTab(winA, profA, @"nav-spare");
        [profA.appleScriptTabs addObject:pageA];
        navSpare.URL = @"https://example.com";
        DPSet(winA, &DPSpareKey, DPMakeOverlay(winA, navSpare, pageA));
        DPDropSpare(winA);
        CHECK(!navSpare.closed && !DPSpareIn(winA), "DPDropSpare does not close a navigated tab");

        DPFakeTab *closingSpare = DPAddHiddenTab(winA, profA, @"closing-spare");
        DPSet(winA, &DPSpareKey, DPMakeOverlay(winA, closingSpare, pageA));
        DPNoteSpare(@"closing-spare", YES);
        CHECK([gSuiteAsked isEqual:@"com.diapatches.spare-domain"], "the tabs the bar leaves behind are noted in DIATWEAKS_DOMAIN's domain, not the real one");
        DPForgetSpare(winA);
        CHECK(!closingSpare.closed && !DPSpareIn(winA) && ![gDefaults.store[DPSparesKey] containsObject:@"closing-spare"],
              "DPForgetSpare clears spare and persisted ID without closing tab");

        DPApplySpares(&DPCommandBarSpare);
        CHECK(DPSpareTimer != nil && DPSpareTimer.valid, "timer active while spares on");
        DPCommandBar.on = NO;
        DPMakeSpare();
        CHECK(DPSpareTimer == nil, "DPMakeSpare invalidates timer when DPCommandBar turns off");
        DPCommandBar.on = YES;

        DPApplySpares(&DPCommandBarSpare);
        DPFakeTab *hidTab = DPAddHiddenTab(winA, profA, @"hid-tab");
        DPCommandBarHideTab.on = NO;
        DPApplyHideTab(&DPCommandBarHideTab);
        CHECK(DPSpareTimer == nil && !DPHidden.count && !DPParked.count && !DPOwner.count,
              "turning HideTab off stops spare timer and clears hidden/parked tables");
        (void)hidTab;

        DPCommandBarHideTab.on = YES;
        DPCommandBarSpare.on = YES;
        DPCommandBar.on = YES;
        [profA.appleScriptTabs removeAllObjects];
        [profA.appleScriptTabs addObject:pageA];
        swA.activeTab = pageA;
        DPPeekCard *peekCard = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        RenderWidgetHostViewCocoa *peekWeb = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        peekCard.host = peekWeb;
        [peekCard addSubview:peekWeb];
        [winA.contentView addSubview:peekCard];
        winA.fakeResponder = peekWeb;
        gIdleSeconds = 10;
        gSendActionCalls = 0;
        DPWanted = YES;
        [DPSpareAttempts removeAllObjects];
        DPMakeSpare();
        CHECK(gSendActionCalls == 0, "DPMakeSpare does not create a background spare while a visible Peek card is open");

        DPFakeTab *overPeekSpare = DPAddHiddenTab(winA, profA, @"over-peek-spare");
        DPCommandBarOverlay *overPeekOverlay = DPMakeOverlay(winA, overPeekSpare, pageA);
        [winA.contentView addSubview:overPeekOverlay];
        winA.fakeResponder = overPeekOverlay;
        CHECK(DPParkSpare(overPeekOverlay), "DPParkSpare succeeds over a visible Peek card");
        CHECK(winA.firstResponder == peekWeb, "DPParkSpare focuses visible Peek web view instead of covered tab");
        DPDropSpare(winA);
        [overPeekOverlay removeFromSuperview];
        peekCard.hidden = YES;
        winA.fakeResponder = webA;
        DPWanted = YES;
        [DPSpareAttempts removeAllObjects];
        gSendActionCalls = 0;
        DPMakeSpare();
        CHECK(gSendActionCalls == 1, "DPMakeSpare resumes once Peek card is parked/hidden");
        DPStopExpecting();
        [peekCard removeFromSuperview];

        DPCommandBarSpare.on = YES;
        DPCommandBarHideTab.on = YES;
        peekCard.hidden = NO;
        [profA.appleScriptTabs removeAllObjects];
        [profA.appleScriptTabs addObject:pageA];
        swA.appleScriptProfiles = [NSMutableArray arrayWithObject:profA];
        swA.activeTab = pageA;
        DPFakeTab *otherSpaceTab = DPMakeTab(@"other-space", @"https://example.com");
        DPFakeProfile *otherSpace = [DPFakeProfile new];
        otherSpace.appleScriptTabs = [NSMutableArray arrayWithObject:otherSpaceTab];
        DPFakeTab *leftSpare = DPAddHiddenTab(winA, profA, @"left-space-spare");
        CHECK(DPParkSpare(DPMakeOverlay(winA, leftSpare, pageA)) && DPSpareIn(winA), "a spare parks in its own space");
        swA.appleScriptProfiles = [NSMutableArray arrayWithObjects:otherSpace, profA, nil];
        swA.activeTab = otherSpaceTab;
        CHECK(!DPShowSpare(winA) && !DPSpareIn(winA), "a spare left in another space isn't shown when the bar opens there");
        CHECK(leftSpare.closed && !otherSpaceTab.closed && !pageA.closed, "dropping the left spare closes only the spare, not the new space's tabs");
        CHECK([gClosedBarTabs containsObject:@"left-space-spare"] && ![gClosedBarTabs containsObject:@"other-space"], "a dropped spare closes as a bar tab, so it leaves the recent tabs");
        CHECK(![gDefaults.store[DPSparesKey] containsObject:@"left-space-spare"], "a dropped spare is no longer noted");

        swA.appleScriptProfiles = [NSMutableArray arrayWithObject:profA];
        swA.activeTab = pageA;
        [profA.appleScriptTabs removeObject:leftSpare];
        DPFakeTab *idleSpare = DPAddHiddenTab(winA, profA, @"idle-space-spare");
        CHECK(DPParkSpare(DPMakeOverlay(winA, idleSpare, pageA)) && DPSpareIn(winA), "a second spare parks in its own space");
        swA.appleScriptProfiles = [NSMutableArray arrayWithObjects:otherSpace, profA, nil];
        swA.activeTab = otherSpaceTab;
        winA.fakeResponder = webA;
        gIdleSeconds = 10;
        DPMakeSpare();
        CHECK(!DPSpareIn(winA) || DPSpareIn(winA).openedTab != idleSpare, "the spare timer drops a spare left in another space");
        CHECK(idleSpare.closed && !otherSpaceTab.closed, "the spare timer closes the left spare without touching the new space");
        DPStopExpecting();
        swA.appleScriptProfiles = [NSMutableArray arrayWithObject:profA];
        swA.activeTab = pageA;

        DPCommandBarSpare.on = NO;
        DPCommandBarHideTab.on = YES;
        DPCommandBarHideTab.unavailable = NO;
        DPCommandBar.on = YES;
        CHECK(!DPSparesOn(), "spares are off for the open-bar-tab regression");

        DPFakeTab *leftOpen = DPMakeTab(@"left-open", @"");
        [profA.appleScriptTabs addObject:leftOpen];
        DPNoteOpenTab(@"left-open", YES);
        CHECK([gDefaults.store[DPOpenTabsKey] containsObject:@"left-open"], "opening the bar notes its tab even with spares off");
        DPNoteSpare(@"left-open", NO);
        CHECK(![gDefaults.store[DPOpenTabsKey] containsObject:@"left-open"], "dismissing the bar clears the noted tab");

        DPNoteOpenTab(@"left-open", YES);
        swA.activeTab = pageA;
        gIdleSeconds = 10;
        DPCloseLeftBarTabs();
        CHECK(leftOpen.closed, "launch cleanup closes the tab the bar left behind with spares off");
        CHECK(![gDefaults.store[DPOpenTabsKey] containsObject:@"left-open"], "launch cleanup clears the noted tab");
        [profA.appleScriptTabs removeObject:leftOpen];

        DPFakeTab *onlyOpen = DPMakeTab(@"only-open", @"");
        [profA.appleScriptTabs removeAllObjects];
        [profA.appleScriptTabs addObject:onlyOpen];
        swA.activeTab = onlyOpen;
        DPNoteOpenTab(@"only-open", YES);
        DPCloseLeftBarTabs();
        CHECK(!onlyOpen.closed, "launch cleanup keeps a space's only tab");
        CHECK(![gDefaults.store[DPOpenTabsKey] containsObject:@"only-open"], "launch cleanup forgets a tab it can't close");

        DPCommandBarSpare.on = YES;
        DPCommandBarHideTab.on = YES;
        DPDropSpare(winA);
        DPDropSpare(winB);
        DPStopExpecting();
        [profA.appleScriptTabs removeAllObjects];
        [profA.appleScriptTabs addObject:pageA];
        swA.activeTab = pageA;
        swB.activeTab = pageB;
        winA.fakeResponder = webA;
        winB.fakeResponder = webB;
        gIdleSeconds = 10;
        gSendActionCalls = 0;
        DPWanted = YES;
        gKeyWindow = winA;
        DPMakeSpare();
        DPWanted = YES;
        gKeyWindow = winB;
        DPMakeSpare();
        CHECK(gSendActionCalls == 2, "each window starts its own spare");
        DPCommandBarOverlay *spareBarA = DPMakeOverlay(winA, DPMakeTab(@"made-A", @""), pageA);
        DPParkIfSpare(spareBarA);
        CHECK(spareBarA.hidden, "a spare made in one window still parks after another window starts one");
        DPStopExpecting();
        gKeyWindow = winA;

        NSObject *fill = [NSObject new];
        NSView *button = [NSView new], *background = [NSView new];
        [button addSubview:background];
        gLook = @[ fill, @3 ];
        gStyled = background;
        gStyle = 2;
        gShape = 1;
        CFIndex resting = CFGetRetainCount((__bridge CFTypeRef)fill);
        @autoreleasepool { DPSelectButton(background, YES); }
        CHECK(gStyle == (uintptr_t)(__bridge void *)fill && gShape == 3, "the New Tab button takes the selected look");
        @autoreleasepool { DPSelectButton(background, NO); }
        CHECK(gStyle == 2 && gShape == 1 && CFGetRetainCount((__bridge CFTypeRef)fill) == resting, "putting Dia's look back releases the colour once");
        @autoreleasepool { DPSelectButton(background, YES); }
        CFRelease((CFTypeRef)(void *)gStyle);
        gStyle = 2;
        @autoreleasepool { DPSelectButton(background, NO); }
        CHECK(gStyle == 2 && CFGetRetainCount((__bridge CFTypeRef)fill) == resting, "a colour Dia already released when writing over the style isn't released again");
        gStyled = nil;
        gLook = nil;

        if (failures) return 1;
        puts("PASS: command bar spare guards, launch cleanup, and timer lifecycle");
    }
    return 0;
}

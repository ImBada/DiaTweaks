#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "Patches/CommandBar/CommandBar.m"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/HideNewTabLogo/HideNewTabLogo.m"
#import "Patches/KeepWindowsActive/KeepWindowsActive.m"
NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";

static NSString *DPTestSuiteName(void) { return [NSString stringWithFormat:@"com.diapatches.command-bar-lifecycle.%d", getpid()]; }

@interface NSUserDefaults (DPLifecycleSuite)
- (instancetype)dp_lifecycleInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPLifecycleSuite)
- (instancetype)dp_lifecycleInitWithSuiteName:(NSString *)suite {
    return [self dp_lifecycleInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPTestSuiteName() : suite];
}
@end

static BOOL gHiding;
static int gOpenAttempts;
static int gCleanHideTabCalls, gUpdateSpareTimerCalls, gForgetSpareCalls, gDropSpareCalls, gClearCatchUpCalls, gFinishHandOverCalls, gCancelPopoverCalls, gHandToDiaCalls;
static DPCommandBarOverlay *gHandedOver;
static NSString *gChoice = @"macos";
static NSArray<NSWindow *> *gWindows;

NSString *DPChoice(DPPatch *patch) { return gChoice; }
void DPInstallAutoPipHold(void) {}
static int gHolds;
void DPHoldAutoPip(void) { gHolds++; }
BOOL DPHiding(void) { return gHiding; }
void DPExpectNewTab(NSWindow *window) {}
void DPStopExpecting(void) { gOpenAttempts++; }
static NSMutableArray<NSString *> *gHiddenRowIDs;
static NSString *gStandIn;
void DPHideTabRow(NSString *tabID, NSWindow *window) { [gHiddenRowIDs addObject:tabID ?: @""]; }
static NSMutableArray<NSArray *> *gShownRows, *gNotedSpares, *gNotedOpenTabs;
void DPShowTabRow(NSString *tabID, BOOL closing) { [gShownRows addObject:@[ tabID ?: @"", @(closing) ]]; }
BOOL DPHidesTab(NSString *tabID) { return NO; }
void DPParkTab(NSString *tabID, BOOL parked) {}
void DPHideBlank(NSString *tabID, BOOL hidden, NSWindow *window) {}
BOOL DPParksTab(NSString *tabID) { return NO; }
void DPFreezeLists(NSWindow *window) {}
static BOOL gHidingATab;
static int gRelayouts;
BOOL DPHidingATab(NSWindow *window) { return gHidingATab; }
BOOL DPParkingAny(void) { return NO; }
void DPRelayoutLists(void) { gRelayouts++; }
BOOL DPOnlyListedTab(NSString *tabID, NSString *closingID, NSWindow *window) { return NO; }
void DPStandInFor(NSWindow *window, NSString *tabID) { gStandIn = tabID; }
void DPStandInForTab(NSWindow *window, NSString *tabID) {}
void DPStandInWhileSwitching(NSWindow *window, NSString *tabID, NSString *leaving) {}
NSString *DPVerifyStandIn(NSWindow *window, NSString *tabID) { return nil; }
void DPCleanHideTab(void) { gCleanHideTabCalls++; }
BOOL DPInTabLayout(NSView *view) { return NO; }
NSEvent *DPTabLayoutMouseDown(DPCommandBarOverlay *overlay, NSEvent *event) { return event; }
void DPTabLayoutMouseUp(DPCommandBarOverlay *overlay) {}
void DPHandOver(DPCommandBarOverlay *overlay) {}
void DPFinishHandOver(NSWindow *window) { gFinishHandOverCalls++; }
DPCommandBarOverlay *DPTakeHandOver(NSWindow *window) { DPCommandBarOverlay *o = gHandedOver; gHandedOver = nil; return o; }
void DPClearCatchUp(NSWindow *window) { gClearCatchUpCalls++; }
NSEvent *DPHandToDia(NSWindow *window, NSEvent *event, BOOL newTab) { gHandToDiaCalls++; return nil; }
BOOL DPWaitForDia(NSWindow *window, NSEvent *event, BOOL newTab) { return NO; }
void DPDiaCaughtUp(NSWindow *window) {}
BOOL DPParkSpare(DPCommandBarOverlay *overlay) { return NO; }
void DPParkIfSpare(DPCommandBarOverlay *overlay) {}
static BOOL gShowSpare;
BOOL DPShowSpare(NSWindow *window) { return gShowSpare; }
void DPDropSpare(NSWindow *window) { gDropSpareCalls++; }
void DPForgetSpare(NSWindow *window) { gForgetSpareCalls++; }
void DPUpdateSpareTimer(void) { gUpdateSpareTimerCalls++; }
static DPCommandBarOverlay *gSpare;
DPCommandBarOverlay *DPSpareIn(NSWindow *window) { return gSpare.host == window ? gSpare : nil; }
void DPNoteSpare(NSString *tabID, BOOL parked) { [gNotedSpares addObject:@[ tabID ?: @"", @(parked) ]]; }
void DPNoteOpenTab(NSString *tabID, BOOL open) { [gNotedOpenTabs addObject:@[ tabID ?: @"", @(open) ]]; }
BOOL DPAdoptSpare(NSWindow *window, NSView *page) { return NO; }
void DPNotMakingSpare(void) {}
NSView *DPCommandBarPart(NSView *commandBar, const char *className) { return nil; }
NSView *DPGoButton(NSView *toolbar) { return nil; }

@interface _TtC6Window14PlatformWindow : NSWindow
@property (strong) NSWindow *fakeSheet;
@property (weak) NSResponder *fakeResponder;
@end
@implementation _TtC6Window14PlatformWindow
- (NSWindow *)attachedSheet { return self.fakeSheet; }
- (NSResponder *)firstResponder { return self.fakeResponder ?: [super firstResponder]; }
- (BOOL)isVisible { return NO; }
@end

@interface DPPeekCard : NSView
@property BOOL closing;
@property (strong) NSView *toolbar;
@end
@implementation DPPeekCard
@end

@interface _TtC20AssistantPanelUIBase22AssistantPanelRootView : NSView
@end
@implementation _TtC20AssistantPanelUIBase22AssistantPanelRootView
@end

@interface _TtC5Popup19PlatformPopupWindow : NSWindow
@end
@implementation _TtC5Popup19PlatformPopupWindow
@end

@interface DPFakeNewTabPage : NSView
@end
@implementation DPFakeNewTabPage
@end

@interface DPFakePopoverText : NSTextView
@end
@implementation DPFakePopoverText
- (void)doCommandBySelector:(SEL)sel { if (sel == @selector(cancelOperation:)) gCancelPopoverCalls++; }
@end

@interface DPCountingPanel : NSView
@property NSInteger frameWrites;
@end
@implementation DPCountingPanel
- (void)setFrame:(NSRect)frame { self.frameWrites++; [super setFrame:frame]; }
@end

// Compact Command Bar keeps the panel 48 pt short of the height Dia sets, and DPTrim reports the difference.
@interface DPTrimmedPanel : _TtC20AssistantPanelUIBase22AssistantPanelRootView
@property BOOL compact;
@property CGFloat trim, kept;
@end
@implementation DPTrimmedPanel
- (void)setFrameSize:(NSSize)size {
    if (self.compact && size.height != self.kept) {
        self.trim = 48;
        size.height -= self.trim;
        self.kept = size.height;
    } else if (!self.compact) self.trim = 0;
    [super setFrameSize:size];
}
@end

CGFloat DPTrim(NSView *container) { return [container isKindOfClass:DPTrimmedPanel.class] ? ((DPTrimmedPanel *)container).trim : 0; }

@interface DPFakeSuggestions : NSView
@property CGFloat rows;
@end
@implementation DPFakeSuggestions
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, self.rows); }
@end

@interface _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView : NSView
@end
@implementation _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView
@end

@interface DPCountingMenu : NSMenu
@end
static int gMenuWalks;
@implementation DPCountingMenu
- (NSArray<NSMenuItem *> *)itemArray {
    gMenuWalks++;
    return [super itemArray];
}
@end

static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gWindows; }
static NSWindow *gKeyWindow, *gMainWindow;
static NSWindow *DPApp_keyWindow(NSApplication *self, SEL _cmd) { return gKeyWindow; }
static NSWindow *DPApp_mainWindow(NSApplication *self, SEL _cmd) { return gMainWindow; }

@interface _TtC5TabUI14TabContentView : NSView
@property int closes;
@end
@implementation _TtC5TabUI14TabContentView
- (void)closeButtonClicked { self.closes++; }
@end

@interface DPFakeTab : NSObject
@property(copy) NSString *tabId, *URL;
@property BOOL closed;
@end
@implementation DPFakeTab
- (void)close:(id)sender { self.closed = YES; }
@end

@interface DPFakeSpace : NSObject
@property(strong) NSMutableArray<DPFakeTab *> *appleScriptTabs;
@end
@implementation DPFakeSpace
@end

@interface DPFakeScriptWindow : NSObject
@property(copy) NSString *windowId;
@property(strong) DPFakeTab *activeTab;
@property(strong) NSArray<DPFakeSpace *> *appleScriptProfiles;
@property(strong) DPFakeSpace *front;
- (NSArray<DPFakeTab *> *)appleScriptTabs;
@end
@implementation DPFakeScriptWindow
- (NSArray<DPFakeTab *> *)appleScriptTabs { return self.front.appleScriptTabs ?: @[]; }
@end

static int gScriptReads;

@interface DPFakeAppDelegate : NSObject
@property(nonatomic, strong) NSArray<DPFakeScriptWindow *> *appleScriptWindows;
@end
@implementation DPFakeAppDelegate
@synthesize appleScriptWindows = _appleScriptWindows;
- (NSArray *)appleScriptWindows { gScriptReads++; return _appleScriptWindows; }
@end

static DPFakeTab *DPTab(NSString *identifier, NSString *URL) {
    DPFakeTab *tab = [DPFakeTab new];
    tab.tabId = identifier;
    tab.URL = URL;
    return tab;
}

static DPFakeSpace *DPSpace(NSArray<DPFakeTab *> *tabs) {
    DPFakeSpace *space = [DPFakeSpace new];
    space.appleScriptTabs = tabs.mutableCopy;
    return space;
}

// Switching space brings another space's tabs forward, leaving the old ones listed only under their own space.
static void DPSwitchTo(DPFakeScriptWindow *script, DPFakeSpace *space) {
    script.front = space;
    script.activeTab = space.appleScriptTabs.firstObject;
}

static DPCommandBarOverlay *DPBarFor(NSWindow *window, DPFakeTab *opened, DPFakeTab *returnTab) {
    DPCommandBarOverlay *overlay = [[DPCommandBarOverlay alloc] initWithFrame:window.contentView.bounds];
    overlay.host = window;
    overlay.openedTab = opened;
    overlay.returnTab = returnTab;
    overlay.startURL = opened.URL;
    DPSet(window, &DPOverlayKey, overlay);
    return overlay;
}

static DPFakeAppDelegate *gDelegate;

static BOOL DPLast(NSArray<NSArray *> *rows, NSString *tabID, BOOL flag) { return [rows.lastObject isEqual:@[ tabID, @(flag) ]]; }
static BOOL DPHas(NSArray<NSArray *> *rows, NSString *tabID, BOOL flag) { return [rows containsObject:@[ tabID, @(flag) ]]; }

@interface DPScene : NSObject
@property(strong) NSWindow *window;
@property(strong) DPFakeScriptWindow *script;
@property(strong) DPFakeSpace *old, *next;
@property(strong) DPFakeTab *back, *bar;
@property(strong) DPCommandBarOverlay *overlay;
@end
@implementation DPScene
- (instancetype)initIn:(NSWindow *)window {
    if ((self = [super init])) {
        NSString *name = window.identifier;
        _window = window;
        _back = DPTab([name stringByAppendingString:@"-back"], @"https://example.org");
        _bar = DPTab([name stringByAppendingString:@"-bar"], @"");
        _old = DPSpace(@[ _back, _bar ]);
        _next = DPSpace(@[ DPTab([name stringByAppendingString:@"-next"], @"https://example.com") ]);
        _script = [DPFakeScriptWindow new];
        _script.windowId = name;
        _script.appleScriptProfiles = @[ _old, _next ];
        DPSwitchTo(_script, _old);
        _script.activeTab = _bar;
        NSMutableArray *scripts = [(gDelegate.appleScriptWindows ?: @[]) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"windowId != %@", name]].mutableCopy;
        [scripts addObject:_script];
        gDelegate.appleScriptWindows = scripts;
        _overlay = DPBarFor(window, _bar, _back);
        DPSet(window, &DPRecentKey, @[ _back.tabId, _bar.tabId ]);
    }
    return self;
}
- (void)leave { DPSwitchTo(self.script, self.next); }
- (void)watch { DPCommandBarOverlay *overlay = self.overlay; if (overlay.host) DPWatchNewTab(overlay, nil); }
- (BOOL)open { return self.overlay.host != nil && DPGet(self.window, &DPOverlayKey) == self.overlay; }
@end

static NSEvent *DPKey(NSWindow *window, NSString *ch, unsigned short code) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                           timestamp:1 windowNumber:window.windowNumber context:nil
                          characters:ch charactersIgnoringModifiers:ch isARepeat:NO keyCode:code];
}

static NSEvent *DPTyped(NSWindow *window, NSString *chars, NSEventModifierFlags mods) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:1 windowNumber:window.windowNumber
                             context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:0];
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static void DPSpin(NSTimeInterval seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }

static DPCommandBarOverlay *DPOpenBar(Class pageCls, NSString *name, BOOL panelFirst, NSView **page, NSView **panel) {
    _TtC6Window14PlatformWindow *window = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                        styleMask:NSWindowStyleMaskTitled
                                                                                          backing:NSBackingStoreBuffered defer:NO];
    window.identifier = name;
    gWindows = @[ window ];
    DPFakeTab *back = DPTab([name stringByAppendingString:@"-back"], @"https://example.org"), *bar = DPTab([name stringByAppendingString:@"-bar"], @"");
    DPFakeScriptWindow *script = [DPFakeScriptWindow new];
    script.windowId = name;
    script.front = DPSpace(@[ back, bar ]);
    script.appleScriptProfiles = @[ script.front ];
    script.activeTab = bar;
    gDelegate.appleScriptWindows = @[ script ];
    DPSet(window, &DPRecentKey, @[ back.tabId, bar.tabId ]);
    *page = [[pageCls alloc] initWithFrame:window.contentView.bounds];
    NSView *root = [[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)];
    root.wantsLayer = YES;
    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"position"];
    slide.fromValue = [NSValue valueWithPoint:NSMakePoint(200, 200)];
    slide.duration = 5;
    [root.layer addAnimation:slide forKey:@"slide"];
    *panel = root;
    if (panelFirst) [*page addSubview:root];
    [window.contentView addSubview:*page];
    if (!panelFirst) [*page addSubview:root];
    DPSpin(0.4);
    return DPGet(window, &DPOverlayKey);
}

static BOOL DPRecentHas(NSWindow *window, NSString *tabID) { return [(NSArray *)DPGet(window, &DPRecentKey) containsObject:tabID]; }

// #623: a bar tab that was closed must not stay the tab the next new tab is said to have come from.
static void DPCheckRepeatedNewTab(Class pageCls, Class stripCls, BOOL hiding, BOOL stripped, BOOL byKey) {
    gHiding = hiding;
    NSString *name = [NSString stringWithFormat:@"window-repeat-%d%d%d", hiding, stripped, byKey];
    NSString *mode = [NSString stringWithFormat:@"%@, %@, %@", hiding ? @"Hide New Tab on" : @"Hide New Tab off", stripped ? @"tabs at top" : @"sidebar", byKey ? @"Cmd+T" : @"Esc"];
    _TtC6Window14PlatformWindow *window = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                        styleMask:NSWindowStyleMaskTitled
                                                                                          backing:NSBackingStoreBuffered defer:NO];
    window.identifier = name;
    gWindows = @[ window ];
    if (stripped) [window.contentView addSubview:[[stripCls alloc] initWithFrame:NSMakeRect(0, 0, 600, 40)]];
    DPFakeTab *site = DPTab([name stringByAppendingString:@"-site"], @"https://google.com");
    DPFakeScriptWindow *script = [DPFakeScriptWindow new];
    script.windowId = name;
    script.front = DPSpace(@[ DPTab([name stringByAppendingString:@"-other"], @"https://example.org"), site ]);
    script.appleScriptProfiles = @[ script.front ];
    script.activeTab = site;
    gDelegate.appleScriptWindows = @[ script ];
    DPNoteActiveTab(window, script, NULL);
    for (int round = 1; round <= 3; round++) {
        NSString *what = [NSString stringWithFormat:@"%@, open %d", mode, round];
        DPFakeTab *tab = DPTab([NSString stringWithFormat:@"%@-new%d", name, round], @"");
        [script.front.appleScriptTabs addObject:tab];
        script.activeTab = tab;
        NSView *page = [[pageCls alloc] initWithFrame:window.contentView.bounds];
        [page addSubview:[[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)]];
        [window.contentView addSubview:page];
        DPSpin(0.15);
        DPCommandBarOverlay *bar = DPGet(window, &DPOverlayKey);
        CHECK(bar && bar.openedTab == tab && bar.returnTab == site && !DPGet(page, &DPOwnBarKey) && ![DPBlanks(window) containsObject:tab.tabId],
              [@"Cmd+T opens the floating bar over the page, not Dia's own New Tab page: " stringByAppendingString:what].UTF8String);
        if (!bar) break;
        script.activeTab = site;
        if (byKey) DPCommandBarKey(DPKey(window, @"t", 17));
        else DPCancelCommandBar(bar);
        CHECK(!bar.host && tab.closed && !site.closed, [@"cancelling the bar closes only its own tab: " stringByAppendingString:what].UTF8String);
        CHECK(!DPRecentHas(window, tab.tabId), [@"a closed bar tab leaves the recent tabs: " stringByAppendingString:what].UTF8String);
        [script.front.appleScriptTabs removeObject:tab];
        [page removeFromSuperview];
    }
    [script.front.appleScriptTabs removeObjectAtIndex:0];
    _TtC5TabUI14TabContentView *row = [[_TtC5TabUI14TabContentView alloc] initWithFrame:NSMakeRect(0, 0, 200, 37)];
    [window.contentView addSubview:row];
    [row closeButtonClicked];
    DPFakeTab *replacement = DPTab([name stringByAppendingString:@"-replacement"], @"");
    [script.front.appleScriptTabs addObject:replacement];
    [script.front.appleScriptTabs removeObject:site];
    script.activeTab = replacement;
    NSView *page = [[pageCls alloc] initWithFrame:window.contentView.bounds];
    [page addSubview:[[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)]];
    [window.contentView addSubview:page];
    DPSpin(0.05);
    CHECK(!DPGet(window, &DPOverlayKey) && page.hidden && [DPBlanks(window) containsObject:replacement.tabId],
          [@"closing the last tab afterwards still leaves a blank, not a bar: " stringByAppendingString:mode].UTF8String);
    [page removeFromSuperview];
    [row removeFromSuperview];
    DPSet(window, &DPBlankKey, nil);
}

// #622: ⌘L's bar opens where it stays, before any ⌘T has measured a bar for the window.
static void DPCheckFirstCommandL(Class popoverCls, Class barCls, Class suggestionsCls, Class toolbarCls, NSString *position, BOOL compact) {
    gChoice = position;
    NSString *name = [NSString stringWithFormat:@"window-first-l-%@-%d", position, compact];
    NSString *mode = [NSString stringWithFormat:@"%@, Compact Command Bar %@", position, compact ? @"on" : @"off"];
    NSRect visible = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame : NSMakeRect(0, 0, 1400, 1000);
    _TtC6Window14PlatformWindow *window = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 700, MIN(1000, NSHeight(visible) - 100))
                                                                                        styleMask:NSWindowStyleMaskTitled
                                                                                          backing:NSBackingStoreBuffered defer:NO];
    window.identifier = name;
    [window setFrameTopLeftPoint:NSMakePoint(NSMinX(visible), NSMaxY(visible))];
    gWindows = @[ window ];
    DPFakeTab *site = DPTab([name stringByAppendingString:@"-site"], @"https://example.org");
    DPFakeScriptWindow *script = [DPFakeScriptWindow new];
    script.windowId = name;
    script.front = DPSpace(@[ site ]);
    script.appleScriptProfiles = @[ script.front ];
    script.activeTab = site;
    gDelegate.appleScriptWindows = @[ script ];

    DPTrimmedPanel *panel = [[DPTrimmedPanel alloc] initWithFrame:NSMakeRect(40, 40, 500, 108)];
    panel.compact = compact;
    NSView *commandBar = [[barCls alloc] initWithFrame:panel.bounds];
    DPFakeSuggestions *suggestions = [[suggestionsCls alloc] initWithFrame:NSMakeRect(0, 60, 500, 0)];
    [commandBar addSubview:suggestions];
    [commandBar addSubview:[[toolbarCls alloc] initWithFrame:NSMakeRect(0, 0, 500, 48)]];
    [panel addSubview:commandBar];
    NSView *popover = [[popoverCls alloc] initWithFrame:window.contentView.bounds];
    [popover addSubview:panel];
    [window.contentView addSubview:popover];

    DPCommandBarOverlay *bar = DPGet(window, &DPOverlayKey);
    CHECK(bar != nil && DPGet(window, &DPAnchorKey) == nil, [@"⌘L lifts its bar in a window no ⌘T has measured: " stringByAppendingString:mode].UTF8String);
    if (!bar) return [popover removeFromSuperview];
    CGFloat want = NSMinY(DPBarFrame(bar, NSMakeSize(500, 108), 108));
    NSMutableArray<NSString *> *moved = [NSMutableArray array];
    void (^settled)(NSString *) = ^(NSString *step) {
        if (NSMinY(panel.frame) != want) [moved addObject:[NSString stringWithFormat:@"%@ %.0f", step, NSMinY(panel.frame) - want]];
    };
    NSRect (^diaSizes)(CGFloat) = ^NSRect(CGFloat height) { return NSMakeRect(40, 40, 500, height); };
    settled(@"lifted");
    panel.frame = diaSizes(108);
    settled(@"Dia sizes it");
    [bar layout];
    settled(@"overlay layout");
    DPSpin(0.6);
    CHECK(bar.alphaValue == 1, [@"⌘L's bar shows once built: " stringByAppendingString:mode].UTF8String);
    settled(@"shown");
    panel.frame = diaSizes(108);
    [bar layout];
    settled(@"Dia sizes it again");
    suggestions.rows = 160;
    panel.frame = diaSizes(108 + 168);
    settled(@"suggestions grow");
    [bar layout];
    settled(@"layout with suggestions");
    suggestions.rows = 0;
    panel.frame = diaSizes(108);
    [bar layout];
    settled(@"suggestions go");
    panel.compact = !compact;
    [panel setFrameSize:NSMakeSize(500, 108)];
    [bar layout];
    settled(@"Compact Command Bar toggled");
    panel.frame = diaSizes(108);
    [bar layout];
    settled(@"Dia sizes it after the toggle");

    DPCommandBarOverlay *newTabBar = [[DPCommandBarOverlay alloc] initWithFrame:window.contentView.bounds];
    newTabBar.host = window;
    NSView *newTabPage = [[NSView alloc] initWithFrame:NSZeroRect];
    newTabBar.page = newTabPage;
    NSView *newTabPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 108)];
    [newTabPanel addSubview:[[barCls alloc] initWithFrame:newTabPanel.bounds]];
    newTabBar.panel = newTabPanel;
    [newTabBar frameForPanelSize:NSMakeSize(500, 108)];
    CHECK([DPGet(window, &DPAnchorKey) doubleValue] == 108, [@"the new tab bar measures the same height ⌘L opened with: " stringByAppendingString:mode].UTF8String);
    [bar layout];
    settled(@"⌘T measured the window");
    panel.frame = diaSizes(108);
    settled(@"Dia sizes it after ⌘T");
    NSString *shifts = [NSString stringWithFormat:@"⌘L's bar stays put from its first frame (%@): %@", mode, [moved componentsJoinedByString:@", "]];
    CHECK(!moved.count, shifts.UTF8String);
    [popover removeFromSuperview];
    CHECK(!DPGet(window, &DPOverlayKey), [@"closing the popover closes the lifted bar: " stringByAppendingString:mode].UTF8String);
}

int main(void) {
    @autoreleasepool {
        unsetenv("DIATWEAKS_DOMAIN");
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_lifecycleInitWithSuiteName:)));
        [NSApplication sharedApplication];
        gShownRows = [NSMutableArray array];
        gHiddenRowIDs = [NSMutableArray array];
        gNotedSpares = [NSMutableArray array];
        gNotedOpenTabs = [NSMutableArray array];
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        DPHookClass(NSApp.class, @selector(keyWindow), (IMP)DPApp_keyWindow);
        DPHookClass(NSApp.class, @selector(mainWindow), (IMP)DPApp_mainWindow);

        Class ntpCls = objc_allocateClassPair(DPFakeNewTabPage.class, DPDiaNewTabPage, 0);
        objc_registerClassPair(ntpCls);
        Class paneCls = objc_allocateClassPair(NSView.class, DPDiaContentPane, 0);
        objc_registerClassPair(paneCls);
        Class tabListCls = objc_allocateClassPair(NSView.class, DPDiaTabList, 0);
        objc_registerClassPair(tabListCls);
        Class stripCls = objc_allocateClassPair(NSView.class, DPDiaTabStripTabs, 0);
        objc_registerClassPair(stripCls);

        NSMenu *mainMenu = [[DPCountingMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *fileRoot = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
        NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
        [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
        [fileMenu addItemWithTitle:@"Open Command Bar" action:@selector(openBar:) keyEquivalent:@"l"];
        fileRoot.submenu = fileMenu;
        [mainMenu addItem:fileRoot];
        NSApp.mainMenu = mainMenu;

        DPCommandBar.on = YES;

        _TtC5Popup19PlatformPopupWindow *littleDia = [[_TtC5Popup19PlatformPopupWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300)
                                                                                                        styleMask:NSWindowStyleMaskTitled
                                                                                                          backing:NSBackingStoreBuffered defer:NO];
        NSEvent *littleL = DPKey(littleDia, @"l", 37), *littleT = DPKey(littleDia, @"t", 17);
        CHECK(DPCommandBarKey(littleL) == littleL && DPCommandBarKey(littleT) == littleT,
              "DPCommandBarKey passes through Cmd+L / Cmd+T in Little Dia windows");

        _TtC6Window14PlatformWindow *browser = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                             styleMask:NSWindowStyleMaskTitled
                                                                                               backing:NSBackingStoreBuffered defer:NO];
        browser.fakeSheet = littleDia;
        NSEvent *sheetL = DPKey(browser, @"l", 37);
        CHECK(DPCommandBarKey(sheetL) == sheetL, "DPCommandBarKey passes through when browser window has an attached sheet");
        browser.fakeSheet = nil;

        __weak NSTimer *weakTimer = nil;
        @autoreleasepool {
            DPCommandBarOverlay *temp = [[DPCommandBarOverlay alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
            NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {}];
            temp.watch = t;
            weakTimer = t;
            CHECK(t.valid, "watch timer starts valid");
        }
        CHECK(weakTimer == nil || !weakTimer.valid, "DPCommandBarOverlay -dealloc invalidates watch timer");

        gWindows = @[ browser ];
        NSView *page = [[ntpCls alloc] initWithFrame:browser.contentView.bounds];
        [browser.contentView addSubview:page];
        _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView *popover =
            [[_TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView alloc] initWithFrame:NSMakeRect(0, 0, 200, 50)];
        [popover addSubview:[[DPFakePopoverText alloc] initWithFrame:popover.bounds]];
        [browser.contentView addSubview:popover];

        DPCommandBarOverlay *overlay = [[DPCommandBarOverlay alloc] initWithFrame:browser.contentView.bounds];
        overlay.host = browser;
        overlay.page = page;
        [browser.contentView addSubview:overlay];
        DPSet(browser, &DPOverlayKey, overlay);
        overlay.needsLayout = NO;

        gChoice = @"window";
        DPCountingPanel *countingPanel = [[DPCountingPanel alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)];
        overlay.panel = countingPanel;
        [overlay addSubview:countingPanel];
        [overlay layout];
        NSInteger afterFirst = countingPanel.frameWrites;
        [overlay layout];
        [overlay layout];
        CHECK(afterFirst == 1 && countingPanel.frameWrites == 1,
              "DPCommandBarOverlay -layout skips redundant panel setFrame: when target rect is unchanged");
        overlay.panel = nil;
        [countingPanel removeFromSuperview];
        overlay.needsLayout = NO;
        DPApplyCommandBar(&DPCommandBarBlur);
        CHECK(overlay.needsLayout && gCancelPopoverCalls == 0,
              "DPApplyCommandBar marks overlay needsLayout and sub-patch toggle does not close Cmd+L popover");

        DPSet(page, &DPBlankKey, @YES);
        page.hidden = YES;
        gCleanHideTabCalls = gUpdateSpareTimerCalls = gDropSpareCalls = gClearCatchUpCalls = gFinishHandOverCalls = 0;
        DPCommandBar.on = NO;
        DPApplyCommandBar(&DPCommandBar);
        CHECK(!page.hidden && DPGet(page, &DPBlankKey) == nil, "turning CommandBar off unhides blank page even in non-visible window");
        CHECK(gCleanHideTabCalls == 1 && gUpdateSpareTimerCalls == 1 && gDropSpareCalls == 1 && gClearCatchUpCalls == 1 && gFinishHandOverCalls == 1,
              "turning CommandBar off cleans HideTab, spare timer, spares, catch-up, and hand-over");

        DPInstallCommandBar();
        DPCommandBar.on = YES;
        DPCommandBarOverlay *openOverlay = [[DPCommandBarOverlay alloc] initWithFrame:browser.contentView.bounds];
        openOverlay.host = browser;
        openOverlay.watch = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {}];
        DPSet(browser, &DPOverlayKey, openOverlay);
        gHandedOver = [[DPCommandBarOverlay alloc] initWithFrame:browser.contentView.bounds];
        gHandedOver.host = browser;
        gForgetSpareCalls = gClearCatchUpCalls = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:browser];
        CHECK(DPGet(browser, &DPOverlayKey) == nil && !openOverlay.watch.valid && gHandedOver == nil && gForgetSpareCalls == 1 && gClearCatchUpCalls == 1,
              "NSWindowWillCloseNotification cleans up open overlay, handed-over overlay, spare, and catch-up");

        DPPeekCard *peekCard = [[DPPeekCard alloc] initWithFrame:browser.contentView.bounds];
        peekCard.toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 38)];
        [browser.contentView addSubview:peekCard];
        gHandToDiaCalls = 0;
        NSEvent *peekL = DPKey(browser, @"l", 37), *peekT = DPKey(browser, @"t", 17);
        CHECK(DPCommandBarKey(peekL) == peekL && gHandToDiaCalls == 0,
              "Cmd+L over visible Peek with toolbar bypasses DPHandToDia");
        CHECK(DPCommandBarKey(peekT) == nil && gHandToDiaCalls == 1,
              "Cmd+T over visible Peek still hands off to Command Bar");
        _TtC20AssistantPanelUIBase22AssistantPanelRootView *sideChat =
            [[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        NSView *chatField = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [sideChat addSubview:chatField];
        [browser.contentView addSubview:sideChat];
        browser.fakeResponder = chatField;
        CHECK(DPCommandBarKey(peekL) == nil && gHandToDiaCalls == 2,
              "Cmd+L with focus inside Side Chat still reaches Command Bar");
        browser.fakeResponder = nil;
        [sideChat removeFromSuperview];
        [peekCard removeFromSuperview];

        NSView *blankPage = [[ntpCls alloc] initWithFrame:browser.contentView.bounds];
        [browser.contentView addSubview:blankPage];
        DPSet(blankPage, &DPBlankKey, @YES);
        [DPBlanks(browser) addObject:@"blank-tab"];
        browser.identifier = @"window-a";
        DPFakeTab *blankTab = DPTab(@"blank-tab", @""), *otherTab = DPTab(@"other-tab", @"https://example.org");
        DPFakeSpace *only = DPSpace(@[ blankTab, otherTab ]);
        DPFakeScriptWindow *script = [DPFakeScriptWindow new];
        script.windowId = @"window-a";
        script.appleScriptProfiles = @[ only ];
        DPSwitchTo(script, only);
        gDelegate = [DPFakeAppDelegate new];
        gDelegate.appleScriptWindows = @[ script ];
        NSApp.delegate = (id)gDelegate;
        gHiding = YES;
        NSTextView *rename = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [browser.contentView addSubview:rename];
        NSTextView *blankText = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [blankPage addSubview:blankText];
        NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [browser.contentView addSubview:plain];
        NSEvent *typed = DPTyped(browser, @"a", 0);
        int before = gOpenAttempts;
        browser.fakeResponder = nil;
        CHECK(DPCommandBarKey(typed) == typed && gOpenAttempts == before + 1, "typing with nothing focused opens the bar over the blank tab");
        browser.fakeResponder = plain;
        before = gOpenAttempts;
        DPCommandBarKey(typed);
        CHECK(gOpenAttempts == before + 1, "typing with a non-text view focused still opens the bar");
        browser.fakeResponder = blankText;
        before = gOpenAttempts;
        DPCommandBarKey(typed);
        CHECK(gOpenAttempts == before + 1, "typing in the blank tab's own text still opens the bar");
        browser.fakeResponder = rename;
        before = gOpenAttempts;
        CHECK(DPCommandBarKey(typed) == typed && gOpenAttempts == before, "typing in a rename field doesn't open the bar");
        NSTextField *label = [NSTextField textFieldWithString:@""];
        NSTextView *fieldEditor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        fieldEditor.fieldEditor = YES;
        fieldEditor.delegate = (id)label;
        [browser.contentView addSubview:fieldEditor];
        browser.fakeResponder = fieldEditor;
        DPCommandBarKey(typed);
        CHECK(gOpenAttempts == before, "typing in a text field's editor doesn't open the bar");
        [fieldEditor removeFromSuperview];
        NSView *sideChatInput = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        _TtC20AssistantPanelUIBase22AssistantPanelRootView *chatPanel =
            [[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        [chatPanel addSubview:sideChatInput];
        [browser.contentView addSubview:chatPanel];
        browser.fakeResponder = sideChatInput;
        DPCommandBarKey(typed);
        CHECK(gOpenAttempts == before, "typing in a Side Chat page doesn't open the bar");
        [chatPanel removeFromSuperview];
        DPPeekCard *typingPeek = [[DPPeekCard alloc] initWithFrame:browser.contentView.bounds];
        NSView *peekPage = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [typingPeek addSubview:peekPage];
        [browser.contentView addSubview:typingPeek];
        browser.fakeResponder = peekPage;
        DPCommandBarKey(typed);
        CHECK(gOpenAttempts == before, "typing in a visible Peek page doesn't open the bar");
        typingPeek.hidden = YES;
        DPCommandBarKey(typed);
        CHECK(gOpenAttempts == before + 1, "a hidden Peek doesn't swallow typing on the blank tab");
        [typingPeek removeFromSuperview];
        browser.fakeResponder = nil;
        before = gOpenAttempts;
        DPCommandBarKey(DPTyped(browser, @"a", NSEventModifierFlagCommand));
        DPCommandBarKey(DPTyped(browser, @"a", NSEventModifierFlagControl));
        DPCommandBarKey(DPTyped(browser, @"\x1b", 0));
        DPCommandBarKey(DPTyped(browser, @"\x7f", 0));
        CHECK(gOpenAttempts == before, "shortcuts and control characters don't open the bar");
        DPCommandBarKey(DPTyped(browser, @"å", NSEventModifierFlagOption));
        CHECK(gOpenAttempts == before + 1, "Option-typed characters still open the bar");
        before = gOpenAttempts;
        script.activeTab = otherTab;
        DPCommandBarKey(typed);
        script.activeTab = blankTab;
        gHiding = NO;
        DPCommandBarKey(typed);
        gHiding = YES;
        CHECK(gOpenAttempts == before, "typing doesn't open the bar off the blank tab or with Hide New Tab off");
        [blankPage removeFromSuperview];
        [rename removeFromSuperview];
        [plain removeFromSuperview];
        [DPBlanks(browser) removeAllObjects];
        gHiding = NO;

        gHiding = YES;
        browser.identifier = @"window-a";
        _TtC6Window14PlatformWindow *browserB = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                                styleMask:NSWindowStyleMaskTitled
                                                                                                  backing:NSBackingStoreBuffered defer:NO];
        browserB.identifier = @"window-b";
        DPScene *scene = [[DPScene alloc] initIn:browser];
        [scene watch];
        CHECK([scene open] && !scene.bar.closed && scene.overlay.listlessSince == 0, "the bar stays while its tab is in the space in front");
        [gShownRows removeAllObjects];
        [gNotedSpares removeAllObjects];
        [scene leave];
        [scene watch];
        CHECK(!scene.overlay.host && DPGet(browser, &DPOverlayKey) == nil, "the bar closes when another space comes forward");
        CHECK(scene.bar.closed, "the bar's unused new tab closes, even if the space in front has a single tab");
        CHECK(!scene.back.closed, "the tab the bar was opened from stays");
        CHECK(!DPRecentHas(browser, scene.bar.tabId), "a bar tab closed for another space leaves the recent tabs");
        CHECK(DPLast(gShownRows, scene.bar.tabId, YES), "the closing tab's row stays hidden on its way out");
        CHECK(DPHas(gNotedSpares, scene.bar.tabId, NO) && !DPHas(gNotedSpares, scene.bar.tabId, YES),
              "a tab left behind in another space is no longer noted as a spare");

        scene = [[DPScene alloc] initIn:browser];
        scene.script.front = DPSpace(@[]);
        scene.script.activeTab = nil;
        [scene watch];
        CHECK([scene open] && !scene.bar.closed && scene.overlay.listlessSince > 0, "a swipe listing no tabs waits instead of deciding");
        [scene leave];
        [scene watch];
        CHECK(!scene.overlay.host && scene.bar.closed, "the tab closes once the swipe settles on another space");

        scene = [[DPScene alloc] initIn:browser];
        scene.script.front = DPSpace(@[]);
        [scene watch];
        scene.overlay.listlessSince = CACurrentMediaTime() - 10;
        [scene watch];
        CHECK(!scene.overlay.host && scene.bar.closed, "a space listing no tabs for good stops waiting");

        scene = [[DPScene alloc] initIn:browser];
        scene.bar.URL = @"https://example.net";
        [scene leave];
        [scene watch];
        CHECK(!scene.overlay.host && !scene.bar.closed && DPLast(gShownRows, scene.bar.tabId, NO),
              "a tab a result is loading in is kept when another space comes forward");

        scene = [[DPScene alloc] initIn:browser];
        NSView *barPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
        NSTextView *barField = [[NSTextView alloc] initWithFrame:barPanel.bounds];
        barField.string = @"example.net";
        [barPanel addSubview:barField];
        scene.overlay.panel = barPanel;
        scene.overlay.picked = YES;
        [scene leave];
        [scene watch];
        CHECK(!scene.overlay.host && !scene.bar.closed, "a tab whose result was just picked is kept before its page starts loading");

        scene = [[DPScene alloc] initIn:browser];
        [scene.old.appleScriptTabs removeObject:scene.back];
        [scene leave];
        [scene watch];
        CHECK(!scene.overlay.host && !scene.bar.closed, "a space's only tab is kept");

        scene = [[DPScene alloc] initIn:browser];
        scene.overlay.overBlank = YES;
        [scene leave];
        [scene watch];
        CHECK(!scene.overlay.host && !scene.bar.closed, "a tab opened over a blank tab is kept");

        scene = [[DPScene alloc] initIn:browser];
        gHiding = NO;
        [scene leave];
        [scene watch];
        gHiding = YES;
        CHECK(!scene.overlay.host && !scene.bar.closed, "with Hide New Tab off, the visible new tab is left as it was");

        scene = [[DPScene alloc] initIn:browser];
        scene.script.windowId = @"unknown";
        [scene watch];
        CHECK(!scene.overlay.host && !scene.bar.closed, "a window Dia no longer lists doesn't leave the bar waiting for good");

        scene = [[DPScene alloc] initIn:browser];
        gSpare = scene.overlay;
        [scene leave];
        [scene watch];
        CHECK(scene.overlay.host == browser && !scene.bar.closed, "a parked spare is left alone when another space comes forward");
        gSpare = nil;
        [scene.overlay.watch invalidate];
        DPDismiss(scene.overlay, NO);

        DPScene *first = [[DPScene alloc] initIn:browser], *second = [[DPScene alloc] initIn:browserB];
        [second leave];
        [first watch];
        [second watch];
        CHECK([first open] && !first.bar.closed, "switching space in one window leaves another window's bar and tab alone");
        CHECK(!second.overlay.host && second.bar.closed && !second.back.closed, "switching space in a window closes only that window's bar tab");
        [first leave];
        [first watch];
        CHECK(!first.overlay.host && first.bar.closed, "the other window's bar closes on its own switch");

        NSView *barPage = [[ntpCls alloc] initWithFrame:browser.contentView.bounds];
        [browser.contentView addSubview:barPage];
        scene = [[DPScene alloc] initIn:browser];
        scene.overlay.page = barPage;
        [scene leave];
        DPCancelCommandBar(scene.overlay);
        CHECK(!scene.overlay.host && scene.bar.closed && !scene.back.closed, "cancelling a bar left in another space closes its tab even if the space in front has one tab");
        scene = [[DPScene alloc] initIn:browser];
        scene.overlay.page = barPage;
        [scene.old.appleScriptTabs removeObject:scene.back];
        scene.overlay.returnTab = scene.back;
        [scene leave];
        DPCancelCommandBar(scene.overlay);
        CHECK(!scene.overlay.host && !scene.bar.closed, "cancelling a bar left in another space keeps its space's only tab");
        scene = [[DPScene alloc] initIn:browser];
        scene.overlay.page = barPage;
        DPCancelCommandBar(scene.overlay);
        CHECK(!scene.overlay.host && scene.bar.closed, "cancelling a bar in the space in front still closes its tab");
        CHECK(!DPRecentHas(browser, scene.bar.tabId), "a cancelled bar's closed tab leaves the recent tabs");
        scene = [[DPScene alloc] initIn:browser];
        scene.overlay.page = barPage;
        DPFakeTab *elsewhere = DPTab(@"window-a-elsewhere", @"https://example.net");
        [scene.old.appleScriptTabs addObject:elsewhere];
        scene.script.activeTab = elsewhere;
        [scene watch];
        CHECK(!scene.overlay.host && scene.bar.closed && !scene.back.closed && !elsewhere.closed && !DPRecentHas(browser, scene.bar.tabId),
              "a bar left behind by a tab switch closes its tab and drops it from the recent tabs");
        [barPage removeFromSuperview];
        gHiding = NO;

        gHiding = YES;
        DPCommandBar.on = YES;
        _TtC6Window14PlatformWindow *noteWindow = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                                  styleMask:NSWindowStyleMaskTitled
                                                                                                    backing:NSBackingStoreBuffered defer:NO];
        noteWindow.identifier = @"window-note";
        gWindows = @[ noteWindow ];
        NSView *notePage = [[ntpCls alloc] initWithFrame:noteWindow.contentView.bounds];
        [noteWindow.contentView addSubview:notePage];
        _TtC20AssistantPanelUIBase22AssistantPanelRootView *notePanel =
            [[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)];
        [notePage addSubview:notePanel];
        DPFakeTab *noteBack = DPTab(@"note-back", @"https://example.org"), *noteBar = DPTab(@"note-bar", @"");
        DPFakeSpace *noteSpace = DPSpace(@[ noteBack, noteBar ]);
        DPFakeScriptWindow *noteScript = [DPFakeScriptWindow new];
        noteScript.windowId = @"window-note";
        noteScript.appleScriptProfiles = @[ noteSpace ];
        noteScript.front = noteSpace;
        noteScript.activeTab = noteBar;
        gDelegate.appleScriptWindows = @[ noteScript ];
        DPSet(noteWindow, &DPRecentKey, @[ @"note-back", @"note-bar" ]);
        [gNotedOpenTabs removeAllObjects];
        DPPresentCommandBar(notePage, NO);
        CHECK(DPHas(gNotedOpenTabs, @"note-bar", YES), "opening the bar over a new tab notes it as an open bar tab");
        DPCommandBarOverlay *noteOverlay = DPGet(noteWindow, &DPOverlayKey);
        CHECK(noteOverlay != nil, "the bar opens over the new tab");
        [gNotedSpares removeAllObjects];
        DPDismiss(noteOverlay, NO);
        CHECK(DPHas(gNotedSpares, @"note-bar", NO), "dismissing the bar stops noting its open bar tab");
        [notePage removeFromSuperview];
        gHiding = NO;

        gHiding = YES;
        DPCommandBar.on = YES;
        _TtC6Window14PlatformWindow *launch = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                              styleMask:NSWindowStyleMaskTitled
                                                                                                backing:NSBackingStoreBuffered defer:NO];
        launch.identifier = @"window-launch";
        gWindows = @[ launch ];
        DPFakeTab *launchTab = DPTab(@"launch-new", @""), *launchOther = DPTab(@"launch-other", @"https://example.org");
        DPFakeScriptWindow *launchScript = [DPFakeScriptWindow new];
        launchScript.windowId = @"window-launch";
        launchScript.front = DPSpace(@[ launchOther, launchTab ]);
        launchScript.appleScriptProfiles = @[ launchScript.front ];
        launchScript.activeTab = launchTab;
        gDelegate.appleScriptWindows = @[ launchScript ];
        NSView *launchPage = [[ntpCls alloc] initWithFrame:launch.contentView.bounds];
        [launchPage addSubview:[[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)]];
        [gHiddenRowIDs removeAllObjects];
        gStandIn = nil;
        [launch.contentView addSubview:launchPage];
        DPCommandBarOverlay *launchBar = DPGet(launch, &DPOverlayKey);
        CHECK(launchBar && !launchBar.returnTab, "the bar opens over a launch tab with no tab to go back to");
        CHECK([gHiddenRowIDs containsObject:@"launch-new"] && [gStandIn isEqual:@"launch-new"],
              "the launch tab's row hides behind the bar and the New Tab button stands in for it");
        DPDismiss(launchBar, NO);
        [launchPage removeFromSuperview];

        _TtC6Window14PlatformWindow *closer = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                              styleMask:NSWindowStyleMaskTitled
                                                                                                backing:NSBackingStoreBuffered defer:NO];
        closer.identifier = @"window-closer";
        gWindows = @[ closer ];
        DPFakeTab *closedTab = DPTab(@"closed-tab", @"https://example.org"), *replacement = DPTab(@"replacement-tab", @"");
        DPFakeScriptWindow *closerScript = [DPFakeScriptWindow new];
        closerScript.windowId = @"window-closer";
        closerScript.front = DPSpace(@[ closedTab ]);
        closerScript.appleScriptProfiles = @[ closerScript.front ];
        closerScript.activeTab = closedTab;
        gDelegate.appleScriptWindows = @[ closerScript ];
        DPNoteActiveTab(closer, closerScript, NULL);
        _TtC5TabUI14TabContentView *closedRow = [[_TtC5TabUI14TabContentView alloc] initWithFrame:NSMakeRect(0, 0, 200, 37)];
        [closer.contentView addSubview:closedRow];
        [closedRow closeButtonClicked];
        CHECK(closedRow.closes == 1, "the sidebar's X still reaches Dia");
        [closerScript.front.appleScriptTabs addObject:replacement];
        closerScript.activeTab = replacement;
        DPNoteActiveTab(closer, closerScript, NULL);
        NSView *replacementPage = [[ntpCls alloc] initWithFrame:closer.contentView.bounds];
        [replacementPage addSubview:[[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)]];
        [closer.contentView addSubview:replacementPage];
        CHECK(DPGet(closer, &DPOverlayKey) == nil && replacementPage.hidden && [DPBlanks(closer) containsObject:@"replacement-tab"] && !DPGet(replacementPage, &DPOwnBarKey),
              "closing the last tab with the sidebar's X leaves its replacement blank, not a bar going back to the closed tab or Dia's own page");
        [replacementPage removeFromSuperview];

        DPCheckRepeatedNewTab(ntpCls, stripCls, NO, NO, YES);
        DPCheckRepeatedNewTab(ntpCls, stripCls, NO, YES, NO);
        DPCheckRepeatedNewTab(ntpCls, stripCls, YES, NO, NO);
        DPCheckRepeatedNewTab(ntpCls, stripCls, YES, YES, YES);
        gHiding = YES;

        _TtC6Window14PlatformWindow *gone = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                           styleMask:NSWindowStyleMaskTitled
                                                                                             backing:NSBackingStoreBuffered defer:NO];
        gone.identifier = @"window-gone";
        gWindows = @[ gone ];
        DPFakeTab *goneKeep = DPTab(@"gone-keep", @"https://example.org"), *goneClosed = DPTab(@"gone-closed", @""), *goneNew = DPTab(@"gone-new", @"");
        DPFakeScriptWindow *goneScript = [DPFakeScriptWindow new];
        goneScript.windowId = @"window-gone";
        goneScript.front = DPSpace(@[ goneKeep, goneClosed ]);
        goneScript.appleScriptProfiles = @[ goneScript.front ];
        goneScript.activeTab = goneClosed;
        gDelegate.appleScriptWindows = @[ goneScript ];
        DPNoteActiveTab(gone, goneScript, NULL);
        [goneScript.front.appleScriptTabs removeObject:goneClosed];
        [goneScript.front.appleScriptTabs addObject:goneNew];
        NSView *gonePage = [[ntpCls alloc] initWithFrame:gone.contentView.bounds];
        [gonePage addSubview:[[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)]];
        [gone.contentView addSubview:gonePage];
        CHECK(DPGet(gone, &DPOverlayKey) == nil && !gonePage.hidden && DPGet(gonePage, &DPOwnBarKey),
              "a tab Dia still names active after closing by any route leaves the survivor's own page, not a bar for the closed tab");
        goneScript.activeTab = goneNew;
        DPNoteActiveTab(gone, goneScript, NULL);
        CHECK(![DPSeenTabs(gone) containsObject:@"gone-closed"] && [DPSeenTabs(gone) containsObject:@"gone-keep"] && ![DPKeptTabs(gone) containsObject:@"gone-closed"],
              "a closed tab leaves the seen and kept sets, and only its own window's");
        [gonePage removeFromSuperview];
        NSMenuItem *closeOthers = [[NSMenuItem alloc] initWithTitle:@"Close Other Tabs" action:nil keyEquivalent:@""];
        gKeyWindow = littleDia;
        gMainWindow = gone;
        [NSNotificationCenter.defaultCenter postNotificationName:NSMenuWillSendActionNotification object:nil userInfo:@{ @"MenuItem" : closeOthers }];
        CHECK(DPGet(gone, &DPClosedAtKey) != nil && DPGet(littleDia, &DPClosedAtKey) == nil && fabs([DPGet(gone, &DPClosedAtKey) doubleValue] - NSProcessInfo.processInfo.systemUptime) < 5,
              "a close from the menu stamps the browser window it acts on, not whichever window is key");
        gKeyWindow = gMainWindow = nil;
        DPSet(gone, &DPClosedAtKey, nil);

        DPFakeTab *noID = DPTab(nil, @""), *emptyID = DPTab(@"", @"");
        DPFakeScriptWindow *idsScript = [DPFakeScriptWindow new];
        idsScript.windowId = @"window-ids";
        idsScript.front = DPSpace(@[ noID, emptyID ]);
        idsScript.activeTab = emptyID;
        gDelegate.appleScriptWindows = @[ idsScript ];
        gone.identifier = @"window-ids";
        BOOL emptySeen = YES;
        CHECK(!DPNoteActiveTab(gone, idsScript, &emptySeen) && !emptySeen, "tabs whose ID Dia hasn't given yet are not one tab already seen");

        DPFakeTab *lateOther = DPTab(@"late-other", @"https://example.org"), *lateTab = DPTab(nil, @"");
        DPFakeScriptWindow *lateScript = [DPFakeScriptWindow new];
        _TtC6Window14PlatformWindow *late = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                           styleMask:NSWindowStyleMaskTitled
                                                                                             backing:NSBackingStoreBuffered defer:NO];
        late.identifier = @"window-late";
        gWindows = @[ late ];
        lateScript.windowId = @"window-late";
        lateScript.front = DPSpace(@[ lateOther, lateTab ]);
        lateScript.appleScriptProfiles = @[ lateScript.front ];
        lateScript.activeTab = lateTab;
        gDelegate.appleScriptWindows = @[ lateScript ];
        NSView *latePage = [[ntpCls alloc] initWithFrame:late.contentView.bounds];
        [latePage addSubview:[[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)]];
        [gHiddenRowIDs removeAllObjects];
        gStandIn = nil;
        [late.contentView addSubview:latePage];
        DPCommandBarOverlay *lateBar = DPGet(late, &DPOverlayKey);
        CHECK(lateBar != nil, "the bar opens over a tab Dia hasn't named yet");
        lateTab.tabId = @"launch-late";
        DPSpin(0.4);
        CHECK([gHiddenRowIDs containsObject:@"launch-late"] && [gStandIn isEqual:@"launch-late"],
              "a launch tab named after its page mounts still hides its row and stands the New Tab button in for it");
        DPDismiss(lateBar, NO);
        [latePage removeFromSuperview];
        gone.identifier = @"window-gone";

        _TtC6Window14PlatformWindow *grouping = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                                styleMask:NSWindowStyleMaskTitled
                                                                                                  backing:NSBackingStoreBuffered defer:NO];
        grouping.identifier = @"window-grouping";
        gWindows = @[ grouping ];
        gKeyWindow = grouping;
        DPFakeTab *groupFront = DPTab(@"group-front", @"https://example.org"), *groupTab = DPTab(@"group-tab", @"");
        DPFakeScriptWindow *groupScript = [DPFakeScriptWindow new];
        groupScript.windowId = @"window-grouping";
        groupScript.front = DPSpace(@[ groupFront, groupTab ]);
        groupScript.appleScriptProfiles = @[ groupScript.front ];
        groupScript.activeTab = groupFront;
        gDelegate.appleScriptWindows = @[ groupScript ];
        DPNoteActiveTab(grouping, groupScript, NULL);
        NSMenuItem *newGroup = [[NSMenuItem alloc] initWithTitle:@"New Group" action:nil keyEquivalent:@""];
        [NSNotificationCenter.defaultCenter postNotificationName:NSMenuWillSendActionNotification object:nil userInfo:@{ @"MenuItem" : newGroup }];
        groupScript.activeTab = groupTab;
        NSView *groupPage = [[ntpCls alloc] initWithFrame:grouping.contentView.bounds];
        [groupPage addSubview:[[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)]];
        [grouping.contentView addSubview:groupPage];
        CHECK(DPGet(grouping, &DPOverlayKey) == nil && !groupPage.hidden && DPGet(groupPage, &DPOwnBarKey),
              "New Group's new tab keeps Dia's page so the group's name field keeps the keyboard");
        [groupPage removeFromSuperview];
        DPFakeTab *groupBarTab = DPTab(@"group-bar", @"");
        [groupScript.front.appleScriptTabs addObject:groupBarTab];
        DPCommandBarOverlay *groupBar = DPBarFor(grouping, groupBarTab, groupTab);
        NSView *backPage = [[ntpCls alloc] initWithFrame:grouping.contentView.bounds];
        [grouping.contentView addSubview:backPage];
        CHECK(DPGet(grouping, &DPOverlayKey) == groupBar && !groupBarTab.closed && DPGet(backPage, &DPOwnBarKey),
              "⌘T from the group's empty tab keeps the bar when it switches back to that tab's own page");
        [backPage removeFromSuperview];
        [groupBar.watch invalidate];
        DPDismiss(groupBar, NO);
        gKeyWindow = nil;
        gHiding = NO;

        Class barCls = objc_allocateClassPair(NSView.class, DPDiaCommandBar, 0);
        NSWindow *addressBarHost;
        objc_registerClassPair(barCls);
        gChoice = @"window";
        NSView *barHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        DPCommandBarOverlay *newTabBar = [[DPCommandBarOverlay alloc] initWithFrame:barHost.bounds];
        newTabBar.host = browser;
        addressBarHost = browser;
        NSView *newTabPage = [[NSView alloc] initWithFrame:NSZeroRect];
        newTabBar.page = newTabPage;
        NSView *newTabPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 60)], *newTabRoot = [[barCls alloc] initWithFrame:NSMakeRect(0, 0, 500, 60)];
        [newTabPanel addSubview:newTabRoot];
        [newTabBar addSubview:newTabPanel];
        newTabBar.panel = newTabPanel;
        [barHost addSubview:newTabBar];
        CGFloat newTabTop = NSMinY([newTabBar frameForPanelSize:NSMakeSize(500, 60)]);
        DPCommandBarOverlay *addressBar = [[DPCommandBarOverlay alloc] initWithFrame:barHost.bounds];
        addressBar.host = addressBarHost;
        addressBar.page = popover;
        NSView *addressPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 84)];
        [addressBar addSubview:addressPanel];
        addressBar.panel = addressPanel;
        [barHost addSubview:addressBar];
        CHECK(NSMinY([addressBar frameForPanelSize:NSMakeSize(500, 84)]) == newTabTop, "⌘L's bar opens with its top where ⌘T's was");
        [addressBar removeFromSuperview];
        gHiding = NO;
        for (NSString *position in @[ @"macos", @"window", @"page" ])
            for (NSNumber *panelFirst in @[ @YES, @NO ]) {
                gChoice = position;
                NSView *openPage, *openPanel;
                DPCommandBarOverlay *opened = DPOpenBar(ntpCls, [NSString stringWithFormat:@"window-open-%@-%@", position, panelFirst], panelFirst.boolValue, &openPage, &openPanel);
                NSString *what = [NSString stringWithFormat:@"the bar (%@, %@ first) opens at its anchor on its first frame", position, panelFirst.boolValue ? @"panel" : @"page"];
                CHECK(opened && openPanel.superview == opened && NSEqualRects(openPanel.frame, [opened frameForPanelSize:openPanel.frame.size]) && ![openPanel.layer animationForKey:@"slide"],
                      what.UTF8String);
                [opened.watch invalidate];
                DPDismiss(opened, NO);
                [openPage removeFromSuperview];
            }
        gChoice = @"window";

        // #619: each window keeps its own bar height, so one window's new tab bar never places another window's Cmd+L popover.
        DPCommandBarOverlay *newTabBarA = [[DPCommandBarOverlay alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        newTabBarA.host = browser;
        NSView *newTabPageA = [[ntpCls alloc] initWithFrame:NSZeroRect];
        newTabBarA.page = newTabPageA;
        NSView *panelA = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 60)];
        [panelA addSubview:[[barCls alloc] initWithFrame:NSMakeRect(0, 0, 500, 60)]];
        newTabBarA.panel = panelA;
        CGFloat topA = NSMinY([newTabBarA frameForPanelSize:NSMakeSize(500, 60)]);
        DPCommandBarOverlay *popoverBarB = [[DPCommandBarOverlay alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        popoverBarB.host = browserB;
        popoverBarB.page = popover;
        NSView *panelB = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 84)];
        popoverBarB.panel = panelB;
        CGFloat topB = NSMinY([popoverBarB frameForPanelSize:NSMakeSize(500, 84)]);
        CHECK(topA == round(NSMidY(newTabBarA.bounds) - 30), "the new tab bar places its top from its own one line height");
        CHECK(topB == round(NSMidY(popoverBarB.bounds) - 42),
              "a window without a bar of its own places Cmd+L from its own height, not another window's");

        Class suggestionsCls = objc_allocateClassPair(DPFakeSuggestions.class, DPDiaCommandBarSuggestions, 0);
        objc_registerClassPair(suggestionsCls);
        Class toolbarCls = objc_allocateClassPair(NSView.class, DPDiaCommandBarToolbar, 0);
        objc_registerClassPair(toolbarCls);
        for (NSString *position in @[ @"macos", @"window", @"page" ])
            for (NSNumber *compact in @[ @NO, @YES ])
                DPCheckFirstCommandL(popover.class, barCls, suggestionsCls, toolbarCls, position, compact.boolValue);
        gChoice = @"window";

        // #618: mounting a content pane with the bar off must not walk Dia's scripting bridge.
        NSView *offPane = [[paneCls alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [browser.contentView addSubview:offPane];
        DPCommandBar.on = NO;
        gScriptReads = 0;
        DPContentPane_viewDidMoveToWindow(offPane, @selector(viewDidMoveToWindow));
        DPNewTabPage_viewDidMoveToWindow([[ntpCls alloc] initWithFrame:NSZeroRect], @selector(viewDidMoveToWindow));
        CHECK(gScriptReads == 0, "mounting content panes with Command Bar off never reads Dia's scripting bridge");
        DPCommandBar.on = YES;
        gScriptReads = 0;
        DPContentPane_viewDidMoveToWindow(offPane, @selector(viewDidMoveToWindow));
        CHECK(gScriptReads > 0, "and with the bar on it still notes the tab it mounted for");
        [offPane removeFromSuperview];

        // #619: dragging a shade slider refreshes the shade it made instead of building a new one per tick.
        NSUserDefaults *tuning = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
        DPCommandBar.on = YES;
        DPCommandBarBlur.on = YES;
        DPCommandBarDarken.on = YES;
        DPCommandBarShadow.on = YES;
        DPCommandBarOverlay *shadeBar = [[DPCommandBarOverlay alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        shadeBar.host = browser;
        shadeBar.returnTab = DPTab(@"shade-back", @"https://example.org");
        NSView *shadePanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 60)];
        shadeBar.panel = shadePanel;
        DPShowShade(shadeBar);
        NSView *firstShade = shadeBar.shade, *firstBlur = shadeBar.windowBlur;
        NSShadow *firstShadow = shadeBar.panel.shadow;
        for (int i = 0; i < 100; i++) {
            [tuning setDouble:i / 100.0 forKey:@"commandBarDarkness"];
            [tuning setDouble:10 + i / 100.0 forKey:@"commandBarBlurRadius"];
            DPShowShade(shadeBar);
        }
        CHECK(firstShade != nil && shadeBar.shade == firstShade && shadeBar.windowBlur == firstBlur,
              "100 slider ticks keep the same shade and blur views");
        CHECK(firstShadow != nil && [shadeBar.panel.shadow.shadowColor isEqual:firstShadow.shadowColor],
              "refreshing the shade leaves the panel's shadow as it was");
        [tuning removeObjectForKey:@"commandBarDarkness"];
        [tuning removeObjectForKey:@"commandBarBlurRadius"];
        DPCommandBarBlur.on = YES;
        DPCommandBarDarken.on = YES;

        setenv("DIATWEAKS_DOMAIN", "com.diapatches.lifecycle-domain", 1);
        NSUserDefaults *scratch = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches.lifecycle-domain"];
        [scratch setDouble:0.5 forKey:@"commandBarHeight"];
        CHECK(DPTuned(DPHeightKey) == 0.5, "the bar's saved tuning follows DIATWEAKS_DOMAIN");
        [scratch removePersistentDomainForName:@"com.diapatches.lifecycle-domain"];
        unsetenv("DIATWEAKS_DOMAIN");

        NSScrollView *fieldScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 10, 200, 23)];
        NSTextView *field = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 23)];
        field.font = [NSFont systemFontOfSize:16];
        field.verticallyResizable = YES;
        fieldScroll.documentView = field;
        [newTabRoot addSubview:fieldScroll];
        newTabPanel.frame = [newTabBar frameForPanelSize:newTabPanel.frame.size];
        newTabBar.keyMonitor = DPWatchKeys(newTabBar);
        [field insertText:@"a query long enough to wrap onto a second line in the floating bar" replacementRange:NSMakeRange(0, 0)];
        CHECK(NSHeight(newTabPanel.frame) == 60 + 23 && NSMinY(newTabPanel.frame) == newTabTop, "the bar grows a line downward once its text wraps");
        [field insertText:@"short" replacementRange:NSMakeRange(0, field.string.length)];
        CHECK(NSHeight(newTabPanel.frame) == 60 && NSMinY(newTabPanel.frame) == newTabTop, "the bar shrinks back to one line");
        DPStopWatching(newTabBar);
        CHECK(newTabBar.textWatch == nil, "closing the bar stops watching its text");
        CFAbsoluteTime textStart = CFAbsoluteTimeGetCurrent();
        for (int i = 0; i < 20000; i++) { @autoreleasepool { DPBarText(newTabBar); } }
        printf("bar_text_us=%.3f\n", (CFAbsoluteTimeGetCurrent() - textStart) * 1e6 / 20000);

        Class logoCls = objc_allocateClassPair(NSView.class, "_TtC10NewTabPage8LogoView", 0);
        objc_registerClassPair(logoCls);
        NSView *logoPage = [[ntpCls alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)], *logo = [[logoCls alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)];
        [logoPage addSubview:logo];
        CHECK(DPHideNewTabLogo.hides(logo) && !DPHideNewTabLogo.hides([[logoCls alloc] initWithFrame:NSZeroRect]) && !DPHideNewTabLogo.hides(logoPage),
              "#598: Hide New Tab Logo matches Dia 1.58's logo view, only on a new tab page");
        CHECK(!strcmp(DPHideNewTabLogo.classes[0], DPDiaNewTabPage) && !DPHideNewTabLogo.classes[1],
              "Hide New Tab Logo stays available without the older logo classes");

        Class settingsCls = objc_allocateClassPair(NSViewController.class, DPDiaSettingsController, 0);
        objc_registerClassPair(settingsCls);
        DPKeepWindowsActive.install();
        NSWindow *settings = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                           backing:NSBackingStoreBuffered defer:NO];
        NSViewController *settingsController = [settingsCls new];
        settingsController.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        settings.contentViewController = settingsController;
        NSWindow *behind = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered defer:NO];
        DPKeepWindowsActive.on = YES;
        CHECK(behind._hasActiveAppearance && behind.hasKeyAppearance, "Keep Windows Active keeps a browser window looking active");
        CHECK(settings._hasActiveAppearance == DPAppKitAnswer(settings, @selector(_hasActiveAppearance)) && settings.hasKeyAppearance == DPAppKitAnswer(settings, @selector(hasKeyAppearance)),
              "the Settings window itself isn't kept looking active");
        DPKeepWindowsActive.on = NO;
        CHECK(behind._hasActiveAppearance == DPAppKitAnswer(behind, @selector(_hasActiveAppearance)), "Keep Windows Active off leaves AppKit's answer");

        DPCommandBar.on = YES;
        gHiding = YES;
        _TtC6Window14PlatformWindow *clicks = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                              styleMask:NSWindowStyleMaskTitled
                                                                                                backing:NSBackingStoreBuffered defer:NO];
        clicks.identifier = @"window-clicks";
        gWindows = @[ clicks ];
        NSView *strip = [[stripCls alloc] initWithFrame:NSMakeRect(0, 0, 600, 40)], *plus = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 28, 28)];
        [strip addSubview:plus];
        [clicks.contentView addSubview:strip];
        gShowSpare = YES;
        gHolds = 0;
        DPPlusButton_mouseDown(plus, @selector(mouseDown:), nil);
        DPTabList_backgroundDoubleClick(strip, @selector(handleBackgroundDoubleClick:), nil);
        DPNewTabButton_mouseDown(plus, @selector(mouseDown:), nil);
        CHECK(gHolds == 3, "a New Tab click the bar takes itself still holds Auto PiP");
        gShowSpare = NO;
        [strip removeFromSuperview];
        gHidingATab = YES;
        gRelayouts = 0;
        NSView *tabList = [[tabListCls alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
        [clicks.contentView addSubview:tabList];
        CHECK(gRelayouts > 0, "a sidebar mounting while a tab is hidden lays out again to park its row");
        gHidingATab = NO;
        [tabList removeFromSuperview];

        [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeTab:) keyEquivalent:@"w"];
        NSEvent *chord = DPTyped(clicks, @"x", NSEventModifierFlagCommand);
        DPCommandBarKey(chord);
        gMenuWalks = 0;
        for (int i = 0; i < 50; i++) DPCommandBarKey(chord);
        CHECK(gMenuWalks == 0, "⌘-chords match Dia's menu items without walking the whole menu each key press");
        CHECK(DPGet(clicks, &DPClosedAtKey) == nil, "only Close Tab's own chord stamps a close");
        DPCommandBarKey(DPKey(clicks, @"w", 13));
        CHECK(DPGet(clicks, &DPClosedAtKey) != nil && fabs([DPGet(clicks, &DPClosedAtKey) doubleValue] - NSProcessInfo.processInfo.systemUptime) < 5,
              "Close Tab's chord stamps a close on the clock the other stamps use");
        DPSet(clicks, &DPClosedAtKey, nil);
        NSMenuItem *replaced = [fileMenu itemWithTitle:@"New Tab"];
        [fileMenu removeItem:replaced];
        [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"y"];
        CHECK(DPIsShortcut(DPKey(clicks, @"y", 16), @"New Tab") && !DPIsShortcut(DPKey(clicks, @"t", 17), @"New Tab"),
              "a menu item Dia replaces is looked up again");
        [fileMenu itemWithTitle:@"New Tab"].keyEquivalent = @"t";

        DPCommandBar.on = NO;
        DPApplyCommandBar(&DPCommandBar);
        CHECK(DPKeyMonitor == nil, "with the bar off no key monitor runs");
        DPCommandBar.on = YES;
        DPApplyCommandBar(&DPCommandBar);
        id monitor = DPKeyMonitor;
        DPApplyCommandBar(&DPCommandBarBlur);
        CHECK(monitor && DPKeyMonitor == monitor, "turning the bar on watches keys once");
        DPCommandBar.on = NO;
        DPApplyCommandBar(&DPCommandBar);
        CHECK(DPKeyMonitor == nil, "turning the bar off removes its key monitor");
        gHiding = NO;

        [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] removePersistentDomainForName:DPTestSuiteName()];
        if (failures) return 1;
        puts("PASS: CommandBar key-window guard, dealloc/window-close cleanup, and off-tweak teardown");
    }
    return 0;
}

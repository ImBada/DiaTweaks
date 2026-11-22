#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "Patches/CommandBar/CommandBar.m"
#import "Patches/CommandBar/Tabs.h"

static BOOL gHiding;
static int gOpenAttempts;
static int gCleanHideTabCalls, gUpdateSpareTimerCalls, gForgetSpareCalls, gDropSpareCalls, gClearCatchUpCalls, gFinishHandOverCalls, gCancelPopoverCalls, gHandToDiaCalls;
static DPCommandBarOverlay *gHandedOver;
static NSString *gChoice = @"macos";
static NSArray<NSWindow *> *gWindows;

NSString *DPChoice(DPPatch *patch) { return gChoice; }
void DPInstallAutoPipHold(void) {}
void DPHoldAutoPip(void) {}
BOOL DPHiding(void) { return gHiding; }
void DPExpectNewTab(NSWindow *window) {}
void DPStopExpecting(void) { gOpenAttempts++; }
void DPHideTabRow(NSString *tabID, NSWindow *window) {}
static NSMutableArray<NSArray *> *gShownRows, *gNotedSpares;
void DPShowTabRow(NSString *tabID, BOOL closing) { [gShownRows addObject:@[ tabID ?: @"", @(closing) ]]; }
BOOL DPHidesTab(NSString *tabID) { return NO; }
void DPParkTab(NSString *tabID, BOOL parked) {}
void DPHideBlank(NSString *tabID, BOOL hidden, NSWindow *window) {}
BOOL DPParksTab(NSString *tabID) { return NO; }
void DPFreezeLists(NSWindow *window) {}
BOOL DPOnlyListedTab(NSString *tabID, NSString *closingID, NSWindow *window) { return NO; }
void DPStandInFor(NSWindow *window, NSString *tabID) {}
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
BOOL DPShowSpare(NSWindow *window) { return NO; }
void DPDropSpare(NSWindow *window) { gDropSpareCalls++; }
void DPForgetSpare(NSWindow *window) { gForgetSpareCalls++; }
void DPUpdateSpareTimer(void) { gUpdateSpareTimerCalls++; }
static DPCommandBarOverlay *gSpare;
DPCommandBarOverlay *DPSpareIn(NSWindow *window) { return gSpare.host == window ? gSpare : nil; }
void DPNoteSpare(NSString *tabID, BOOL parked) { [gNotedSpares addObject:@[ tabID ?: @"", @(parked) ]]; }
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

@interface _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView : NSView
@end
@implementation _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView
@end

static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gWindows; }


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

@interface DPFakeAppDelegate : NSObject
@property(strong) NSArray<DPFakeScriptWindow *> *appleScriptWindows;
@end
@implementation DPFakeAppDelegate
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

// A window with the bar open over a new tab in its old space, and another space ready to come forward.
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

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gShownRows = [NSMutableArray array];
        gNotedSpares = [NSMutableArray array];
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);

        Class ntpCls = objc_allocateClassPair(DPFakeNewTabPage.class, DPDiaNewTabPage, 0);
        objc_registerClassPair(ntpCls);

        NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *fileRoot = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
        NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
        [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
        [fileMenu addItemWithTitle:@"Open Command Bar" action:@selector(openBar:) keyEquivalent:@"l"];
        fileRoot.submenu = fileMenu;
        [mainMenu addItem:fileRoot];
        NSApp.mainMenu = mainMenu;

        DPCommandBar.on = YES;

        // 1. Regression: DPCommandBarKey ignores non-DPDiaWindow (Little Dia / Settings) and sheet-attached browser windows.
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

        // 2. Regression: DPCommandBarOverlay -dealloc invalidates watch timer.
        __weak NSTimer *weakTimer = nil;
        @autoreleasepool {
            DPCommandBarOverlay *temp = [[DPCommandBarOverlay alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
            NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {}];
            temp.watch = t;
            weakTimer = t;
            CHECK(t.valid, "watch timer starts valid");
        }
        CHECK(weakTimer == nil || !weakTimer.valid, "DPCommandBarOverlay -dealloc invalidates watch timer");

        // 3. Regression: DPApplyCommandBar repositions open overlay on Position choice change, and toggling sub-patch doesn't close popover.
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

        // 4. Regression: Turning CommandBar OFF clears invisible window blanks, cleans HideTab, stops spare timer, and clears swap state.
        DPSet(page, &DPBlankKey, @YES);
        page.hidden = YES;
        gCleanHideTabCalls = gUpdateSpareTimerCalls = gDropSpareCalls = gClearCatchUpCalls = gFinishHandOverCalls = 0;
        DPCommandBar.on = NO;
        DPApplyCommandBar(&DPCommandBar);
        CHECK(!page.hidden && DPGet(page, &DPBlankKey) == nil, "turning CommandBar off unhides blank page even in non-visible window");
        CHECK(gCleanHideTabCalls == 1 && gUpdateSpareTimerCalls == 1 && gDropSpareCalls == 1 && gClearCatchUpCalls == 1 && gFinishHandOverCalls == 1,
              "turning CommandBar off cleans HideTab, spare timer, spares, catch-up, and hand-over");

        // 5. Regression: NSWindowWillCloseNotification tears down overlay, handed-over overlay, and spare without DPCloseTab.
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

        // 6. Regression: Cmd+L over a visible Peek card with toolbar passes straight to Peek without arming DPHandToDia,
        // while Cmd+T and Cmd+L from Side Chat still go through DPHandToDia.
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

        // 7. Regression: typing on a blank tab opens the bar, but typing in another field (rename, Find, Side Chat, Peek) is left alone.
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

        // 8. Regression: another space coming forward closes the bar's unused new tab, in the window that switched only.
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

        // Escaping a bar left in another space judges it by its own space, so a one-tab space in front doesn't strand it.
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
        [barPage removeFromSuperview];
        gHiding = NO;

        if (failures) return 1;
        puts("PASS: CommandBar key-window guard, dealloc/window-close cleanup, and off-tweak teardown");
    }
    return 0;
}

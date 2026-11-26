#import "Commands/GroupTabs/Tracking.m"
#import "runloop.h"
#import "Patches/UndoCloseTab/UndoCloseTab.m"

CFTimeInterval DPFoldedAt;
#define CACurrentMediaTime() (NSProcessInfo.processInfo.systemUptime)
#import "Patches/KeepFoldersOpen/KeepFoldersOpen.m"
#undef CACurrentMediaTime
#import "Patches/CompactSidebarHeader/CompactSidebarHeader.m"

static int gSwitcherLookups;
static NSWindowController *gMockSwitcher;
static NSEventModifierFlags gSwitcherMods;
#define DPOpenTabSwitcher() (gSwitcherLookups++, gMockSwitcher)
#import "Patches/CloseFromTabSwitcher/CloseFromTabSwitcher.m"
#undef DPOpenTabSwitcher

#import "Patches/TabTitles/Title.m"
static int gTitleScans;
static NSString *DPCountedDisplayTitle(NSString *title) {
    gTitleScans++;
    return DPDisplayTitle(title);
}
#define DPDisplayTitle DPCountedDisplayTitle
#import "Patches/TabTitles/TabTitles.m"
#undef DPDisplayTitle

static BOOL ownClose;
BOOL DPTakeOwnClose(void) {
    BOOL own = ownClose;
    ownClose = NO;
    return own;
}
BOOL DPShortcutMatches(NSEvent *event, DPPatch *patch) { return event.keyCode == 6 && (event.modifierFlags & NSEventModifierFlagCommand); }
BOOL DPCanUndoGrouping(void) { return NO; }
void DPForgetGroupingUndo(void) {}

@interface DPReopenTarget : NSObject
@property int reopened;
@end
@implementation DPReopenTarget
- (void)reopen:(id)sender { self.reopened++; }
@end

@interface ArcBrowser : NSObject
@end
@implementation ArcBrowser
- (void)setDelegate:(id)delegate {}
- (void)setWindow:(NSWindow *)window {}
- (id)createWebContents:(id)configuration { return [NSClassFromString(@"ArcWebContents") new]; }
- (void)takeOwnershipOfWebContents:(id)contents {}
@end

@interface _TtC3ADK15ChromiumBrowser : NSObject
@end
@implementation _TtC3ADK15ChromiumBrowser
- (void)browser:(id)browser didRestoreWebContents:(id)contents withSessionId:(id)session {}
- (void)browser:(id)browser didCreateNewWebContents:(id)contents isActive:(BOOL)active {}
@end

@interface ArcWebContents : NSObject
@property long long sessionId;
@property (copy) NSString *title;
- (id)clone;
- (void)closeWithForegroundCommitTiming:(NSInteger)timing;
@end
@implementation ArcWebContents
- (id)clone { return [ArcWebContents new]; }
- (void)closeWithForegroundCommitTiming:(NSInteger)timing {}
@end

@interface _TtC3ADK18WebContentChromium : NSObject
@end
@implementation _TtC3ADK18WebContentChromium
- (void)webContents:(id)webContents didCreateNewWebContent:(id)newContents targetURL:(NSURL *)url disposition:(NSInteger)disposition {}
@end

void DPOnLaunch(void (^block)(void)) { block(); }
void DPInstallGroupMenus(void) {}
void DPInstallGroupTabsShortcut(void) {}

static int failures;
static NSWindow *offscreenWindow(void);
static void checkUndoCloseTab(void);

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static NSWindow *offscreenWindow(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 200, 100) styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    return window;
}

static NSEvent *commandZ(NSWindow *window) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0
                        windowNumber:window ? window.windowNumber : 0 context:nil characters:@"z" charactersIgnoringModifiers:@"z" isARepeat:NO keyCode:6];
}

static void checkUndoCloseTab(void) {
    DPHook(DPDiaWebContents, @selector(closeWithForegroundCommitTiming:), (IMP)DPPage_close);
    DPUndoCloseTab.on = YES;
    DPReopenTarget *target = [DPReopenTarget new];
    NSMenu *bar = [NSMenu new], *history = [[NSMenu alloc] initWithTitle:@"History"];
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:@"History" action:nil keyEquivalent:@""];
    NSMenuItem *reopen = [[NSMenuItem alloc] initWithTitle:@"Reopen Closed Tab" action:@selector(reopen:) keyEquivalent:@""];
    reopen.target = target;
    [history addItem:reopen];
    top.submenu = history;
    [bar addItem:top];
    NSApp.mainMenu = bar;

    NSWindow *first = offscreenWindow(), *second = offscreenWindow();
    expect(commandZ(second).window == second && commandZ(first).window == first && first != second, @"a ⌘Z carries the window it was typed in");
    ArcBrowser *browser = [ArcBrowser new], *unplaced = [ArcBrowser new];
    [browser setWindow:first];
    id page = [browser createWebContents:nil], orphan = [unplaced createWebContents:nil];

    [page closeWithForegroundCommitTiming:0];
    expect(DPUndoEvent(commandZ(first)) == nil && target.reopened == 1, @"⌘Z in the window a tab was closed in brings it back");

    [page closeWithForegroundCommitTiming:0];
    NSEvent *elsewhere = commandZ(second);
    expect(DPUndoEvent(elsewhere) == elsewhere && target.reopened == 1, @"⌘Z in another window leaves the closed tab alone");
    NSEvent *again = commandZ(first);
    expect(DPUndoEvent(again) == again && target.reopened == 1, @"and the undo is spent once another window got the key press");

    [page closeWithForegroundCommitTiming:0];
    expect(DPUndoEvent(commandZ(nil)) == nil && target.reopened == 2, @"a ⌘Z that names no window still undoes");

    [orphan closeWithForegroundCommitTiming:0];
    expect(DPUndoEvent(commandZ(second)) == nil && target.reopened == 3, @"a tab whose window Dia never told us about can be undone from any window");

    ownClose = YES;
    [page closeWithForegroundCommitTiming:0];
    NSEvent *own = commandZ(first);
    expect(DPUndoEvent(own) == own && target.reopened == 3, @"a close this tweak made itself isn't undone");

    DPUndoCloseTab.on = NO;
    [page closeWithForegroundCommitTiming:0];
    DPUndoCloseTab.on = YES;
    NSEvent *off = commandZ(first);
    expect(DPUndoEvent(off) == off && target.reopened == 3, @"a close made while the tweak was off isn't undone");
    DPUndoCloseTab.on = NO;
    DPApplyUndoCloseTab(&DPUndoCloseTab);
}

@interface _TtC5TabUI12TabGroupView : NSView {
@public
    id viewModel;
    NSView *$__lazy_storage_$_headerView;
    BOOL shouldDisplayExpandedContainer;
    int clicks;
}
@end
@implementation _TtC5TabUI12TabGroupView
- (void)layout { [super layout]; }
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event { clicks++; }
@end

@interface DPFakeGroupHeaderBase : NSView
@property int headerClicks;
@end
@implementation DPFakeGroupHeaderBase
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event { self.headerClicks++; }
@end

@interface DPFakeGroupCellBase : NSView {
@public
    id viewModel;
    NSView *$__lazy_storage_$_chevronIconView;
}
@end
@implementation DPFakeGroupCellBase
- (BOOL)isFlipped { return YES; }
- (void)layout { [super layout]; }
- (void)prepareForReuse {}
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}
@end

@interface DPVisibleTestWindow : NSWindow
@property BOOL liveVisible;
@end
@implementation DPVisibleTestWindow
- (BOOL)isVisible { return self.liveVisible; }
@end

static NSEvent *mouseAt(NSEventType type, NSWindow *win, NSPoint pt) {
    return [NSEvent mouseEventWithType:type location:pt modifierFlags:0 timestamp:0
                          windowNumber:win ? win.windowNumber : 0 context:nil eventNumber:0 clickCount:1
                              pressure:type != NSEventTypeLeftMouseUp];
}

static Class registerSubclass(Class sup, const char *name) {
    Class existing = objc_getClass(name);
    if (existing) return existing;
    Class cls = objc_allocateClassPair(sup, name, 0);
    objc_registerClassPair(cls);
    return cls;
}

static void checkKeepFoldersOpen(void) {
    Class headerCls = registerSubclass(DPFakeGroupHeaderBase.class, DPDiaTabGroupHeader);
    Class cellCls = registerSubclass(DPFakeGroupCellBase.class, DPDiaTabGroupCell);
    (void)cellCls;
    DPKeepFoldersOpen.install();
    DPKeepFoldersOpen.on = YES;

    DPVisibleTestWindow *win = [[DPVisibleTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 300, 200)
                                                                      styleMask:NSWindowStyleMaskBorderless
                                                                        backing:NSBackingStoreBuffered defer:NO];
    win.releasedWhenClosed = NO;
    win.liveVisible = YES;
    _TtC5TabUI12TabGroupView *folder = [[_TtC5TabUI12TabGroupView alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
    DPFakeGroupHeaderBase *header = [[headerCls alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
    folder->$__lazy_storage_$_headerView = header;
    folder->shouldDisplayExpandedContainer = YES;
    folder->viewModel = [NSObject new];
    [folder addSubview:header];
    [win.contentView addSubview:folder];
    [folder layout];

    [header mouseDown:mouseAt(NSEventTypeLeftMouseDown, win, NSMakePoint(20, 14))];
    [header mouseDragged:mouseAt(NSEventTypeLeftMouseDragged, win, NSMakePoint(45, 14))];
    [header mouseUp:mouseAt(NSEventTypeLeftMouseUp, win, NSMakePoint(45, 14))];
    header.headerClicks = 0;
    folder->shouldDisplayExpandedContainer = NO;
    [folder layout];
    DPPumpUntil(^BOOL { return header.headerClicks == 1; });
    expect(header.headerClicks == 1, @"dragging a folder header does not suppress reopening when it collapses");

    folder->shouldDisplayExpandedContainer = YES;
    DPStateOf(folder)->reopened = 0;
    [folder layout];
    header.headerClicks = 0;
    [header mouseDown:mouseAt(NSEventTypeLeftMouseDown, win, NSMakePoint(20, 14))];
    [header mouseUp:mouseAt(NSEventTypeLeftMouseUp, win, NSMakePoint(21, 14))];
    header.headerClicks = 0;
    folder->shouldDisplayExpandedContainer = NO;
    [folder layout];
    DPDrainMainQueue(0.2);
    expect(header.headerClicks == 0, @"clicking the folder header lets the user collapse it");

    DPStateOf(folder)->clicked = 0;
    DPStateOf(folder)->reopened = 0;
    header.headerClicks = 0;
    folder->shouldDisplayExpandedContainer = YES;
    [folder layout];
    folder->shouldDisplayExpandedContainer = NO;
    [folder layout];
    win.liveVisible = NO;
    [win close];
    DPDrainMainQueue(0.2);
    expect(header.headerClicks == 0, @"closing the window before DPReopenFolders fires posts no events to a dead window");

    DPKeepFoldersOpen.on = NO;
    DPKeepFoldersOpen.apply(&DPKeepFoldersOpen);
}

static int gWeakTableLookups;
static BOOL DPCountedHashContains(NSHashTable *self, SEL _cmd, id obj) {
    if (self == DPSidebars) gWeakTableLookups++;
    return DPCallOriginal(DPCountedHashContains, self, obj);
}

@interface _TtC10TabSidebar30SidebarContainerViewController : NSViewController
@end
@implementation _TtC10TabSidebar30SidebarContainerViewController
- (void)viewWillLayout { [super viewWillLayout]; }
@end

@interface _TtC10TabSidebar17SidebarHeaderView : NSView
@end
@implementation _TtC10TabSidebar17SidebarHeaderView
- (BOOL)isFlipped { return YES; }
- (void)layout { [super layout]; }
@end

@interface _TtC10TabSidebar17TrafficLightsView : NSView
@end
@implementation _TtC10TabSidebar17TrafficLightsView
@end

static void checkCompactSidebarHeaderPerf(void) {
    DPCompactSidebarHeader.install();
    DPCompactSidebarHeader.on = NO;
    DPHookClass(object_getClass(DPSidebars), @selector(containsObject:), (IMP)DPCountedHashContains);
    expect(!DPIsHooked(NSView.class, @selector(setFrame:), (IMP)DPCompactFrame_setFrame), @"NSView -setFrame: is not hooked while CompactSidebarHeader is off");
    expect(!DPIsHooked(NSStackView.class, @selector(setFrame:), (IMP)DPButtonsRow_setFrame), @"NSStackView -setFrame: is not hooked while CompactSidebarHeader is off");

    _TtC10TabSidebar30SidebarContainerViewController *sc = [_TtC10TabSidebar30SidebarContainerViewController new];
    NSView *sidebar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 500)];
    _TtC10TabSidebar17SidebarHeaderView *header = [[_TtC10TabSidebar17SidebarHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 220, 44)];
    NSStackView *row = [[NSStackView alloc] initWithFrame:NSMakeRect(12, 10, 180, 20)];
    _TtC10TabSidebar17TrafficLightsView *lights = [[_TtC10TabSidebar17TrafficLightsView alloc] initWithFrame:NSMakeRect(0, 0, 52, 14)];
    [row addSubview:lights];
    [header addSubview:row];
    NSView *body = [[NSView alloc] initWithFrame:NSMakeRect(0, 44, 220, 456)];
    [sidebar addSubview:header];
    [sidebar addSubview:body];
    sc.view = sidebar;

    DPCompactSidebarHeader.on = YES;
    [sc viewWillLayout];
    [header layout];
    header.frame = NSMakeRect(0, 0, 220, 44);
    body.frame = NSMakeRect(0, 44, 220, 456);
    expect(fabs(NSHeight(header.frame) - 34) < 0.5 && fabs(NSMinY(body.frame) - 34) < 0.5 && fabs(NSHeight(body.frame) - 466) < 0.5,
           @"CompactSidebarHeader trims header and lifts plain NSView body by 10pt");

    NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    NSView *unrelated = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
    [host addSubview:unrelated];
    gWeakTableLookups = 0;
    for (int i = 0; i < 1000; i++) unrelated.frame = NSMakeRect(i % 5, 0, 100, 30);
    expect(gWeakTableLookups == 0, @"unrelated NSView -setFrame: performs zero DPSidebars weak-table lookups");

    DPCompactSidebarHeader.on = NO;
    header.frame = NSMakeRect(0, 0, 220, 44);
    body.frame = NSMakeRect(0, 44, 220, 456);
    expect(fabs(NSHeight(header.frame) - 44) < 0.5 && fabs(NSMinY(body.frame) - 44) < 0.5,
           @"turning CompactSidebarHeader off restores full header and body frames");
}

@interface DPSwitcherCloseTab : NSObject
@property (copy) NSString *tabId;
@property BOOL closed;
@end
@implementation DPSwitcherCloseTab
- (void)close:(id)sender { self.closed = YES; }
@end

@interface DPSwitcherScriptWin : NSObject
@property (copy) NSArray *appleScriptTabs;
@end
@implementation DPSwitcherScriptWin
@end

@interface DPSwitcherAppDel : NSObject <NSApplicationDelegate>
@property (copy) NSArray *appleScriptWindows;
@end
@implementation DPSwitcherAppDel
@end

@interface DPSwitcherStateObj : NSObject
@property (copy) NSString *focusedItemID, *items;
@end
@implementation DPSwitcherStateObj
- (id)safeSwiftValueForKey:(NSString *)k { return [self valueForKey:k]; }
@end

@interface DPSwitcherSubj : NSObject
@property (strong) DPSwitcherStateObj *currentValue;
@end
@implementation DPSwitcherSubj
- (id)safeSwiftValueForKey:(NSString *)k { return [self valueForKey:k]; }
@end

@interface DPSwitcherVM : NSObject
@property (strong) DPSwitcherSubj *stateSubject;
@end
@implementation DPSwitcherVM
- (id)safeSwiftValueForKey:(NSString *)k { return [self valueForKey:k]; }
@end

@interface DPSwitcherWC : NSWindowController
@property (strong) DPSwitcherVM *viewModel;
@end
@implementation DPSwitcherWC
- (id)safeSwiftValueForKey:(NSString *)k { return [self valueForKey:k]; }
- (void)close { gMockSwitcher = nil; }
@end

@interface DPCycleTarget : NSObject
@property int cycles;
@end
@implementation DPCycleTarget
- (void)cycle:(id)sender { self.cycles++; }
@end

static NSEventModifierFlags DPFakeCtrlMods(id self, SEL _cmd) { return gSwitcherMods; }

static void checkCloseFromTabSwitcher(void) {
    DPHookClass(object_getClass(NSEvent.class), @selector(modifierFlags), (IMP)DPFakeCtrlMods);
    gSwitcherMods = NSEventModifierFlagControl;
    DPCloseFromTabSwitcher.on = YES;

    DPCycleTarget *cycleTarget = [DPCycleTarget new];
    NSMenu *bar = [NSMenu new], *winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenuItem *cycle = [[NSMenuItem alloc] initWithTitle:@"Next Tab" action:@selector(cycle:) keyEquivalent:@"\t"];
    cycle.keyEquivalentModifierMask = NSEventModifierFlagControl;
    cycle.target = cycleTarget;
    [winMenu addItem:cycle];
    top.submenu = winMenu;
    [bar addItem:top];
    NSApp.mainMenu = bar;

    NSString *u1 = @"11111111-1111-1111-1111-111111111111";
    NSString *u2 = @"22222222-2222-2222-2222-222222222222";
    NSString *u3 = @"33333333-3333-3333-3333-333333333333";
    DPSwitcherCloseTab *t1 = [DPSwitcherCloseTab new], *t2 = [DPSwitcherCloseTab new], *t3 = [DPSwitcherCloseTab new];
    t1.tabId = u1; t2.tabId = u2; t3.tabId = u3;
    DPSwitcherScriptWin *sw = [DPSwitcherScriptWin new];
    sw.appleScriptTabs = @[ t1, t2, t3 ];
    DPSwitcherAppDel *del = [DPSwitcherAppDel new];
    del.appleScriptWindows = @[ sw ];
    id prevDel = NSApp.delegate;
    NSApp.delegate = del;

    DPSwitcherStateObj *st = [DPSwitcherStateObj new];
    st.focusedItemID = u1;
    st.items = [NSString stringWithFormat:@"[%@, %@, %@]", u1, u2, u3];
    DPSwitcherSubj *subj = [DPSwitcherSubj new];
    subj.currentValue = st;
    DPSwitcherVM *vm = [DPSwitcherVM new];
    vm.stateSubject = subj;
    DPSwitcherWC *wc = [DPSwitcherWC new];
    wc.viewModel = vm;
    gMockSwitcher = wc;

    gSwitcherLookups = 0;
    expect(DPCloseFocusedTab(wc) && t1.closed, @"closing focused tab from switcher closes the tab");
    sw.appleScriptTabs = @[ t2, t3 ];
    // Switcher never reopens: DPFocus must stop after <= 9 lookups instead of polling 100 times for 2s.
    DPPumpUntil(^BOOL { return cycleTarget.cycles == 1; });
    for (int seen = -1; seen != gSwitcherLookups;) {
        seen = gSwitcherLookups;
        DPDrainMainQueue(0.1);
    }
    expect(cycleTarget.cycles == 1, @"cycle menu item fires once after tab closes");
    expect(gSwitcherLookups >= 2 && gSwitcherLookups <= 12, @"switcher focus polling stops within bounded retries when switcher stays closed");

    gSwitcherMods = 0;
    DPCloseFromTabSwitcher.on = NO;
    NSApp.delegate = prevDel;
}

static void checkTabTitlesMemo(void) {
    DPTabTitles.install();
    DPTabTitles.on = YES;
    ArcWebContents *page = [ArcWebContents new];
    page.title = @"\u200B\uFEFFProject Roadmap";
    gTitleScans = 0;
    expect([[page title] isEqualToString:@"Project Roadmap"] && gTitleScans == 1, @"first WebContents -title strips invisible prefix");
    for (int i = 0; i < 50; i++) {
        page.title = [NSString stringWithFormat:@"%C%CProject Roadmap", (unichar)0x200B, (unichar)0xFEFF];
        expect([[page title] isEqualToString:@"Project Roadmap"], @"repeated WebContents -title returns clean title");
    }
    expect(gTitleScans == 1, @"50 repeated WebContents -title reads hit per-contents memo with zero rescans");

    page.title = @"\u200DNext Sprint";
    expect([[page title] isEqualToString:@"Next Sprint"] && gTitleScans == 2, @"changing WebContents title updates the memo cleanly");

    DPTabTitles.on = NO;
    expect([[page title] isEqualToString:@"\u200DNext Sprint"] && gTitleScans == 2, @"turning Clean Tab Titles off returns raw title");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPInstallGroupTabs();
        ArcBrowser *browser = [ArcBrowser new];
        id page = [browser createWebContents:nil], ui = [_TtC3ADK18WebContentChromium new];
        expect(DPBrowserOfContents(page) == browser, @"a tab Dia creates belongs to the browser that made it");

        id linked = [ArcWebContents new];
        [ui webContents:page didCreateNewWebContent:linked targetURL:nil disposition:2];
        expect(DPBrowserOfContents(linked) == browser, @"a tab a link or a script opens belongs to its opener's browser");
        expect([DPTrackedContents(browser) containsObject:linked], @"and Group Tabs, Tidy Tabs and the rest see it");

        id nested = [ArcWebContents new];
        [ui webContents:linked didCreateNewWebContent:nested targetURL:nil disposition:3];
        expect(DPBrowserOfContents(nested) == browser, @"so does one opened from a tab that was itself opened that way");

        id stranger = [ArcWebContents new], fromStranger = [ArcWebContents new];
        [ui webContents:stranger didCreateNewWebContent:fromStranger targetURL:nil disposition:2];
        expect(DPBrowserOfContents(fromStranger) == nil, @"a page nobody told us about opens tabs nobody is told about");

        id copy = [page clone];
        expect(DPBrowserOfContents(copy) == browser, @"a duplicate belongs to its original's browser");
        expect(DPBrowserOfContents([stranger clone]) == nil, @"and a duplicate of an unknown page stays unknown");
        checkUndoCloseTab();
        checkKeepFoldersOpen();
        checkCompactSidebarHeaderPerf();
        checkCloseFromTabSwitcher();
        checkTabTitlesMemo();
    }
    if (failures) return 1;
    puts("PASS: tabs opened by a link, a script or a duplicate are tracked");
    return 0;
}

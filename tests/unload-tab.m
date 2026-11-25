#import "StdPatch/StdPatch.h"
#import "Patches/UnloadTab/Pages.h"
#import "Patches/UnloadTab/Recent.h"
#import "Patches/PinnedTabCloseButton/PinnedTabs.h"
#import "Patches/CommandBar/Tabs.h"
#import <objc/message.h>
#import "watchdog.h"

void *swift_unknownObjectWeakLoadStrong(void *ref) {
    return ref && *(__unsafe_unretained id *)ref ? (__bridge_retained void *)*(__unsafe_unretained id *)ref : NULL;
}
void DPOnLaunch(void (^block)(void)) { block(); }

@interface DPTestMenuAction : NSObject
@property (nonatomic, copy) void (^block)(void);
@end
@implementation DPTestMenuAction
- (void)invoke:(id)sender { if (self.block) self.block(); }
@end

NSMenuItem *DPMenuItem(NSString *title, void (^action)(void)) {
    DPTestMenuAction *target = [DPTestMenuAction new];
    target.block = action;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title ?: @"" action:@selector(invoke:) keyEquivalent:@""];
    item.target = target;
    objc_setAssociatedObject(item, @selector(invoke:), target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return item;
}

static void Trigger(NSMenuItem *item) {
    if (item.target && item.action) ((void (*)(id, SEL, id))objc_msgSend)(item.target, item.action, item);
}

// The main queue is FIFO, so once the sentinel runs, every block queued before it has run too.
static void DrainMainQueue(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!drained && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static int failures;
static void Check(BOOL ok, NSString *msg) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", msg.UTF8String);
}

@interface DPTestWindow : NSWindow
@property (nonatomic) BOOL mockVisible;
@end
@implementation DPTestWindow
- (BOOL)isVisible { return self.mockVisible; }
@end

@interface _TtC11ContentPane15ContentPaneView : NSView
@property (nonatomic, copy) NSString *contentPaneID;
@end
@implementation _TtC11ContentPane15ContentPaneView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"contentPaneID"] ? self.contentPaneID : nil; }
@end

@interface ArcWebContents : NSObject
@property (nonatomic, strong) NSView *nativeView;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic) NSInteger visibilityValue;
@property (nonatomic) NSInteger discardCount;
@property (nonatomic, copy) void (^onDiscard)(ArcWebContents *page);
@end
@implementation ArcWebContents
- (NSInteger)visibility { return self.visibilityValue; }
- (void)setVisibility:(NSInteger)visibility { self.visibilityValue = visibility; }
- (void)discard {
    self.discardCount++;
    if (self.onDiscard) self.onDiscard(self);
}
@end

@interface _TtC3ADK18WebContentChromium : NSObject
- (void)webContents:(id)contents finalizeDiscardRequest:(BOOL)discarded;
- (void)webContents:(id)contents didCloseWithSessionID:(id)sessionID;
@end
@implementation _TtC3ADK18WebContentChromium
- (void)webContents:(id)contents finalizeDiscardRequest:(BOOL)discarded {}
- (void)webContents:(id)contents didCloseWithSessionID:(id)sessionID {}
@end

@interface DPTestScriptTab : NSObject
@property (nonatomic, copy) NSString *tabId;
@property (nonatomic, copy) NSString *URL;
@property (nonatomic, copy) void (^onFocus)(DPTestScriptTab *tab);
@end
@implementation DPTestScriptTab
- (void)focus:(id)arg { if (self.onFocus) self.onFocus(self); }
@end

@interface DPTestScriptProfile : NSObject
@property (nonatomic, copy) NSArray *appleScriptTabs;
@end
@implementation DPTestScriptProfile
@end

@interface DPTestScriptWindow : NSObject
@property (nonatomic, copy) NSString *windowId;
@property (nonatomic, copy) NSArray *appleScriptTabs;
@property (nonatomic, copy) NSArray *appleScriptProfiles;
@property (nonatomic, strong) DPTestScriptTab *activeTab;
@end
@implementation DPTestScriptWindow
@end

@interface DPTestAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, copy) NSArray *appleScriptWindows;
@end
@implementation DPTestAppDelegate
@end

@interface DPTestSubject : NSObject
@property (nonatomic, strong) id currentValue;
@end
@implementation DPTestSubject
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"currentValue"] ? self.currentValue : nil; }
@end

@interface DPTestTabState : NSObject
@property (nonatomic, copy) NSString *selectionStyle;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *contentIDs;
@end
@implementation DPTestTabState
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"selectionStyle"]) return self.selectionStyle;
    if ([key isEqualToString:@"icon"]) return self.icon;
    if ([key isEqualToString:@"contentIDs"]) return self.contentIDs;
    return nil;
}
@end

@interface _TtC5TabUI33TabWebContentAttributesController : NSObject {
@public
    BOOL isInFavoritesOrPinnedContainer;
    void *activeURL;
}
@end
@implementation _TtC5TabUI33TabWebContentAttributesController
@end

@interface _TtC5TabUI20TabContentController : NSObject {
@public
    id attributesController;
}
@property (nonatomic, copy) NSString *tabID;
@property (nonatomic, copy) NSString *contentID;
@property (nonatomic, copy) NSURL *webContentURL;
@end
@implementation _TtC5TabUI20TabContentController
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"tabID"]) return self.tabID;
    if ([key isEqualToString:@"contentID"]) return self.contentID;
    if ([key isEqualToString:@"webContentURL"]) return self.webContentURL;
    return nil;
}
@end

@interface DPTestTabController : NSObject {
@public
    uint8_t requestedCloseButtonStyle;
}
@end
@implementation DPTestTabController
@end

@interface DPTestViewModel : NSObject {
@public
    __unsafe_unretained id delegate;
}
@property (nonatomic, strong) DPTestSubject *stateSubject;
@property (nonatomic, copy) NSString *tabID;
@end
@implementation DPTestViewModel
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"stateSubject"]) return self.stateSubject;
    if ([key isEqualToString:@"delegate"]) return delegate;
    if ([key isEqualToString:@"tabID"]) return self.tabID;
    return nil;
}
@end

@interface _TtC5TabUI14TabContentView : NSView {
@public
    id viewModel;
}
@property (nonatomic, strong) _TtC5TabUI20TabContentController *retainedController;
@property (nonatomic) NSInteger closeClicks;
@property (nonatomic) uint8_t styleAtClose;
@end
@implementation _TtC5TabUI14TabContentView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"viewModel"] ? viewModel : nil; }
- (void)closeButtonClicked {
    self.closeClicks++;
    NSView *tab = self.superview;
    id ctrl = tab ? DPViewModelDelegate(tab) : nil;
    uint8_t *style = DPIvar(ctrl, "requestedCloseButtonStyle");
    self.styleAtClose = style ? *style : 0;
}
@end

@interface _TtC5TabUI7TabView : NSView {
@public
    id viewModel;
}
@property (nonatomic, copy) NSDictionary *contentViews;
@property (nonatomic, strong) DPTestTabController *retainedController;
@property (nonatomic, copy) NSArray<NSString *> *baseMenuTitles;
@end
@implementation _TtC5TabUI7TabView
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"viewModel"]) return viewModel;
    if ([key isEqualToString:@"contentViews"]) return self.contentViews;
    return nil;
}
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [NSMenu new];
    for (NSString *title in (self.baseMenuTitles ?: @[@"Reload", @"Duplicate", @"Close"]))
        [menu addItemWithTitle:title action:nil keyEquivalent:@""];
    return menu;
}
@end

@interface DPTestUnbridgedDict : NSObject
@property (nonatomic, copy) NSString *rawDescription;
@end
@implementation DPTestUnbridgedDict
- (NSString *)description { return self.rawDescription ?: @"[:]"; }
@end

@interface _TtC5TabUI21TabDockItemController : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, strong) id contentControllers;
@end
@implementation _TtC5TabUI21TabDockItemController
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"itemID"]) return self.itemID;
    if ([key isEqualToString:@"contentControllers"]) return self.contentControllers;
    return nil;
}
@end

@interface _TtC5TabUI15TabDockItemView : NSView {
@public
    id viewModel;
}
@property (nonatomic, strong) _TtC5TabUI21TabDockItemController *retainedController;
@property (nonatomic, copy) NSArray<NSString *> *baseMenuTitles;
@end
@implementation _TtC5TabUI15TabDockItemView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"viewModel"] ? viewModel : nil; }
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [NSMenu new];
    for (NSString *title in (self.baseMenuTitles ?: @[@"Reload", @"Unpin", @"Delete"]))
        [menu addItemWithTitle:title action:nil keyEquivalent:@""];
    return menu;
}
@end

@interface DPPeekCard : NSView
@end
@implementation DPPeekCard
@end

@interface _TtC18ExtensionSidePanel23WebContentContainerView : NSView
@end
@implementation _TtC18ExtensionSidePanel23WebContentContainerView
@end

@interface _TtC14AssistantPanel18AssistantPanelView : NSView
@end
@implementation _TtC14AssistantPanel18AssistantPanelView
@end

@interface DPEphemeralScriptWindow : NSObject
@property (nonatomic, copy) NSString *windowId;
@property (nonatomic, copy) NSArray<NSString *> *tabIDs;
@property (nonatomic, copy) NSString *activeTabID;
@property (nonatomic, copy) void (^onFocusTabID)(NSString *tabID);
@end
@implementation DPEphemeralScriptWindow
- (NSArray *)appleScriptTabs {
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *tid in self.tabIDs) {
        DPTestScriptTab *t = [DPTestScriptTab new];
        t.tabId = tid;
        t.URL = [NSString stringWithFormat:@"https://%@.test/", tid];
        __weak DPEphemeralScriptWindow *weakSelf = self;
        t.onFocus = ^(DPTestScriptTab *focused) {
            DPEphemeralScriptWindow *s = weakSelf;
            if (s && s.onFocusTabID) s.onFocusTabID(focused.tabId);
        };
        [list addObject:t];
    }
    return list;
}
- (id)activeTab {
    if (!self.activeTabID) return nil;
    DPTestScriptTab *t = [DPTestScriptTab new];
    t.tabId = self.activeTabID;
    t.URL = [NSString stringWithFormat:@"https://%@.test/", self.activeTabID];
    return t;
}
@end

static DPTestWindow *MakeWindow(NSString *windowId) {
    DPTestWindow *win = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:YES];
    win.identifier = windowId;
    win.releasedWhenClosed = NO;
    win.mockVisible = YES;
    return win;
}

static _TtC5TabUI7TabView *MakeTabView(DPTestWindow *win, NSString *tabID, NSString *contentID, NSString *urlStr,
                                       BOOL isPinned, BOOL isOpenPinned, NSString *selectionStyle,
                                       _TtC5TabUI14TabContentView **outPane) {
    _TtC5TabUI33TabWebContentAttributesController *attrs = [_TtC5TabUI33TabWebContentAttributesController new];
    attrs->isInFavoritesOrPinnedContainer = isPinned;
    NSURL *url = urlStr ? [NSURL URLWithString:urlStr] : nil;
    attrs->activeURL = isOpenPinned ? (__bridge void *)url : NULL;

    _TtC5TabUI20TabContentController *ctrl = [_TtC5TabUI20TabContentController new];
    ctrl->attributesController = attrs;
    ctrl.tabID = tabID;
    ctrl.contentID = contentID;
    ctrl.webContentURL = url;

    DPTestViewModel *cvm = [DPTestViewModel new];
    cvm->delegate = ctrl;

    _TtC5TabUI14TabContentView *pane = [[_TtC5TabUI14TabContentView alloc] initWithFrame:NSMakeRect(0, 0, 180, 32)];
    pane->viewModel = cvm;
    pane.retainedController = ctrl;

    DPTestTabController *tabCtrl = [DPTestTabController new];
    tabCtrl->requestedCloseButtonStyle = 0;

    DPTestTabState *state = [DPTestTabState new];
    state.selectionStyle = selectionStyle;
    DPTestSubject *subject = [DPTestSubject new];
    subject.currentValue = state;

    DPTestViewModel *tvm = [DPTestViewModel new];
    tvm->delegate = tabCtrl;
    tvm.stateSubject = subject;
    tvm.tabID = tabID;

    _TtC5TabUI7TabView *tab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 36)];
    tab->viewModel = tvm;
    tab.retainedController = tabCtrl;
    tab.contentViews = @{ (contentID ?: @"pane") : pane };
    [tab addSubview:pane];
    [win.contentView addSubview:tab];
    if (outPane) *outPane = pane;
    return tab;
}

static _TtC5TabUI15TabDockItemView *MakeDockItem(DPTestWindow *win, NSString *itemID, id contentControllers,
                                                 NSString *selectionStyle, NSString *icon) {
    _TtC5TabUI21TabDockItemController *ctrl = [_TtC5TabUI21TabDockItemController new];
    ctrl.itemID = itemID;
    ctrl.contentControllers = contentControllers;

    DPTestTabState *state = [DPTestTabState new];
    state.selectionStyle = selectionStyle;
    state.icon = icon;
    DPTestSubject *subject = [DPTestSubject new];
    subject.currentValue = state;

    DPTestViewModel *vm = [DPTestViewModel new];
    vm->delegate = ctrl;
    vm.stateSubject = subject;

    _TtC5TabUI15TabDockItemView *dock = [[_TtC5TabUI15TabDockItemView alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)];
    dock->viewModel = vm;
    dock.retainedController = ctrl;
    [win.contentView addSubview:dock];
    return dock;
}

static ArcWebContents *MakePage(DPTestWindow *win, NSString *paneID, NSString *urlStr, NSInteger visibility,
                                _TtC11ContentPane15ContentPaneView **outContentPane) {
    ArcWebContents *page = [ArcWebContents new];
    page.url = [NSURL URLWithString:urlStr];
    NSView *nv = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    page.nativeView = nv;
    if (win && paneID) {
        _TtC11ContentPane15ContentPaneView *cp = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
        cp.contentPaneID = paneID;
        [cp addSubview:nv];
        [win.contentView addSubview:cp];
        if (outContentPane) *outContentPane = cp;
    }
    [page setVisibility:visibility];
    return page;
}

static DPTestScriptTab *MakeScriptTab(NSString *tabID, NSString *url) {
    DPTestScriptTab *st = [DPTestScriptTab new];
    st.tabId = tabID;
    st.URL = url;
    return st;
}

static void TestRegularAndSidebarPinnedTabs(_TtC3ADK18WebContentChromium *chromium) {
    DPTestWindow *win = MakeWindow(@"WIN-1");
    NSString *regTabID = @"11111111-1111-1111-1111-111111111111";
    NSString *regPaneID = @"11111111-1111-1111-1111-111111111112";
    NSString *pinHomeTabID = @"22222222-2222-2222-2222-222222222221";
    NSString *pinHomePaneID = @"22222222-2222-2222-2222-222222222222";
    NSString *pinNavTabID = @"33333333-3333-3333-3333-333333333331";
    NSString *pinNavPaneID = @"33333333-3333-3333-3333-333333333332";
    NSString *pinClosedTabID = @"44444444-4444-4444-4444-444444444441";
    NSString *pinClosedPaneID = @"44444444-4444-4444-4444-444444444442";
    NSString *pinFallbackTabID = @"55555555-5555-5555-5555-555555555551";
    NSString *pinFallbackPaneID = @"55555555-5555-5555-5555-555555555552";

    _TtC5TabUI14TabContentView *pinHomePane = nil, *pinNavPane = nil, *pinFallbackPane = nil;
    _TtC5TabUI7TabView *regTab = MakeTabView(win, regTabID, regPaneID, @"https://reg.test/", NO, NO, @"primary", nil);
    _TtC5TabUI7TabView *pinHomeTab = MakeTabView(win, pinHomeTabID, pinHomePaneID, @"https://pinhome.test/", YES, YES, @"none", &pinHomePane);
    _TtC5TabUI7TabView *pinNavTab = MakeTabView(win, pinNavTabID, pinNavPaneID, @"https://pinnav.test/subpage", YES, YES, @"none", &pinNavPane);
    _TtC5TabUI7TabView *pinClosedTab = MakeTabView(win, pinClosedTabID, pinClosedPaneID, @"https://reg.test/", YES, NO, @"none", nil);
    _TtC5TabUI7TabView *pinFallbackTab = MakeTabView(win, pinFallbackTabID, pinFallbackPaneID, @"https://fallback.test/", YES, YES, @"none", &pinFallbackPane);

    DPTestScriptTab *stReg = MakeScriptTab(regTabID, @"https://reg.test/");
    DPTestScriptTab *stPinHome = MakeScriptTab(pinHomeTabID, @"https://pinhome.test/");
    // Saved URL in AppleScript stays at home URL even after pinNav navigated away!
    DPTestScriptTab *stPinNav = MakeScriptTab(pinNavTabID, @"https://pinnav.test/");
    DPTestScriptTab *stPinClosed = MakeScriptTab(pinClosedTabID, @"https://reg.test/");
    DPTestScriptTab *stPinFallback = MakeScriptTab(pinFallbackTabID, @"https://fallback.test/");

    DPTestScriptWindow *sw = [DPTestScriptWindow new];
    sw.windowId = @"WIN-1";
    sw.appleScriptTabs = @[stReg, stPinHome, stPinNav, stPinClosed, stPinFallback];
    sw.activeTab = stReg;

    DPTestAppDelegate *appDel = [DPTestAppDelegate new];
    appDel.appleScriptWindows = @[sw];
    NSApp.delegate = appDel;

    ArcWebContents *regPage = MakePage(win, regPaneID, @"https://reg.test/", 2, nil);
    ArcWebContents *pinHomePage = MakePage(win, pinHomePaneID, @"https://pinhome.test/", 0, nil);
    ArcWebContents *pinNavPage = MakePage(win, pinNavPaneID, @"https://pinnav.test/subpage", 0, nil);

    NSMenu *closedMenu = DPTabContextMenu(pinClosedTab);
    Check([closedMenu itemWithTitle:@"Unload Tab"] == nil, @"sidebar closed pinned tab never offers Unload Tab even when sharing URL");

    NSMenu *homeMenu = DPTabContextMenu(pinHomeTab);
    NSMenuItem *homeItem = [homeMenu itemWithTitle:@"Unload Tab"];
    Check(homeItem != nil && homeItem.enabled, @"sidebar pinned tab at home URL offers enabled Unload Tab");
    Check([homeMenu indexOfItem:homeItem] == [homeMenu indexOfItemWithTitle:@"Close"] - 1, @"Unload Tab inserted right before Close");
    pinHomePage.onDiscard = ^(ArcWebContents *p) { [chromium webContents:p finalizeDiscardRequest:YES]; };
    Trigger(homeItem);
    Check(pinHomePage.discardCount == 1, @"sidebar pinned tab at home URL unloads via discard");
    Check(pinHomePane.closeClicks == 0, @"sidebar pinned tab discard does not call closeButtonClicked");
    Check(!DPTakeOwnClose(), @"discarding pinned tab does not arm own-close");
    Check([DPTabContextMenu(pinHomeTab) itemWithTitle:@"Unload Tab"] == nil, @"discarded sidebar pinned tab hides Unload Tab without falling through to close");
    [pinHomePage setVisibility:2];
    [pinHomePage setVisibility:0];
    Check([DPTabContextMenu(pinHomeTab) itemWithTitle:@"Unload Tab"] != nil, @"reopened sidebar pinned tab restores Unload Tab");

    NSMenu *navMenu = DPTabContextMenu(pinNavTab);
    NSMenuItem *navItem = [navMenu itemWithTitle:@"Unload Tab"];
    Check(navItem != nil && navItem.enabled, @"navigated sidebar pinned tab offers Unload Tab via contentPaneID");
    pinNavPage.onDiscard = ^(ArcWebContents *p) { [chromium webContents:p finalizeDiscardRequest:NO]; };
    Trigger(navItem);
    Check(pinNavPage.discardCount == 1, @"navigated sidebar pinned tab calls discard");
    Check([DPTabContextMenu(pinNavTab) itemWithTitle:@"Unload Tab"] != nil, @"declined discard keeps Unload Tab in menu");
    pinNavPage.onDiscard = ^(ArcWebContents *p) { [chromium webContents:p finalizeDiscardRequest:YES]; };
    Trigger([DPTabContextMenu(pinNavTab) itemWithTitle:@"Unload Tab"]);
    Check([DPTabContextMenu(pinNavTab) itemWithTitle:@"Unload Tab"] == nil, @"finalized discard hides Unload Tab on navigated pinned tab");

    NSMenuItem *fbItem = [DPTabContextMenu(pinFallbackTab) itemWithTitle:@"Unload Tab"];
    Check(fbItem != nil && fbItem.enabled, @"untracked open pinned tab falls back to keep-pinned close");
    Trigger(fbItem);
    Check(pinFallbackPane.closeClicks == 1 && pinFallbackPane.styleAtClose == 1, @"fallback uses DPCloseKeepingTabStyle (1)");
    Check(DPTakeOwnClose(), @"fallback marks own-close so UndoCloseTab ignores it");

    __block BOOL focusedBefore = NO;
    stPinHome.onFocus = ^(DPTestScriptTab *t) {
        focusedBefore = YES;
        sw.activeTab = t;
        [regPage setVisibility:0];
    };
    regPage.onDiscard = ^(ArcWebContents *p) { [chromium webContents:p finalizeDiscardRequest:YES]; };
    NSMenuItem *regItem = [DPTabContextMenu(regTab) itemWithTitle:@"Unload Tab"];
    Check(regItem != nil && regItem.enabled, @"front regular tab offers enabled Unload Tab when other tabs exist");
    Trigger(regItem);
    DrainMainQueue();
    Check(focusedBefore, @"front tab focuses another tab before discarding");
    Check(regPage.discardCount == 1, @"front tab discards after visibility leaves visible");

    regTab.contentViews = @{ @"a" : [[NSView alloc] init], @"b" : [[NSView alloc] init] };
    Check([DPTabContextMenu(regTab) itemWithTitle:@"Unload Tab"] == nil, @"split TabView never offers Unload Tab");

    NSString *rowTabID = @"66666666-6666-6666-6666-666666666661";
    NSString *rowPaneID = @"66666666-6666-6666-6666-666666666662";
    DPTestTabState *rowState = [DPTestTabState new];
    rowState.contentIDs = [NSString stringWithFormat:@"[%@]", rowPaneID];
    DPTestSubject *rowSubject = [DPTestSubject new];
    rowSubject.currentValue = rowState;
    DPTestViewModel *rowVM = [DPTestViewModel new];
    rowVM.stateSubject = rowSubject;
    rowVM.tabID = rowTabID;
    _TtC5TabUI7TabView *rowTab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 36)];
    rowTab->viewModel = rowVM;
    [win.contentView addSubview:rowTab];
    ArcWebContents *rowPage = MakePage(win, rowPaneID, @"https://rowfallback.test/", 0, nil);
    NSMenuItem *rowItem = [DPTabContextMenu(rowTab) itemWithTitle:@"Unload Tab"];
    Check(rowItem != nil && rowItem.enabled, @"TabView without contentViews resolves page via contentIDs");
    Trigger(rowItem);
    Check(rowPage.discardCount == 1, @"TabView contentIDs fallback discards page");

    [chromium webContents:rowPage didCloseWithSessionID:@4];
    [chromium webContents:regPage didCloseWithSessionID:@1];
    [chromium webContents:pinHomePage didCloseWithSessionID:@2];
    [chromium webContents:pinNavPage didCloseWithSessionID:@3];
    NSApp.delegate = nil;
    win.mockVisible = NO;
    [win close];
}

@interface _TtC5Popup19PlatformPopupWindow : NSWindow
@end
@implementation _TtC5Popup19PlatformPopupWindow
@end

static void TestDockAndTopTabPinnedTabs(_TtC3ADK18WebContentChromium *chromium) {
    DPTestWindow *win = MakeWindow(@"WIN-DOCK");
    NSString *dockColdTabID = @"A1111111-1111-1111-1111-111111111111";
    NSString *dockColdPaneID = @"A1111111-1111-1111-1111-111111111112";
    NSString *dockHomeTabID = @"A2222222-2222-2222-2222-222222222221";
    NSString *dockHomePaneID = @"A2222222-2222-2222-2222-222222222222";
    NSString *dockNavTabID = @"A3333333-3333-3333-3333-333333333331";
    NSString *dockNavPaneID = @"A3333333-3333-3333-3333-333333333332";
    NSString *dockFrontTabID = @"A4444444-4444-4444-4444-444444444441";
    NSString *dockFrontPaneID = @"A4444444-4444-4444-4444-444444444442";
    NSString *dockGroupID = @"A5555555-5555-5555-5555-555555555551";

    _TtC5TabUI15TabDockItemView *coldDock = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", dockColdTabID],
                                                         @{ dockColdPaneID : @"ContentController" }, nil, @"favicon");
    _TtC5TabUI15TabDockItemView *homeDock = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", dockHomeTabID],
                                                         @{ dockHomePaneID : @"ContentController" }, nil, @"favicon");
    DPTestUnbridgedDict *unbridged = [DPTestUnbridgedDict new];
    unbridged.rawDescription = [NSString stringWithFormat:@"[ContentPaneID(%@): TabUI.ContentController]", dockNavPaneID];
    _TtC5TabUI15TabDockItemView *navDock = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", dockNavTabID],
                                                        unbridged, nil, @"favicon");
    _TtC5TabUI15TabDockItemView *frontDock = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", dockFrontTabID],
                                                          @{ dockFrontPaneID : @"ContentController" }, nil, @"favicon");
    _TtC5TabUI15TabDockItemView *groupDock = MakeDockItem(win, [NSString stringWithFormat:@"group(%@)", dockGroupID],
                                                          @{}, nil, @"folder");
    DPTestUnbridgedDict *splitControllers = [DPTestUnbridgedDict new];
    splitControllers.rawDescription = @"[11111111-2222-3333-4444-555555555555: C1, 66666666-7777-8888-9999-AAAAAAAAAAAA: C2]";
    _TtC5TabUI15TabDockItemView *splitDock = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", dockHomeTabID],
                                                          splitControllers, nil, @"split(count: 2)");

    DPTestScriptTab *stCold = MakeScriptTab(dockColdTabID, @"https://cold.test/");
    DPTestScriptTab *stHome = MakeScriptTab(dockHomeTabID, @"https://dockhome.test/");
    DPTestScriptTab *stNav = MakeScriptTab(dockNavTabID, @"https://docknav.test/");
    DPTestScriptTab *stFront = MakeScriptTab(dockFrontTabID, @"https://dockfront.test/");

    DPTestScriptWindow *sw = [DPTestScriptWindow new];
    sw.windowId = @"WIN-DOCK";
    sw.appleScriptTabs = @[stCold, stHome, stNav, stFront];
    sw.activeTab = stFront;

    DPTestAppDelegate *appDel = [DPTestAppDelegate new];
    appDel.appleScriptWindows = @[sw];
    NSApp.delegate = appDel;

    ArcWebContents *homePage = MakePage(nil, nil, @"https://dockhome.test/", 0, nil);
    // Navigated page attached to navPaneID; appleScriptTab still says https://docknav.test/ while page is at https://cold.test/!
    // This ALSO tests shared-URL safety: coldDock's saved URL is https://cold.test/, so coldDock must NOT steal navPage!
    ArcWebContents *navPage = MakePage(win, dockNavPaneID, @"https://cold.test/", 0, nil);
    ArcWebContents *frontPage = MakePage(win, dockFrontPaneID, @"https://dockfront.test/", 2, nil);

    Check([DPTabContextMenu(coldDock) itemWithTitle:@"Unload Tab"] == nil, @"cold dock tile never steals another pane's navigated page");

    Check([DPTabContextMenu(groupDock) itemWithTitle:@"Unload Tab"] == nil, @"group dock tile skipped");
    Check([DPTabContextMenu(splitDock) itemWithTitle:@"Unload Tab"] == nil, @"split dock tile skipped");

    NSMenu *homeMenu = DPTabContextMenu(homeDock);
    NSMenuItem *homeItem = [homeMenu itemWithTitle:@"Unload Tab"];
    Check(homeItem != nil && homeItem.enabled, @"background dock tile offers enabled Unload Tab via URL fallback");
    Check([homeMenu indexOfItem:homeItem] == [homeMenu indexOfItemWithTitle:@"Delete"] - 1, @"Unload Tab inserted before Delete on pinned tile");
    homePage.onDiscard = ^(ArcWebContents *p) { [chromium webContents:p finalizeDiscardRequest:YES]; };
    Trigger(homeItem);
    Check(homePage.discardCount == 1, @"background dock tile discards via ArcWebContents.discard");
    Check([DPTabContextMenu(homeDock) itemWithTitle:@"Unload Tab"] == nil, @"discarded dock tile hides Unload Tab");
    [homePage setVisibility:2];
    [homePage setVisibility:0];
    Check([DPTabContextMenu(homeDock) itemWithTitle:@"Unload Tab"] != nil, @"reopened dock tile restores Unload Tab");

    NSMenuItem *navItem = [DPTabContextMenu(navDock) itemWithTitle:@"Unload Tab"];
    Check(navItem != nil && navItem.enabled, @"navigated dock tile with unbridged contentControllers offers Unload Tab");
    navPage.onDiscard = ^(ArcWebContents *p) { [chromium webContents:p finalizeDiscardRequest:YES]; };
    Trigger(navItem);
    Check(navPage.discardCount == 1, @"navigated dock tile discards its own page");
    Check([DPTabContextMenu(navDock) itemWithTitle:@"Unload Tab"] == nil, @"discarded navigated dock tile hides Unload Tab");

    __block BOOL switchedAway = NO;
    stNav.onFocus = ^(DPTestScriptTab *t) {
        switchedAway = YES;
        sw.activeTab = t;
        [frontPage setVisibility:0];
    };
    stHome.onFocus = stNav.onFocus;
    stCold.onFocus = stNav.onFocus;
    frontPage.onDiscard = ^(ArcWebContents *p) { [chromium webContents:p finalizeDiscardRequest:YES]; };
    NSMenuItem *frontItem = [DPTabContextMenu(frontDock) itemWithTitle:@"Unload Tab"];
    Check(frontItem != nil && frontItem.enabled, @"front dock tile offers enabled Unload Tab even when selectionStyle is nil");
    Trigger(frontItem);
    DrainMainQueue();
    Check(switchedAway && frontPage.discardCount == 1, @"front dock tile switches to before and discards on hide");

    [frontPage setVisibility:2];
    sw.appleScriptTabs = @[stFront];
    sw.activeTab = stFront;
    NSMenuItem *onlyItem = [DPTabContextMenu(frontDock) itemWithTitle:@"Unload Tab"];
    Check(onlyItem != nil && !onlyItem.enabled, @"front dock tile disables Unload Tab when it is the only tab");

    NSString *err = DPUnloadTab.verify(&DPUnloadTab);
    Check(err == nil, [NSString stringWithFormat:@"DPVerifyUnloadTab passes with dock tiles (got: %@)", err]);

    ArcWebContents *peekPage = [ArcWebContents new];
    peekPage.url = [NSURL URLWithString:@"https://cold.test/"];
    DPPeekCard *peekCard = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    NSView *peekNV = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    [peekCard addSubview:peekNV];
    [win.contentView addSubview:peekCard];
    peekPage.nativeView = peekNV;
    [peekPage setVisibility:2];
    Check([DPTabContextMenu(coldDock) itemWithTitle:@"Unload Tab"] == nil, @"cold tab never steals a Peek card's page sharing its URL");

    _TtC5Popup19PlatformPopupWindow *popupWin = [[_TtC5Popup19PlatformPopupWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                                                                   styleMask:NSWindowStyleMaskBorderless
                                                                                                     backing:NSBackingStoreBuffered defer:YES];
    popupWin.releasedWhenClosed = NO;
    ArcWebContents *littlePage = [ArcWebContents new];
    littlePage.url = [NSURL URLWithString:@"https://cold.test/"];
    NSView *littleNV = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [popupWin.contentView addSubview:littleNV];
    littlePage.nativeView = littleNV;
    [littlePage setVisibility:2];
    Check([DPTabContextMenu(coldDock) itemWithTitle:@"Unload Tab"] == nil, @"cold tab never steals a Little Dia popup page sharing its URL");

    [chromium webContents:peekPage didCloseWithSessionID:@13];
    [chromium webContents:littlePage didCloseWithSessionID:@14];
    [peekCard removeFromSuperview];
    [popupWin close];

    [chromium webContents:homePage didCloseWithSessionID:@10];
    [chromium webContents:navPage didCloseWithSessionID:@11];
    [chromium webContents:frontPage didCloseWithSessionID:@12];
    NSApp.delegate = nil;
    win.mockVisible = NO;
    [win close];
}

static void TestMultiWindowSyncedAndSharedURL(_TtC3ADK18WebContentChromium *chromium) {
    DPTestWindow *win1 = MakeWindow(@"WIN-S1");
    DPTestWindow *win2 = MakeWindow(@"WIN-S2");
    NSString *syncTabID = @"B1111111-1111-1111-1111-111111111111";
    NSString *syncPaneID = @"B1111111-1111-1111-1111-111111111112";
    NSString *otherTabID = @"B2222222-2222-2222-2222-222222222221";
    NSString *dup1TabID = @"B3333333-3333-3333-3333-333333333331";
    NSString *dup1PaneID = @"B3333333-3333-3333-3333-333333333332";
    NSString *dup2TabID = @"B4444444-4444-4444-4444-444444444441";
    NSString *dup2PaneID = @"B4444444-4444-4444-4444-444444444442";

    _TtC5TabUI15TabDockItemView *dock1 = MakeDockItem(win1, [NSString stringWithFormat:@"tab(%@)", syncTabID],
                                                      @{ syncPaneID : @"C" }, @"primary", @"favicon");
    _TtC5TabUI15TabDockItemView *dock2 = MakeDockItem(win2, [NSString stringWithFormat:@"tab(%@)", syncTabID],
                                                      @{ syncPaneID : @"C" }, nil, @"favicon");
    _TtC5TabUI15TabDockItemView *dup1 = MakeDockItem(win1, [NSString stringWithFormat:@"tab(%@)", dup1TabID],
                                                     @{ dup1PaneID : @"C" }, nil, @"favicon");
    _TtC5TabUI15TabDockItemView *dup2 = MakeDockItem(win1, [NSString stringWithFormat:@"tab(%@)", dup2TabID],
                                                     @{ dup2PaneID : @"C" }, nil, @"favicon");

    DPTestScriptTab *stSync1 = MakeScriptTab(syncTabID, @"https://synced.test/");
    DPTestScriptTab *stSync2 = MakeScriptTab(syncTabID, @"https://synced.test/");
    DPTestScriptTab *stOther = MakeScriptTab(otherTabID, @"https://other.test/");
    DPTestScriptTab *stDup1 = MakeScriptTab(dup1TabID, @"https://dup.test/");
    DPTestScriptTab *stDup2 = MakeScriptTab(dup2TabID, @"https://dup.test/");

    DPTestScriptProfile *p1 = [DPTestScriptProfile new];
    p1.appleScriptTabs = @[stSync1, stDup1, stDup2];
    DPTestScriptWindow *sw1 = [DPTestScriptWindow new];
    sw1.windowId = @"WIN-S1";
    sw1.appleScriptTabs = p1.appleScriptTabs;
    sw1.appleScriptProfiles = @[p1];
    sw1.activeTab = stSync1;

    DPTestScriptProfile *p2 = [DPTestScriptProfile new];
    p2.appleScriptTabs = @[stSync2, stOther];
    DPTestScriptWindow *sw2 = [DPTestScriptWindow new];
    sw2.windowId = @"WIN-S2";
    sw2.appleScriptTabs = p2.appleScriptTabs;
    sw2.appleScriptProfiles = @[p2];
    sw2.activeTab = stOther;

    DPTestAppDelegate *appDel = [DPTestAppDelegate new];
    appDel.appleScriptWindows = @[sw1, sw2];
    NSApp.delegate = appDel;

    ArcWebContents *bgSynced = MakePage(nil, nil, @"https://synced.test/", 0, nil);
    NSMenuItem *dedupItem = [DPTabContextMenu(dock2) itemWithTitle:@"Unload Tab"];
    Check(dedupItem != nil && dedupItem.enabled, @"synced pinned tab across 2 windows deduplicates tabID in DPPageByURL");
    [chromium webContents:bgSynced didCloseWithSessionID:@20];
    Check([DPTabContextMenu(dock2) itemWithTitle:@"Unload Tab"] == nil, @"didCloseWithSessionID clears closed page immediately");

    ArcWebContents *sharedPage = MakePage(win1, syncPaneID, @"https://synced.test/", 2, nil);
    NSMenuItem *inWin2Visible = [DPTabContextMenu(dock2) itemWithTitle:@"Unload Tab"];
    Check(inWin2Visible != nil && !inWin2Visible.enabled, @"synced page visible in win1 disables Unload Tab in win2");
    NSString *verifyErr = DPUnloadTab.verify(&DPUnloadTab);
    Check(verifyErr == nil, [NSString stringWithFormat:@"verify passes for synced pinned tab visible in other window (%@)", verifyErr]);
    [sharedPage setVisibility:0];
    NSMenuItem *inWin2Hidden = [DPTabContextMenu(dock2) itemWithTitle:@"Unload Tab"];
    Check(inWin2Hidden != nil && inWin2Hidden.enabled, @"synced page hidden in win1 enables Unload Tab in win2");

    ArcWebContents *pageWin2 = MakePage(win2, syncPaneID, @"https://synced.test/", 0, nil);
    Trigger([DPTabContextMenu(dock1) itemWithTitle:@"Unload Tab"]);
    Check(sharedPage.discardCount == 1 && pageWin2.discardCount == 0, @"per-window pages unload independently for win1");
    Trigger([DPTabContextMenu(dock2) itemWithTitle:@"Unload Tab"]);
    Check(pageWin2.discardCount == 1, @"per-window pages unload independently for win2");

    ArcWebContents *dupPage1 = MakePage(win1, dup1PaneID, @"https://dup.test/", 0, nil);
    ArcWebContents *dupPage2 = MakePage(win1, dup2PaneID, @"https://dup.test/", 0, nil);
    Trigger([DPTabContextMenu(dup1) itemWithTitle:@"Unload Tab"]);
    Check(dupPage1.discardCount == 1 && dupPage2.discardCount == 0, @"shared-URL tab 1 unloads only its own page");
    Trigger([DPTabContextMenu(dup2) itemWithTitle:@"Unload Tab"]);
    Check(dupPage2.discardCount == 1, @"shared-URL tab 2 unloads only its own page");

    [chromium webContents:sharedPage didCloseWithSessionID:@21];
    [chromium webContents:pageWin2 didCloseWithSessionID:@22];
    [chromium webContents:dupPage1 didCloseWithSessionID:@23];
    [chromium webContents:dupPage2 didCloseWithSessionID:@24];
    NSApp.delegate = nil;
    win1.mockVisible = NO;
    win2.mockVisible = NO;
    [win1 close];
    [win2 close];
}

static void TestOffPausedAndVerify(_TtC3ADK18WebContentChromium *chromium) {
    DPTestWindow *win = MakeWindow(@"WIN-OFF");
    NSString *tab1ID = @"C1111111-1111-1111-1111-111111111111";
    NSString *pane1ID = @"C1111111-1111-1111-1111-111111111112";
    NSString *tab2ID = @"C2222222-2222-2222-2222-222222222221";
    NSString *pane2ID = @"C2222222-2222-2222-2222-222222222222";

    _TtC5TabUI7TabView *tab1 = MakeTabView(win, tab1ID, pane1ID, @"https://off1.test/", NO, NO, @"primary", nil);
    _TtC5TabUI15TabDockItemView *dock2 = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", tab2ID],
                                                      @{ pane2ID : @"C" }, nil, @"favicon");

    DPTestScriptTab *st1 = MakeScriptTab(tab1ID, @"https://off1.test/");
    DPTestScriptTab *st2 = MakeScriptTab(tab2ID, @"https://off2.test/");
    DPTestScriptWindow *sw = [DPTestScriptWindow new];
    sw.windowId = @"WIN-OFF";
    sw.appleScriptTabs = @[st1, st2];
    sw.activeTab = st1;
    DPTestAppDelegate *appDel = [DPTestAppDelegate new];
    appDel.appleScriptWindows = @[sw];
    NSApp.delegate = appDel;

    ArcWebContents *page1 = MakePage(win, pane1ID, @"https://off1.test/", 2, nil);
    ArcWebContents *page2 = MakePage(win, pane2ID, @"https://off2.test/", 0, nil);

    st2.onFocus = ^(DPTestScriptTab *t) {
        DPUnloadTab.on = NO;
        [page1 setVisibility:0];
    };
    Trigger([DPTabContextMenu(tab1) itemWithTitle:@"Unload Tab"]);
    DrainMainQueue();
    Check(page1.discardCount == 0, @"turning tweak off prevents queued unload-on-hide from discarding");

    Check([DPTabContextMenu(tab1) itemWithTitle:@"Unload Tab"] == nil, @"off state adds no Unload Tab to TabView");
    Check([DPTabContextMenu(dock2) itemWithTitle:@"Unload Tab"] == nil, @"off state adds no Unload Tab to TabDockItemView");
    NSString *offErr = DPUnloadTab.verify(&DPUnloadTab);
    Check(offErr == nil, [NSString stringWithFormat:@"verify passes when off (%@)", offErr]);

    DPUnloadTab.on = YES;
    [dock2 removeFromSuperview];
    [page1 setVisibility:2];
    NSString *noPinnedErr = DPUnloadTab.verify(&DPUnloadTab);
    Check(noPinnedErr == nil, [NSString stringWithFormat:@"verify passes with 0 pinned tabs (%@)", noPinnedErr]);

    [chromium webContents:page1 didCloseWithSessionID:@30];
    [chromium webContents:page2 didCloseWithSessionID:@31];
    NSApp.delegate = nil;
    win.mockVisible = NO;
    [win close];
}

static void TestNonTabIsolationAndEdgeCases(_TtC3ADK18WebContentChromium *chromium) {
    DPTestWindow *win = MakeWindow(@"WIN-NONTAB");
    DPTestWindow *popupWin = MakeWindow(@"WIN-POPUP");
    NSString *coldTabID = @"D1111111-1111-1111-1111-111111111111";
    NSString *coldPaneID = @"D1111111-1111-1111-1111-111111111112";
    NSString *bgTabID = @"D2222222-2222-2222-2222-222222222221";
    NSString *bgPaneID = @"D2222222-2222-2222-2222-222222222222";
    NSString *frontTabID = @"D3333333-3333-3333-3333-333333333331";
    NSString *frontPaneID = @"D3333333-3333-3333-3333-333333333332";

    _TtC5TabUI15TabDockItemView *coldDock = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", coldTabID],
                                                         @{ coldPaneID : @"C" }, nil, @"favicon");
    _TtC5TabUI15TabDockItemView *bgDock = MakeDockItem(win, [NSString stringWithFormat:@"tab(%@)", bgTabID],
                                                       @{ bgPaneID : @"C" }, nil, @"favicon");
    _TtC5TabUI7TabView *frontTab = MakeTabView(win, frontTabID, frontPaneID, @"https://front.test/", NO, NO, @"primary", nil);

    DPTestScriptTab *stCold = MakeScriptTab(coldTabID, @"https://shared-peek.test/");
    DPTestScriptTab *stBg = MakeScriptTab(bgTabID, @"https://shared-bg.test/");
    DPTestScriptTab *stFront = MakeScriptTab(frontTabID, @"https://front.test/");
    DPTestScriptWindow *sw = [DPTestScriptWindow new];
    sw.windowId = @"WIN-NONTAB";
    sw.appleScriptTabs = @[stCold, stBg, stFront];
    sw.activeTab = stFront;
    DPTestAppDelegate *appDel = [DPTestAppDelegate new];
    appDel.appleScriptWindows = @[sw];
    NSApp.delegate = appDel;

    _TtC11ContentPane15ContentPaneView *frontPane = nil;
    ArcWebContents *frontPage = MakePage(win, frontPaneID, @"https://front.test/", 2, &frontPane);
    DPPeekCard *peekCard = [[DPPeekCard alloc] initWithFrame:frontPane.bounds];
    [frontPane addSubview:peekCard];
    ArcWebContents *peekPage = [ArcWebContents new];
    peekPage.url = [NSURL URLWithString:@"https://shared-peek.test/"];
    peekPage.nativeView = [[NSView alloc] initWithFrame:peekCard.bounds];
    [peekCard addSubview:peekPage.nativeView];
    [peekPage setVisibility:2];
    Check(!DPPageIsTracked(peekPage), @"Peek card WebContents inside ContentPaneView is excluded from tracking");

    ArcWebContents *markedPeek = [ArcWebContents new];
    markedPeek.url = [NSURL URLWithString:@"https://shared-bg.test/"];
    objc_setAssociatedObject(markedPeek, NSSelectorFromString(@"dp_nonTabWebContents"), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [markedPeek setVisibility:2];
    Check(!DPPageIsTracked(markedPeek), @"dp_nonTabWebContents marker excludes WebContents before mounting");

    ArcWebContents *popupPage = [ArcWebContents new];
    popupPage.url = [NSURL URLWithString:@"https://shared-peek.test/"];
    popupPage.nativeView = [[NSView alloc] initWithFrame:popupWin.contentView.bounds];
    [popupWin.contentView addSubview:popupPage.nativeView];
    [popupPage setVisibility:2];

    _TtC18ExtensionSidePanel23WebContentContainerView *extPanel = [[_TtC18ExtensionSidePanel23WebContentContainerView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
    [win.contentView addSubview:extPanel];
    ArcWebContents *extPage = [ArcWebContents new];
    extPage.url = [NSURL URLWithString:@"https://shared-bg.test/"];
    extPage.nativeView = [[NSView alloc] initWithFrame:extPanel.bounds];
    [extPanel addSubview:extPage.nativeView];
    [extPage setVisibility:2];

    _TtC14AssistantPanel18AssistantPanelView *chatPanel = [[_TtC14AssistantPanel18AssistantPanelView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
    [win.contentView addSubview:chatPanel];
    ArcWebContents *chatPage = [ArcWebContents new];
    chatPage.url = [NSURL URLWithString:@"https://shared-peek.test/"];
    chatPage.nativeView = [[NSView alloc] initWithFrame:chatPanel.bounds];
    [chatPanel addSubview:chatPage.nativeView];
    [chatPage setVisibility:2];

    Check([DPTabContextMenu(coldDock) itemWithTitle:@"Unload Tab"] == nil,
          @"cold pinned tab never matches Peek, popup, or Side Chat WebContents at same URL");

    ArcWebContents *realBgPage = MakePage(nil, nil, @"https://shared-bg.test/", 0, nil);
    NSMenuItem *bgItem = [DPTabContextMenu(bgDock) itemWithTitle:@"Unload Tab"];
    Check(bgItem != nil && bgItem.enabled, @"real background tab matches cleanly despite non-tab WebContents at same URL");
    Trigger(bgItem);
    Check(realBgPage.discardCount == 1 && markedPeek.discardCount == 0 && extPage.discardCount == 0 && peekPage.discardCount == 0 && popupPage.discardCount == 0,
          @"only real tab page is discarded; Peek, ExtensionSidePanel, and popup pages remain untouched");

    __block BOOL raceSwitched = NO;
    stCold.onFocus = ^(DPTestScriptTab *t) {
        raceSwitched = YES;
        [frontPage setVisibility:0];
        [frontPage setVisibility:2];
    };
    stBg.onFocus = stCold.onFocus;
    NSMenuItem *raceItem = [DPTabContextMenu(frontTab) itemWithTitle:@"Unload Tab"];
    Trigger(raceItem);
    DrainMainQueue();
    Check(raceSwitched && frontPage.discardCount == 0, @"switching back to visible before async discard prevents unloading visible tab");

    [realBgPage setVisibility:2];
    [realBgPage setVisibility:0];
    NSMenuItem *staleDiscardItem = [DPTabContextMenu(bgDock) itemWithTitle:@"Unload Tab"];
    [chromium webContents:realBgPage finalizeDiscardRequest:YES];
    NSInteger beforeDiscard = realBgPage.discardCount;
    Trigger(staleDiscardItem);
    Check(realBgPage.discardCount == beforeDiscard, @"clicking stale menu item after finalizeDiscardRequest is a no-op");

    [realBgPage setVisibility:2];
    [realBgPage setVisibility:0];
    NSMenuItem *staleCloseItem = [DPTabContextMenu(bgDock) itemWithTitle:@"Unload Tab"];
    [chromium webContents:realBgPage didCloseWithSessionID:@99];
    Trigger(staleCloseItem);
    Check(realBgPage.discardCount == beforeDiscard, @"clicking stale menu item after didCloseWithSessionID is a no-op");

    sw.activeTab = MakeScriptTab(@"MISSING-ID", @"https://missing.test/");
    Check(DPTabBefore(win) == stCold, @"DPTabBefore falls back to first tab when active tab is not in appleScriptTabs");

    DPEphemeralScriptWindow *eph = [DPEphemeralScriptWindow new];
    eph.windowId = @"WIN-NONTAB";
    eph.tabIDs = @[ coldTabID, frontTabID ];
    eph.activeTabID = frontTabID;
    __block NSString *focusedEphID = nil;
    __weak DPEphemeralScriptWindow *weakEph = eph;
    eph.onFocusTabID = ^(NSString *tid) {
        focusedEphID = tid;
        weakEph.activeTabID = tid;
        [frontPage setVisibility:0];
    };
    appDel.appleScriptWindows = @[ eph ];
    NSMenuItem *ephItem = nil;
    @autoreleasepool {
        ephItem = [DPTabContextMenu(frontTab) itemWithTitle:@"Unload Tab"];
    }
    Check(ephItem != nil && ephItem.enabled, @"front tab with ephemeral AppleScript tabs offers enabled Unload Tab");
    Trigger(ephItem);
    DrainMainQueue();
    Check([focusedEphID isEqualToString:coldTabID] && frontPage.discardCount == 1,
          @"ephemeral AppleScript wrapper still focuses previous tab and discards front tab after autoreleasepool drain");

    [chromium webContents:frontPage didCloseWithSessionID:@40];
    [chromium webContents:peekPage didCloseWithSessionID:@41];
    [chromium webContents:markedPeek didCloseWithSessionID:@42];
    [chromium webContents:popupPage didCloseWithSessionID:@43];
    [chromium webContents:extPage didCloseWithSessionID:@44];
    [chromium webContents:chatPage didCloseWithSessionID:@45];
    NSApp.delegate = nil;
    win.mockVisible = NO;
    popupWin.mockVisible = NO;
    [win close];
    [popupWin close];
}

static void TestTabBeforeInHoldingProfile(void) {
    DPTestWindow *win = MakeWindow(@"WIN-PROFILES");
    DPTestScriptTab *a1 = MakeScriptTab(@"E1111111-1111-1111-1111-111111111111", @"https://a1.test/");
    DPTestScriptTab *a2 = MakeScriptTab(@"E1111111-1111-1111-1111-111111111112", @"https://a2.test/");
    DPTestScriptTab *b1 = MakeScriptTab(@"E2222222-2222-2222-2222-222222222221", @"https://b1.test/");
    DPTestScriptTab *b2 = MakeScriptTab(@"E2222222-2222-2222-2222-222222222222", @"https://b2.test/");
    DPTestScriptTab *b3 = MakeScriptTab(@"E2222222-2222-2222-2222-222222222223", @"https://b3.test/");
    DPTestScriptProfile *pa = [DPTestScriptProfile new], *pb = [DPTestScriptProfile new];
    pa.appleScriptTabs = @[a1, a2];
    pb.appleScriptTabs = @[b1, b2, b3];
    DPTestScriptWindow *sw = [DPTestScriptWindow new];
    sw.windowId = @"WIN-PROFILES";
    sw.appleScriptProfiles = @[pa, pb];
    sw.activeTab = b2;
    DPTestAppDelegate *appDel = [DPTestAppDelegate new];
    appDel.appleScriptWindows = @[sw];
    NSApp.delegate = appDel;

    Check(DPTabBefore(win) == b3, @"DPTabBefore finds the neighbor in the profile holding the front tab when the window lists none");
    sw.appleScriptTabs = pa.appleScriptTabs;
    Check(DPTabBefore(win) == b3, @"DPTabBefore ignores another profile's tabs listed on the window");
    sw.activeTab = b3;
    Check(DPTabBefore(win) == b2, @"DPTabBefore steps back inside the holding profile from its last tab");
    sw.activeTab = a1;
    Check(DPTabBefore(win) == a2, @"DPTabBefore follows the front tab to the other profile");

    NSApp.delegate = nil;
    win.mockVisible = NO;
    [win close];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPArmTestWatchdog(120);
        DPUnloadTab.install();
        DPUnloadTab.on = YES;
        _TtC3ADK18WebContentChromium *chromium = [_TtC3ADK18WebContentChromium new];

        DPStage("TestRegularAndSidebarPinnedTabs");
        TestRegularAndSidebarPinnedTabs(chromium);
        DPStage("TestDockAndTopTabPinnedTabs");
        TestDockAndTopTabPinnedTabs(chromium);
        DPStage("TestMultiWindowSyncedAndSharedURL");
        TestMultiWindowSyncedAndSharedURL(chromium);
        DPStage("TestOffPausedAndVerify");
        TestOffPausedAndVerify(chromium);
        DPStage("TestNonTabIsolationAndEdgeCases");
        TestNonTabIsolationAndEdgeCases(chromium);
        DPStage("TestTabBeforeInHoldingProfile");
        TestTabBeforeInHoldingProfile();

        if (failures) {
            printf("%d unload-tab test(s) failed\n", failures);
            return 1;
        }
        printf("all unload-tab tests passed\n");
    }
    return 0;
}

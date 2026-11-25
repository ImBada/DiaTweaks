#import "Peek/Peek.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import <Carbon/Carbon.h>
#import <objc/runtime.h>

static int gCloseCalls, gDetachCalls, gGiveCalls, gZoomCalls, gOrigZoomCalls;
static NSString *gActiveTabID;
static NSMapTable<NSWindow *, id> *gScriptWindows;

@interface DPTabMock : NSObject
@property (nonatomic, copy) NSString *tabId;
@end
@implementation DPTabMock
+ (instancetype)tabWithID:(NSString *)tid { DPTabMock *t = [self new]; t.tabId = tid; return t; }
@end

@interface DPProfileMock : NSObject
@property (nonatomic, strong) NSMutableArray<DPTabMock *> *appleScriptTabs;
@end
@implementation DPProfileMock
@end

@interface DPScriptWindowMock : NSObject
@property (nonatomic, strong) NSMutableArray<DPTabMock *> *appleScriptTabs;
@property (nonatomic, strong) NSMutableArray<DPProfileMock *> *appleScriptProfiles;
@property (nonatomic, copy) NSString *activeID;
@end
@implementation DPScriptWindowMock
- (id)activeTab {
    if (!self.activeID) return nil;
    return [DPTabMock tabWithID:self.activeID];
}
@end

@interface DPFakeTabState : NSObject
@property (nonatomic, copy) NSString *selectionStyle, *contentID;
@end
static int gDescriptions, gMenuBuilds;

@implementation DPFakeTabState
- (NSString *)description {
    gDescriptions++;
    return self.contentID ? [NSString stringWithFormat:@"state(contentIDs: [%@], selectionStyle: %@)", self.contentID, self.selectionStyle ?: @"nil"]
                          : [NSString stringWithFormat:@"state(selectionStyle: %@)", self.selectionStyle ?: @"nil"];
}
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"selectionStyle"] ? self.selectionStyle : nil; }
@end

@interface DPFakeTabSubject : NSObject
@property (nonatomic, strong) DPFakeTabState *currentValue;
@end
@implementation DPFakeTabSubject
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"currentValue"] ? self.currentValue : nil; }
@end

@interface DPFakeTabVM : NSObject
@property (nonatomic, strong) DPFakeTabSubject *stateSubject;
@end
@implementation DPFakeTabVM
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"stateSubject"] ? self.stateSubject : nil; }
@end

@interface _TtC5TabUI7TabView : NSView
@property (nonatomic, strong) DPFakeTabVM *viewModel;
@property (nonatomic) BOOL pinnedRow;
@end
@implementation _TtC5TabUI7TabView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"viewModel"] ? self.viewModel : nil; }
- (NSMenu *)menuForEvent:(NSEvent *)event {
    gMenuBuilds++;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Tab"];
    [menu addItemWithTitle:self.pinnedRow ? @"Unpin" : @"Pin" action:@selector(copy:) keyEquivalent:@""];
    return menu;
}
@end

@interface _TtC5TabUI15TabDockItemView : NSView
@property (nonatomic, strong) DPFakeTabVM *viewModel;
@end
@implementation _TtC5TabUI15TabDockItemView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"viewModel"] ? self.viewModel : nil; }
@end

@interface DPTestTabStrip : NSView
@end
@implementation DPTestTabStrip
@end

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; }
@end

@interface DPPeekHostMock : NSView
@end
@implementation DPPeekHostMock
- (BOOL)acceptsFirstResponder { return YES; }
@end

@interface ArcWebContents : NSObject <DPPeekPage>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL isReadyToDisplay;
@property (nonatomic) float zoomFactor;
@property (nonatomic, weak) NSView *attachedHost;
@end
@implementation ArcWebContents
- (NSView *)createPaneHostView { return [[DPPeekHostMock alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)]; }
- (void)attachToPaneHostView:(NSView *)host { self.attachedHost = host; }
- (void)detachFromPaneHostView:(NSView *)host { gDetachCalls++; if (self.attachedHost == host) self.attachedHost = nil; }
- (void)close { gCloseCalls++; }
- (void)closeWithForegroundCommitTiming:(NSInteger)timing {}
- (void)setVisibility:(NSInteger)visibility {}
- (id)navigationController { return self; }
- (id)load:(NSURL *)url initiatorOrigin:(NSURL *)origin { self.url = url; return nil; }
- (void)resetZoomAndScaleFactors { self.zoomFactor = 1; gZoomCalls++; }
- (void)setZoomFactor:(float)z { _zoomFactor = z; gZoomCalls++; }
@end

@interface DPIdentifiedPage : ArcWebContents
@property (nonatomic, copy) NSString *identifier;
@end
@implementation DPIdentifiedPage
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"identifier"] ? self.identifier : nil; }
@end

@interface ArcWebContentsConfiguration : NSObject
@end
@implementation ArcWebContentsConfiguration
@end

@interface ArcBrowserContext : NSObject
@end
@implementation ArcBrowserContext
- (id)createWebContents:(id)config {
    ArcWebContents *p = [ArcWebContents new];
    p.url = [NSURL URLWithString:@"https://example.com"];
    return p;
}
@end

@interface ArcBrowser : NSObject
@end
@implementation ArcBrowser
- (id)createWebContents:(id)config { return [[ArcBrowserContext new] createWebContents:config]; }
@end

@interface _TtC3ADK18WebContentChromium : NSObject
@end
@implementation _TtC3ADK18WebContentChromium
- (void)webContents:(id)source didCreateNewWebContent:(id)page targetURL:(NSURL *)url disposition:(NSInteger)disp { gGiveCalls++; }
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

@interface DPPeekTabWindow : NSWindow
@property NSInteger makeKeyCalls;
@property BOOL fakeKey;
@property CGFloat fakeScale;
@end
@implementation DPPeekTabWindow
- (void)makeKeyWindow { self.makeKeyCalls++; }
- (BOOL)isKeyWindow { return self.fakeKey; }
- (BOOL)isVisible { return YES; }
- (CGFloat)backingScaleFactor { return self.fakeScale > 0 ? self.fakeScale : [super backingScaleFactor]; }
@end

DPPatch DPPeek = { .on = YES }, DPPeekPinnedLinks = { .on = YES }, DPShowLoadingProgress;
static ArcBrowser *gBrowser;

id DPScriptWindow(NSWindow *window) { return [gScriptWindows objectForKey:window]; }
NSString *DPTabID(id tab) { return [tab respondsToSelector:@selector(tabId)] ? [tab valueForKey:@"tabId"] : nil; }
NSString *DPActiveTabIDIn(id scriptWindow) { return DPTabID([scriptWindow valueForKey:@"activeTab"]); }
NSString *DPActiveTabID(NSWindow *window) {
    id sw = DPScriptWindow(window);
    return sw ? DPActiveTabIDIn(sw) : gActiveTabID;
}
id DPBrowserOfWindow(NSWindow *window) { return gBrowser; }
void DPOnLaunch(void (^block)(void)) { block(); }
double DPPeekDarkness(void) { return 0.45; }
double DPPeekResponse(void) { return 0.2; }
BOOL DPPeekGenie(void) { return NO; }
BOOL DPPeekShowsToolbar(void) { return NO; }
void DPPeekAddToolbar(DPPeekCard *peek) {}
CGFloat DPPeekToolbarInset(DPPeekCard *peek) { return 0; }
void DPPeekPlaceToolbar(DPPeekCard *peek) {}
void DPPeekNavigate(id page, DPPeekStep step) {}
void DPPeekEditToolbarAddress(DPPeekCard *peek) {}
BOOL DPPeekCopyURL(DPPeekCard *peek, NSEvent *event) { return NO; }
BOOL DPPeekIsShortcut(NSEvent *event, NSMenuItem *item) { return NO; }
float DPZoomStep(float now, int direction) { return direction > 0 ? now + 0.1f : now - 0.1f; }
BOOL DPEventIsKey(NSEvent *event, NSString *key) { return [event.charactersIgnoringModifiers caseInsensitiveCompare:key] == NSOrderedSame; }
void DPPeekOpenDragged(NSURL *url, NSPoint origin) {}
void DPPeekHideDragZone(void) {}
NSURL *DPAddressURL(NSString *typed) { return [NSURL URLWithString:typed]; }
NSButton *DPMakeBarButton(NSString *symbol, NSString *label, NSString *key, void (^action)(void)) { return [NSButton new]; }

#import "Peek/Controls.m"
#import "Peek/Address.m"
#import "Peek/Find.m"
#import "Peek/Tab.m"
#import "Peek/Selection.m"
#import "Peek/Motion.m"
#import "Peek/Keys.m"
#import "Peek/Visibility.m"
#import "Peek/Chat.m"
#import "Peek/ChatContext.m"
#import "Peek/Card.m"
#import "Peek/Pages.m"
#import "Peek/Handoff.m"
#import "Peek/Zoom.m"

static int failures;
static void Check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}

static NSView *MakeHolder(NSWindow *window, NSRect frame, _TtC11ContentPane15ContentPaneView **outPane) {
    NSView *holder = [[NSView alloc] initWithFrame:frame];
    holder.wantsLayer = YES;
    holder.layer.cornerRadius = 10;
    holder.layer.masksToBounds = YES;
    _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:holder.bounds];
    [holder addSubview:pane];
    [window.contentView addSubview:holder];
    if (outPane) *outPane = pane;
    return holder;
}

static _TtC5TabUI7TabView *MakeTabRow(NSView *parent, NSString *contentID, NSString *style) {
    _TtC5TabUI7TabView *tab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 180, 32)];
    DPFakeTabVM *vm = [DPFakeTabVM new];
    vm.stateSubject = [DPFakeTabSubject new];
    vm.stateSubject.currentValue = [DPFakeTabState new];
    vm.stateSubject.currentValue.contentID = contentID;
    vm.stateSubject.currentValue.selectionStyle = style;
    tab.viewModel = vm;
    [parent addSubview:tab];
    return tab;
}

static _TtC5TabUI15TabDockItemView *MakePinnedTile(NSView *parent, NSString *style) {
    _TtC5TabUI15TabDockItemView *tab = [[_TtC5TabUI15TabDockItemView alloc] initWithFrame:NSMakeRect(0, 0, 44, 44)];
    DPFakeTabVM *vm = [DPFakeTabVM new];
    vm.stateSubject = [DPFakeTabSubject new];
    vm.stateSubject.currentValue = [DPFakeTabState new];
    vm.stateSubject.currentValue.selectionStyle = style;
    tab.viewModel = vm;
    [parent addSubview:tab];
    return tab;
}

static NSEvent *KeyEvent(NSWindow *window, NSString *chars, unsigned short code, NSEventModifierFlags mods) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:0
                        windowNumber:window.windowNumber context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code];
}

static void DrainMain(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!drained && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gScriptWindows = [NSMapTable weakToStrongObjectsMapTable];
        gBrowser = [ArcBrowser new];
        DPPeekInstallPages();
        DPPeekInstallSelection();
        DPPeekInstallZoom();

        DPPeekTabWindow *window = [[DPPeekTabWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 900, 600)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.fakeKey = YES;

        DPScriptWindowMock *sw = [DPScriptWindowMock new];
        sw.appleScriptTabs = [NSMutableArray arrayWithObjects:[DPTabMock tabWithID:@"A"], [DPTabMock tabWithID:@"B"], [DPTabMock tabWithID:@"C"], nil];
        sw.activeID = @"A";
        [gScriptWindows setObject:sw forKey:window];

        _TtC11ContentPane15ContentPaneView *pane1 = nil;
        NSView *holder1 = MakeHolder(window, NSMakeRect(200, 0, 700, 600), &pane1);
        _TtC3ADK18WebContentChromium *delegate = [_TtC3ADK18WebContentChromium new];

        ArcWebContents *sourceA = [ArcWebContents new], *sourceB = [ArcWebContents new];
        NSString *uuidA = @"11111111-1111-1111-1111-111111111111";
        _TtC5TabUI7TabView *rowA = MakeTabRow(window.contentView, uuidA, @"selected");
        DPPeekOpenFrom(window, @"A", [NSURL URLWithString:@"https://a.example"], NSMakeRect(250, 200, 80, 20), delegate, sourceA, nil, nil);
        DPPeekCard *p1 = DPPeekCardIn(window);
        ArcWebContents *p1Page = (ArcWebContents *)p1.page;
        p1Page.url = [NSURL URLWithString:@"about:blank"];
        Check(p1 != nil && DPPeekPageIn(window) == p1Page && [p1.originTabID isEqual:@"A"], "P1 opens on Tab A");
        Check(p1.superview == holder1 && p1.tabBadge.superview == rowA, "P1 mounts in holder1 with badge on rowA");
        Check(DPPeekSyncTimer != nil, "sync timer runs while cards exist");

        ArcWebContents *dupWarm = [ArcWebContents new];
        dupWarm.url = [NSURL URLWithString:@"about:blank"];
        gCloseCalls = 0;
        DPPeekOpenFrom(window, @"A", [NSURL URLWithString:@"https://dup.example"], NSMakeRect(250, 200, 80, 20), delegate, sourceA, dupWarm, nil);
        Check(DPPeekAllCards(window).count == 1 && gCloseCalls == 1, "duplicate Peek on Tab A rejected and warm page discarded");

        gDetachCalls = gCloseCalls = 0;
        [window makeFirstResponder:p1.host];
        sw.activeID = @"B";
        rowA.viewModel.stateSubject.currentValue.selectionStyle = @"none";
        DPPeekSyncTabs(window);
        Check(p1.hidden && !p1.closing && p1.superview == window.contentView, "switching to B hides P1 and parks it on contentView");
        Check(DPPeekCardIn(window) == nil && DPPeekPageIn(window) == nil && DPPeekHiddenCards(window).count == 1, "DPPeekCardIn/PageIn nil while P1 parked");
        Check(gDetachCalls == 0 && gCloseCalls == 0 && p1Page.attachedHost == p1.host, "parking preserves P1 WebContents attached");
        Check(window.firstResponder != p1.host, "hiding P1 clears first responder off hidden card");
        Check(p1.tabBadge.superview == rowA, "👀 badge stays on Tab A row while parked");

        ArcWebContents *staleWarm = [ArcWebContents new];
        staleWarm.url = [NSURL URLWithString:@"about:blank"];
        gCloseCalls = 0;
        DPPeekOpenFrom(window, @"A", [NSURL URLWithString:@"https://stale.example"], NSMakeRect(250, 200, 80, 20), delegate, sourceA, staleWarm, nil);
        Check(DPPeekAllCards(window).count == 1 && gCloseCalls == 1, "stale click for inactive origin tab discarded cleanly");

        DPPeekOpenFrom(window, @"B", [NSURL URLWithString:@"https://b.example"], NSMakeRect(250, 200, 80, 20), delegate, sourceB, nil, nil);
        DPPeekCard *p2 = DPPeekCardIn(window);
        ArcWebContents *p2Page = (ArcWebContents *)p2.page;
        p2Page.url = [NSURL URLWithString:@"about:blank"];
        Check(p2 != nil && p2 != p1 && DPPeekAllCards(window).count == 2 && DPPeekHiddenCards(window).count == 1, "P2 opens on Tab B alongside parked P1");

        NSEvent *esc = KeyEvent(window, @"\x1b", kVK_Escape, 0);
        NSEvent *cmdW = KeyEvent(window, @"w", kVK_ANSI_W, NSEventModifierFlagCommand);
        NSEvent *cmdF = KeyEvent(window, @"f", kVK_ANSI_F, NSEventModifierFlagCommand);
        NSEvent *ctrlTab = KeyEvent(window, @"\t", kVK_Tab, NSEventModifierFlagControl);
        Check(DPPeekHandleKeyEvent(p1, esc) == esc && !p1.closing, "hidden P1 does not intercept Esc");
        Check(DPPeekHandleKeyEvent(p1, cmdW) == cmdW && !p1.closing, "hidden P1 does not intercept Cmd+W");
        Check(DPPeekHandleKeyEvent(p1, cmdF) == cmdF, "hidden P1 does not intercept Cmd+F");
        Check(DPPeekHandleKeyEvent(p1, ctrlTab) == ctrlTab, "hidden P1 does not intercept Control+Tab");

        _TtC6Window24PlatformWindowController *wc = [[_TtC6Window24PlatformWindowController alloc] initWithWindow:window];
        gZoomCalls = gOrigZoomCalls = 0;
        [wc zoomIn:nil];
        Check(gZoomCalls == 1 && p2Page.zoomFactor > 0 && p1Page.zoomFactor == 0, "zoom reaches active P2, not hidden P1");

        sw.activeID = @"C";
        DPPeekSyncTabs(window);
        Check(p1.hidden && p2.hidden && DPPeekCardIn(window) == nil && DPPeekHiddenCards(window).count == 2, "Tab C hides both P1 and P2");
        Check(DPPeekHandleKeyEvent(p1, esc) == esc && DPPeekHandleKeyEvent(p2, esc) == esc, "neither hidden card intercepts Esc on Tab C");
        gZoomCalls = gOrigZoomCalls = 0;
        [wc zoomIn:nil];
        Check(gZoomCalls == 0 && gOrigZoomCalls == 1, "zoom passes through to Dia on Tab C with no visible Peek");

        [holder1 removeFromSuperview];
        [rowA removeFromSuperview];
        _TtC11ContentPane15ContentPaneView *pane2 = nil;
        NSView *holder2 = MakeHolder(window, NSMakeRect(0, 0, 900, 540), &pane2);
        DPTestTabStrip *strip = [[DPTestTabStrip alloc] initWithFrame:NSMakeRect(0, 540, 900, 40)];
        [window.contentView addSubview:strip];
        _TtC5TabUI7TabView *topRowA = MakeTabRow(strip, uuidA, @"selected");
        sw.activeID = @"A";
        [window makeFirstResponder:pane2];
        DPPeekSyncTabs(window);
        DrainMain();
        Check(!p1.hidden && p2.hidden && p1.superview == holder2 && p1.pane == pane2, "returning to A remounts P1 into rebuilt holder2/pane2");
        Check(NSEqualRects(p1.frame, [holder2 convertRect:pane2.bounds fromView:pane2]), "P1 adopts rebuilt pane2 frame");
        Check(p1.tabBadge.superview == topRowA, "👀 badge reattaches onto rebuilt top-tab rowA");
        Check(window.firstResponder == p1.host, "returning to A restores first responder to P1");

        NSString *uuidOther = @"99999999-9999-9999-9999-999999999999";
        topRowA.viewModel.stateSubject.currentValue.contentID = uuidOther;
        DPPeekRefreshTabBadge(p1);
        Check(p1.tabBadge.superview == nil && topRowA.trackingAreas.count == 0,
              "recycled TabView cell sheds 👀 badge and tracking area when origin tab scrolls off-screen");
        _TtC5TabUI7TabView *reboundA = MakeTabRow(strip, uuidA, @"selected");
        DPPeekRefreshTabBadge(p1);
        Check(p1.tabBadge.superview == reboundA && reboundA.trackingAreas.count == 1,
              "👀 badge re-attaches cleanly once origin tab reappears");
        [reboundA removeFromSuperview];
        topRowA.viewModel.stateSubject.currentValue.contentID = uuidA;
        DPPeekRefreshTabBadge(p1);

        window.fakeScale = 1.0;
        [p1 viewDidChangeBackingProperties];
        Check(fabs(p1.clip.layer.borderWidth - 1.0) < 0.01, "DPPeekCard updates clip borderWidth for 1x display");
        DPPeekButton *ctrlBtn = nil;
        for (NSView *sub in p1.controls.subviews) if ([sub isKindOfClass:DPPeekButton.class]) { ctrlBtn = (DPPeekButton *)sub; break; }
        [ctrlBtn viewDidChangeBackingProperties];
        Check(ctrlBtn != nil && fabs(ctrlBtn.iconLayer.contentsScale - 1.0) < 0.01, "DPPeekButton re-rasterizes icon at 1x scale");
        window.fakeScale = 2.0;
        [p1 viewDidChangeBackingProperties];
        [ctrlBtn viewDidChangeBackingProperties];
        Check(fabs(p1.clip.layer.borderWidth - 0.5) < 0.01 && fabs(ctrlBtn.iconLayer.contentsScale - 2.0) < 0.01,
              "DPPeekCard and DPPeekButton restore 2x hairline and Retina icon on 2x display");
        DPPeekFindShortcut(p1, cmdF, NSEventModifierFlagCommand);
        DPPeekFind *findBar = DPGet(p1, DPPeekFindKey);
        window.fakeScale = 1.0;
        [findBar viewDidChangeBackingProperties];
        Check(findBar != nil && fabs(findBar.layer.borderWidth - 1.0) < 0.01, "DPPeekFind updates borderWidth on scale change");
        window.fakeScale = 2.0;
        DPPeekHideFind(p1);

        DPPeekAddress *addr = (DPPeekAddress *)DPPeekAddressFor(p1Page);
        addr.frame = NSMakeRect(0, 0, 200, 30);
        [p1.clip addSubview:addr];
        [addr begin];
        Check(addr.field != nil, "address field begins editing");
        sw.activeID = @"C";
        DPPeekSyncTabs(window);
        [addr end];
        Check(window.firstResponder != p1.host, "ending address edit on hidden P1 never steals focus");
        DPPeekFindShortcut(p1, cmdF, NSEventModifierFlagCommand);
        DPPeekHideFind(p1);
        Check(window.firstResponder != p1.host, "closing Find bar on hidden P1 never steals focus");

        NSTextView *externalBar = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 30)];
        [window.contentView addSubview:externalBar];
        [window makeFirstResponder:externalBar];
        sw.activeID = @"A";
        DPPeekSyncTabs(window);
        DrainMain();
        Check(window.firstResponder == externalBar, "returning to A does not steal focus from external NSTextView");

        DPProfileMock *prof1 = [DPProfileMock new];
        prof1.appleScriptTabs = [NSMutableArray arrayWithObjects:[DPTabMock tabWithID:@"A"], [DPTabMock tabWithID:@"B"], nil];
        DPProfileMock *prof2 = [DPProfileMock new];
        prof2.appleScriptTabs = [NSMutableArray arrayWithObjects:[DPTabMock tabWithID:@"P2-1"], nil];
        sw.appleScriptProfiles = [NSMutableArray arrayWithObjects:prof1, prof2, nil];
        sw.appleScriptTabs = prof2.appleScriptTabs;
        sw.activeID = @"P2-1";
        DPPeekSyncTabs(window);
        Check(p1.hidden && p2.hidden && !p1.closing && !p2.closing && DPPeekAllCards(window).count == 2,
              "switching profiles hides Peeks without pruning other profile's tabs");

        sw.activeID = nil;
        DPPeekSyncTabs(window);
        Check(p1.hidden && p2.hidden && !p1.closing && !p2.closing, "unreadable selection hides without exposing or pruning");

        gCloseCalls = 0;
        window.makeKeyCalls = 0;
        [prof1.appleScriptTabs removeLastObject];
        sw.activeID = @"P2-1";
        DPPeekSyncTabs(window);
        Check(p2.closing && !p2.superview && gCloseCalls == 1 && window.makeKeyCalls == 0, "removed origin tab B synchronously closes hidden P2 without makeKeyWindow");
        Check(!p1.closing && DPPeekAllCards(window).count == 1, "P1 stays alive when B is removed");

        gCloseCalls = 0;
        [delegate webContents:sourceA finalizeDiscardRequest:NO];
        Check(!p1.closing && DPPeekAllCards(window).count == 1, "declined discard leaves hidden P1 open");
        [delegate webContents:sourceA finalizeDiscardRequest:YES];
        Check(p1.closing && !p1.superview && gCloseCalls == 1 && DPPeekAllCards(window).count == 0,
              "confirmed discard (unload) immediately tears down hidden P1");
        Check(DPPeekSyncTimer == nil, "sync timer stops once last card closes");

        topRowA.hidden = YES;
        sw.appleScriptTabs = [NSMutableArray arrayWithObjects:[DPTabMock tabWithID:@"pin-1"], [DPTabMock tabWithID:@"C"], nil];
        sw.appleScriptProfiles = nil;
        sw.activeID = @"pin-1";
        _TtC5TabUI15TabDockItemView *pinTile = MakePinnedTile(window.contentView, @"selected");
        ArcWebContents *pinSource = [ArcWebContents new];
        DPPeekOpenFrom(window, @"pin-1", [NSURL URLWithString:@"https://pin.example"], NSMakeRect(100, 100, 80, 20), delegate, pinSource, nil, nil);
        DPPeekCard *pinPeek = DPPeekCardIn(window);
        ((ArcWebContents *)pinPeek.page).url = [NSURL URLWithString:@"about:blank"];
        Check(pinPeek != nil && pinPeek.tabBadge.superview == pinTile, "pinned icon tile opens Peek with badge on TabDockItemView");
        sw.activeID = @"C";
        pinTile.viewModel.stateSubject.currentValue.selectionStyle = nil;
        DPPeekSyncTabs(window);
        Check(pinPeek.hidden && !pinPeek.closing && pinPeek.tabBadge.superview == pinTile, "switching away from pinned tile hides Peek and keeps badge");
        sw.activeID = @"pin-1";
        pinTile.viewModel.stateSubject.currentValue.selectionStyle = @"selected";
        DPPeekSyncTabs(window);
        Check(!pinPeek.hidden && DPPeekCardIn(window) == pinPeek, "returning to pinned tile restores its Peek");
        sw.activeID = @"C";
        DPPeekSyncTabs(window);
        gCloseCalls = 0;
        [pinSource closeWithForegroundCommitTiming:0];
        Check(pinPeek.closing && !pinPeek.superview && gCloseCalls == 1 && DPPeekAllCards(window).count == 0,
              "closing pinned tab's WebContents tears down hidden Peek immediately");

        {
            sw.activeID = @"C";
            ArcWebContents *ntpSource = [ArcWebContents new];
            DPPeekOpenFrom(window, @"C", [NSURL URLWithString:@"https://ntp-switch.example"], NSMakeRect(100, 100, 80, 20), delegate, ntpSource, nil, nil);
            DPPeekCard *ntpPeek = DPPeekCardIn(window);
            ArcWebContents *ntpPeekPage = (ArcWebContents *)ntpPeek.page;
            ntpPeekPage.url = [NSURL URLWithString:@"about:blank"];
            Check(ntpPeek != nil && !ntpPeek.hidden, "Peek opens on Tab C before switching to NTP");
            sw.activeID = @"pin-1";
            // Simulate Dia hiding source WebContents when switching to a non-WebContents NTP/unloaded tab (no new page gets setVisibility:2).
            [ntpSource setVisibility:0];
            Check(ntpPeek.hidden && DPPeekCardIn(window) == nil, "hiding visible Peek source immediately parks Peek without waiting for sync timer");
            sw.activeID = @"C";
            DPPeekSyncTabs(window);
            Check(!ntpPeek.hidden, "Peek restores on return to C");
            gCloseCalls = 0;
            [ntpPeekPage close];
            Check(ntpPeek.closing && DPPeekCardIn(window) == nil,
                  "window.close() on visible Peek page immediately begins closing Peek card");
            [ntpPeek handOverTo:nil attach:nil];

            DPPeekOpenFrom(window, @"C", [NSURL URLWithString:@"https://parked-close.example"], NSMakeRect(100, 100, 80, 20), delegate, ntpSource, nil, nil);
            DPPeekCard *parkedClose = DPPeekCardIn(window);
            ArcWebContents *parkedClosePage = (ArcWebContents *)parkedClose.page;
            parkedClosePage.url = [NSURL URLWithString:@"about:blank"];
            sw.activeID = @"pin-1";
            DPPeekSyncTabs(window);
            Check(parkedClose.hidden, "parkedClose hidden on switch");
            [parkedClosePage closeWithForegroundCommitTiming:0];
            Check(parkedClose.closing && DPPeekAllCards(window).count == 0,
                  "closeWithForegroundCommitTiming: on parked Peek page synchronously removes Peek card");
        }

        {
            sw.appleScriptTabs = [NSMutableArray arrayWithObjects:[DPTabMock tabWithID:@"A"], [DPTabMock tabWithID:@"B"], nil];
            sw.activeID = @"A";
            ArcWebContents *srcA = [ArcWebContents new], *srcB = [ArcWebContents new];
            DPPeekOpenFrom(window, @"A", [NSURL URLWithString:@"https://promote-a.example"], NSMakeRect(100, 100, 80, 20), delegate, srcA, nil, nil);
            DPPeekCard *peekA = DPPeekCardIn(window);
            ((ArcWebContents *)peekA.page).url = [NSURL URLWithString:@"about:blank"];
            sw.activeID = @"B";
            DPPeekSyncTabs(window);
            DPPeekOpenFrom(window, @"B", [NSURL URLWithString:@"https://promote-b.example"], NSMakeRect(100, 100, 80, 20), delegate, srcB, nil, nil);
            DPPeekCard *peekB = DPPeekCardIn(window);
            ((ArcWebContents *)peekB.page).url = [NSURL URLWithString:@"about:blank"];
            Check(peekA.hidden && !peekB.hidden && DPPeekAllCards(window).count == 2, "parked Peek A and visible Peek B before promotion");

            NSView *tabHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
            [window.contentView addSubview:tabHost];
            gDetachCalls = 0;
            peekB.grown = 1;
            __block BOOL mountedDuringAttach = NO;
            [peekB handOverTo:tabHost attach:^{ mountedDuringAttach = peekB.superview != nil; }];
            Check(mountedDuringAttach && gDetachCalls == 1 && peekB.superview == nil && peekB.page == nil,
                  "promoting Peek B attaches its page while the expanded card is still mounted");
            Check(DPPeekAllCards(window).count == 1 && peekA.hidden && !peekA.closing && peekA.superview == window.contentView,
                  "promoting Peek B leaves parked Peek A untouched");
            [peekA handOverTo:nil attach:nil];
            Check(DPPeekAllCards(window).count == 0 && DPPeekSyncTimer == nil, "handing over the last Peek stops the sync timer");
            [tabHost removeFromSuperview];
            sw.appleScriptTabs = [NSMutableArray arrayWithObjects:[DPTabMock tabWithID:@"pin-1"], [DPTabMock tabWithID:@"C"], nil];
        }

        DPPeekTabWindow *window2 = [[DPPeekTabWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 800, 500)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window2.releasedWhenClosed = NO;
        DPScriptWindowMock *sw2 = [DPScriptWindowMock new];
        sw2.appleScriptTabs = [NSMutableArray arrayWithObjects:[DPTabMock tabWithID:@"X"], [DPTabMock tabWithID:@"Y"], nil];
        sw2.activeID = @"X";
        [gScriptWindows setObject:sw2 forKey:window2];
        MakeHolder(window2, NSMakeRect(0, 0, 800, 500), NULL);

        sw.activeID = @"C";
        ArcWebContents *s1 = [ArcWebContents new], *s2 = [ArcWebContents new], *sX = [ArcWebContents new];
        DPPeekOpenFrom(window, @"C", [NSURL URLWithString:@"https://c.example"], NSMakeRect(100, 100, 80, 20), delegate, s1, nil, nil);
        DPPeekCard *c1 = DPPeekCardIn(window);
        ((ArcWebContents *)c1.page).url = [NSURL URLWithString:@"about:blank"];
        sw.activeID = @"pin-1";
        DPPeekSyncTabs(window);
        DPPeekOpenFrom(window, @"pin-1", [NSURL URLWithString:@"https://p.example"], NSMakeRect(100, 100, 80, 20), delegate, s2, nil, nil);
        DPPeekCard *c2 = DPPeekCardIn(window);
        ((ArcWebContents *)c2.page).url = [NSURL URLWithString:@"about:blank"];
        DPPeekOpenFrom(window2, @"X", [NSURL URLWithString:@"https://x.example"], NSMakeRect(100, 100, 80, 20), delegate, sX, nil, nil);
        DPPeekCard *cX = DPPeekCardIn(window2);
        ((ArcWebContents *)cX.page).url = [NSURL URLWithString:@"about:blank"];
        sw2.activeID = @"Y";
        DPPeekSyncTabs(window2);
        Check(DPPeekAllCards(window).count == 2 && DPPeekAllCards(window2).count == 1 && cX.hidden, "two windows hold visible + hidden cards");

        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:window];
        Check(DPPeekAllCards(window).count == 0 && DPPeekAllCards(window2).count == 1 && !cX.closing,
              "closing window 1 tears down visible+hidden cards in window 1 only");

        DPPeek.on = NO;
        DPPeekCloseAll();
        Check(DPPeekAllCards(nil).count == 0 && DPPeekHiddenCards(nil).count == 0 && DPPeekSyncTimer == nil,
              "DPPeekCloseAll tears down hidden background cards across all windows and stops sync timer");

        [pane2 removeFromSuperview];
        [holder2 addSubview:pane2];
        [sX setVisibility:2];
        [sX closeWithForegroundCommitTiming:0];
        [delegate webContents:sX finalizeDiscardRequest:YES];
        Check(DPPeekSyncTimer == nil && DPPeekAllCards(nil).count == 0, "hooks are complete no-ops when Peek is off");

        DPPeekTabWindow *pinWindow = [[DPPeekTabWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        pinWindow.releasedWhenClosed = NO;
        NSString *pinID = @"22222222-2222-2222-2222-222222222222";
        MakeTabRow(pinWindow.contentView, @"33333333-3333-3333-3333-333333333333", @"none");
        _TtC5TabUI7TabView *pinRow = MakeTabRow(pinWindow.contentView, pinID, @"selected");
        pinRow.pinnedRow = YES;
        DPIdentifiedPage *pinPage = [DPIdentifiedPage new], *strayPage = [DPIdentifiedPage new];
        pinPage.identifier = pinID;
        strayPage.identifier = @"44444444-4444-4444-4444-444444444444";
        NSUInteger tabs = DPFindViews(DPDiaTabView).count + DPFindViews(DPDiaPinnedTab).count;
        gMenuBuilds = gDescriptions = 0;
        BOOL pinned = DPPageInPinnedRow(pinWindow, pinPage) && DPPageInPinnedRow(pinWindow, pinPage) && DPPageInPinnedRow(pinWindow, pinPage);
        Check(pinned && gMenuBuilds == 1, "the hooks asking about one click build Dia's tab menu once");
        gMenuBuilds = gDescriptions = 0;
        Check(DPPageInPinnedRow(pinWindow, strayPage) && gMenuBuilds == 1 && gDescriptions > 0 && (NSUInteger)gDescriptions <= tabs,
              "a page no tab names falls back to the selected tab, describing each tab once");
        pinRow.pinnedRow = NO;
        [NSThread sleepForTimeInterval:0.6];
        Check(!DPPageInPinnedRow(pinWindow, pinPage) && gMenuBuilds == 2, "a remembered answer expires, so unpinning is seen");
        [pinWindow close];

        [window close];
        [window2 close];
        printf("peek-tabs: %d failures\n", failures);
    }
    return failures ? 1 : 0;
}

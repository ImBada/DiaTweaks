#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "StdPatch/StdPatch.h"
#import "watchdog.h"
#import "runloop.h"
#import "StdPatch/Hide.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import "Patches/HideConnectAppPrompts/HideConnectAppPrompts.h"
#import "Patches/TurnOffAI/TurnOffAI.h"
#import "Patches/ProfileColorPicker/ProfileColorPicker.h"
#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/AutoPip.h"
#import "Peek/Peek.h"
#import "Patches/LittleDia/LittleDia.h"
#import "Patches/UnloadTab/Pages.h"
#import "Patches/UnloadTab/Recent.h"
#import "Patches/LaunchFlags/LaunchFlags.h"

#pragma mark - Isolated Defaults & SafeMode Path

static NSString *DPCombSuiteName(void) {
    return [NSString stringWithFormat:@"com.diapatches.combinatorial-test.%d", getpid()];
}

@interface NSUserDefaults (DPCombIsolation)
- (instancetype)dp_combInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPCombIsolation)
- (instancetype)dp_combInitWithSuiteName:(NSString *)suite {
    return [self dp_combInitWithSuiteName:[suite isEqualToString:@"com.diapatches"] ? DPCombSuiteName() : suite];
}
@end

static const char *DPTestDylibPath;
static int DPTestDladdr(const void *address, Dl_info *info) {
    int found = dladdr(address, info);
    if (DPTestDylibPath) info->dli_fname = DPTestDylibPath;
    return found;
}
#define dladdr DPTestDladdr
#import "SafeMode/SafeMode.m"
#undef dladdr

#pragma mark - Minimal Stubs for Unlinked Subsystems

NSString *const DPDia = @"dia", *const DPTweaks = @"tweaks";
NSNotificationName const DPUpdatesDidChangeNotification = @"DPUpdatesDidChange";

void DPSetHint(NSView *view, NSString *text) { DPSet(view, "dp_test_hint", text); }
NSString *DPHintOf(NSView *view) { return DPGet(view, "dp_test_hint"); }
void DPShowHint(NSView *view) {}
void DPHandOffAndQuit(NSArray<NSString *> *args) {}
void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output)) { if (completion) completion(@""); }
NSURL *DPAddressURL(NSString *typed) { return [NSURL URLWithString:typed]; }

void *swift_unknownObjectWeakLoadStrong(void *ref) {
    return ref && *(__unsafe_unretained id *)ref ? (__bridge_retained void *)*(__unsafe_unretained id *)ref : NULL;
}

@implementation DPPreviewView
- (instancetype)initWithKey:(NSString *)key { return [super initWithFrame:NSZeroRect]; }
@end

@implementation DPSoftwareUpdateView
@end

@implementation DPUpdates
+ (instancetype)shared {
    static DPUpdates *shared;
    if (!shared) shared = [DPUpdates new];
    return shared;
}
- (void)check:(void (^)(void))done {}
- (BOOL)available:(NSString *)part { return NO; }
- (BOOL)staged:(NSString *)part { return NO; }
- (BOOL)downloading:(NSString *)part { return NO; }
- (BOOL)failed:(NSString *)part { return NO; }
- (NSString *)failure:(NSString *)part { return nil; }
- (double)progress:(NSString *)part { return 0; }
- (void)download:(NSString *)part then:(void (^)(void))done {}
- (void)installAndRelaunch:(NSArray<NSString *> *)parts {}
- (void)pretend:(NSString *)part {}
- (void)stopPretending {}
@end

// HideToolbar helpers normally in PlainTab.m / LittleDia/Over.m
void DPRepaintTabs(NSWindow *window) {}
BOOL DPLittleDiaIsOver(NSWindow *window) { return NO; }

// GroupTabs command stubs (Menu.m + Tracking.m are real)
void DPGroupTabsOnce(void) {}
void DPGroupSelectedTabsOnce(void) {}
void DPSetAllGroupsCollapsed(BOOL collapsed) {}
void DPUngroupDomain(void) {}
void DPUngroupAllDomains(void) {}
void DPForgetGroupingUndo(void) {}
BOOL DPCanReadSelection(id browser) { return YES; }
void DPInstallGroupTabsShortcut(void) {}
NSDictionary *DPDefaultGroupTabsShortcut(void) { return @{ @"keyCode" : @5, @"modifiers" : @(NSEventModifierFlagCommand | NSEventModifierFlagOption), @"key" : @"G" }; }

// LittleDia runtime stubs (LinkMenu.m + Options.m are real)
DPPatch DPLittleDia = { .key = @"littleDia", .title = @"Little Dia", .detail = @"", .symbol = @"macwindow", .tint = @"systemMintColor", .section = @"Links" };
DPPatch DPLittleDiaTabLinks = { .key = @"littleDiaTabLinks", .title = @"Open Links from Tabs", .detail = @"", .symbol = @"macwindow", .tint = @"systemMintColor", .requires = @"littleDia" };
static NSHashTable<NSWindow *> *gLittleDiaWindows;
static NSMutableArray<NSURL *> *gLittleDiaOpenedLinks;
BOOL DPLittleDiaReady(void) { return YES; }
void DPOpenLinkInLittleDia(NSURL *url) { if (url) [gLittleDiaOpenedLinks addObject:url]; }
BOOL DPIsLittleDiaWindow(NSWindow *window) { return window && [gLittleDiaWindows containsObject:window]; }

// CommandBar spare/swap stubs (CommandBar.m + AutoPip.m + HideTabLayout.m + HideTabParked.m + Tabs.m are real)
static BOOL gHideTabEnabled = YES;
static NSMutableSet<NSString *> *gHiddenTabIDs;
static NSWindow *gHidingTabWindow;
static int gCommandBarExpectCount;
static NSMutableArray<NSString *> *gRowNames;

BOOL DPHiding(void) { return gHideTabEnabled; }
void DPExpectNewTab(NSWindow *window) { gCommandBarExpectCount++; }
void DPStopExpecting(void) {}
void DPHideTabRow(NSString *tabID, NSWindow *window) { if (tabID) [gHiddenTabIDs addObject:tabID]; gHidingTabWindow = window; }
void DPShowTabRow(NSString *tabID, BOOL closing) { if (tabID) [gHiddenTabIDs removeObject:tabID]; if (!gHiddenTabIDs.count) gHidingTabWindow = nil; }
BOOL DPHidesTab(NSString *tabID) { return tabID && [gHiddenTabIDs containsObject:tabID]; }
BOOL DPHidingATab(NSWindow *window) { return gHiddenTabIDs.count > 0 && (!window || gHidingTabWindow == window); }
BOOL DPParkingAny(void) { return NO; }
void DPParkTab(NSString *tabID, BOOL parked) {}
void DPHideBlank(NSString *tabID, BOOL hidden, NSWindow *window) {}
BOOL DPParksTab(NSString *tabID) { return NO; }
BOOL DPOnlyListedTab(NSString *tabID, NSString *closingID, NSWindow *window) { return NO; }
void DPStandInFor(NSWindow *window, NSString *tabID) {}
void DPStandInForTab(NSWindow *window, NSString *tabID) {}
void DPStandInWhileSwitching(NSWindow *window, NSString *tabID, NSString *leaving) {}
NSString *DPVerifyStandIn(NSWindow *window, NSString *tabID) { return nil; }
void DPCleanHideTab(void) { [gHiddenTabIDs removeAllObjects]; gHidingTabWindow = nil; }
BOOL DPInTabLayout(NSView *view) { return NO; }
NSEvent *DPTabLayoutMouseDown(DPCommandBarOverlay *overlay, NSEvent *event) { return event; }
void DPTabLayoutMouseUp(DPCommandBarOverlay *overlay) {}
void DPHandOver(DPCommandBarOverlay *overlay) {}
void DPFinishHandOver(NSWindow *window) {}
DPCommandBarOverlay *DPTakeHandOver(NSWindow *window) { return nil; }
void DPClearCatchUp(NSWindow *window) {}
NSEvent *DPHandToDia(NSWindow *window, NSEvent *event, BOOL newTab) { return nil; }
BOOL DPWaitForDia(NSWindow *window, NSEvent *event, BOOL newTab) { return NO; }
void DPDiaCaughtUp(NSWindow *window) {}
BOOL DPParkSpare(DPCommandBarOverlay *overlay) { return NO; }
void DPParkIfSpare(DPCommandBarOverlay *overlay) {}
BOOL DPShowSpare(NSWindow *window) { return NO; }
void DPDropSpare(NSWindow *window) {}
void DPForgetSpare(NSWindow *window) {}
void DPUpdateSpareTimer(void) {}
DPCommandBarOverlay *DPSpareIn(NSWindow *window) { return nil; }
void DPNoteSpare(NSString *tabID, BOOL parked) {}
void DPNoteOpenTab(NSString *tabID, BOOL open) {}
BOOL DPAdoptSpare(NSWindow *window, NSView *page) { return NO; }
void DPNotMakingSpare(void) {}
NSView *DPCommandBarPart(NSView *commandBar, const char *className) { return nil; }
NSView *DPGoButton(NSView *toolbar) { return nil; }
NSString *DPRowName(NSCollectionView *list, NSIndexPath *path) {
    NSInteger idx = path.section == 0 ? path.item : 3 + path.item;
    return idx >= 0 && idx < (NSInteger)gRowNames.count ? gRowNames[idx] : nil;
}
NSString *DPTabIn(NSString *rowName) {
    if (![rowName hasPrefix:@".tab("] || ![rowName hasSuffix:@")"]) return nil;
    return [rowName substringWithRange:NSMakeRange(5, rowName.length - 6)];
}
void DPInstallParkedRows(void) {}
CGFloat DPClosedUp(NSCollectionViewLayout *layout, NSRect frame) { return 0; }
CGFloat DPParkedHeight(NSCollectionViewLayout *layout) { return 0; }
BOOL DPIsLeftOutRow(NSCollectionView *list, NSIndexPath *path) { return NO; }
NSCollectionViewLayoutAttributes *DPClosedAttributes(NSCollectionViewLayout *layout, NSCollectionViewLayoutAttributes *attributes) { return attributes; }

// Peek UI helper stubs (Peek.m + Keys.m + Chat.m + ChatContext.m + Card.m + Pages.m + Visibility.m + Motion.m + Selection.m + Tab.m + Zoom.m are real)
const CGFloat DPPeekToolbarHeight = 36;
static int gPeekEditAddressCalls;
NSView *DPPeekControls(id target, SEL action) { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 36, 120)]; }
void DPPeekResetControlHints(NSView *controls) {}
NSView *DPPeekToolbarFor(id page) { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 36)]; }
void DPPeekAddToolbar(DPPeekCard *peek) {
    if (!peek.toolbar) {
        peek.toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 36)];
        [peek.card addSubview:peek.toolbar];
    }
}
CGFloat DPPeekToolbarInset(DPPeekCard *peek) { return peek.toolbar ? DPPeekToolbarHeight : 0; }
void DPPeekPlaceToolbar(DPPeekCard *peek) {}
void DPPeekNavigate(id page, DPPeekStep step) {}
NSView *DPPeekToolbarAddress(NSView *toolbar) { return nil; }
NSView *DPPeekAddressFor(id page) { return nil; }
NSView *DPPeekGlowFor(id page) { return nil; }
void DPPeekRefreshAddress(NSView *address) {}
void DPPeekEditAddress(NSView *address) {}
BOOL DPPeekEditingAddress(NSView *address) { return NO; }
void DPPeekEditToolbarAddress(DPPeekCard *peek) { gPeekEditAddressCalls++; }
BOOL DPPeekCopyURL(DPPeekCard *peek, NSEvent *event) { return NO; }
BOOL DPPeekIsShortcut(NSEvent *event, NSMenuItem *item) { return NO; }
BOOL DPPeekFindShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods) { return NO; }
BOOL DPPeekHideFind(DPPeekCard *peek) { return NO; }
void DPPeekInstallCursor(void) {}
void DPPeekLayoutHints(NSView *controls, CGFloat availableRight) {}
void DPPeekHideDragZone(void) {}
CATransform3D DPPeekScaled(NSView *view, CGFloat scale) { return CATransform3DMakeScale(scale, scale, 1); }
NSString *DPDomainKey(NSString *address) { return address ? [NSURL URLWithString:address].host.lowercaseString : nil; }
NSString *DPRegistrableDomain(NSString *host) { return host; }
double DPPeekDarkness(void) { return 0.35; }
double DPPeekResponse(void) { return 0.3; }
BOOL DPSamplesProgressColors;
BOOL DPPeekGenie(void) { return NO; }
BOOL DPPeekShowsToolbar(void) { return YES; }
NSArray<NSView *> *DPPeekSettingsRows(void) { return @[]; }
DPPatch DPPeekPinnedLinks = { .key = @"peekPinnedLinks", .title = @"Peek Pinned Links", .detail = @"", .symbol = @"eye", .tint = @"systemMintColor", .requires = @"peek" };

#pragma mark - Global Test Harness State & Helpers

static int gFailures;
static NSArray<NSWindow *> *gMockWindows;
static NSWindow *gMockKeyWindow;
static NSArray<NSString *> *gLastConfigArgv;
static int gLastConfigArgc;
static int gPopupCalls, gPipRequests;
static NSMutableArray<NSEvent * (^)(NSEvent *)> *gKeyMonitors;

static const NSPoint DPCombOffscreenPointer = {-100000, -100000};
static NSPoint DPEvent_mouseLocation(id self, SEL _cmd) { return DPCombOffscreenPointer; }
static NSUInteger DPEvent_pressedMouseButtons(id self, SEL _cmd) { return 0; }

static id DPEvent_addLocalMonitor(id self, SEL _cmd, NSEventMask mask, NSEvent * (^handler)(NSEvent *)) {
    id token = DPCallOriginal(DPEvent_addLocalMonitor, self, mask, handler);
    if ((mask & NSEventMaskKeyDown) && handler) {
        if (!gKeyMonitors) gKeyMonitors = [NSMutableArray array];
        id copied = [handler copy];
        [gKeyMonitors addObject:copied];
        DPSet(token, "dp_comb_monitor_handler", copied);
    }
    return token;
}

static void DPEvent_removeMonitor(id self, SEL _cmd, id token) {
    id handler = token ? DPGet(token, "dp_comb_monitor_handler") : nil;
    if (handler) [gKeyMonitors removeObjectIdenticalTo:handler];
    DPCallOriginal(DPEvent_removeMonitor, self, token);
}

static NSEvent *DispatchToKeyMonitors(NSEvent *event, BOOL reverse) {
    NSArray *list = [gKeyMonitors copy];
    NSEvent *cur = event;
    if (reverse) {
        for (NSUInteger i = list.count; i-- > 0 && cur;) cur = ((NSEvent * (^)(NSEvent *))list[i])(cur);
    } else {
        for (NSEvent * (^h)(NSEvent *) in list) {
            cur = h(cur);
            if (!cur) break;
        }
    }
    return cur;
}

static void Check(BOOL ok, NSString *msg) {
    if (ok) return;
    gFailures++;
    printf("FAIL: %s\n", msg.UTF8String);
}

static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gMockWindows ?: @[]; }
static NSArray<NSWindow *> *DPApp_orderedWindows(NSApplication *self, SEL _cmd) { return gMockWindows ?: @[]; }
static NSWindow *DPApp_keyWindow(NSApplication *self, SEL _cmd) { return gMockKeyWindow; }

static void DPNoOpPopUpContext(id self, SEL _cmd, NSMenu *menu, NSEvent *event, NSView *view) { gPopupCalls++; }
static BOOL DPNoOpPopUpAt(NSMenu *self, SEL _cmd, NSMenuItem *item, NSPoint location, NSView *view) { gPopupCalls++; return YES; }

static NSEvent *MakeKeyEvent(NSWindow *window, NSString *ch, unsigned short code, NSEventModifierFlags mods) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:1
                        windowNumber:window.windowNumber context:nil characters:ch charactersIgnoringModifiers:ch
                           isARepeat:NO keyCode:code];
}

static NSEvent *MakeRightClick(NSWindow *window) {
    return [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSMakePoint(10, 10) modifierFlags:0 timestamp:1
                          windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

#pragma mark - Realistic Mock Dia Runtime Hierarchy (registered via StdPatch/Dia.h macros)

@interface DPCombContextID : NSObject
@property (nonatomic) BOOL incognito;
@property (nonatomic, copy) NSString *directoryBasename;
- (BOOL)isIncognito;
@end
@implementation DPCombContextID
- (BOOL)isIncognito { return self.incognito; }
@end

@interface DPCombContext : NSObject
@property (nonatomic, strong) DPCombContextID *id;
@end
@implementation DPCombContext
@end

@interface DPCombWindowDelegate : NSObject
@property (nonatomic, copy) NSString *committedFocusedSpaceID;
@property (nonatomic, copy) NSString *initialFocusedSpaceID;
@end
@implementation DPCombWindowDelegate
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"committedFocusedSpaceID"]) return self.committedFocusedSpaceID;
    if ([key isEqualToString:@"initialFocusedSpaceID"]) return self.initialFocusedSpaceID;
    return nil;
}
@end

@interface DPCombWindowVM : NSObject
@property (nonatomic, strong) DPCombWindowDelegate *delegate;
@end
@implementation DPCombWindowVM
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"delegate"] ? self.delegate : nil; }
@end

@interface DPCombBaseWindow : NSWindow
@property (nonatomic) CGFloat fakeCornerRadius;
@property (nonatomic) BOOL fakeVisible, fakeKey, closeCalled;
@property (nonatomic, strong) NSWindow *fakeSheet;
@property (nonatomic, strong) NSView *mockContentView;
@property (nonatomic, strong) DPCombWindowVM *viewModel;
@property (nonatomic, strong) NSButton *fakeCloseButton;
@property (nonatomic, weak) NSResponder *mockFirstResponder;
@end
@implementation DPCombBaseWindow
- (NSView *)contentView { return self.mockContentView ?: [super contentView]; }
- (CGFloat)_cornerRadius { return self.fakeCornerRadius; }
- (void)_setCornerRadius:(CGFloat)r { self.fakeCornerRadius = r; }
- (void)_updateWindowCornerMask {}
- (BOOL)isVisible { return self.fakeVisible; }
- (BOOL)isKeyWindow { return self.fakeKey; }
- (NSWindow *)attachedSheet { return self.fakeSheet; }
- (NSButton *)standardWindowButton:(NSWindowButton)b { return b == NSWindowCloseButton ? self.fakeCloseButton : [super standardWindowButton:b]; }
- (NSResponder *)firstResponder { return self.mockFirstResponder ?: [super firstResponder]; }
- (NSPoint)mouseLocationOutsideOfEventStream { return DPCombOffscreenPointer; }
- (BOOL)makeFirstResponder:(NSResponder *)responder { self.mockFirstResponder = responder; return YES; }
- (void)performClose:(id)sender { self.closeCalled = YES; }
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"viewModel"] ? self.viewModel : nil; }
@end

@interface DPCombFlippedView : NSView
@end
@implementation DPCombFlippedView
- (BOOL)isFlipped { return YES; }
@end

typedef struct {
    void *tintColorOverride;
    void *topTintColorOverride;
    double gradientAlpha;
    double themeIntensity;
    uint8_t pad[40];
} DPCombTintStorage;

@interface DPCombTintView : NSView {
@public
    DPCombTintStorage tint;
}
@end
@implementation DPCombTintView
- (void)updateLayer {}
@end

@interface DPCombGradientView : NSView
@property (nonatomic, strong) NSArray *diaColors;
@end
@implementation DPCombGradientView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        CAGradientLayer *grad = [CAGradientLayer layer];
        grad.frame = self.bounds;
        [self.layer addSublayer:grad];
    }
    return self;
}
- (void)updateLayer {
    for (CALayer *sub in self.layer.sublayers)
        if ([sub isKindOfClass:CAGradientLayer.class] && self.diaColors) ((CAGradientLayer *)sub).colors = self.diaColors;
}
@end

static int gHoverUpdateCount;
static BOOL gHoverLastValue;
static void DPCombHoverCallback(bool hovered, void *context __attribute__((swift_context))) __attribute__((swiftcall)) {
    gHoverUpdateCount++;
    gHoverLastValue = hovered;
}

@interface DPCombHoverTracker : NSObject {
@public
    __weak NSView *view;
    BOOL isHovered;
}
@end
@implementation DPCombHoverTracker
- (void)mouseEntered:(NSEvent *)event { isHovered = YES; }
- (void)mouseMoved:(NSEvent *)event {}
- (void)mouseExited:(NSEvent *)event { isHovered = NO; }
@end

@interface DPCombDelayedHover : NSObject {
@public
    BOOL isHoverActive;
    BOOL isIncidentalHover;
    void *onUpdate[2];
}
@end
@implementation DPCombDelayedHover
@end

@interface DPCombAddressField : NSView {
@public
    void *hoverTracker;
}
@property (nonatomic, strong) DPCombDelayedHover *ownedDelayed;
@property (nonatomic, strong) DPCombHoverTracker *ownedTracker;
@end
@implementation DPCombAddressField
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _ownedDelayed = [DPCombDelayedHover new];
        _ownedDelayed->onUpdate[0] = (void *)DPCombHoverCallback;
        _ownedDelayed->onUpdate[1] = NULL;
        hoverTracker = (__bridge void *)_ownedDelayed;
        Class trackerCls = objc_getClass(DPDiaHoverTracker);
        _ownedTracker = [trackerCls new];
        _ownedTracker->view = self;
        NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
            options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:_ownedTracker userInfo:nil];
        [self addTrackingArea:area];
    }
    return self;
}
@end

@interface DPCombSidebarHeader : DPCombFlippedView
@property (nonatomic, strong) NSStackView *rowStack;
@property (nonatomic) NSRect diaStackFrame;
@end
@implementation DPCombSidebarHeader
- (void)layout {
    [super layout];
    if (self.rowStack && !NSIsEmptyRect(self.diaStackFrame)) self.rowStack.frame = self.diaStackFrame;
}
@end

@interface DPCombSidebarController : NSViewController
@property (nonatomic, strong) NSView *headerView, *bodyView;
@end
@implementation DPCombSidebarController
- (void)viewWillLayout {
    [super viewWillLayout];
    if (self.headerView) self.headerView.frame = NSMakeRect(0, 0, 220, 44);
    if (self.bodyView) self.bodyView.frame = NSMakeRect(0, 44, 220, 500);
}
- (void)viewDidLayout { [super viewDidLayout]; }
@end

@interface DPCombBrowser : NSObject
@property (nonatomic, strong) DPCombContext *context;
@property (nonatomic, weak) id delegate;
@property (nonatomic, weak) NSWindow *window;
@end
@implementation DPCombBrowser
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (void)setWindow:(NSWindow *)window { _window = window; }
- (id)createWebContents:(id)config { return [objc_getClass(DPDiaWebContents) new]; }
- (void)takeOwnershipOfWebContents:(id)contents {}
@end

@interface DPCombBrowserDelegate : NSObject
@end
@implementation DPCombBrowserDelegate
- (void)browser:(id)b didRestoreWebContents:(id)c withSessionId:(id)s {}
- (void)browser:(id)b didCreateNewWebContents:(id)c isActive:(BOOL)a {}
@end

@interface DPCombWebContents : NSObject <DPPeekPage>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSView *nativeView;
@property (nonatomic) NSInteger visibilityValue;
@property (nonatomic) float zoomFactorValue;
@property (nonatomic) BOOL discarded;
@property (nonatomic) long long sessionId;
@property (nonatomic) NSInteger discardCalls;
@end
@implementation DPCombWebContents
- (instancetype)init {
    if ((self = [super init])) _zoomFactorValue = 1.0f;
    return self;
}
- (NSInteger)visibility { return self.visibilityValue; }
- (void)setVisibility:(NSInteger)v { self.visibilityValue = v; }
- (float)zoomFactor { return self.zoomFactorValue; }
- (void)setZoomFactor:(float)z { self.zoomFactorValue = z; }
- (void)resetZoomAndScaleFactors { self.zoomFactorValue = 1.0f; }
- (void)discard { self.discardCalls++; self.discarded = YES; }
- (id)clone { return [self.class new]; }
- (NSView *)createPaneHostView { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)]; }
- (void)attachToPaneHostView:(NSView *)host {}
- (void)detachFromPaneHostView:(NSView *)host {}
- (void)close {}
- (id)navigationController { return self; }
- (id)load:(NSURL *)url initiatorOrigin:(NSURL *)origin { self.url = url; return nil; }
@end

@interface DPCombWebContentChromium : NSObject
@property (nonatomic) NSInteger lastDisposition;
@property (nonatomic) NSInteger decideCalls;
@end
@implementation DPCombWebContentChromium
- (void)webContents:(id)wc didCreateNewWebContent:(id)nw targetURL:(NSURL *)url disposition:(NSInteger)d { self.lastDisposition = d; }
- (NSInteger)webContents:(id)wc decidePolicyForNavigationAction:(id)action { self.decideCalls++; return DPForegroundTab; }
- (void)webContents:(id)wc didChangeStatusText:(NSString *)text {}
- (BOOL)webContents:(id)wc willShowContextMenu:(id)menu withElement:(id)element { return YES; }
- (void)webContents:(id)wc finalizeDiscardRequest:(BOOL)discarded {}
- (void)webContents:(id)wc didCloseWithSessionID:(id)sid {}
@end

@interface DPCombWindowController : NSWindowController
@end
@implementation DPCombWindowController
- (void)zoomIn:(id)s {}
- (void)zoomInAlternate:(id)s {}
- (void)zoomOut:(id)s {}
- (void)resetZoom:(id)s {}
- (BOOL)validateMenuItem:(NSMenuItem *)item { return YES; }
@end

@interface DPCombAppConfig : NSObject
- (id)init:(int)argc argv:(NSArray<NSString *> *)argv profilePath:(NSString *)profilePath applicationID:(NSUInteger)applicationID
         isProduction:(BOOL)isProduction sessionRestorationPolicy:(NSUInteger)restorationPolicy shouldLoadAllProfilesAtStartup:(BOOL)loadAllProfiles
         quitRunLoopOnTermination:(BOOL)quitRunLoop userDefaultsSuiteName:(NSString *)suiteName;
@end
@implementation DPCombAppConfig
- (id)init:(int)argc argv:(NSArray<NSString *> *)argv profilePath:(NSString *)profilePath applicationID:(NSUInteger)applicationID
         isProduction:(BOOL)isProduction sessionRestorationPolicy:(NSUInteger)restorationPolicy shouldLoadAllProfilesAtStartup:(BOOL)loadAllProfiles
         quitRunLoopOnTermination:(BOOL)quitRunLoop userDefaultsSuiteName:(NSString *)suiteName {
    gLastConfigArgc = argc;
    gLastConfigArgv = argv;
    return [super init];
}
@end

@interface DPCombTabView : NSView
@property (nonatomic, strong) NSMenu *reusedMenu;
@property (nonatomic) BOOL returnNilMenu;
@property (nonatomic, strong) NSDictionary *contentViews;
@end
@implementation DPCombTabView
- (NSMenu *)menuForEvent:(NSEvent *)event { return self.returnNilMenu ? nil : self.reusedMenu; }
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"contentViews"] ? self.contentViews : nil; }
@end

@interface DPCombTabContentController : NSObject
@property (nonatomic, copy) NSString *tabID, *contentID;
@property (nonatomic, strong) NSURL *webContentURL;
@end
@implementation DPCombTabContentController
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"tabID"]) return self.tabID;
    if ([key isEqualToString:@"contentID"]) return self.contentID;
    if ([key isEqualToString:@"webContentURL"]) return self.webContentURL;
    return nil;
}
@end

@interface DPCombTabContentVM : NSObject
@property (nonatomic, strong) DPCombTabContentController *delegate;
@end
@implementation DPCombTabContentVM
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"delegate"] ? self.delegate : nil; }
@end

@interface DPCombTabContentView : NSView
@property (nonatomic, strong) DPCombTabContentVM *viewModel;
@end
@implementation DPCombTabContentView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"viewModel"] ? self.viewModel : nil; }
@end

@interface DPCombContentPane : DPCombFlippedView
@property (nonatomic, copy) NSString *contentPaneID;
@end
@implementation DPCombContentPane
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"contentPaneID"] ? self.contentPaneID : nil; }
@end

@interface DPCombTabListLayout : NSCollectionViewLayout
@property (nonatomic) NSInteger pinnedCount, regularCount;
@property (nonatomic) CGFloat rowHeight;
@end
@implementation DPCombTabListLayout
- (instancetype)init {
    if ((self = [super init])) { _pinnedCount = 2; _regularCount = 2; _rowHeight = 37; }
    return self;
}
- (NSSize)collectionViewContentSize { return NSMakeSize(220, (_pinnedCount + _regularCount) * _rowHeight + 1); }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    NSCollectionViewLayoutAttributes *a = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:path];
    if (path.section == 0) {
        if (path.item < _pinnedCount) a.frame = NSMakeRect(0, path.item * _rowHeight, 220, _rowHeight);
        else a.frame = NSMakeRect(0, _pinnedCount * _rowHeight, 220, 1);
    } else {
        a.frame = NSMakeRect(0, _pinnedCount * _rowHeight + 1 + path.item * _rowHeight, 220, _rowHeight);
    }
    return a;
}
- (NSArray<NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect {
    NSMutableArray *all = [NSMutableArray array];
    for (NSInteger i = 0; i <= _pinnedCount; i++) {
        NSCollectionViewLayoutAttributes *a = [self layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
        if (NSIntersectsRect(a.frame, rect)) [all addObject:a];
    }
    for (NSInteger i = 0; i < _regularCount; i++) {
        NSCollectionViewLayoutAttributes *a = [self layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:1]];
        if (NSIntersectsRect(a.frame, rect)) [all addObject:a];
    }
    return all;
}
@end

@interface DPCombCollectionView : NSCollectionView
@property (nonatomic) NSInteger pinnedCount, regularCount;
@end
@implementation DPCombCollectionView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { _pinnedCount = 2; _regularCount = 2; }
    return self;
}
- (NSInteger)numberOfSections { return 2; }
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return section == 0 ? self.pinnedCount + 1 : self.regularCount; }
@end

@interface DPCombTabListDelegate : NSObject
@property (nonatomic, copy) NSString *spaceID;
@end
@implementation DPCombTabListDelegate
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"spaceID"] ? self.spaceID : nil; }
@end

@interface DPCombTabListVM : NSObject
@property (nonatomic, strong) DPCombTabListDelegate *delegate;
@end
@implementation DPCombTabListVM
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"delegate"] ? self.delegate : nil; }
@end

@interface DPCombTabListView : DPCombFlippedView
@property (nonatomic, strong) DPCombTabListVM *viewModel;
@property (nonatomic) NSInteger diaDoubleClicks;
@end
@implementation DPCombTabListView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqualToString:@"viewModel"] ? self.viewModel : nil; }
- (void)handleBackgroundDoubleClick:(id)gesture { self.diaDoubleClicks++; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (void)draggingExited:(id<NSDraggingInfo>)info {}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info { return YES; }
@end

@interface DPCombGesture : NSObject
@property (nonatomic) NSPoint point;
- (NSPoint)locationInView:(NSView *)view;
@end
@implementation DPCombGesture
- (NSPoint)locationInView:(NSView *)view { return self.point; }
@end

@interface DPCombMediaSession : NSObject
@end
@implementation DPCombMediaSession
- (BOOL)requestPictureInPicture:(NSError **)error { gPipRequests++; return YES; }
- (BOOL)exitPictureInPicture:(BOOL)flag error:(NSError **)error { return YES; }
@end

@interface DPCombThemePicker : NSView
@end
@implementation DPCombThemePicker
- (void)themeClicked:(id)sender {}
@end

@interface DPCombLinkElement : NSObject
@property (nonatomic, strong) NSURL *linkURL;
@end
@implementation DPCombLinkElement
@end

@interface DPCombDialogPanel : NSView
@property (nonatomic) NSInteger declineClicks;
@end
@implementation DPCombDialogPanel
- (void)handleButton:(id)sender {
    if ([sender isKindOfClass:NSControl.class] && ((NSControl *)sender).tag == 1) self.declineClicks++;
}
@end

@interface DPCombDialogVC : NSViewController
@property (nonatomic, strong) DPCombDialogPanel *panel;
@end
@implementation DPCombDialogVC
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)]; }
- (void)viewDidLoad { [super viewDidLoad]; if (self.panel) [self.view addSubview:self.panel]; }
@end

@interface DPCombSettingsSidebarDelegate : NSObject <NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, copy) NSArray<NSString *> *titles;
@end
@implementation DPCombSettingsSidebarDelegate
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)self.titles.count; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
    NSTextField *tf = [NSTextField labelWithString:self.titles[row]];
    return tf;
}
- (CGFloat)tableView:(NSTableView *)t heightOfRow:(NSInteger)row { return 24; }
@end

@interface DPCombProfilePane : NSViewController
@end
@implementation DPCombProfilePane
- (void)viewDidLoad { [super viewDidLoad]; }
- (void)viewWillDisappear { [super viewWillDisappear]; }
@end

@interface DPCombSidebarLayoutCoord : NSObject
@end
@implementation DPCombSidebarLayoutCoord
- (void)containerViewResized:(NSNotification *)note {}
@end

@interface DPCombPageExtraction : NSObject
@end
@implementation DPCombPageExtraction
- (void)getExtractedContentForWebContents:(id)wc completion:(void (^)(NSDictionary *))c { if (c) c(@{}); }
@end

static Class RegisterMockClass(Class superCls, const char *name) {
    Class existing = objc_getClass(name);
    if (existing) return existing;
    Class cls = objc_allocateClassPair(superCls, name, 0);
    NSCAssert(cls != Nil, @"failed to allocate %s", name);
    objc_registerClassPair(cls);
    return cls;
}

static void RegisterAllMockDiaClasses(void) {
    RegisterMockClass(DPCombBaseWindow.class, DPDiaWindow);
    RegisterMockClass(NSView.class, DPDiaWindowFrame);
    RegisterMockClass(DPCombTintView.class, DPDiaWindowTint);
    RegisterMockClass(DPCombGradientView.class, DPDiaGradientView);
    RegisterMockClass(NSView.class, DPDiaColorView);
    RegisterMockClass(NSView.class, DPDiaFloatingSidebar);
    RegisterMockClass(NSView.class, DPDiaWindowBackground);
    RegisterMockClass(NSView.class, DPDiaWindowBackgroundTile);
    RegisterMockClass(DPCombFlippedView.class, DPDiaContentContainer);
    RegisterMockClass(DPCombContentPane.class, DPDiaContentPane);
    RegisterMockClass(NSView.class, DPDiaToolbar);
    RegisterMockClass(NSView.class, DPDiaBookmarksBar);
    RegisterMockClass(DPCombAddressField.class, DPDiaAddressField);
    RegisterMockClass(DPCombHoverTracker.class, DPDiaHoverTracker);
    RegisterMockClass(DPCombSidebarHeader.class, DPDiaSidebarHeader);
    RegisterMockClass(NSView.class, DPDiaSidebarFooter);
    RegisterMockClass(DPCombSidebarController.class, DPDiaSidebarController);
    RegisterMockClass(NSViewController.class, DPDiaTabStripController);
    RegisterMockClass(NSView.class, DPDiaTabStrip);
    RegisterMockClass(NSView.class, DPDiaTabStripTabs);
    RegisterMockClass(NSView.class, DPDiaTrafficLights);
    RegisterMockClass(NSButton.class, DPDiaCapsuleButton);
    RegisterMockClass(NSView.class, DPDiaLibraryButton);
    RegisterMockClass(NSView.class, DPDiaLibraryCell);
    RegisterMockClass(NSView.class, DPDiaSkillsSuggestions);
    RegisterMockClass(NSView.class, DPDiaPersonalizeButton);
    RegisterMockClass(NSView.class, DPDiaChatUsage);
    RegisterMockClass(NSView.class, DPDiaCapabilityButton);
    RegisterMockClass(NSView.class, DPDiaNewTabButton);
    RegisterMockClass(NSView.class, DPDiaTabSurfaceButton);
    RegisterMockClass(NSView.class, DPDiaNewTabPage);
    RegisterMockClass(NSView.class, DPDiaAssistantPanel);
    RegisterMockClass(NSView.class, DPDiaChatHeader);
    RegisterMockClass(NSView.class, DPDiaPopover);
    RegisterMockClass(NSView.class, DPDiaCommandBar);
    RegisterMockClass(NSView.class, DPDiaCommandBarInput);
    RegisterMockClass(NSView.class, DPDiaCommandBarText);
    RegisterMockClass(NSView.class, DPDiaCommandBarSuggestions);
    RegisterMockClass(NSView.class, DPDiaCommandBarToolbar);
    RegisterMockClass(NSView.class, DPDiaCommandBarButton);
    RegisterMockClass(NSView.class, DPDiaShadowView);
    RegisterMockClass(NSView.class, DPDiaPinnedExtension);
    RegisterMockClass(NSView.class, DPDiaPinnedTabOutline);
    RegisterMockClass(NSView.class, DPDiaTabGroupBackground);
    RegisterMockClass(NSView.class, DPDiaTabGroupView);
    RegisterMockClass(NSView.class, DPDiaTabGroupCell);
    RegisterMockClass(NSView.class, DPDiaTabBackground);
    RegisterMockClass(NSView.class, DPDiaTabShape);
    RegisterMockClass(NSView.class, DPDiaRenderWidget);
    RegisterMockClass(NSView.class, DPDiaSettingsHeader);
    RegisterMockClass(NSView.class, DPDiaSettingsFormGroup);
    RegisterMockClass(DPCombThemePicker.class, DPDiaThemePicker);
    RegisterMockClass(DPCombProfilePane.class, DPDiaProfilePane);
    RegisterMockClass(NSView.class, DPDiaSpaceSwitcher);
    RegisterMockClass(NSView.class, DPDiaSpaceSwitcherItem);
    RegisterMockClass(NSView.class, DPDiaPageIndicatorDot);
    RegisterMockClass(DPCombTabView.class, DPDiaTabView);
    RegisterMockClass(DPCombTabView.class, DPDiaPinnedTab);
    RegisterMockClass(DPCombTabContentView.class, DPDiaTabContentView);
    RegisterMockClass(DPCombTabListView.class, DPDiaTabList);
    RegisterMockClass(DPCombCollectionView.class, DPDiaTabListCollection);
    RegisterMockClass(DPCombTabListLayout.class, DPDiaTabListLayout);
    RegisterMockClass(DPCombBrowser.class, DPDiaBrowser);
    RegisterMockClass(DPCombBrowser.class, DPDiaBrowserContext);
    RegisterMockClass(DPCombBrowserDelegate.class, DPDiaBrowserDelegate);
    RegisterMockClass(DPCombWebContents.class, DPDiaWebContents);
    RegisterMockClass(NSObject.class, DPDiaWebContentsConfiguration);
    RegisterMockClass(DPCombWebContentChromium.class, DPDiaWebContent);
    RegisterMockClass(DPCombWindowController.class, "_TtC6Window24PlatformWindowController");
    RegisterMockClass(DPCombAppConfig.class, DPDiaAppConfiguration);
    RegisterMockClass(DPCombMediaSession.class, DPDiaMediaSession);
    RegisterMockClass(DPCombDialogPanel.class, DPDiaDialogPanel);
    RegisterMockClass(DPCombDialogVC.class, DPDiaDialogPanelVC);
    RegisterMockClass(NSWindowController.class, DPDiaDialogPanelWC);
    RegisterMockClass(NSButton.class, DPDiaDialogButton);
    RegisterMockClass(NSView.class, "_TtC9AppUpsell26RebrandedUpsellContentView");
    RegisterMockClass(DPCombSettingsSidebarDelegate.class, DPDiaSettingsSidebar);
    RegisterMockClass(NSViewController.class, DPDiaAssistantSidebar);
    RegisterMockClass(DPCombSidebarLayoutCoord.class, DPDiaAssistantSidebarLayout);
    RegisterMockClass(DPCombPageExtraction.class, DPDiaPageContentExtraction);
    RegisterMockClass(NSView.class, DPDiaWebsitePermissionPopover);
    RegisterMockClass(NSView.class, DPDiaSplitPane);
}

#pragma mark - Synthetic Multi-Hook Chain Verification Classes

@interface DPChainBase : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *trace;
- (void)ping;
@end
@implementation DPChainBase
- (void)ping { [self.trace addObject:@"orig"]; }
@end

@interface DPChainSub : DPChainBase
@end
@implementation DPChainSub
@end

static void DPChainHookA(DPChainBase *self, SEL _cmd) {
    [self.trace addObject:@"A-in"];
    DPCallOriginal(DPChainHookA, self);
    [self.trace addObject:@"A-out"];
}
static void DPChainHookB(DPChainBase *self, SEL _cmd) {
    [self.trace addObject:@"B-in"];
    DPCallOriginal(DPChainHookB, self);
    [self.trace addObject:@"B-out"];
}
static void DPChainHookC(DPChainBase *self, SEL _cmd) {
    [self.trace addObject:@"C-in"];
    DPCallOriginal(DPChainHookC, self);
    [self.trace addObject:@"C-out"];
}
static void DPChainUnhooked(DPChainBase *self, SEL _cmd) {}
static void DPChainClobber(DPChainBase *self, SEL _cmd) { [self.trace addObject:@"clobber"]; }

#pragma mark - Helper Builders for Mock Dia Windows

@interface DPMockWindowBundle : NSObject
@property (nonatomic, strong) DPCombBaseWindow *window;
@property (nonatomic, strong) NSView *themeFrame;
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) DPCombTintView *tintView;
@property (nonatomic, strong) NSView *washView;
@property (nonatomic, strong) DPCombGradientView *gradientView;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) NSView *floatingSidebar;
@property (nonatomic, strong) NSVisualEffectView *floatingEffect;
@property (nonatomic, strong) DPCombTintView *floatingTint;
@property (nonatomic, strong) NSView *floatingWash;
@property (nonatomic, strong) DPCombFlippedView *container;
@property (nonatomic, strong) DPCombContentPane *pane;
@property (nonatomic, strong) NSView *toolbar;
@property (nonatomic, strong) NSView *bookmarksBar;
@property (nonatomic, strong) DPCombAddressField *addressField;
@property (nonatomic, strong) NSButton *chatButton;
@property (nonatomic, strong) NSView *pageHost;
@property (nonatomic, strong) DPCombSidebarController *sidebarController;
@property (nonatomic, strong) DPCombSidebarHeader *sidebarHeader;
@property (nonatomic, strong) NSStackView *headerStack;
@property (nonatomic, strong) NSView *trafficLights;
@property (nonatomic, strong) NSView *sidebarBody;
@property (nonatomic, strong) NSView *sidebarFooter;
@property (nonatomic, strong) DPCombBrowser *browser;
@end
@implementation DPMockWindowBundle
@end

static DPMockWindowBundle *BuildMockWindow(BOOL incognito, BOOL visible, NSString *spaceID, NSArray *diaGradColors) {
    DPMockWindowBundle *b = [DPMockWindowBundle new];
    DPCombBaseWindow *win = [[objc_getClass(DPDiaWindow) alloc] initWithContentRect:NSMakeRect(0, 0, 960, 640)
                                                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                                            backing:NSBackingStoreBuffered defer:NO];
    win.releasedWhenClosed = NO;
    win.fakeCornerRadius = 10;
    win.fakeVisible = visible;
    win.fakeKey = visible && !incognito;
    win.opaque = YES;
    win.backgroundColor = NSColor.windowBackgroundColor;

    DPCombWindowDelegate *wdel = [DPCombWindowDelegate new];
    wdel.committedFocusedSpaceID = spaceID;
    DPCombWindowVM *wvm = [DPCombWindowVM new];
    wvm.delegate = wdel;
    win.viewModel = wvm;

    DPCombContextID *cid = [DPCombContextID new];
    cid.incognito = incognito;
    cid.directoryBasename = incognito ? @"Incognito" : @"Default";
    DPCombContext *ctx = [DPCombContext new];
    ctx.id = cid;
    DPCombBrowser *browser = [objc_getClass(DPDiaBrowser) new];
    browser.context = ctx;
    [browser setWindow:win];

    // Theme frame -> contentView -> tint -> (wash, gradient), hosted inside real NSWindow contentView so .window is valid.
    NSView *themeFrame = [[objc_getClass(DPDiaWindowFrame) alloc] initWithFrame:NSMakeRect(0, 0, 960, 640)];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 640)];
    content.wantsLayer = YES;
    content.layer.cornerRadius = 10;
    [themeFrame addSubview:content];
    [win.contentView addSubview:themeFrame];
    win.mockContentView = content;
    DPSet(win, "dp_comb_theme_frame", themeFrame);
    DPSet(win, "dp_comb_browser", browser);

    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:content.bounds];
    effect.material = NSVisualEffectMaterialUnderWindowBackground;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateFollowsWindowActiveState;
    [content addSubview:effect];

    DPCombTintView *tint = [[objc_getClass(DPDiaWindowTint) alloc] initWithFrame:content.bounds];
    tint->tint.themeIntensity = 0.7;
    NSView *wash = [[objc_getClass(DPDiaColorView) alloc] initWithFrame:tint.bounds];
    DPCombGradientView *gradient = [[objc_getClass(DPDiaGradientView) alloc] initWithFrame:tint.bounds];
    gradient.diaColors = diaGradColors;
    CAGradientLayer *gradLayer = (CAGradientLayer *)gradient.layer.sublayers.firstObject;
    gradLayer.colors = diaGradColors;
    [tint addSubview:wash];
    [tint addSubview:gradient];
    [content addSubview:tint];

    NSView *floating = [[objc_getClass(DPDiaFloatingSidebar) alloc] initWithFrame:NSMakeRect(8, 8, 220, 624)];
    floating.wantsLayer = YES;
    floating.layer.cornerRadius = 12;
    NSView *floatInner = [[NSView alloc] initWithFrame:floating.bounds];
    floatInner.wantsLayer = YES;
    floatInner.layer.cornerRadius = 12;
    [floating addSubview:floatInner];
    NSVisualEffectView *floatEffect = [[NSVisualEffectView alloc] initWithFrame:floatInner.bounds];
    floatEffect.material = NSVisualEffectMaterialHUDWindow;
    floatEffect.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    floatEffect.state = NSVisualEffectStateFollowsWindowActiveState;
    [floatInner addSubview:floatEffect];
    DPCombTintView *floatTint = [[objc_getClass(DPDiaWindowTint) alloc] initWithFrame:floatInner.bounds];
    NSView *floatWash = [[objc_getClass(DPDiaColorView) alloc] initWithFrame:floatTint.bounds];
    [floatTint addSubview:floatWash];
    [floatInner addSubview:floatTint];
    [content addSubview:floating];

    DPCombSidebarController *sidebarCtrl = [objc_getClass(DPDiaSidebarController) new];
    DPCombFlippedView *sidebarView = [[DPCombFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 220, 640)];
    DPCombSidebarHeader *header = [[objc_getClass(DPDiaSidebarHeader) alloc] initWithFrame:NSMakeRect(0, 0, 220, 44)];
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(16, 12, 196, 20)];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    NSView *lights = [[objc_getClass(DPDiaTrafficLights) alloc] initWithFrame:NSMakeRect(0, 0, 56, 16)];
    NSButton *closeBtn = [NSButton buttonWithTitle:@"" target:nil action:nil];
    closeBtn.frame = NSMakeRect(0, 2, 12, 12);
    win.fakeCloseButton = closeBtn;
    [lights addSubview:closeBtn];
    NSButton *profileBtn = [NSButton buttonWithTitle:@"Profile" target:nil action:nil];
    [stack addArrangedSubview:lights];
    [stack addArrangedSubview:profileBtn];
    header.rowStack = stack;
    header.diaStackFrame = NSMakeRect(16, 12, 196, 20);
    [header addSubview:stack];

    NSView *sidebarBody = [[NSView alloc] initWithFrame:NSMakeRect(0, 44, 220, 556)];
    NSView *sidebarFooter = [[objc_getClass(DPDiaSidebarFooter) alloc] initWithFrame:NSMakeRect(0, 600, 220, 40)];
    [sidebarView addSubview:header];
    [sidebarView addSubview:sidebarBody];
    [sidebarView addSubview:sidebarFooter];
    sidebarCtrl.view = sidebarView;
    sidebarCtrl.headerView = header;
    sidebarCtrl.bodyView = sidebarBody;
    DPSet(win, "dp_comb_sidebar_ctrl", sidebarCtrl);
    [content addSubview:sidebarView];

    DPCombFlippedView *container = [[objc_getClass(DPDiaContentContainer) alloc] initWithFrame:NSMakeRect(220, 6, 734, 628)];
    container.wantsLayer = YES;
    container.layer.cornerRadius = 10;
    DPCombContentPane *pane = [[objc_getClass(DPDiaContentPane) alloc] initWithFrame:container.bounds];
    pane.wantsLayer = YES;
    pane.layer.cornerRadius = 10;
    pane.contentPaneID = @"11111111-1111-1111-1111-111111111111";

    NSView *toolbar = [[objc_getClass(DPDiaToolbar) alloc] initWithFrame:NSMakeRect(0, 0, 734, 42)];
    DPCombAddressField *addr = [[objc_getClass(DPDiaAddressField) alloc] initWithFrame:NSMakeRect(80, 6, 400, 30)];
    NSButton *chatBtn = [[objc_getClass(DPDiaCapsuleButton) alloc] initWithFrame:NSMakeRect(660, 6, 60, 30)];
    chatBtn.accessibilityLabel = @"Chat with this tab";
    [toolbar addSubview:addr];
    [toolbar addSubview:chatBtn];

    NSView *bookmarks = [[objc_getClass(DPDiaBookmarksBar) alloc] initWithFrame:NSMakeRect(0, 42, 734, 28)];
    NSView *pageHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 70, 734, 558)];
    NSView *pageChild = [[NSView alloc] initWithFrame:pageHost.bounds];
    [pageHost addSubview:pageChild];

    [pane addSubview:toolbar];
    [pane addSubview:bookmarks];
    [pane addSubview:pageHost];
    [container addSubview:pane];
    [content addSubview:container];

    b.window = win;
    b.themeFrame = themeFrame;
    b.effectView = effect;
    b.tintView = tint;
    b.washView = wash;
    b.gradientView = gradient;
    b.gradientLayer = gradLayer;
    b.floatingSidebar = floating;
    b.floatingEffect = floatEffect;
    b.floatingTint = floatTint;
    b.floatingWash = floatWash;
    b.container = container;
    b.pane = pane;
    b.toolbar = toolbar;
    b.bookmarksBar = bookmarks;
    b.addressField = addr;
    b.chatButton = chatBtn;
    b.pageHost = pageHost;
    b.sidebarController = sidebarCtrl;
    b.sidebarHeader = header;
    b.headerStack = stack;
    b.trafficLights = lights;
    b.sidebarBody = sidebarBody;
    b.sidebarFooter = sidebarFooter;
    b.browser = browser;
    return b;
}

static void SetPatchImmediate(NSString *key, BOOL on, BOOL save) {
    DPPatch *p = DPPatchNamed(key);
    if (!p) return;
    if (save) [[NSUserDefaults.alloc initWithSuiteName:@"com.diapatches"] setBool:on forKey:p->key];
    if (DPPaused) on = NO;
    p->on = on;
    p->progress = on ? 1.0 : 0.0;
    if (p->apply) p->apply(p);
    else if (p->relayout) p->relayout();
}

static void ResetAllPatchesOff(void) {
    if (DPPaused) {
        DPSetPaused(NO);
        DPApplySavedSettings();
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        [defaults setBool:NO forKey:DPPatches[i]->key];
        DPPatches[i]->on = NO;
        DPPatches[i]->progress = 0;
        if (DPPatches[i]->apply) DPPatches[i]->apply(DPPatches[i]);
        else if (DPPatches[i]->relayout) DPPatches[i]->relayout();
    }
}

#pragma mark - Test 1: Multi-Hook Stacking & DPIsHooked

static void TestHookChainsAndDPIsHooked(void) {
    DPHookClass(DPChainBase.class, @selector(ping), (IMP)DPChainHookA);
    DPHookClass(DPChainSub.class, @selector(ping), (IMP)DPChainHookB);
    DPHookClass(DPChainBase.class, @selector(ping), (IMP)DPChainHookC);

    DPChainSub *sub = [DPChainSub new];
    sub.trace = [NSMutableArray array];
    [sub ping];
    Check([sub.trace isEqualToArray:@[@"B-in", @"C-in", @"A-in", @"orig", @"A-out", @"C-out", @"B-out"]],
          @"multi-hook subclass+superclass dispatch chain runs in exact outer->inner->orig order");

    Check(DPIsHooked(DPChainBase.class, @selector(ping), (IMP)DPChainHookA), @"DPIsHooked finds inner hook on base class");
    Check(DPIsHooked(DPChainBase.class, @selector(ping), (IMP)DPChainHookC), @"DPIsHooked finds outer hook on base class");
    Check(DPIsHooked(DPChainSub.class, @selector(ping), (IMP)DPChainHookB), @"DPIsHooked finds subclass hook");
    Check(!DPIsHooked(DPChainBase.class, @selector(ping), (IMP)DPChainUnhooked), @"DPIsHooked rejects unhooked IMP");

    Method m = class_getInstanceMethod(DPChainBase.class, @selector(ping));
    IMP saved = method_setImplementation(m, (IMP)DPChainClobber);
    Check(!DPIsHooked(DPChainBase.class, @selector(ping), (IMP)DPChainHookA), @"DPIsHooked detects external clobber on inner hook");
    Check(!DPIsHooked(DPChainBase.class, @selector(ping), (IMP)DPChainHookC), @"DPIsHooked detects external clobber on outer hook");
    method_setImplementation(m, saved);

    DPPatch *privTheme = DPPatchNamed(@"privateWindowTheme");
    DPPatch *colorPicker = DPPatchNamed(@"profileColorPicker");
    DPPatch *peek = DPPatchNamed(@"peek");
    Check(privTheme && colorPicker && peek, @"core stacked patches registered in DPPatches");
    Check(privTheme->verify(privTheme) == nil, @"PrivateWindowTheme verify succeeds while stacked with ProfileColorPicker");
    Check(colorPicker->verify(colorPicker) == nil, @"ProfileColorPicker verify succeeds while stacked with PrivateWindowTheme");
    Check(peek->verify(peek) == nil, @"Peek verify succeeds while stacked with GroupTabs/Tracking");
}

#pragma mark - Test 2: Cluster A (Toolbar, Address Field, Chrome, Corners)

static void TestClusterAToolbarChrome(void) {
    ResetAllPatchesOff();
    NSArray *diaColors = @[ (id)NSColor.systemBlueColor.CGColor, (id)NSColor.systemTealColor.CGColor ];
    DPMockWindowBundle *b = BuildMockWindow(NO, YES, @"space-a", diaColors);
    gMockWindows = @[ b.window ];
    gMockKeyWindow = b.window;

    [b.sidebarController viewWillLayout];
    [b.sidebarHeader layout];
    [b.pane layout];
    [b.addressField layout];
    [b.container layout];
    Check(fabs(NSHeight(b.sidebarHeader.frame) - 44) < 0.1, @"Cluster A baseline: header height untouched when off");
    Check(fabs(NSMinX(b.headerStack.frame) - 16) < 0.1, @"Cluster A baseline: header stack untouched when off");
    Check(fabs(b.toolbar.alphaValue - 1.0) < 0.01 && fabs(NSMinY(b.pageHost.frame) - 70) < 0.1, @"Cluster A baseline: toolbar and page untouched when off");
    Check(!b.addressField.ownedDelayed->isHoverActive, @"Cluster A baseline: address field hover untouched when off");
    Check(b.window.fakeCornerRadius == 10 && b.container.layer.cornerRadius == 10, @"Cluster A baseline: corners untouched when off");

    SetPatchImmediate(@"hideToolbar", YES, YES);
    [b.pane layout];
    Check(b.toolbar.alphaValue < 0.01 && fabs(NSMinY(b.pageHost.frame)) < 0.5, @"HideToolbar hides toolbar and lifts page");
    SetPatchImmediate(@"showAddressField", YES, YES);
    [b.addressField layout];
    Check(b.addressField.ownedDelayed->isHoverActive, @"ShowAddressField activates hover state");
    SetPatchImmediate(@"hideToolbar", NO, YES);
    [b.pane layout];
    Check(fabs(b.toolbar.alphaValue - 1.0) < 0.01 && fabs(NSMinY(b.pageHost.frame) - 70) < 0.5, @"HideToolbar OFF restores toolbar while ShowAddressField stays ON");
    Check(b.addressField.ownedDelayed->isHoverActive, @"ShowAddressField remains active after HideToolbar turns OFF");
    SetPatchImmediate(@"showAddressField", NO, YES);
    [b.addressField layout];
    Check(!b.addressField.ownedDelayed->isHoverActive, @"ShowAddressField OFF clears forced hover cleanly");

    [DPHideHosts addObject:b.toolbar];
    DPEnforceHides(b.toolbar);
    Check(!b.chatButton.hidden, @"chat button starts visible");
    SetPatchImmediate(@"hideChatButton", YES, YES);
    SetPatchImmediate(@"turnOffAI", YES, YES);
    Check(b.chatButton.hidden, @"chat button hidden when both HideChatButton and TurnOffAI are ON");
    SetPatchImmediate(@"hideChatButton", NO, YES);
    Check(b.chatButton.hidden, @"chat button stays hidden when HideChatButton turns OFF while TurnOffAI stays ON");
    SetPatchImmediate(@"turnOffAI", NO, YES);
    Check(!b.chatButton.hidden, @"chat button reappears when both HideChatButton and TurnOffAI are OFF");
    SetPatchImmediate(@"hideChatButton", YES, YES);
    SetPatchImmediate(@"turnOffAI", YES, YES);
    SetPatchImmediate(@"turnOffAI", NO, YES);
    Check(b.chatButton.hidden, @"chat button stays hidden when TurnOffAI turns OFF while HideChatButton stays ON");
    SetPatchImmediate(@"hideChatButton", NO, YES);
    Check(!b.chatButton.hidden, @"chat button restored after HideChatButton OFF");

    [DPHideHosts addObject:b.sidebarHeader];
    SetPatchImmediate(@"compactSidebarHeader", YES, YES);
    SetPatchImmediate(@"hideTrafficLights", YES, YES);
    [b.sidebarController viewWillLayout];
    [b.sidebarHeader layout];
    Check(fabs(NSHeight(b.sidebarHeader.frame) - 34) < 0.5, @"CompactSidebarHeader trims header by 10pt alongside HideTrafficLights");
    Check(b.trafficLights.hidden, @"HideTrafficLights hides traffic lights alongside CompactSidebarHeader");
    Check(fabs(NSMinX(b.headerStack.frame) - 6) < 0.5, @"HideTrafficLights aligns header stack to x=6 without CompactSidebarHeader fighting it");
    DPPatch *compactHeader = DPPatchNamed(@"compactSidebarHeader"), *hideLights = DPPatchNamed(@"hideTrafficLights");
    Check(compactHeader->verify(compactHeader) == nil, @"CompactSidebarHeader verify passes with HideTrafficLights ON");
    Check(hideLights->verify(hideLights) == nil, @"HideTrafficLights verify passes with CompactSidebarHeader ON");

    SetPatchImmediate(@"hideTrafficLights", NO, YES);
    [b.sidebarController viewWillLayout];
    [b.sidebarHeader layout];
    Check(!b.trafficLights.hidden && fabs(NSHeight(b.sidebarHeader.frame) - 34) < 0.5, @"turning HideTrafficLights OFF keeps CompactSidebarHeader active");
    Check(hideLights->verify(hideLights) == nil, @"HideTrafficLights verify passes after turning OFF with CompactSidebarHeader ON");

    SetPatchImmediate(@"hideTrafficLights", YES, YES);
    SetPatchImmediate(@"compactSidebarHeader", NO, YES);
    [b.sidebarController viewWillLayout];
    [b.sidebarHeader layout];
    Check(fabs(NSHeight(b.sidebarHeader.frame) - 44) < 0.5, @"turning CompactSidebarHeader OFF restores full header height");
    Check(fabs(NSMinX(b.headerStack.frame) - 6) < 0.5, @"HideTrafficLights keeps x=6 after CompactSidebarHeader turns OFF");

    SetPatchImmediate(@"windowCorners", YES, YES);
    SetPatchImmediate(@"edgeToEdge", YES, YES);
    SetPatchImmediate(@"squareSidebarCorners", YES, YES);
    [b.container layout];
    Check(b.window.fakeCornerRadius == 26, @"WindowCorners sets window radius to 26");

    DPSetTweaksPaused(YES, nil);
    [b.sidebarController viewWillLayout];
    [b.sidebarHeader layout];
    [b.pane layout];
    [b.container layout];
    Check(b.window.fakeCornerRadius == 10, @"Pause Tweaks restores WindowCorners radius");
    Check(!b.trafficLights.hidden && fabs(NSMinX(b.headerStack.frame) - 16) < 0.5, @"Pause Tweaks restores HideTrafficLights and header stack");
    Check(fabs(b.container.layer.cornerRadius - 10) < 0.5, @"Pause Tweaks restores container corner radius");

    DPSetTweaksPaused(NO, nil);
    [b.sidebarController viewWillLayout];
    [b.sidebarHeader layout];
    Check(b.window.fakeCornerRadius == 26 && b.trafficLights.hidden, @"Resume Tweaks re-applies Cluster A patches");

    ResetAllPatchesOff();
    gMockWindows = nil;
    gMockKeyWindow = nil;
}

#pragma mark - Test 3: Cluster B (ProfileColorPicker x PrivateWindowTheme x WindowMaterial x TranslucentSidebar)

static void TestClusterBThemeMaterialTint(void) {
    ResetAllPatchesOff();
    NSArray *normalDiaColors = @[ (id)NSColor.systemBlueColor.CGColor, (id)NSColor.systemTealColor.CGColor ];
    NSArray *privateDiaColors = @[ (id)NSColor.systemIndigoColor.CGColor, (id)NSColor.systemPurpleColor.CGColor ];
    DPMockWindowBundle *normal = BuildMockWindow(NO, YES, @"space-main", normalDiaColors);
    DPMockWindowBundle *priv = BuildMockWindow(YES, YES, nil, privateDiaColors);
    DPMockWindowBundle *minPriv = BuildMockWindow(YES, NO, nil, privateDiaColors);
    gMockWindows = @[ normal.window, priv.window, minPriv.window ];
    gMockKeyWindow = normal.window;

    SetPatchImmediate(@"profileColorPicker", YES, YES);
    SetPatchImmediate(@"privateWindowTheme", YES, YES);
    DPSetProfileHexForSpace(@"space-main", @"#E05A2B");
    DPRefreshProfileColors();

    NSArray *customOrange = normal.gradientLayer.colors;
    Check(![customOrange isEqual:normalDiaColors], @"ProfileColorPicker applies custom orange hex to normal window");
    Check([priv.gradientLayer.colors isEqual:customOrange], @"PrivateWindowTheme synchronously mirrors custom hex to visible private window");
    Check([minPriv.gradientLayer.colors isEqual:customOrange], @"PrivateWindowTheme synchronously mirrors custom hex to minimized private window");

    DPSetProfileHexForSpace(@"space-main", @"#1B8A5A");
    DPRefreshProfileColorForWindow(normal.window);
    NSArray *customGreen = normal.gradientLayer.colors;
    Check(![customGreen isEqual:customOrange], @"ProfileColorPicker updates normal window to green hex");
    Check([priv.gradientLayer.colors isEqual:customGreen], @"PrivateWindowTheme mirrors single-window hex update");
    Check([minPriv.gradientLayer.colors isEqual:customGreen], @"PrivateWindowTheme mirrors single-window hex update to minimized window");

    SetPatchImmediate(@"profileColorPicker", NO, YES);
    Check([normal.gradientLayer.colors isEqual:normalDiaColors], @"normal window restores Dia colors when ProfileColorPicker turns OFF");
    Check([priv.gradientLayer.colors isEqual:normalDiaColors], @"private window immediately drops stale custom hex and mirrors normal Dia colors");
    Check([minPriv.gradientLayer.colors isEqual:normalDiaColors], @"minimized private window also mirrors restored normal Dia colors");

    SetPatchImmediate(@"profileColorPicker", YES, YES);
    Check([priv.gradientLayer.colors isEqual:customGreen], @"re-enabling ProfileColorPicker re-syncs private window to custom green");
    SetPatchImmediate(@"privateWindowTheme", NO, YES);
    Check([priv.gradientLayer.colors isEqual:privateDiaColors], @"turning PrivateWindowTheme OFF restores private window's original colors");
    Check([normal.gradientLayer.colors isEqual:customGreen], @"normal window keeps custom green while PrivateWindowTheme is OFF");

    DPPatch *matPatch = DPPatchNamed(@"windowMaterial");
    DPSetChoice(matPatch, @"material.7");
    SetPatchImmediate(@"windowMaterial", YES, YES);
    SetPatchImmediate(@"translucentSidebar", YES, YES);
    Check(normal.washView.hidden && normal.floatingWash.hidden, @"WindowMaterial + TranslucentSidebar hide both window and floating sidebar washes");
    Check(!normal.window.opaque && normal.effectView.material == NSVisualEffectMaterialSidebar, @"WindowMaterial sets Sidebar material and non-opaque window");
    Check(normal.floatingEffect.material == NSVisualEffectMaterialSidebar, @"floating sidebar uses WindowMaterial choice");

    SetPatchImmediate(@"windowMaterial", NO, YES);
    Check(!normal.washView.hidden && normal.window.opaque, @"disabling WindowMaterial restores window wash and opacity");
    Check(normal.effectView.material == NSVisualEffectMaterialUnderWindowBackground, @"disabling WindowMaterial restores window material");
    Check(normal.floatingWash.hidden, @"TranslucentSidebar keeps floating sidebar wash hidden after WindowMaterial turns OFF");
    Check(normal.floatingEffect.material == NSVisualEffectMaterialUnderWindowBackground, @"floating sidebar falls back to restored window background material");

    SetPatchImmediate(@"translucentSidebar", NO, YES);
    Check(!normal.floatingWash.hidden, @"disabling TranslucentSidebar restores floating sidebar wash");
    Check(normal.floatingEffect.material == NSVisualEffectMaterialHUDWindow, @"disabling TranslucentSidebar restores original floating sidebar material");

    NSView *pinnedTabHost = [[objc_getClass(DPDiaPinnedTab) alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)];
    NSView *pinnedOutline = [[objc_getClass(DPDiaPinnedTabOutline) alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
    pinnedOutline.wantsLayer = YES;
    [pinnedTabHost addSubview:pinnedOutline];
    NSView *groupCell = [[objc_getClass(DPDiaTabGroupCell) alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
    NSView *groupBG = [[objc_getClass(DPDiaTabGroupBackground) alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
    groupBG.wantsLayer = YES;
    CGColorRef greyBG = [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:0.3].CGColor;
    groupBG.layer.backgroundColor = greyBG;
    [groupCell addSubview:groupBG];
    [normal.window.contentView addSubview:pinnedTabHost];
    [normal.window.contentView addSubview:groupCell];

    SetPatchImmediate(@"privateWindowTheme", YES, YES);
    SetPatchImmediate(@"windowMaterial", YES, YES);
    SetPatchImmediate(@"translucentSidebar", YES, YES);
    SetPatchImmediate(@"hidePinnedTabBorder", YES, YES);
    SetPatchImmediate(@"hideTabGroupBackground", YES, YES);
    [pinnedTabHost layout];
    [groupCell updateLayer];
    Check(pinnedOutline.hidden && groupBG.layer.backgroundColor == nil, @"HidePinnedTabBorder and HideTabGroupBackground apply alongside Cluster B");

    DPSetTweaksPaused(YES, nil);
    Check([normal.gradientLayer.colors isEqual:normalDiaColors], @"Pause Tweaks restores normal gradient colors");
    Check([priv.gradientLayer.colors isEqual:privateDiaColors], @"Pause Tweaks restores private gradient colors");
    Check(!normal.washView.hidden && !normal.floatingWash.hidden && normal.window.opaque, @"Pause Tweaks restores WindowMaterial and TranslucentSidebar");
    Check(!pinnedOutline.hidden && groupBG.layer.backgroundColor != nil, @"Pause Tweaks restores pinned border and tab group background");

    DPSetTweaksPaused(NO, nil);
    [pinnedTabHost layout];
    [groupCell updateLayer];
    Check([normal.gradientLayer.colors isEqual:customGreen] && [priv.gradientLayer.colors isEqual:customGreen],
          @"Resume Tweaks restores coordinated ProfileColorPicker + PrivateWindowTheme");
    Check(normal.washView.hidden && normal.floatingWash.hidden && pinnedOutline.hidden && groupBG.layer.backgroundColor == nil,
          @"Resume Tweaks re-applies full Cluster B state");

    DPSetProfileHexForSpace(@"space-main", nil);
    ResetAllPatchesOff();
    gMockWindows = nil;
    gMockKeyWindow = nil;
}

#pragma mark - Test 4: Cluster C (Menus, Escape/Shortcut Priority, CollapsePinned x CommandBar, Tracking x Peek)

static void TestClusterCMenusOverlaysAndLayout(void) {
    ResetAllPatchesOff();
    NSArray *diaColors = @[ (id)NSColor.systemBlueColor.CGColor ];
    DPMockWindowBundle *b = BuildMockWindow(NO, YES, @"space-c", diaColors);
    gMockWindows = @[ b.window ];
    gMockKeyWindow = b.window;

    SetPatchImmediate(@"unloadTab", YES, YES);
    SetPatchImmediate(@"groupTabsByDomain", YES, YES);
    SetPatchImmediate(@"turnOffAI", YES, YES);

    NSString *tabUUID = @"22222222-2222-2222-2222-222222222222";
    NSString *paneUUID = @"33333333-3333-3333-3333-333333333333";
    DPCombWebContents *page = [objc_getClass(DPDiaWebContents) new];
    page.url = [NSURL URLWithString:@"https://example.com/doc"];
    page.visibilityValue = 0;
    page.nativeView = [[NSView alloc] initWithFrame:b.pane.bounds];
    b.pane.contentPaneID = paneUUID;
    [b.pane addSubview:page.nativeView];
    [page setVisibility:0];
    DPRecordVisiblePanePages();

    DPCombTabContentController *tabCtrl = [DPCombTabContentController new];
    tabCtrl.tabID = tabUUID;
    tabCtrl.contentID = paneUUID;
    tabCtrl.webContentURL = page.url;
    DPCombTabContentVM *tabVM = [DPCombTabContentVM new];
    tabVM.delegate = tabCtrl;
    DPCombTabContentView *tabContent = [[objc_getClass(DPDiaTabContentView) alloc] initWithFrame:NSMakeRect(0, 0, 180, 32)];
    tabContent.viewModel = tabVM;

    DPCombTabView *tabView = [[objc_getClass(DPDiaTabView) alloc] initWithFrame:NSMakeRect(0, 0, 180, 32)];
    tabView.contentViews = @{ paneUUID : tabContent };
    [tabView addSubview:tabContent];
    [b.sidebarBody addSubview:tabView];

    NSMenu *reused = [[NSMenu alloc] initWithTitle:@"Tab"];
    [reused addItemWithTitle:@"New Group with 2 Tabs" action:nil keyEquivalent:@""];
    [reused addItemWithTitle:@"Chat with this tab" action:nil keyEquivalent:@""];
    [reused addItemWithTitle:@"Close Tab" action:nil keyEquivalent:@""];
    tabView.reusedMenu = reused;

    NSMenu *returned = [tabView menuForEvent:MakeRightClick(b.window)];
    Check(returned == reused, @"tab menuForEvent returns populated menu");
    NSInteger groupIdx = [reused indexOfItemWithTitle:@"Group Tabs by Domain"];
    NSInteger unloadIdx = [reused indexOfItemWithTitle:@"Unload Tab"];
    NSInteger closeIdx = [reused indexOfItemWithTitle:@"Close Tab"];
    NSMenuItem *chatItem = [reused itemWithTitle:@"Chat with this tab"];
    Check(groupIdx >= 0 && unloadIdx >= 0 && closeIdx >= 0, @"GroupTabs and UnloadTab both insert items");
    Check(groupIdx < unloadIdx && unloadIdx < closeIdx, @"GroupTabs items stay before Unload Tab and Close Tab");
    Check(chatItem.hidden, @"TurnOffAI hides AI item inside tab context menu");

    [tabView menuForEvent:MakeRightClick(b.window)];
    NSInteger unloadCount = 0, groupCount = 0;
    for (NSMenuItem *it in reused.itemArray) {
        if ([it.title isEqualToString:@"Unload Tab"]) unloadCount++;
        if ([it.title isEqualToString:@"Group Tabs by Domain"]) groupCount++;
    }
    Check(unloadCount == 1 && groupCount == 1, @"reused tab menu has zero duplicate Unload Tab or Group Tabs items");

    tabView.returnNilMenu = YES;
    Check([tabView menuForEvent:MakeRightClick(b.window)] == nil, @"nil menuForEvent passes through safely");
    tabView.returnNilMenu = NO;

    SetPatchImmediate(@"groupTabsByDomain", NO, YES);
    Check([reused itemWithTitle:@"Group Tabs by Domain"].hidden, @"turning GroupTabs OFF immediately hides items in reused context menu");
    SetPatchImmediate(@"unloadTab", NO, YES);
    [tabView menuForEvent:MakeRightClick(b.window)];
    Check([reused itemWithTitle:@"Unload Tab"] == nil, @"turning UnloadTab OFF strips tagged Unload Tab from reused menu");
    SetPatchImmediate(@"turnOffAI", NO, YES);
    Check(!chatItem.hidden, @"turning TurnOffAI OFF unhides AI context menu item");

    DPLittleDia.on = YES;
    [gLittleDiaOpenedLinks removeAllObjects];
    DPCombWebContentChromium *wcDelegate = [objc_getClass(DPDiaWebContent) new];
    DPCombLinkElement *linkEl = [DPCombLinkElement new];
    linkEl.linkURL = [NSURL URLWithString:@"https://example.com/little-target"];
    [wcDelegate webContents:page willShowContextMenu:nil withElement:linkEl];

    NSMenu *sidebarMenu = [[NSMenu alloc] initWithTitle:@"Grain"];
    [sidebarMenu addItemWithTitle:@"Sidebar Grain" action:nil keyEquivalent:@""];
    [NSMenu popUpContextMenu:sidebarMenu withEvent:MakeRightClick(b.window) forView:b.sidebarBody];
    Check([sidebarMenu itemWithTitle:@"Open Link in Little Dia"] == nil, @"non-web sidebar menu never receives Open Link in Little Dia");

    NSView *renderView = [[objc_getClass(DPDiaRenderWidget) alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSMenu *webMenu = [[NSMenu alloc] initWithTitle:@"Link"];
    [webMenu addItemWithTitle:@"Open Link in New Tab" action:nil keyEquivalent:@""];
    [webMenu addItemWithTitle:@"Copy Link Address" action:nil keyEquivalent:@""];
    [NSMenu popUpContextMenu:webMenu withEvent:MakeRightClick(b.window) forView:renderView];
    Check([webMenu indexOfItemWithTitle:@"Open Link in Little Dia"] == 1,
          @"web link menu still receives Open Link in Little Dia after non-web menu popup");

    [NSMenu popUpContextMenu:webMenu withEvent:MakeRightClick(b.window) forView:renderView];
    Check([webMenu itemWithTitle:@"Open Link in Little Dia"] == nil, @"stale Little Dia link item is stripped on menu reuse");
    DPLittleDia.on = NO;

    SetPatchImmediate(@"peek", YES, YES);
    SetPatchImmediate(@"commandBar", YES, YES);
    DPLittleDia.on = YES;
    SetPatchImmediate(@"littleDiaEscapeCloses", YES, YES);
    [gLittleDiaWindows addObject:b.window];

    DPCombWebContents *peekPage = [objc_getClass(DPDiaWebContents) new];
    peekPage.url = [NSURL URLWithString:@"https://example.com/peek"];
    DPPeekCard *peekCard = DPPeekShowCard(b.window, peekPage, nil, NSZeroRect);
    DPPeekAddToolbar(peekCard);
    Check(peekCard && DPPeekCardIn(b.window) == peekCard, @"Peek card mounts cleanly on window");

    DPCommandBarOverlay *overlay = [[DPCommandBarOverlay alloc] initWithFrame:b.window.contentView.bounds];
    overlay.host = b.window;
    NSView *panel = [[objc_getClass(DPDiaAssistantPanel) alloc] initWithFrame:NSMakeRect(100, 200, 500, 60)];
    [overlay addSubview:panel];
    overlay.panel = panel;
    [b.window.contentView addSubview:overlay];
    DPSet(b.window, &DPOverlayKey, overlay);

    NSWindow *fakeSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 120) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    b.window.fakeSheet = fakeSheet;
    NSEvent *esc = MakeKeyEvent(b.window, @"\x1b", kVK_Escape, 0);
    NSEvent *cmdW = MakeKeyEvent(b.window, @"w", kVK_ANSI_W, NSEventModifierFlagCommand);
    Check(DispatchToKeyMonitors(esc, NO) == esc && DispatchToKeyMonitors(esc, YES) == esc,
          @"attached sheet preserves Escape across all key monitors in both orders");
    Check(DPPeekHandleKeyEvent(peekCard, cmdW) == cmdW, @"Peek yields Cmd+W when attached sheet is open");
    Check(!peekCard.closing && !b.window.closeCalled, @"attached sheet protects Peek and LittleDia from Escape");
    b.window.fakeSheet = nil;

    Check(DPPeekHandleKeyEvent(peekCard, esc) == esc, @"Peek yields Escape when CommandBarOverlay is visible above it");
    Check(DPPeekHandleKeyEvent(peekCard, cmdW) == cmdW, @"Peek yields Cmd+W when CommandBarOverlay is visible above it");
    Check(DispatchToKeyMonitors(esc, YES) == esc || (!peekCard.closing && !b.window.closeCalled),
          @"LittleDia Escape monitor yields while CommandBarOverlay and Peek are open");
    Check(!peekCard.closing && !b.window.closeCalled, @"Peek and LittleDia stay open while CommandBarOverlay is active");

    [overlay removeFromSuperview];
    DPSet(b.window, &DPOverlayKey, nil);
    gPeekEditAddressCalls = 0;
    NSEvent *cmdL = MakeKeyEvent(b.window, @"l", kVK_ANSI_L, NSEventModifierFlagCommand);
    Check(DispatchToKeyMonitors(cmdL, NO) == nil && gPeekEditAddressCalls == 1,
          @"CommandBar yields Cmd+L to open Peek toolbar across full key monitor chain");
    Check(DispatchToKeyMonitors(esc, NO) == nil && peekCard.closing && !b.window.closeCalled,
          @"Escape closes Peek first without closing LittleDia behind it");
    DPPeekCloseAll();

    b.window.closeCalled = NO;
    Check(DispatchToKeyMonitors(esc, NO) == nil && b.window.closeCalled,
          @"Escape closes LittleDia once all higher-priority overlays are gone");
    b.window.closeCalled = NO;
    [gLittleDiaWindows removeObject:b.window];

    DPCombTabListView *tabList = [[objc_getClass(DPDiaTabList) alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
    DPCombTabListDelegate *tlDel = [DPCombTabListDelegate new];
    tlDel.spaceID = @"space-c";
    DPCombTabListVM *tlVM = [DPCombTabListVM new];
    tlVM.delegate = tlDel;
    tabList.viewModel = tlVM;
    DPCombCollectionView *collection = [[objc_getClass(DPDiaTabListCollection) alloc] initWithFrame:tabList.bounds];
    collection.pinnedCount = 2;
    collection.regularCount = 2;
    DPCombTabListLayout *listLayout = [objc_getClass(DPDiaTabListLayout) new];
    listLayout.pinnedCount = 2;
    listLayout.regularCount = 2;
    listLayout.rowHeight = 37;
    collection.collectionViewLayout = listLayout;
    [tabList addSubview:collection];
    [b.sidebarBody addSubview:tabList];
    gRowNames = [@[ @".tab(p1)", @".tab(p2)", @".sep", @".tab(r1)", @".tab(r2)" ] mutableCopy];

    SetPatchImmediate(@"collapsePinned", YES, YES);
    SetPatchImmediate(@"compactTabRows", YES, YES);
    [listLayout prepareLayout];
    NSView *pinnedHeader = DPFindView(collection, ^BOOL(NSView *v) { return [v isKindOfClass:NSClassFromString(@"DPPinnedHeader")]; });
    Check(pinnedHeader && !pinnedHeader.hidden && fabs(NSMinY(pinnedHeader.frame)) < 0.5, @"CollapsePinned mounts Pinned header at y=0");

    DPHideTabRow(@"temp-hidden", b.window);
    DPFreezeLists(b.window);
    [listLayout prepareLayout];
    Check(fabs(NSMinY(pinnedHeader.frame)) < 0.5, @"CollapsePinned header stays at y=0 when HideTabLayout freezes shifted rows");
    DPPatch *collapsePatch = DPPatchNamed(@"collapsePinned");
    Check(collapsePatch->verify(collapsePatch) == nil, @"CollapsePinned verify passes alongside frozen CommandBar HideTabLayout");
    DPShowTabRow(@"temp-hidden", YES);
    DPRelayoutLists();

    gCommandBarExpectCount = 0;
    gPipRequests = 0;
    DPCombGesture *clickOnHeader = [DPCombGesture new];
    clickOnHeader.point = NSMakePoint(40, 10);
    [tabList handleBackgroundDoubleClick:clickOnHeader];
    DPCombMediaSession *media = [objc_getClass(DPDiaMediaSession) new];
    NSError *pipErr = nil;
    [media requestPictureInPicture:&pipErr];
    Check(gCommandBarExpectCount == 0 && tabList.diaDoubleClicks == 0 && gPipRequests == 1,
          @"double-click on Pinned header does not open CommandBar, hold AutoPip, or create a new tab");

    DPCombWebContents *opener = [b.browser createWebContents:nil];
    DPCombWebContents *ignoredWC = [objc_getClass(DPDiaWebContents) new];
    DPCombWebContents *realWC = [objc_getClass(DPDiaWebContents) new];
    [wcDelegate webContents:opener didCreateNewWebContent:ignoredWC targetURL:[NSURL URLWithString:@"https://example.com/a"] disposition:0];
    [wcDelegate webContents:opener didCreateNewWebContent:realWC targetURL:[NSURL URLWithString:@"https://example.com/b"] disposition:DPForegroundTab];
    Check(DPBrowserOfContents(ignoredWC) == nil, @"GroupTabs/Tracking ignores disposition 0 cancelled by Peek");
    Check(DPBrowserOfContents(realWC) == b.browser, @"GroupTabs/Tracking still tracks real disposition 2 tabs");

    ResetAllPatchesOff();
    gMockWindows = nil;
    gMockKeyWindow = nil;
}

#pragma mark - Test 5: Cluster D (LaunchFlags x TurnOffAI x SplitClientHello, Covered Tweaks, Settings Pause, Minimized Rows)

static void TestClusterDLaunchFlagsAndCoveredTweaks(void) {
    ResetAllPatchesOff();

    NSString *passkeysExt = DPAppSupport(@"DiaPatches/passkeys-extension");
    NSString *staleExt = DPAppSupport(@"DiaPatches/stale-old-extension");
    NSString *userExt = @"/Users/test/Extensions/custom-ext";
    NSString *aiRules = @"--host-resolver-rules=MAP ai-service.diabrowser.engineering ~NOTFOUND, MAP aiproxy.diabrowser.engineering ~NOTFOUND";
    DPAddLaunchFlag(@"--host-resolver-rules=MAP custom.local 127.0.0.1");
    DPAddLaunchFlag(aiRules);
    DPAddLaunchFlag(@"--enable-features=CustomFeature");
    DPAddLaunchFlag(@"--enable-features=NetworkServiceInProcess2");
    DPAddLaunchFlag([@"--load-extension=" stringByAppendingString:userExt]);
    DPLoadExtension(passkeysExt);
    DPDropLaunchFlag(@"--host-resolver-rules=MAP stale-ai.diabrowser.engineering ~NOTFOUND");
    DPDropLaunchFlag(@"--enable-features=StaleFeature");

    NSArray<NSString *> *relaunchArgv = @[
        @"/Applications/Dia.app/Contents/MacOS/Dia",
        @"--host-resolver-rules=MAP user-carried.local 127.0.0.1,MAP stale-ai.diabrowser.engineering ~NOTFOUND",
        @"--enable-features=UserCarriedFeature,StaleFeature",
        [NSString stringWithFormat:@"--load-extension=%@", staleExt],
    ];
    (void)[[objc_getClass(DPDiaAppConfiguration) alloc] init:(int)relaunchArgv.count argv:relaunchArgv profilePath:@"" applicationID:1
                                                isProduction:YES sessionRestorationPolicy:0 shouldLoadAllProfilesAtStartup:NO
                                    quitRunLoopOnTermination:NO userDefaultsSuiteName:nil];
    NSArray<NSString *> *merged = gLastConfigArgv;
    Check(gLastConfigArgc == (int)merged.count, @"relaunch argc matches merged argv count");
    NSString *joined1 = [merged componentsJoinedByString:@" "];
    Check([joined1 containsString:@"--host-resolver-rules=MAP user-carried.local 127.0.0.1,MAP custom.local 127.0.0.1,MAP ai-service.diabrowser.engineering ~NOTFOUND,MAP aiproxy.diabrowser.engineering ~NOTFOUND"],
          @"LaunchFlags and TurnOffAI merge into one --host-resolver-rules flag while preserving user rules");
    Check(![joined1 containsString:@"stale-ai.diabrowser.engineering"], @"dropped host resolver rule is stripped on relaunch");
    Check([joined1 containsString:@"--enable-features=UserCarriedFeature,CustomFeature,NetworkServiceInProcess2"],
          @"LaunchFlags and SplitClientHello merge into one --enable-features flag");
    Check(![joined1 containsString:@"StaleFeature"], @"dropped feature flag is stripped on relaunch");
    Check([joined1 containsString:[NSString stringWithFormat:@"--load-extension=%@,%@", userExt, passkeysExt]] && ![joined1 containsString:staleExt],
          @"user and active DiaPatches extensions merge while stale DiaPatches extension is dropped");

    NSArray<NSString *> *coveredKeys = @[
        @"hideChatButton", @"hideChatsButton", @"hideUpgradeBanner",
        @"hidePersonalizeButton", @"hideSkillsSuggestions", @"hideConnectAppPrompts"
    ];
    for (NSString *key in coveredKeys) {
        DPPatch *p = DPPatchNamed(key);
        Check(p && [p->coveredBy isEqualToString:@"turnOffAI"], [NSString stringWithFormat:@"%@ declares coveredBy = turnOffAI", key]);
    }

    SetPatchImmediate(@"turnOffAI", YES, YES);
    SetPatchImmediate(@"hideToolbar", YES, YES);
    SetPatchImmediate(@"showAddressField", YES, YES);
    SetPatchImmediate(@"commandBar", YES, YES);
    SetPatchImmediate(@"commandBarBlur", YES, YES);

    DPPatch *hideChat = DPPatchNamed(@"hideChatButton");
    DPPatch *showAddr = DPPatchNamed(@"showAddressField");
    DPPatch *cbBlur = DPPatchNamed(@"commandBarBlur");
    DPPatchSwitch *chatSwitch = [[DPPatchSwitch alloc] initWithPatch:hideChat];
    DPPatchSwitch *addrSwitch = [[DPPatchSwitch alloc] initWithPatch:showAddr];
    DPPatchSwitch *blurSwitch = [[DPPatchSwitch alloc] initWithPatch:cbBlur];

    Check([DPWhyDisabled(hideChat) isEqualToString:@"Turn Off AI hides this too."], @"covered tweak shows covering reason while unpaused");
    Check([DPWhyHidden(showAddr) isEqualToString:@"Hidden while Hide Toolbar is on"], @"disabledBy tweak shows hidden reason while unpaused");
    Check(DPWhyDisabled(cbBlur) == nil, @"sub-option with ON parent is not disabled while unpaused");

    Check([DPRelaunchingOnPause() containsObject:@"Turn Off AI"], @"DPRelaunchingOnPause reports Turn Off AI before pausing");
    DPSetTweaksPaused(YES, nil);
    [chatSwitch sync];
    [addrSwitch sync];
    [blurSwitch sync];
    Check([DPWhyDisabled(hideChat) isEqualToString:@"Turn Off AI hides this too."],
          @"covered tweak keeps Turn Off AI reason while paused");
    Check([DPWhyHidden(showAddr) isEqualToString:@"Hidden while Hide Toolbar is on"],
          @"disabledBy tweak keeps hidden-by reason while paused");
    Check(DPWhyDisabled(cbBlur) == nil,
          @"sub-option with saved-ON parent does not falsely report Needs Parent while paused");
    Check(!chatSwitch.enabled && !addrSwitch.enabled && !blurSwitch.enabled && blurSwitch.state == NSControlStateValueOn,
          @"switches stay disabled and display saved state while paused");

    DPMockWindowBundle *hostWin = BuildMockWindow(NO, YES, @"space-d", @[ (id)NSColor.systemBlueColor.CGColor ]);
    gMockWindows = @[ hostWin.window ];
    DPCombDialogPanel *dialog = [[objc_getClass(DPDiaDialogPanel) alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    NSView *upsell = [[objc_getClass("_TtC9AppUpsell26RebrandedUpsellContentView") alloc] initWithFrame:NSMakeRect(0, 0, 360, 120)];
    [upsell addSubview:[NSTextField labelWithString:@"Connect Gmail to Dia?"]];
    NSButton *notNow = [[objc_getClass(DPDiaDialogButton) alloc] initWithFrame:NSMakeRect(0, 0, 80, 28)];
    notNow.title = @"Not Now";
    notNow.tag = 1;
    notNow.target = dialog;
    notNow.action = @selector(handleButton:);
    [dialog addSubview:upsell];
    [dialog addSubview:notNow];
    DPCombDialogVC *dvc = [objc_getClass(DPDiaDialogPanelVC) new];
    dvc.panel = dialog;
    [hostWin.window.contentView addSubview:dvc.view];
    DPDrainMainQueue(0.05);
    Check(dialog.declineClicks == 0, @"paused TurnOffAI does not auto-decline Connect App dialog");

    DPSetTweaksPaused(NO, nil);
    DPDrainMainQueue(0.05);
    Check(dialog.declineClicks == 1, @"resumed TurnOffAI auto-declines Connect App dialog even with HideConnectAppPrompts OFF");

    DPMockWindowBundle *minWin = BuildMockWindow(NO, NO, @"space-min", @[ (id)NSColor.systemBlueColor.CGColor ]);
    gMockWindows = @[ minWin.window ];
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 240, 200)];
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"col"]];
    DPCombSettingsSidebarDelegate *sideDel = [objc_getClass(DPDiaSettingsSidebar) new];
    sideDel.titles = @[ @"General", @"Apps", @"Skills", @"Profiles" ];
    table.dataSource = sideDel;
    table.delegate = sideDel;
    [minWin.window.contentView addSubview:table];
    [table reloadData];
    Check([table.hiddenRowIndexes containsIndex:1] && [table.hiddenRowIndexes containsIndex:2],
          @"TurnOffAI hides Apps and Skills rows in settings sidebar table");

    SetPatchImmediate(@"turnOffAI", NO, YES);
    Check(table.hiddenRowIndexes.count == 0, @"TurnOffAI OFF restores folded AI rows even inside a minimized window");

    ResetAllPatchesOff();
    gMockWindows = nil;
    gMockKeyWindow = nil;
}

#pragma mark - Test 6: Multi-Cluster Permutation & Pause/Resume Teardown Stress Under ASan/UBSan

static uint32_t gSeed = 0xD1A57AB1u;
static uint32_t NextRand(void) {
    gSeed = gSeed * 1664525u + 1013904223u;
    return gSeed;
}

static void TestPermutationAndPauseStress(void) {
    ResetAllPatchesOff();
    NSArray<NSString *> *stressKeys = @[
        @"hideToolbar", @"showAddressField", @"hideChatButton", @"turnOffAI",
        @"hideTrafficLights", @"compactSidebarHeader", @"windowCorners", @"edgeToEdge",
        @"squareSidebarCorners", @"profileColorPicker", @"privateWindowTheme",
        @"windowMaterial", @"translucentSidebar", @"hidePinnedTabBorder",
        @"hideTabGroupBackground", @"unloadTab", @"groupTabsByDomain",
        @"collapsePinned", @"compactTabRows", @"commandBar", @"peek"
    ];

    @autoreleasepool {
        NSArray *normalDia = @[ (id)NSColor.systemBlueColor.CGColor, (id)NSColor.systemTealColor.CGColor ];
        NSArray *privDia = @[ (id)NSColor.systemIndigoColor.CGColor, (id)NSColor.systemPurpleColor.CGColor ];
        DPMockWindowBundle *norm = BuildMockWindow(NO, YES, @"space-stress", normalDia);
        DPMockWindowBundle *priv = BuildMockWindow(YES, YES, nil, privDia);
        gMockWindows = @[ norm.window, priv.window ];
        gMockKeyWindow = norm.window;

        [DPHideHosts addObject:norm.toolbar];
        [DPHideHosts addObject:norm.sidebarHeader];
        DPSetProfileHexForSpace(@"space-stress", @"#3B82F6");

        DPCombTabListView *tabList = [[objc_getClass(DPDiaTabList) alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
        DPCombCollectionView *collection = [[objc_getClass(DPDiaTabListCollection) alloc] initWithFrame:tabList.bounds];
        collection.pinnedCount = 2;
        collection.regularCount = 2;
        DPCombTabListLayout *layout = [objc_getClass(DPDiaTabListLayout) new];
        collection.collectionViewLayout = layout;
        [tabList addSubview:collection];
        [norm.sidebarBody addSubview:tabList];

        DPCombTabView *tabView = [[objc_getClass(DPDiaTabView) alloc] initWithFrame:NSMakeRect(0, 0, 180, 32)];
        NSMenu *reusedMenu = [[NSMenu alloc] initWithTitle:@"Stress"];
        [reusedMenu addItemWithTitle:@"New Group with 2 Tabs" action:nil keyEquivalent:@""];
        [reusedMenu addItemWithTitle:@"Chat with this tab" action:nil keyEquivalent:@""];
        [reusedMenu addItemWithTitle:@"Close Tab" action:nil keyEquivalent:@""];
        tabView.reusedMenu = reusedMenu;
        [norm.sidebarBody addSubview:tabView];

        for (int iter = 0; iter < 60; iter++) {
            for (NSString *key in stressKeys) {
                if ((NextRand() & 3u) == 0) {
                    DPPatch *p = DPPatchNamed(key);
                    if (p) SetPatchImmediate(key, !p->on, YES);
                }
            }
            [norm.sidebarController viewWillLayout];
            [norm.sidebarHeader layout];
            [norm.pane layout];
            [norm.addressField layout];
            [norm.container layout];
            [norm.themeFrame layout];
            [norm.floatingSidebar layout];
            [norm.gradientView updateLayer];
            [priv.gradientView updateLayer];
            [layout prepareLayout];
            [tabView menuForEvent:MakeRightClick(norm.window)];

            if ((iter % 15) == 14) {
                DPSetTweaksPaused(YES, nil);
                [norm.sidebarController viewWillLayout];
                [norm.sidebarHeader layout];
                [norm.pane layout];
                [norm.container layout];
                Check(norm.window.fakeCornerRadius == 10, @"stress pause: window radius restored");
                Check([norm.gradientLayer.colors isEqual:normalDia], @"stress pause: normal tint restored");
                Check([priv.gradientLayer.colors isEqual:privDia], @"stress pause: private tint restored");
                Check(!norm.washView.hidden && norm.window.opaque, @"stress pause: window material restored");
                Check(!norm.chatButton.hidden && !norm.trafficLights.hidden, @"stress pause: hidden views restored");
                DPSetTweaksPaused(NO, nil);
            }
        }

        DPSetProfileHexForSpace(@"space-stress", nil);
        ResetAllPatchesOff();
        DPPeekCloseAll();
        [norm.window close];
        [priv.window close];
        gMockWindows = nil;
        gMockKeyWindow = nil;
    }
    DPDrainMainQueue(0.05);
    Check(YES, @"60-iteration multi-cluster permutation stress + teardown completed cleanly under ASan/UBSan");
}

#pragma mark - Main

int main(void) {
    @autoreleasepool {
        unsetenv("DIATWEAKS_DOMAIN");
        [NSApplication sharedApplication];
        DPArmTestWatchdog(120);
        DPTesting = YES;
        gLittleDiaWindows = [NSHashTable weakObjectsHashTable];
        gLittleDiaOpenedLinks = [NSMutableArray array];
        gHiddenTabIDs = [NSMutableSet set];

        // Isolate NSUserDefaults and SafeMode pause file to scratch storage.
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_combInitWithSuiteName:)));
        NSString *scratchDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dp-comb-%d-%@", getpid(), NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:scratchDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *fakeDylib = [scratchDir stringByAppendingPathComponent:@"DiaPatches.dylib"];
        DPTestDylibPath = fakeDylib.fileSystemRepresentation;
        setenv("DIAPATCH_HOME", [scratchDir stringByAppendingPathComponent:@"home"].fileSystemRepresentation, 1);

        // Capture all installed local key monitors so overlay priority tests exercise the real monitor chain.
        Class eventMeta = object_getClass(NSEvent.class);
        DPHookClass(eventMeta, @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)DPEvent_addLocalMonitor);
        DPHookClass(eventMeta, @selector(removeMonitor:), (IMP)DPEvent_removeMonitor);
        // Keep the host's real pointer and held mouse buttons out of every hover check.
        DPHookClass(eventMeta, @selector(mouseLocation), (IMP)DPEvent_mouseLocation);
        DPHookClass(eventMeta, @selector(pressedMouseButtons), (IMP)DPEvent_pressedMouseButtons);

        // Stub NSMenu popup presentation before patches hook it, so popup tests never block headless runs.
        Class menuMeta = object_getClass(NSMenu.class);
        DPHookClass(menuMeta, @selector(popUpContextMenu:withEvent:forView:), (IMP)DPNoOpPopUpContext);
        DPHookClass(NSMenu.class, @selector(popUpMenuPositioningItem:atLocation:inView:), (IMP)DPNoOpPopUpAt);

        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        DPHookClass(NSApp.class, @selector(orderedWindows), (IMP)DPApp_orderedWindows);
        DPHookClass(NSApp.class, @selector(keyWindow), (IMP)DPApp_keyWindow);

        NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
        NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
        [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
        [fileMenu addItemWithTitle:@"Open Command Bar" action:@selector(openBar:) keyEquivalent:@"l"];
        [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeTab:) keyEquivalent:@"w"];
        fileItem.submenu = fileMenu;
        NSMenuItem *tabItem = [[NSMenuItem alloc] initWithTitle:@"Tabs" action:nil keyEquivalent:@""];
        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@"Tabs"];
        [tabMenu addItemWithTitle:@"New Group with 1 Tab" action:nil keyEquivalent:@""];
        tabItem.submenu = tabMenu;
        [mainMenu addItem:fileItem];
        [mainMenu addItem:tabItem];
        NSApp.mainMenu = mainMenu;

        RegisterAllMockDiaClasses();
        DPBeginLaunch();
        DPLoadPatches();
        DPInstallPatches();
        // Install sub-patch hooks whose parent patch wrappers aren't linked, in production outer order.
        DPInstallFrozenLists();
        DPInstallLittleDiaLinkMenu();
        [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidFinishLaunchingNotification object:NSApp];

        Check(DPPatchCount >= 25, [NSString stringWithFormat:@"registered %lu real patches for combinatorial testing", (unsigned long)DPPatchCount]);

        DPRunTest(TestHookChainsAndDPIsHooked);
        DPRunTest(TestClusterAToolbarChrome);
        DPRunTest(TestClusterBThemeMaterialTint);
        DPRunTest(TestClusterCMenusOverlaysAndLayout);
        DPRunTest(TestClusterDLaunchFlagsAndCoveredTweaks);
        DPRunTest(TestPermutationAndPauseStress);

        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:DPCombSuiteName()];
        [NSFileManager.defaultManager removeItemAtPath:scratchDir error:nil];
    }
    if (gFailures) {
        printf("FAIL: %d combinatorial stability check(s) failed\n", gFailures);
        return 1;
    }
    puts("PASS: combinatorial stability (Clusters A-D, hook chains, menus, priority, Pause Tweaks, and 60-iter stress)");
    return 0;
}

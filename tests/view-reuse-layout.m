#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "StdPatch/StdPatch.h"
#import "StdPatch/Hide.h"
#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import "Patches/HideVerticalTabGlow/HideVerticalTabGlow.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import "Patches/PullRequestRepo/PullRequestRepo.h"
#import "Patches/CompactTabRows/CompactTabRows.h"
#import "Patches/TidyTabs/TidyTabs.h"
#import "Patches/SidebarGrain/SidebarGrain.h"
#import "Patches/CompactCommandBar/CompactCommandBar.h"
#import "Patches/LittleDia/LittleDia.h"
#import "Patches/TurnOffAI/TurnOffAI.h"
#import "watchdog.h"

BOOL DPTesting = YES;

extern DPPatch DPWindowMaterial, DPTranslucentSidebar, DPCollapsePinned, DPHideTabGroupBackground;
extern DPPatch DPProfileEmoji, DPCompactTabRows, DPCompactWithChat;

static NSString *DPTestSuiteName(void) {
    return [NSString stringWithFormat:@"com.diapatches.view-reuse-layout.%d", getpid()];
}

@interface NSUserDefaults (DPViewReuseTestSuite)
- (instancetype)dp_vrInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPViewReuseTestSuite)
- (instancetype)dp_vrInitWithSuiteName:(NSString *)suite {
    return [self dp_vrInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPTestSuiteName() : suite];
}
@end

DPPatch DPTranslucentSidebar, DPCompactWithChat, DPLittleDia, DPLittleDiaRemember;
DPPatch DPHideToolbar, DPShowLoadingProgress;
NSHashTable<NSView *> *DPPanes;
NSHashTable<NSView *> *DPHideHosts;

static NSString *gMaterialChoice = @"material.7";
static NSString *gCompactChoice = @"small";
static NSArray<NSWindow *> *gFakeWindows;
static int gGrainRefreshes, gToolbarApplyCalls, gProgressDrawCalls;

static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gFakeWindows ?: @[]; }
static NSArray<NSWindow *> *DPApp_orderedWindows(NSApplication *self, SEL _cmd) { return gFakeWindows ?: @[]; }

void DPOnLaunch(void (^block)(void)) {}
NSString *DPChoice(DPPatch *patch) {
    if (patch == &DPWindowMaterial) return gMaterialChoice;
    if (patch == &DPCompactTabRows) return gCompactChoice;
    return patch->defaultChoice;
}
NSMenuItem *DPMenuItem(NSString *title, void (^action)(void)) { return [[NSMenuItem alloc] initWithTitle:title ?: @"" action:nil keyEquivalent:@""]; }
void DPSetHint(NSView *view, NSString *text) {}
void DPShowHint(NSView *view) {}
void DPTidyTabsNow(NSWindow *window) {}
NSString *DPTidyUnavailableReason(void) { return nil; }
void DPTrackGrainHost(NSView *host) {}
void DPRefreshSidebarGrain(void) { gGrainRefreshes++; }
void DPRefreshSidebarGrainFrames(void) {}
NSEvent *DPGrainRightClick(NSEvent *event) { return event; }
NSMenu *DPGrainTextureMenu(void) { return [NSMenu new]; }
NSString *DPVerifyGrainHosts(DPPatch *patch) { return nil; }
NSArray<NSView *> *DPGrainRows(void) { return @[]; }
NSView *DPBookmarksUnder(NSView *pane, NSView *bar) { return nil; }
void DPApplyToolbar(NSView *pane) { gToolbarApplyCalls++; }
CAMetalLayer *DPProgressShaderLayer(void) { return nil; }
void DPProgressColors(NSView *pane, NSString *choice, simd_float3 *primary, simd_float3 *secondary) {}
void DPDrawProgressShader(CAMetalLayer *layer, CGFloat progress, CGFloat cycle, simd_float3 primary, simd_float3 secondary) { gProgressDrawCalls++; }
void DPEnforceHides(NSView *host) {}
void DPApplyHides(DPPatch *patch) {}
void DPDismissConnectAppPrompts(void) {}
BOOL DPIsSingleAppUpsellBar(NSView *view) { return NO; }
void DPAddLaunchFlag(NSString *flag) {}
void DPDropLaunchFlag(NSString *flag) {}
BOOL DPSavedOn(DPPatch *patch) { return NO; }
BOOL DPAnimating(void) { return NO; }
void DPHandOffAndQuit(NSArray<NSString *> *args) {}
BOOL DPShortcutRecording(void) { return NO; }
void DPRestoreStack(NSWindow *little, NSDictionary *noted) {}
NSArray<NSDictionary *> *DPWindowStack(void) { return @[]; }
void DPReturnToSource(pid_t pid, NSWindow *little, NSArray<NSDictionary *> *stack) {}
void DPBringBackPutAway(NSWindow *little) {}
BOOL DPHideAgain(void) { return NO; }
void DPInstallLittleDiaStack(void) {}
void DPSaveLittleDiaFrame(NSRect frame) {}
BOOL DPSendToLittleDia(NSDictionary *request) { return NO; }
NSDictionary *DPLittleDiaTab(NSWindow *window, NSString *action) { return nil; }
NSString *DPLittleDiaURL(NSWindow *window) { return @"https://example.com"; }
void DPLittleDiaGo(NSWindow *window, SEL action) {}
void DPLittleDiaNavigate(NSWindow *window, NSString *typed) {}
NSArray<NSString *> *DPLittleDiaProfiles(void) { return @[@"Personal", @"Work"]; }
NSImage *DPLittleDiaProfileImage(NSString *name) { return nil; }
NSString *DPOpenInLabel(NSString *profile, NSUInteger profiles) { return @"Open in Dia"; }
void DPOpenInProfile(NSString *url, NSUInteger index, void (^done)(BOOL opened)) {}
id DPMsg(id object, SEL sel) { return nil; }
NSString *DPText(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }

static int failures;
static void Check(BOOL ok, NSString *msg) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", msg.UTF8String);
}

static void DrainMain(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!done && until.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

@interface DPActionCheckLayer : CALayer
@property NSInteger mutations, unguardedMutations;
@end
@implementation DPActionCheckLayer
- (void)recordMutation {
    self.mutations++;
    if (![CATransaction disableActions]) self.unguardedMutations++;
}
- (void)setHidden:(BOOL)hidden { [self recordMutation]; [super setHidden:hidden]; }
- (void)setBackgroundColor:(CGColorRef)backgroundColor { [self recordMutation]; [super setBackgroundColor:backgroundColor]; }
- (void)setBorderWidth:(CGFloat)borderWidth { [self recordMutation]; [super setBorderWidth:borderWidth]; }
- (void)setOpacity:(float)opacity { [self recordMutation]; [super setOpacity:opacity]; }
@end

@interface _TtC6Window14PlatformWindow : NSWindow
@property CGFloat fakeCornerRadius;
@property BOOL fakeVisible, fakeMiniaturized;
@property NSWindowStyleMask fakeStyleMask;
@property BOOL useFakeStyleMask;
@end
@implementation _TtC6Window14PlatformWindow
- (CGFloat)_cornerRadius { return self.fakeCornerRadius; }
- (void)_setCornerRadius:(CGFloat)r { self.fakeCornerRadius = r; }
- (void)_updateWindowCornerMask {}
- (BOOL)isVisible { return self.fakeVisible; }
- (BOOL)isMiniaturized { return self.fakeMiniaturized; }
- (NSWindowStyleMask)styleMask { return self.useFakeStyleMask ? self.fakeStyleMask : [super styleMask]; }
- (void)setStyleMask:(NSWindowStyleMask)mask {
    if (self.useFakeStyleMask) self.fakeStyleMask = mask;
    else [super setStyleMask:mask];
}
@end

@interface _TtC6Window24PlatformWindowThemeFrame : NSView
@property NSInteger subviewChanges;
@end
@implementation _TtC6Window24PlatformWindowThemeFrame
- (void)layout {}
@end

@interface _TtC15WindowTreatment31WindowBackgroundOverlayTintView : NSView
@end
@implementation _TtC15WindowTreatment31WindowBackgroundOverlayTintView
@end

@interface _TtC5ARCUI19BackgroundColorView : NSView
@property NSInteger hiddenCalls;
@property CGColorRef diaBG;
@end
@implementation _TtC5ARCUI19BackgroundColorView
- (void)setHidden:(BOOL)hidden { self.hiddenCalls++; [super setHidden:hidden]; }
- (void)updateLayer { self.layer.backgroundColor = self.diaBG; }
@end

@interface _TtC15WindowTreatment24WindowBackgroundBaseView : NSView
@end
@implementation _TtC15WindowTreatment24WindowBackgroundBaseView
- (void)updateLayer {}
@end

@interface _TtGC5ARCUI25WindowFrameBackgroundViewC15WindowTreatment24WindowBackgroundBaseView_ : NSView
@end
@implementation _TtGC5ARCUI25WindowFrameBackgroundViewC15WindowTreatment24WindowBackgroundBaseView_
@end

@interface _TtC6Window28FloatingSidebarContainerView : NSView
@end
@implementation _TtC6Window28FloatingSidebarContainerView
- (void)layout {}
@end

@interface _TtC6Window20ContentContainerView : NSView {
@public
    CGFloat cornerRadius;
}
@property NSInteger frameWrites;
@end
@implementation _TtC6Window20ContentContainerView
- (void)setFrame:(NSRect)frame { self.frameWrites++; [super setFrame:frame]; }
- (void)layout {}
- (void)updateLayer {}
@end

@interface _TtC5ARCUI10ShadowView : NSView
@end
@implementation _TtC5ARCUI10ShadowView
- (void)layout {}
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
- (void)layout {}
@end

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
- (BOOL)isFlipped { return YES; }
@end

@interface _TtC10TabSidebar15SidebarRootView : NSView
@end
@implementation _TtC10TabSidebar15SidebarRootView
@end

@interface _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView : NSView
@end
@implementation _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView
@end

@interface _TtC5TabUI7TabView : NSView
@end
@implementation _TtC5TabUI7TabView
@end

@interface _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView : NSView {
@public
    CALayer *$__lazy_storage_$_shadowLayer;
    CAGradientLayer *$__lazy_storage_$_gradientBorderLayer;
    NSView *rimHighlightView;
    uint8_t shape;
}
@end
@implementation _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView
- (void)layout {}
@end

@interface _TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView : NSView
@end
@implementation _TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView
@end

@interface _TtC5TabUI16TabGroupCellView : NSView
@end
@implementation _TtC5TabUI16TabGroupCellView
- (void)layout {}
- (void)updateLayer {}
@end

@interface _TtC10TabSidebar17SidebarHeaderView : NSView
@end
@implementation _TtC10TabSidebar17SidebarHeaderView
- (void)layout {}
@end

@interface _TtC10TabSidebar26SidebarContainerFooterView : NSView
@end
@implementation _TtC10TabSidebar26SidebarContainerFooterView
- (void)layout {}
@end

@interface _TtC10TabSidebar17SpaceSwitcherView : NSView
@property NSDictionary *itemViews;
@end
@implementation _TtC10TabSidebar17SpaceSwitcherView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPTrackingDot : NSView
@property NSInteger originWrites;
@end
@implementation DPTrackingDot
- (void)setFrameOrigin:(NSPoint)newOrigin { self.originWrites++; [super setFrameOrigin:newOrigin]; }
@end

@interface _TtC10TabSidebar21SpaceSwitcherItemView : NSView
@property BOOL isSelected;
@property DPTrackingDot *dot;
@property NSInteger subviewAdds, subviewRemovals;
@end
@implementation _TtC10TabSidebar21SpaceSwitcherItemView
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqual:@"isSelected"]) return @(self.isSelected);
    if ([key isEqual:@"$__lazy_storage_$_dotView"]) return self.dot;
    return nil;
}
- (void)addSubview:(NSView *)view { self.subviewAdds++; [super addSubview:view]; }
- (void)willRemoveSubview:(NSView *)subview { self.subviewRemovals++; [super willRemoveSubview:subview]; }
- (void)layout {}
- (void)updateLayer {}
@end

@interface _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView : NSView
@property BOOL isSelected;
@end
@implementation _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"isSelected"] ? @(self.isSelected) : nil; }
- (void)layout {}
- (void)updateLayer {}
@end

@interface _TtC5ARCUI24FeatheredTruncatingLabel : NSTextField
@end
@implementation _TtC5ARCUI24FeatheredTruncatingLabel
- (void)layout {}
@end

@interface _TtC5ARCUI27FeatheredTransitioningLabel : NSView
@end
@implementation _TtC5ARCUI27FeatheredTransitioningLabel
@end

@interface DPFakePRDelegate : NSObject
@property (copy) NSString *currentlyRenderedLiveItem, *tabID;
@end
@implementation DPFakePRDelegate
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakePRVM : NSObject
@property DPFakePRDelegate *delegate;
@end
@implementation DPFakePRVM
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface _TtC5TabUI14TabContentView : NSView {
@public
    NSView *$__lazy_storage_$_titleView;
    NSView *subtitleView;
    NSView *subtitleIconView;
}
@property DPFakePRVM *viewModel;
@end
@implementation _TtC5TabUI14TabContentView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (void)layout {}
@end

@interface DPFakeDiffableImpl : NSObject
@property NSArray<NSString *> *identifiers;
@end
@implementation DPFakeDiffableImpl
- (id)itemIdentifierForIndexPath:(NSIndexPath *)path {
    return path.item < (NSInteger)self.identifiers.count ? self.identifiers[path.item] : nil;
}
@end

@interface DPFakeDiffableDS : NSObject <NSCollectionViewDataSource> {
@public
    DPFakeDiffableImpl *_impl;
}
@end
@implementation DPFakeDiffableDS
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)cv { return 1; }
- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section { return _impl.identifiers.count; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip { return [NSCollectionViewItem new]; }
@end

@interface _TtC7TabList27TabListCollectionViewLayout : NSCollectionViewLayout {
@public
    double contentHeight;
}
@property NSArray<NSCollectionViewLayoutAttributes *> *cachedAttributes;
@end
@implementation _TtC7TabList27TabListCollectionViewLayout
- (void)prepareLayout {}
- (NSSize)collectionViewContentSize { return NSMakeSize(200, contentHeight); }
- (NSArray<NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect { return self.cachedAttributes ?: @[]; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    return path.item < (NSInteger)self.cachedAttributes.count ? self.cachedAttributes[path.item] : nil;
}
@end

@interface _TtCC7TabList11TabListView14CollectionView : NSCollectionView
@end
@implementation _TtCC7TabList11TabListView14CollectionView
@end

@interface _TtC7TabList11TabListView : NSView
@end
@implementation _TtC7TabList11TabListView
- (void)layout {}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (void)draggingExited:(id<NSDraggingInfo>)info {}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (void)handleBackgroundDoubleClick:(NSGestureRecognizer *)click {}
@end

@interface _TtC7TabList20TabListSeparatorView : NSView
@property NSInteger subviewAdds, subviewRemovals;
@end
@implementation _TtC7TabList20TabListSeparatorView
- (void)addSubview:(NSView *)view { self.subviewAdds++; [super addSubview:view]; }
- (void)willRemoveSubview:(NSView *)subview { self.subviewRemovals++; [super willRemoveSubview:subview]; }
- (void)layout {}
- (void)updateLayer {}
@end

@interface _TtC15BoostCommandBar8RootView : NSView
@end
@implementation _TtC15BoostCommandBar8RootView
- (void)layout {}
@end

@interface _TtC15BoostCommandBar18InputContainerView : NSView
@end
@implementation _TtC15BoostCommandBar18InputContainerView
- (void)layout {}
@end

@interface _TtC15BoostCommandBar17TextContainerView : NSView
@end
@implementation _TtC15BoostCommandBar17TextContainerView
@end

@interface _TtC15BoostCommandBar15SuggestionsView : NSView
@end
@implementation _TtC15BoostCommandBar15SuggestionsView
@end

@interface _TtC15BoostCommandBar11ToolbarView : NSView
@end
@implementation _TtC15BoostCommandBar11ToolbarView
@end

@interface _TtC15BoostCommandBar13ToolbarButton : NSView
@end
@implementation _TtC15BoostCommandBar13ToolbarButton
- (void)layout {}
@end

@interface _TtC20AssistantPanelUIBase22AssistantPanelRootView : NSView
@end
@implementation _TtC20AssistantPanelUIBase22AssistantPanelRootView
@end

@interface _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView : NSView
@end
@implementation _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView
@end

@interface _TtC5Popup19PlatformPopupWindow : _TtC6Window14PlatformWindow
@end
@implementation _TtC5Popup19PlatformPopupWindow
@end

@interface _TtC5Popup22PopupNavigationBarView : NSView
@end
@implementation _TtC5Popup22PopupNavigationBarView
@end

@interface _TtC13NavigationBar21AssistantBarTitleView : NSView
@end
@implementation _TtC13NavigationBar21AssistantBarTitleView
@end

@interface _TtC11Preferences15SidebarListView : NSObject <NSTableViewDelegate, NSTableViewDataSource>
@property NSArray<NSString *> *titles;
@end
@implementation _TtC11Preferences15SidebarListView
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.titles.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    return [NSTextField labelWithString:self.titles[row]];
}
@end

@interface DPTrackingMenuItem : NSMenuItem
@property NSInteger hiddenCalls;
@end
@implementation DPTrackingMenuItem
- (void)setHidden:(BOOL)hidden { self.hiddenCalls++; [super setHidden:hidden]; }
@end

typedef struct CACornerRadii { CGSize topLeft, topRight, bottomRight, bottomLeft; } CACornerRadii;

@interface CALayer (DPTestCornerRadii)
@property CACornerRadii cornerRadii;
@property (readonly) BOOL _usesCornerRadii;
@end

// Stands in for releases that keep _usesCornerRadii on all-zero radii, or refuse to store them at all.
@interface DPKeptRadiiLayer : CALayer
@property BOOL refusesZero;
@end
@implementation DPKeptRadiiLayer {
    CACornerRadii _radii;
    BOOL _uses;
}
- (BOOL)_usesCornerRadii { return _uses; }
- (CACornerRadii)cornerRadii { return _radii; }
- (void)setCornerRadii:(CACornerRadii)radii {
    CACornerRadii zero = {0};
    if (self.refusesZero && !memcmp(&radii, &zero, sizeof radii)) return;
    _radii = radii;
    _uses = YES;
}
@end

@interface DPKeptRadiiView : NSView
@property BOOL refusesZero;
@end
@implementation DPKeptRadiiView
- (CALayer *)makeBackingLayer {
    DPKeptRadiiLayer *layer = [DPKeptRadiiLayer layer];
    layer.refusesZero = self.refusesZero;
    return layer;
}
@end

// All-zero radii, or radii equal to cornerRadius, draw the plain rounded rect, so neither overrides it.
static BOOL OverridesCornerRadius(CALayer *layer) {
    if (![layer respondsToSelector:@selector(_usesCornerRadii)] || !layer._usesCornerRadii) return NO;
    CACornerRadii radii = layer.cornerRadii;
    CGSize corners[4] = { radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft };
    BOOL zero = YES, plain = YES;
    for (int i = 0; i < 4; i++) {
        zero &= CGSizeEqualToSize(corners[i], CGSizeZero);
        plain &= corners[i].width == layer.cornerRadius && corners[i].height == layer.cornerRadius;
    }
    return !zero && !plain;
}

static void TestEdgeToEdgeOffAndRestore(void) {
    DPEdgeToEdge.on = NO;
    DPEdgeToEdge.progress = 0;
    DPWindowCorners.on = NO;
    DPSquareSidebarCorners.on = YES;
    DPSquareSidebarCorners.progress = 1;

    _TtC6Window14PlatformWindow *win = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 900, 600)
                                                                                     styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    win.fakeCornerRadius = 16;
    win.fakeVisible = YES;
    gFakeWindows = @[ win ];

    _TtC6Window20ContentContainerView *container = [[_TtC6Window20ContentContainerView alloc] initWithFrame:NSMakeRect(220, 6, 674, 588)];
    container->cornerRadius = 10;
    NSView *rounded = [[NSView alloc] initWithFrame:container.bounds];
    rounded.wantsLayer = YES;
    rounded.layer.masksToBounds = YES;
    rounded.layer.cornerRadius = 10;
    rounded.layer.cornerCurve = kCACornerCurveCircular;

    _TtC13NavigationBar17NavigationBarView *bar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 548, 674, 40)];
    NSView *cornerBtn = [[NSView alloc] initWithFrame:NSMakeRect(4, 8, 28, 28)];
    cornerBtn.wantsLayer = YES;
    cornerBtn.layer.cornerRadius = 6;
    [bar addSubview:cornerBtn];
    [rounded addSubview:bar];

    NSView *chatRoot = [[NSView alloc] initWithFrame:rounded.bounds];
    NSView *chatHost = [[NSView alloc] initWithFrame:NSMakeRect(340, 10, 320, 500)];
    chatHost.wantsLayer = YES;
    chatHost.layer.masksToBounds = YES;
    chatHost.layer.cornerRadius = 10;
    chatHost.layer.cornerCurve = kCACornerCurveCircular;
    [chatRoot addSubview:chatHost];
    [rounded addSubview:chatRoot];
    chatHost.hidden = YES;

    NSView *borderHost = [[NSView alloc] initWithFrame:container.bounds];
    borderHost.wantsLayer = YES;
    CAShapeLayer *shape = [CAShapeLayer layer];
    CGPathRef origPath = CGPathCreateWithRoundedRect(CGRectMake(0, 0, 674, 588), 10, 10, NULL);
    shape.path = origPath;
    [borderHost.layer addSublayer:shape];

    [container addSubview:rounded];
    [container addSubview:borderHost];
    [win.contentView addSubview:container];

    container.frame = NSMakeRect(220, 6, 674, 588);
    [container layout];
    [container updateLayer];
    DrainMain();
    Check(rounded.layer.cornerCurve == kCACornerCurveCircular, @"EdgeToEdge off: leaves cornerCurve untouched");
    Check(![rounded.layer respondsToSelector:@selector(_usesCornerRadii)] || !rounded.layer._usesCornerRadii,
          @"EdgeToEdge off: does not set private cornerRadii");
    Check(container->cornerRadius == 10, @"EdgeToEdge off: leaves cornerRadius ivar untouched");
    Check(CGPathEqualToPath(shape.path, origPath), @"EdgeToEdge off: leaves shape path untouched");

    DPEdgeToEdge.on = YES;
    DPEdgeToEdge.progress = 1;
    chatHost.hidden = YES;
    container.frame = NSMakeRect(220, 6, 674, 588);
    chatHost.hidden = NO;
    container.frameWrites = 0;
    [container updateLayer];
    Check(container.frameWrites == 0, @"EdgeToEdge: updateLayer does not synchronously call container.frame =");
    DrainMain();
    Check(container.frameWrites >= 1, @"EdgeToEdge: deferred restyle restores frame cleanly off updateLayer");

    chatHost.hidden = YES;
    container.frame = NSMakeRect(220, 6, 674, 588);
    [container layout];
    Check(rounded.layer.cornerCurve == kCACornerCurveContinuous, @"EdgeToEdge on: sets continuous cornerCurve");
    Check(!DPCornersRound(rounded.layer, NO) && DPCornersRound(rounded.layer, YES), @"EdgeToEdge on: squares left corners beside sidebar");
    Check(container->cornerRadius > 10, @"EdgeToEdge on: grows cornerRadius ivar");

    DPEdgeToEdge.on = NO;
    DPEdgeToEdge.progress = 0;
    DPEdgeToEdge.relayout();
    Check(rounded.layer.cornerCurve == kCACornerCurveCircular, @"EdgeToEdge off: restores original cornerCurve");
    Check(!OverridesCornerRadius(rounded.layer), @"EdgeToEdge off: leaves no cornerRadii override");
    Check(DPCornersRound(rounded.layer, NO) && DPCornersRound(rounded.layer, YES), @"EdgeToEdge off: all corners round again");
    Check(container->cornerRadius == 10, @"EdgeToEdge off: restores cornerRadius ivar to 10");
    Check(CGPathEqualToPath(shape.path, origPath), @"EdgeToEdge off: restores original shape path");
    CGPathRelease(origPath);
}

static void TestEdgeToEdgeOffWithKeptCornerRadii(void) {
    DPEdgeToEdge.on = YES;
    DPEdgeToEdge.progress = 1;
    DPWindowCorners.on = NO;
    DPSquareSidebarCorners.on = YES;
    DPSquareSidebarCorners.progress = 1;

    for (int refuses = 0; refuses < 2; refuses++) {
        NSString *mode = refuses ? @"refused zero radii" : @"kept _usesCornerRadii";
        _TtC6Window14PlatformWindow *win = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 900, 600)
                                                                                         styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        win.fakeCornerRadius = 16;
        win.fakeVisible = YES;
        gFakeWindows = @[ win ];

        _TtC6Window20ContentContainerView *container = [[_TtC6Window20ContentContainerView alloc] initWithFrame:NSMakeRect(220, 6, 674, 588)];
        container->cornerRadius = 10;
        DPKeptRadiiView *rounded = [[DPKeptRadiiView alloc] initWithFrame:container.bounds];
        rounded.refusesZero = refuses;
        rounded.wantsLayer = YES;
        rounded.layer.masksToBounds = YES;
        rounded.layer.cornerRadius = 10;
        [container addSubview:rounded];
        [win.contentView addSubview:container];

        DPEdgeToEdge.on = YES;
        DPEdgeToEdge.progress = 1;
        container.frame = NSMakeRect(220, 6, 674, 588);
        [container layout];
        Check(!DPCornersRound(rounded.layer, NO) && DPCornersRound(rounded.layer, YES),
              [NSString stringWithFormat:@"%@: EdgeToEdge on squares the left corners", mode]);

        DPEdgeToEdge.on = NO;
        DPEdgeToEdge.progress = 0;
        DPEdgeToEdge.relayout();
        Check(DPCornersRound(rounded.layer, NO) && DPCornersRound(rounded.layer, YES),
              [NSString stringWithFormat:@"%@: EdgeToEdge off rounds every corner again", mode]);
        Check(!OverridesCornerRadius(rounded.layer),
              [NSString stringWithFormat:@"%@: EdgeToEdge off leaves no cornerRadii override", mode]);
        [container removeFromSuperview];
    }
}

static void TestWindowMaterialUpdateLayerAndIdempotency(void) {
    _TtC6Window14PlatformWindow *win = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                     styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    win.fakeVisible = YES;
    gFakeWindows = @[ win ];

    _TtC6Window28FloatingSidebarContainerView *host = [[_TtC6Window28FloatingSidebarContainerView alloc] initWithFrame:NSMakeRect(0, 0, 240, 400)];
    NSView *content = [[NSView alloc] initWithFrame:host.bounds];
    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:host.bounds];
    effect.material = NSVisualEffectMaterialUnderWindowBackground;
    _TtC15WindowTreatment31WindowBackgroundOverlayTintView *tint = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:host.bounds];
    _TtC5ARCUI19BackgroundColorView *wash = [[_TtC5ARCUI19BackgroundColorView alloc] initWithFrame:host.bounds];
    _TtC15WindowTreatment24WindowBackgroundBaseView *tile = [[_TtC15WindowTreatment24WindowBackgroundBaseView alloc] initWithFrame:host.bounds];
    [tint addSubview:wash];
    [tint addSubview:tile];
    [content addSubview:effect];
    [content addSubview:tint];
    [host addSubview:content];
    [win.contentView addSubview:host];

    DPWindowMaterial.on = YES;
    gMaterialChoice = @"material.7";

    wash.hiddenCalls = 0;
    [tile updateLayer];
    [tile updateLayer];
    [tile updateLayer];
    Check(!wash.hidden && wash.hiddenCalls == 0, @"WindowMaterial: tile updateLayer does not synchronously call setHidden:");

    DrainMain();
    Check(wash.hidden && wash.hiddenCalls == 1 && effect.material == NSVisualEffectMaterialSidebar,
          @"WindowMaterial: deferred coalesced updateLayer applies material and hides wash once");

    wash.hiddenCalls = 0;
    for (int i = 0; i < 10; i++) [host layout];
    Check(wash.hidden && wash.hiddenCalls == 0, @"WindowMaterial: repeated layout makes 0 redundant setHidden: calls");

    DPWindowMaterial.on = NO;
    DPWindowMaterial.apply(&DPWindowMaterial);
    Check(!wash.hidden && effect.material == NSVisualEffectMaterialUnderWindowBackground,
          @"WindowMaterial: turning off restores wash and material");
}

static void TestPullRequestRepoAndCompactTabRows(void) {
    _TtC6Window14PlatformWindow *win = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 300, 500)
                                                                                     styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    win.fakeVisible = NO;
    gFakeWindows = @[ win ];

    _TtC7TabList11TabListView *tabList = [[_TtC7TabList11TabListView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
    _TtCC7TabList11TabListView14CollectionView *cv = [[_TtCC7TabList11TabListView14CollectionView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
    _TtC7TabList27TabListCollectionViewLayout *layout = [_TtC7TabList27TabListCollectionViewLayout new];
    DPFakeDiffableDS *ds = [DPFakeDiffableDS new];
    ds->_impl = [DPFakeDiffableImpl new];
    NSString *uuidA = @"AAAAAAAA-1111-1111-1111-111111111111";
    NSString *uuidB = @"BBBBBBBB-2222-2222-2222-222222222222";
    NSString *uuidC = @"CCCCCCCC-3333-3333-3333-333333333333";
    ds->_impl.identifiers = @[
        [NSString stringWithFormat:@".tab(%@)", uuidA],
        [NSString stringWithFormat:@".tab(%@)", uuidB],
        [NSString stringWithFormat:@".tab(%@)", uuidC],
    ];
    cv.dataSource = ds;
    cv.collectionViewLayout = layout;
    [tabList addSubview:cv];

    // Cached layout attributes reused across prepareLayout calls (simulating Dia's layout cache)
    NSMutableArray<NSCollectionViewLayoutAttributes *> *attrs = [NSMutableArray new];
    for (NSInteger i = 0; i < 3; i++) {
        NSCollectionViewLayoutAttributes *a = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
        a.frame = NSMakeRect(0, i * 37, 220, 37);
        [attrs addObject:a];
    }
    layout.cachedAttributes = attrs;
    layout->contentHeight = 111;

    _TtC5TabUI14TabContentView *content = [[_TtC5TabUI14TabContentView alloc] initWithFrame:NSMakeRect(0, 0, 220, 51)];
    DPFakePRVM *vm = [DPFakePRVM new];
    vm.delegate = [DPFakePRDelegate new];
    vm.delegate.tabID = uuidA;
    vm.delegate.currentlyRenderedLiveItem = @".pullRequest(url: https://github.com/org/repo/pull/1, author: \"alice\", status: PullRequest.Status.open)";
    content.viewModel = vm;
    NSTextField *titleView = [NSTextField labelWithString:@"PR #1"];
    titleView.frame = NSMakeRect(30, 30, 160, 16);
    _TtC5ARCUI27FeatheredTransitioningLabel *subWrap = [[_TtC5ARCUI27FeatheredTransitioningLabel alloc] initWithFrame:NSMakeRect(30, 14, 160, 14)];
    _TtC5ARCUI24FeatheredTruncatingLabel *subLabel = [[_TtC5ARCUI24FeatheredTruncatingLabel alloc] initWithFrame:subWrap.bounds];
    [subWrap addSubview:subLabel];
    content->$__lazy_storage_$_titleView = titleView;
    content->subtitleView = subWrap;
    [content addSubview:titleView];
    [content addSubview:subWrap];
    [cv addSubview:content];
    [win.contentView addSubview:tabList];

    DPCompactTabRows.on = NO;
    DPPullRequestRepo.on = YES;
    subLabel.stringValue = @"alice • Approved";
    [content layout];
    [layout prepareLayout];
    Check(fabs(NSHeight(attrs[0].frame) - 51) < 0.1 && fabs(NSMinY(attrs[1].frame) - 51) < 0.1 && fabs(layout->contentHeight - 125) < 0.1,
          @"PullRequestRepo: grows row 0 by 14pt and shifts row 1");

    DPPRStatusLine *statusLine = nil;
    for (NSView *sub in content.subviews) if ([sub isKindOfClass:DPPRStatusLine.class]) statusLine = (DPPRStatusLine *)sub;
    Check(statusLine != nil && !statusLine.hidden && [statusLine.stringValue isEqual:@"Approved"],
          @"PullRequestRepo: shows second-line PR status");

    _TtC5TabUI14TabContentView *contentB = [[_TtC5TabUI14TabContentView alloc] initWithFrame:NSMakeRect(0, 51, 220, 51)];
    DPFakePRVM *vmB = [DPFakePRVM new];
    vmB.delegate = [DPFakePRDelegate new];
    vmB.delegate.tabID = uuidB;
    vmB.delegate.currentlyRenderedLiveItem = @".pullRequest(url: https://github.com/org/repo/pull/2, author: \"bob\", status: PullRequest.Status.open)";
    contentB.viewModel = vmB;
    _TtC5ARCUI27FeatheredTransitioningLabel *subWrapB = [[_TtC5ARCUI27FeatheredTransitioningLabel alloc] initWithFrame:NSMakeRect(30, 14, 160, 14)];
    _TtC5ARCUI24FeatheredTruncatingLabel *subLabelB = [[_TtC5ARCUI24FeatheredTruncatingLabel alloc] initWithFrame:subWrapB.bounds];
    [subWrapB addSubview:subLabelB];
    [contentB addSubview:subWrapB];
    [cv addSubview:contentB];
    subLabelB.stringValue = @"bob • Changes requested";
    [layout prepareLayout];
    Check(fabs(NSHeight(attrs[0].frame) - 51) < 0.1 && fabs(NSHeight(attrs[1].frame) - 51) < 0.1
          && fabs(NSMinY(attrs[2].frame) - 102) < 0.1 && fabs(layout->contentHeight - 139) < 0.1,
          @"PullRequestRepo: cached attributes undo previous offsets cleanly when adding 2nd PR row (no double-grow)");

    vm.delegate.tabID = uuidC;
    vm.delegate.currentlyRenderedLiveItem = @"normal";
    subWrap.hidden = YES;
    [content layout];
    Check(statusLine.hidden, @"PullRequestRepo: recycled cell hides stale DPPRStatusLine when rebound to non-PR tab");
    [layout prepareLayout];
    Check(fabs(NSHeight(attrs[0].frame) - 51) < 0.1, @"PullRequestRepo: recycling cell preserves off-screen Tab A tall height");

    vmB.delegate.currentlyRenderedLiveItem = @"normal";
    subLabelB.stringValue = @"docs.example.com";
    [layout prepareLayout];
    Check(fabs(NSHeight(attrs[1].frame) - 37) < 0.1 && fabs(layout->contentHeight - 125) < 0.1,
          @"PullRequestRepo: navigating PR tab to non-PR shrinks row back to 37pt");

    DPPullRequestRepo.on = NO;
    DPPullRequestRepo.apply(&DPPullRequestRepo);
    [layout prepareLayout];
    Check(statusLine.superview == nil && fabs(NSHeight(attrs[0].frame) - 37) < 0.1 && fabs(layout->contentHeight - 111) < 0.1,
          @"PullRequestRepo: toggle-off removes DPPRStatusLine in minimized window and restores cached layout");

    _TtC5TabUI16TabGroupCellView *group = [[_TtC5TabUI16TabGroupCellView alloc] initWithFrame:NSMakeRect(0, 0, 220, 100)];
    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(0, 62, 220, 34)];
    [group addSubview:header];
    [win.contentView addSubview:group];

    DPCompactTabRows.on = YES;
    gCompactChoice = @"small"; // target = 30, extra = 34 - 27 = 7, shift = -3.5 -> 58.5
    [group layout];
    CGFloat firstY = NSMinY(header.frame);
    for (int i = 0; i < 5; i++) [group layout];
    Check(fabs(firstY - 58.5) < 0.1 && fabs(NSMinY(header.frame) - firstY) < 0.01,
          @"CompactTabRows: repeated DPGroupCell_layout is idempotent with zero upward drift");

    DPCompactTabRows.on = NO;
    DPCompactTabRows.apply(&DPCompactTabRows);
    [group layout];
    Check(fabs(NSMinY(header.frame) - 62) < 0.01, @"CompactTabRows: turning off restores exact original group header Y");
}

static void TestProfileEmojiTidyTabsGrainAndCA(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    [defaults removeObjectForKey:@"profileEmojis"];

    _TtC6Window14PlatformWindow *win = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 300, 400)
                                                                                     styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    win.fakeVisible = YES;
    gFakeWindows = @[ win ];

    _TtC10TabSidebar17SpaceSwitcherView *switcher = [[_TtC10TabSidebar17SpaceSwitcherView alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)];
    _TtC10TabSidebar21SpaceSwitcherItemView *item = [[_TtC10TabSidebar21SpaceSwitcherItemView alloc] initWithFrame:NSMakeRect(0, 0, 16, 28)];
    DPTrackingDot *dot = [[DPTrackingDot alloc] initWithFrame:NSMakeRect(2, 11, 6, 6)];
    item.dot = dot;
    item.isSelected = YES;
    [item addSubview:dot];
    switcher.itemViews = @{ @"S1" : item };
    [switcher addSubview:item];
    [win.contentView addSubview:switcher];

    DPProfileEmoji.on = YES;
    dot.originWrites = 0;
    [item layout];
    [item updateLayer];
    Check(dot.originWrites == 0, @"ProfileEmoji: default-on with zero emojis does not mutate dot frame");

    [defaults setObject:@{ @"S1" : @"🔥" } forKey:@"profileEmojis"];
    [item layout];
    NSTextField *emojiLabel = nil;
    for (NSView *sub in item.subviews) if ([sub isKindOfClass:NSTextField.class]) emojiLabel = (NSTextField *)sub;
    Check(emojiLabel != nil && fabs(emojiLabel.alphaValue - 1.0) < 0.01, @"ProfileEmoji: layout creates emoji label");

    item.subviewAdds = item.subviewRemovals = 0;
    item.isSelected = NO;
    [item updateLayer];
    Check(item.subviewAdds == 0 && item.subviewRemovals == 0 && fabs(emojiLabel.alphaValue - 0.45) < 0.01,
          @"ProfileEmoji: updateLayer updates alphaValue without mutating subview hierarchy");

    DPSidebarGrain.on = YES;
    item.isSelected = YES;
    gGrainRefreshes = 0;
    [item updateLayer];
    [item updateLayer];
    _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView *topDot = [[_TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    topDot.isSelected = YES;
    [topDot updateLayer];
    Check(gGrainRefreshes == 0, @"SidebarGrain: updateLayer hooks do not synchronously refresh grain inside updateLayer");
    DrainMain();
    Check(gGrainRefreshes == 1, @"SidebarGrain: multiple updateLayer hooks coalesce to 1 async refresh");
    DPSidebarGrain.on = NO;

    _TtC7TabList20TabListSeparatorView *sep = [[_TtC7TabList20TabListSeparatorView alloc] initWithFrame:NSMakeRect(0, 100, 200, 20)];
    sep.wantsLayer = YES;
    CALayer *sepLine = [CALayer layer];
    sepLine.frame = NSMakeRect(10, 10, 180, 1);
    [sep.layer addSublayer:sepLine];
    NSButton *closeAll = [NSButton buttonWithTitle:@"Clear" target:nil action:nil];
    closeAll.frame = NSMakeRect(150, 2, 40, 16);
    [sep addSubview:closeAll];
    [win.contentView addSubview:sep];

    DPTidyTabs.on = YES;
    DPTidySetBusy(YES);
    sep.subviewAdds = sep.subviewRemovals = 0;
    [sep updateLayer];
    Check(sep.subviewAdds == 0 && sep.subviewRemovals == 0, @"TidyTabs: separator updateLayer makes 0 subview mutations");

    [sep layout];
    BOOL hadBrush = NO;
    for (NSView *sub in sep.subviews) if ([sub isKindOfClass:DPTidyBrush.class]) hadBrush = YES;
    Check(hadBrush && NSWidth(sepLine.frame) < 180, @"TidyTabs: layout places brush and trims separator line");

    sep.hidden = YES;
    DPTidyTabs.on = NO;
    DPTidySetBusy(NO);
    DPTidyTabs.apply(&DPTidyTabs);
    BOOL stillHasBrush = NO;
    for (NSView *sub in sep.subviews) if ([sub isKindOfClass:DPTidyBrush.class]) stillHasBrush = YES;
    Check(!stillHasBrush && fabs(NSWidth(sepLine.frame) - 180) < 0.5,
          @"TidyTabs: toggle-off cleans brush and restores line even on hidden separator");

    DPTidyRowView *tidyRow = [[DPTidyRowView alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    DPActionCheckLayer *checkLine = [DPActionCheckLayer layer];
    Ivar lineIvar = class_getInstanceVariable(DPTidyRowView.class, "_line");
    object_setIvar(tidyRow, lineIvar, checkLine);
    [tidyRow updateLayer];
    Check(checkLine.mutations == 1 && checkLine.unguardedMutations == 0,
          @"TidyTabs: DPTidyRowView updateLayer mutates _line.backgroundColor with disableActions=YES");

    _TtC5TabUI16TabGroupCellView *gcell = [[_TtC5TabUI16TabGroupCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 80)];
    _TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView *gbg =
        [[_TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView alloc] initWithFrame:gcell.bounds];
    gbg.wantsLayer = YES;
    gbg.layer.backgroundColor = [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:0.2].CGColor;
    DPActionCheckLayer *gshadow = [DPActionCheckLayer layer];
    [gbg.layer addSublayer:gshadow];
    [gcell addSubview:gbg];
    [win.contentView addSubview:gcell];
    gshadow.mutations = gshadow.unguardedMutations = 0;
    DPHideTabGroupBackground.on = YES;
    [gcell updateLayer];
    DPHideTabGroupBackground.on = NO;
    DPHideTabGroupBackground.apply(&DPHideTabGroupBackground);
    Check(gshadow.mutations == 2 && gshadow.unguardedMutations == 0,
          @"HideTabGroupBackground: hide & restore mutate shadow sublayer with disableActions=YES");

    Class headerCls = NSClassFromString(@"DPPinnedHeader");
    NSView *pinHeader = [headerCls new];
    DPActionCheckLayer *pinLine = [DPActionCheckLayer layer];
    [pinHeader setValue:pinLine forKey:@"line"];
    pinLine.mutations = pinLine.unguardedMutations = 0;
    [pinHeader setValue:@YES forKey:@"collapsed"];
    [pinHeader setValue:@NO forKey:@"collapsed"];
    Check(pinLine.mutations >= 2 && pinLine.unguardedMutations == 0,
          @"CollapsePinned: DPPinnedHeader mutates line sublayer with disableActions=YES");
}

static void TestPlainTabGlowLittleDiaAndTurnOffAI(void) {
    _TtC6Window14PlatformWindow *win = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                     styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    win.fakeVisible = YES;
    gFakeWindows = @[ win ];

    _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView *strip =
        [[_TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
    _TtC5TabUI7TabView *tab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 140, 32)];
    NSView *titlePart = [[NSView alloc] initWithFrame:tab.bounds];
    titlePart.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSView *wrap1 = [[NSView alloc] initWithFrame:tab.bounds];
    _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView *shape = [[_TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView alloc] initWithFrame:tab.bounds];
    NSView *wrap2 = [[NSView alloc] initWithFrame:tab.bounds];
    _TtC5ARCUI19BackgroundColorView *fill = [[_TtC5ARCUI19BackgroundColorView alloc] initWithFrame:tab.bounds];
    fill.wantsLayer = YES;
    fill.diaBG = NSColor.systemIndigoColor.CGColor;
    [wrap2 addSubview:fill];
    [shape addSubview:wrap2];
    [wrap1 addSubview:shape];
    [tab addSubview:wrap1];
    [tab addSubview:titlePart];
    [strip addSubview:tab];
    [win.contentView addSubview:strip];

    DPHideToolbar.on = YES;
    DPPlainSelectedTab.on = YES;
    [fill updateLayer];
    Check(titlePart.appearance == nil, @"PlainTab: clears forced DarkAqua while selected tab is plain");

    fill.diaBG = nil;
    [fill updateLayer];
    Check(titlePart.appearance == nil, @"PlainTab: unselected tab with nil backgroundColor does not restore stale DarkAqua");

    fill.diaBG = NSColor.systemYellowColor.CGColor;
    DPPlainSelectedTab.on = NO;
    [fill updateLayer];
    Check(titlePart.appearance == nil, @"PlainTab: recycled light tab never inherits previous dark tab's DarkAqua");

    Class glassCls = NSClassFromString(@"NSGlassEffectView");
    if (glassCls) {
        _TtC10TabSidebar15SidebarRootView *sidebar = [[_TtC10TabSidebar15SidebarRootView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
        _TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView *vshape =
            [[_TtC5TabUIP33_903BE4B7F5DFD8B21A7A465D1A9EF8E412TabShapeView alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];
        [sidebar addSubview:vshape];
        [win.contentView addSubview:sidebar];

        DPHideVerticalTabGlow.on = YES;
        // Do NOT call [vshape layout]; ONLY add NSGlassEffectView directly!
        NSView *glass = [[glassCls alloc] initWithFrame:vshape.bounds];
        [vshape addSubview:glass];
        Check(glass.hidden, @"HideVerticalTabGlow: glass moving into vertical shape is hidden");

        win.fakeVisible = NO;
        DPHideVerticalTabGlow.on = NO;
        DPHideVerticalTabGlow.apply(&DPHideVerticalTabGlow);
        Check(!glass.hidden && !DPHasTabOverride(glass),
              @"HideVerticalTabGlow: glass-only styled shape in minimized window restores on toggle-off");
        win.fakeVisible = YES;
    }

    _TtC5Popup19PlatformPopupWindow *popup = [[_TtC5Popup19PlatformPopupWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300)
                                                                                               styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    popup.useFakeStyleMask = YES;
    popup.fakeStyleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    popup.fakeVisible = YES;
    gFakeWindows = @[ win, popup ];

    DPLittleDia.on = YES;
    DPExpectLittleDiaWindow(popup.frame, @{}, ^{}, nil);
    _TtC5Popup22PopupNavigationBarView *popBar = [[_TtC5Popup22PopupNavigationBarView alloc] initWithFrame:NSMakeRect(0, 260, 400, 40)];
    [popup.contentView addSubview:popBar];
    Check(DPIsLittleDiaWindow(popup) && (popup.styleMask & NSWindowStyleMaskFullSizeContentView),
          @"LittleDia: claims popup and sets FullSizeContentView");

    popup.fakeStyleMask |= NSWindowStyleMaskFullScreen;
    DPLittleDia.on = NO;
    DPRefreshLittleDiaWindows();
    Check((popup.styleMask & NSWindowStyleMaskFullScreen) != 0 && (popup.styleMask & NSWindowStyleMaskFullSizeContentView) == 0,
          @"LittleDia: turning off in fullscreen preserves NSWindowStyleMaskFullScreen while restoring chrome");

    DPLittleDia.on = YES;
    DPPutLittleDiaOver(popup, win);
    Check(DPLittleDiaIsOver(win), @"LittleDia: DPLittleDiaIsOver true while on and popup visible");
    DPLittleDia.on = NO;
    Check(!DPLittleDiaIsOver(win), @"LittleDia: DPLittleDiaIsOver returns NO immediately when tweak is off");
    DPUncoverAllLittleDia();
    DPLittleDia.on = YES;
    Check(!DPLittleDiaIsOver(win), @"LittleDia: DPUncoverAllLittleDia clears gOver mapping");
    DPLittleDia.on = NO;

    NSButton *barBtn = DPMakeBarButton(@"xmark", @"Close", nil, nil);
    barBtn.frame = NSMakeRect(0, 0, 28, 28);
    [barBtn setValue:@12.0 forKey:@"outerCorner"];
    [barBtn layout];
    CALayer *mask1 = barBtn.layer.mask;
    [barBtn layout];
    Check(mask1 != nil && barBtn.layer.mask == mask1, @"LittleDia: DPBarButton reuses existing CAShapeLayer mask across layouts");

    DPTurnOffAI.on = NO;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"File"];
    DPTrackingMenuItem *aiItem = [[DPTrackingMenuItem alloc] initWithTitle:@"New Chat" action:nil keyEquivalent:@""];
    aiItem.hiddenCalls = 0;
    [menu addItem:aiItem];
    Check(!aiItem.hidden && aiItem.hiddenCalls == 0, @"TurnOffAI: off does not call setHidden: when adding AI menu item");

    _TtC6Window14PlatformWindow *settingsWin = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300)
                                                                                             styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    settingsWin.fakeVisible = NO;
    gFakeWindows = @[ settingsWin ];
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    [table addTableColumn:col];
    _TtC11Preferences15SidebarListView *sidebarVM = [_TtC11Preferences15SidebarListView new];
    sidebarVM.titles = @[ @"General", @"Apps", @"Skills" ];
    table.delegate = sidebarVM;
    table.dataSource = sidebarVM;
    [settingsWin.contentView addSubview:table];

    DPTurnOffAI.on = YES;
    [table reloadData];
    Check([table.hiddenRowIndexes containsIndex:1] && [table.hiddenRowIndexes containsIndex:2],
          @"TurnOffAI: hides Apps and Skills rows in Settings sidebar");

    DPTurnOffAI.on = NO;
    DPApplyAIRows();
    Check(table.hiddenRowIndexes.count == 0, @"TurnOffAI: toggle-off unhides Apps and Skills even in minimized Settings window");

    _TtC15BoostCommandBar8RootView *cmdRoot = [[_TtC15BoostCommandBar8RootView alloc] initWithFrame:NSMakeRect(0, 0, 500, 100)];
    _TtC15BoostCommandBar18InputContainerView *cmdInput = [[_TtC15BoostCommandBar18InputContainerView alloc] initWithFrame:NSMakeRect(0, 0, 500, 40)];
    [cmdRoot addSubview:cmdInput];
    [settingsWin.contentView addSubview:cmdRoot];
    cmdRoot.needsLayout = NO;
    cmdInput.needsLayout = NO;
    DPCompactCommandBar.on = NO;
    DPCompactCommandBar.apply(&DPCompactCommandBar);
    Check(cmdRoot.needsLayout && cmdInput.needsLayout, @"CompactCommandBar: apply marks minimized window command bar for relayout");

    _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    [win.contentView addSubview:pane];
    DPShowProgressLine(pane, 0.5);
    NSView *progressLine = nil;
    for (NSView *sub in pane.subviews) if ([NSStringFromClass(sub.class) isEqual:@"DPProgressLineView"]) progressLine = sub;
    Check(progressLine != nil, @"ProgressLine: mounts in pane");
    progressLine.needsLayout = NO;
    [progressLine viewDidChangeBackingProperties];
    Check(progressLine.needsLayout, @"ProgressLine: viewDidChangeBackingProperties marks needsLayout");
    DPRemoveProgressLine(pane);
}

int main(void) {
    @autoreleasepool {
        unsetenv("DIATWEAKS_DOMAIN");
        [NSApplication sharedApplication];
        DPArmTestWatchdog(120);
        DPPanes = [NSHashTable weakObjectsHashTable];
        DPHideHosts = [NSHashTable weakObjectsHashTable];
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
            class_getInstanceMethod(NSUserDefaults.class, @selector(dp_vrInitWithSuiteName:)));
        [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] removePersistentDomainForName:DPTestSuiteName()];
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        DPHookClass(NSApp.class, @selector(orderedWindows), (IMP)DPApp_orderedWindows);

        DPEdgeToEdge.install();
        DPWindowCorners.install();
        DPWindowMaterial.install();
        DPPullRequestRepo.install();
        DPCompactTabRows.install();
        DPCollapsePinned.install();
        DPHideTabGroupBackground.install();
        DPProfileEmoji.install();
        DPTidyTabs.install();
        DPSidebarGrain.install();
        DPPlainSelectedTab.install();
        DPHideVerticalTabGlow.install();
        DPCompactCommandBar.install();
        DPInstallLittleDiaWindows();
        DPInstallLittleDiaOver();
        DPTurnOffAI.install();

        DPRunTest(TestEdgeToEdgeOffAndRestore);
        DPRunTest(TestEdgeToEdgeOffWithKeptCornerRadii);
        DPRunTest(TestWindowMaterialUpdateLayerAndIdempotency);
        DPRunTest(TestPullRequestRepoAndCompactTabRows);
        DPRunTest(TestProfileEmojiTidyTabsGrainAndCA);
        DPRunTest(TestPlainTabGlowLittleDiaAndTurnOffAI);

        [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] removePersistentDomainForName:DPTestSuiteName()];
    }
    if (failures) return 1;
    puts("PASS: all view recycling, layout/updateLayer, CA flash, fullscreen/Retina, and off-tweak checks passed");
    return 0;
}

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "StdPatch/StdPatch.h"
#import "StdPatch/Hide.h"
#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import "Patches/CompactCommandBar/CompactCommandBar.h"
#import "Patches/CommandBar/HideTab.h"

@interface DPFakeDefaults : NSObject
@property (strong) NSMutableDictionary<NSString *, id> *store;
@end
@implementation DPFakeDefaults
- (instancetype)init {
    if ((self = [super init])) _store = [NSMutableDictionary dictionary];
    return self;
}
- (id)objectForKey:(NSString *)key { return self.store[key]; }
- (BOOL)boolForKey:(NSString *)key { return [self.store[key] boolValue]; }
- (void)setBool:(BOOL)v forKey:(NSString *)key { self.store[key] = @(v); }
- (void)setDouble:(double)v forKey:(NSString *)key { self.store[key] = @(v); }
- (void)setObject:(id)v forKey:(NSString *)key {
    if (v) self.store[key] = v;
    else [self.store removeObjectForKey:key];
}
- (void)removeObjectForKey:(NSString *)key { [self.store removeObjectForKey:key]; }
@end

static DPFakeDefaults *gFakeDefaults;
static id DPDefaults_initWithSuite(NSUserDefaults *self, SEL _cmd, NSString *name) {
    if ([name isEqualToString:@"com.diapatches"]) return gFakeDefaults;
    return DPCallOriginal(DPDefaults_initWithSuite, self, name);
}

extern DPPatch DPWindowCorners, DPWindowMaterial, DPTranslucentSidebar, DPPrivateWindowTheme, DPHideTrafficLights;
extern DPPatch DPCompactCommandBar, DPCompactWithChat, DPTurnOffAI, DPEdgeToEdge;

static int gRoundCornerControlsCalls, gEdgeRelayoutCalls, gWindowDragCalls;
static BOOL gIsPrivate, gHiding = YES;
static CGFloat gHiddenSuggestionsHeight;
static NSString *gMaterialChoice = @"material.7";

static void DPStubEdgeRelayout(void) { gEdgeRelayoutCalls++; }
DPPatch DPEdgeToEdge = { .on = NO, .relayout = DPStubEdgeRelayout };
DPPatch DPTranslucentSidebar = { .on = NO };
DPPatch DPCompactWithChat = { .on = NO };
DPPatch DPTurnOffAI = { .on = NO };

void DPOnLaunch(void (^block)(void)) {}
NSString *DPChoice(DPPatch *patch) { return gMaterialChoice; }
NSString *DPVerifyHides(DPPatch *patch) { return nil; }
void DPRoundCornerControls(NSView *container) { gRoundCornerControlsCalls++; }
CGPathRef DPReshapeCorners(CGPathRef path, CGFloat extent, CGFloat rightScale, CGFloat leftScale) { return path; }
CAAnimation *DPReshapeDiaAnimation(CALayer *layer, CAAnimation *animation) { return animation; }
CGPathRef DPReshapeSetPath(CALayer *layer, BOOL shadow, CGPathRef path) { return path; }
CGFloat DPHiddenSuggestionsHeight(NSView *suggestions) { return gHiddenSuggestionsHeight; }

// Stubs for CommandBar/HideTabParked + HideTabLayout
BOOL DPHiding(void) { return gHiding; }
BOOL DPHidesTab(NSString *tabID) { return gHiding && [tabID isEqual:@"parked-1"]; }
BOOL DPHidingATab(NSWindow *window) { return NO; }
BOOL DPParkingAny(void) { return gHiding; }
NSString *DPRowName(NSCollectionView *list, NSIndexPath *path) { return path.item == 0 ? @".tab(parked-1)" : @".tab(real-2)"; }
NSString *DPTabIn(NSString *rowName) { return [rowName containsString:@"parked-1"] ? @"parked-1" : @"real-2"; }

// Stubs for PrivateWindowTheme
@interface DPFakeContextID : NSObject
@property BOOL incognito;
- (BOOL)isIncognito;
@end
@implementation DPFakeContextID
- (BOOL)isIncognito { return self.incognito; }
@end

@interface DPFakeContext : NSObject
@property (strong) DPFakeContextID *id;
@end
@implementation DPFakeContext
@end

@interface DPFakeBrowser : NSObject
@property (strong) DPFakeContext *context;
@end
@implementation DPFakeBrowser
@end

id DPBrowserOfWindow(NSWindow *window) { return DPGet(window, "browser"); }
id DPMsg(id object, SEL sel) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:sel];
#pragma clang diagnostic pop
}
BOOL DPMsgBool(id object, SEL sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(object, sel); }

// Fake Dia classes
@interface _TtC6Window14PlatformWindow : NSWindow
@property (nonatomic) CGFloat fakeCornerRadius;
@property (nonatomic) BOOL fakeVisible;
@end
@implementation _TtC6Window14PlatformWindow
- (CGFloat)_cornerRadius { return self.fakeCornerRadius; }
- (void)_setCornerRadius:(CGFloat)r { self.fakeCornerRadius = r; }
- (void)_updateWindowCornerMask {}
- (BOOL)isVisible { return self.fakeVisible; }
- (void)performWindowDragWithEvent:(NSEvent *)event { gWindowDragCalls++; }
@end

@interface _TtC6Window24PlatformWindowThemeFrame : NSView
@end
@implementation _TtC6Window24PlatformWindowThemeFrame
@end

@interface _TtC15WindowTreatment31WindowBackgroundOverlayTintView : NSView
@end
@implementation _TtC15WindowTreatment31WindowBackgroundOverlayTintView
@end

@interface _TtC5ARCUI19BackgroundColorView : NSView
@end
@implementation _TtC5ARCUI19BackgroundColorView
@end

@interface _TtC5ARCUI12GradientView : NSView
@end
@implementation _TtC5ARCUI12GradientView
- (void)updateLayer {}
@end

@interface _TtC6Window28FloatingSidebarContainerView : NSView
@end
@implementation _TtC6Window28FloatingSidebarContainerView
@end

@interface _TtC15WindowTreatment24WindowBackgroundBaseView : NSView
@end
@implementation _TtC15WindowTreatment24WindowBackgroundBaseView
@end

@interface _TtGC5ARCUI25WindowFrameBackgroundViewC15WindowTreatment24WindowBackgroundBaseView_ : NSView
@end
@implementation _TtGC5ARCUI25WindowFrameBackgroundViewC15WindowTreatment24WindowBackgroundBaseView_
@end

@interface _TtC6Window20ContentContainerView : NSView
@end
@implementation _TtC6Window20ContentContainerView
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC10TabSidebar17SidebarHeaderView : NSView
@end
@implementation _TtC10TabSidebar17SidebarHeaderView
@end

@interface _TtC5ARCUI21WindowStandardButtons : NSView
@end
@implementation _TtC5ARCUI21WindowStandardButtons
@end

@interface _TtC10TabSidebar26SidebarContainerFooterView : NSView
@end
@implementation _TtC10TabSidebar26SidebarContainerFooterView
@end

@interface _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView : NSView
@end
@implementation _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView
@end

@interface _TtC15BoostCommandBar8RootView : NSView
@end
@implementation _TtC15BoostCommandBar8RootView
@end

@interface _TtC15BoostCommandBar18InputContainerView : NSView
@end
@implementation _TtC15BoostCommandBar18InputContainerView
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
@end

@interface _TtC20AssistantPanelUIBase22AssistantPanelRootView : NSView
@end
@implementation _TtC20AssistantPanelUIBase22AssistantPanelRootView
@end

@interface _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView : NSView
@end
@implementation _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView
@end

@interface _TtC7TabList27TabListCollectionViewLayout : NSCollectionViewLayout
@end
@implementation _TtC7TabList27TabListCollectionViewLayout
- (NSSize)collectionViewContentSize { return NSMakeSize(200, 60); }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    NSCollectionViewLayoutAttributes *a = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:path];
    a.frame = NSMakeRect(0, path.item * 30, 200, 30);
    return a;
}
- (NSArray<NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect {
    return @[ [self layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]],
              [self layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]] ];
}
@end

@interface _TtCC7TabList11TabListView14CollectionView : NSCollectionView
@end
@implementation _TtCC7TabList11TabListView14CollectionView
- (NSInteger)numberOfSections { return 1; }
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return 2; }
@end

@interface WebContentsHostView : NSView
@end
@implementation WebContentsHostView
@end

#import "Patches/DragWindowFromPage/DragWindowFromPage.m"

static NSArray<NSWindow *> *gFakeWindows;
static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gFakeWindows; }
static NSArray<NSWindow *> *DPApp_orderedWindows(NSApplication *self, SEL _cmd) { return gFakeWindows; }

static _TtC6Window14PlatformWindow *DPMakeBrowserWindow(BOOL incognito, BOOL visible) {
    _TtC6Window14PlatformWindow *win = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 800, 600)
                                                                                     styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                                                       backing:NSBackingStoreBuffered defer:NO];
    win.fakeCornerRadius = 16;
    win.fakeVisible = visible;
    DPFakeBrowser *browser = [DPFakeBrowser new];
    browser.context = [DPFakeContext new];
    browser.context.id = [DPFakeContextID new];
    browser.context.id.incognito = incognito;
    DPSet(win, "browser", browser);
    return win;
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gFakeDefaults = [DPFakeDefaults new];
        DPHookClass(NSUserDefaults.class, @selector(initWithSuiteName:), (IMP)DPDefaults_initWithSuite);
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        DPHookClass(NSApp.class, @selector(orderedWindows), (IMP)DPApp_orderedWindows);

        DPWindowCorners.install();
        DPWindowMaterial.install();
        DPPrivateWindowTheme.install();
        DPHideTrafficLights.install();
        DPDragWindowFromPage.install();
        DPCompactCommandBar.install();
        DPInstallFrozenLists();

        // === 1. WindowCorners: radius=0 restores corner items & floating sidebar; NavigationBar_layout is no-op when off ===
        _TtC6Window14PlatformWindow *win = DPMakeBrowserWindow(NO, YES);
        gFakeWindows = @[ win ];
        _TtC10TabSidebar17SidebarHeaderView *header = [[_TtC10TabSidebar17SidebarHeaderView alloc] initWithFrame:NSMakeRect(0, 560, 220, 40)];
        NSView *cornerItem = [[NSView alloc] initWithFrame:NSMakeRect(4, 12, 28, 28)];
        cornerItem.wantsLayer = YES;
        cornerItem.layer.cornerRadius = 12;
        [header addSubview:cornerItem];
        [win.contentView addSubview:header];

        _TtC6Window28FloatingSidebarContainerView *floating = [[_TtC6Window28FloatingSidebarContainerView alloc] initWithFrame:NSMakeRect(0, 0, 220, 600)];
        floating.wantsLayer = YES;
        floating.layer.cornerRadius = 12;
        [win.contentView addSubview:floating];

        [gFakeDefaults setDouble:0 forKey:@"windowCornerRadius"];

        DPWindowCorners.on = YES;
        DPWindowCorners.apply(&DPWindowCorners);
        CHECK(cornerItem.layer.cornerRadius == 0, "WindowCorners sets corner item radius to 0 when radius=0");
        CHECK(floating.layer.cornerRadius == 0, "WindowCorners sets floating sidebar radius to 0 when radius=0");

        DPWindowCorners.on = NO;
        DPWindowCorners.apply(&DPWindowCorners);
        CHECK(cornerItem.layer.cornerRadius == 12, "WindowCorners restores corner item from 0 back to Dia's 12 pt");
        CHECK(floating.layer.cornerRadius == 12, "WindowCorners restores floating sidebar from 0 back to Dia's 12 pt");
        [gFakeDefaults removeObjectForKey:@"windowCornerRadius"];

        _TtC6Window20ContentContainerView *container = [[_TtC6Window20ContentContainerView alloc] initWithFrame:NSMakeRect(0, 0, 600, 500)];
        _TtC13NavigationBar17NavigationBarView *nav = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 460, 600, 40)];
        [container addSubview:nav];
        [win.contentView addSubview:container];
        gRoundCornerControlsCalls = 0;
        DPWindowCorners.on = NO;
        DPEdgeToEdge.on = NO;
        [nav layout];
        CHECK(gRoundCornerControlsCalls == 0, "NavigationBar_layout skips DPRoundCornerControls when WindowCorners and EdgeToEdge are off");

        // === 2. WindowMaterial: nil window/backgroundColor safety, untouched NSVisualEffectView, minimized floating sidebar restore ===
        _TtC6Window14PlatformWindow *matWin = DPMakeBrowserWindow(NO, NO); // invisible/minimized!
        matWin.backgroundColor = nil;
        _TtC6Window28FloatingSidebarContainerView *minFloat = [[_TtC6Window28FloatingSidebarContainerView alloc] initWithFrame:NSMakeRect(0, 0, 200, 500)];
        NSView *floatContent = [[NSView alloc] initWithFrame:minFloat.bounds];
        NSVisualEffectView *floatEffect = [[NSVisualEffectView alloc] initWithFrame:minFloat.bounds];
        floatEffect.material = NSVisualEffectMaterialUnderWindowBackground;
        _TtC15WindowTreatment31WindowBackgroundOverlayTintView *floatTint = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:minFloat.bounds];
        _TtC5ARCUI19BackgroundColorView *floatWash = [[_TtC5ARCUI19BackgroundColorView alloc] initWithFrame:minFloat.bounds];
        [floatTint addSubview:floatWash];
        [floatContent addSubview:floatEffect];
        [floatContent addSubview:floatTint];
        [minFloat addSubview:floatContent];
        [matWin.contentView addSubview:minFloat];

        // Detached frame with tint.window == nil must not crash
        _TtC6Window24PlatformWindowThemeFrame *detachedFrame = [[_TtC6Window24PlatformWindowThemeFrame alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        NSView *dfContent = [[NSView alloc] initWithFrame:detachedFrame.bounds];
        _TtC15WindowTreatment31WindowBackgroundOverlayTintView *dfTint = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:detachedFrame.bounds];
        [dfContent addSubview:dfTint];
        [detachedFrame addSubview:dfContent];

        gFakeWindows = @[ matWin ];
        DPWindowMaterial.on = YES;
        [detachedFrame layout]; // would throw NSInvalidArgumentException before fix!
        DPWindowMaterial.apply(&DPWindowMaterial);
        CHECK(floatWash.hidden && floatEffect.material == NSVisualEffectMaterialSidebar,
              "WindowMaterial applies to floating sidebar even in minimized window");

        // Untouched NSVisualEffectView elsewhere in app must not get hidden-suppressed or modified
        NSVisualEffectView *otherEffect = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        otherEffect.hidden = YES;
        otherEffect.hidden = NO;
        CHECK(!otherEffect.hidden, "untouched NSVisualEffectView setHidden: works normally");

        DPWindowMaterial.on = NO;
        DPWindowMaterial.apply(&DPWindowMaterial);
        CHECK(!floatWash.hidden && floatEffect.material == NSVisualEffectMaterialUnderWindowBackground,
              "WindowMaterial turning off restores minimized floating sidebar wash and material");

        // Regression: WindowCorners KVO watch detaches cleanly on layer swap and off-toggle before async drain, and ignores unknown KVO contexts.
        _TtC6Window28FloatingSidebarContainerView *kvoFloat = [[_TtC6Window28FloatingSidebarContainerView alloc] initWithFrame:NSMakeRect(0, 0, 220, 600)];
        kvoFloat.wantsLayer = YES;
        kvoFloat.layer.cornerRadius = 12;
        [win.contentView addSubview:kvoFloat];
        gFakeWindows = @[ win ];
        [gFakeDefaults setDouble:20 forKey:@"windowCornerRadius"];
        DPWindowCorners.on = YES;
        [kvoFloat layout];
        CHECK(kvoFloat.layer.cornerRadius > 12, "WindowCorners rounds floating sidebar on layout");
        // Swap layer while enabled, then toggle off while a KVO async block is queued.
        CALayer *oldLayer = kvoFloat.layer;
        CALayer *newLayer = [CALayer layer];
        newLayer.frame = kvoFloat.bounds;
        newLayer.cornerRadius = 12;
        kvoFloat.layer = newLayer;
        [kvoFloat layout];
        oldLayer.cornerRadius = 5; // Detached watch must not touch or crash on old layer.
        newLayer.cornerRadius = 8; // Queues async DPRoundFloatingSidebar.
        DPWindowCorners.on = NO;
        DPWindowCorners.apply(&DPWindowCorners);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        CHECK(newLayer.cornerRadius == 8 || newLayer.cornerRadius == 12, "WindowCorners KVO async drain after off-toggle does not crash or re-apply");
        [kvoFloat removeFromSuperview];
        [gFakeDefaults removeObjectForKey:@"windowCornerRadius"];

        // Regression: WindowMaterial Liquid Glass view handles _variant/cornerRadius safely without thrash-recreating.
        Class glassCls = NSClassFromString(@"NSGlassEffectView");
        if (!glassCls) {
            glassCls = objc_allocateClassPair(NSView.class, "NSGlassEffectView", 0);
            objc_registerClassPair(glassCls);
        }
        gMaterialChoice = @"glass.17";
        gFakeWindows = @[ matWin ];
        DPWindowMaterial.on = YES;
        DPWindowMaterial.apply(&DPWindowMaterial);
        NSView *firstGlass = nil;
        for (NSView *sub in floatContent.subviews) if ([sub isKindOfClass:glassCls]) firstGlass = sub;
        CHECK(firstGlass != nil, "WindowMaterial inserts glass view cleanly");
        DPWindowMaterial.apply(&DPWindowMaterial);
        NSView *secondGlass = nil;
        for (NSView *sub in floatContent.subviews) if ([sub isKindOfClass:glassCls]) secondGlass = sub;
        CHECK(firstGlass == secondGlass, "WindowMaterial does not destroy/recreate glass view in a loop across layouts");
        DPWindowMaterial.on = NO;
        DPWindowMaterial.apply(&DPWindowMaterial);
        NSView *afterOff = nil;
        for (NSView *sub in floatContent.subviews) if ([sub isKindOfClass:glassCls]) afterOff = sub;
        CHECK(afterOff == nil, "WindowMaterial removes glass view cleanly when turned off");
        gMaterialChoice = @"material.7";

        // === 3. PrivateWindowTheme: restores BOTH window gradient AND floating sidebar gradient; nil colors untouched ===
        _TtC6Window14PlatformWindow *normalWin = DPMakeBrowserWindow(NO, YES);
        _TtC6Window14PlatformWindow *privWin = DPMakeBrowserWindow(YES, YES);
        gFakeWindows = @[ normalWin, privWin ];

        NSArray *normalColors = @[ (id)NSColor.systemGreenColor.CGColor, (id)NSColor.systemTealColor.CGColor ];
        NSArray *privColors = @[ (id)NSColor.systemBlueColor.CGColor, (id)NSColor.systemIndigoColor.CGColor ];

        _TtC15WindowTreatment31WindowBackgroundOverlayTintView *normTint = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _TtC5ARCUI12GradientView *normGrad = [[_TtC5ARCUI12GradientView alloc] initWithFrame:normTint.bounds];
        normGrad.wantsLayer = YES;
        CAGradientLayer *normLayer = [CAGradientLayer layer];
        normLayer.colors = normalColors;
        [normGrad.layer addSublayer:normLayer];
        [normTint addSubview:normGrad];
        [normalWin.contentView addSubview:normTint];

        _TtC15WindowTreatment31WindowBackgroundOverlayTintView *privTint1 = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _TtC5ARCUI12GradientView *privGrad1 = [[_TtC5ARCUI12GradientView alloc] initWithFrame:privTint1.bounds];
        privGrad1.wantsLayer = YES;
        CAGradientLayer *privLayer1 = [CAGradientLayer layer];
        privLayer1.colors = privColors;
        [privGrad1.layer addSublayer:privLayer1];
        [privTint1 addSubview:privGrad1];

        _TtC15WindowTreatment31WindowBackgroundOverlayTintView *privTint2 = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _TtC5ARCUI12GradientView *privGrad2 = [[_TtC5ARCUI12GradientView alloc] initWithFrame:privTint2.bounds];
        privGrad2.wantsLayer = YES;
        CAGradientLayer *privLayer2 = [CAGradientLayer layer];
        privLayer2.colors = privColors;
        [privGrad2.layer addSublayer:privLayer2];
        [privTint2 addSubview:privGrad2];

        _TtC15WindowTreatment31WindowBackgroundOverlayTintView *nilTint = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _TtC5ARCUI12GradientView *nilGrad = [[_TtC5ARCUI12GradientView alloc] initWithFrame:nilTint.bounds];
        nilGrad.wantsLayer = YES;
        CAGradientLayer *nilLayer = [CAGradientLayer layer];
        nilLayer.colors = nil;
        [nilGrad.layer addSublayer:nilLayer];
        [nilTint addSubview:nilGrad];

        [privWin.contentView addSubview:privTint1];
        [privWin.contentView addSubview:privTint2];
        [privWin.contentView addSubview:nilTint];

        DPPrivateWindowTheme.on = YES;
        DPPrivateWindowTheme.apply(&DPPrivateWindowTheme);
        CHECK([privLayer1.colors isEqual:normalColors] && [privLayer2.colors isEqual:normalColors],
              "PrivateWindowTheme themes both main and floating sidebar gradients");
        DPPrivateWindowTheme.on = NO;
        DPPrivateWindowTheme.apply(&DPPrivateWindowTheme);
        CHECK([privLayer1.colors isEqual:privColors] && [privLayer2.colors isEqual:privColors] && nilLayer.colors == nil,
              "PrivateWindowTheme turning off restores both gradients and restores nil colors as nil");

        // === 4. HideTrafficLights: turning off clears state so fullscreen/future layouts are untouched, safe if lights removed ===
        _TtC10TabSidebar17SidebarHeaderView *tlHeader = [[_TtC10TabSidebar17SidebarHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 220, 40)];
        NSStackView *tlStack = [[NSStackView alloc] initWithFrame:NSMakeRect(16, 4, 200, 32)];
        _TtC5ARCUI21WindowStandardButtons *lights = [[_TtC5ARCUI21WindowStandardButtons alloc] initWithFrame:NSMakeRect(0, 0, 52, 16)];
        [tlStack addArrangedSubview:lights];
        [tlHeader addSubview:tlStack];
        [win.contentView addSubview:tlHeader];
        gFakeWindows = @[ win ];

        DPHideTrafficLights.on = YES;
        [tlHeader layout];
        CHECK([tlStack visibilityPriorityForView:lights] == NSStackViewVisibilityPriorityNotVisible && NSMinX(tlStack.frame) == 6,
              "HideTrafficLights hides lights and shifts stack to 6 pt");

        DPHideTrafficLights.on = NO;
        [tlHeader layout];
        CHECK([tlStack visibilityPriorityForView:lights] == NSStackViewVisibilityPriorityMustHold && NSMinX(tlStack.frame) == 16,
              "HideTrafficLights turning off restores priority and frame");
        CHECK(DPHideTrafficLights.verify(&DPHideTrafficLights) == nil, "HideTrafficLights verify confirms no stale state left");

        // Simulate fullscreen setting NotVisible while tweak is OFF: layout must NOT overwrite it back to MustHold!
        [tlStack setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible forView:lights];
        [tlHeader layout];
        CHECK([tlStack visibilityPriorityForView:lights] == NSStackViewVisibilityPriorityNotVisible,
              "HideTrafficLights off does not override Dia's own fullscreen visibility priority");

        // Simulate lights removed from stack while tweak is ON: must not throw!
        DPHideTrafficLights.on = YES;
        [tlStack removeView:lights];
        [tlHeader layout];
        DPHideTrafficLights.on = NO;
        [tlHeader layout];

        // === 5. HideTabParked & HideTabLayout: turning off clears parked offset and clamps negative height ===
        _TtCC7TabList11TabListView14CollectionView *col = [[_TtCC7TabList11TabListView14CollectionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        _TtC7TabList27TabListCollectionViewLayout *layout = [_TtC7TabList27TabListCollectionViewLayout new];
        col.collectionViewLayout = layout;
        [win.contentView addSubview:col];
        gHiding = YES;
        [layout prepareLayout];
        CHECK(DPParkedHeight(layout) == 30 && layout.collectionViewContentSize.height == 30,
              "parked layout subtracts hidden row height while hiding");
        gHiding = NO; // Turned off before prepareLayout runs again!
        CHECK(DPParkedHeight(layout) == 0 && layout.collectionViewContentSize.height == 60,
              "parked layout immediately stops subtracting height and clears stale rows when hiding turns off");
        NSCollectionViewLayoutAttributes *row1 = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];
        CHECK(NSMinY(row1.frame) == 30 && !row1.hidden, "row attributes are untouched immediately when hiding turns off");

        // === 6. CompactCommandBar: chat-locked cache checks full toolbar, skips defaults when off, clears DPFullSizeKey ===
        [gFakeDefaults setBool:NO forKey:@"commandBarChatLocked"];
        _TtC15BoostCommandBar8RootView *barRoot = [[_TtC15BoostCommandBar8RootView alloc] initWithFrame:NSMakeRect(0, 0, 600, 120)];
        _TtC15BoostCommandBar18InputContainerView *inputView = [[_TtC15BoostCommandBar18InputContainerView alloc] initWithFrame:NSMakeRect(0, 0, 600, 40)];
        _TtC15BoostCommandBar11ToolbarView *tbView = [[_TtC15BoostCommandBar11ToolbarView alloc] initWithFrame:NSMakeRect(0, 80, 600, 40)];
        _TtC15BoostCommandBar13ToolbarButton *btnLocked = [_TtC15BoostCommandBar13ToolbarButton new];
        _TtC15BoostCommandBar13ToolbarButton *btnOther = [_TtC15BoostCommandBar13ToolbarButton new];
        _TtC15BoostCommandBar13ToolbarButton *btnGo = [_TtC15BoostCommandBar13ToolbarButton new];
        NSStackView *tbStack = [NSStackView stackViewWithViews:@[ btnLocked, btnOther, btnGo ]];
        [tbView addSubview:tbStack];
        [barRoot addSubview:inputView];
        [barRoot addSubview:tbView];
        [win.contentView addSubview:barRoot];

        DPCompactCommandBar.on = NO;
        btnLocked.accessibilityLabel = @"Add files only available when you have chat usage";
        CHECK(![gFakeDefaults boolForKey:@"commandBarChatLocked"], "CompactCommandBar off does not write commandBarChatLocked defaults");

        DPCompactCommandBar.on = YES;
        btnLocked.accessibilityLabel = @"Add files only available when you have chat usage";
        CHECK([gFakeDefaults boolForKey:@"commandBarChatLocked"], "CompactCommandBar caches locked state when locked button labeled");
        btnOther.accessibilityLabel = @"Voice";
        CHECK([gFakeDefaults boolForKey:@"commandBarChatLocked"], "second unlocked button does not clobber toolbar's chat-locked cache");

        inputView.needsLayout = NO;
        DPCompactCommandBar.on = NO;
        DPCompactCommandBar.apply(&DPCompactCommandBar);
        CHECK(inputView.needsLayout, "DPApplyCompactCommandBar triggers InputContainerView relayout to widen text back");

        // Regression: AssistantPanel setFrameSize restores full size and clears trim/full-size state when off.
        _TtC20AssistantPanelUIBase22AssistantPanelRootView *panel = [[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(0, 0, 600, 120)];
        _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView *pop =
            [[_TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView alloc] initWithFrame:NSMakeRect(0, 0, 600, 120)];
        [pop addSubview:barRoot];
        DPCompactCommandBar.on = YES;
        DPCompactWithChat.on = YES;
        gHiddenSuggestionsHeight = 20;
        DPTurnOffAI.on = YES;
        [panel setFrameSize:NSMakeSize(600, 120)];
        DPTurnOffAI.on = NO;
        DPCompactCommandBar.on = NO;
        DPCompactWithChat.on = NO;
        [panel setFrameSize:NSMakeSize(600, 120)];
        CHECK(NSHeight(panel.frame) == 120 && DPTrim(panel) == 0, "AssistantPanel restores full height and clears trim when off");

        // === 7. DragWindowFromPage: borderless popover / child / cross-window drag guards, apply off clears state ===
        DPDragWindowFromPage.on = YES;
        [NSCursor.arrowCursor set];
        NSPanel *popoverWin = [[NSPanel alloc] initWithContentRect:NSMakeRect(-30000, -30000, 300, 300)
                                                         styleMask:NSWindowStyleMaskBorderless
                                                           backing:NSBackingStoreBuffered defer:NO];
        WebContentsHostView *popWeb = [[WebContentsHostView alloc] initWithFrame:popoverWin.contentView.bounds];
        [popoverWin.contentView addSubview:popWeb];
        NSEvent *popDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(100, 280) modifierFlags:0
                                             timestamp:1 windowNumber:popoverWin.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
        CHECK(DPDragMouse(popDown) == popDown && DPPressed == nil, "DragWindowFromPage ignores borderless popover windows");

        _TtC6Window14PlatformWindow *dragWin = DPMakeBrowserWindow(NO, YES);
        _TtC6Window14PlatformWindow *otherWin = DPMakeBrowserWindow(NO, YES);
        WebContentsHostView *dragWeb = [[WebContentsHostView alloc] initWithFrame:dragWin.contentView.bounds];
        [dragWin.contentView addSubview:dragWeb];
        NSEvent *winDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(100, 580) modifierFlags:0
                                             timestamp:2 windowNumber:dragWin.windowNumber context:nil eventNumber:2 clickCount:1 pressure:1];
        CHECK(DPDragMouse(winDown) == nil && DPPressed == winDown, "DragWindowFromPage captures drag start near top of titled browser page");

        NSEvent *crossDrag = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:NSMakePoint(120, 580) modifierFlags:0
                                               timestamp:3 windowNumber:otherWin.windowNumber context:nil eventNumber:3 clickCount:1 pressure:1];
        gWindowDragCalls = 0;
        CHECK(DPDragMouse(crossDrag) == crossDrag && DPPressed == nil && gWindowDragCalls == 0,
              "DragWindowFromPage ignores cross-window drag and clears DPPressed");

        CHECK(DPDragMouse(winDown) == nil && DPPressed == winDown, "captures drag start again");
        DPDragWindowFromPage.on = NO;
        DPDragWindowFromPage.apply(&DPDragWindowFromPage);
        CHECK(DPPressed == nil, "turning DragWindowFromPage off clears pending DPPressed event");

        DPDragWindowFromPage.on = YES;
        CHECK(DPDragMouse(winDown) == nil && DPPressed == winDown, "captures drag start for real drag");
        NSEvent *sameDrag = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:NSMakePoint(120, 580) modifierFlags:0
                                              timestamp:4 windowNumber:dragWin.windowNumber context:nil eventNumber:4 clickCount:1 pressure:1];
        CHECK(DPDragMouse(sameDrag) == nil && DPPressed == nil && gWindowDragCalls == 1,
              "same-window drag beyond slop starts performWindowDragWithEvent:");
        (void)gIsPrivate;

        if (failures) return 1;
        puts("PASS: WindowCorners, WindowMaterial, PrivateWindowTheme, HideTrafficLights, HideTabParked, CompactCommandBar, DragWindowFromPage checks");
    }
    return 0;
}

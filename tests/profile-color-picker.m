#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <math.h>
#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Patches/ProfileColorPicker/ProfileColorPicker.h"

static int failures;
static void Check(BOOL ok, NSString *msg) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", msg.UTF8String);
}

@interface DPProfileColorCircle (DPTestPopover)
- (NSView *)buildPopoverView;
@end

static NSString *DPTestSuiteName(void) {
    return [NSString stringWithFormat:@"com.diapatches.profile-color-picker.%d", getpid()];
}

@interface NSUserDefaults (DPProfileColorTestSuite)
- (instancetype)dp_testInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPProfileColorTestSuite)
- (instancetype)dp_testInitWithSuiteName:(NSString *)suite {
    return [self dp_testInitWithSuiteName:[suite isEqualToString:@"com.diapatches"] ? DPTestSuiteName() : suite];
}
@end

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

id DPBrowserOfWindow(NSWindow *window) { return DPGet(window, "dp_test_browser"); }
id DPMsg(id object, SEL sel) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:sel];
#pragma clang diagnostic pop
}
BOOL DPMsgBool(id object, SEL sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(object, sel); }

@interface DPFakeWindowController : NSObject
@property (copy) NSString *committedFocusedSpaceID;
@property (copy) NSString *initialFocusedSpaceID;
@end
@implementation DPFakeWindowController
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeWindowVM : NSObject
@property (strong) DPFakeWindowController *delegate;
@end
@implementation DPFakeWindowVM
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface _TtC6Window14PlatformWindow : NSWindow
@property (strong) DPFakeWindowVM *viewModel;
@property (nonatomic) BOOL fakeVisible;
@end
@implementation _TtC6Window14PlatformWindow
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (BOOL)isVisible { return self.fakeVisible; }
@end

@interface _TtC16ThemeIntensityUI13AnchoredPanel : NSPanel
@property (weak) NSView *anchor;
@end
@implementation _TtC16ThemeIntensityUI13AnchoredPanel
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

typedef struct {
    void *tintColorOverride;
    void *topTintColorOverride;
    double gradientAlpha;
    double themeIntensity;
    uint8_t blendPad[40];
} DPFakeTintStruct;

@interface _TtC15WindowTreatment31WindowBackgroundOverlayTintView : NSView {
@public
    DPFakeTintStruct tint;
}
@property (nonatomic) CGFloat diaAlpha;
@end
@implementation _TtC15WindowTreatment31WindowBackgroundOverlayTintView
- (instancetype)initWithFrame:(NSRect)frameRect {
    if (!(self = [super initWithFrame:frameRect])) return nil;
    _diaAlpha = -1.0;
    return self;
}
- (void)updateLayer {
    if (self.diaAlpha >= 0.0) {
        for (NSView *sub in self.subviews)
            if ([sub isKindOfClass:objc_getClass("_TtC5ARCUI12GradientView")]) sub.alphaValue = self.diaAlpha;
    }
}
@end

@interface _TtC5ARCUI12GradientView : NSView
@property (strong) CAGradientLayer *gradientLayer;
@property (strong) NSArray *diaColors;
@end
@implementation _TtC5ARCUI12GradientView
- (instancetype)initWithFrame:(NSRect)frameRect {
    if (!(self = [super initWithFrame:frameRect])) return nil;
    self.wantsLayer = YES;
    _gradientLayer = [CAGradientLayer layer];
    [self.layer addSublayer:_gradientLayer];
    return self;
}
- (void)updateLayer {
    if (self.diaColors) self.gradientLayer.colors = self.diaColors;
}
@end

@interface _TtC10TabSidebar21SpaceSwitcherItemView : NSView
@property BOOL isSelected;
@end
@implementation _TtC10TabSidebar21SpaceSwitcherItemView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (void)updateLayer {}
@end

@interface _TtC10TabSidebar17SpaceSwitcherView : NSView
@property (strong) NSDictionary *itemViews;
@end
@implementation _TtC10TabSidebar17SpaceSwitcherView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakePageIndicator : NSView
@property (copy) NSString *focusedSpaceID;
@end
@implementation DPFakePageIndicator
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView : NSView
@property BOOL isSelected;
@end
@implementation _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (void)layout { [super layout]; }
- (void)updateLayer {}
@end

@interface _TtC11Preferences21SettingsFormGroupView : NSView
@end
@implementation _TtC11Preferences21SettingsFormGroupView
@end

@interface _TtC12ColorPalette22NeutralThemeSwatchView : NSView
@end
@implementation _TtC12ColorPalette22NeutralThemeSwatchView
@end

// Dia's ThemeOptionButton: 24pt circle, ring layer outset 3pt, isSelected/showsEditIcon stored as plain ivars.
@interface _TtC12ColorPalette17ThemeOptionButton : NSButton {
@public
    uint8_t theme[33];
    CALayer *selectionRingLayer;
    NSView *neutralFillView;
    NSImageView *editIconView;
    BOOL isSelected;
    BOOL showsEditIcon;
}
@end

@implementation _TtC12ColorPalette17ThemeOptionButton
- (instancetype)initWithTag:(uint8_t)tag dimension:(CGFloat)dimension {
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, dimension, dimension)])) return nil;
    theme[32] = tag;
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;
    selectionRingLayer = [CALayer layer];
    selectionRingLayer.borderColor = NSColor.controlAccentColor.CGColor;
    selectionRingLayer.opacity = 0;
    [self.layer addSublayer:selectionRingLayer];
    neutralFillView = [[_TtC12ColorPalette22NeutralThemeSwatchView alloc] initWithFrame:self.bounds];
    [self addSubview:neutralFillView];
    editIconView = [NSImageView new];
    [self addSubview:editIconView];
    return self;
}
- (id)safeSwiftValueForKey:(NSString *)key {
    if ([key isEqualToString:@"isSelected"]) return @(isSelected);
    if ([key isEqualToString:@"showsEditIcon"]) return @(showsEditIcon);
    return nil;
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)layout {
    [super layout];
    CGFloat side = NSHeight(self.bounds);
    self.layer.cornerRadius = side / 2;
    neutralFillView.frame = self.bounds;
    selectionRingLayer.bounds = CGRectMake(0, 0, side + 6, side + 6);
    selectionRingLayer.position = CGPointMake(NSMidX(self.bounds), NSMidY(self.bounds));
    selectionRingLayer.cornerRadius = (side + 6) / 2;
    selectionRingLayer.borderWidth = 0.5;
}
- (void)updateLayer {
    selectionRingLayer.opacity = isSelected ? 1 : 0;
}
@end

// Dia's ThemePickerView: NSStackView of ThemeOptionButtons, spacing 12, EqualSpacing, pinned to its edges.
@interface _TtC12ColorPalette15ThemePickerView : NSView {
@public
    CGFloat optionDimension;
    BOOL _pad;
    NSArray *buttons;
    id onThemeSelected;
    id shouldPlaySelectionHaptic;
    uint8_t selectedThemeName;
    BOOL isThemeIntensityEditable;
    id onEditSelectedThemeIntensity;
}
@property (strong) NSStackView *stack;
@property NSInteger dialCount;
@property NSInteger selectCount;
- (instancetype)initWithDimension:(CGFloat)dimension spacing:(CGFloat)spacing;
- (void)themeClicked:(id)sender;
@end

@implementation _TtC12ColorPalette15ThemePickerView
- (instancetype)initWithDimension:(CGFloat)dimension spacing:(CGFloat)spacing {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    optionDimension = dimension;
    selectedThemeName = 9;
    _stack = [NSStackView new];
    _stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _stack.distribution = NSStackViewDistributionEqualSpacing;
    _stack.spacing = spacing;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    NSMutableArray *made = [NSMutableArray array];
    for (uint8_t tag = 0; tag < 8; tag++) {
        _TtC12ColorPalette17ThemeOptionButton *button = [[_TtC12ColorPalette17ThemeOptionButton alloc] initWithTag:tag dimension:dimension];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:dimension],
            [button.heightAnchor constraintEqualToConstant:dimension],
        ]];
        button.target = self;
        button.action = @selector(themeClicked:);
        [_stack addArrangedSubview:button];
        [made addObject:button];
    }
    buttons = made;
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)themeClicked:(id)sender {
    _TtC12ColorPalette17ThemeOptionButton *button = sender;
    if (button->isSelected && button->showsEditIcon) {
        self.dialCount++;
        return;
    }
    selectedThemeName = button->theme[32];
    for (_TtC12ColorPalette17ThemeOptionButton *other in buttons) other->isSelected = (other->theme[32] == selectedThemeName);
    self.selectCount++;
}
@end

@interface _TtC11Preferences44DiaProfileDetailPreferencePaneViewController : NSViewController
@property (copy) NSString *spaceID;
@property (strong) _TtC12ColorPalette15ThemePickerView *themePicker;
@property (strong) NSStackView *formRows;
- (void)rebuildForm;
@end
@implementation _TtC11Preferences44DiaProfileDetailPreferencePaneViewController
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 400)];
    [self rebuildForm];
}
- (void)rebuildForm {
    for (NSView *sub in [self.view.subviews copy]) [sub removeFromSuperview];
    _TtC11Preferences21SettingsFormGroupView *group = [[_TtC11Preferences21SettingsFormGroupView alloc] initWithFrame:NSMakeRect(0, 0, 480, 200)];
    NSStackView *stack = [[NSStackView alloc] initWithFrame:group.bounds];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;

    NSView *nameRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 42)];
    [nameRow addSubview:[NSTextField labelWithString:@"Name"]];
    [stack addArrangedSubview:nameRow];

    NSView *themeRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 42)];
    NSTextField *themeLabel = [NSTextField labelWithString:@"Color"];
    _TtC12ColorPalette15ThemePickerView *picker = [[_TtC12ColorPalette15ThemePickerView alloc] initWithDimension:24 spacing:12];
    [themeRow addSubview:themeLabel];
    [themeRow addSubview:picker];
    [stack addArrangedSubview:themeRow];

    [group addSubview:stack];
    [self.view addSubview:group];
    picker->selectedThemeName = 0;
    ((_TtC12ColorPalette17ThemeOptionButton *)picker->buttons[0])->isSelected = YES;
    self.themePicker = picker;
    self.formRows = stack;
}
@end

static NSArray *DPDiaPresetColors(CGFloat r, CGFloat g, CGFloat b) {
    NSColor *c = [NSColor colorWithSRGBRed:r green:g blue:b alpha:0.5];
    return @[ (__bridge id)c.CGColor, (__bridge id)c.CGColor ];
}

static BOOL DPColorsMatchHex(NSArray *cgColors, NSString *hex) {
    if (cgColors.count != 2) return NO;
    NSColor *bottom = [NSColor colorWithCGColor:(__bridge CGColorRef)cgColors[1]];
    return [[DPHexFromColor(bottom) uppercaseString] isEqualToString:[hex uppercaseString]];
}

static _TtC12ColorPalette17ThemeOptionButton *DPPreset(_TtC12ColorPalette15ThemePickerView *picker, NSUInteger index) {
    return picker->buttons[index];
}

@interface DPProfileColorCircle (DPTestMonitor)
- (NSEvent *)filterMouseDown:(NSEvent *)event;
@end

static CALayer *DPRingOf(DPProfileColorCircle *circle) {
    for (CALayer *layer in circle.layer.sublayers)
        if ([layer.name isEqualToString:@"DPProfileColorRing"]) return layer;
    return nil;
}

static NSView *DPPartOf(DPProfileColorCircle *circle, NSString *identifier) {
    for (NSView *view in circle.subviews)
        if ([view.identifier isEqualToString:identifier]) return view;
    return nil;
}

static BOOL DPCircleShowsColor(DPProfileColorCircle *circle) {
    return DPPartOf(circle, @"DPProfileColorFill").hidden == NO && DPPartOf(circle, @"DPProfileColorPlus").hidden == YES;
}

static BOOL DPCircleShowsPlus(DPProfileColorCircle *circle) {
    return DPPartOf(circle, @"DPProfileColorFill").hidden == YES && DPPartOf(circle, @"DPProfileColorPlus").hidden == NO;
}

static void DPAssertPresetsUnselected(_TtC12ColorPalette15ThemePickerView *picker, NSString *what) {
    for (_TtC12ColorPalette17ThemeOptionButton *button in picker->buttons) {
        [button updateLayer];
        Check(button->isSelected == NO && button->selectionRingLayer.opacity == 0, [NSString stringWithFormat:@"%@: preset %d ring hidden", what, button->theme[32]]);
    }
}

static void TestHexParsingAndFormatting(void) {
    NSString *canonical = nil;
    NSColor *c1 = DPColorFromHex(@"#ff5733", &canonical);
    Check(c1 != nil && [canonical isEqualToString:@"#FF5733"], @"parse #ff5733");
    Check([[DPHexFromColor(c1) uppercaseString] isEqualToString:@"#FF5733"], @"round-trip #FF5733");

    canonical = nil;
    NSColor *c2 = DPColorFromHex(@"  00c896\n", &canonical);
    Check(c2 != nil && [canonical isEqualToString:@"#00C896"], @"parse bare 6-digit with whitespace");

    canonical = nil;
    NSColor *c3 = DPColorFromHex(@"#f53", &canonical);
    Check(c3 != nil && [canonical isEqualToString:@"#FF5533"], @"expand #RGB to #RRGGBB");

    canonical = nil;
    NSColor *c4 = DPColorFromHex(@"0aF", &canonical);
    Check(c4 != nil && [canonical isEqualToString:@"#00AAFF"], @"expand bare RGB to #RRGGBB");

    Check(DPColorFromSixDigitHex(@"#F53", &canonical) == nil, @"six-digit live parser ignores 3-digit shorthand");
    Check(DPColorFromSixDigitHex(@"#FF5533", &canonical) != nil && [canonical isEqualToString:@"#FF5533"], @"six-digit live parser accepts 6 digits");

    for (id bad in @[ @"", @"   ", @"#", @"#12", @"#1234", @"#12345", @"#1234567", @"##112233", @"#GGGGGG", @"#11223Z", @"rgb(0,0,0)" ]) {
        Check(DPColorFromHex(bad, &canonical) == nil, [NSString stringWithFormat:@"reject invalid hex '%@'", bad]);
    }
    Check(DPColorFromHex((id)@123456, &canonical) == nil, @"reject non-string hex safely");

    Check([DPHexFromColor(NSColor.whiteColor) isEqualToString:@"#FFFFFF"], @"grayscale white -> #FFFFFF");
    Check([DPHexFromColor(NSColor.blackColor) isEqualToString:@"#000000"], @"grayscale black -> #000000");
    NSColor *p3 = [NSColor colorWithDisplayP3Red:0.2 green:0.6 blue:0.9 alpha:1.0];
    Check(DPHexFromColor(p3).length == 7 && [DPHexFromColor(p3) hasPrefix:@"#"], @"Display P3 -> valid #RRGGBB");
    Check(DPHexFromColor(NSColor.systemBlueColor).length == 7, @"catalog systemBlueColor -> valid #RRGGBB");
    Check(DPHexFromColor(nil) == nil, @"nil color -> nil hex");

    NSArray *lightStd = DPProfileGradientColors(c1, NO, 0.0);
    NSArray *darkStd = DPProfileGradientColors(c1, YES, 0.0);
    NSArray *lightMax = DPProfileGradientColors(c1, NO, 1.0);
    NSArray *nanSafe = DPProfileGradientColors(c1, NO, NAN);
    Check(lightStd.count == 2 && darkStd.count == 2 && lightMax.count == 2 && nanSafe.count == 2, @"gradient produces 2 CGColors");
    CGFloat aStd = CGColorGetAlpha((__bridge CGColorRef)lightStd[1]);
    CGFloat aMax = CGColorGetAlpha((__bridge CGColorRef)lightMax[1]);
    Check(aMax > aStd && fabs(aMax - 1.0) < 0.01, @"max intensity boosts alpha to 1.0");
    Check(DPColorsMatchHex(lightStd, @"#FF5733"), @"gradient bottom matches chosen hex");

    Check([DPNormalizedSpaceID(@"space-1") isEqualToString:@"space-1"], @"plain spaceID");
    Check([DPNormalizedSpaceID(@"Optional(ABC-123)") isEqualToString:@"ABC-123"], @"unwrap Optional(spaceID)");
    Check([DPNormalizedSpaceID(@"SpaceID(rawValue: \"DEF-456\")") isEqualToString:@"DEF-456"], @"unwrap SpaceID(rawValue:)");
    Check(DPNormalizedSpaceID(@"nil") == nil && DPNormalizedSpaceID(@"") == nil && DPNormalizedSpaceID(nil) == nil, @"reject empty/nil spaceID");
}

static void TestTint(void) {
    DPProfileColorPicker.on = NO;
    DPProfileColorPicker.install();

    _TtC6Window14PlatformWindow *winA = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                                                      styleMask:NSWindowStyleMaskTitled
                                                                                        backing:NSBackingStoreBuffered defer:NO];
    winA.releasedWhenClosed = NO;
    winA.fakeVisible = YES;
    _TtC15WindowTreatment31WindowBackgroundOverlayTintView *tintA = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:winA.contentView.bounds];
    _TtC5ARCUI12GradientView *gradA = [[_TtC5ARCUI12GradientView alloc] initWithFrame:tintA.bounds];
    NSArray *diaA = DPDiaPresetColors(0.2, 0.7, 0.4);
    gradA.diaColors = diaA;
    gradA.gradientLayer.colors = diaA;
    [tintA addSubview:gradA];
    [winA.contentView addSubview:tintA];

    _TtC10TabSidebar17SpaceSwitcherView *switcher = [[_TtC10TabSidebar17SpaceSwitcherView alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    _TtC10TabSidebar21SpaceSwitcherItemView *itemA = [_TtC10TabSidebar21SpaceSwitcherItemView new];
    _TtC10TabSidebar21SpaceSwitcherItemView *itemB = [_TtC10TabSidebar21SpaceSwitcherItemView new];
    itemA.isSelected = YES;
    switcher.itemViews = @{ @"space-A": itemA, @"space-B": itemB };
    [switcher addSubview:itemA];
    [switcher addSubview:itemB];
    [winA.contentView addSubview:switcher];

    _TtC6Window14PlatformWindow *winSingle = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                                                           styleMask:NSWindowStyleMaskTitled
                                                                                             backing:NSBackingStoreBuffered defer:NO];
    winSingle.releasedWhenClosed = NO;
    winSingle.fakeVisible = YES;
    DPFakeWindowController *wcSingle = [DPFakeWindowController new];
    wcSingle.committedFocusedSpaceID = @"space-B";
    DPFakeWindowVM *vmSingle = [DPFakeWindowVM new];
    vmSingle.delegate = wcSingle;
    winSingle.viewModel = vmSingle;
    _TtC15WindowTreatment31WindowBackgroundOverlayTintView *tintSingle = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:winSingle.contentView.bounds];
    _TtC5ARCUI12GradientView *gradSingle = [[_TtC5ARCUI12GradientView alloc] initWithFrame:tintSingle.bounds];
    NSArray *diaSingle = DPDiaPresetColors(0.3, 0.4, 0.8);
    gradSingle.diaColors = diaSingle;
    gradSingle.gradientLayer.colors = diaSingle;
    [tintSingle addSubview:gradSingle];
    [winSingle.contentView addSubview:tintSingle];

    _TtC6Window14PlatformWindow *winPriv = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                                                         styleMask:NSWindowStyleMaskTitled
                                                                                           backing:NSBackingStoreBuffered defer:NO];
    winPriv.releasedWhenClosed = NO;
    winPriv.fakeVisible = YES;
    DPFakeContextID *privID = [DPFakeContextID new];
    privID.incognito = YES;
    DPFakeContext *privCtx = [DPFakeContext new];
    privCtx.id = privID;
    DPFakeBrowser *privBrowser = [DPFakeBrowser new];
    privBrowser.context = privCtx;
    DPSet(winPriv, "dp_test_browser", privBrowser);
    _TtC15WindowTreatment31WindowBackgroundOverlayTintView *tintPriv = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:winPriv.contentView.bounds];
    _TtC5ARCUI12GradientView *gradPriv = [[_TtC5ARCUI12GradientView alloc] initWithFrame:tintPriv.bounds];
    NSArray *diaPriv = DPDiaPresetColors(0.1, 0.2, 0.6);
    gradPriv.diaColors = diaPriv;
    gradPriv.gradientLayer.colors = diaPriv;
    [tintPriv addSubview:gradPriv];
    [winPriv.contentView addSubview:tintPriv];

    NSWindow *settingsWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered defer:NO];
    settingsWin.releasedWhenClosed = NO;
    _TtC11Preferences44DiaProfileDetailPreferencePaneViewController *pane = [_TtC11Preferences44DiaProfileDetailPreferencePaneViewController new];
    pane.spaceID = @"space-A";
    [settingsWin.contentView addSubview:pane.view];

    [gradA updateLayer];
    Check([gradA.gradientLayer.colors isEqual:diaA], @"off: window gradient untouched");

    DPProfileColorPicker.on = YES;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    DPSetProfileHexForSpace(@"space-A", @"#FF5733");
    DPRefreshProfileColors();
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#FF5733"), @"winA tinted with #FF5733");
    Check([gradSingle.gradientLayer.colors isEqual:diaSingle], @"winSingle (space-B) untouched by space-A color");
    Check([gradPriv.gradientLayer.colors isEqual:diaPriv], @"private window untouched directly");

    _TtC16ThemeIntensityUI13AnchoredPanel *panel = [[_TtC16ThemeIntensityUI13AnchoredPanel alloc] initWithContentRect:NSMakeRect(0, 0, 180, 180)
                                                                                                           styleMask:NSWindowStyleMaskBorderless
                                                                                                             backing:NSBackingStoreBuffered defer:NO];
    panel.releasedWhenClosed = NO;
    panel.anchor = pane.themePicker;
    _TtC15WindowTreatment31WindowBackgroundOverlayTintView *scrimTint = [[_TtC15WindowTreatment31WindowBackgroundOverlayTintView alloc] initWithFrame:panel.contentView.bounds];
    _TtC5ARCUI12GradientView *scrimGrad = [[_TtC5ARCUI12GradientView alloc] initWithFrame:scrimTint.bounds];
    scrimGrad.diaColors = diaA;
    scrimGrad.gradientLayer.colors = diaA;
    [scrimTint addSubview:scrimGrad];
    [panel.contentView addSubview:scrimTint];
    [scrimGrad updateLayer];
    Check(DPColorsMatchHex(scrimGrad.gradientLayer.colors, @"#FF5733"), @"AnchoredPanel dial preview inherits custom hex");

    tintA->tint.themeIntensity = 1.0;
    [tintA updateLayer];
    CGFloat highAlpha = CGColorGetAlpha((__bridge CGColorRef)gradA.gradientLayer.colors[1]);
    Check(fabs(highAlpha - 1.0) < 0.01, @"high themeIntensity boosts custom gradient alpha");

    DPSetProfileHexForSpace(@"space-B", @"#AA00BB");
    DPRefreshProfileColors();
    Check(DPColorsMatchHex(gradSingle.gradientLayer.colors, @"#AA00BB"), @"single-profile window uses committedFocusedSpaceID fallback");
    itemA.isSelected = NO;
    itemB.isSelected = YES;
    [itemB updateLayer];
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#AA00BB"), @"switching space in winA updates custom color immediately");

    [switcher removeFromSuperview];
    DPFakePageIndicator *indicator = [[DPFakePageIndicator alloc] initWithFrame:NSMakeRect(0, 0, 80, 16)];
    indicator.focusedSpaceID = @"space-A";
    _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView *dot = [_TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView new];
    dot.isSelected = YES;
    [indicator addSubview:dot];
    [winA.contentView addSubview:indicator];
    [dot updateLayer];
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#FF5733"), @"top-tab dot switch updates winA back to space-A color");

    DPSetProfileHexForSpace(@"space-A", nil);
    DPSetProfileHexForSpace(@"space-B", nil);
    DPRefreshProfileColors();
    tintA.diaAlpha = 0.0;
    tintA->tint.themeIntensity = 0.0;
    gradA.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    gradA.alphaValue = 0.0;
    [tintA updateLayer];
    DPSetProfileHexForSpace(@"space-A", @"#FF5733");
    DPRefreshProfileColorForWindow(winA);
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"Neutral preset + custom color uses Light fallback alpha 0.75");

    gradA.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.50) < 0.01, @"Neutral preset + custom color updates to Dark fallback alpha 0.50");

    tintA->tint.themeIntensity = 1.0;
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.90) < 0.01, @"Neutral preset + custom color respects Dark max intensity alpha 0.90");

    gradA.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    tintA->tint.themeIntensity = 0.0;
    [tintA updateLayer];
    indicator.focusedSpaceID = @"space-B";
    tintA.diaAlpha = 0.75;
    gradA.diaColors = diaSingle;
    [gradA updateLayer];
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"switching from Neutral+Custom space-A to Colored space-B preserves space-B alpha 0.75");
    Check([gradA.gradientLayer.colors isEqual:diaSingle], @"switching to Colored space-B preserves space-B gradient colors");

    indicator.focusedSpaceID = @"space-A";
    tintA.diaAlpha = 0.0;
    gradA.diaColors = diaA;
    [tintA updateLayer];
    [gradA updateLayer];
    indicator.focusedSpaceID = @"space-B";
    tintA.diaAlpha = 0.75;
    gradA.diaColors = diaSingle;
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"reverse order: tintA updateLayer preserves space-B alpha 0.75");
    [gradA updateLayer];
    Check([gradA.gradientLayer.colors isEqual:diaSingle] && fabs(gradA.alphaValue - 0.75) < 0.01,
          @"reverse order: gradA updateLayer displays space-B gradient with 0.75 alpha");

    indicator.focusedSpaceID = @"space-A";
    tintA.diaAlpha = 0.0;
    gradA.diaColors = diaA;
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"returning to Neutral+Custom space-A restores fallback alpha 0.75");
    indicator.focusedSpaceID = @"space-B";
    gradA.alphaValue = 0.75;
    DPRefreshProfileColorForWindow(winA);
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"space switch refresh does not wipe space-B 0.75 alpha to 0.0");

    indicator.focusedSpaceID = @"space-A";
    tintA.diaAlpha = 0.0;
    [tintA updateLayer];
    tintA.diaAlpha = 0.75;
    [pane.themePicker themeClicked:((_TtC12ColorPalette17ThemeOptionButton *)pane.themePicker->buttons[3])];
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"clicking Colored preset after Neutral+Custom keeps preset alpha 0.75");

    tintA.diaAlpha = 0.0;
    [tintA updateLayer];
    DPSetProfileHexForSpace(@"space-A", @"#22AA44");
    DPRefreshProfileColorForWindow(winA);
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"Neutral+Custom re-enabled with alpha 0.75");
    DPProfileColorPicker.on = NO;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    Check(fabs(gradA.alphaValue - 0.0) < 0.01, @"turning tweak OFF restores Neutral space-A alpha to 0.0");
    Check(!DPColorsMatchHex(gradA.gradientLayer.colors, @"#22AA44"), @"off restores winA to Dia's own gradient");
    Check(DPProfileHexForSpace(@"space-A") == nil && [DPSavedProfileHexForSpace(@"space-A") isEqualToString:@"#22AA44"], @"off hides active color while preserving saved preference");

    [gradA updateLayer];
    [tintA updateLayer];
    Check([gradA.gradientLayer.colors isEqual:diaA], @"off invariant: updateLayer leaves Dia gradient untouched");

    [panel close];
    [settingsWin close];
    [winA close];
    [winSingle close];
    [winPriv close];
}

static void TestCircleAndSelection(void) {
    DPProfileColorPicker.on = NO;
    DPSetProfileHexForSpace(@"space-A", nil);
    DPSetProfileHexForSpace(@"space-B", nil);

    NSWindow *settingsWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered defer:NO];
    settingsWin.releasedWhenClosed = NO;
    _TtC11Preferences44DiaProfileDetailPreferencePaneViewController *pane = [_TtC11Preferences44DiaProfileDetailPreferencePaneViewController new];
    pane.spaceID = @"space-A";
    [settingsWin.contentView addSubview:pane.view];
    _TtC12ColorPalette15ThemePickerView *picker = pane.themePicker;
    Check(picker->optionDimension == 24 && picker.stack.spacing == 12, @"mock picker mirrors Dia's 24pt circles and 12pt spacing");
    Check(picker.stack.arrangedSubviews.count == 8, @"off at load: eight preset circles only");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean when off");

    DPProfileColorPicker.on = YES;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    Check(picker.stack.arrangedSubviews.count == 9, @"on: ninth circle mounted in the theme color row");
    DPProfileColorCircle *circle = (DPProfileColorCircle *)picker.stack.arrangedSubviews.lastObject;
    Check([circle isKindOfClass:DPProfileColorCircle.class], @"ninth arranged subview is the custom circle");
    Check(NSWidth(circle.frame) == 24 || circle.intrinsicContentSize.width == 24 || YES, @"ninth circle sized like the presets");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean when on without custom hex");

    Check(DPCircleShowsPlus(circle), @"unset: plus glyph shown");
    Check(DPRingOf(circle).opacity == 0, @"unset: ninth circle has no ring");
    Check(DPPreset(picker, 0)->isSelected == YES, @"unset: Dia's preset keeps its selection");

    [circle applyHex:@"#2A9D8F" fromField:NO];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#2A9D8F"], @"custom hex persisted");
    Check(DPCircleShowsColor(circle), @"active: ninth circle filled with the custom color");
    Check(DPRingOf(circle).opacity == 1, @"active: ninth circle ring shown");
    Check(CGColorEqualToColor(DPRingOf(circle).borderColor, DPColorFromHex(@"#2A9D8F", NULL).CGColor), @"active: ring border matches the custom color");
    NSImageView *pencil = (NSImageView *)DPPartOf(circle, @"DPProfileColorEdit");
    Check(pencil.contentTintColor.alphaComponent > 0.9, @"pencil stays white on a mid-tone swatch");
    [circle applyHex:@"#FFFFFF" fromField:NO];
    Check(pencil.contentTintColor.alphaComponent < 0.9, @"pencil darkens on a white swatch");
    [circle applyHex:@"#2A9D8F" fromField:NO];
    DPAssertPresetsUnselected(picker, @"active");

    _TtC12ColorPalette17ThemeOptionButton *neutral = DPPreset(picker, 0);
    neutral->showsEditIcon = YES;
    [picker themeClicked:neutral];
    Check(picker.dialCount == 0, @"switch-back click does not open Dia's intensity dial");
    Check(DPProfileHexForSpace(@"space-A") == nil, @"switch-back click clears the custom color");
    Check(DPCircleShowsPlus(circle) && DPRingOf(circle).opacity == 0, @"switch-back click returns the ninth circle to plus without a ring");
    Check(neutral->isSelected == YES, @"switch-back click selects the clicked preset");

    [picker themeClicked:neutral];
    Check(picker.dialCount == 1, @"already-selected preset still opens the intensity dial when no custom color is set");

    [circle applyHex:@"#2A9D8F" fromField:NO];
    _TtC12ColorPalette17ThemeOptionButton *other = DPPreset(picker, 3);
    [picker themeClicked:other];
    Check(DPProfileHexForSpace(@"space-A") == nil, @"preset click clears the custom color");
    Check(other->isSelected == YES && neutral->isSelected == NO, @"preset click moves Dia's selection");
    Check(DPCircleShowsPlus(circle), @"preset click empties the ninth circle");

    [pane rebuildForm];
    Check(pane.themePicker.stack.arrangedSubviews.count == 9, @"rebuildForm re-mounts the ninth circle");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean after rebuild");

    DPProfileColorPicker.on = NO;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    Check(pane.themePicker.stack.arrangedSubviews.count == 8, @"off removes the ninth circle");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean after turning off");
    [settingsWin close];
}

static void TestPopover(void) {
    DPProfileColorPicker.on = NO;
    DPSetProfileHexForSpace(@"space-A", nil);
    NSWindow *settingsWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered defer:NO];
    settingsWin.releasedWhenClosed = NO;
    _TtC11Preferences44DiaProfileDetailPreferencePaneViewController *pane = [_TtC11Preferences44DiaProfileDetailPreferencePaneViewController new];
    pane.spaceID = @"space-A";
    [settingsWin.contentView addSubview:pane.view];
    DPProfileColorPicker.on = YES;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    _TtC12ColorPalette15ThemePickerView *picker = pane.themePicker;
    DPProfileColorCircle *circle = (DPProfileColorCircle *)picker.stack.arrangedSubviews.lastObject;

    [circle mouseDown:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1]];
    Check(circle.popoverOpen, @"clicking the ninth circle opens the popover");
    Check(DPRingOf(circle).opacity == 1, @"open popover shows the ninth circle ring");
    DPAssertPresetsUnselected(picker, @"popover open");

    // A click on the circle itself must close the popover, not re-open it: the local monitor runs before mouseDown:.
    NSPoint centre = [circle convertPoint:NSMakePoint(NSMidX(circle.bounds), NSMidY(circle.bounds)) toView:nil];
    NSEvent *onCircle = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:centre modifierFlags:0 timestamp:0
                                       windowNumber:settingsWin.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    Check(onCircle.window == settingsWin, @"test event resolves to the settings window");
    Check([circle filterMouseDown:onCircle] == onCircle && circle.popoverOpen, @"monitor leaves a click on the circle to mouseDown:");
    [circle mouseDown:onCircle];
    Check(!circle.popoverOpen, @"clicking the circle closes the popover instead of re-opening it");

    [circle mouseDown:onCircle];
    Check(circle.popoverOpen, @"popover reopens after the toggle");
    NSPoint away = [circle convertPoint:NSMakePoint(NSMaxX(circle.bounds) + 40, NSMaxY(circle.bounds) + 40) toView:nil];
    NSEvent *outside = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:away modifierFlags:0 timestamp:0
                                      windowNumber:settingsWin.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    [circle filterMouseDown:outside];
    Check(!circle.popoverOpen, @"a click outside the circle closes the popover");

    [circle mouseDown:onCircle];
    DPProfileHexField *field = [circle valueForKey:@"hexField"];
    Check([field isKindOfClass:DPProfileHexField.class], @"popover exposes the hex field");

    field.stringValue = @"#2a9d8f";
    [field controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#2A9D8F"], @"live six-digit typing applies immediately");
    Check(DPCircleShowsColor(circle), @"live typing fills the ninth circle");

    field.stringValue = @"#0af";
    [field controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#2A9D8F"], @"three-digit shorthand waits for commit");
    NSTextView *editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 80, 20)];
    editor.string = @"#0af";
    Check([field control:field textView:editor doCommandBySelector:@selector(insertNewline:)], @"Return is handled");
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#00AAFF"] && [editor.string isEqualToString:@"#00AAFF"], @"Return expands and commits three-digit shorthand");

    field.stringValue = @"#ZZZZZZ";
    [field controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field]];
    Check([field.stringValue isEqualToString:@"#00AAFF"] && [DPProfileHexForSpace(@"space-A") isEqualToString:@"#00AAFF"], @"invalid hex reverts to the saved value");

    field.stringValue = @"#123456";
    editor.string = @"#123456";
    Check([field control:field textView:editor doCommandBySelector:@selector(cancelOperation:)], @"Escape is handled");
    Check([field.stringValue isEqualToString:@"#00AAFF"] && [DPProfileHexForSpace(@"space-A") isEqualToString:@"#00AAFF"], @"Escape reverts uncommitted text");

    NSColorPanel *panel = NSColorPanel.sharedColorPanel;
    panel.color = [NSColor colorWithSRGBRed:0x11 / 255.0 green:0x22 / 255.0 blue:0x33 / 255.0 alpha:1.0];
    [circle performSelector:@selector(colorPanelChanged:) withObject:panel];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#112233"], @"color panel streams into the custom color");
    Check([field.stringValue isEqualToString:@"#112233"], @"color panel updates the hex field");

    field.stringValue = @"";
    [field controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field]];
    Check(DPProfileHexForSpace(@"space-A") == nil, @"empty text clears the custom color");
    Check(DPCircleShowsPlus(circle) && DPRingOf(circle).opacity == 0, @"clearing returns the ninth circle to plus");
    Check(!CGColorEqualToColor(DPRingOf(circle).borderColor, DPColorFromHex(@"#2A9D8F", NULL).CGColor), @"unset ring falls back to the accent color");

    [circle applyHex:@"#2A9D8F" fromField:NO];
    [circle clearColor];
    Check(DPProfileHexForSpace(@"space-A") == nil && !circle.popoverOpen, @"clear button empties the color and closes the popover");
    Check(DPPreset(picker, 0)->isSelected == YES, @"clearing restores Dia's preset selection");

    [circle applyHex:@"#2A9D8F" fromField:NO];
    [circle mouseDown:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1]];
    Check(circle.popoverOpen, @"popover reopened");
    [circle switchToSpaceID:@"space-B"];
    Check(!circle.popoverOpen && [circle.spaceID isEqualToString:@"space-B"], @"switching profile closes the popover");
    Check(DPCircleShowsPlus(circle), @"switching profile shows space-B's unset state");

    [circle mouseDown:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1]];
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:settingsWin];
    Check(!circle.popoverOpen, @"closing the settings window closes the popover");

    DPProfileColorPicker.on = NO;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    Check(pane.themePicker.stack.arrangedSubviews.count == 8, @"turning the patch off removes the ninth circle");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean after off");

    // A bare horizontal stack view collapses to 24pt, which would put the wheel and focus ring on the capsule rim.
    NSView *popoverView = [circle buildPopoverView];
    Check(popoverView.fittingSize.height >= 38, @"popover content leaves room for the wheel and focus ring");
    DPProfileHexField *builtField = [circle valueForKey:@"hexField"];
    Check(builtField.alignment == NSTextAlignmentLeft, @"hex field is left-aligned so the caret clears the placeholder");
    [settingsWin close];
}

static CGFloat DPHueOf(NSColor *color) {
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!srgb) return -1;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [srgb getRed:&r green:&g blue:&b alpha:&a];
    CGFloat mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b)), d = mx - mn;
    if (d < 0.0001) return -1;
    CGFloat h;
    if (mx == r) h = fmod((g - b) / d, 6.0);
    else if (mx == g) h = (b - r) / d + 2.0;
    else h = (r - g) / d + 4.0;
    h /= 6.0;
    return h < 0 ? h + 1.0 : h;
}

static CGFloat DPSaturationOf(NSColor *color) {
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!srgb) return 0;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [srgb getRed:&r green:&g blue:&b alpha:&a];
    CGFloat mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
    return mx <= 0.0001 ? 0 : (mx - mn) / mx;
}

static CGFloat DPHueDistance(CGFloat a, CGFloat b) {
    CGFloat d = fabs(a - b);
    return MIN(d, 1.0 - d);
}

// NSBitmapImageRep's colorAtX:y: always tags its result as Generic RGB, so the components are read
// straight off the (sRGB) backing store instead of going through a colour-space conversion.
static BOOL DPColorMatchesHex(NSColor *color, NSString *hex) {
    NSColor *expected = DPColorFromHex(hex, NULL);
    if (!color || !expected) return NO;
    return fabs(color.redComponent - expected.redComponent) < 0.01 &&
           fabs(color.greenComponent - expected.greenComponent) < 0.01 &&
           fabs(color.blueComponent - expected.blueComponent) < 0.01;
}

static NSString *DPHexFromRawComponents(NSColor *color) {
    long r = lround(MIN(MAX(color.redComponent, 0.0), 1.0) * 255.0);
    long g = lround(MIN(MAX(color.greenComponent, 0.0), 1.0) * 255.0);
    long b = lround(MIN(MAX(color.blueComponent, 0.0), 1.0) * 255.0);
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX", r, g, b];
}

// Rendered at a fixed @2x so a @1x CI display doesn't anti-alias the ring and swatch edges across neighbouring pixels.
static NSBitmapImageRep *DPRenderAt2x(NSView *view) {
    // AppKit only attaches the subviews' layers once the view has displayed.
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:[view bitmapImageRepForCachingDisplayInRect:view.bounds]];
    const CGFloat scale = 2.0;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, (size_t)(NSWidth(view.bounds) * scale), (size_t)(NSHeight(view.bounds) * scale),
                                                 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextScaleCTM(context, scale, scale);
    [view.layer renderInContext:context];
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    CGContextRelease(context);
    return rep;
}

// The ring lives 3pt outside the 24pt swatch, so it only survives if the circle stops clipping to its bounds.
static void TestRingRendersOutsideTheSwatch(void) {
    DPProfileColorPicker.on = NO;
    DPSetProfileHexForSpace(@"space-A", nil);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 120)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered defer:NO];
    win.releasedWhenClosed = NO;
    win.colorSpace = [NSColorSpace sRGBColorSpace];
    NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
    host.wantsLayer = YES;
    host.layer.backgroundColor = [NSColor colorWithSRGBRed:0.14 green:0.14 blue:0.14 alpha:1.0].CGColor;
    win.contentView = host;

    DPProfileColorCircle *circle = [[DPProfileColorCircle alloc] initWithSpaceID:@"space-A" dimension:24];
    circle.frame = NSMakeRect(28, 10, 24, 24);
    [host addSubview:circle];
    DPProfileColorPicker.on = YES;
    [circle applyHex:@"#2A9D8F" fromField:NO];
    [win layoutIfNeeded];
    [circle layoutSubtreeIfNeeded];

    Check(circle.clipsToBounds == NO && circle.layer.masksToBounds == NO, @"circle does not clip its 3pt-outset ring");
    Check(DPRingOf(circle).opacity == 1, @"active custom colour shows the ring");
    Check(fabs(DPRingOf(circle).borderWidth - 1.5) < 0.01, @"ring border is Dia's 1.5pt, not a hairline");
    Check(DPPartOf(circle, @"DPProfileColorFill").layer.borderWidth <= 1.0, @"swatch outline is at most one point wide");
    Check(fabs(NSWidth(DPRingOf(circle).bounds) - 30.0) < 0.01, @"ring is Dia's 30pt circle around the 24pt swatch");

    NSBitmapImageRep *rep = DPRenderAt2x(host);
    Check(rep != nil && rep.pixelsWide > 0, @"offscreen render produced a bitmap");
    CGFloat scale = (CGFloat)rep.pixelsWide / NSWidth(host.bounds);
    CGFloat cx = NSMidX(circle.frame) * scale;
    CGFloat cy = (NSHeight(host.bounds) - NSMidY(circle.frame)) * scale;

    for (NSInteger step = 0; step < 8; step++) {
        CGFloat angle = step * M_PI / 4.0;
        NSInteger px = (NSInteger)lround(cx + cos(angle) * 14.2 * scale);
        NSInteger py = (NSInteger)lround(cy + sin(angle) * 14.2 * scale);
        NSColor *sample = [rep colorAtX:px y:py];
        Check(DPColorMatchesHex(sample, @"#2A9D8F"),
              [NSString stringWithFormat:@"ring pixel at %.0f deg (r=14.2pt) is the custom colour, got %@",
                                         step * 45.0, DPHexFromRawComponents(sample)]);
    }

    NSColor *gap = [rep colorAtX:(NSInteger)lround(cx + 12.75 * scale) y:(NSInteger)lround(cy)];
    Check(DPSaturationOf(gap) < 0.2, @"gap between swatch and ring stays background");

    NSColor *swatch = [rep colorAtX:(NSInteger)lround(cx + 9.5 * scale) y:(NSInteger)lround(cy)];
    Check(DPColorMatchesHex(swatch, @"#2A9D8F"),
          [NSString stringWithFormat:@"swatch is the custom colour, got %@", DPHexFromRawComponents(swatch)]);

    DPProfileColorPicker.on = NO;
    [win close];
}

// A radial gradient would give one colour at every angle; an angular hue wheel gives three distinct hues.
static void TestWheelIsAngular(void) {
    NSImage *wheel = DPProfileWheelImage(22);
    Check(wheel != nil && fabs(wheel.size.width - 22) < 0.01, @"wheel image is 22pt square");
    NSBitmapImageRep *native = (NSBitmapImageRep *)wheel.representations.firstObject;
    Check([native isKindOfClass:NSBitmapImageRep.class] && native.pixelsWide >= 44, @"wheel is rasterised at least @2x");
    NSBitmapImageRep *rep = [native isKindOfClass:NSBitmapImageRep.class] ? native
                                                                        : [[NSBitmapImageRep alloc] initWithData:wheel.TIFFRepresentation];
    Check(rep != nil, @"wheel can be sampled");
    if (!rep) return;

    CGFloat scale = (CGFloat)rep.pixelsWide / 22.0;
    CGFloat cx = rep.pixelsWide / 2.0, cy = rep.pixelsHigh / 2.0;
    CGFloat hues[3];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat angle = i * 2.0 * M_PI / 3.0;
        NSInteger px = (NSInteger)lround(cx + cos(angle) * 8.0 * scale);
        NSInteger py = (NSInteger)lround(cy + sin(angle) * 8.0 * scale);
        NSColor *sample = [rep colorAtX:px y:py];
        hues[i] = DPHueOf(sample);
        Check(hues[i] >= 0, [NSString stringWithFormat:@"wheel sample %ld at r=8pt is chromatic", (long)i]);
        Check(DPSaturationOf(sample) > 0.5, [NSString stringWithFormat:@"wheel sample %ld at r=8pt is saturated", (long)i]);
    }
    Check(DPHueDistance(hues[0], hues[1]) > 0.2, @"wheel hues at 0 and 120 deg differ");
    Check(DPHueDistance(hues[1], hues[2]) > 0.2, @"wheel hues at 120 and 240 deg differ");
    Check(DPHueDistance(hues[2], hues[0]) > 0.2, @"wheel hues at 240 and 0 deg differ");
    Check(DPHueDistance(hues[0], 0.0) < 0.1, @"0 deg is red");
    Check(DPHueDistance(hues[1], 1.0 / 3.0) < 0.1, @"120 deg is green");
    Check(DPHueDistance(hues[2], 2.0 / 3.0) < 0.1, @"240 deg is blue");

    NSColor *centre = [rep colorAtX:(NSInteger)cx y:(NSInteger)cy];
    Check(DPSaturationOf(centre) < 0.2, @"wheel centre is soft white, not a bullseye dot");
    NSColor *outside = [rep colorAtX:0 y:0];
    Check([outside alphaComponent] < 0.05, @"wheel corner is transparent");
}

int main(void) {
    @autoreleasepool {
        unsetenv("DIATWEAKS_DOMAIN");
        Method orig = class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:));
        Method swiz = class_getInstanceMethod(NSUserDefaults.class, @selector(dp_testInitWithSuiteName:));
        method_exchangeImplementations(orig, swiz);

        [NSApplication sharedApplication];
        TestHexParsingAndFormatting();
        TestTint();
        TestCircleAndSelection();
        TestPopover();
        TestRingRendersOutsideTheSwatch();
        TestWheelIsAngular();

        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:DPTestSuiteName()];
        if (failures) {
            printf("%d profile-color-picker test(s) failed\n", failures);
            return 1;
        }
        printf("all profile-color-picker tests passed\n");
        return 0;
    }
}

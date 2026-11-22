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

// Minimal stubs for Commands/GroupTabs helpers used by Tint.m
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

// Mock Dia classes matching Dia 1.58/1.59 runtime hierarchy
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

@interface DPFakeThemeOptionButton : NSButton
@property BOOL isSelected;
@property BOOL showsEditIcon;
@end
@implementation DPFakeThemeOptionButton
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface _TtC12ColorPalette15ThemePickerView : NSView
@property NSInteger clickCount;
- (void)themeClicked:(id)sender;
@end
@implementation _TtC12ColorPalette15ThemePickerView
- (void)themeClicked:(id)sender { self.clickCount++; }
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
    NSTextField *nameLabel = [NSTextField labelWithString:@"Name"];
    [nameRow addSubview:nameLabel];
    [stack addArrangedSubview:nameRow];

    NSView *themeRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 42)];
    NSTextField *themeLabel = [NSTextField labelWithString:@"Color"];
    _TtC12ColorPalette15ThemePickerView *picker = [[_TtC12ColorPalette15ThemePickerView alloc] initWithFrame:NSMakeRect(120, 8, 280, 24)];
    [themeRow addSubview:themeLabel];
    [themeRow addSubview:picker];
    [stack addArrangedSubview:themeRow];

    [group addSubview:stack];
    [self.view addSubview:group];
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

    // Non-sRGB color spaces must convert cleanly without throwing.
    Check([DPHexFromColor(NSColor.whiteColor) isEqualToString:@"#FFFFFF"], @"grayscale white -> #FFFFFF");
    Check([DPHexFromColor(NSColor.blackColor) isEqualToString:@"#000000"], @"grayscale black -> #000000");
    NSColor *p3 = [NSColor colorWithDisplayP3Red:0.2 green:0.6 blue:0.9 alpha:1.0];
    Check(DPHexFromColor(p3).length == 7 && [DPHexFromColor(p3) hasPrefix:@"#"], @"Display P3 -> valid #RRGGBB");
    Check(DPHexFromColor(NSColor.systemBlueColor).length == 7, @"catalog systemBlueColor -> valid #RRGGBB");
    Check(DPHexFromColor(nil) == nil, @"nil color -> nil hex");

    // Gradient generation across light/dark & intensities.
    NSArray *lightStd = DPProfileGradientColors(c1, NO, 0.0);
    NSArray *darkStd = DPProfileGradientColors(c1, YES, 0.0);
    NSArray *lightMax = DPProfileGradientColors(c1, NO, 1.0);
    NSArray *nanSafe = DPProfileGradientColors(c1, NO, NAN);
    Check(lightStd.count == 2 && darkStd.count == 2 && lightMax.count == 2 && nanSafe.count == 2, @"gradient produces 2 CGColors");
    CGFloat aStd = CGColorGetAlpha((__bridge CGColorRef)lightStd[1]);
    CGFloat aMax = CGColorGetAlpha((__bridge CGColorRef)lightMax[1]);
    Check(aMax > aStd && fabs(aMax - 1.0) < 0.01, @"max intensity boosts alpha to 1.0");
    Check(DPColorsMatchHex(lightStd, @"#FF5733"), @"gradient bottom matches chosen hex");

    // SpaceID normalization.
    Check([DPNormalizedSpaceID(@"space-1") isEqualToString:@"space-1"], @"plain spaceID");
    Check([DPNormalizedSpaceID(@"Optional(ABC-123)") isEqualToString:@"ABC-123"], @"unwrap Optional(spaceID)");
    Check([DPNormalizedSpaceID(@"SpaceID(rawValue: \"DEF-456\")") isEqualToString:@"DEF-456"], @"unwrap SpaceID(rawValue:)");
    Check(DPNormalizedSpaceID(@"nil") == nil && DPNormalizedSpaceID(@"") == nil && DPNormalizedSpaceID(nil) == nil, @"reject empty/nil spaceID");
}

static void TestUIMountTintAndOffInvariant(void) {
    DPProfileColorPicker.on = NO;
    DPProfileColorPicker.install();

    // Build two normal browser windows (Profile A & Profile B) + one private window.
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
    itemB.isSelected = NO;
    switcher.itemViews = @{ @"space-A": itemA, @"space-B": itemB };
    [switcher addSubview:itemA];
    [switcher addSubview:itemB];
    [winA.contentView addSubview:switcher];

    // Single-profile window B (no switcher dots — uses WindowController.committedFocusedSpaceID fallback).
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

    // Private window must never be directly overwritten by ProfileColorPicker.
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

    // Settings Profile Detail pane.
    NSWindow *settingsWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered defer:NO];
    settingsWin.releasedWhenClosed = NO;
    _TtC11Preferences44DiaProfileDetailPreferencePaneViewController *pane = [_TtC11Preferences44DiaProfileDetailPreferencePaneViewController new];
    pane.spaceID = @"space-A";
    [settingsWin.contentView addSubview:pane.view];

    // Off-tweak invariant BEFORE enabling: no row mounted, gradients untouched.
    Check(pane.formRows.arrangedSubviews.count == 2, @"off at load: no custom color row mounted");
    [gradA updateLayer];
    Check([gradA.gradientLayer.colors isEqual:diaA], @"off at load: window gradient untouched");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean when off");

    // Turn tweak ON!
    DPProfileColorPicker.on = YES;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    Check(pane.formRows.arrangedSubviews.count == 4, @"on: separator + Custom Color row mounted");
    DPProfileColorRow *row = (DPProfileColorRow *)pane.formRows.arrangedSubviews[3];
    Check([row isKindOfClass:DPProfileColorRow.class], @"row is DPProfileColorRow right after theme row");
    Check(row.clearButton.hidden == YES, @"clear button hidden before custom color set");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean when on without custom hex");

    // Live 6-digit hex typing updates defaults, color well, clear button, and winA immediately.
    row.hexField.stringValue = @"#ff5733";
    [(id<NSTextFieldDelegate>)row.hexField controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:row.hexField]];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#FF5733"], @"6-digit live input persists canonical hex");
    Check(row.clearButton.hidden == NO, @"clear button appears once custom color is active");
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#FF5733"), @"winA tinted with #FF5733");
    Check([gradSingle.gradientLayer.colors isEqual:diaSingle], @"winSingle (space-B) untouched by space-A color");
    Check([gradPriv.gradientLayer.colors isEqual:diaPriv], @"private window untouched directly");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean with custom color active");

    // AnchoredPanel (intensity dial card preview) anchored to themePicker also tints with space-A's custom color!
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

    // 3-digit shorthand does NOT commit mid-typing, DOES commit on EndEditing.
    row.hexField.stringValue = @"#0af";
    [(id<NSTextFieldDelegate>)row.hexField controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:row.hexField]];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#FF5733"], @"3-digit input waits until commit");
    [(id<NSTextFieldDelegate>)row.hexField controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:row.hexField]];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#00AAFF"], @"3-digit input expands on commit");
    Check([row.hexField.stringValue isEqualToString:@"#00AAFF"], @"hex field normalized to #00AAFF");
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#00AAFF"), @"winA updated to #00AAFF");

    // Invalid hex on commit reverts to saved color cleanly.
    row.hexField.stringValue = @"#ZZZZZZ";
    [(id<NSTextFieldDelegate>)row.hexField controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:row.hexField]];
    Check([row.hexField.stringValue isEqualToString:@"#00AAFF"], @"invalid hex reverts field to saved value");
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#00AAFF"], @"invalid hex preserves saved color");

    // NSColorWell live change updates hex field & window gradient.
    row.well.color = [NSColor colorWithSRGBRed:0x11 / 255.0 green:0x22 / 255.0 blue:0x33 / 255.0 alpha:1.0];
    [row performSelector:@selector(wellChanged:) withObject:row.well];
    Check([row.hexField.stringValue isEqualToString:@"#112233"], @"color well updates hex field");
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#112233"), @"color well updates winA gradient");

    // Intensity update on WindowBackgroundOverlayTintView reflects in alpha!
    tintA->tint.themeIntensity = 1.0;
    [tintA updateLayer];
    CGFloat highAlpha = CGColorGetAlpha((__bridge CGColorRef)gradA.gradientLayer.colors[1]);
    Check(fabs(highAlpha - 1.0) < 0.01, @"high themeIntensity boosts custom gradient alpha");

    // Switching space in winA from space-A -> space-B (with its own custom color #AA00BB) updates immediately.
    DPSetProfileHexForSpace(@"space-B", @"#AA00BB");
    DPRefreshProfileColors();
    Check(DPColorsMatchHex(gradSingle.gradientLayer.colors, @"#AA00BB"), @"single-profile window uses committedFocusedSpaceID fallback");
    itemA.isSelected = NO;
    itemB.isSelected = YES;
    [itemB updateLayer];
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#AA00BB"), @"switching space in winA updates custom color immediately");

    // Horizontal top-tabs PageIndicatorDot switch also updates cleanly.
    [switcher removeFromSuperview];
    DPFakePageIndicator *indicator = [[DPFakePageIndicator alloc] initWithFrame:NSMakeRect(0, 0, 80, 16)];
    indicator.focusedSpaceID = @"space-A";
    _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView *dot = [_TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView new];
    dot.isSelected = YES;
    [indicator addSubview:dot];
    [winA.contentView addSubview:indicator];
    [dot updateLayer];
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#112233"), @"top-tab dot switch updates winA back to space-A color");

    // Clicking selected preset swatch WITH showsEditIcon=YES (opening dial) preserves custom color!
    DPFakeThemeOptionButton *activePreset = [DPFakeThemeOptionButton new];
    activePreset.isSelected = YES;
    activePreset.showsEditIcon = YES;
    [pane.themePicker themeClicked:activePreset];
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#112233"], @"clicking pencil icon preserves custom color");

    // Dia rebuilding form re-mounts Custom Color row cleanly without duplicates.
    [pane rebuildForm];
    Check(pane.formRows.arrangedSubviews.count == 4, @"rebuildForm automatically re-mounts Custom Color row");
    DPProfileColorRow *rebuiltRow = (DPProfileColorRow *)pane.formRows.arrangedSubviews[3];
    Check([rebuiltRow isKindOfClass:DPProfileColorRow.class] && [rebuiltRow.hexField.stringValue isEqualToString:@"#112233"], @"rebuilt row preserves saved hex");

    // Clicking another preset swatch clears custom color and restores Dia's gradient!
    DPFakeThemeOptionButton *otherPreset = [DPFakeThemeOptionButton new];
    otherPreset.isSelected = NO;
    otherPreset.showsEditIcon = NO;
    [pane.themePicker themeClicked:otherPreset];
    Check(DPProfileHexForSpace(@"space-A") == nil, @"clicking another preset clears custom color");
    Check([rebuiltRow.hexField.stringValue isEqualToString:@""] && rebuiltRow.clearButton.hidden, @"preset click resets row UI");
    Check([gradA.gradientLayer.colors isEqual:diaA], @"preset click restores Dia's original gradient");

    // Re-apply custom color on space-A, then turn tweak OFF (and test Pause/off restoration).
    [rebuiltRow applyHex:@"#33CC66" fromField:NO];
    Check(DPColorsMatchHex(gradA.gradientLayer.colors, @"#33CC66"), @"custom color re-applied before off check");
    DPProfileColorPicker.on = NO;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    Check(pane.formRows.arrangedSubviews.count == 2, @"off removes Custom Color row cleanly");
    Check([gradA.gradientLayer.colors isEqual:diaA], @"off restores winA to Dia's original gradient");
    Check([gradSingle.gradientLayer.colors isEqual:diaSingle], @"off restores winSingle to Dia's original gradient");
    Check(DPProfileHexForSpace(@"space-A") == nil && [DPSavedProfileHexForSpace(@"space-A") isEqualToString:@"#33CC66"], @"off hides active color while preserving saved preference");
    Check(DPProfileColorPicker.verify(&DPProfileColorPicker) == nil, @"verify clean after turning off");

    // Off-tweak invariant: subsequent updateLayer while OFF must not re-apply custom color.
    [gradA updateLayer];
    [tintA updateLayer];
    Check([gradA.gradientLayer.colors isEqual:diaA], @"off invariant: updateLayer leaves Dia gradient untouched");

    // --- Neutral preset (alpha=0) + Space switch + Appearance/Intensity + ColorWell/HexField edge cases ---
    DPProfileColorPicker.on = YES;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    // Reset space-A & space-B custom colors.
    DPSetProfileHexForSpace(@"space-A", nil);
    DPSetProfileHexForSpace(@"space-B", nil);
    DPRefreshProfileColors();

    // 1. Neutral preset on space-A (diaAlpha = 0.0) + custom color #FF5733 in Light & Dark & high intensity.
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

    // 2. Switching winA from Neutral+Custom space-A (alpha=0.75) to Colored preset space-B (no custom color, diaAlpha=0.75!)
    // MUST NOT misidentify space-B's 0.75 alpha as our Neutral override and wipe it to 0.0!
    gradA.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    tintA->tint.themeIntensity = 0.0;
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"Neutral+Custom space-A at Light default alpha 0.75");
    indicator.focusedSpaceID = @"space-B";
    tintA.diaAlpha = 0.75;
    gradA.diaColors = diaSingle;
    [gradA updateLayer];
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"switching from Neutral+Custom space-A to Colored space-B preserves space-B alpha 0.75");
    Check([gradA.gradientLayer.colors isEqual:diaSingle], @"switching to Colored space-B preserves space-B gradient colors");

    // Reverse update order ([tintA updateLayer] before [gradA updateLayer]) also preserves space-B alpha & colors!
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

    // Even if space switcher fires BEFORE tintA updateLayer, space-B alpha is NOT wiped to 0.0!
    indicator.focusedSpaceID = @"space-A";
    tintA.diaAlpha = 0.0;
    gradA.diaColors = diaA;
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"returning to Neutral+Custom space-A restores fallback alpha 0.75");
    indicator.focusedSpaceID = @"space-B";
    gradA.alphaValue = 0.75;
    DPRefreshProfileColorForWindow(winA);
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"space switch refresh does not wipe space-B 0.75 alpha to 0.0");

    // Clicking a Colored preset on space-A after Neutral+Custom restores Colored preset alpha 0.75, not 0.0.
    indicator.focusedSpaceID = @"space-A";
    tintA.diaAlpha = 0.0;
    [tintA updateLayer];
    tintA.diaAlpha = 0.75;
    [pane.themePicker themeClicked:otherPreset];
    [tintA updateLayer];
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"clicking Colored preset after Neutral+Custom keeps preset alpha 0.75");

    // Clearing / turning tweak OFF on Neutral space-A DOES restore Dia's 0.0 alpha.
    tintA.diaAlpha = 0.0;
    [tintA updateLayer];
    DPSetProfileHexForSpace(@"space-A", @"#22AA44");
    DPRefreshProfileColorForWindow(winA);
    Check(fabs(gradA.alphaValue - 0.75) < 0.01, @"Neutral+Custom re-enabled with alpha 0.75");
    DPProfileColorPicker.on = NO;
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    Check(fabs(gradA.alphaValue - 0.0) < 0.01, @"turning tweak OFF restores Neutral space-A alpha to 0.0");

    // 3. DPProfileHexField Escape/Return & DPProfileColorRow switchToSpaceID / prepareForRemoval / window close safety.
    DPProfileColorPicker.on = YES;
    DPSetProfileHexForSpace(@"space-A", @"#112233");
    DPSetProfileHexForSpace(@"space-B", @"#AABBCC");
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    DPProfileColorRow *edgeRow = (DPProfileColorRow *)pane.formRows.arrangedSubviews[3];
    Check([edgeRow isKindOfClass:DPProfileColorRow.class] && [edgeRow.hexField.stringValue isEqualToString:@"#112233"], @"edgeRow synced to space-A");

    // Escape after typing valid 3-digit shorthand #0AF must cancel cleanly WITHOUT committing #00AAFF!
    NSTextView *mockEditor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 80, 20)];
    mockEditor.string = @"#0AF";
    edgeRow.hexField.stringValue = @"#0AF";
    BOOL handledEsc = [edgeRow.hexField control:edgeRow.hexField textView:mockEditor doCommandBySelector:@selector(cancelOperation:)];
    Check(handledEsc && [edgeRow.hexField.stringValue isEqualToString:@"#112233"] && [mockEditor.string isEqualToString:@"#112233"],
          @"Escape restores saved hex in both hexField and field editor");
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#112233"], @"Escape on valid 3-digit shorthand does not commit");

    // Return commits valid 3-digit shorthand once and updates field editor string.
    mockEditor.string = @"#0AF";
    edgeRow.hexField.stringValue = @"#0AF";
    BOOL handledRet = [edgeRow.hexField control:edgeRow.hexField textView:mockEditor doCommandBySelector:@selector(insertNewline:)];
    Check(handledRet && [DPProfileHexForSpace(@"space-A") isEqualToString:@"#00AAFF"] && [mockEditor.string isEqualToString:@"#00AAFF"],
          @"Return expands and commits 3-digit shorthand once");

    // switchToSpaceID: must not leak space-A's in-progress edit into space-B and deactivates well.
    edgeRow.hexField.stringValue = @"#999999";
    [edgeRow.well activate:NO];
    [edgeRow switchToSpaceID:@"space-B"];
    Check([edgeRow.spaceID isEqualToString:@"space-B"] && [edgeRow.hexField.stringValue isEqualToString:@"#AABBCC"] && !edgeRow.well.isActive,
          @"switchToSpaceID deactivates well and loads space-B without leaking edit");
    Check([DPProfileHexForSpace(@"space-A") isEqualToString:@"#00AAFF"] && [DPProfileHexForSpace(@"space-B") isEqualToString:@"#AABBCC"],
          @"switchToSpaceID preserves both spaces' saved colors");

    // prepareForRemoval while hexField is empty must NOT erase space-B's saved color on controlTextDidEndEditing:.
    edgeRow.hexField.stringValue = @"";
    [edgeRow.well activate:NO];
    [edgeRow prepareForRemoval];
    [edgeRow.hexField controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:edgeRow.hexField]];
    Check(!edgeRow.well.isActive && [DPProfileHexForSpace(@"space-B") isEqualToString:@"#AABBCC"],
          @"prepareForRemoval suppresses end-editing commit and preserves saved color");

    // NSWindowWillCloseNotification deactivates active color well cleanly (Settings window has releasedWhenClosed = NO).
    DPProfileColorPicker.apply(&DPProfileColorPicker);
    [pane rebuildForm];
    DPProfileColorRow *closeRow = (DPProfileColorRow *)pane.formRows.arrangedSubviews[3];
    [closeRow.well activate:NO];
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:settingsWin];
    Check(!closeRow.well.isActive, @"NSWindowWillCloseNotification deactivates active color well");

    // Clicking a preset swatch deactivates active color well.
    [closeRow.well activate:NO];
    [pane.themePicker themeClicked:otherPreset];
    Check(!closeRow.well.isActive, @"clicking preset swatch deactivates active color well");

    [panel close];
    [settingsWin close];
    [winA close];
    [winSingle close];
    [winPriv close];
}

int main(void) {
    @autoreleasepool {
        Method orig = class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:));
        Method swiz = class_getInstanceMethod(NSUserDefaults.class, @selector(dp_testInitWithSuiteName:));
        method_exchangeImplementations(orig, swiz);

        [NSApplication sharedApplication];
        TestHexParsingAndFormatting();
        TestUIMountTintAndOffInvariant();

        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:DPTestSuiteName()];
        if (failures) {
            printf("%d profile-color-picker test(s) failed\n", failures);
            return 1;
        }
        printf("all profile-color-picker tests passed\n");
        return 0;
    }
}

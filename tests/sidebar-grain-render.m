#import "sidebar-grain-render.h"

extern DPPatch DPKeepWindowsActive;
@interface NSWindow (DPTestAppearance)
- (BOOL)_hasActiveAppearance;
@end

NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";

__attribute__((objc_runtime_name(DPDiaSettingsController)))
@interface DPTestSettingsController : NSViewController
@end
@implementation DPTestSettingsController
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)]; }
@end

@interface NSWindow (DPTestShadow)
- (BOOL)hasKeyAppearance;
- (void)_setShadowParameters;
@end

static NSUInteger DPTestKeyWindowQueries;
static NSWindow *DPTestKeyWindow;

@interface DPTestBrowserWindow : NSWindow
@property BOOL shown;
@property NSUInteger visibleQueries, refreshes;
@end
@implementation DPTestBrowserWindow
- (BOOL)isVisible { self.visibleQueries++; return self.shown; }
- (void)_setShadowParameters { self.refreshes++; [super _setShadowParameters]; }
@end

static NSWindow *DPTestApp_keyWindow(id self, SEL _cmd) { DPTestKeyWindowQueries++; return DPTestKeyWindow; }

static void DPTestSettle(void) {
    for (int round = 0; round < 4; round++) {
        __block BOOL done = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
        while (!done) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, true);
    }
}

static void DPTestRunBlock(void (^__strong *block)(void)) { (*block)(); }

static void DPTestFocus(NSWindow *settings, BOOL key) {
    DPTestKeyWindow = key ? settings : nil;
    [NSNotificationCenter.defaultCenter postNotificationName:key ? NSWindowDidBecomeKeyNotification : NSWindowDidResignKeyNotification object:settings];
}

static void DPTestSettingsPreview(NSAppearance *appearance) {
    DPPatch *patch = &DPKeepWindowsActive;
    BOOL savedOn = patch->on;
    NSInteger savedSafeMode = DPSafeMode;
    BOOL savedPaused = DPPaused, savedPausedAtLaunch = DPPausedAtLaunch;
    Method method = class_getInstanceMethod(NSApplication.class, @selector(keyWindow));
    IMP original = method_setImplementation(method, (IMP)DPTestApp_keyWindow);
    __attribute__((objc_precise_lifetime)) DPTestSettingsController *controller = [DPTestSettingsController new];
    NSWindow *settings = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    settings.releasedWhenClosed = NO;
    settings.contentViewController = controller;
    DPTestBrowserWindow *browser = [[DPTestBrowserWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 250)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    browser.releasedWhenClosed = NO;
    browser.appearance = appearance;
    browser.shown = YES;
    DPSidebarGrainView *grain = [[DPSidebarGrainView alloc] initWithFrame:browser.contentView.bounds];
    grain.tracksWindowActivity = YES;
    [browser.contentView addSubview:grain];
    void (^restore)(void) __attribute__((cleanup(DPTestRunBlock), unused)) = ^{
        DPTestFocus(settings, NO);
        DPTestSettle();
        browser.shown = NO;
        [grain removeFromSuperview];
        patch->on = savedOn;
        DPSafeMode = savedSafeMode;
        DPPaused = savedPaused;
        DPPausedAtLaunch = savedPausedAtLaunch;
        DPTestKeyWindow = nil;
        method_setImplementation(method, original);
        patch->apply(patch);
    };
    BOOL (^lookActive)(void) = ^BOOL {
        BOOL active = browser._hasActiveAppearance;
        assert(browser.hasKeyAppearance == active);
        return active;
    };
    BOOL (^grainShown)(void) = ^BOOL { return [[grain valueForKey:@"grainOpacity"] doubleValue] > 0; };

    DPSafeMode = 0; DPPaused = NO; DPPausedAtLaunch = NO;
    patch->on = NO;
    DPKeepWindowsActive.install();
    DPKeepWindowsActive.install();
    patch->apply(patch);
    assert(!lookActive() && !grainShown());

    // Off with no Settings window key, the hot queries read two flags and touch no window or app state.
    browser.visibleQueries = DPTestKeyWindowQueries = 0;
    for (int i = 0; i < 50; i++) { (void)browser._hasActiveAppearance; (void)browser.hasKeyAppearance; }
    assert(DPTestKeyWindowQueries == 0 && browser.visibleQueries == 0);

    // (a) Behind Settings the browser window looks active even though the tweak is off, and the Settings window itself never does.
    DPTestFocus(settings, YES);
    DPTestSettle();
    assert(lookActive() && grainShown());
    assert(!settings._hasActiveAppearance && !settings.hasKeyAppearance);
    browser.shown = NO;
    assert(!lookActive());
    browser.shown = YES;
    assert(lookActive());

    // (c) It goes back to inactive once Settings resigns key, and a second resign has nothing left to refresh.
    DPTestFocus(settings, NO);
    DPTestSettle();
    assert(!lookActive() && !grainShown());
    NSUInteger refreshes = browser.refreshes;
    DPTestFocus(settings, NO);
    DPTestSettle();
    assert(browser.refreshes == refreshes);

    // Rapid focus flips coalesce into one pass, and a pass that lands where it started refreshes nothing.
    NSUInteger passes = DPTestKeyWindowQueries;
    DPTestFocus(settings, YES); DPTestFocus(settings, NO); DPTestFocus(settings, YES);
    DPTestSettle();
    assert(DPTestKeyWindowQueries == passes + 1);
    assert(browser.refreshes == refreshes + 1 && lookActive() && grainShown());
    DPTestFocus(settings, NO); DPTestFocus(settings, YES);
    DPTestSettle();
    assert(browser.refreshes == refreshes + 1 && lookActive());

    // (b) Pausing while Settings is key ends the preview at once; neither a pause nor safe mode lets it start.
    DPPaused = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    DPTestSettle();
    assert(!lookActive() && !grainShown());
    DPPaused = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    DPTestSettle();
    assert(lookActive() && grainShown());
    DPTestFocus(settings, NO);
    DPTestSettle();
    assert(!lookActive());
    refreshes = browser.refreshes;
    for (int blocked = 0; blocked < 3; blocked++) {
        DPSafeMode = blocked == 0; DPPaused = blocked == 1; DPPausedAtLaunch = blocked == 2;
        DPTestFocus(settings, YES);
        DPTestSettle();
        assert(!lookActive() && !grainShown() && browser.refreshes == refreshes);
        DPTestFocus(settings, NO);
        DPTestSettle();
    }
    DPSafeMode = 0; DPPaused = NO; DPPausedAtLaunch = NO;

    // Switched on, the windows are active whatever Settings does and its focus changes cost nothing.
    patch->on = YES;
    patch->apply(patch);
    assert(lookActive() && grainShown());
    refreshes = browser.refreshes;
    DPTestFocus(settings, YES); DPTestFocus(settings, NO);
    DPTestSettle();
    assert(lookActive() && browser.refreshes == refreshes);
    patch->on = NO;
    patch->apply(patch);
    assert(!lookActive() && !grainShown());
}

@interface DPObserverGrainView : DPSidebarGrainView
@property NSUInteger notices;
@end
@implementation DPObserverGrainView
- (void)testNotice:(NSNotification *)note { self.notices++; }
@end

static CGContextRef DPTestBitmap(NSMutableData *data, CGColorSpaceRef space) {
    return CGBitmapContextCreate(data.mutableBytes, 200, 200, 8, 800, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
}

double DPTestTextureContrast(NSAppearance *appearance, NSString *texture, double amount, double softness, double scale) {
    DPTestTexture = texture;
    DPSidebarGrainView *view = [[DPSidebarGrainView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    view.appearance = appearance;
    [view setGrainAmount:amount softness:softness scale:scale];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    NSMutableData *overlay = [NSMutableData dataWithLength:200 * 200 * 4];
    CGContextRef context = DPTestBitmap(overlay, space);
    [appearance performAsCurrentDrawingAppearance:^{
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
        CGContextScaleCTM(context, 2, 2);
        [view drawRect:view.bounds];
        [NSGraphicsContext restoreGraphicsState];
    }];
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    NSMutableData *composite = [NSMutableData dataWithLength:200 * 200 * 4];
    context = DPTestBitmap(composite, space);
    BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
    const double base[] = {dark ? .10 : .64, dark ? .16 : .76, dark ? .19 : .82};
    BOOL fine = [texture isEqual:@"fine"];
    BOOL screen = [view.layer.compositingFilter isEqual:@"screenBlendMode"];
    CGContextSetRGBFillColor(context, base[0], base[1], base[2], 1);
    CGContextFillRect(context, CGRectMake(0, 0, 200, 200));
    CGContextSetBlendMode(context, fine ? kCGBlendModeNormal : screen ? kCGBlendModeScreen : kCGBlendModeMultiply);
    CGContextDrawImage(context, CGRectMake(0, 0, 200, 200), image);
    CGImageRelease(image); CGContextRelease(context); CGColorSpaceRelease(space);
    const uint8_t *pixels = composite.bytes;
    const uint8_t *source = overlay.bytes;
    double sum = 0, square = 0;
    for (NSUInteger i = 0; i < 40000; i++) {
        // Measure pre-8-bit-rounded luminance so dark flat blends don't amplify byte-boundary noise.
        double alpha = source[4*i+3] / 255.0, brightness = 0;
        for (NSUInteger c = 0; c < 3; c++) {
            double red = source[4*i+c] / 255.0;
            double value = fine ? base[c] * (1-alpha) + red : screen ? base[c] + red*(1-base[c]) : base[c] * (1-alpha+red);
            assert(fabs(pixels[4*i+c] - value*255) <= 2.1);
            brightness += value / 3;
        }
        sum += brightness; square += brightness * brightness;
        assert(pixels[4*i+3] == 255);
    }
    return sqrt(MAX(0, square/40000 - pow(sum/40000, 2)));
}

void DPTestTextureActivity(NSAppearance *appearance) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ DPKeepWindowsActive.install(); });
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 250)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.appearance = appearance;
    DPObserverGrainView *grain = [[DPObserverGrainView alloc] initWithFrame:window.contentView.bounds];
    [NSNotificationCenter.defaultCenter addObserver:grain selector:@selector(testNotice:) name:@"DPGrainFixtureUnrelated" object:nil];
    grain.tracksWindowActivity = YES;
    [window.contentView addSubview:grain];
    [NSNotificationCenter.defaultCenter postNotificationName:@"DPGrainFixtureUnrelated" object:nil];
    assert(grain.notices == 1);
    DPSidebarGrainView *preview = [[DPSidebarGrainView alloc] initWithFrame:NSMakeRect(0, 0, 100, 40)];
    [window.contentView addSubview:preview];
    for (NSString *texture in DPGrainMaterialKeys()) {
        DPTestTexture = texture;
        for (NSNumber *keepActive in @[@YES, @NO, @YES]) {
            DPKeepWindowsActive.on = keepActive.boolValue;
            DPKeepWindowsActive.apply(&DPKeepWindowsActive);
            assert(window._hasActiveAppearance == keepActive.boolValue);
            assert(([[grain valueForKey:@"grainOpacity"] doubleValue] > 0) == keepActive.boolValue);
            [preview setGrainAmount:100 softness:0 scale:100];
            assert([[preview valueForKey:@"grainOpacity"] doubleValue] > 0);
        }
        for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSAppearanceNameAqua]) {
            preview.appearance = [NSAppearance appearanceNamed:name];
            [preview layoutSubtreeIfNeeded];
            id expected = [texture isEqual:@"fine"] ? nil :
                [name isEqual:NSAppearanceNameDarkAqua] ? @"screenBlendMode" : @"multiplyBlendMode";
            assert((!expected && !preview.layer.compositingFilter) || [preview.layer.compositingFilter isEqual:expected]);
        }
    }
    [grain removeFromSuperview]; [preview removeFromSuperview];
    DPTestSettingsPreview(appearance);
}

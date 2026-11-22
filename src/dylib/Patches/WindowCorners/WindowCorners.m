#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import <objc/message.h>

extern DPPatch DPWindowCorners;
static const CGFloat DPCornerReach = 26, DPMaxRadius = 26;
static NSString *const DPRadiusSetting = @"windowCornerRadius";
static char DPRadiusKey, DPPathKey, DPMaskPathKey, DPShadowPathKey, DPBarTouchedKey;
#define DPCornerBars (@[ @DPDiaTabStrip, @DPDiaSidebarHeader, @DPDiaSidebarFooter ])

static CGFloat DPCornerRadius(NSWindow *window) { return ((CGFloat (*)(id, SEL))objc_msgSend)(window, @selector(_cornerRadius)); }
static CGFloat DPDiaRadius(id object, CGFloat current) { return [DPDiaValue(object, &DPRadiusKey, @(current)) doubleValue]; }

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

static CGFloat DPRadius(void) {
    id saved = [DPSettings() objectForKey:DPRadiusSetting];
    return saved ? MIN(MAX([saved doubleValue], 0), DPMaxRadius) : DPMaxRadius;
}

static BOOL DPInFullScreen(NSWindow *window) { return (window.styleMask & NSWindowStyleMaskFullScreen) != 0; }

CGFloat DPWindowCornerGrowth(NSWindow *window) {
    if (!DPWindowCorners.on || !DPIsKind(window, DPDiaWindow) || DPInFullScreen(window)) return 0;
    return DPRadius() - DPDiaRadius(window, DPCornerRadius(window));
}

// AppKit takes a radius under 1 as its default.
static CGFloat DPWindowTarget(NSWindow *window, CGFloat dia) { return DPWindowCorners.on && !DPInFullScreen(window) ? MAX(1, DPRadius()) : dia; }

static void DPRoundWindow(NSWindow *window) {
    CGFloat current = DPCornerRadius(window), dia = DPDiaRadius(window, current);
    CGFloat target = DPWindowTarget(window, dia);
    if (DPWindowCorners.on && !DPInFullScreen(window)) DPOverride(window, &DPRadiusKey, @(dia), @(target));
    else if (DPGet(window, &DPRadiusKey)) DPSet(window, &DPRadiusKey, nil);
    if (current == target) return;
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(window, @selector(_setCornerRadius:), target);
    // macOS 26.7 has no _updateWindowCornerMask, so its older _cornerMaskChanged redraws the mask there.
    SEL update = [window respondsToSelector:@selector(_updateWindowCornerMask)] ? @selector(_updateWindowCornerMask) : @selector(_cornerMaskChanged);
    if ([window respondsToSelector:update]) ((void (*)(id, SEL))objc_msgSend)(window, update);
    [window invalidateShadow];
}

static void DPRoundLayers(CALayer *layer, CGFloat growth) {
    CGFloat dia = DPDiaRadius(layer, layer.cornerRadius);
    if (dia >= 10) {
        CGFloat target = MAX(0, MIN(dia + growth, MAX(dia, MIN(CGRectGetWidth(layer.bounds), CGRectGetHeight(layer.bounds)) / 2)));
        if (target != dia) DPOverride(layer, &DPRadiusKey, @(dia), @(target));
        else if (DPGet(layer, &DPRadiusKey)) DPSet(layer, &DPRadiusKey, nil);
        if (layer.cornerRadius != target) layer.cornerRadius = target;
    }
    for (CALayer *sublayer in layer.sublayers) DPRoundLayers(sublayer, growth);
}

static void DPRoundCornerItems(NSView *root) {
    NSView *frame = root.window.contentView.superview;
    if (!frame) return;
    CGFloat growth = DPWindowCornerGrowth(root.window);
    if (growth == 0 && !DPGet(root, &DPBarTouchedKey)) return;
    DPSet(root, &DPBarTouchedKey, growth != 0 ? @YES : nil);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPFindView(root, ^BOOL(NSView *view) {
        if (view == root || DPDiaRadius(view.layer, view.layer.cornerRadius) < 10) return NO;
        NSRect rect = [view convertRect:view.bounds toView:frame], bounds = frame.bounds;
        BOOL side = NSMinX(rect) < DPCornerReach || NSMaxX(rect) > NSMaxX(bounds) - DPCornerReach;
        BOOL end = NSMinY(rect) < DPCornerReach || NSMaxY(rect) > NSMaxY(bounds) - DPCornerReach;
        DPRoundLayers(view.layer, side && end ? growth : 0);
        return NO;
    });
    [CATransaction commit];
}

static CGPathRef DPScaledPath(id owner, char *key, CGPathRef current, CGSize size, CGFloat base, CGFloat scale) {
    CGRect box = CGPathGetBoundingBox(current);
    if (!current || fabs(box.size.width - size.width) > 1 || fabs(box.size.height - size.height) > 1) return NULL;
    if (scale == 1) {
        NSArray *saved = DPGet(owner, key);
        if (!saved) return NULL;
        CGPathRef dia = (__bridge CGPathRef)saved[0];
        BOOL match = [saved[1] isEqual:(__bridge id)current];
        DPSet(owner, key, nil);
        return match && !CGPathEqualToPath(dia, current) ? (CGPathRef)CFAutorelease(CGPathCreateCopy(dia)) : NULL;
    }
    id dia = DPDiaValue(owner, key, (__bridge id)current);
    if (dia == (__bridge id)current) dia = CFBridgingRelease(CGPathCreateCopy(current));
    CGPathRef path = DPReshapeCorners((__bridge CGPathRef)dia, base * 1.6, scale, scale);
    DPOverride(owner, key, dia, (__bridge id)path);
    return CGPathEqualToPath(path, current) ? NULL : path;
}

static void DPRoundFloatingLayers(CALayer *layer, CGSize size, CGFloat base, CGFloat growth) {
    if (fabs(layer.bounds.size.width - size.width) < 1 && fabs(layer.bounds.size.height - size.height) < 1) {
        CGFloat dia = DPDiaRadius(layer, layer.cornerRadius);
        if (dia > 0) {
            CGFloat target = MAX(0, dia + growth);
            if (target != dia) DPOverride(layer, &DPRadiusKey, @(dia), @(target));
            else if (DPGet(layer, &DPRadiusKey)) DPSet(layer, &DPRadiusKey, nil);
            if (layer.cornerRadius != target) layer.cornerRadius = target;
        }
    }
    CGFloat scale = MAX(0, base + growth) / base;
    CAShapeLayer *shape = [layer isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)layer : nil;
    CAShapeLayer *mask = [layer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)layer.mask : nil;
    CGPathRef path;
    if ((path = DPScaledPath(shape, &DPPathKey, shape.path, size, base, scale))) shape.path = path;
    if ((path = DPScaledPath(mask, &DPMaskPathKey, mask.path, size, base, scale))) mask.path = path;
    if ((path = DPScaledPath(layer, &DPShadowPathKey, layer.shadowPath, size, base, scale))) layer.shadowPath = path;
    for (CALayer *sublayer in layer.sublayers) DPRoundFloatingLayers(sublayer, size, base, growth);
}

static void DPRoundFloatingSidebar(NSView *self);

static char DPFloatingCornerKVOContext;

// The watch holds the layer, so it can't go before the observer does.
@interface DPFloatingCornerWatch : NSObject
@property (nonatomic, weak) NSView *sidebar;
@property (nonatomic, strong) CALayer *layer;
- (void)detach;
@end

@implementation DPFloatingCornerWatch
- (instancetype)initWithSidebar:(NSView *)sidebar {
    if ((self = [super init])) {
        self.sidebar = sidebar;
        self.layer = sidebar.layer;
        if (self.layer) [self.layer addObserver:self forKeyPath:@"cornerRadius" options:0 context:&DPFloatingCornerKVOContext];
    }
    return self;
}

- (void)detach {
    CALayer *layer = _layer;
    _layer = nil;
    if (layer) [layer removeObserver:self forKeyPath:@"cornerRadius" context:&DPFloatingCornerKVOContext];
}

- (void)dealloc { [self detach]; }

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(CALayer *)layer change:(NSDictionary *)change context:(void *)context {
    if (context != &DPFloatingCornerKVOContext) return [super observeValueForKeyPath:keyPath ofObject:layer change:change context:context];
    __weak DPFloatingCornerWatch *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        DPFloatingCornerWatch *watch = weak;
        NSView *sidebar = watch.sidebar;
        if (watch.layer == layer && sidebar.layer == layer) DPRoundFloatingSidebar(sidebar);
    });
}
@end

static char DPWatchedKey;

static void DPRoundFloatingSidebar(NSView *self) {
    DPFloatingCornerWatch *watch = DPGet(self, &DPWatchedKey);
    if (!DPWindowCorners.on || !self.layer) {
        if (watch) {
            [watch detach];
            DPSet(self, &DPWatchedKey, nil);
        }
    } else if (watch.layer != self.layer) {
        [watch detach];
        DPSet(self, &DPWatchedKey, [[DPFloatingCornerWatch alloc] initWithSidebar:self]);
    }
    CGFloat base = DPDiaRadius(self.layer, self.layer.cornerRadius);
    if (base <= 0) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPRoundFloatingLayers(self.layer, self.bounds.size, base, DPWindowCornerGrowth(self.window));
    [CATransaction commit];
}

static void DPFloatingSidebar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFloatingSidebar_layout, self);
    if (DPWindowCorners.on || DPGet(self, &DPWatchedKey)) DPRoundFloatingSidebar(self);
}

static void DPBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPBar_layout, self);
    if (DPWindowCorners.on || DPGet(self, &DPBarTouchedKey)) DPRoundCornerItems(self);
}

static void DPLayer_addAnimation(CALayer *self, SEL _cmd, CAAnimation *animation, NSString *key) {
    DPCallOriginal(DPLayer_addAnimation, self, DPWindowCorners.on ? DPReshapeDiaAnimation(self, animation) : animation, key);
}

static void DPShapeLayer_setPath(CAShapeLayer *self, SEL _cmd, CGPathRef path) {
    DPCallOriginal(DPShapeLayer_setPath, self, DPWindowCorners.on ? DPReshapeSetPath(self, NO, path) : path);
}

static void DPLayer_setShadowPath(CALayer *self, SEL _cmd, CGPathRef path) {
    DPCallOriginal(DPLayer_setShadowPath, self, DPWindowCorners.on ? DPReshapeSetPath(self, YES, path) : path);
}

// Rounder corners expose Dia's tiled background seams as the sidebar slides.
static void DPBackgroundTile_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (!DPWindowCorners.on) return DPCallOriginal(DPBackgroundTile_setFrame, self, frame);
    NSView *background = self.superview;
    DPCallOriginal(DPBackgroundTile_setFrame, self, DPIsKind(background, DPDiaWindowBackground) ? background.bounds : frame);
}

static void DPNavigationBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPNavigationBar_layout, self);
    if (!DPWindowCorners.on && !DPEdgeToEdge.on) return;
    NSView *container = self;
    while (container && !DPIsKind(container, DPDiaContentContainer)) container = container.superview;
    if (container) DPRoundCornerControls(container);
}

static void DPWindow_becomeKey(NSWindow *self, SEL _cmd) {
    DPCallOriginal(DPWindow_becomeKey, self);
    if (DPWindowCorners.on || DPGet(self, &DPRadiusKey)) DPRoundWindow(self);
}

static void DPApplyWindowCorners(DPPatch *patch) {
    Class floatingCls = objc_getClass(DPDiaFloatingSidebar), bgCls = objc_getClass(DPDiaWindowBackground);
    for (NSWindow *window in NSApp.windows) {
        if (DPIsKind(window, DPDiaWindow)) DPRoundWindow(window);
        DPFindView(window.contentView, ^BOOL(NSView *view) {
            for (NSString *bar in DPCornerBars)
                if (DPIsKind(view, bar.UTF8String)) DPRoundCornerItems(view);
            if (floatingCls && [view isKindOfClass:floatingCls]) {
                if (DPWindowCorners.on || DPGet(view, &DPWatchedKey)) DPRoundFloatingSidebar(view);
                view.needsLayout = YES;
            }
            if (bgCls && [view isKindOfClass:bgCls]) {
                view.needsLayout = YES;
                for (NSView *tile in view.subviews) tile.frame = tile.frame;
            }
            return NO;
        });
    }
    DPEdgeToEdge.relayout();
}

static NSString *DPVerifyWindowCorners(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows) {
        if (!DPIsKind(window, DPDiaWindow) || !window.isVisible) continue;
        CGFloat radius = DPCornerRadius(window);
        if (radius != DPWindowTarget(window, DPDiaRadius(window, radius)))
            return patch->on ? @"window corners aren't the chosen radius" : @"window corners keep the chosen radius";
    }
    return nil;
}

@interface DPRadiusRow : NSStackView <NSTextFieldDelegate>
@property NSSlider *slider;
@property NSTextField *field;
@end

@implementation DPRadiusRow
- (void)tune:(NSControl *)control {
    double radius = round(MIN(MAX(control.doubleValue, 0), DPMaxRadius));
    self.slider.doubleValue = self.field.doubleValue = radius;
    [DPSettings() setDouble:radius forKey:DPRadiusSetting];
    if (DPWindowCorners.on) DPApplyWindowCorners(&DPWindowCorners);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    NSNumber *step = @{ @"moveUp:" : @1, @"moveDown:" : @-1, @"moveUpAndModifySelection:" : @10, @"moveDownAndModifySelection:" : @-10 }[NSStringFromSelector(command)];
    if (!step) return NO;
    self.field.doubleValue = textView.string.doubleValue + step.doubleValue;
    [self tune:self.field];
    [textView selectAll:nil];
    return YES;
}
@end

static NSArray<NSView *> *DPWindowCornersRows(void) {
    DPRadiusRow *row = [DPRadiusRow new];
    row.slider = [NSSlider sliderWithValue:DPRadius() minValue:0 maxValue:DPMaxRadius target:row action:@selector(tune:)];
    row.field = [NSTextField textFieldWithString:@""];
    NSNumberFormatter *whole = [NSNumberFormatter new];
    whole.maximumFractionDigits = 0;
    row.field.formatter = whole;
    row.field.doubleValue = DPRadius();
    row.field.alignment = NSTextAlignmentRight;
    row.field.target = row.field.delegate = row;
    row.field.action = @selector(tune:);
    [row.field.widthAnchor constraintEqualToConstant:44].active = YES;
    [row.slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *hint = [NSTextField wrappingLabelWithString:@"26 pt is macOS 26, 10 pt is macOS 11 to 15, and 0 is square."];
    hint.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    hint.textColor = NSColor.secondaryLabelColor;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ row.slider, row.field, [NSTextField labelWithString:@"pt"] ]];
    [row setViews:@[ [NSTextField labelWithString:@"Radius"], controls, hint ] inGravity:NSStackViewGravityTop];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    [controls.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    return @[ row ];
}

static void DPInstallWindowCorners(void) {
    DPHook(DPDiaWindow, @selector(becomeKeyWindow), (IMP)DPWindow_becomeKey);
    DPHook(DPDiaFloatingSidebar, @selector(layout), (IMP)DPFloatingSidebar_layout);
    DPHook(DPDiaWindowBackgroundTile, @selector(setFrame:), (IMP)DPBackgroundTile_setFrame);
    DPHook(DPDiaToolbar, @selector(layout), (IMP)DPNavigationBar_layout);
    DPHookClass(CALayer.class, @selector(addAnimation:forKey:), (IMP)DPLayer_addAnimation);
    DPHookClass(CALayer.class, @selector(setShadowPath:), (IMP)DPLayer_setShadowPath);
    DPHookClass(CAShapeLayer.class, @selector(setPath:), (IMP)DPShapeLayer_setPath);
    for (NSString *bar in DPCornerBars) DPHook(bar.UTF8String, @selector(layout), (IMP)DPBar_layout);
    // AppKit flips the style mask just after each will, and a screen-sized window doesn't lay out.
    NSArray<NSNotificationName> *names = @[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
                                           NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification];
    for (NSNotificationName name in names)
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *_) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (DPWindowCorners.on) DPApplyWindowCorners(&DPWindowCorners); });
        }];
    DPOnLaunch(^{ if (DPWindowCorners.on) DPApplyWindowCorners(&DPWindowCorners); });
}

DP_PATCH(DPWindowCorners) {
    .key = @"windowCorners",
    .order = 97,
    .title = @"Window Corners",
    .detail = @"Round Dia’s windows like other apps on macOS 26, or pick a smaller radius down to square, with the page’s corners to match.",
    .symbol = @"app.fill",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaWindow, DPDiaToolbar, DPDiaFloatingSidebar, DPDiaWindowBackgroundTile, DPDiaWindowBackground, DPDiaTabStrip, DPDiaSidebarHeader, DPDiaSidebarFooter),
    .rows = DPWindowCornersRows,
    .install = DPInstallWindowCorners,
    .apply = DPApplyWindowCorners,
    .verify = DPVerifyWindowCorners,
};

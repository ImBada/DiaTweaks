#import "StdPatch/StdPatch.h"

extern DPPatch DPHideTabGroupBackground;
static char DPHiddenKey, DPTouchedKey;

static BOOL DPIsGrey(CGColorRef color) {
    NSColor *rgb = [[NSColor colorWithCGColor:color] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return NO;
    CGFloat r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent;
    return fabs(r - g) < 0.02 && fabs(g - b) < 0.02;
}

static void DPStyleBackground(NSView *cell) {
    BOOL on = DPHideTabGroupBackground.on;
    if (!on && !DPGet(cell, &DPTouchedKey)) return;
    CALayer *layer = DPSubview(cell, DPDiaTabGroupBackground).layer;
    NSArray *hidden = DPGet(layer, &DPHiddenKey);
    if (on && layer.backgroundColor && DPIsGrey(layer.backgroundColor)) {
        NSMutableArray *shadows = hidden ? hidden[1] : [NSMutableArray new];
        hidden = @[ hidden ? hidden[0] : @(layer.borderWidth), shadows, (__bridge id)layer.backgroundColor ];
        DPSet(layer, &DPHiddenKey, hidden);
        DPSet(cell, &DPTouchedKey, @YES);
        DPWithoutAnimation(^{
            for (CALayer *shadow in layer.sublayers) {
                if (shadow.hidden) continue;
                shadow.hidden = YES;
                [shadows addObject:shadow];
            }
            layer.backgroundColor = nil;
            layer.borderWidth = 0;
        });
        return;
    }
    if (hidden && (!on || layer.backgroundColor)) {
        DPWithoutAnimation(^{
            if (!layer.backgroundColor) layer.backgroundColor = (__bridge CGColorRef)hidden[2];
            layer.borderWidth = [hidden[0] doubleValue];
            for (CALayer *shadow in hidden[1]) shadow.hidden = NO;
        });
        DPSet(layer, &DPHiddenKey, nil);
    }
    if (!on) DPSet(cell, &DPTouchedKey, nil);
}

static void DPGroupCell_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGroupCell_updateLayer, self);
    DPStyleBackground(self);
}

static void DPApplyHideTabGroupBackground(DPPatch *patch) {
    for (NSView *cell in DPFindAllViews(DPDiaTabGroupCell)) {
        if (!patch->on) DPStyleBackground(cell);
        cell.needsDisplay = YES;
        DPSubview(cell, DPDiaTabGroupBackground).needsDisplay = YES;
    }
}

static NSString *DPVerifyHideTabGroupBackground(DPPatch *patch) {
    for (NSView *background in DPFindViews(DPDiaTabGroupBackground)) {
        if (patch->on && background.layer.backgroundColor && DPIsGrey(background.layer.backgroundColor)) return @"a tab group is still grey";
        if (!patch->on && DPGet(background.layer, &DPHiddenKey)) return @"a tab group background wasn't restored";
    }
    return nil;
}

static void DPInstallHideTabGroupBackground(void) {
    DPHook(DPDiaTabGroupCell, @selector(updateLayer), (IMP)DPGroupCell_updateLayer);
}

DP_PATCH(DPHideTabGroupBackground) {
    .key = @"hideTabGroupBackground",
    .order = 81,
    .title = @"Hide Group Background",
    .detail = @"Leave an open tab group without the grey behind it, unless you’ve picked a colour for the group.",
    .symbol = @"square.stack.fill square.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaTabGroupCell, DPDiaTabGroupBackground),
    .install = DPInstallHideTabGroupBackground,
    .apply = DPApplyHideTabGroupBackground,
    .verify = DPVerifyHideTabGroupBackground,
};

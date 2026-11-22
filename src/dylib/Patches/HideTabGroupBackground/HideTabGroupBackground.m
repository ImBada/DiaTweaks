#import "StdPatch/StdPatch.h"

extern DPPatch DPHideTabGroupBackground;
static char DPHiddenKey;

static BOOL DPIsGrey(CGColorRef color) {
    NSColor *rgb = [[NSColor colorWithCGColor:color] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return NO;
    CGFloat r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent;
    return fabs(r - g) < 0.02 && fabs(g - b) < 0.02;
}

static void DPStyleBackground(NSView *cell) {
    CALayer *layer = DPSubview(cell, DPDiaTabGroupBackground).layer;
    if (!layer) return;
    NSArray *hidden = DPGet(layer, &DPHiddenKey);
    if (DPHideTabGroupBackground.on && layer.backgroundColor && DPIsGrey(layer.backgroundColor)) {
        NSMutableArray *shadows = hidden ? hidden[1] : [NSMutableArray new];
        hidden = @[ hidden ? hidden[0] : @(layer.borderWidth), shadows, (__bridge id)layer.backgroundColor ];
        DPSet(layer, &DPHiddenKey, hidden);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (CALayer *shadow in layer.sublayers) {
            if (shadow.hidden) continue;
            shadow.hidden = YES;
            [shadows addObject:shadow];
        }
        layer.backgroundColor = nil;
        layer.borderWidth = 0;
        [CATransaction commit];
    } else if (hidden && (!DPHideTabGroupBackground.on || layer.backgroundColor)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (!layer.backgroundColor) layer.backgroundColor = (__bridge CGColorRef)hidden[2];
        layer.borderWidth = [hidden[0] doubleValue];
        for (CALayer *shadow in hidden[1]) shadow.hidden = NO;
        [CATransaction commit];
        DPSet(layer, &DPHiddenKey, nil);
    }
}

static void DPGroupCell_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGroupCell_updateLayer, self);
    DPStyleBackground(self);
}

static void DPCollectGroupCells(NSView *view, Class cls, NSMutableArray<NSView *> *out) {
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (NSView *sub in view.subviews) DPCollectGroupCells(sub, cls, out);
}

static void DPApplyHideTabGroupBackground(DPPatch *patch) {
    Class cls = objc_getClass(DPDiaTabGroupCell);
    if (!cls) return;
    NSMutableArray<NSView *> *cells = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows) DPCollectGroupCells(window.contentView, cls, cells);
    for (NSView *cell in cells) {
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
    .detail = @"Leave an open tab group without the grey behind it, unless you've picked a colour for the group.",
    .symbol = @"square.stack.fill square.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaTabGroupCell, DPDiaTabGroupBackground),
    .install = DPInstallHideTabGroupBackground,
    .apply = DPApplyHideTabGroupBackground,
    .verify = DPVerifyHideTabGroupBackground,
};

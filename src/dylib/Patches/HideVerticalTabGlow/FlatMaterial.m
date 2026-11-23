#import "HideVerticalTabGlow.h"

static Class DPGlassViewClass(void) {
    static Class glass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ glass = NSClassFromString(@"NSGlassEffectView"); });
    return glass;
}

static BOOL DPIsGlass(NSView *view) {
    Class glass = DPGlassViewClass();
    return glass && [view isKindOfClass:glass];
}

void DPFlattenTabMaterial(NSView *view, NSView *shape) {
    if (DPIsGlass(view)) DPHideTabDecoration(view, shape);
    for (NSView *sub in view.subviews) DPFlattenTabMaterial(sub, shape);
}

NSString *DPVerifyFlatTabMaterial(NSView *shape, BOOL on) {
    if (DPIsGlass(shape)) {
        if (on && !shape.hidden) return @"a vertical tab still has its glass highlight";
        if (!on && DPHasTabOverride(shape)) return @"tab glass wasn't restored";
    }
    for (NSView *sub in shape.subviews) {
        NSString *problem = DPVerifyFlatTabMaterial(sub, on);
        if (problem) return problem;
    }
    return nil;
}

static void DPGlass_viewDidMoveToSuperview(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGlass_viewDidMoveToSuperview, self);
    if (!DPHideVerticalTabGlow.on && !DPHasTabOverride(self)) return;
    DPWithoutAnimation(^{
        NSView *shape = nil;
        for (NSView *up = self.superview; up; up = up.superview)
            if (DPIsKind(up, DPDiaTabShape)) { shape = up; break; }
        if (shape) DPHideTabDecoration(self, shape);
        else DPRestoreTabDecoration(self);
    });
}

void DPInstallFlatTabMaterial(void) {
    Class glass = DPGlassViewClass();
    if (glass) DPHookClass(glass, @selector(viewDidMoveToSuperview), (IMP)DPGlass_viewDidMoveToSuperview);
}

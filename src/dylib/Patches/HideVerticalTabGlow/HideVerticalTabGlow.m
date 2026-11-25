#import "HideVerticalTabGlow.h"

static const char *const DPDecorationIvars[] = { "$__lazy_storage_$_shadowLayer", "rimHighlightView", NULL };
char DPTabStyledKey;
static NSHashTable<NSView *> *DPStyledShapes;

void DPTrackStyledShape(NSView *shape) {
    if (!shape) return;
    if (!DPStyledShapes) DPStyledShapes = [NSHashTable weakObjectsHashTable];
    [DPStyledShapes addObject:shape];
}

static void DPStyleTab(NSView *shape) {
    BOOL active = DPHideVerticalTabGlow.on && DPIsVerticalTab(shape);
    if (!active && !DPGet(shape, &DPTabStyledKey)) return;
    DPSet(shape, &DPTabStyledKey, active ? @YES : nil);
    if (active) DPTrackStyledShape(shape);
    else [DPStyledShapes removeObject:shape];
    DPWithoutAnimation(^{
        for (const char *const *name = DPDecorationIvars; *name; name++) {
            id part = DPTabDecoration(shape, *name);
            if (active) DPHideTabDecoration(part, shape);
            else DPRestoreTabDecoration(part);
        }
        DPFlattenTabMaterial(shape, shape);
        DPStyleUniformTabBorder(shape);
    });
}

static void DPTabShape_restyle(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabShape_restyle, self);
    if (DPHideVerticalTabGlow.on || DPGet(self, &DPTabStyledKey)) DPStyleTab(self);
}

static void DPApplyHideVerticalTabGlow(DPPatch *patch) {
    for (NSView *shape in DPFindViews(DPDiaTabShape)) DPStyleTab(shape);
    for (NSView *shape in patch->on ? DPFindAllViews(DPDiaTabShape) : DPStyledShapes.allObjects) DPStyleTab(shape);
}

static NSString *DPVerifyHideVerticalTabGlow(DPPatch *patch) {
    for (NSView *shape in DPFindViews(DPDiaTabShape)) {
        BOOL active = patch->on && DPIsVerticalTab(shape);
        for (const char *const *name = DPDecorationIvars; *name; name++) {
            if (active && !DPIvar(shape, *name)) return @"tab decoration is unavailable";
            id part = DPTabDecoration(shape, *name);
            if (active && part && (!DPHasTabOverride(part) || ![part isHidden])) return @"a vertical tab still has its glow";
            if (!active && DPHasTabOverride(part)) return @"a tab decoration wasn't restored";
        }
        NSString *problem = DPVerifyFlatTabMaterial(shape, active) ?: DPVerifyUniformTabBorder(shape, active);
        if (problem) return problem;
    }
    return nil;
}

static void DPInstallHideVerticalTabGlow(void) {
    DPHook(DPDiaTabShape, @selector(layout), (IMP)DPTabShape_restyle);
    DPHook(DPDiaTabShape, @selector(viewDidChangeEffectiveAppearance), (IMP)DPTabShape_restyle);
    DPHook(DPDiaTabShape, @selector(viewDidMoveToSuperview), (IMP)DPTabShape_restyle);
    DPHook(DPDiaTabShape, @selector(viewDidMoveToWindow), (IMP)DPTabShape_restyle);
    DPInstallFlatTabMaterial();
}

DP_PATCH(DPHideVerticalTabGlow) {
    .key = @"hideVerticalTabGlow",
    .order = 75,
    .title = @"Hide Vertical Tab Glow",
    .detail = @"Remove the selected sidebar tab’s glow and glass highlights, with a uniform border.",
    .symbol = @"sun.max",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaTabShape, DPVerticalSidebarRoot, DPDiaTabStrip),
    .install = DPInstallHideVerticalTabGlow,
    .apply = DPApplyHideVerticalTabGlow,
    .verify = DPVerifyHideVerticalTabGlow,
};

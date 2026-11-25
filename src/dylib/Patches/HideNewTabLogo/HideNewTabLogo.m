#import "StdPatch/StdPatch.h"

static const char *const DPLogoClasses[] = {DPDiaNewTabLogoView, DPDiaNewTabLogo, DPDiaNewTabLogoParticles};

static BOOL DPIsNewTabLogo(NSView *view) {
    BOOL logo = NO;
    for (size_t i = 0; i < sizeof DPLogoClasses / sizeof *DPLogoClasses && !logo; i++) logo = DPIsKind(view, DPLogoClasses[i]);
    if (!logo) return NO;
    for (NSView *up = view.superview; up; up = up.superview)
        if (DPIsKind(up, DPDiaNewTabPage)) return YES;
    return NO;
}

DP_PATCH(DPHideNewTabLogo) {
    .key = @"hideNewTabLogo",
    .order = 93,
    .section = @"New Tab Page",
    .title = @"Hide New Tab Logo",
    .detail = @"Hide the Dia logo above the search field on new tab pages.",
    .symbol = @"circle.dashed",
    .tint = @"systemGrayColor",
    .classes = DPClasses(DPDiaNewTabPage),
    .hides = DPIsNewTabLogo,
};

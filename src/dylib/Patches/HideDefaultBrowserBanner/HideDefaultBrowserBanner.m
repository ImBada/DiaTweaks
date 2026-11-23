#import "StdPatch/Hide.h"

static BOOL DPIsDefaultBrowserBanner(NSView *view) { return DPIsKind(view, DPDiaDefaultBrowserBanner); }

// The new tab page lays the banner out, so host it wherever Dia puts it.
static void DPBanner_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPBanner_layout, self);
}

static void DPInstallHideDefaultBrowserBanner(void) {
    DPHook(DPDiaDefaultBrowserBanner, @selector(layout), (IMP)DPBanner_layout);
}

DP_PATCH(DPHideDefaultBrowserBanner) {
    .key = @"hideDefaultBrowserBanner",
    .order = 93,
    .section = @"New Tab Page",
    .title = @"Hide Default Browser Banner",
    .detail = @"Hide the “Dia works best as your default browser” banner at the bottom of new tab pages. You can still set Dia as the default in Settings.",
    .symbol = @"safari",
    .tint = @"systemGrayColor",
    .classes = DPClasses(DPDiaDefaultBrowserBanner),
    .hides = DPIsDefaultBrowserBanner,
    .install = DPInstallHideDefaultBrowserBanner,
};

#import "StdPatch/Hide.h"

static BOOL DPIsDefaultBrowserBanner(NSView *view) { return DPIsKind(view, DPDiaDefaultBrowserBanner); }

static void DPInstallHideDefaultBrowserBanner(void) { DPHostHides(DPDiaDefaultBrowserBanner); }

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

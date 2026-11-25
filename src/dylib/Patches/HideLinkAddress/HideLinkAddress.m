#import "StdPatch/Hide.h"

static BOOL DPIsLinkAddress(NSView *view) { return DPIsKind(view, DPDiaStatusText); }

static void DPInstallHideLinkAddress(void) { DPHostHides(DPDiaStatusText); }

DP_PATCH(DPHideLinkAddress) {
    .key = @"hideLinkAddress",
    .order = 105,
    .section = @"Links",
    .title = @"Hide Link Address",
    .detail = @"Hide the address that shows at the bottom of the page when you point at a link.",
    .symbol = @"text.bubble.fill",
    .tint = @"systemMintColor",
    .classes = DPClasses(DPDiaStatusText),
    .hides = DPIsLinkAddress,
    .install = DPInstallHideLinkAddress,
};

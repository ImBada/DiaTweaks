#import "EdgeToEdge.h"

static NSString *DPVerifyFullScreenOnly(DPPatch *patch) {
    if (!patch->on || !DPEdgeToEdge.on || DPAnimating()) return nil;
    for (NSView *container in DPFindViews(DPDiaContentContainer)) {
        if (DPWindowFullScreen(container.window) || DPChatCard(container)) continue;
        NSValue *requested = DPRequestedFrame(container);
        if (requested && !NSEqualRects(container.frame, requested.rectValue)) return @"a windowed page is still edge-to-edge";
    }
    return nil;
}

DP_PATCH(DPFullScreenOnly) {
    .key = @"fullScreenOnly",
    .defaultOn = NO,
    .order = 15,
    .title = @"Only in Full Screen",
    .detail = @"Remove the padding only when the window is in full screen.",
    .symbol = @"arrow.up.left.and.arrow.down.right",
    .tint = @"systemBlueColor",
    .requires = @"edgeToEdge",
    .relayout = DPRelayoutContainers,
    .verify = DPVerifyFullScreenOnly,
};

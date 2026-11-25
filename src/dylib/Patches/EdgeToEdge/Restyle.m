#import "EdgeToEdge.h"

static char DPChatKey, DPPendingRestyleKey, DPCheckChatKey;

static void DPRestyleContainerBody(NSView *container, BOOL allowFrame) {
    DPApplySquareCorners(container);
    if (!allowFrame || !DPEdgeToEdgeActive() || !DPChatCard(container)) return;
    NSValue *requested = DPRequestedFrame(container);
    if (requested && !NSEqualRects(container.frame, requested.rectValue) && DPMayAdjust(container)) container.frame = requested.rectValue;
}

void DPRestyleContainer(NSView *container) { DPRestyleContainerBody(container, YES); }

static void DPQueueRestyle(NSView *container, BOOL checkChat) {
    if (checkChat) DPSet(container, &DPCheckChatKey, @YES);
    if ([DPGet(container, &DPPendingRestyleKey) boolValue]) return;
    DPSet(container, &DPPendingRestyleKey, @YES);
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL check = [DPGet(container, &DPCheckChatKey) boolValue];
        DPSet(container, &DPPendingRestyleKey, nil);
        DPSet(container, &DPCheckChatKey, nil);
        if (check && DPEdgeToEdgeActive()) {
            BOOL chat = DPChatCard(container) != nil;
            if ([DPGet(container, &DPChatKey) boolValue] != chat) {
                DPSet(container, &DPChatKey, @(chat));
                NSValue *requested = DPRequestedFrame(container);
                if (requested) container.frame = requested.rectValue;
            }
        }
        DPRestyleContainer(container);
    });
}

static void DPContainer_layoutOrUpdateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContainer_layoutOrUpdateLayer, self);
    DPRestyleContainerBody(self, _cmd != @selector(updateLayer));
    if (DPEdgeToEdgeActive()) DPQueueRestyle(self, NO);
}

static void DPShadow_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPShadow_layout, self);
    if (!DPEdgeToEdgeActive()) return;
    NSView *container = self;
    while (container && !DPIsKind(container, DPDiaContentContainer)) container = container.superview;
    if (container) DPQueueRestyle(container, YES);
}

void DPInstallRestyle(void) {
    DPHook(DPDiaContentContainer, @selector(layout), (IMP)DPContainer_layoutOrUpdateLayer);
    DPHook(DPDiaContentContainer, @selector(updateLayer), (IMP)DPContainer_layoutOrUpdateLayer);
    DPHook(DPDiaShadowView, @selector(layout), (IMP)DPShadow_layout);
    // AppKit flips the style mask just after each will, and a screen-sized window doesn't lay out.
    NSArray<NSNotificationName> *names = @[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
                                           NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification];
    for (NSNotificationName name in names)
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *_) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (DPEdgeToEdgeActive()) DPRelayoutContainers(); });
        }];
}

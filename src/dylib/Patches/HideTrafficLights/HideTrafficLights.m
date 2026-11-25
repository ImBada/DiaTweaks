#import "StdPatch/Hide.h"

extern DPPatch DPHideTrafficLights;
static const CGFloat DPPinnedTabsInset = 6;
static char DPLightsKey, DPStackFrameKey;

static BOOL DPIsTrafficLights(NSView *view) { return DPIsKind(view, DPDiaTrafficLights); }

static NSRect DPLaidOutStack(NSView *stack) { return [DPDiaValue(stack, &DPStackFrameKey, @(stack.frame)) rectValue]; }

// Out of the stack the lights aren't subviews, so cache them on the header.
static void DPSidebarHeader_layout(NSView *self, SEL _cmd) {
    NSArray *held = DPGet(self, &DPLightsKey);
    if (!DPHideTrafficLights.on && !held) return DPCallOriginal(DPSidebarHeader_layout, self);
    NSView *lights = DPFindView(self, ^BOOL(NSView *view) { return DPIsTrafficLights(view); });
    if (lights && lights.superview) DPSet(self, &DPLightsKey, held = @[ lights, lights.superview ]);
    NSStackView *stack = held.lastObject;
    if (![stack isKindOfClass:NSStackView.class] || ![stack.views containsObject:held.firstObject]) {
        if (!DPHideTrafficLights.on) DPSet(self, &DPLightsKey, nil);
        return DPCallOriginal(DPSidebarHeader_layout, self);
    }
    // Writing a priority the stack already has re-invalidates its layout, so only write a new one.
    NSStackViewVisibilityPriority priority = DPHideTrafficLights.on ? NSStackViewVisibilityPriorityNotVisible : NSStackViewVisibilityPriorityMustHold;
    if ([stack visibilityPriorityForView:held.firstObject] != priority) [stack setVisibilityPriority:priority forView:held.firstObject];
    DPCallOriginal(DPSidebarHeader_layout, self);
    if (!DPHideTrafficLights.on) {
        NSRect laidOut = DPLaidOutStack(stack);
        if (DPGet(stack, &DPStackFrameKey) && !NSEqualRects(stack.frame, laidOut)) stack.frame = laidOut;
        DPSet(stack, &DPStackFrameKey, nil);
        DPSet(self, &DPLightsKey, nil);
        return;
    }
    if (!DPMayAdjust(stack)) return;
    NSRect laidOut = DPLaidOutStack(stack), frame = laidOut;
    if (NSMinX(laidOut) > DPPinnedTabsInset) {
        frame.origin.x = DPPinnedTabsInset;
        frame.size.width = NSMaxX(laidOut) - DPPinnedTabsInset;
    }
    DPOverride(stack, &DPStackFrameKey, @(laidOut), @(frame));
    if (!NSEqualRects(stack.frame, frame)) stack.frame = frame;
}

static void DPInstallHideTrafficLights(void) { DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPSidebarHeader_layout); }

static NSString *DPVerifyHideTrafficLights(DPPatch *patch) {
    NSString *problem = DPVerifyHides(patch);
    if (problem) return problem;
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        if (header.hiddenOrHasHiddenAncestor) continue;
        NSArray *held = DPGet(header, &DPLightsKey);
        if (!patch->on && held) return @"traffic light state left after turning off";
        NSStackView *stack = held.lastObject;
        if (![stack isKindOfClass:NSStackView.class]) continue;
        NSRect laidOut = DPLaidOutStack(stack);
        CGFloat left = patch->on ? MIN(NSMinX(laidOut), DPPinnedTabsInset) : NSMinX(laidOut);
        if (fabs(NSMinX(stack.frame) - left) > 0.5) return patch->on ? @"profile button isn't in line with the pinned tabs" : @"profile button moved";
        if (fabs(NSMaxX(stack.frame) - NSMaxX(laidOut)) > 0.5) return @"header buttons moved";
    }
    return nil;
}

DP_PATCH(DPHideTrafficLights) {
    .key = @"hideTrafficLights",
    .order = 98,
    .title = @"Hide Window Controls",
    .detail = @"Hide the close, minimize and zoom buttons. ⌘W, ⌘M and the Window menu still work.",
    .symbol = @"ellipsis",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaTrafficLights, DPDiaSidebarHeader),
    .hides = DPIsTrafficLights,
    .install = DPInstallHideTrafficLights,
    .verify = DPVerifyHideTrafficLights,
};

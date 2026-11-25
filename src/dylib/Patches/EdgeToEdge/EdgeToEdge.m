#import "EdgeToEdge.h"

const CGFloat DPWindowPadding = 6;
NSHashTable<NSView *> *DPContainers;
static char DPRequestedFrameKey, DPRadiusKey, DPAnimationKey;

NSValue *DPRequestedFrame(NSView *container) {
    return DPGet(container, &DPRequestedFrameKey);
}

static NSEdgeInsets DPGaps(NSView *superview, NSRect frame) {
    NSRect bounds = superview.bounds;
    CGFloat low = NSMinY(frame) - NSMinY(bounds), high = NSMaxY(bounds) - NSMaxY(frame);
    return NSEdgeInsetsMake(superview.isFlipped ? low : high, NSMinX(frame) - NSMinX(bounds), superview.isFlipped ? high : low, NSMaxX(bounds) - NSMaxX(frame));
}

static BOOL DPIsPadding(CGFloat gap) { return fabs(gap - DPWindowPadding) < 0.5; }

BOOL DPWindowFullScreen(NSWindow *window) {
    return window && (window.styleMask & NSWindowStyleMaskFullScreen);
}

CGFloat DPEdgeToEdgeAmount(NSView *view) {
    if (DPFullScreenOnly.progress <= 0 || DPWindowFullScreen(view.window)) return DPEdgeToEdge.progress;
    return DPEdgeToEdge.progress * (1 - DPFullScreenOnly.progress);
}

static NSRect DPEdgeToEdgeFrame(NSView *view, NSRect frame, CGFloat amount) {
    CGFloat inset = amount * DPWindowPadding;
    NSView *superview = view.superview;
    if (inset == 0 || !superview || DPChatCard(view)) return frame;
    NSEdgeInsets gaps = DPGaps(superview, frame);
    if (DPIsPadding(gaps.left)) frame.origin.x -= inset, frame.size.width += inset;
    if (DPIsPadding(gaps.right)) frame.size.width += inset;
    if (DPIsPadding(gaps.top)) {
        frame.size.height += inset;
        if (superview.isFlipped) frame.origin.y -= inset;
    }
    if (DPIsPadding(gaps.bottom)) {
        frame.size.height += inset;
        if (!superview.isFlipped) frame.origin.y -= inset;
    }
    return frame;
}

CGFloat DPBaseCornerRadius(NSView *container) {
    CGFloat *radius = DPIvar(container, "cornerRadius");
    return radius ? [DPDiaValue(container, &DPRadiusKey, @(*radius)) doubleValue] : 0;
}

static void DPSetCornerRadius(NSView *container, CGFloat inset) {
    CGFloat *radius = DPIvar(container, "cornerRadius");
    if (!radius) return;
    CGFloat growth = DPWindowCornerGrowth(container.window);
    if (inset == 0 && growth == 0 && !DPGet(container, &DPRadiusKey)) return;
    CGFloat base = DPBaseCornerRadius(container), target = MAX(0, base + inset + growth);
    if (target != base) DPOverride(container, &DPRadiusKey, @(base), @(target));
    else if (DPGet(container, &DPRadiusKey)) DPSet(container, &DPRadiusKey, nil);
    if (*radius == target) return;
    *radius = target;
    container.needsLayout = YES;
}

void DPAnimateLayer(NSView *container, CALayer *layer, NSString *key, id value) {
    NSArray *animation = DPGet(container, &DPAnimationKey);
    CFTimeInterval remaining = [animation.firstObject doubleValue] - CACurrentMediaTime();
    id from = [layer.presentationLayer valueForKey:key];
    DPWithoutAnimation(^{ [layer setValue:value forKey:key]; });
    if (remaining <= 0 || !from || [from isEqual:value]) return;
    CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:key];
    move.fromValue = from;
    move.toValue = value;
    move.duration = remaining;
    move.timingFunction = animation.lastObject;
    [layer addAnimation:move forKey:key];
}

static void DPContainer_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    BOOL active = DPEdgeToEdgeActive();
    if (active) {
        NSAnimationContext *context = NSAnimationContext.currentContext;
        if (context.allowsImplicitAnimation || CATransaction.animationDuration > 0) {
            CFTimeInterval duration = context.duration ?: CATransaction.animationDuration;
            CAMediaTimingFunction *timing = context.timingFunction ?: [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
            DPSet(self, &DPAnimationKey, @[ @(CACurrentMediaTime() + duration), timing ]);
        }
    } else if (DPGet(self, &DPAnimationKey)) {
        DPSet(self, &DPAnimationKey, nil);
    }
    // Only a live override needs Dia's frame kept: otherwise this is one NSValue and one associated write per frame set.
    BOOL recording = active || DPGet(self, &DPRequestedFrameKey) || DPGet(self, &DPAnimationKey);
    if (recording) {
        DPSet(self, &DPRequestedFrameKey, @(frame));
        [DPContainers addObject:self];
    }
    CGFloat amount = active && DPMayAdjust(self) ? DPEdgeToEdgeAmount(self) : 0;
    NSRect adjusted = amount > 0 ? DPEdgeToEdgeFrame(self, frame, amount) : frame;
    if (recording) DPSetCornerRadius(self, NSEqualRects(adjusted, frame) ? 0 : amount * DPWindowPadding);
    DPCallOriginal(DPContainer_setFrame, self, adjusted);
}

void DPRelayoutContainers(void) {
    // Setting a frame re-enters the hook, which adds to DPContainers, so walk a snapshot.
    for (NSView *container in DPContainers.allObjects) {
        NSValue *requested = DPRequestedFrame(container);
        if (requested) container.frame = requested.rectValue;
        container.needsLayout = container.needsDisplay = YES;
        DPRestyleContainer(container);
    }
}

static NSString *DPVerifyEdgeToEdge(DPPatch *patch) {
    NSArray<NSView *> *containers = DPFindViews(DPDiaContentContainer);
    if (!containers.count) return @"no web content found";
    for (NSView *container in containers) {
        NSValue *requested = DPRequestedFrame(container);
        if (!requested) {
            if (patch->on) return @"never saw Dia place the web content";
            continue;
        }
        CALayer *layer = DPRoundedContent(container).layer;
        BOOL square = patch->on && DPFullScreen(container);
        if (layer && (DPCornersRound(layer, YES) == square || (!DPBesideSidebar(container) && DPCornersRound(layer, NO) == square)))
            return square ? @"corners stay round in full screen" : @"corners are square out of full screen";
        if (!patch->on || DPEdgeToEdgeAmount(container) == 0 || DPChatCard(container)) {
            if (!NSEqualRects(container.frame, requested.rectValue)) return @"web content isn't where Dia put it";
            continue;
        }
        NSEdgeInsets gaps = DPGaps(container.superview, container.frame);
        if (fabs(gaps.right) > 0.5 || fabs(gaps.bottom) > 0.5) return @"web content doesn't reach the window's edge";
        if (fabs(gaps.top - DPWindowPadding) < 0.5 || fabs(gaps.left - DPWindowPadding) < 0.5) return @"padding left around web content";
    }
    return nil;
}

static void DPInstallEdgeToEdge(void) {
    DPContainers = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaContentContainer, @selector(setFrame:), (IMP)DPContainer_setFrame);
    DPInstallRestyle();
    DPInstallPopover();
}

DP_PATCH(DPEdgeToEdge) {
    .key = @"edgeToEdge",
    .defaultOn = YES,
    .order = 10,
    .title = @"Edge-to-Edge Web Pages",
    .detail = @"Remove the padding between web pages and the window edge.",
    .symbol = @"arrow.up.left.and.arrow.down.right.rectangle.fill arrow.up.left.and.arrow.down.right.square.fill",
    .tint = @"systemBlueColor",
    .section = @"Page",
    .classes = DPClasses(DPDiaContentContainer, DPDiaShadowView),
    .install = DPInstallEdgeToEdge,
    .relayout = DPRelayoutContainers,
    .verify = DPVerifyEdgeToEdge,
};

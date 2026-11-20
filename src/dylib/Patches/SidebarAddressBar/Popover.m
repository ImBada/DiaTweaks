#import "Editor.h"

static char DPQueryKey, DPRequestKey, DPAnchorKey, DPIdentifierKey, DPStartupLayerKey, DPStartupVisibilityKey, DPPendingParentKey;
static char DPQuietSuggestionKey;
static char DPQuietAccessibilityKey;
static NSString *const DPSidebarPopoverIdentifier = @"DiaTweaks.SidebarAddressBar.Popover";

@interface DPAddressRequest : NSObject
@property(weak) NSView *anchor;
@property CFTimeInterval expires;
@property(copy) NSString *query;
@end
@implementation DPAddressRequest @end

void DPSidebarRequestPopover(NSView *anchor) {
    DPSidebarRequestPopoverWithQuery(anchor, nil);
}

void DPSidebarRequestPopoverWithQuery(NSView *anchor, NSString *query) {
    DPAddressRequest *request = [DPAddressRequest new];
    request.anchor = anchor;
    request.query = query;
    request.expires = CACurrentMediaTime() + 1;
    DPSet(anchor.window, &DPRequestKey, request);
}

void DPSidebarCancelPopoverRequest(NSView *anchor) {
    DPAddressRequest *request = DPGet(anchor.window, &DPRequestKey);
    if (request.anchor == anchor) DPSet(anchor.window, &DPRequestKey, nil);
}

static NSRect DPAddressFrameInParent(NSView *page, NSRect proposed, NSView *parent) {
    NSView *anchor = DPGet(page, &DPAnchorKey);
    if (!DPSidebarAddressBar.on || !parent || anchor.window != parent.window || !anchor.superview) return proposed;
    NSRect row = [parent convertRect:anchor.bounds fromView:anchor];
    CGFloat width = MIN(NSWidth(row) + 20, NSWidth(parent.bounds) - 8);
    CGFloat height = MIN(NSHeight(proposed), MAX(0, NSHeight(parent.bounds) - 16));
    // The native shell has ten points of shadow padding. Align its visible panel, not that transparent shell.
    CGFloat x = MAX(NSMinX(parent.bounds) - 4, MIN(NSMinX(row) - 10, NSMaxX(parent.bounds) - width + 4));
    CGFloat top = parent.isFlipped ? NSMinY(row) - 10 : NSMaxY(row) + 10 - height;
    CGFloat y = MAX(NSMinY(parent.bounds) - 4, MIN(top, NSMaxY(parent.bounds) - height + 4));
    return NSMakeRect(round(x), round(y), MAX(0, width), height);
}

static NSRect DPAnchoredAddressFrame(NSView *page, NSRect proposed) { return DPAddressFrameInParent(page, proposed, page.superview ?: DPGet(page, &DPPendingParentKey)); }

static void DPClaimAddressPopover(NSView *self, NSWindow *window) {
    DPAddressRequest *request = DPGet(window, &DPRequestKey);
    if (window && DPSidebarAddressBar.on && request.anchor && request.expires > CACurrentMediaTime()) {
        DPSet(self, &DPAnchorKey, request.anchor);
        DPSet(self, &DPQueryKey, request.query);
        DPSet(self, &DPIdentifierKey, self.identifier ?: NSNull.null);
        self.identifier = DPSidebarPopoverIdentifier;
        DPSet(window, &DPRequestKey, nil);
    }
}

static id DPAddressPopup_animation(NSView *self, SEL _cmd, NSString *key) {
    if (DPSidebarAddressBar.on && ([key hasPrefix:@"frame"] || [key isEqual:@"bounds"])) {
        for (NSView *view = self; view; view = view.superview)
            if (DPGet(view, &DPAnchorKey)) return nil;
    }
    return DPCallOriginal(DPAddressPopup_animation, self, key);
}

static void DPAddressLayer_addAnimation(CALayer *self, SEL _cmd, CAAnimation *animation, NSString *key) {
    if (DPSidebarAddressBar.on) {
        for (CALayer *layer = self; layer; layer = layer.superlayer)
            if ([DPGet(layer,&DPStartupLayerKey) doubleValue] > CACurrentMediaTime()) return;
    }
    DPCallOriginal(DPAddressLayer_addAnimation,self,animation,key);
}

static void DPAddressClearOpeningAnimations(CALayer *layer) {
    for (NSString *key in layer.animationKeys)
        [layer removeAnimationForKey:key];
    for (CALayer *child in layer.sublayers) DPAddressClearOpeningAnimations(child);
    if (layer.mask) DPAddressClearOpeningAnimations(layer.mask);
}

static void DPAddressFreezeStartup(NSView *page) {
    if (!page.layer) return;
    DPSet(page.layer,&DPStartupLayerKey,@(CACurrentMediaTime()+0.25));
    DPAddressClearOpeningAnimations(page.layer);
}

static void DPAddressLayer_setHidden(CALayer *self, SEL _cmd, BOOL hidden) {
    // AppKit synchronizes its backing layer during the first layout pass.
    if (DPGet(self,&DPStartupVisibilityKey) || DPGet(self,&DPQuietSuggestionKey)) hidden = YES;
    DPCallOriginal(DPAddressLayer_setHidden,self,hidden);
}

static NSView *DPQuietSuggestion_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    if (DPGet(self.layer, &DPQuietSuggestionKey)) return nil;
    return DPCallOriginal(DPQuietSuggestion_hitTest, self, point);
}

void DPSidebarHideSuggestionSurface(NSView *surface, BOOL hide) {
    CALayer *layer = surface.layer;
    if (!layer) return;
    NSNumber *previous = DPGet(layer, &DPQuietSuggestionKey);
    if (hide) {
        DPHookClass(surface.class, @selector(hitTest:), (IMP)DPQuietSuggestion_hitTest);
        if (!previous) DPSet(layer, &DPQuietSuggestionKey, @(layer.hidden));
        if (!DPGet(surface, &DPQuietAccessibilityKey))
            DPSet(surface, &DPQuietAccessibilityKey, @(surface.accessibilityHidden));
        surface.accessibilityHidden = YES;
        layer.hidden = YES;
    } else if (previous) {
        DPSet(layer, &DPQuietSuggestionKey, nil);
        layer.hidden = previous.boolValue;
        surface.accessibilityHidden = [DPGet(surface, &DPQuietAccessibilityKey) boolValue];
        DPSet(surface, &DPQuietAccessibilityKey, nil);
    }
}

static void DPAddressRevealLayer(CALayer *layer) {
    NSArray<NSNumber *> *previous = DPGet(layer,&DPStartupVisibilityKey);
    if (!previous) return;
    DPSet(layer,&DPStartupVisibilityKey,nil);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.hidden = previous.firstObject.boolValue;
    [CATransaction commit];
}

NSView *DPSidebarEditorAnchor(NSView *view) {
    for (; view; view = view.superview) {
        NSView *anchor = DPGet(view, &DPAnchorKey);
        if (anchor.window && anchor.window == view.window) return anchor;
    }
    return nil;
}

static void DPAddressStageFirstPaint(NSView *page) {
    CALayer *layer = page.layer;
    if (!layer || DPGet(layer,&DPStartupVisibilityKey)) return;
    NSArray *previous = @[@(layer.hidden)];
    DPSet(layer,&DPStartupVisibilityKey,previous);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.hidden = YES;
    [CATransaction commit];
    __weak NSView *weakPage = page;
    // Let the native attachment finish, then lay out and reveal in the same render pass.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DPGet(layer,&DPStartupVisibilityKey) != previous) return;
        NSView *view = weakPage;
        if (view.window && DPGet(view,&DPAnchorKey)) {
            [NSAnimationContext beginGrouping];
            NSAnimationContext.currentContext.duration = 0;
            NSAnimationContext.currentContext.allowsImplicitAnimation = NO;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            view.frame = DPAnchoredAddressFrame(view,view.frame);
            [view layoutSubtreeIfNeeded];
            DPAddressClearOpeningAnimations(layer);
            DPSidebarAddressRow *anchor = DPGet(view, &DPAnchorKey);
            BOOL suggestionsOnly = DPGet(view, &DPQueryKey) != nil;

            DPAddressRevealLayer(layer);
            if (!suggestionsOnly) [anchor setNativeEditorVisible:YES];
            [CATransaction commit];
            [NSAnimationContext endGrouping];
            NSString *query = DPGet(view, &DPQueryKey);
            DPSet(view, &DPQueryKey, nil);
            if (query) {
                NSView *input = DPFindView(view, ^BOOL(NSView *child) {
                    return DPIsKind(child, DPDiaCommandBarText);
                });
                NSTextView *editor = (NSTextView *)DPFindView(input, ^BOOL(NSView *child) {
                    return [child isKindOfClass:NSTextView.class];
                });
                if (editor) [anchor attachSuggestionSession:view editor:editor];
                // Defer until Dia has completed the initial first-responder handoff.
                dispatch_async(dispatch_get_main_queue(), ^{
                    [anchor finishStartingSuggestionSession];
                });
            }
            return;
        }
        DPAddressRevealLayer(layer);
    });
}

static void DPAddressPopover_willMove(NSView *self, SEL _cmd, NSView *parent) {
    DPClaimAddressPopover(self, parent.window);
    if (parent && DPGet(self, &DPAnchorKey)) {
        DPSet(self, &DPPendingParentKey, parent);
        DPAddressFreezeStartup(self);
        DPAddressStageFirstPaint(self);
        self.frame = DPAddressFrameInParent(self, self.frame, parent);
    }
    DPCallOriginal(DPAddressPopover_willMove, self, parent);
}

static void DPAddressPopover_attached(NSView *self, SEL _cmd) {
    DPSet(self, &DPPendingParentKey, nil);
    DPClaimAddressPopover(self, self.window);
    if (!self.window && DPGet(self, &DPAnchorKey)) {
        DPSidebarAddressRow *anchor = DPGet(self, &DPAnchorKey);
        [anchor setNativeEditorVisible:NO];
        DPAddressRevealLayer(self.layer);
        id previous = DPGet(self, &DPIdentifierKey);
        self.identifier = previous == NSNull.null ? nil : previous;
        DPSet(self, &DPAnchorKey, nil);
        DPSet(self, &DPQueryKey, nil);
        DPSet(self, &DPIdentifierKey, nil);
    }
    DPCallOriginal(DPAddressPopover_attached, self);
    if (DPGet(self, &DPAnchorKey)) {
        self.frame = DPAnchoredAddressFrame(self, self.frame);
        DPAddressFreezeStartup(self);
        DPAddressStageFirstPaint(self);
        [self layoutSubtreeIfNeeded];
    }
}

static void DPAddressPopover_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (!DPGet(self, &DPAnchorKey)) return DPCallOriginal(DPAddressPopover_setFrame, self, frame);
    [NSAnimationContext beginGrouping];
    NSAnimationContext.currentContext.duration = 0;
    NSAnimationContext.currentContext.allowsImplicitAnimation = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPCallOriginal(DPAddressPopover_setFrame, self, DPAnchoredAddressFrame(self, frame));
    [CATransaction commit];
    [NSAnimationContext endGrouping];
}

static void DPAddressPopover_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    NSRect proposed = self.frame;
    proposed.origin = origin;
    DPCallOriginal(DPAddressPopover_setFrameOrigin, self, DPAnchoredAddressFrame(self, proposed).origin);
}

static void DPAddressPopover_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    if (!DPGet(self, &DPAnchorKey)) return DPCallOriginal(DPAddressPopover_setFrameSize, self, size);
    NSRect proposed = self.frame;
    proposed.size = size;
    DPCallOriginal(DPAddressPopover_setFrameSize, self, DPAnchoredAddressFrame(self, proposed).size);
}

void DPSidebarInstallPopover(void) {
    DPSidebarInstallSuggestionOverlay();
    DPHookClass(CALayer.class, @selector(setHidden:), (IMP)DPAddressLayer_setHidden);
    DPHookClass(CALayer.class, @selector(addAnimation:forKey:), (IMP)DPAddressLayer_addAnimation);
    DPHook(DPDiaPopover, @selector(viewWillMoveToSuperview:), (IMP)DPAddressPopover_willMove);
    DPHook(DPDiaPopover, @selector(viewDidMoveToWindow), (IMP)DPAddressPopover_attached);
    DPHook(DPDiaPopover, @selector(setFrame:), (IMP)DPAddressPopover_setFrame);
    DPHook(DPDiaPopover, @selector(animationForKey:), (IMP)DPAddressPopup_animation);
    DPHook(DPDiaAssistantPanel, @selector(animationForKey:), (IMP)DPAddressPopup_animation);
    DPHookClass(objc_getClass(DPDiaCommandBar), @selector(animationForKey:), (IMP)DPAddressPopup_animation);
    DPHookClass(objc_getClass(DPDiaCommandBarInput), @selector(animationForKey:), (IMP)DPAddressPopup_animation);
    DPHook(DPDiaPopover, @selector(setFrameSize:), (IMP)DPAddressPopover_setFrameSize);
    DPHook(DPDiaPopover, @selector(setFrameOrigin:), (IMP)DPAddressPopover_setFrameOrigin);
}

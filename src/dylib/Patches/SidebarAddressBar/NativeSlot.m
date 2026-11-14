#import "NativeSlot.h"

static char DPNativeSlotKey, DPSiteHoverLayerKey;

static void DPSiteHoverCornerRadius(CALayer *self, SEL _cmd, CGFloat radius) {
    DPCallOriginal(DPSiteHoverCornerRadius,self,DPGet(self,&DPSiteHoverLayerKey) ? 9 : radius);
}

static void DPSiteHoverMasksToBounds(CALayer *self, SEL _cmd, BOOL masks) {
    DPCallOriginal(DPSiteHoverMasksToBounds,self,DPGet(self,&DPSiteHoverLayerKey) ? YES : masks);
}

static void DPRestoreSiteHover(DPAddressNativeSlot *slot) {
    CALayer *layer = slot.styledHoverLayer;
    if (!layer) return;
    DPSet(layer,&DPSiteHoverLayerKey,nil);
    layer.cornerRadius = slot.originalCornerRadius;
    layer.masksToBounds = slot.originalMasksToBounds;
    slot.styledHoverLayer = nil;
}

void DPAddressStyleSiteHover(DPAddressNativeSlot *slot) {
    CALayer *layer = slot.view.layer;
    if (!layer || layer == slot.styledHoverLayer) return;
    DPRestoreSiteHover(slot);
    slot.styledHoverLayer = layer;
    slot.originalCornerRadius = layer.cornerRadius;
    slot.originalMasksToBounds = layer.masksToBounds;
    DPHookClass(CALayer.class,@selector(setCornerRadius:),(IMP)DPSiteHoverCornerRadius);
    DPHookClass(CALayer.class,@selector(setMasksToBounds:),(IMP)DPSiteHoverMasksToBounds);
    DPSet(layer,&DPSiteHoverLayerKey,@YES);
    layer.cornerRadius = 9;
    layer.masksToBounds = YES;
}
@implementation DPAddressNativeSlot @end
DPAddressNativeSlot *DPAddressNativeSlotFor(NSView *view) { return DPGet(view, &DPNativeSlotKey); }

// Dia still owns these controls and can remove them while changing profiles.
static void DPAddressStackRemove(NSStackView *self, SEL _cmd, NSView *view, BOOL animated, BOOL removeFromHierarchy) {
    DPAddressNativeSlot *slot = DPAddressNativeSlotFor(view);
    if (slot.home == self && !slot.moving && view.superview != self)
        DPRestoreAddressNative(slot);
    DPCallOriginal(DPAddressStackRemove,self,view,animated,removeFromHierarchy);
}

DPAddressNativeSlot *DPAttachAddressNative(NSView *view, NSView *owner, NSView *destination, NSRect frame, BOOL pinned) {
    if (!view || !view.superview || DPAddressNativeSlotFor(view)) return nil;
    DPAddressNativeSlot *slot = [DPAddressNativeSlot new];
    slot.view = view; slot.home = view.superview; slot.owner = owner; slot.pinned = pinned;
    slot.originalFrame = view.frame; slot.forcedFrame = frame; slot.naturalWidth = NSWidth(view.frame);
    slot.originalHidden = view.hidden; slot.originalAlpha = view.alphaValue;
    slot.originalMask = view.autoresizingMask; slot.originalTranslates = view.translatesAutoresizingMaskIntoConstraints;
    slot.index = [slot.home.subviews indexOfObjectIdenticalTo:view];
    slot.moving = YES;
    DPSet(view, &DPNativeSlotKey, slot);
    DPInstallAddressNativeHooks(view);
    if ([slot.home isKindOfClass:NSStackView.class]) {
        NSStackView *stack = (NSStackView *)slot.home;
        DPHookClass(stack.class,NSSelectorFromString(@"_removeView:animated:removeFromViewHierarchy:"),(IMP)DPAddressStackRemove);
        for (NSNumber *gravity in @[@(NSStackViewGravityLeading), @(NSStackViewGravityCenter), @(NSStackViewGravityTrailing)]) {
            NSUInteger index = [[stack viewsInGravity:gravity.integerValue] indexOfObjectIdenticalTo:view];
            if (index != NSNotFound) { slot.gravity = gravity.integerValue; slot.index = index; break; }
        }
        [stack removeView:view];
    } else {
        NSMutableArray *constraints = [NSMutableArray new];
        for (NSLayoutConstraint *constraint in slot.home.constraints)
            if (constraint.firstItem == view || constraint.secondItem == view) [constraints addObject:constraint];
        slot.constraints = constraints;
        [NSLayoutConstraint deactivateConstraints:constraints];
        [view removeFromSuperview];
    }
    view.autoresizingMask = NSViewNotSizable;
    view.translatesAutoresizingMaskIntoConstraints = YES;
    if ([destination isKindOfClass:NSClipView.class]) ((NSClipView *)destination).documentView = view;
    else [destination addSubview:view];
    view.frame = frame; view.hidden = NO; view.alphaValue = 1;
    slot.moving = NO;
    return slot;
}

void DPLayoutAddressNative(DPAddressNativeSlot *slot, NSRect frame) {
    if (!slot.view) return;
    slot.forcedFrame = frame;
    slot.moving = YES;
    if (!NSEqualRects(slot.view.frame, frame)) slot.view.frame = frame;
    if (slot.view.hidden != slot.forcedHidden) slot.view.hidden = slot.forcedHidden;
    if (slot.view.alphaValue != 1) slot.view.alphaValue = 1;
    slot.moving = NO;
}

void DPRestoreAddressNative(DPAddressNativeSlot *slot) {
    NSView *view = slot.view, *home = slot.home;
    if (!view) return;
    slot.moving = YES;
    DPSet(view, &DPNativeSlotKey, nil);
    if ([view.superview isKindOfClass:NSClipView.class]) ((NSClipView *)view.superview).documentView = nil;
    [view removeFromSuperview];
    if ([home isKindOfClass:NSStackView.class]) {
        NSStackView *stack = (NSStackView *)home;
        NSUInteger count = [stack viewsInGravity:slot.gravity].count;
        [stack insertView:view atIndex:MIN(slot.index, count) inGravity:slot.gravity];
    } else if (home) {
        NSArray *siblings = home.subviews;
        if (slot.index < siblings.count) [home addSubview:view positioned:NSWindowBelow relativeTo:siblings[slot.index]];
        else [home addSubview:view];
    }
    view.autoresizingMask = slot.originalMask;
    view.translatesAutoresizingMaskIntoConstraints = slot.originalTranslates;
    view.frame = slot.originalFrame; view.hidden = slot.originalHidden; view.alphaValue = slot.originalAlpha;
    DPRestoreSiteHover(slot);
    if (slot.icon) { slot.icon.image = slot.originalImage; slot.icon.contentTintColor = slot.originalTint; }
    if (home && slot.constraints.count) [NSLayoutConstraint activateConstraints:slot.constraints];
    home.needsLayout = YES;
    slot.owner = nil;
    slot.view = nil;
}

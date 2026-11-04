#import "Editor.h"

static char DPHoverKey;
@interface DPAddressHover : NSObject
@property NSTrackingArea *tracking;
@property BOOL hovered;
@end
@implementation DPAddressHover @end

static DPAddressHover *DPAddressHoverFor(NSView *row) {
    DPAddressHover *state = DPGet(row, &DPHoverKey);
    if (!state) DPSet(row, &DPHoverKey, state = [DPAddressHover new]);
    return state;
}

BOOL DPSidebarRowIsHovered(NSView *row) {
    return DPAddressHoverFor(row).hovered || (row.window && NSPointInRect(
        [row convertPoint:row.window.mouseLocationOutsideOfEventStream fromView:nil], row.bounds));
}

NSColor *DPSidebarEditorFill(void) {
    return [NSColor.textBackgroundColor blendedColorWithFraction:0.02 ofColor:NSColor.controlAccentColor];
}

NSColor *DPSidebarEditorBorder(void) {
    BOOL light = [[NSAppearance.currentDrawingAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameAqua];
    return light ? [NSColor.whiteColor colorWithAlphaComponent:0.85] :
        [NSColor.labelColor colorWithAlphaComponent:0.16];
}

void DPSidebarUpdateHover(NSView *row, BOOL animated) {
    id focus = row.window.firstResponder;
    BOOL focused = [focus isKindOfClass:NSView.class] && [(NSView *)focus isDescendantOf:row];
    BOOL editing = [(DPSidebarAddressRow *)row isEditingAddress];
    BOOL active = DPSidebarRowIsHovered(row) || focused;
    [row.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *fill = editing ? DPSidebarEditorFill() :
            [NSColor.labelColor colorWithAlphaComponent:active ? 0.11 : 0.06];
        NSColor *border = DPSidebarEditorBorder();
        CGColorRef color = fill.CGColor;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        row.layer.borderColor = border.CGColor;
        row.layer.borderWidth = editing ? 1 : 0;
        row.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        row.layer.masksToBounds = YES;
        [CATransaction commit];
        if (row.layer.backgroundColor && CGColorEqualToColor(row.layer.backgroundColor, color)) return;
        id previous = (__bridge id)(row.layer.presentationLayer.backgroundColor ?: row.layer.backgroundColor);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        row.layer.backgroundColor = color;
        [CATransaction commit];
        if (animated && previous && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
            fade.fromValue = previous;
            fade.toValue = (__bridge id)color;
            fade.duration = 0.12;
            [row.layer addAnimation:fade forKey:@"sidebarAddressHover"];
        }
    }];
}

@implementation DPSidebarAddressRow (Hover)
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    DPAddressHover *state = DPAddressHoverFor(self);
    if (state.tracking) [self removeTrackingArea:state.tracking];
    state.tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways |
                      NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:state.tracking];
}
- (void)mouseEntered:(NSEvent *)event { DPAddressHoverFor(self).hovered = YES; DPSidebarUpdateHover(self, YES); DPSidebarLayoutNativeControls(self); }
- (void)mouseMoved:(NSEvent *)event { [self updateActionHover]; }
- (void)mouseExited:(NSEvent *)event { DPAddressHoverFor(self).hovered = NO; DPSidebarUpdateHover(self, YES); DPSidebarLayoutNativeControls(self); }
@end

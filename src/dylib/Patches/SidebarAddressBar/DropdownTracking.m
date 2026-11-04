#import "Editor.h"

@interface DPDropdownShield : NSObject
@property (weak) NSView *surface;
@property (weak) NSWindow *parent;
@property NSMapTable<NSView *, NSMutableArray<NSTrackingArea *> *> *areas;
@property NSMapTable<NSView *, NSString *> *tooltips;
@property BOOL restoring;
@end
@implementation DPDropdownShield @end

static NSMapTable<NSWindow *, DPDropdownShield *> *DPShields;
static char DPDropdownShieldKey;

static DPDropdownShield *DPShieldForView(NSView *view) {
    DPDropdownShield *shield = [DPShields objectForKey:view.window];
    if (!shield.surface.window || shield.surface.hiddenOrHasHiddenAncestor || shield.restoring) return nil;
    if ([view isKindOfClass:DPSidebarAddressRow.class] || [view isDescendantOf:shield.surface]) return nil;
    for (NSView *ancestor = view; ancestor; ancestor = ancestor.superview)
        if ([ancestor isKindOfClass:DPSidebarAddressRow.class]) return nil;
    if (view == view.window.contentView || view == view.window.contentView.superview) return nil;
    NSRect frame = [view.window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
    NSRect covered = [shield.parent convertRectToScreen:[shield.surface convertRect:shield.surface.bounds toView:nil]];
    return NSIntersectsRect(frame, covered) ? shield : nil;
}

static void DPSaveTrackingArea(DPDropdownShield *shield, NSView *view, NSTrackingArea *area) {
    NSMutableArray *areas = [shield.areas objectForKey:view];
    if (!areas) [shield.areas setObject:areas = [NSMutableArray array] forKey:view];
    if (![areas containsObject:area]) [areas addObject:area];
}

static void DPDropdown_addTrackingArea(NSView *self, SEL _cmd, NSTrackingArea *area) {
    DPDropdownShield *shield = DPShieldForView(self);
    if (shield) DPSaveTrackingArea(shield, self, area);
    else DPCallOriginal(DPDropdown_addTrackingArea, self, area);
}

static void DPDropdown_removeTrackingArea(NSView *self, SEL _cmd, NSTrackingArea *area) {
    DPDropdownShield *shield = [DPShields objectForKey:self.window];
    if ([[shield.areas objectForKey:self] containsObject:area] && !shield.restoring) {
        [[shield.areas objectForKey:self] removeObject:area];
        return;
    }
    DPCallOriginal(DPDropdown_removeTrackingArea, self, area);
}

static void DPDropdown_setToolTip(NSView *self, SEL _cmd, NSString *tooltip) {
    DPDropdownShield *shield = DPShieldForView(self);
    if (shield) {
        if (tooltip) [shield.tooltips setObject:tooltip forKey:self];
        else [shield.tooltips removeObjectForKey:self];
        tooltip = nil;
    }
    DPCallOriginal(DPDropdown_setToolTip, self, tooltip);
}

static void DPShieldSubviews(NSView *view, DPDropdownShield *shield) {
    if (DPShieldForView(view)) {
        for (NSTrackingArea *area in view.trackingAreas.copy) {
            // Remove through the original entry point so the native view can
            // later remove or replace the saved area without duplicating it.
            ((void (*)(id, SEL, id))DPOriginalIMP(view, @selector(removeTrackingArea:), (IMP)DPDropdown_removeTrackingArea))
                (view, @selector(removeTrackingArea:), area);
            DPSaveTrackingArea(shield, view, area);
        }
        if (view.toolTip) {
            [shield.tooltips setObject:view.toolTip forKey:view];
            ((void (*)(id, SEL, id))DPOriginalIMP(view, @selector(setToolTip:), (IMP)DPDropdown_setToolTip))
                (view, @selector(setToolTip:), nil);
        }
    }
    for (NSView *child in view.subviews.copy) DPShieldSubviews(child, shield);
}

void DPSidebarShieldDropdown(NSView *surface, NSWindow *parent) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DPShields = [NSMapTable weakToStrongObjectsMapTable];
        DPHookClass(NSView.class, @selector(addTrackingArea:), (IMP)DPDropdown_addTrackingArea);
        DPHookClass(NSView.class, @selector(removeTrackingArea:), (IMP)DPDropdown_removeTrackingArea);
        DPHookClass(NSView.class, @selector(setToolTip:), (IMP)DPDropdown_setToolTip);
    });
    DPSidebarInstallSuggestionTooltips();
    DPSidebarUnshieldDropdown(surface);
    DPDropdownShield *shield = [DPDropdownShield new];
    shield.surface = surface;
    shield.parent = parent;
    shield.areas = [NSMapTable weakToStrongObjectsMapTable];
    shield.tooltips = [NSMapTable weakToStrongObjectsMapTable];
    [DPShields setObject:shield forKey:parent];
    DPSet(surface, &DPDropdownShieldKey, shield);
    DPShieldSubviews(parent.contentView.superview, shield);
}

void DPSidebarUnshieldDropdown(NSView *surface) {
    DPDropdownShield *shield = DPGet(surface, &DPDropdownShieldKey);
    if (shield.surface != surface) return;
    shield.restoring = YES;
    for (NSView *view in shield.areas)
        for (NSTrackingArea *area in [shield.areas objectForKey:view])
            if (![view.trackingAreas containsObject:area]) [view addTrackingArea:area];
    for (NSView *view in shield.tooltips) view.toolTip = [shield.tooltips objectForKey:view];
    [DPShields removeObjectForKey:shield.parent];
    DPSet(surface, &DPDropdownShieldKey, nil);
}

BOOL DPSidebarSuggestionsCoverView(NSView *view) {
    DPDropdownShield *shield = [DPShields objectForKey:view.window];
    if (!shield.surface.window) return NO;
    NSPoint point = [shield.surface convertPoint:view.window.mouseLocationOutsideOfEventStream fromView:nil];
    return NSPointInRect(point, shield.surface.bounds);
}

BOOL DPSidebarSuggestionsContainScreenPoint(NSPoint point) {
    for (NSWindow *parent in DPShields) {
        DPDropdownShield *shield = [DPShields objectForKey:parent];
        if (!parent.isVisible || !shield.surface.window || shield.surface.hiddenOrHasHiddenAncestor) continue;
        NSRect covered = [parent convertRectToScreen:[shield.surface convertRect:shield.surface.bounds toView:nil]];
        if (NSPointInRect(point, covered)) return YES;
    }
    return NO;
}

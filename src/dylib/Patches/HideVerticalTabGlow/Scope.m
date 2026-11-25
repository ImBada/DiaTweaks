#import "HideVerticalTabGlow.h"

BOOL DPIsVerticalTab(NSView *shape) {
    static Class strip, root;
    strip = strip ?: objc_getClass(DPDiaTabStrip);
    root = root ?: objc_getClass(DPVerticalSidebarRoot);
    BOOL sidebar = NO;
    for (NSView *up = shape; up; up = up.superview) {
        if (strip && [up isKindOfClass:strip]) return NO;
        if (root && [up isKindOfClass:root]) sidebar = YES;
    }
    return sidebar;
}

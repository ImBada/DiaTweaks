#import "SidebarAddressBar.h"

static char DPPinFrameKey;

static BOOL DPSpacedSidebarPin(NSView *tab) {
    if (!DPSidebarAddressBar.on || !DPSidebarComfortableSpacing.on) return NO;
    for (NSView *view = tab.superview; view; view = view.superview)
        if (DPSubview(view, DPDiaSidebarHeader)) return DPSidebarUsesVerticalTabs(view);
    return NO;
}

static void DPSpacedPin_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSRect native = [DPDiaValue(self, &DPPinFrameKey, [NSValue valueWithRect:frame]) rectValue];
    NSRect spaced = DPSpacedSidebarPin(self) && NSWidth(native) > 4 && NSHeight(native) > 4 ? NSInsetRect(native, 1, 1) : native;
    DPOverride(self, &DPPinFrameKey, [NSValue valueWithRect:native], [NSValue valueWithRect:spaced]);
    DPCallOriginal(DPSpacedPin_setFrame, self, spaced);
}

void DPSidebarApplySpacing(void) {
    for (NSView *pin in DPFindViews(DPDiaPinnedTab)) pin.frame = pin.frame;
}

static void DPApplySidebarSpacing(DPPatch *patch) {
    DPSidebarApplyLayout();
    DPSidebarApplySpacing();
}

static void DPPin_mouseEntered(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPSidebarSuggestionsCoverView(self)) return;
    DPCallOriginal(DPPin_mouseEntered, self, event);
}
static void DPPin_mouseMoved(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPSidebarSuggestionsCoverView(self)) return;
    DPCallOriginal(DPPin_mouseMoved, self, event);
}
static void DPInstallSidebarSpacing(void) {
    DPHook(DPDiaPinnedTab, @selector(setFrame:), (IMP)DPSpacedPin_setFrame);
    DPHook(DPDiaPinnedTab, @selector(mouseEntered:), (IMP)DPPin_mouseEntered);
    DPHook(DPDiaPinnedTab, @selector(mouseMoved:), (IMP)DPPin_mouseMoved);
}

static NSString *DPVerifySidebarSpacing(DPPatch *patch) {
    for (NSView *pin in DPFindViews(DPDiaPinnedTab)) {
        if (pin.hiddenOrHasHiddenAncestor) continue;
        NSRect native = [DPDiaValue(pin, &DPPinFrameKey, [NSValue valueWithRect:pin.frame]) rectValue];
        NSRect expected = DPSpacedSidebarPin(pin) && NSWidth(native) > 4 && NSHeight(native) > 4 ? NSInsetRect(native, 1, 1) : native;
        if (!NSEqualRects(pin.frame, expected)) return @"pinned tab spacing does not match its setting";
    }
    return nil;
}

DP_PATCH(DPSidebarComfortableSpacing) {
    .key = @"sidebarComfortableSpacing",
    .order = 92, .title = @"Comfortable sidebar spacing",
    .detail = @"Add a little space around the address bar and pinned tabs.",
    .symbol = @"sidebar.left",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .defaultOn = YES,
    .requires = @"sidebarAddressBar",
    .classes = DPClasses(DPDiaPinnedTab),
    .install = DPInstallSidebarSpacing,
    .apply = DPApplySidebarSpacing,
    .verify = DPVerifySidebarSpacing,
};

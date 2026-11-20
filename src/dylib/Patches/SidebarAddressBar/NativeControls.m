#import "NativeControls.h"
#import "WindowTabs.h"

#define DPNativePinnedExtensions "_TtC16PinnedExtensions20PinnedExtensionsView"
static char DPNativeControlsKey;
@implementation DPAddressNativeControls @end

DPAddressNativeControls *DPAddressControlsFor(NSView *row, BOOL create) {
    DPAddressNativeControls *state = DPGet(row, &DPNativeControlsKey);
    if (!state && create) DPSet(row, &DPNativeControlsKey, state = [DPAddressNativeControls new]);
    return state;
}

void DPSidebarRestoreNativeControls(NSView *row) {
    DPAddressNativeControls *state = DPAddressControlsFor(row, NO);
    DPAddressRestoreGrid(state);
    if (state.gridHeight) { state.gridHeight = 0; row.superview.needsLayout = YES; }
    DPRestoreAddressNative(state.more);
    DPRestoreAddressNative(state.extensions);
    state.more = state.extensions = nil;
    state.toolbar = nil;
    [state.scroll removeFromSuperview];
    [state.extensionsButton removeFromSuperview];
}

static void DPRefreshAddressNativeControls(DPSidebarAddressRow *row) {
    if (!DPSidebarAddressBar.on || !row.window || !row.superview || row.hiddenOrHasHiddenAncestor) {
        DPSidebarRestoreNativeControls(row);
        return;
    }
    NSView *toolbar = DPWindowSourceToolbar(row.window);
    DPAddressNativeControls *state = DPAddressControlsFor(row, YES);
    NSView *extensions = DPFindView(toolbar, ^BOOL(NSView *view) { return DPIsKind(view, DPNativePinnedExtensions); });
    // A committed suggestion can attach a new toolbar before its extension
    // host arrives. Keep the current pins mounted through that handoff.
    if (state.toolbar != toolbar && state.extensions.view.window == row.window &&
        state.toolbar.window == row.window && (!toolbar || !extensions)) {
        DPSidebarLayoutNativeControls(row);
        return;
    }
    if (state.toolbar != toolbar) DPSidebarRestoreNativeControls(row);
    if (!toolbar) { DPSidebarLayoutNativeControls(row); return; }
    state.toolbar = toolbar;
    DPCreateAddressExtensionsHost(state);
    if (!state.scroll.superview) [row addSubview:state.scroll];
    if (!state.extensionsButton.superview) [row addSubview:state.extensionsButton];
    NSView *more = DPFindView(toolbar, ^BOOL(NSView *view) { return DPHasLabel(view, @"Site menu"); });
    if (more && more != state.more.view) {
        DPRestoreAddressNative(state.more);
        state.more = DPAttachAddressNative(more, row, row, NSMakeRect(MAX(0, NSWidth(row.bounds)-32),4,28,28), NO);
        DPAddressInstallSiteMenuHooks(more);
        state.more.icon = (NSImageView *)DPFindView(more, ^BOOL(NSView *view) { return [view isKindOfClass:NSImageView.class]; });
        state.more.originalImage = state.more.icon.image;
        state.more.originalTint = state.more.icon.contentTintColor;
        state.more.displayImage = [[NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:nil]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium]];
    }
    if (extensions && extensions != state.extensions.view) {
        DPRestoreAddressNative(state.extensions);
        state.extensions = DPAttachAddressNative(extensions, row, state.scroll.contentView, NSMakeRect(0,0,NSWidth(extensions.frame),42), YES);
    }
    DPAddressStyleSiteHover(state.more);
    if (state.more.icon && state.more.icon.image != state.more.displayImage) {
        state.more.originalImage = state.more.icon.image;
        state.more.icon.image = state.more.displayImage;
        state.more.icon.contentTintColor = NSColor.secondaryLabelColor;
    }
    DPSidebarLayoutNativeControls(row);
}


void DPSidebarRefreshNativeControls(DPSidebarAddressRow *row) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try { DPRefreshAddressNativeControls(row); }
    @finally { [CATransaction commit]; }
}

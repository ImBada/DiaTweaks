#import "Toolbar.h"

typedef NSString *(*DPToolbarCheck)(DPPatch *);
static DPToolbarCheck DPOriginalHideCheck, DPOriginalKeptCheck, DPOriginalRevealCheck;

static BOOL DPHasReplacement(void) {
    for (NSView *pane in DPFindViews(DPDiaContentPane))
        if (DPSidebarReplacesToolbar(pane)) return YES;
    return NO;
}

static NSString *DPSidebarCheckHide(DPPatch *patch) {
    return DPHasReplacement() ? DPSidebarVerifyToolbar() : DPOriginalHideCheck(patch);
}

static NSString *DPSidebarCheckKept(DPPatch *patch) {
    if (!DPHasReplacement()) return DPOriginalKeptCheck(patch);
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        if (DPSidebarReplacesToolbar(pane)) continue;
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        if (!DPHideToolbar.on || !bar || bar.hiddenOrHasHiddenAncestor || hover.revealed) continue;
        BOOL kept = DPKeptInPlace(pane);
        if (kept && bar.alphaValue < 0.99) return @"toolbar stays hidden where an option keeps it";
        if (!kept && bar.alphaValue > 0.01) return @"toolbar shows where nothing keeps it";
    }
    return DPSidebarVerifyToolbar();
}

static NSString *DPSidebarCheckReveal(DPPatch *patch) {
    if (!DPHasReplacement()) return DPOriginalRevealCheck(patch);
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        BOOL watching = !DPSidebarReplacesToolbar(pane) && patch->on && DPHideToolbar.on &&
            !hover.inPlace && bar && !bar.hiddenOrHasHiddenAncestor;
        if ((hover.tracking != nil) != watching) return @"toolbar hover tracking is wrong";
        if (watching && !hover.revealed && bar.alphaValue > 0.01) return @"toolbar shows while pointer is away";
    }
    return DPSidebarVerifyToolbar();
}

void DPSidebarInstallToolbarVerification(void) {
    DPPatch *hide = DPPatchNamed(@"hideToolbar"), *reveal = DPPatchNamed(@"revealToolbarOnHover");
    DPPatch *sidebar = DPPatchNamed(@"showToolbarWithSidebar"), *newTab = DPPatchNamed(@"showToolbarOnNewTab");
    // Chain the existing checks, never patch their source or silently ignore a failure.
    if (hide && hide->verify) { DPOriginalHideCheck = hide->verify; hide->verify = DPSidebarCheckHide; }
    if (reveal && reveal->verify) { DPOriginalRevealCheck = reveal->verify; reveal->verify = DPSidebarCheckReveal; }
    if (sidebar && sidebar->verify) DPOriginalKeptCheck = sidebar->verify;
    else if (newTab && newTab->verify) DPOriginalKeptCheck = newTab->verify;
    if (DPOriginalKeptCheck) {
        if (sidebar) sidebar->verify = DPSidebarCheckKept;
        if (newTab) newTab->verify = DPSidebarCheckKept;
    }
}

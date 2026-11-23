#import "HideToolbar.h"

static NSString *DPVerifyKeepBookmarksBar(DPPatch *patch) {
    if (!patch->on) return nil;
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        NSView *bookmarks = bar ? DPBookmarksUnder(pane, bar) : nil;
        if (!bookmarks || hover.progress > 0 || hover.inPlaceProgress > 0 || DPToolbarHasPermissionRequest(hover)) continue;
        if (bookmarks.alphaValue < 0.99) return @"bookmarks bar hides with the toolbar";
        if (![bookmarks hitTest:NSMakePoint(NSMidX(bookmarks.frame), NSMidY(bookmarks.frame))]) return @"bookmarks bar doesn’t take clicks";
    }
    return nil;
}

DP_PATCH(DPKeepBookmarksBar) {
    .key = @"keepBookmarksBar",
    .order = 44,
    .title = @"Keep Bookmarks Bar",
    .detail = @"Keep Dia’s bookmarks bar at the top of the page while hiding the address bar above it.",
    .symbol = @"bookmark",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"Showing the Toolbar",
    .classes = DPClasses(DPDiaContentPane, DPDiaToolbar),
    .apply = DPApplyRelayoutPanes,
    .verify = DPVerifyKeepBookmarksBar,
};

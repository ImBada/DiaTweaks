#import "Toolbar.h"

static char DPToolbarReplacementStateKey;
void DPSidebarCheckToolbarState(void) {
    BOOL changed = NO;
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        BOOL replacing = DPSidebarReplacesToolbar(pane);
        NSNumber *previous = DPGet(pane, &DPToolbarReplacementStateKey);
        changed |= previous && previous.boolValue != replacing;
        DPSet(pane, &DPToolbarReplacementStateKey, @(replacing));
    }
    if (changed) DPSidebarRefreshToolbar();
}

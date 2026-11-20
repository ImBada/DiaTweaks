#import "Editor.h"

static void DPApplySidebarEditorMode(DPPatch *patch) {
    for (DPSidebarAddressRow *row in DPFindViews("DPSidebarAddressRow")) [row finishInlineEditing];
}

DP_PATCH(DPSidebarDefaultEditor) {
    .key = @"sidebarDefaultEditor",
    .order = 86, .title = @"Use Dia’s default address editor",
    .detail = @"Open Dia’s editor instead of editing inline.",
    .symbol = @"text.cursor",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .defaultOn = NO,
    .requires = @"sidebarAddressBar",
    .apply = DPApplySidebarEditorMode,
};

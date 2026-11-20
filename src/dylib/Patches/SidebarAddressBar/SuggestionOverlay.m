#import "Editor.h"

void DPSidebarQuietSuggestionOverlay(DPSidebarAddressRow *row) {
    NSView *overlay = row.nativeOverlay;
    if (!overlay || !row.inlineEditor) return;
    // Command Bar can rebuild its shade after attaching the borrowed input.
    // Preserve each surface's original state, including subsequent replacements.
    for (NSString *key in @[@"shade", @"windowBlur"]) {
        if (![overlay respondsToSelector:NSSelectorFromString(key)]) continue;
        NSView *surface = [overlay valueForKey:key];
        if (![surface isKindOfClass:NSView.class]) continue;
        if (![row.nativeSurfaceAlphas objectForKey:surface])
            [row.nativeSurfaceAlphas setObject:@(surface.alphaValue) forKey:surface];
        DPSidebarHideSuggestionSurface(surface, YES);
        surface.alphaValue = 0;
    }
}

// Upstream Command Bar reparents the native input out of its popover.
// Follow that input into the overlay instead of modifying Command Bar's source.
static void DPSidebarSuggestionPanel_moved(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarSuggestionPanel_moved, self);
    if (![NSStringFromClass(self.superview.class) isEqualToString:@"DPCommandBarOverlay"] || !self.window) return;
    DPSidebarAddressRow *row = (id)DPFindView(self.window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, "DPSidebarAddressRow") && [(DPSidebarAddressRow *)view inlineEditor] &&
            [(DPSidebarAddressRow *)view startingSuggestionSession];
    });
    if (!row) return;
    NSView *input = DPFindView(self, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarText); });
    NSTextView *editor = (id)DPFindView(input, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
    if (!editor) return;
    [row attachSuggestionSession:self editor:editor];
    __weak DPSidebarAddressRow *weakRow = row;
    dispatch_async(dispatch_get_main_queue(), ^{
        DPSidebarQuietSuggestionOverlay(weakRow);
        [weakRow finishStartingSuggestionSession];
    });
}

void DPSidebarInstallSuggestionOverlay(void) {
    DPHookClass(objc_getClass(DPDiaAssistantPanel), @selector(viewDidMoveToSuperview), (IMP)DPSidebarSuggestionPanel_moved);
    DPHookClass(objc_getClass(DPDiaAssistantPanel), @selector(viewDidMoveToWindow), (IMP)DPSidebarSuggestionPanel_moved);
}

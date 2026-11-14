#import "StdPatch/StdPatch.h"

DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
DPPatch *DPPatchNamed(NSString *key) {
    for (NSUInteger i=0; i<DPPatchCount; i++) if ([DPPatches[i]->key isEqual:key]) return DPPatches[i];
    return NULL;
}
DPPatch *DPRequired(DPPatch *patch) { return DPPatchNamed(patch->requires); }
// Standalone fixtures apply state without writing the user's preference suite.
void DPSetPatch(DPPatch *patch, BOOL on, BOOL save) {
    if (patch->on == on) return;
    patch->on = on;
    if (patch->apply) patch->apply(patch);
}
NSImageView *DPSymbol(NSString *symbol, CGFloat size, NSColor *color) {
    return [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
}
// The settings-order fixture does not need the upstream glass-hint presenter.
void DPSetHint(NSView *view, NSString *hint) { view.toolTip = hint; }
NSString *DPHintOf(NSView *view) { return view.toolTip; }

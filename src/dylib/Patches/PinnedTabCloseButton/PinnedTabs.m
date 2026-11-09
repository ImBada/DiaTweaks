#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

extern void *swift_unknownObjectWeakLoadStrong(void *reference);

// viewModel.delegate is a Swift weak reference, which DPSwiftValue can't read.
id DPViewModelDelegate(NSView *view) {
    void **viewModel = DPIvar(view, "viewModel");
    void *delegate = viewModel && *viewModel ? DPIvar((__bridge id)*viewModel, "delegate") : NULL;
    return delegate ? (__bridge_transfer id)swift_unknownObjectWeakLoadStrong(delegate) : nil;
}

NSView *DPEnclosingTab(NSView *view) {
    while (view && !DPIsKind(view, DPDiaTabView)) view = view.superview;
    return view;
}

void DPRelayoutTabContents(void) {
    for (NSView *content in DPFindViews(DPDiaTabContentView)) content.needsLayout = YES;
}

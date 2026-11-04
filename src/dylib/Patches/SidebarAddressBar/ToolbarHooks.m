#import "Toolbar.h"

// Run outside Hide Toolbar's hook, restoring our frames before it reads its own.
static void DPSidebarPane_layout(NSView *self, SEL _cmd) {
    DPSidebarRestoreToolbar(self);
    DPCallOriginal(DPSidebarPane_layout, self);
    DPSidebarApplyToolbar(self);
}

static NSView *DPSidebarToolbar_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    if (DPSidebarReplacesToolbar(self.superview)) return nil;
    return DPCallOriginal(DPSidebarToolbar_hitTest, self, point);
}

static void DPSidebarController_layout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPSidebarController_layout, self);
    DPPatch *compact = DPPatchNamed(@"compactSidebarHeader");
    if (!DPSidebarAddressBar.on || !compact || !compact->on || !self.view.isFlipped) return;
    NSView *header = DPSubview(self.view, DPDiaSidebarHeader);
    if (header) DPSidebarLayoutHeader(header);
}

static void DPSidebarToolbarRoot_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarToolbarRoot_layout, self);
    DPSidebarCheckToolbarState();
}

static void DPSidebarToolbarHeader_attached(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarToolbarHeader_attached, self);
    if (self.superview) DPHookClass(self.superview.class, @selector(layout), (IMP)DPSidebarToolbarRoot_layout);
}

void DPSidebarInstallToolbar(void) {
    DPOnLaunch(^{
        DPHook(DPDiaContentPane, @selector(layout), (IMP)DPSidebarPane_layout);
        DPHook(DPDiaToolbar, @selector(hitTest:), (IMP)DPSidebarToolbar_hitTest);
        DPHook(DPDiaSidebarController, @selector(viewDidLayout), (IMP)DPSidebarController_layout);
        DPHook(DPDiaSidebarHeader, @selector(viewDidMoveToWindow), (IMP)DPSidebarToolbarHeader_attached);
        for (NSView *header in DPFindViews(DPDiaSidebarHeader))
            DPHookClass(header.superview.class, @selector(layout), (IMP)DPSidebarToolbarRoot_layout);
        DPSidebarInstallToolbarHover();
        DPSidebarInstallToolbarVerification();
        DPSidebarRefreshToolbar();
    });
}

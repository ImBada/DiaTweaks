#import "SidebarAddressBar.h"
#import "Settings.h"
#import "Toolbar.h"

static NSTimer *DPAddressWatch;

static void DPApplySidebarAddress(DPPatch *patch) {
    [DPAddressWatch invalidate];
    DPAddressWatch = nil;
    // Its effective state changes with this patch even when its own switch does not.
    DPPatch *compact = DPPatchNamed(@"compactSidebarHeader");
    if (compact && compact->apply) compact->apply(compact);
    DPSidebarApplyLayout();
    DPSidebarApplySpacing();
    DPSidebarRefreshToolbar();
    if (!patch->on) return;
    DPAddressWatch = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        DPSidebarRefreshLayout();
    }];
    [NSRunLoop.mainRunLoop addTimer:DPAddressWatch forMode:NSDefaultRunLoopMode];
}

static BOOL DPAddressSuspendedForQuit;

static void DPAddressPrepareToQuit(void) {
    if (!DPSidebarAddressBar.on) return;
    DPAddressSuspendedForQuit = YES;
    // Return the native stack views before Dia's shutdown handlers remove them.
    DPSetPatch(&DPSidebarAddressBar, NO, NO);
}

static void DPAddressCancelQuit(void) {
    if (!DPAddressSuspendedForQuit) return;
    DPAddressSuspendedForQuit = NO;
    DPSetPatch(&DPSidebarAddressBar, DPSavedOn(&DPSidebarAddressBar), NO);
}

static void DPAddressAppTerminate(NSApplication *self, SEL _cmd, id sender) {
    DPAddressPrepareToQuit();
    DPCallOriginal(DPAddressAppTerminate, self, sender);
}

static void DPAddressAppReplyToQuit(NSApplication *self, SEL _cmd, BOOL terminate) {
    if (terminate) DPAddressPrepareToQuit();
    else DPAddressCancelQuit();
    DPCallOriginal(DPAddressAppReplyToQuit, self, terminate);
}

static NSApplicationTerminateReply DPAddressAppShouldTerminate(id self, SEL _cmd, NSApplication *app) {
    NSApplicationTerminateReply reply = DPCallOriginal(DPAddressAppShouldTerminate, self, app);
    if (reply == NSTerminateCancel) DPAddressCancelQuit();
    else if (reply == NSTerminateNow) DPAddressPrepareToQuit();
    return reply;
}

// Dia 1.56 presents copy feedback in a toast panel, independently of the toolbar.
static BOOL DPAddressSuppressCopyToast;

static void DPAddressToastOrderFront(NSWindow *self, SEL _cmd, id sender) {
    if (!DPAddressSuppressCopyToast) DPCallOriginal(DPAddressToastOrderFront, self, sender);
}

static void DPAddressToastOrderRegardless(NSWindow *self, SEL _cmd) {
    if (!DPAddressSuppressCopyToast) DPCallOriginal(DPAddressToastOrderRegardless, self);
}

static void DPAddressToastOrderWindow(NSWindow *self, SEL _cmd, NSWindowOrderingMode place, NSInteger other) {
    if (place == NSWindowOut || !DPAddressSuppressCopyToast)
        DPCallOriginal(DPAddressToastOrderWindow, self, place, other);
}

static BOOL DPAddressAppSendAction(NSApplication *self, SEL _cmd, SEL action, id target, id sender) {
    if ([sender isKindOfClass:NSButton.class] && [[sender title] isEqual:@"Quit"] && [sender window].sheetParent)
        DPAddressPrepareToQuit();
    BOOL copiesURL = DPSidebarAddressBar.on && action == NSSelectorFromString(@"copyCurrentURL:");
    NSWindow *window = copiesURL ? self.keyWindow : nil;
    NSInteger before = window ? NSPasteboard.generalPasteboard.changeCount : 0;
    BOOL useToolbarFeedback = window && DPSidebarUsesToolbarCopyFeedback(window);
    BOOL previousSuppression = DPAddressSuppressCopyToast;
    DPAddressSuppressCopyToast |= window && !useToolbarFeedback && DPSidebarAddressRowAvailable(window);
    BOOL sent;
    @try {
        sent = DPCallOriginal(DPAddressAppSendAction, self, action, target, sender);
    } @finally {
        DPAddressSuppressCopyToast = previousSuppression;
    }
    if (!sent || !window || before == NSPasteboard.generalPasteboard.changeCount) return sent;
    if (useToolbarFeedback) return sent;
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        if (header.window != window || header.hiddenOrHasHiddenAncestor) continue;
        for (NSView *view in header.superview.subviews)
            if ([view isKindOfClass:DPSidebarAddressRow.class]) [(DPSidebarAddressRow *)view showCopyFeedback];
    }
    return sent;
}

static void DPInstallSidebarAddress(void) {
    DPSidebarInstallContextTracking();
    DPSidebarInstallToolbar();
    DPSidebarInstallLayout();
    DPSidebarInstallPopover();
    DPSidebarInstallInlineFocus();
    DPOnLaunch(^{
        DPHookClass(NSApp.class, @selector(terminate:), (IMP)DPAddressAppTerminate);
        DPHookClass(NSApp.class, @selector(replyToApplicationShouldTerminate:), (IMP)DPAddressAppReplyToQuit);
        DPHookClass(NSApp.delegate.class, @selector(applicationShouldTerminate:), (IMP)DPAddressAppShouldTerminate);
        DPHookClass(NSApp.class, @selector(sendAction:to:from:), (IMP)DPAddressAppSendAction);
        Class toast = objc_getClass(DPDiaToasts);
        if (toast) {
            DPHookClass(toast, @selector(orderFront:), (IMP)DPAddressToastOrderFront);
            DPHookClass(toast, @selector(orderFrontRegardless), (IMP)DPAddressToastOrderRegardless);
            DPHookClass(toast, @selector(orderWindow:relativeTo:), (IMP)DPAddressToastOrderWindow);
        }
        DPApplySidebarAddress(&DPSidebarAddressBar);
    });
}

DP_PATCH(DPSidebarAddressBar) {
    .key = @"sidebarAddressBar",
    .order = 85,
    .title = @"Sidebar address bar",
    .detail = @"Search, edit addresses and access page actions from the sidebar.",
    .symbol = @"link",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaSidebarHeader, DPDiaPopover, DPDiaCommandBar, DPDiaCommandBarText, DPDiaCommandBarSuggestions, DPDiaNewTabPage),
    .install = DPInstallSidebarAddress,
    .apply = DPApplySidebarAddress,
    .rows = DPSidebarSettingsRows,
    .verify = DPSidebarVerifyLayout,
};

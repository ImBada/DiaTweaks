#import "LittleDia.h"
#import "Updates/Updates.h"

static BOOL gLoadedOn;

static void DPInstallLittleDia(void) {
    gLoadedOn = DPLittleDia.on;
    DPInstallLittleDiaExtension();
    DPInstallLittleDiaRoute();
    DPInstallLittleDiaWindows();
    DPInstallLittleDiaOver();
    DPInstallLittleDiaLinkMenu();
    DPInstallLittleDiaNewWindow();
    DPInstallLittleDiaShortcuts();
}

static void DPApplyLittleDia(DPPatch *patch) {
    if (!patch->on) {
        DPHideLittleDiaLauncher();
        DPUncoverAllLittleDia();
        DPRestoreLittleDiaStack();
    }
    DPRefreshLittleDiaWindows();
    DPRefreshLittleDiaNewWindow();
    if (patch->on && !gLoadedOn) DPWriteLittleDiaExtension(YES);
    // Self-tests flip patches without saving, so skip the relaunch prompt for them.
    if (!patch->on || gLoadedOn || patch->on != DPSavedOn(patch) || DPLittleDiaExtensionProblem()) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Relaunch Dia to use Little Dia";
    alert.informativeText = @"Until then, links from other apps keep opening in a tab.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

static NSString *DPLittleDiaProblem(DPPatch *patch) { return DPLittleDiaExtensionProblem(); }

static NSString *DPVerifyLittleDia(DPPatch *patch) {
    for (NSView *bar in DPFindViews(DPDiaPopupBar)) {
        BOOL little = DPIsLittleDiaWindow(bar.window);
        NSView *button = DPFindView(bar, ^BOOL(NSView *view) { return DPHasLabel(view, @"Open in Dia"); });
        if (patch->on && little && !button) return @"Open in Dia button missing";
        if (!patch->on && button) return @"Open in Dia button still showing";
        if (patch->on && little && bar.window.titleVisibility != NSWindowTitleHidden) return @"title bar still showing";
    }
    return DPLittleDiaNewWindowProblem() ?: (patch->on ? DPLittleDiaLinkMenuProblem() ?: DPLittleDiaShortcutsProblem() : nil);
}

DP_PATCH(DPLittleDia) {
    .key = @"littleDia",
    .order = 104,
    .section = @"Links",
    .title = @"Little Dia",
    .detail = @"Opens links from other apps, like Slack or Mail, in a small window instead of a tab, and so does right-clicking a link and choosing Open Link in Little Dia. It has back, forward, reload and an editable address. Open in Dia or ⌘O keeps it as a tab. Option-click opens a tab.",
    .symbol = @"macwindow.on.rectangle rectangle.on.rectangle",
    .tint = @"systemMintColor",
    .classes = DPClasses(DPDiaOpenURLEvents, DPDiaPopupWindow, DPDiaPopupBar, DPDiaPopupTitle),
    .settings = DPSettingList({DPSettingNumber, @"littleDiaWidth", .defaultNumber = 1180, .min = 480, .max = 2000},
                              {DPSettingNumber, @"littleDiaHeight", .defaultNumber = 860, .min = 360, .max = 1400}),
    .rows = DPLittleDiaRows,
    .relaunch = YES,
    .install = DPInstallLittleDia,
    .apply = DPApplyLittleDia,
    .verify = DPVerifyLittleDia,
    .ready = DPLittleDiaProblem,
};

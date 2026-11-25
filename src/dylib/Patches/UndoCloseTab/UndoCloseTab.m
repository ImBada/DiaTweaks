#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Patches/CommandBar/Tabs.h"
#import <dlfcn.h>

extern DPPatch DPUndoCloseTab;
static BOOL DPJustClosed;
static __weak NSWindow *DPJustClosedWindow;
static id DPEventMonitor;

static NSMenuItem *DPReopenItem(void) {
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        for (NSMenuItem *item in top.submenu.itemArray)
            if ([item.title isEqualToString:@"Reopen Closed Tab"]) return item;
    return nil;
}

static NSWindow *DPClosedPageWindow(id page) {
    static id (*browserOf)(id);
    static NSWindow *(*windowOf)(id);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        browserOf = dlsym(RTLD_DEFAULT, "DPBrowserOfContents");
        windowOf = dlsym(RTLD_DEFAULT, "DPBrowserWindow");
    });
    if (browserOf && windowOf) {
        NSWindow *window = windowOf(browserOf(page));
        if (window) return window;
    }
    id view = DPValueForKey(page, @"nativeView");
    return [view isKindOfClass:NSView.class] ? ((NSView *)view).window : nil;
}

// Not -close: Peek closes its pages with it, and that must not arm Undo.
static void DPPage_close(id self, SEL _cmd, NSInteger timing) {
    NSWindow *window = DPUndoCloseTab.on ? DPClosedPageWindow(self) : nil;
    DPCallOriginal(DPPage_close, self, timing);
    if (!DPUndoCloseTab.on) return;
    if (!DPTakeOwnClose()) {
        DPJustClosed = YES;
        DPJustClosedWindow = window;
    }
    DPForgetGroupingUndo();
}

static BOOL DPEditingWithUndo(NSWindow *window) {
    NSText *text = [window.firstResponder isKindOfClass:NSText.class] ? (NSText *)window.firstResponder : nil;
    return text.editable && text.undoManager.canUndo;
}

static NSDictionary *DPDefaultUndoShortcut(void) { return @{ @"keyCode" : @6, @"modifiers" : @(NSEventModifierFlagCommand), @"key" : @"Z" }; }

static NSEvent *DPUndoEvent(NSEvent *event) {
    if (!DPUndoCloseTab.on || !DPJustClosed) {
        DPJustClosed = NO;
        DPJustClosedWindow = nil;
        return event;
    }
    NSWindow *closedIn = DPJustClosedWindow;
    BOOL sameWindow = !closedIn || !event.window || event.window == closedIn;
    BOOL undo = sameWindow && event.type == NSEventTypeKeyDown && DPShortcutMatches(event, &DPUndoCloseTab)
        && !DPCanUndoGrouping() && !DPEditingWithUndo(event.window);
    DPJustClosed = NO;
    DPJustClosedWindow = nil;
    NSMenuItem *reopen = undo ? DPReopenItem() : nil;
    if (!reopen) return event;
    [reopen.menu performActionForItemAtIndex:[reopen.menu indexOfItem:reopen]];
    return nil;
}

static void DPApplyUndoCloseTab(DPPatch *patch) {
    if (!patch->on) {
        DPJustClosed = NO;
        DPJustClosedWindow = nil;
    }
    DPSyncMonitor(&DPEventMonitor, patch->on, NSEventMaskKeyDown | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown,
                  ^NSEvent *(NSEvent *event) { return DPUndoEvent(event); });
}

static void DPInstallUndoCloseTab(void) {
    DPHook(DPDiaWebContents, @selector(closeWithForegroundCommitTiming:), (IMP)DPPage_close);
    DPApplyUndoCloseTab(&DPUndoCloseTab);
}

static NSString *DPVerifyUndoCloseTab(DPPatch *patch) {
    return patch->on && !DPReopenItem() ? @"Dia has no Reopen Closed Tab menu item" : nil;
}

DP_PATCH(DPUndoCloseTab) {
    .key = @"undoCloseTab",
    .order = 86,
    .title = @"Undo Closing a Tab",
    .detail = @"Press a shortcut, ⌘Z unless you set another, right after closing a tab to bring it back, as long as you haven’t typed or clicked since.",
    .symbol = @"arrow.uturn.backward.circle.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaWebContents),
    .shortcut = @"undoCloseTabShortcut",
    .defaultShortcut = DPDefaultUndoShortcut,
    .sharesShortcutWith = @"undo:",
    .install = DPInstallUndoCloseTab,
    .apply = DPApplyUndoCloseTab,
    .verify = DPVerifyUndoCloseTab,
};

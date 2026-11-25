#import "LittleDia.h"

static NSMenuItem *gItem;
static NSUInteger gLookTurn;
static BOOL gLooking;
static int gLooks;

static NSMenu *DPFileMenu(void) { return [NSApp.mainMenu itemWithTitle:@"File"].submenu; }

static BOOL DPShouldShow(void) { return DPLittleDia.on && DPLittleDiaReady(); }

// The extension is ready some time after launch, so this polls for a minute until it is.
void DPRefreshLittleDiaNewWindow(void) {
    NSMenu *file = DPFileMenu();
    BOOL show = DPShouldShow();
    if (gItem && file && show != ([file indexOfItem:gItem] >= 0)) {
        NSInteger after = [file indexOfItemWithTitle:@"New Incognito Window"];
        if (show) [file insertItem:gItem atIndex:after >= 0 ? after + 1 : file.numberOfItems];
        else [file removeItem:gItem];
    }
    if (show || !DPLittleDia.on) {
        gLooks = 0;
        gLooking = NO;
        gLookTurn++;
        return;
    }
    if (gLooking) return;
    if (gLooks >= 120) return;
    gLooking = YES;
    NSUInteger turn = gLookTurn;
    gLooks++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (turn != gLookTurn) return;
        gLooking = NO;
        DPRefreshLittleDiaNewWindow();
    });
}

void DPInstallLittleDiaNewWindow(void) {
    gItem = DPMenuItem(@"New Little Dia Window", ^{
        if (!DPShouldShow()) return NSBeep();
        if (DPLittleDiaLauncher.on) DPToggleLittleDiaLauncher();
        else DPOpenBlankLittleDia();
    });
    gItem.keyEquivalent = @"n";
    gItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    DPOnLaunch(^{ DPRefreshLittleDiaNewWindow(); });
    // With no window at launch the extension isn't ready until one opens, after the poll has given up.
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPRefreshLittleDiaNewWindow(); }];
}

NSString *DPLittleDiaNewWindowProblem(void) {
    NSMenu *file = DPFileMenu();
    if (!file) return nil;
    BOOL shown = [file indexOfItem:gItem] >= 0;
    if (shown && !DPShouldShow()) return @"New Little Dia Window stays in the File menu";
    if (!shown && DPShouldShow()) return @"the File menu has no New Little Dia Window";
    return nil;
}

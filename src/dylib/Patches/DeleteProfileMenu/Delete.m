#import "Patches/DeleteProfileMenu/DeleteProfileMenu.h"

static NSString *const DPDeleteTitle = @"Delete Profile…";

// Settings while it's hidden for a delete; the browser window the confirmation sheet is on.
static __weak NSWindow *DPHiddenSettings, *DPSheetHost;
static NSMutableArray *DPObservers;

BOOL DPOpeningHiddenSettings;

static NSWindow *DPConfirmSheet(NSWindow *window) {
    for (NSWindow *sheet in window.sheets)
        if (DPIsKind(sheet.windowController, DPDiaDialogPanelWC)) return sheet;
    return nil;
}

BOOL DPDeletingProfile(void) { return DPSheetHost != nil; }

static void DPObserve(NSNotificationName name, id object, void (^block)(void)) {
    if (!DPObservers) DPObservers = [NSMutableArray new];
    [DPObservers addObject:[NSNotificationCenter.defaultCenter addObserverForName:name object:object queue:nil usingBlock:^(NSNotification *note) { block(); }]];
}

// Done: lets go and puts Settings back, whether the delete happened, failed or was turned off.
void DPFinishProfileDelete(BOOL closeSettings) {
    for (id observer in DPObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    [DPObservers removeAllObjects];
    NSWindow *settings = DPHiddenSettings;
    DPHiddenSettings = DPSheetHost = nil;
    if (!settings || !DPSettingsHidden(settings)) return;
    // orderOut rather than close: Dia keeps this window's panes and toolbar, and closing it breaks them for the next open.
    if (closeSettings) [settings orderOut:nil];
    DPShowSettings(settings);
    if (!closeSettings) [settings makeKeyAndOrderFront:nil];  // Leave Settings open on Profiles, as Profile Settings would.
}

// The confirmation goes first, so its Cancel button never lands on a hidden sheet.
static void DPCancelConfirmSheet(NSWindow *host, NSWindow *sheet) {
    if (!sheet) return;
    NSView *cancel = DPFindView(sheet.contentView, ^BOOL(NSView *view) { return DPHasLabel(view, @"Cancel"); });
    if (cancel) [cancel accessibilityPerformPress];
    if (host && DPConfirmSheet(host) == sheet) [host endSheet:sheet returnCode:NSModalResponseCancel];
}

// Turning the option off: cancel a confirmation that's up, which ends the delete.
void DPEndProfileDelete(void) {
    DPCancelConfirmSheet(DPSheetHost, DPConfirmSheet(DPSheetHost));
    DPFinishProfileDelete(YES);
}

static NSTableView *DPProfilesTable(NSWindow *settings) {
    return (NSTableView *)DPFindView(settings.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaProfilesTable); });
}

// Whether the settings row is this profile, read from the row's own label.
static BOOL DPRowIs(NSTableView *table, NSUInteger row, NSString *name) {
    NSView *cell = [table viewAtColumn:0 row:(NSInteger)row makeIfNecessary:NO]
        ?: [table viewAtColumn:0 row:(NSInteger)row makeIfNecessary:YES];
    return DPFindView(cell, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqual:name];
    }) != nil;
}

// Dia's own Delete Profile… from Settings › Profiles, which is the only path that deletes a profile properly.
static NSMenuItem *DPRowDeleteItem(NSWindow *window, NSWindow *settings, NSString *name, NSUInteger index) {
    NSTableView *table = DPProfilesTable(settings);
    if (!table) return nil;
    NSUInteger row = index;
    if (row >= (NSUInteger)table.numberOfRows || !DPRowIs(table, row, name)) {
        // Another row only while no other profile shares the name, or a delete could take the wrong profile.
        NSUInteger sameName = 0;
        for (id profile in DPProfilesOf(window)) if ([DPValueForKey(profile, @"name") isEqual:name]) sameName++;
        if (sameName != 1) return nil;
        row = NSNotFound;
        for (NSUInteger candidate = 0; candidate < (NSUInteger)table.numberOfRows; candidate++) {
            if (!DPRowIs(table, candidate, name)) continue;
            if (row != NSNotFound) return nil;
            row = candidate;
        }
        if (row == NSNotFound) return nil;
    }
    NSRect rect = [table rectOfRow:(NSInteger)row];
    NSPoint point = [table convertPoint:NSMakePoint(NSMidX(rect), NSMidY(rect)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:0
        windowNumber:settings.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSMenu *menu = [table menuForEvent:click];
    if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:menu];  // Dia fills it as it opens.
    NSMenuItem *item = [menu itemWithTitle:DPDeleteTitle];
    if (!item) return nil;
    [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
    // The menu never opened, so tell the table it closed, which clears its right-clicked row.
    if (menu) [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidEndTrackingNotification object:menu];
    return item;
}

// Never confirm for a profile the user didn't pick: the sheet has to name it, curly quotes or straight.
static BOOL DPSheetNames(NSWindow *sheet, NSString *name) {
    NSArray<NSString *> *quoted = @[ [NSString stringWithFormat:@"“%@”", name], [NSString stringWithFormat:@"\"%@\"", name] ];
    return DPFindView(sheet.contentView, ^BOOL(NSView *view) {
        NSString *text = [view isKindOfClass:NSTextView.class] ? ((NSTextView *)view).string
            : [view isKindOfClass:NSTextField.class] ? ((NSTextField *)view).stringValue : nil;
        for (NSString *form in quoted) if (text && [text containsString:form]) return YES;
        return NO;
    }) != nil;
}

static void DPWatchSheet(NSWindow *window, NSString *name, int tries) {
    NSWindow *sheet = DPConfirmSheet(window);
    if (!sheet && tries > 0) {
        __weak NSWindow *weak = window;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (weak && DPSheetHost == weak) DPWatchSheet(weak, name, tries - 1);
        });
        return;
    }
    if (!sheet) return DPFinishProfileDelete(NO);  // No confirmation after all: leave Settings open to finish by hand.
    if (!DPSheetNames(sheet, name)) {
        // Dia is asking about someone else, so cancel it and give up rather than hide Settings behind it.
        DPCancelConfirmSheet(window, sheet);
        return DPFinishProfileDelete(YES);
    }
    __weak NSWindow *weak = window;
    DPObserve(NSWindowDidEndSheetNotification, window, ^{ if (!DPConfirmSheet(weak)) DPFinishProfileDelete(YES); });
}

// Dia builds Settings' list on the next pass, so give it two seconds of layout to have the rows.
static void DPWaitForTable(NSWindow *settings, NSWindow *window, NSString *name, NSUInteger index, int tries) {
    [settings layoutIfNeeded];
    NSTableView *table = DPProfilesTable(settings);
    [table layoutSubtreeIfNeeded];
    if ((!table || table.numberOfRows == 0) && tries > 0) {
        __weak NSWindow *weakSettings = settings, *weakWindow = window;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (weakWindow && DPSheetHost == weakWindow) DPWaitForTable(weakSettings, weakWindow, name, index, tries - 1);
        });
        return;
    }
    if (!table || !DPRowDeleteItem(window, settings, name, index)) return DPFinishProfileDelete(NO);
    DPWatchSheet(window, name, 60);
}

void DPDeleteProfile(NSWindow *window, NSString *name, NSUInteger index, NSMenuItem *settingsItem) {
    if (DPSheetHost || DPConfirmSheet(window)) return;
    // Settings that's open, or in the Dock, stays as it is. Otherwise hide it before Dia shows it.
    BOOL wasOpen = DPSettingsWindow(YES) != nil;
    if (!wasOpen) DPHideSettings(DPSettingsWindow(NO));
    DPOpeningHiddenSettings = !wasOpen;
    [NSApp sendAction:settingsItem.action to:settingsItem.target from:settingsItem];
    DPOpeningHiddenSettings = NO;
    NSWindow *settings = DPSettingsWindow(NO);
    if (!settings) return;
    DPSheetHost = window;
    if (!wasOpen) {
        DPHideSettings(settings);
        DPHiddenSettings = settings;
        // Opened another way meanwhile (⌘, or the Window menu): it's the user's now.
        __weak NSWindow *weakSettings = settings;
        DPObserve(NSWindowDidBecomeKeyNotification, settings, ^{
            DPShowSettings(weakSettings);
            DPHiddenSettings = nil;
        });
    }
    DPObserve(NSWindowWillCloseNotification, settings, ^{ DPFinishProfileDelete(YES); });
    DPObserve(NSWindowWillCloseNotification, window, ^{ DPFinishProfileDelete(YES); });
    // Dia puts the confirmation on the key window, and fills Settings' list on the next pass.
    [window makeKeyAndOrderFront:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DPSheetHost != window) return;
        DPWaitForTable(settings, window, name, index, 40);
    });
}

#import "StdPatch/Hide.h"

extern DPPatch DPHideSetupSuggestions;

static char DPHiddenRowsKey, DPRowCountKey, DPNotingKey, DPHidByUsKey, DPDiaHiddenKey;

static NSSet<NSString *> *DPOnboardingTitles(void) {
    static NSSet<NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = [NSSet setWithArray:@[ @"Upgrade Chat", @"Import from another browser", @"Import passwords", @"Sign in to Google Calendar" ]];
    });
    return titles;
}

static NSString *DPTitleIn(NSView *cell) {
    NSView *title = DPFindView(cell, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSuggestionTitle); });
    NSTextField *label = (NSTextField *)DPFindView(title, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextField.class] && ((NSTextField *)view).stringValue.length > 0;
    });
    return [label.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL DPIsSetupSuggestion(NSView *cell) {
    if (!DPIsKind(cell, DPDiaSuggestionCell)) return NO;
    NSString *title = DPTitleIn(cell);
    return title.length > 0 && [DPOnboardingTitles() containsObject:title];
}

// Rows we collapsed, so a row Dia reuses for a real suggestion is never left at zero height.
static NSMutableIndexSet *DPHiddenRows(NSTableView *table) {
    NSMutableIndexSet *rows = DPGet(table, &DPHiddenRowsKey);
    if (rows && [DPGet(table, &DPRowCountKey) integerValue] == table.numberOfRows) return rows;
    rows = [NSMutableIndexSet indexSet];
    DPSet(table, &DPHiddenRowsKey, rows);
    DPSet(table, &DPRowCountKey, @(table.numberOfRows));
    return rows;
}

static void DPForgetHiddenRows(NSTableView *table) {
    DPSet(table, &DPHiddenRowsKey, nil);
    DPSet(table, &DPRowCountKey, nil);
}

static void DPNoteRows(NSTableView *table) {
    if ([DPGet(table, &DPNotingKey) boolValue]) return;
    DPSet(table, &DPNotingKey, @YES);
    dispatch_async(dispatch_get_main_queue(), ^{
        DPSet(table, &DPNotingKey, nil);
        NSInteger count = table.numberOfRows;
        if (count > 0) [table noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)]];
    });
}

static CGFloat DPSuggestions_heightOfRow(NSView *self, SEL _cmd, NSTableView *table, NSInteger row) {
    CGFloat height = DPCallOriginal(DPSuggestions_heightOfRow, self, table, row);
    if (!DPHideSetupSuggestions.on) return height;
    NSMutableIndexSet *rows = DPHiddenRows(table);
    if (![rows containsIndex:row]) return height;
    NSView *cell = [table viewAtColumn:0 row:row makeIfNecessary:NO];
    if (cell && !DPIsSetupSuggestion(cell)) {
        [rows removeIndex:row];
        return height;
    }
    return 0;
}

static BOOL DPSuggestions_shouldSelectRow(NSView *self, SEL _cmd, NSTableView *table, NSInteger row) {
    if (DPHideSetupSuggestions.on && [DPHiddenRows(table) containsIndex:row]) return NO;
    return DPCallOriginal(DPSuggestions_shouldSelectRow, self, table, row);
}

static void DPSuggestionCell_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSuggestionCell_layout, self);
    BOOL hide = DPHideSetupSuggestions.on && DPIsSetupSuggestion(self);
    BOOL ours = [DPGet(self, &DPHidByUsKey) boolValue];
    if (hide) {
        if (!ours) {
            DPSet(self, &DPDiaHiddenKey, @(self.hidden));
            DPSet(self, &DPHidByUsKey, @YES);
        }
        if (!self.hidden) self.hidden = YES;
    } else if (ours) {
        BOOL diaHidden = [DPGet(self, &DPDiaHiddenKey) boolValue];
        DPSet(self, &DPHidByUsKey, nil);
        DPSet(self, &DPDiaHiddenKey, nil);
        self.hidden = diaHidden;
    }
    if (!hide && !DPHideSetupSuggestions.on) return;
    NSTableView *table = nil;
    for (NSView *up = self.superview; up && !table; up = up.superview)
        if ([up isKindOfClass:NSTableView.class]) table = (NSTableView *)up;
    if (!table) return;
    if (!hide && !DPGet(table, &DPHiddenRowsKey)) return;
    NSInteger row = [table rowForView:self];
    if (row < 0) return;
    NSMutableIndexSet *rows = DPHiddenRows(table);
    if (hide == [rows containsIndex:row]) return;
    if (hide) [rows addIndex:row];
    else [rows removeIndex:row];
    DPNoteRows(table);
}

static void DPSuggestionsTable_reloadData(NSTableView *self, SEL _cmd) {
    DPForgetHiddenRows(self);
    DPCallOriginal(DPSuggestionsTable_reloadData, self);
}

static void DPSuggestionsTable_reloadRows(NSTableView *self, SEL _cmd, NSIndexSet *rows, NSIndexSet *columns) {
    DPForgetHiddenRows(self);
    DPCallOriginal(DPSuggestionsTable_reloadRows, self, rows, columns);
}

static void DPInstallHideSetupSuggestions(void) {
    DPHook(DPDiaCommandBarSuggestions, @selector(tableView:heightOfRow:), (IMP)DPSuggestions_heightOfRow);
    DPHook(DPDiaCommandBarSuggestions, @selector(tableView:shouldSelectRow:), (IMP)DPSuggestions_shouldSelectRow);
    DPHook(DPDiaSuggestionCell, @selector(layout), (IMP)DPSuggestionCell_layout);
    if (objc_getClass(DPDiaSuggestionsTable)) {
        DPHook(DPDiaSuggestionsTable, @selector(reloadData), (IMP)DPSuggestionsTable_reloadData);
        DPHook(DPDiaSuggestionsTable, @selector(reloadDataForRowIndexes:columnIndexes:), (IMP)DPSuggestionsTable_reloadRows);
    }
}

static void DPApplyHideSetupSuggestions(DPPatch *patch) {
    for (NSView *view in DPFindViews(DPDiaCommandBarSuggestions)) {
        NSTableView *table = (NSTableView *)DPFindView(view, ^BOOL(NSView *sub) { return [sub isKindOfClass:NSTableView.class]; });
        if (!table) continue;
        DPForgetHiddenRows(table);
        if (table.numberOfRows > 0) [table noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, table.numberOfRows)]];
        [table reloadData];
    }
}

DP_PATCH(DPHideSetupSuggestions) {
    .key = @"hideSetupSuggestions",
    .order = 91,
    .section = @"Command Bar",
    .title = @"Hide Setup Suggestions",
    .detail = @"Hide the setup rows in the command bar, like “Upgrade Chat” and “Import from another browser”. Searches, links and open tabs still show.",
    .symbol = @"text.badge.xmark",
    .tint = @"systemOrangeColor",
    .classes = DPClasses(DPDiaCommandBarSuggestions, DPDiaSuggestionCell, DPDiaSuggestionTitle, DPDiaSuggestionsTable),
    .install = DPInstallHideSetupSuggestions,
    .apply = DPApplyHideSetupSuggestions,
};

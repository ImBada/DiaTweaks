#import "Editor.h"

@implementation DPSidebarAddressRow (SuggestionResults)
- (NSTableView *)nativeSuggestionTable {
    NSView *suggestions = DPFindView(self.nativeSuggestionPanel, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaCommandBarSuggestions);
    });
    return (NSTableView *)DPFindView(suggestions, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTableView.class];
    });
}

- (void)submitSuggestionAtIndex:(NSInteger)index {
    NSTextView *editor = self.nativeSuggestionEditor;
    if (!editor.window || self.submittingSuggestion) return;
    if (index >= 0) {
        if (index >= (NSInteger)self.nativeSuggestionRows.count) return;
        NSTableView *table = [self nativeSuggestionTable];
        NSInteger row = self.nativeSuggestionRows[(NSUInteger)index].integerValue;
        if (!table || row >= table.numberOfRows) return;
        NSView *cell = table.numberOfColumns ? [table viewAtColumn:0 row:row makeIfNecessary:YES] : nil;
        NSTextField *label = (NSTextField *)DPFindView(cell, ^BOOL(NSView *view) {
            return [view isKindOfClass:NSTextField.class] && [(NSTextField *)view stringValue].length;
        });
        NSString *title = label.stringValue ?: cell.accessibilityLabel;
        if (![title isEqualToString:self.suggestionURLs[(NSUInteger)index]]) { [self refreshNativeSuggestions]; return; }
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    }
    NSView *overlay = self.nativeOverlay;
    if ([overlay respondsToSelector:NSSelectorFromString(@"setPicked:")]) [overlay setValue:@YES forKey:@"picked"];
    self.submittingSuggestion = YES;
    BOOL handled = [editor.delegate respondsToSelector:@selector(textView:doCommandBySelector:)] &&
        [editor.delegate textView:editor doCommandBySelector:@selector(insertNewline:)];
    if (!handled) { self.submittingSuggestion = NO; return; }
    [self dismissSuggestionList];
    __weak DPSidebarAddressRow *weakRow = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakRow refreshNativeSuggestions]; });
}

- (void)refreshNativeSuggestions {
    if (!self.inlineEditor) return;
    DPSidebarQuietSuggestionOverlay(self);
    [self positionSuggestions];
    if (![self.editingTabID isEqualToString:DPSidebarTabIdentifier(self.window) ?: @""]) { [self finishInlineEditing]; return; }
    if (self.submittingSuggestion) {
        NSView *overlay = self.nativeOverlay;
        if ([overlay respondsToSelector:NSSelectorFromString(@"watch")]) {
            NSTimer *watch = [overlay valueForKey:@"watch"];
            if ([watch isKindOfClass:NSTimer.class]) [watch fire];
        }
        if (!self.nativeSuggestionEditor.string.length || !self.nativeSuggestionPanel.window ||
            ![self.editingTabURL isEqualToString:DPSidebarURL(self.window) ?: @""]) [self finishInlineEditing];
        return;
    }
    if (!self.nativeSuggestionPanel.window) { [self finishInlineEditing]; return; }
    NSString *url = DPSidebarURL(self.window) ?: @"";
    if (![self.editingTabURL isEqualToString:url]) { [self finishInlineEditing]; return; }
    NSTableView *table = [self nativeSuggestionTable];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
    NSMutableArray<NSImage *> *icons = [NSMutableArray array];
    static NSImage *fallback;
    if (!fallback) fallback = [NSImage imageWithSystemSymbolName:@"arrow.up.left" accessibilityDescription:nil];
    for (NSInteger index = 0; index < MIN(10, table.numberOfRows); index++) {
        if ([table.delegate respondsToSelector:@selector(tableView:isGroupRow:)] &&
            [table.delegate tableView:table isGroupRow:index]) continue;
        NSView *cell = table.numberOfColumns ? [table viewAtColumn:0 row:index makeIfNecessary:YES] : nil;
        NSTextField *label = (NSTextField *)DPFindView(cell, ^BOOL(NSView *view) {
            return [view isKindOfClass:NSTextField.class] && [(NSTextField *)view stringValue].length;
        });
        NSString *title = label.stringValue ?: cell.accessibilityLabel;
        if (!title.length) continue;
        NSImageView *icon = (NSImageView *)DPFindView(cell, ^BOOL(NSView *view) {
            return [view isKindOfClass:NSImageView.class] && [(NSImageView *)view image] &&
                NSWidth(view.bounds) <= 24 && NSWidth(view.bounds) > 0;
        });
        [icons addObject:icon.image ?: fallback];
        [titles addObject:title];
        [rows addObject:@(index)];
    }
    if (![rows isEqualToArray:self.nativeSuggestionRows] || ![titles isEqualToArray:self.suggestionURLs] ||
        ![icons isEqualToArray:self.nativeSuggestionIcons]) {
        NSNumber *selectedRow = self.selectedSuggestion >= 0 && self.selectedSuggestion < (NSInteger)self.nativeSuggestionRows.count ?
            self.nativeSuggestionRows[(NSUInteger)self.selectedSuggestion] : nil;
        NSUInteger selected = selectedRow ? [rows indexOfObject:selectedRow] : NSNotFound;
        self.selectedSuggestion = selected == NSNotFound ? (titles.count ? 0 : -1) : (NSInteger)selected;
        self.hoveredSuggestion = -1;
        self.nativeSuggestionRows = rows;
        self.nativeSuggestionIcons = icons;
        self.suggestionURLs = titles;
        [self renderSuggestions];
    }
}


@end

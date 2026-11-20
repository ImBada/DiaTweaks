#import "Editor.h"

@implementation DPSidebarAddressRow (SuggestionSession)
- (void)updateNativeSuggestionsWithQuery:(NSString *)query {
    NSTextView *editor = self.nativeSuggestionEditor;
    if (!editor.window) return;
    self.suggestionGeneration++;
    NSTextView *inlineText = (NSTextView *)self.inlineEditor.currentEditor;
    NSRange selection = inlineText ? inlineText.selectedRange : NSMakeRange(query.length, 0);
    self.startingSuggestionSession = YES;
    [editor insertText:query replacementRange:NSMakeRange(0, editor.string.length)];
    if (!self.inlineEditor.currentEditor) {
        self.inlineEditor.stringValue = query;
        [self.inlineEditor selectText:nil];
    }
    self.addressFieldEditor = (NSTextView *)self.inlineEditor.currentEditor;
    if (NSMaxRange(selection) <= self.addressFieldEditor.string.length)
        self.addressFieldEditor.selectedRange = selection;
    self.startingSuggestionSession = NO;
    self.selectedSuggestion = self.suggestionURLs.count ? 0 : -1;
    self.hoveredSuggestion = -1;
    // Keep the surface mounted while Dia refreshes its results. Clearing it
    // here collapses the expanded row on every keystroke.
    [self refreshSuggestionHighlight];
    // Read after Dia has applied the input change, then keep listening for
    // network suggestions and favicons that arrive later.
    __weak DPSidebarAddressRow *weakRow = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakRow refreshNativeSuggestions]; });
}

- (void)attachSuggestionSession:(NSView *)panel editor:(NSTextView *)editor {
    if (!self.startingSuggestionSession || !self.inlineEditor || self.nativeSuggestionEditor) return;
    self.nativeSuggestionAlpha = panel.alphaValue;
    self.nativeSuggestionPanel = panel;
    self.nativeSuggestionEditor = editor;
    self.nativeSurfaceAlphas = [NSMapTable weakToStrongObjectsMapTable];
    for (NSView *ancestor = panel; ancestor; ancestor = ancestor.superview) {
        if (![NSStringFromClass(ancestor.class) isEqualToString:@"DPCommandBarOverlay"]) continue;
        self.nativeOverlay = ancestor;
        DPSidebarHideSuggestionSurface(ancestor, YES);
        [self.nativeSurfaceAlphas setObject:@(ancestor.alphaValue) forKey:ancestor];
        ancestor.alphaValue = 0;
        for (NSString *key in @[@"shade", @"windowBlur"]) {
            if (![ancestor respondsToSelector:NSSelectorFromString(key)]) continue;
            NSView *surface = [ancestor valueForKey:key];
            if (![surface isKindOfClass:NSView.class]) continue;
            [self.nativeSurfaceAlphas setObject:@(surface.alphaValue) forKey:surface];
            surface.alphaValue = 0;
        }
        break;
    }
    panel.alphaValue = 0;
    DPSidebarHideSuggestionSurface(panel, YES);
}

- (void)startSuggestionSession {
    if (!self.inlineEditor || self.startingSuggestionSession || self.nativeSuggestionEditor.window) return;
    self.startingSuggestionSession = YES;
    NSString *url = DPSidebarURL(self.window);
    BOOL empty = !url.length || [url isEqual:@"about:blank"] || [url hasPrefix:@"chrome://newtab"];
    if (empty) {
        // The new-tab input survives inside its hidden page after the command
        // bar is dismissed. Reuse its controller without opening another bar.
        NSView *bar = DPFindView(self.window.contentView.superview, ^BOOL(NSView *view) {
            if (!DPIsKind(view, DPDiaCommandBar)) return NO;
            // Chat pages also contain a command-bar text view, but it is a
            // conversation composer, not an address-suggestion session.
            return !DPFindView(view, ^BOOL(NSView *child) {
                return DPHasLabel(child, @"Add a tab or file");
            });
        });
        NSTextView *editor = (NSTextView *)DPFindView(bar, ^BOOL(NSView *view) {
            return [view isKindOfClass:NSTextView.class];
        });
        if (editor) {
            [self attachSuggestionSession:bar editor:editor];
            [self finishStartingSuggestionSession];
            return;
        }
    }
    if (!DPSidebarOpenEditorWithQuery(self, @"")) self.startingSuggestionSession = NO;
    NSUInteger generation = ++self.suggestionGeneration;
    __weak DPSidebarAddressRow *weakRow = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DPSidebarAddressRow *row = weakRow;
        if (row.startingSuggestionSession && row.suggestionGeneration == generation)
            [row finishStartingSuggestionSession];
    });
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object != self.inlineEditor) return;
    if (self.startingSuggestionSession) return;
    NSString *query = self.addressFieldEditor.string ?: self.inlineEditor.stringValue;
    if (self.nativeSuggestionEditor.window) [self updateNativeSuggestionsWithQuery:query];
    else [self startSuggestionSession];
}

- (void)finishStartingSuggestionSession {
    if (!self.startingSuggestionSession) return;
    if (!self.inlineEditor || !self.window.isKeyWindow) { self.startingSuggestionSession = NO; return; }
    NSTextView *editor = (NSTextView *)self.inlineEditor.currentEditor;
    if (!editor) {
        [self.inlineEditor selectText:nil];
        editor = (NSTextView *)self.inlineEditor.currentEditor;
    }
    self.addressFieldEditor = editor;
    editor.insertionPointColor = NSColor.labelColor;
    self.startingSuggestionSession = NO;
    if (!editor) { [self finishInlineEditing]; return; }
    [self.suggestionTimer invalidate];
    __weak DPSidebarAddressRow *weakRow = self;
    self.suggestionTimer = [NSTimer timerWithTimeInterval:0.12 repeats:YES block:^(NSTimer *timer) {
        DPSidebarAddressRow *row = weakRow;
        if (!row.inlineEditor) { [timer invalidate]; return; }
        [row refreshNativeSuggestions];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.suggestionTimer forMode:NSRunLoopCommonModes];
    [self updateNativeSuggestionsWithQuery:editor.string ?: @""];
    if (self.pendingSubmit) { self.pendingSubmit = NO; [self submitSuggestionAtIndex:-1]; }
}


@end

#import "Editor.h"

extern DPPatch DPSidebarDefaultEditor;

@implementation DPSidebarAddressRow (InlineEditor)
- (void)finishInlineEditing {
    NSTextField *field = self.inlineEditor;
    if (!field) return;
    self.inlineEditor = nil;
    DPSidebarCancelPopoverRequest(self);
    DPSidebarSetInlineOwner(self, NO);
    self.startingSuggestionSession = NO;
    self.suggestionGeneration++;
    [self.suggestionTimer invalidate];
    self.suggestionTimer = nil;
    self.editingTabURL = nil;
    self.editingTabID = nil;
    self.pendingSubmit = NO;
    NSTextView *nativeEditor = self.nativeSuggestionEditor;
    NSView *nativeSurface = self.nativeSuggestionPanel;
    self.nativeSuggestionEditor = nil;
    self.nativeSuggestionPanel.alphaValue = self.nativeSuggestionAlpha;
    self.nativeSuggestionPanel = nil;
    NSView *overlay = self.nativeOverlay;
    self.nativeOverlay = nil;
    if (!self.submittingSuggestion && nativeEditor && overlay.window) {
        NSEvent *dismiss = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint
            modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:overlay.window.windowNumber
            context:nil eventNumber:0 clickCount:1 pressure:1];
        [overlay mouseDown:dismiss];
    }
    for (NSView *surface in self.nativeSurfaceAlphas) {
        surface.alphaValue = [[self.nativeSurfaceAlphas objectForKey:surface] doubleValue];
        DPSidebarHideSuggestionSurface(surface, NO);
    }
    self.nativeSurfaceAlphas = nil;
    if (!self.submittingSuggestion && !overlay && nativeEditor.window && [nativeEditor.delegate respondsToSelector:@selector(textView:doCommandBySelector:)])
        [nativeEditor.delegate textView:nativeEditor doCommandBySelector:@selector(cancelOperation:)];
    DPSidebarHideSuggestionSurface(nativeSurface, NO);
    self.submittingSuggestion = NO;
    [self dismissSuggestionList];
    self.suggestionURLs = nil;

    self.nativeSuggestionRows = nil;
    self.nativeSuggestionIcons = nil;
    if (self.editingClickMonitor) {
        [NSEvent removeMonitor:self.editingClickMonitor];
        self.editingClickMonitor = nil;
    }
    if (self.previousCaretColor) self.addressFieldEditor.insertionPointColor = self.previousCaretColor;
    self.addressFieldEditor = nil;
    self.previousCaretColor = nil;
    if (field.currentEditor) [self.window makeFirstResponder:nil];
    self.nativeEditorVisible = NO;
    [field removeFromSuperview];
    self.address.hidden = NO;
    DPSidebarLayoutNativeControls(self);
    DPSidebarUpdateHover(self, YES);
}

- (void)openEditor:(id)sender {
    if (self.isEditingAddress || !self.window || self.window.attachedSheet) return;
    if (DPSidebarDefaultEditor.on) { DPSidebarOpenDefaultEditor(self); return; }
    NSURLComponents *current = [NSURLComponents componentsWithString:DPSidebarURL(self.window) ?: @""];
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.editable = YES;
    field.selectable = YES;
    field.bordered = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = self.address.font;
    field.textColor = NSColor.labelColor;
    field.cell.scrollable = YES;
    field.cell.usesSingleLineMode = YES;
    field.delegate = self;
    field.accessibilityLabel = @"Sidebar address";
    field.placeholderString = @"Enter URL";
    NSURLComponents *parts = current;
    if (parts.host.length && [@[@"http", @"https"] containsObject:parts.scheme.lowercaseString]) {
        parts.user = nil;
        parts.password = nil;
        field.stringValue = parts.string ?: @"";
    }
    NSRect frame = self.address.frame;
    field.frame = NSMakeRect(NSMinX(frame), 9, NSWidth(frame), 20);
    self.inlineEditor = field;
    DPSidebarSetInlineOwner(self, YES);
    self.editingTabURL = DPSidebarURL(self.window) ?: @"";
    self.editingTabID = DPSidebarTabIdentifier(self.window) ?: @"";
    [self addSubview:field positioned:NSWindowAbove relativeTo:self.address];
    [self.window makeKeyAndOrderFront:nil];
    [field selectText:nil];
    NSTextView *editor = (NSTextView *)field.currentEditor;
    if (!editor || self.inlineEditor != field) {
        [self finishInlineEditing];
        return;
    }
    self.address.hidden = YES;
    self.addressFieldEditor = editor;
    self.previousCaretColor = editor.insertionPointColor;
    editor.insertionPointColor = NSColor.labelColor;
    DPSidebarLayoutNativeControls(self);
    editor.selectedRange = NSMakeRange(0, editor.string.length);
    [editor scrollRangeToVisible:NSMakeRange(0, 0)];
    DPSidebarUpdateHover(self, YES);

    __weak DPSidebarAddressRow *weakRow = self;
    self.editingClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
        NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        DPSidebarAddressRow *row = weakRow;
        if (!row.window) return event;
        if (event.type == NSEventTypeKeyDown) {
            NSEventModifierFlags mods = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
            if (!row.startingSuggestionSession && (mods & NSEventModifierFlagCommand) &&
                [@[@"l", @"t", @"n", @"w"] containsObject:event.charactersIgnoringModifiers.lowercaseString])
                [row finishInlineEditing];
            return event;
        }
        if (event.window != row.window) return event;
        NSPoint point = [row convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, row.bounds)) {
            [row finishInlineEditing];
        } else if (event.type == NSEventTypeLeftMouseDown && NSPointInRect(point, row.inlineEditor.frame)) {
            NSTextView *fieldEditor = row.addressFieldEditor;
            NSRange selection = fieldEditor.selectedRange;
            if (selection.length && selection.location == 0 && selection.length == fieldEditor.string.length) {
                fieldEditor.selectedRange = NSMakeRange(selection.length, 0);
                [fieldEditor scrollRangeToVisible:fieldEditor.selectedRange];
                return nil;
            }
        }
        return event;
    }];
    [self startSuggestionSession];
}


@end

#import "Editor.h"

@implementation DPSidebarAddressRow (InlineCommands)
- (void)submitAddress:(NSString *)address {
    if (DPSidebarNavigate(self.window, address)) [self finishInlineEditing];
    else NSBeep();
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)editor doCommandBySelector:(SEL)command {
    if (control != self.inlineEditor) return NO;
    if (command == @selector(cancelOperation:)) {
        [self finishInlineEditing];
        return YES;
    }
    NSInteger count = (NSInteger)self.suggestionURLs.count;
    if (count && (command == @selector(moveDown:) || command == @selector(moveUp:))) {
        NSInteger next = command == @selector(moveDown:) ? MIN(count - 1, self.selectedSuggestion + 1) :
            MAX(0, self.selectedSuggestion - 1);
        [self highlightSuggestion:next];
        return YES;
    }
    if (command != @selector(insertNewline:)) return NO;
    if (self.startingSuggestionSession) { self.pendingSubmit = YES; return YES; }
    if (self.nativeSuggestionEditor.window) {
        [self submitSuggestionAtIndex:self.hoveredSuggestion >= 0 ? self.hoveredSuggestion : self.selectedSuggestion];
        return YES;
    }
    [self submitAddress:editor.string];
    return YES;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.inlineEditor && !self.startingSuggestionSession)
        [self finishInlineEditing];
}

@end

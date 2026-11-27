#import "Editor.h"

@interface DPSidebarActionButton : NSButton @end
@implementation DPSidebarActionButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    // NSButtonCell can tighten its title when its available width changes.
    // Draw the same glyphs at the same origin and truncate only the tail.
    NSDictionary *attributes = @{NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: self.contentTintColor ?: NSColor.labelColor};
    NSString *title = self.title;
    CGFloat available = MAX(0, NSWidth(self.bounds) - 4);
    if ([title sizeWithAttributes:attributes].width > available) {
        CGFloat tail = [@"…" sizeWithAttributes:attributes].width;
        NSUInteger end = 0;
        while (end < title.length) {
            NSRange next = [title rangeOfComposedCharacterSequenceAtIndex:end];
            if ([[title substringToIndex:NSMaxRange(next)] sizeWithAttributes:attributes].width > available - tail) break;
            end = NSMaxRange(next);
        }
        title = [[title substringToIndex:end] stringByAppendingString:@"…"];
    }
    NSSize size = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(2, floor((NSHeight(self.bounds) - size.height) / 2)) withAttributes:attributes];
}
- (void)mouseDown:(NSEvent *)event {
    // Hover and focus can change this button's frame during mouse tracking.
    // Start editing after the click dispatch, without waiting for tracking.
    __weak DPSidebarActionButton *button = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        DPSidebarActionButton *address = button;
        if (address.window && !address.hiddenOrHasHiddenAncestor)
            [NSApp sendAction:address.action to:address.target from:address];
    });
}
- (BOOL)becomeFirstResponder { BOOL focused = [super becomeFirstResponder]; if (focused) DPSidebarLayoutNativeControls(self.superview); return focused; }
- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [self.superview menuForEvent:event];
    if (menu) [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}
@end


@implementation DPSidebarAddressRow
- (CGFloat)preferredHeight { return 36 + (self.suggestions ? self.suggestionURLs.count * 34 + 8 : 0); }
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.address = [DPSidebarActionButton buttonWithTitle:@"Search or enter URL" target:self action:@selector(openEditor:)];
    self.address.bordered = NO;
    self.address.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.address.contentTintColor = NSColor.labelColor;
    [self addSubview:self.address];
    self.address.alignment = NSTextAlignmentLeft;
    self.address.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    self.address.accessibilityLabel = @"Edit address";
    [self refresh];
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { [self openEditor:self]; }
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    DPSidebarUpdateHover(self, NO);
    [self renderSuggestions];
}
- (void)layout {
    [super layout];
    DPSidebarLayoutNativeControls(self);
    [self positionSuggestions];
}
- (void)layoutAddressBefore:(CGFloat)edge {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.address.frame = NSMakeRect(8, 0, MAX(0, edge - 11), 36);
    self.inlineEditor.frame = NSMakeRect(8, 9, NSWidth(self.address.frame), 20);
    self.address.needsDisplay = YES;
    [CATransaction commit];
    [self updateActionHover];
}
- (void)updateActionHover {
    NSButton *extensions = DPAddressControlsFor(self, NO).extensionsButton;
    NSPoint pointer = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    BOOL hovered = self.window && !extensions.hidden && NSPointInRect(pointer,extensions.frame);
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        extensions.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:hovered ? 0.12 : 0].CGColor;
        [CATransaction commit];
    }];
}
- (BOOL)acceptsAddressMenuAt:(NSPoint)point { return NSPointInRect(point,self.address.frame); }
- (void)refresh {
    NSString *url = DPSidebarURL(self.window);
    self.URLString = url;
    if (!self.copyFeedback) [self updateAddressTitle:DPSidebarDisplayTitle(self.window, url)];
    DPSidebarRefreshNativeControls(self);
    DPSidebarUpdateHover(self, NO);
}
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if (!self.window) { [self finishInlineEditing]; DPSidebarRestoreNativeControls(self); } }
- (void)viewDidHide { [super viewDidHide]; [self finishInlineEditing]; DPSidebarRestoreNativeControls(self); }
- (BOOL)isEditingAddress { return self.inlineEditor != nil || self.nativeEditorVisible; }
- (void)setNativeEditorVisible:(BOOL)visible {
    _nativeEditorVisible = visible;
    self.address.hidden = visible || self.inlineEditor != nil;
    DPSidebarLayoutNativeControls(self);
    DPSidebarUpdateHover(self, NO);
}
- (void)dealloc {
    if (_editingClickMonitor) [NSEvent removeMonitor:_editingClickMonitor];
    [_suggestionTimer invalidate];
}
- (void)showCopyFeedback {
    NSUInteger feedback = ++self.copyFeedback;
    [self transitionAddressTitle];
    NSAccessibilityPostNotificationWithUserInfo(self.address, NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey: @"Link copied", NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
    __weak DPSidebarAddressRow *weakRow = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 950 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        DPSidebarAddressRow *row = weakRow;
        if (!row || row.copyFeedback != feedback) return;
        row.copyFeedback = 0;
        [row transitionAddressTitle];
    });
}
- (NSString *)addressFeedbackTitle {
    return self.copyFeedback ? @"✓ Link copied" : DPSidebarDisplayTitle(self.window, self.URLString);
}
- (void)transitionAddressTitle {
    NSString *title = [self addressFeedbackTitle];
    if ([self.address.title isEqualToString:title]) return;
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && !self.address.hiddenOrHasHiddenAncestor) {
        self.address.wantsLayer = YES;
        self.address.layer.masksToBounds = YES;
        [self.address displayIfNeeded];
        CATransition *slide = [CATransition animation];
        slide.type = kCATransitionPush;
        slide.subtype = kCATransitionFromBottom;
        slide.duration = 0.24;
        slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.address.layer addAnimation:slide forKey:@"copyFeedback"];
    }
    [self updateAddressTitle:title];
    [self.address displayIfNeeded];
}
- (void)updateAddressTitle:(NSString *)title {
    self.address.title = title;
    self.address.contentTintColor = !self.copyFeedback && DPSidebarIsEmptyAddress(self.URLString)
        ? NSColor.secondaryLabelColor : NSColor.labelColor;
}
- (void)copyLink:(id)sender {
    NSString *url = DPSidebarURL(self.window);
    if (DPSidebarIsEmptyAddress(url)) return;
    [NSPasteboard.generalPasteboard clearContents];
    if ([NSPasteboard.generalPasteboard setString:url forType:NSPasteboardTypeString]) [self showCopyFeedback];
}
@end

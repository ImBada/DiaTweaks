#import "CompactCommandBar.h"

static const CGFloat DPCommandBarSpacing = 14;
static char DPCompactedKey;

NSSize DPCompactSize(NSView *container, NSSize size) {
    if (!DPCompactCommandBar.on && !DPTurnOffAI.on) return size;
    NSView *commandBar = DPCommandBarPart(container, DPDiaCommandBar), *toolbar = DPCompactToolbar(commandBar);
    NSView *input = DPCommandBarPart(commandBar, DPDiaCommandBarInput), *suggestions = DPCommandBarPart(commandBar, DPDiaCommandBarSuggestions);
    if (toolbar && input && suggestions) {
        CGFloat emptyGap = suggestions.intrinsicContentSize.height > 0 ? 0 : NSMinY(suggestions.frame) - NSMaxY(input.frame);
        size.height -= MAX(0, NSHeight(toolbar.frame) + emptyGap - NSMinY(input.frame));
    }
    size.height -= DPHiddenSuggestionsHeight(suggestions);
    return size;
}

static void DPPopover_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSSize compact = DPCompactSize(self, size);
    DPSetTrim(self, size.height - compact.height);
    DPCallOriginal(DPPopover_setFrameSize, self, compact);
}

// Shrunk with its container the bar would squeeze the suggestions to keep the row, so the container clips the row.
static void DPCommandBar_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    CGFloat trim = 0;
    for (NSView *view = self.superview; view && !trim; view = view.superview) trim = DPTrim(view);
    DPCallOriginal(DPCommandBar_setFrameSize, self, NSMakeSize(size.width, size.height + trim));
}

static void DPPopover_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    DPCallOriginal(DPPopover_setFrameOrigin, self, origin);
    if (!DPCompactCommandBar.on) return;
    NSView *commandBar = DPCommandBarPart(self, DPDiaCommandBar);
    if (DPCompactToolbar(commandBar)) commandBar.needsLayout = YES;
}

static void DPRefit(NSView *commandBar) {
    NSView *box = commandBar.superview;
    while (box && !DPIsKind(box, DPDiaPopover) && !(DPIsKind(box, DPDiaAssistantPanel) && DPTrimsPanel(box))) box = box.superview;
    if (!box || !DPMayAdjust(box)) return;
    NSRect before = box.frame;
    NSSize full = NSMakeSize(NSWidth(before), NSHeight(before) + DPTrim(box));
    if (fabs(full.height - DPCompactSize(box, full).height - DPTrim(box)) < 0.5) return;
    [box setFrameSize:full];
    if (DPIsKind(box, DPDiaPopover) && !box.superview.isFlipped) [box setFrameOrigin:NSMakePoint(NSMinX(before), NSMaxY(before) - NSHeight(box.frame))];
    box.superview.superview.needsLayout = YES;
}

static void DPCommandBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPCommandBar_layout, self);
    DPRefit(self);
    NSView *toolbar = DPCommandBarPart(self, DPDiaCommandBarToolbar), *suggestions = DPCommandBarPart(self, DPDiaCommandBarSuggestions);
    CGFloat hidden = DPHiddenSuggestionsHeight(suggestions);
    BOOL compact = DPCompactToolbar(self) != nil;
    if (hidden && toolbar && !compact) {
        NSRect frame = toolbar.frame;
        frame.origin.y = NSMaxY(suggestions.frame) - hidden;
        if (!NSEqualRects(toolbar.frame, frame) && DPMayAdjust(toolbar)) toolbar.frame = frame;
    }
    NSStackView *stack = toolbar.subviews.firstObject;
    if (![stack isKindOfClass:NSStackView.class]) return;
    if (!compact && !DPGet(stack, &DPCompactedKey)) return;
    DPSet(stack, &DPCompactedKey, compact ? @YES : nil);
    for (NSView *view in stack.views)
        if (view != DPGoButton(toolbar)) view.alphaValue = !compact;
    NSView *input = DPCommandBarPart(self, DPDiaCommandBarInput);
    if (!compact) return (void)(input.needsLayout = YES);
    if (!input || !suggestions || !self.window) return;
    CGFloat gap = NSMinY(suggestions.frame) - NSMaxY(input.frame), rowBottom = NSMinY(suggestions.frame) + NSMinY(input.frame) - gap;
    CGFloat cut = MAX(0, NSMaxY([self convertRect:self.bounds toView:nil]) - NSHeight(self.window.frame));
    NSRect frame = toolbar.frame;
    frame.origin.y = (MIN(cut, NSMinY(input.frame)) + rowBottom - NSHeight(frame)) / 2;
    if (!NSEqualRects(toolbar.frame, frame) && DPMayAdjust(toolbar)) toolbar.frame = frame;
}

static CGFloat DPTextWidth(NSView *input, NSView *text, NSView *go) {
    return MAX(0, NSWidth(input.bounds) - NSMinX(text.frame) - NSWidth(go.frame) - 2 * DPCommandBarSpacing);
}

static void DPCommandBarInput_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPCommandBarInput_layout, self);
    if (!DPCompactCommandBar.on) return;
    NSView *go = DPGoButton(DPCompactToolbar(self.superview)), *text = DPCommandBarPart(self, DPDiaCommandBarText);
    if (!go || !text) return;
    NSRect frame = text.frame;
    frame.size.width = DPTextWidth(self, text, go);
    if (!NSEqualRects(text.frame, frame) && DPMayAdjust(text)) text.frame = frame;
}

// The toolbar lays Go out after the input, and Go widens to "Go ↵" as you type a URL.
static void DPCommandBarButton_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPCommandBarButton_layout, self);
    if (!DPCompactCommandBar.on) return;
    NSView *commandBar = self;
    while (commandBar && !DPIsKind(commandBar, DPDiaCommandBar)) commandBar = commandBar.superview;
    NSView *input = DPCommandBarPart(commandBar, DPDiaCommandBarInput), *text = DPCommandBarPart(input, DPDiaCommandBarText);
    if (text && self == DPGoButton(DPCompactToolbar(commandBar)) && fabs(NSWidth(text.frame) - DPTextWidth(input, text, self)) > 0.5) input.needsLayout = YES;
}

static void DPCommandBarButton_setAccessibilityLabel(NSView *self, SEL _cmd, NSString *label) {
    DPCallOriginal(DPCommandBarButton_setAccessibilityLabel, self, label);
    if (!DPCompactCommandBar.on) return;
    NSView *commandBar = self;
    while (commandBar && !DPIsKind(commandBar, DPDiaCommandBar)) commandBar = commandBar.superview;
    NSView *toolbar = DPCommandBarPart(commandBar, DPDiaCommandBarToolbar);
    NSStackView *stack = toolbar.subviews.firstObject;
    if (![stack isKindOfClass:NSStackView.class] || ![stack.views containsObject:self] || self == DPGoButton(toolbar)) return;
    DPRememberChatLocked(DPChatLocked(toolbar));
    if ((DPCompactToolbar(commandBar) != nil) == (DPGet(stack, &DPCompactedKey) != nil)) return;
    for (NSView *view = commandBar; view; view = view.superview) view.needsLayout = YES;
}

static NSView *DPCommandBarToolbar_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    NSView *hit = DPCallOriginal(DPCommandBarToolbar_hitTest, self, point);
    if (!DPCompactCommandBar.on || !hit) return hit;
    NSView *commandBar = self.superview.superview;
    if (!DPIsKind(commandBar, DPDiaCommandBar) || !DPCompactToolbar(commandBar)) return hit;
    return [hit isDescendantOf:DPGoButton(self)] ? hit : nil;
}

void DPInstallCommandBarLayout(void) {
    DPHook(DPDiaPopover, @selector(setFrameSize:), (IMP)DPPopover_setFrameSize);
    DPHook(DPDiaPopover, @selector(setFrameOrigin:), (IMP)DPPopover_setFrameOrigin);
    DPInstallNewTabLayout();
    DPHook(DPDiaCommandBar, @selector(setFrameSize:), (IMP)DPCommandBar_setFrameSize);
    DPHook(DPDiaCommandBar, @selector(layout), (IMP)DPCommandBar_layout);
    DPHook(DPDiaCommandBarButton, @selector(setAccessibilityLabel:), (IMP)DPCommandBarButton_setAccessibilityLabel);
    DPHook(DPDiaCommandBarButton, @selector(layout), (IMP)DPCommandBarButton_layout);
    DPHook(DPDiaCommandBarInput, @selector(layout), (IMP)DPCommandBarInput_layout);
    DPHook(DPDiaCommandBarToolbar, @selector(hitTest:), (IMP)DPCommandBarToolbar_hitTest);
}

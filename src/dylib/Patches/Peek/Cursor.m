#import "Patches/Peek/Peek.h"

static BOOL DPPeekHiddenAncestor(NSView *view) {
    for (NSView *up = view.superview; up; up = up.superview)
        if ([up isKindOfClass:DPPeekCard.class]) {
            DPPeekCard *card = (DPPeekCard *)up;
            return card.closing || card.isHiddenOrHasHiddenAncestor;
        }
    return NO;
}

static BOOL DPWeb_shouldChangeCurrentCursor(NSView *self, SEL _cmd) {
    if (!DPCallOriginal(DPWeb_shouldChangeCurrentCursor, self)) return NO;
    if (!DPPeek.on) return YES;
    if (DPPeekHiddenAncestor(self)) return NO;
    DPPeekCard *peek = DPPeekCardIn(self.window);
    if (!peek) return YES;
    NSPoint mouse = self.window.mouseLocationOutsideOfEventStream;
    if (![self isDescendantOf:peek] && !NSPointInRect([peek convertPoint:mouse fromView:nil], peek.bounds)) return YES;
    NSView *root = self.window.contentView;
    NSView *hit = [root hitTest:[root.superview convertPoint:mouse fromView:nil]];
    return hit == self || [hit isDescendantOf:self];
}

static void DPWeb_addCursorRect(NSView *self, SEL _cmd, NSRect rect, NSCursor *cursor) {
    if (!DPPeek.on) return (void)DPCallOriginal(DPWeb_addCursorRect, self, rect, cursor);
    if (DPPeekHiddenAncestor(self)) return;
    DPPeekCard *peek = DPPeekCardIn(self.window);
    if (!peek || [self isDescendantOf:peek]) return (void)DPCallOriginal(DPWeb_addCursorRect, self, rect, cursor);
    // Cursor rectangles, like Chromium's immediate cursor updates, ignore overlapping siblings.
    NSRect covered = NSIntersectionRect(rect, [self convertRect:peek.bounds fromView:peek]);
    if (NSIsEmptyRect(covered)) return (void)DPCallOriginal(DPWeb_addCursorRect, self, rect, cursor);
    NSRect exposed[] = {
        NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), NSMinY(covered) - NSMinY(rect)),
        NSMakeRect(NSMinX(rect), NSMaxY(covered), NSWidth(rect), NSMaxY(rect) - NSMaxY(covered)),
        NSMakeRect(NSMinX(rect), NSMinY(covered), NSMinX(covered) - NSMinX(rect), NSHeight(covered)),
        NSMakeRect(NSMaxX(covered), NSMinY(covered), NSMaxX(rect) - NSMaxX(covered), NSHeight(covered)),
    };
    for (NSUInteger i = 0; i < sizeof exposed / sizeof *exposed; i++)
        if (!NSIsEmptyRect(exposed[i])) DPCallOriginal(DPWeb_addCursorRect, self, exposed[i], cursor);
}

void DPPeekInstallCursor(void) {
    DPHook(DPDiaRenderWidget, @selector(shouldChangeCurrentCursor), (IMP)DPWeb_shouldChangeCurrentCursor);
    DPHook(DPDiaRenderWidget, @selector(addCursorRect:cursor:), (IMP)DPWeb_addCursorRect);
}

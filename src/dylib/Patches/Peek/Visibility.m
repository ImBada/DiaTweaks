#import "Patches/Peek/Peek.h"

@interface DPPeekCard (VisibilityState)
@property (nonatomic, weak) NSResponder *savedResponder;
@property (nonatomic) NSRect parkedFrame;
@property (nonatomic) BOOL reparenting;
- (void)followPane;
@end

NSView *DPPeekPane(NSWindow *window, NSRect area) {
    NSView *pane = nil, *under = nil;
    CGFloat overlap = 0;
    for (NSView *candidate in DPFindViews(DPDiaContentPane)) {
        if (candidate.window != window) continue;
        NSRect hit = NSIntersectionRect([window convertRectToScreen:[candidate convertRect:candidate.bounds toView:nil]], area);
        if (!candidate.isHiddenOrHasHiddenAncestor && NSWidth(hit) * NSHeight(hit) > overlap) {
            under = candidate;
            overlap = NSWidth(hit) * NSHeight(hit);
        }
        if (NSWidth(candidate.bounds) * NSHeight(candidate.bounds) > NSWidth(pane.bounds) * NSHeight(pane.bounds)) pane = candidate;
    }
    return under ?: pane;
}

NSView *DPPeekHolder(NSWindow *window, NSView *pane) {
    NSView *chatHolder = DPPeekChatHolder(window, pane);
    if (chatHolder) return chatHolder;
    for (NSView *view = pane; view && view != window.contentView; view = view.superview)
        if (view.layer.cornerRadius > 0 && view.layer.masksToBounds) return view;
    return window.contentView;
}

void DPPeekWatchPane(DPPeekCard *peek, NSView *pane) {
    DPPeekUnwatchPane(peek.paneObserver);
    peek.paneObserver = nil;
    peek.pane = pane;
    if (!pane) return;
    peek.paneObserver = DPPeekWatchPaneAncestors(peek, pane, peek.superview);
    peek.needsLayout = YES;
}

@implementation DPPeekCard (Visibility)

- (void)setOriginVisible:(BOOL)visible {
    NSWindow *window = self.window ?: self.originWindow;
    NSView *root = window.contentView;
    if (!root || (visible && self.closing)) return;
    if (visible && !self.isHiddenOrHasHiddenAncestor && self.window == window) return;
    if (!visible && self.hidden && self.superview == root) return;

    NSView *previous = self.superview;
    NSRect rootFrame = previous.window == window ? [root convertRect:self.frame fromView:previous]
                                                 : (!NSIsEmptyRect(self.parkedFrame) ? self.parkedFrame : root.bounds);
    if (!visible) {
        NSResponder *responder = window.firstResponder;
        BOOL hadFocus = [responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:self];
        if (hadFocus) {
            if ([responder isKindOfClass:NSText.class] && [(NSText *)responder isFieldEditor]) {
                id delegate = [(NSText *)responder delegate];
                self.savedResponder = [delegate isKindOfClass:NSSearchField.class] ? delegate : self.host;
            } else {
                self.savedResponder = responder;
            }
        }
        DPPeekResetControlHints(self.controls);
        self.parkedFrame = rootFrame;
        DPWithoutAnimation(^{
            self.hidden = YES;
            // Keep the hosted view mounted in the window even if Dia removes the old tab's container.
            if (previous != root) {
                self.reparenting = YES;
                [root addSubview:self positioned:NSWindowBelow relativeTo:nil];
                self.reparenting = NO;
            }
            self.frame = rootFrame;
        });
        if (hadFocus) [window makeFirstResponder:nil];
        [window resetCursorRects];
        return;
    }

    NSView *pane = self.pane;
    if (pane.window != window || pane.isHiddenOrHasHiddenAncestor)
        pane = DPPeekPane(window, [window convertRectToScreen:[root convertRect:rootFrame toView:nil]]);
    NSView *holder = DPPeekHolder(window, pane);
    DPWithoutAnimation(^{
        if (holder != previous || self.window != window) {
            self.reparenting = YES;
            [holder addSubview:self positioned:NSWindowAbove relativeTo:nil];
            self.reparenting = NO;
        }
        NSRect frame = pane ? NSIntersectionRect([holder convertRect:pane.bounds fromView:pane], holder.bounds) : holder.bounds;
        self.frame = NSIsEmptyRect(frame) ? holder.bounds : frame;
        self.autoresizingMask = pane ? NSViewNotSizable : NSViewWidthSizable | NSViewHeightSizable;
        DPPeekWatchPane(self, pane);
        [self stopMotion];
        if (self.card.alphaValue == 0) self.card.alphaValue = self.dim.alphaValue = self.controls.alphaValue = 1;
        self.needsLayout = YES;
        [self layoutSubtreeIfNeeded];
        self.hidden = NO;
    });
    [window resetCursorRects];

    __weak DPPeekCard *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        DPPeekCard *peek = weak;
        NSWindow *win = peek.window;
        if (!win || peek.closing || peek.isHiddenOrHasHiddenAncestor || DPPeekCardIn(win) != peek) return;
        [peek followPane];
        if (!win.isKeyWindow) return;
        NSResponder *current = win.firstResponder;
        if ([current isKindOfClass:NSView.class] && [(NSView *)current isDescendantOf:peek]) return;
        if ([current isKindOfClass:NSText.class]) return;
        if (DPPeekResponderInChat(current)) return;
        BOOL defaultFocus = !current || current == win || DPIsKind(current, DPDiaRenderWidget)
            || ([current isKindOfClass:NSView.class] && peek.pane && [(NSView *)current isDescendantOf:peek.pane]);
        if (!defaultFocus) return;
        NSResponder *saved = peek.savedResponder;
        NSView *target = [saved isKindOfClass:NSView.class] && [(NSView *)saved isDescendantOf:peek] && !((NSView *)saved).isHiddenOrHasHiddenAncestor
            ? (NSView *)saved : peek.host;
        if (target) [win makeFirstResponder:target];
    });
}

@end

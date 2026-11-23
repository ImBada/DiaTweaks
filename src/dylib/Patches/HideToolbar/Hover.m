#import "HideToolbar.h"

static const CGFloat DPToolbarHoverHeight = 8;
static char DPHoverKey;

static NSTimer *DPEase(CGFloat from, CGFloat to, void (^step)(CGFloat value, BOOL done)) {
    CFTimeInterval start = CACurrentMediaTime();
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) {
        CGFloat t = MIN(1, (CACurrentMediaTime() - start) / 0.25);
        if (t == 1) [timer invalidate];
        step(from + (to - from) * t * t * (3 - 2 * t), t == 1);
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    return timer;
}

@implementation DPToolbarHover {
    __unsafe_unretained id _lastResponder;
    __weak NSWindow *_observedWindow;
}

+ (DPToolbarHover *)forPane:(NSView *)pane {
    return DPGet(pane, &DPHoverKey);
}

+ (DPToolbarHover *)attachToPane:(NSView *)pane {
    DPToolbarHover *hover = [self forPane:pane];
    if (hover) return hover;
    hover = [DPToolbarHover new];
    hover.pane = pane;
    DPSet(pane, &DPHoverKey, hover);
    return hover;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(windowResignedKey:) name:NSWindowDidResignKeyNotification object:nil];
    [center addObserver:self selector:@selector(reset) name:NSApplicationDidResignActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [_animation invalidate];
    [_hideTimer invalidate];
    [_inPlaceAnimation invalidate];
    if (_tracking) [_pane removeTrackingArea:_tracking];
    if (_paneTracking) [_pane removeTrackingArea:_paneTracking];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)stopReveal {
    [self.animation invalidate];
    [self.hideTimer invalidate];
    self.animation = self.hideTimer = nil;
    _revealed = NO;
    self.progress = 0;
    _lastResponder = nil;
}

- (void)stopInPlace {
    [self.inPlaceAnimation invalidate];
    self.inPlaceAnimation = nil;
    _inPlace = NO;
    self.inPlaceProgress = 0;
}

- (void)detach {
    [self stopReveal];
    [self stopInPlace];
    [self stopObservingWindow];
    if (self.tracking) [self.pane removeTrackingArea:self.tracking];
    self.tracking = nil;
    if (self.paneTracking) [self.pane removeTrackingArea:self.paneTracking];
    self.paneTracking = nil;
    if (self.pane) DPSet(self.pane, &DPHoverKey, nil);
}

- (void)reset {
    if (!self.revealed && self.progress == 0 && !self.animation && !self.hideTimer) return;
    [self stopReveal];
    if (self.pane) DPApplyToolbar(self.pane);
}

- (void)windowResignedKey:(NSNotification *)notification {
    if (notification.object == self.pane.window) [self reset];
}

- (BOOL)containsPointer {
    NSWindow *window = self.pane.window;
    if (!window.isKeyWindow || !NSApp.isActive || self.pane.hiddenOrHasHiddenAncestor) return NO;
    NSPoint point = [self.pane convertPoint:[window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
    return self.tracking && NSMouseInRect(point, self.tracking.rect, self.pane.isFlipped);
}

// Moving fast out of the page skips the 8pt strip between mouse events, so the pointer can sit over the top of the window unseen.
- (BOOL)pointerAbovePage {
    NSWindow *window = self.pane.window;
    if (!window.isKeyWindow || !NSApp.isActive || self.pane.hiddenOrHasHiddenAncestor) return NO;
    NSPoint mouse = NSEvent.mouseLocation;
    NSRect pane = [window convertRectToScreen:[self.pane convertRect:self.pane.bounds toView:nil]];
    if (mouse.x < NSMinX(pane) || mouse.x > NSMaxX(pane)) return NO;
    // With tabs at the top the tab bar sits above the page, so only the window's top edge counts as overshoot.
    CGFloat lower = DPTabsAtTop(window) && !self.inPlace ? NSMaxY(window.frame) - 12 : NSMaxY(pane) - 1;
    if (mouse.y < lower) return NO;
    return mouse.y <= NSMaxY(window.frame) + 24;
}

- (BOOL)toolbarHasFocus {
    NSWindow *window = self.pane.window;
    if (!window.isKeyWindow || !NSApp.isActive) return NO;
    NSResponder *responder = window.firstResponder;
    if ([responder isKindOfClass:NSTextView.class] && ((NSTextView *)responder).isFieldEditor)
        responder = (NSResponder *)((NSTextView *)responder).delegate;
    return [responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:self.bar];
}

- (void)armHideTimer {
    if (self.hideTimer) return;
    __weak DPToolbarHover *weakSelf = self;
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        DPToolbarHover *me = weakSelf;
        if (!me) return [timer invalidate];
        if ([me containsPointer]) {
            [timer invalidate];
            me.hideTimer = nil;
            return;
        }
        if ([me pointerAbovePage] || [me toolbarHasFocus] || NSEvent.pressedMouseButtons) return;
        [timer invalidate];
        me.hideTimer = nil;
        me.revealed = NO;
    }];
}

- (void)observeWindow:(NSWindow *)window {
    if (window == _observedWindow) return;
    [self stopObservingWindow];
    if (!window) return;
    _observedWindow = window;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidUpdate:) name:NSWindowDidUpdateNotification object:window];
}

- (void)stopObservingWindow {
    if (!_observedWindow) return;
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidUpdateNotification object:_observedWindow];
    _observedWindow = nil;
    _lastResponder = nil;
}

- (void)windowDidUpdate:(NSNotification *)notification {
    NSWindow *window = self.pane.window;
    if (notification.object != window || !window.isKeyWindow || !NSApp.isActive) return;
    NSResponder *responder = window.firstResponder;
    if (responder == _lastResponder) return;
    _lastResponder = responder;
    if (!DPHideToolbar.on || self.inPlace || self.revealed) return;
    if (!self.bar || self.bar.hiddenOrHasHiddenAncestor || ![self toolbarHasFocus]) return;
    self.revealed = YES;
    [self armHideTimer];
}

- (void)setRevealed:(BOOL)revealed {
    if (_revealed == revealed) return;
    _revealed = revealed;
    [self.animation invalidate];
    __weak DPToolbarHover *weakSelf = self;
    self.animation = DPEase(self.progress, revealed, ^(CGFloat value, BOOL done) {
        DPToolbarHover *me = weakSelf;
        if (!me.pane) return;
        me.progress = value;
        DPApplyToolbarOpacity(me);
        if (!done) return;
        me.animation = nil;
        DPApplyToolbar(me.pane);
    });
    DPApplyToolbar(self.pane);
}

- (void)setInPlace:(BOOL)inPlace {
    if (_inPlace == inPlace) return;
    _inPlace = inPlace;
    [self.inPlaceAnimation invalidate];
    __weak DPToolbarHover *weakSelf = self;
    self.inPlaceAnimation = DPEase(self.inPlaceProgress, inPlace, ^(CGFloat value, BOOL done) {
        DPToolbarHover *me = weakSelf;
        if (!me.pane) return;
        me.inPlaceProgress = value;
        if (done) me.inPlaceAnimation = nil;
        DPApplyToolbar(me.pane);
    });
}

- (void)mouseEntered:(NSEvent *)event {
    if (!DPHideToolbar.on || !DPRevealToolbarOnHover.on || ![self containsPointer]) return;
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    self.revealed = YES;
}

- (void)mouseExited:(NSEvent *)event {
    if (!DPHideToolbar.on) return;
    if (!self.revealed) {
        // The pointer left the page upward, over the top of the window: reveal, then hide once it comes back.
        if (DPRevealToolbarOnHover.on && [self pointerAbovePage]) {
            self.revealed = YES;
            [self armHideTimer];
        }
        return;
    }
    // Growing the tracking area on reveal sends a stray exit.
    if ([self containsPointer] || self.hideTimer) return;
    [self armHideTimer];
}

- (NSTrackingArea *)trackingArea:(NSTrackingArea *)area rect:(NSRect)rect {
    if (area && NSEqualRects(area.rect, rect)) return area;
    if (area) [self.pane removeTrackingArea:area];
    if (NSIsEmptyRect(rect)) return nil;
    NSTrackingArea *fresh = [[NSTrackingArea alloc] initWithRect:rect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow
                                                           owner:self userInfo:nil];
    [self.pane addTrackingArea:fresh];
    return fresh;
}

- (void)updateForBar:(NSView *)bar bookmarks:(NSView *)bookmarks {
    self.bar = bar;
    self.bookmarks = bookmarks;
    if (DPHideToolbar.on || DPHideToolbar.progress > 0) self.inPlace = DPKeptInPlace(self.pane);
    else [self stopInPlace];
    // AppKit posts this whenever firstResponder changes, so ⌘L into a hidden bar reveals it without polling.
    if (DPHideToolbar.on && !self.inPlace) [self observeWindow:self.pane.window];
    else [self stopObservingWindow];
    BOOL watching = DPHideToolbar.on && DPRevealToolbarOnHover.on && !self.inPlace && !bar.hiddenOrHasHiddenAncestor;
    NSRect rect = NSZeroRect;
    if (watching) {
        rect = DPLaidOutFrame(bar);
        if (bookmarks) rect = NSUnionRect(rect, DPLaidOutFrame(bookmarks));
        rect = NSIntersectionRect(rect, self.pane.bounds);
        CGFloat height = MIN(DPToolbarHoverHeight, NSHeight(rect));
        if (self.revealed) {
            if (!self.pane.isFlipped) rect.origin.y -= DPToolbarHoverHeight;
            rect.size.height += DPToolbarHoverHeight;
            rect = NSIntersectionRect(rect, self.pane.bounds);
        } else {
            if (!self.pane.isFlipped) rect.origin.y = NSMaxY(rect) - height;
            rect.size.height = height;
        }
    } else if (![self toolbarHasFocus]) {
        [self stopReveal];
    }
    self.tracking = [self trackingArea:self.tracking rect:rect];
    self.paneTracking = [self trackingArea:self.paneTracking rect:watching ? self.pane.bounds : NSZeroRect];
}
@end

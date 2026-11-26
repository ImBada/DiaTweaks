#import "Patches/Peek/Peek.h"

static const CGFloat DPPeekShadowRoom = 48, DPPeekEdgeAlpha = 0.12;
static NSHashTable<DPPeekCard *> *DPPeekCards;

static NSRect DPPeekCardRect(NSRect area) {
    CGFloat insetX = MIN(MAX(NSWidth(area) * 0.09, 48), NSWidth(area) * 0.18);
    return NSInsetRect(area, insetX, MAX(10, NSHeight(area) * 0.012));
}

@interface DPPeekCard ()
@property (nonatomic, weak) NSResponder *savedResponder;
@property (nonatomic) NSRect parkedFrame;
@property (nonatomic) BOOL reparenting;
@end

@implementation DPPeekCard

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)setSource:(id)source {
    _source = source;
    if (source) self.hadSource = YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!DPPeekCards) DPPeekCards = [NSHashTable weakObjectsHashTable];
    if (self.window) {
        if (!self.originWindow) self.originWindow = self.window;
        [DPPeekCards addObject:self];
    } else if (!self.reparenting) {
        if (self.closing || !self.superview || !self.originWindow) {
            [DPPeekCards removeObject:self];
            DPPeekUpdateSyncTimer();
        } else {
            __weak DPPeekCard *weak = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                DPPeekCard *peek = weak;
                if (peek && !peek.closing && !peek.window && peek.originWindow) DPPeekSyncTabs(peek.originWindow);
            });
        }
    }
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    self.clip.layer.borderWidth = 1 / (self.window.backingScaleFactor ?: 2);
    self.needsLayout = YES;
}

- (NSRect)cardFrame {
    NSRect card = DPPeekCardRect(self.bounds), page = self.bounds;
    CGFloat g = self.grown;
    NSRect frame = NSMakeRect(NSMinX(card) + (NSMinX(page) - NSMinX(card)) * g, NSMinY(card) + (NSMinY(page) - NSMinY(card)) * g,
                              NSWidth(card) + (NSWidth(page) - NSWidth(card)) * g, NSHeight(card) + (NSHeight(page) - NSHeight(card)) * g);
    return [self backingAlignedRect:frame options:NSAlignAllEdgesNearest];
}

- (void)layout {
    [super layout];
    NSRect card = self.cardFrame;
    self.dim.frame = self.bounds;
    self.card.frame = NSInsetRect(card, -DPPeekShadowRoom, -DPPeekShadowRoom);
    self.clip.frame = self.shade.frame = NSInsetRect(self.card.bounds, DPPeekShadowRoom, DPPeekShadowRoom);
    DPWithoutAnimation(^{ self.clip.layer.borderColor = [NSColor colorWithWhite:1 alpha:DPPeekEdgeAlpha * (1 - self.grown)].CGColor; });
    self.controls.frame = DPPeekControlsFrame(self, (NSRect){{NSMaxX(card) + 12, NSMinY(card) + 4}, self.controls.frame.size});
    // The page redraws at its new size at once instead of animating with the sidebar slide, so it covers both card sizes meanwhile.
    CGFloat bar = DPPeekToolbarInset(self);
    NSSize page = NSMakeSize(NSWidth(self.clip.bounds), MAX(0, NSHeight(self.clip.bounds) - bar));
    if (self.paneMoves) page = NSMakeSize(MAX(page.width, NSWidth(self.host.frame)), MAX(page.height, NSHeight(self.host.frame)));
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        context.allowsImplicitAnimation = NO;
        BOOL flipped = self.clip.isFlipped;
        self.host.frame = (NSRect){{0, flipped ? bar : NSHeight(self.clip.bounds) - bar - page.height}, page};
        DPPeekPlaceToolbar(self);
        // The hints rebuild once a grow or pane slide settles; redoing all three every frame costs more than the motion.
        if (!self.paneMoves && (self.grown <= 0 || self.grown >= 1)) DPPeekLayoutHints(self.controls, NSWidth(self.bounds) - NSMaxX(self.controls.frame) - 8);
    }];
}

- (void)followPane {
    NSView *root = self.superview;
    if (self.hidden || !root || !self.window) return;
    NSView *pane = self.pane;
    if (pane.window != self.window || pane.isHiddenOrHasHiddenAncestor) {
        NSView *fresh = DPPeekPane(self.window, [self.window convertRectToScreen:[root convertRect:self.frame toView:nil]]);
        if (fresh && fresh != pane) {
            NSView *holder = DPPeekHolder(self.window, fresh);
            if (holder && holder != root) {
                self.reparenting = YES;
                [holder addSubview:self positioned:NSWindowAbove relativeTo:nil];
                self.reparenting = NO;
                root = holder;
            }
            DPPeekWatchPane(self, fresh);
            pane = fresh;
        }
    }
    NSRect frame = pane && pane.window == self.window && !pane.isHiddenOrHasHiddenAncestor
        ? NSIntersectionRect([root convertRect:pane.bounds fromView:pane], root.bounds)
        : root.bounds;
    if (NSIsEmptyRect(frame)) frame = root.bounds;
    if (NSEqualRects(frame, self.frame)) return;
    NSAnimationContext *dia = NSAnimationContext.currentContext;
    if (!dia.timingFunction) return (void)(self.frame = frame);
    self.paneMoves++;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = dia.duration;
        context.timingFunction = dia.timingFunction;
        context.allowsImplicitAnimation = YES;
        self.animator.frame = frame;
        [self layoutSubtreeIfNeeded];
    } completionHandler:^{
        if (!--self.paneMoves) self.needsLayout = YES;
    }];
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (!hit || hit == self.clip || [hit isDescendantOf:self.clip] || hit == self.controls || [hit isDescendantOf:self.controls]) return hit;
    return DPPeekAllowsPaneClick(self, point) ? nil : hit;
}

- (void)setHidden:(BOOL)hidden {
    BOOL was = self.isHidden;
    [super setHidden:hidden];
    if (was != hidden) DPPeekChatVisibilityDidChange(self);
}

- (void)mouseDown:(NSEvent *)event { [self close:DPPeekClose]; }
- (void)rightMouseDown:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {}
- (void)control:(NSButton *)sender { [self close:sender.tag]; }

- (BOOL)stopWatching {
    if (self.closing) return NO;
    self.closing = YES;
    DPPeekChatDetach(self);
    if (self.monitor) [NSEvent removeMonitor:self.monitor];
    DPPeekUnwatchPane(self.paneObserver);
    self.monitor = self.paneObserver = nil;
    self.controls.alphaValue = 0;
    DPPeekHideTabBadge(self);
    DPPeekHideFind(self);
    return YES;
}

- (void)close:(DPPeekExit)exit {
    if (![self stopWatching]) return;
    if (self.isHiddenOrHasHiddenAncestor) [self finish:exit];
    else if (exit == DPPeekClose) [self animateOut:^{ [self finish:exit]; }];
    else if (exit == DPPeekTab) [self animateExpand:^{ [self finish:exit]; }];
    else [self finish:exit];
}

- (void)dealloc {
    DPPeekChatDetachBridge(_chatBridge);
    _chatBridge = nil;
    if (_monitor) [NSEvent removeMonitor:_monitor];
    DPPeekUnwatchPane(_paneObserver);
    [self stopMotion];
}

- (void)handOverTo:(NSView *)destination attach:(void (^)(void))attach {
    NSWindow *window = self.window ?: self.originWindow;
    [self stopMotion];
    [self stopWatching];
    [DPPeekCards removeObject:self];
    BOOL promoting = destination && self.grown >= 1 && !self.isHiddenOrHasHiddenAncestor;
    if (promoting) {
        // Keep the expanded card in place until its page is attached to the tab.
        [CATransaction begin];
        id<DPPeekPage> page = self.page;
        self.page = nil;  // Ignore nested attachment while the closing card is still mounted.
        [page detachFromPaneHostView:self.host];
        if (attach) attach();
    }
    [self removeFromSuperview];
    DPPeekUpdateSyncTimer();
    [window resetCursorRects];
    if (promoting) {
        [CATransaction commit];
        DPPeekCompleteHandoff(self, destination);
        return;
    }
    // The card must be off screen before the page detaches, or it flashes blank.
    if (!self.hidden && self.grown < 1) [CATransaction flush];
    id<DPPeekPage> page = self.page;
    self.page = nil;
    [page detachFromPaneHostView:self.host];
    if (attach) attach();
    DPPeekCompleteHandoff(self, nil);
}

@end

BOOL DPPeekHasCards(void) { return DPPeekCards.count > 0; }

DPPeekCard *DPPeekCardIn(NSWindow *window) {
    if (!window) return nil;
    for (DPPeekCard *peek in DPPeekCards)
        if (peek.window == window && !peek.closing && !peek.isHiddenOrHasHiddenAncestor) return peek;
    return nil;
}

id DPPeekPageIn(NSWindow *window) { return DPPeekCardIn(window).page; }

NSArray<DPPeekCard *> *DPPeekAllCards(NSWindow *window) {
    NSMutableArray<DPPeekCard *> *cards = [NSMutableArray array];
    for (DPPeekCard *peek in DPPeekCards) {
        NSWindow *owner = peek.window ?: peek.originWindow;
        if (!window || owner == window) [cards addObject:peek];
    }
    return cards;
}

NSArray<DPPeekCard *> *DPPeekHiddenCards(NSWindow *window) {
    NSMutableArray<DPPeekCard *> *cards = [NSMutableArray array];
    for (DPPeekCard *peek in DPPeekAllCards(window))
        if (!peek.closing && peek.isHiddenOrHasHiddenAncestor) [cards addObject:peek];
    return cards;
}

DPPeekCard *DPPeekCardForPage(id page) {
    if (!page) return nil;
    for (DPPeekCard *peek in DPPeekCards)
        if (peek.page == page) return peek;
    return nil;
}

DPPeekCard *DPPeekCardForOrigin(NSWindow *window, NSString *originTabID, id source) {
    if (!window || (!originTabID && !source)) return nil;
    for (DPPeekCard *peek in DPPeekAllCards(window)) {
        if (peek.closing) continue;
        if (originTabID && [peek.originTabID isEqual:originTabID]) return peek;
        if (!originTabID && source && peek.source == source) return peek;
    }
    return nil;
}

@interface DPPeekBacking : NSView
@end

@implementation DPPeekBacking
- (BOOL)wantsUpdateLayer { return YES; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self updateLayer]; }
- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor; }];
}
@end

static NSView *DPLayerView(Class kind) {
    NSView *view = [kind new];
    view.wantsLayer = YES;
    return view;
}

NSView *DPPeekWarmHost(NSWindow *window, id<DPPeekPage> page) {
    NSView *host = [page createPaneHostView], *pane = DPPeekPane(window, (NSRect){NSEvent.mouseLocation, {1, 1}});
    if (!host || !pane) return nil;
    NSView *holder = DPPeekHolder(window, pane);
    NSRect area = [holder convertRect:pane.bounds fromView:pane];
    host.frame = NSOffsetRect(DPPeekCardRect((NSRect){NSZeroPoint, area.size}), NSMinX(area), NSMinY(area));
    [holder addSubview:host positioned:NSWindowBelow relativeTo:nil];
    [page attachToPaneHostView:host];
    return host;
}

DPPeekCard *DPPeekShowCard(NSWindow *window, id<DPPeekPage> page, NSView *warmHost, NSRect screenLink) {
    NSView *host = warmHost ?: [page createPaneHostView], *pane = DPPeekPane(window, screenLink);
    if (!window || !host || DPPeekCardIn(window)) return nil;
    NSView *holder = DPPeekHolder(window, pane);
    DPPeekCard *peek = [[DPPeekCard alloc] initWithFrame:pane ? [holder convertRect:pane.bounds fromView:pane] : holder.bounds];
    peek.autoresizingMask = pane ? NSViewNotSizable : NSViewWidthSizable | NSViewHeightSizable;
    peek.originWindow = window;
    peek.pane = pane;
    peek.page = page;
    peek.host = host;
    peek.dim = DPLayerView(NSView.class);
    peek.dim.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:DPPeekDarkness()].CGColor;
    peek.card = DPLayerView(NSView.class);
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
    shadow.shadowBlurRadius = 24;
    shadow.shadowOffset = NSMakeSize(0, -6);
    peek.shade = DPLayerView(DPPeekBacking.class);
    peek.shade.shadow = shadow;
    peek.clip = DPLayerView(DPPeekBacking.class);
    peek.clip.layer.masksToBounds = YES;
    for (NSView *view in @[peek.shade, peek.clip]) {
        view.layer.cornerRadius = 10;
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
    peek.clip.layer.borderWidth = 1 / (window.backingScaleFactor ?: 2);
    peek.controls = DPPeekControls(peek, @selector(control:));
    [peek.clip addSubview:host];
    if (DPPeekShowsToolbar()) DPPeekAddToolbar(peek);
    [peek.card addSubview:peek.shade];
    [peek.card addSubview:peek.clip];
    for (NSView *view in @[peek.dim, peek.card, peek.controls]) [peek addSubview:view];
    [holder addSubview:peek positioned:NSWindowAbove relativeTo:nil];
    [peek layoutSubtreeIfNeeded];
    if (!warmHost) [page attachToPaneHostView:host];
    [window resetCursorRects];
    [window makeFirstResponder:host];
    DPPeekWatchPane(peek, pane);
    DPPeekUpdateSyncTimer();
    peek.monitor = DPPeekWatchKeys(peek);
    peek.link = [peek convertRect:[window convertRectFromScreen:screenLink] fromView:nil];
    [peek animateIn];
    return peek;
}

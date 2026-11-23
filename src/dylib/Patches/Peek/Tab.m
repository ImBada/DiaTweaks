#import "Patches/Peek/Peek.h"

static id DPTabState(NSView *tab) {
    return DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue");
}

// selectionStyle is nil on an unselected pinned tab, "none" on other unselected tabs, above/below beside the selection.
static BOOL DPTabSelected(NSView *tab) {
    NSString *style = [[DPSwiftValue(DPTabState(tab), @"selectionStyle") description] lowercaseString];
    return style && ![style isEqualToString:@"nil"] && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"];
}

static NSView *DPFindTabIn(NSWindow *window, BOOL (^match)(NSView *tab)) {
    const char *kinds[2] = {DPDiaTabView, DPDiaPinnedTab};
    for (int i = 0; i < 2; i++)
        for (NSView *tab in DPFindViews(kinds[i]))
            if (tab.window == window && !tab.isHiddenOrHasHiddenAncestor && match(tab)) return tab;
    return nil;
}

static NSString *DPPeekPageID(id page) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = @[@"identifier", @"id", @"contentID", @"contentId", @"uuid"]; });
    for (NSString *key in keys) {
        NSString *value = [DPSwiftValue((NSObject *)page, key) description];
        if (value.length >= 32 && [value containsString:@"-"]) return value;
    }
    return nil;
}

static NSView *DPPeekOriginTab(NSWindow *window, id source) {
    NSString *sourceID = DPPeekPageID(source);
    __block NSView *selected = nil;
    NSView *exact = DPFindTabIn(window, ^BOOL(NSView *tab) {
        if (sourceID && [[DPTabState(tab) description] containsString:sourceID]) return YES;
        if (!selected && DPTabSelected(tab)) selected = tab;
        return NO;
    });
    return exact ?: selected;
}

// Icon tiles' links already open new tabs; a pinned row's don't, and only its context menu says it is pinned.
BOOL DPPeekInPinnedRow(NSWindow *window, id page) {
    NSView *tab = DPPeekOriginTab(window, page);
    NSMenuItem *unpin = tab && !DPIsKind(tab, DPDiaPinnedTab) ? [DPTabContextMenu(tab) itemWithTitle:@"Unpin"] : nil;
    return unpin && !unpin.hidden && unpin.enabled;
}

static NSString *DPPeekTabContentKey(NSView *tab) {
    NSString *state = [DPTabState(tab) description];
    NSRange mark = [state rangeOfString:@"contentIDs: ["];
    if (mark.location == NSNotFound || state.length < NSMaxRange(mark) + 36) return nil;
    NSString *key = [state substringWithRange:NSMakeRange(NSMaxRange(mark), 36)];
    return [key containsString:@"-"] ? key : nil;
}

static NSView *DPPeekTabWithContent(NSWindow *window, NSString *key) {
    return DPFindTabIn(window, ^BOOL(NSView *tab) { return [[DPTabState(tab) description] containsString:key]; });
}

static BOOL DPTabIsTop(NSView *tab) {
    for (NSView *view = tab; view; view = view.superview)
        if ([NSStringFromClass(view.class) containsString:@"TabStrip"]) return YES;
    return NO;
}

@interface DPPeekTabBadge : NSView
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic, strong) NSTextField *eyes;
@property (nonatomic, copy) NSString *contentKey;
@property (nonatomic) BOOL pinned;
@property (nonatomic, strong) NSTrackingArea *tabTracking;
@property (nonatomic, weak) NSView *trackedTab;
@end

@implementation DPPeekTabBadge
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)clearTracking {
    if (self.tabTracking) [self.trackedTab removeTrackingArea:self.tabTracking];
    self.tabTracking = nil;
    self.trackedTab = nil;
}

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [self clearTracking];
    self.hidden = NO;
    if (!self.superview || self.pinned) return;
    self.tabTracking = [[NSTrackingArea alloc] initWithRect:self.superview.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self.superview addTrackingArea:self.tabTracking];
    self.trackedTab = self.superview;
}

- (void)dealloc { [self clearTracking]; }
- (void)mouseEntered:(NSEvent *)event { if (!self.pinned) self.hidden = YES; }
- (void)mouseExited:(NSEvent *)event { self.hidden = NO; }
@end

static void DPPeekPlaceBadge(DPPeekTabBadge *badge, NSView *tab) {
    if (!badge || !tab) return;
    BOOL pinned = DPIsKind(tab, DPDiaPinnedTab), top = DPTabIsTop(tab);
    badge.pinned = pinned;
    badge.eyes.font = [NSFont systemFontOfSize:pinned ? 11 : 12];
    [badge.eyes sizeToFit];
    CGFloat w = NSWidth(badge.eyes.frame), h = NSHeight(badge.eyes.frame);
    NSRect frame;
    NSAutoresizingMaskOptions resize;
    if (pinned) {
        frame = NSMakeRect(top ? NSMidX(tab.bounds) - w / 2 : NSMaxX(tab.bounds) - w - 2, tab.isFlipped ? 2 : NSMaxY(tab.bounds) - h - 2, w, h);
        resize = (top ? NSViewMinXMargin | NSViewMaxXMargin : NSViewMinXMargin) | (tab.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
    } else {
        frame = NSMakeRect(NSMaxX(tab.bounds) - w - 6, NSMidY(tab.bounds) - h / 2, w, h);
        resize = NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    }
    badge.frame = frame;
    badge.autoresizingMask = resize;
    badge.eyes.frame = NSOffsetRect(badge.bounds, 0, !pinned && top ? 2 : 0);
    badge.hidden = NO;
    if (badge.superview != tab) [tab addSubview:badge];
}

void DPPeekShowTabBadge(DPPeekCard *peek, id source) {
    DPPeekTabBadge *badge = [DPPeekTabBadge new];
    badge.peek = peek;
    NSTextField *eyes = [NSTextField labelWithString:@"👀"];
    eyes.alignment = NSTextAlignmentCenter;
    eyes.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    badge.eyes = eyes;
    [badge addSubview:eyes];
    peek.tabBadge = badge;
    NSView *tab = DPPeekOriginTab(peek.window ?: peek.originWindow, source);
    if (tab) {
        badge.contentKey = DPPeekTabContentKey(tab);
        DPPeekPlaceBadge(badge, tab);
    }
}

void DPPeekRefreshTabBadge(DPPeekCard *peek) {
    DPPeekTabBadge *badge = (DPPeekTabBadge *)peek.tabBadge;
    if (!badge || peek.closing) return;
    NSWindow *window = peek.window ?: peek.originWindow;
    if (!window) return;
    if (badge.contentKey) {
        NSView *current = badge.superview;
        if (current.window == window && [[DPTabState(current) description] containsString:badge.contentKey]) return;
        NSView *tab = DPPeekTabWithContent(window, badge.contentKey);
        if (tab) DPPeekPlaceBadge(badge, tab);
        else [badge removeFromSuperview];
        return;
    }
    if (badge.superview.window == window || peek.hidden) return;
    NSView *tab = DPPeekOriginTab(window, peek.source);
    if (!tab) return;
    badge.contentKey = DPPeekTabContentKey(tab);
    DPPeekPlaceBadge(badge, tab);
}

BOOL DPPeekTabBadgeSelected(DPPeekCard *peek, BOOL *known) {
    DPPeekTabBadge *badge = (DPPeekTabBadge *)peek.tabBadge;
    NSWindow *window = peek.window ?: peek.originWindow;
    NSView *tab = nil;
    if (badge.contentKey) tab = DPPeekTabWithContent(window, badge.contentKey);
    else if (badge.superview.window == window) tab = badge.superview;
    BOOL readable = tab && DPTabState(tab) != nil;
    if (known) *known = readable;
    return readable && DPTabSelected(tab);
}

void DPPeekHideTabBadge(DPPeekCard *peek) {
    DPPeekTabBadge *badge = (DPPeekTabBadge *)peek.tabBadge;
    [badge clearTracking];
    [badge removeFromSuperview];
    peek.tabBadge = nil;
}

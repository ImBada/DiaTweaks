#import "Peek.h"
#import "Patches/LittleDia/LittleDia.h"
#import <objc/message.h>

const CGFloat DPPeekToolbarHeight = 38;
static const CGFloat DPInset = 6, DPGap = 2, DPButton = 28, DPAddressHeight = 30;

@interface DPPeekToolbar : NSView
@property (nonatomic, weak) id page;
@property (nonatomic, strong) NSView *row, *divider, *address, *glow;
@property (nonatomic, strong) NSArray<NSButton *> *buttons;
@property (nonatomic, strong) NSTimer *watch;
@property (nonatomic, strong) id clicks;
@end

@implementation DPPeekToolbar
- (BOOL)wantsUpdateLayer { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event {}  // Swallows the click; the card's mouseDown would close it.

- (instancetype)initWithPage:(id)page {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.page = page;
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    self.row = [NSView new];
    __weak DPPeekToolbar *weak = self;
    self.buttons = @[
        DPMakeBarButton(@"chevron.left", @"Back", nil, ^{ DPPeekNavigate(weak.page, DPPeekBack); }),
        DPMakeBarButton(@"chevron.right", @"Forward", nil, ^{ DPPeekNavigate(weak.page, DPPeekForward); }),
        DPMakeBarButton(@"arrow.clockwise", @"Reload", nil, ^{ DPPeekNavigate(weak.page, DPPeekReload); }),
    ];
    self.address = DPPeekAddressFor(page);
    self.glow = DPPeekGlowFor(page);
    self.divider = DPMakeDivider();
    NSArray<NSView *> *parts = [(NSArray<NSView *> *)self.buttons arrayByAddingObjectsFromArray:@[self.address, self.glow, self.divider]];
    for (NSView *view in parts) [self.row addSubview:view];
    [self addSubview:self.row];
    [self refresh];
    return self;
}

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    }];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    self.needsLayout = YES;
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.arrowCursor]; }

- (void)layout {
    [super layout];
    CGFloat h = NSHeight(self.bounds), full = DPPeekToolbarHeight;
    self.row.frame = NSMakeRect(0, h - full, NSWidth(self.bounds), full);
    CGFloat mid = full / 2, x = DPInset;
    for (NSButton *button in self.buttons) {
        button.frame = NSMakeRect(x, round(mid - DPButton / 2), DPButton, DPButton);
        x += DPButton + DPGap;
    }
    x += DPInset - DPGap;
    self.address.frame = NSMakeRect(x, round(mid - DPAddressHeight / 2), MAX(0, NSWidth(self.row.bounds) - x - DPInset), DPAddressHeight);
    self.divider.frame = NSMakeRect(0, 0, NSWidth(self.row.bounds), 1 / MAX(1, self.window.backingScaleFactor));
    self.glow.frame = NSMakeRect(0, 0, NSWidth(self.row.bounds), MIN(full, 24));
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.watch invalidate];
    self.watch = nil;
    if (self.clicks) [NSEvent removeMonitor:self.clicks];
    self.clicks = nil;
    if (!self.window) return;
    __weak DPPeekToolbar *weak = self;
    self.watch = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        if (weak) [weak refresh]; else [timer invalidate];
    }];
    // Dia's toolbar under the card takes clicks by where they land, whatever is on top, so route them to this bar first.
    self.clicks = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
        DPPeekToolbar *bar = weak;
        NSView *clip = bar.superview;
        if (!bar || event.window != bar.window || bar.hiddenOrHasHiddenAncestor || bar.closing) return event;
        NSPoint inClip = [clip convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(inClip, clip.bounds) || !NSPointInRect(inClip, bar.frame)) return event;
        // Let overlays above Peek (floating chat, command bar, floating sidebar, Find bar) take clicks first.
        NSView *root = bar.window.contentView;
        NSPoint inRoot = root.superview ? [root.superview convertPoint:event.locationInWindow fromView:nil] : event.locationInWindow;
        NSView *top = [root hitTest:inRoot];
        if (root && top != bar && ![top isDescendantOf:bar]) return event;
        [[bar hitTest:inClip] ?: bar mouseDown:event];
        return nil;
    }];
}

- (BOOL)closing {
    for (NSView *view = self.superview; view; view = view.superview)
        if ([view isKindOfClass:DPPeekCard.class]) return ((DPPeekCard *)view).closing;
    return YES;
}

- (void)dealloc {
    [_watch invalidate];
    if (_clicks) [NSEvent removeMonitor:_clicks];
}

- (void)refresh {
    if (self.isHiddenOrHasHiddenAncestor) return;
    NSObject *page = self.page;
    if (!page) return;
    self.buttons[0].enabled = [DPValueForKey(page, @"canGoBack") boolValue];
    self.buttons[1].enabled = [DPValueForKey(page, @"canGoForward") boolValue];
    DPPeekRefreshAddress(self.address);
    DPMatchPage(self.row, page);
}
@end

NSView *DPPeekToolbarFor(id page) { return [[DPPeekToolbar alloc] initWithPage:page]; }
NSView *DPPeekToolbarAddress(NSView *toolbar) { return [toolbar isKindOfClass:DPPeekToolbar.class] ? ((DPPeekToolbar *)toolbar).address : nil; }

void DPPeekNavigate(id page, DPPeekStep step) {
    id navigation = DPValueForKey(page, @"navigationController");
    SEL action = step == DPPeekReload ? @selector(reload) : NULL;
    if (step == DPPeekBack && [DPValueForKey(page, @"canGoBack") boolValue]) action = @selector(goBack);
    if (step == DPPeekForward && [DPValueForKey(page, @"canGoForward") boolValue]) action = @selector(goForward);
    if (action && [navigation respondsToSelector:action]) ((void (*)(id, SEL))objc_msgSend)(navigation, action);
}

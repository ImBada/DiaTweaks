#import "Peek/Peek.h"
#import "StdPatch/Hook.m"

DPPatch DPPeek = { .on = YES };
static NSArray<DPPeekCard *> *allCards;
static NSPoint pointer;
DPPeekCard *DPPeekCardIn(NSWindow *window) {
    for (DPPeekCard *c in allCards)
        if (c.window == window && !c.closing && !c.isHiddenOrHasHiddenAncestor) return c;
    return nil;
}
@implementation DPPeekCard
- (NSRect)cardFrame { return self.bounds; }
- (void)close:(DPPeekExit)exit { [self removeFromSuperview]; }
- (void)handOverTo:(NSView *)destination attach:(void (^)(void))attach {
    [self removeFromSuperview];
    if (attach) attach();
}
- (void)setOriginVisible:(BOOL)visible { self.hidden = !visible; }
@end

@interface CursorWindow : NSWindow
@end
@implementation CursorWindow
- (NSPoint)mouseLocationOutsideOfEventStream { return pointer; }
@end

@interface RenderWidgetHostViewCocoa : NSView
@property BOOL allowed;
@property NSMutableArray<NSValue *> *rects;
@end
@implementation RenderWidgetHostViewCocoa
- (BOOL)shouldChangeCurrentCursor { return self.allowed; }
- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)cursor { [self.rects addObject:[NSValue valueWithRect:rect]]; }
@end

#import "Peek/Cursor.m"

static int hitTests;

@interface CountingCover : NSView
@end
@implementation CountingCover
- (NSView *)hitTest:(NSPoint)point {
    hitTests++;
    return [super hitTest:point];
}
@end

static RenderWidgetHostViewCocoa *Page(NSView *parent, NSRect frame) {
    RenderWidgetHostViewCocoa *page = [[RenderWidgetHostViewCocoa alloc] initWithFrame:frame];
    page.allowed = YES;
    page.rects = [NSMutableArray new];
    [parent addSubview:page];
    return page;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPPeekInstallCursor();
        NSWindow *window = [[CursorWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        RenderWidgetHostViewCocoa *under = Page(window.contentView, window.contentView.bounds);
        pointer = NSMakePoint(300, 300);
        NSCAssert(under.shouldChangeCurrentCursor, @"no Peek preserves Chromium's answer");
        DPPeekCard *card = [[DPPeekCard alloc] initWithFrame:NSMakeRect(100, 100, 600, 400)];
        allCards = @[ card ];
        [window.contentView addSubview:card];
        RenderWidgetHostViewCocoa *peek = Page(card, NSMakeRect(50, 50, 500, 300));
        NSCAssert(!under.shouldChangeCurrentCursor && peek.shouldChangeCurrentCursor, @"only the front page may set the cursor");
        peek.allowed = NO;
        NSCAssert(!peek.shouldChangeCurrentCursor, @"Chromium's inactive/menu/hidden-cursor checks still apply");
        peek.allowed = YES;
        pointer = NSMakePoint(120, 120);
        NSCAssert(!under.shouldChangeCurrentCursor && !peek.shouldChangeCurrentCursor, @"dimmed margins belong to neither page");
        NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(50, 250, 500, 100)];
        [card addSubview:toolbar];
        pointer = NSMakePoint(300, 400);
        NSCAssert(!peek.shouldChangeCurrentCursor, @"toolbar above Peek keeps its own cursor");
        pointer = NSMakePoint(50, 50);
        NSCAssert(under.shouldChangeCurrentCursor, @"uncovered panes retain cursor updates");
        CountingCover *sidebar = [[CountingCover alloc] initWithFrame:NSMakeRect(0, 0, 90, 600)];
        [window.contentView addSubview:sidebar];
        hitTests = 0;
        for (int i = 0; i < 20; i++) NSCAssert(under.shouldChangeCurrentCursor, @"outside the card the page keeps Chromium's answer");
        NSCAssert(hitTests == 0, @"a pointer outside the card skips the window-wide hit test, got %d", hitTests);
        pointer = NSMakePoint(300, 300);
        NSCAssert(!under.shouldChangeCurrentCursor && peek.shouldChangeCurrentCursor && hitTests > 0, @"inside the card the front page still decides");
        [sidebar removeFromSuperview];
        pointer = NSMakePoint(50, 50);
        [under addCursorRect:under.bounds cursor:NSCursor.IBeamCursor];
        CGFloat area = 0;
        for (NSValue *value in under.rects) {
            NSRect rect = value.rectValue;
            NSCAssert(NSIsEmptyRect(NSIntersectionRect(rect, card.frame)), @"background cursor rectangles never cover Peek");
            area += NSWidth(rect) * NSHeight(rect);
        }
        NSCAssert(area == 800 * 600 - 600 * 400, @"all uncovered cursor area is preserved");
        [peek addCursorRect:peek.bounds cursor:NSCursor.pointingHandCursor];
        NSCAssert(peek.rects.count == 1 && NSEqualRects(peek.rects[0].rectValue, peek.bounds), @"Peek keeps its renderer cursor rectangles");

        card.hidden = YES;
        [under.rects removeAllObjects];
        [peek.rects removeAllObjects];
        pointer = NSMakePoint(300, 300);
        NSCAssert(under.shouldChangeCurrentCursor, @"tab B gets full cursor updates while tab A's Peek is hidden");
        NSCAssert(!peek.shouldChangeCurrentCursor, @"hidden Peek never steals cursor updates");
        [under addCursorRect:under.bounds cursor:NSCursor.IBeamCursor];
        NSCAssert(under.rects.count == 1 && NSEqualRects(under.rects[0].rectValue, under.bounds), @"tab B keeps full cursor rectangles while tab A's Peek is hidden");
        [peek addCursorRect:peek.bounds cursor:NSCursor.pointingHandCursor];
        NSCAssert(peek.rects.count == 0, @"hidden Peek registers zero cursor rectangles");

        DPPeekCard *card2 = [[DPPeekCard alloc] initWithFrame:NSMakeRect(100, 100, 600, 400)];
        [window.contentView addSubview:card2];
        RenderWidgetHostViewCocoa *peek2 = Page(card2, NSMakeRect(50, 50, 500, 300));
        allCards = @[ card, card2 ];
        [under.rects removeAllObjects];
        [peek.rects removeAllObjects];
        [peek2.rects removeAllObjects];
        pointer = NSMakePoint(300, 300);
        NSCAssert(!under.shouldChangeCurrentCursor && !peek.shouldChangeCurrentCursor && peek2.shouldChangeCurrentCursor,
                  @"only active Peek P2 may change cursor while P1 is hidden");
        [peek addCursorRect:peek.bounds cursor:NSCursor.pointingHandCursor];
        NSCAssert(peek.rects.count == 0, @"hidden P1 still registers zero cursor rects alongside active P2");
        [peek2 addCursorRect:peek2.bounds cursor:NSCursor.pointingHandCursor];
        NSCAssert(peek2.rects.count == 1 && NSEqualRects(peek2.rects[0].rectValue, peek2.bounds), @"active P2 keeps its cursor rects");
        [card2 removeFromSuperview];
        allCards = @[ card ];
        card.hidden = NO;

        [under.rects removeAllObjects];
        DPPeek.on = NO;
        pointer = NSMakePoint(300, 300);
        NSCAssert(under.shouldChangeCurrentCursor, @"with Peek off the page keeps Chromium's answer");
        [under addCursorRect:under.bounds cursor:NSCursor.IBeamCursor];
        NSCAssert(under.rects.count == 1 && NSEqualRects(under.rects[0].rectValue, under.bounds), @"with Peek off cursor rectangles pass through");
        DPPeek.on = YES;
        [under.rects removeAllObjects];
        [card removeFromSuperview];
        allCards = @[];
        NSCAssert(under.shouldChangeCurrentCursor, @"closing Peek restores immediate updates");
        [under addCursorRect:under.bounds cursor:NSCursor.IBeamCursor];
        NSCAssert(under.rects.count == 1 && NSEqualRects(under.rects[0].rectValue, under.bounds), @"closing Peek restores full cursor rectangles");
        puts("all Peek cursor checks passed");
    }
}

#import "Patches/Peek/Peek.h"
#import "Patches/LittleDia/LittleDia.h"
#import <objc/message.h>

static const void *DPPeekFindKey = &DPPeekFindKey;
static const CGFloat DPFindWidth = 260, DPFindHeight = 30, DPFindMargin = 8, DPFindButton = 24;

@interface DPPeekFind : NSView <NSSearchFieldDelegate>
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic, strong) NSSearchField *field;
@property (nonatomic, strong) NSTextField *count;
@property (nonatomic, strong) NSArray<NSButton *> *buttons;
@end

static void DPPeekStopFind(id page) {
    if ([page respondsToSelector:@selector(stopFind)]) [page performSelector:@selector(stopFind)];
}

@implementation DPPeekFind
- (BOOL)wantsUpdateLayer { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event {}  // Swallows the click; the card's mouseDown would close it.

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        self.layer.borderColor = NSColor.separatorColor.CGColor;
    }];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    self.layer.borderWidth = 1 / (self.window.backingScaleFactor ?: 2);
}

- (instancetype)initForPeek:(DPPeekCard *)peek {
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, DPFindWidth, DPFindHeight)])) return nil;
    self.peek = peek;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 8;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1 / (peek.window.backingScaleFactor ?: 2);
    self.field = [NSSearchField new];
    self.field.placeholderString = @"Find in page";
    self.field.delegate = self;
    self.count = [NSTextField labelWithString:@""];
    self.count.textColor = NSColor.secondaryLabelColor;
    self.count.alignment = NSTextAlignmentRight;
    __weak DPPeekFind *weak = self;
    self.buttons = @[
        DPMakeBarButton(@"chevron.up", @"Previous", nil, ^{ [weak step:NO]; }),
        DPMakeBarButton(@"chevron.down", @"Next", nil, ^{ [weak step:YES]; }),
        DPMakeBarButton(@"xmark", @"Close", nil, ^{ DPPeekHideFind(weak.peek); }),
    ];
    for (NSView *view in [@[self.field, self.count] arrayByAddingObjectsFromArray:self.buttons]) [self addSubview:view];
    return self;
}

- (void)layout {
    [super layout];
    CGFloat h = NSHeight(self.bounds), x = NSWidth(self.bounds) - 2;
    for (NSButton *button in self.buttons.reverseObjectEnumerator) {
        x -= DPFindButton;
        button.frame = NSMakeRect(x, round((h - DPFindButton) / 2), DPFindButton, DPFindButton);
    }
    self.count.frame = NSMakeRect(x - 44, round((h - 16) / 2), 42, 16);
    self.field.frame = NSMakeRect(4, round((h - 22) / 2), NSMinX(self.count.frame) - 6, 22);
}

- (void)step:(BOOL)forward {
    id page = self.peek.page;
    SEL find = @selector(find:forward:matchCase:findMatch:completion:);
    NSString *text = self.field.stringValue;
    if (!text.length) {
        self.count.stringValue = @"";
        return DPPeekStopFind(page);
    }
    if (![page respondsToSelector:find]) return;
    __weak DPPeekFind *weak = self;
    void (^done)(id) = ^(id result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger total = [DPValueForKey(result, @"numMatches") integerValue], at = [DPValueForKey(result, @"activeMatchOrdinal") integerValue];
            weak.count.stringValue = total ? [NSString stringWithFormat:@"%ld/%ld", (long)at, (long)total] : @"0";
        });
    };
    ((void (*)(id, SEL, NSString *, BOOL, BOOL, BOOL, id))objc_msgSend)(page, find, text, forward, NO, YES, done);
}

- (void)controlTextDidChange:(NSNotification *)note { [self step:YES]; }

- (BOOL)control:(NSControl *)control textView:(NSTextView *)view doCommandBySelector:(SEL)command {
    if (command == @selector(insertNewline:)) [self step:!(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift)];
    else if (command == @selector(cancelOperation:)) DPPeekHideFind(self.peek);
    else return NO;
    return YES;
}
@end

static DPPeekFind *DPPeekFindBar(DPPeekCard *peek) {
    DPPeekFind *bar = DPGet(peek, DPPeekFindKey);
    if (bar) return bar;
    bar = [[DPPeekFind alloc] initForPeek:peek];
    BOOL flipped = peek.clip.isFlipped;
    CGFloat top = DPPeekToolbarInset(peek) + DPFindMargin;
    bar.frame = NSMakeRect(NSWidth(peek.clip.bounds) - DPFindWidth - DPFindMargin, flipped ? top : NSHeight(peek.clip.bounds) - DPFindHeight - top, DPFindWidth, DPFindHeight);
    bar.autoresizingMask = NSViewMinXMargin | (flipped ? NSViewMaxYMargin : NSViewMinYMargin);
    [peek.clip addSubview:bar];
    DPSet(peek, DPPeekFindKey, bar);
    return bar;
}

static void DPPeekFindOpen(DPPeekCard *peek) {
    DPPeekFind *bar = DPPeekFindBar(peek);
    [peek.window makeFirstResponder:bar.field];
    [bar.field selectText:nil];
}

BOOL DPPeekHideFind(DPPeekCard *peek) {
    DPPeekFind *bar = DPGet(peek, DPPeekFindKey);
    if (!bar) return NO;
    DPSet(peek, DPPeekFindKey, nil);
    DPPeekStopFind(peek.page);
    NSResponder *focus = peek.window.firstResponder;
    BOOL inBar = [focus isKindOfClass:NSView.class] && [(NSView *)focus isDescendantOf:bar];
    [bar removeFromSuperview];
    if (inBar && !peek.closing && !peek.isHiddenOrHasHiddenAncestor) [peek.window makeFirstResponder:peek.host];
    return YES;
}

BOOL DPPeekFindShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods) {
    BOOL command = mods == NSEventModifierFlagCommand, shifted = mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift);
    if (command && DPEventIsKey(event, @"f")) DPPeekFindOpen(peek);
    else if ((command || shifted) && DPEventIsKey(event, @"g")) {
        DPPeekFind *bar = DPGet(peek, DPPeekFindKey);
        if (bar.field.stringValue.length) [bar step:command];
        else DPPeekFindOpen(peek);
    } else return NO;
    return YES;
}

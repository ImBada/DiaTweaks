#import "Settings.h"

NSToolbarItemIdentifier const DPSearchItemIdentifier = @"DiaPatchesSearch";

@interface DPPaneEntry : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSView *page;
@property (nonatomic, strong) NSScrollView *scroll;
@end

@implementation DPPaneEntry
@end

@implementation DPPaneView {
    NSScrollView *_contentScroll;
    NSMutableArray<DPPaneEntry *> *_stack;
}

- (instancetype)initWithTitle:(NSString *)title content:(NSView<DPPaneContent> *)content {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.wantsLayer = YES;
    _title = [title copy];
    _content = content;
    _stack = [NSMutableArray new];
    if ([content respondsToSelector:@selector(syncWithQuery:)]) {
        _searchItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:DPSearchItemIdentifier];
        _searchItem.searchField.delegate = self;
        [_searchItem.searchField.widthAnchor constraintEqualToConstant:218].active = YES;
    }
    __weak DPPaneView *weakSelf = self;
    content.open = ^(NSString *title, NSView *page) { [weakSelf pushPage:page title:title]; };
    _contentScroll = [self scrollFor:content];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(patchesDidChange:) name:DPPatchesDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _searchItem.searchField.delegate = nil;
}

- (NSScrollView *)scrollFor:(NSView *)content {
    DPFlippedView *document = [DPFlippedView new];
    NSScrollView *scroll = [NSScrollView new];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.automaticallyAdjustsContentInsets = NO;
    scroll.documentView = document;
    [document addSubview:content];
    [self addSubview:scroll];
    for (NSView *v in @[content, document, scroll]) v.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *fill = [content.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-48];
    fill.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor constant:52],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:20],
        [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-20],
        [content.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],
        [content.widthAnchor constraintLessThanOrEqualToConstant:560],
        fill,
    ]];
    return scroll;
}

- (void)pushPage:(NSView *)page title:(NSString *)title {
    DPPaneEntry *entry = [DPPaneEntry new];
    entry.title = title;
    entry.page = page;
    entry.scroll = [self scrollFor:page];
    if ([page respondsToSelector:@selector(setOpen:)]) {
        __weak DPPaneView *weakSelf = self;
        [(id)page setOpen:^(NSString *next, NSView *view) { [weakSelf pushPage:view title:next]; }];
    }
    _stack.lastObject.scroll.hidden = YES;
    _contentScroll.hidden = YES;
    [_stack addObject:entry];
    if (self.titleChanged) self.titleChanged(title, YES);
}

- (void)popToRoot {
    if (!_stack.count) return;
    for (DPPaneEntry *entry in _stack) [entry.scroll removeFromSuperview];
    [_stack removeAllObjects];
    _contentScroll.hidden = NO;
    if (self.titleChanged) self.titleChanged(self.title, NO);
}

- (BOOL)showsPage { return _stack.count > 0; }

- (void)goBack {
    if (!_stack.count) return;
    [_stack.lastObject.scroll removeFromSuperview];
    [_stack removeLastObject];
    DPPaneEntry *top = _stack.lastObject;
    if (top) {
        top.scroll.hidden = NO;
        if (self.titleChanged) self.titleChanged(top.title, YES);
        return;
    }
    _contentScroll.hidden = NO;
    if (self.titleChanged) self.titleChanged(self.title, NO);
}

- (void)reset {
    [self popToRoot];
    self.searchItem.searchField.stringValue = @"";
    [self search];
}

- (void)search {
    if (self.searchItem) [self.content syncWithQuery:self.searchItem.searchField.stringValue];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSString *query = self.searchItem.searchField.stringValue;
    if (query.length) [self popToRoot];
    if ([self.content respondsToSelector:@selector(filterWithQuery:)]) [self.content filterWithQuery:query];
    else [self search];
}

- (void)patchesDidChange:(NSNotification *)notification {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.allowsImplicitAnimation = YES;
        [self search];
        for (DPPaneEntry *entry in self->_stack)
            if ([entry.page respondsToSelector:@selector(sync)]) [(id)entry.page sync];
        [self layoutSubtreeIfNeeded];
    }];
}

- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor; }

// Unhandled events would reach Dia's pane underneath via the responder chain.
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}
- (void)rightMouseDown:(NSEvent *)event {}
- (void)rightMouseUp:(NSEvent *)event {}
- (void)otherMouseDown:(NSEvent *)event {}
- (void)otherMouseUp:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {}
- (NSMenu *)menuForEvent:(NSEvent *)event { return nil; }
@end

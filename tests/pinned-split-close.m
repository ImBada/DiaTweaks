#define DPFindViews DPRealFindViews
#import "StdPatch/Views.m"
#undef DPFindViews
#import "StdPatch/Hook.m"

static NSArray<NSView *> *visibleTabs;
static NSArray<NSView *> *visibleContents;
static NSArray<NSView *> *visibleTiles;
static NSString *activeTabID;

NSArray<NSView *> *DPFindViews(const char *name) {
    if (strcmp(name, DPDiaTabView) == 0) return visibleTabs ?: @[];
    if (strcmp(name, DPDiaTabContentView) == 0) return visibleContents ?: @[];
    if (strcmp(name, DPDiaPinnedTab) == 0) return visibleTiles ?: @[];
    return @[];
}

#import "Patches/PinnedSplitClose/PinnedSplitClose.m"

@interface _TtC5TabUI33TabWebContentAttributesController : NSObject {
@public
    BOOL isInFavoritesOrPinnedContainer;
}
@end
@implementation _TtC5TabUI33TabWebContentAttributesController
@end

@interface _TtC5TabUI20TabContentController : NSObject {
@public
    uint8_t tabID[16];
}
@end
@implementation _TtC5TabUI20TabContentController
@end

@interface _TtC5TabUI21TabDockItemController : NSObject {
@public
    uint8_t itemID[17];
    void *contentControllers;
    BOOL group;
}
@end
@implementation _TtC5TabUI21TabDockItemController
- (id)safeSwiftValueForKey:(NSString *)key {
    if (![key isEqualToString:@"itemID"]) return nil;
    return self->group ? @"group(11111111-2222-3333-4444-555555555555)" : @"tab(11111111-2222-3333-4444-555555555555)";
}
@end

static int closeClicks;

@interface DPTestMenuView : NSView {
@public
    BOOL noClose;
}
@end
@implementation DPTestMenuView
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    if (!noClose) {
        NSMenuItem *close = [NSMenuItem new];
        close.title = @"Close";
        close.target = self;
        close.action = @selector(dpClose:);
        [menu addItem:close];
    }
    NSMenuItem *unpin = [NSMenuItem new];
    unpin.title = @"Unpin";
    unpin.target = self;
    unpin.action = @selector(dpClose:);
    [menu addItem:unpin];
    return menu;
}
- (void)dpClose:(id)sender { closeClicks++; }
@end

@interface _TtC5TabUI14TabContentView : NSView {
@public
    id attributes;
    id controller;
    NSImageView *$__lazy_storage_$_standardIconView;
    NSImageView *$__lazy_storage_$_iconView;
    NSImageView *$__lazy_storage_$_iconContainerView;
    int layoutCalls;
}
@end
@implementation _TtC5TabUI14TabContentView
- (void)layout {
    [super layout];
    layoutCalls++;
}
@end

@interface _TtC5TabUI13TabController : NSObject {
@public
    uint8_t tabID[16];
}
@end
@implementation _TtC5TabUI13TabController
@end

@interface _TtC5TabUI7TabView : DPTestMenuView {
@public
    id controller;
}
@end
@implementation _TtC5TabUI7TabView
@end

@interface _TtC5TabUI15TabDockItemView : DPTestMenuView {
@public
    id controller;
}
@end
@implementation _TtC5TabUI15TabDockItemView
@end

@interface _TtC6Window24PlatformWindowController : NSWindowController {
@public
    int originalCalls;
}
- (void)closeFocusedContent:(id)sender;
@end
@implementation _TtC6Window24PlatformWindowController
- (void)closeFocusedContent:(id)sender { originalCalls++; }
@end

id DPViewModelDelegate(NSView *view) {
    if ([view isKindOfClass:_TtC5TabUI7TabView.class]) return ((_TtC5TabUI7TabView *)view)->controller;
    if ([view isKindOfClass:_TtC5TabUI15TabDockItemView.class]) return ((_TtC5TabUI15TabDockItemView *)view)->controller;
    if ([view isKindOfClass:_TtC5TabUI14TabContentView.class]) return ((_TtC5TabUI14TabContentView *)view)->controller;
    return nil;
}

NSView *DPEnclosingTab(NSView *view) {
    while (view && !DPIsKind(view, DPDiaTabView)) view = view.superview;
    return view;
}

id DPAttributes(NSView *content) {
    return [content isKindOfClass:_TtC5TabUI14TabContentView.class] ? ((_TtC5TabUI14TabContentView *)content)->attributes : nil;
}

void DPRelayoutTabContents(void) {
    for (NSView *content in visibleContents) content.needsLayout = YES;
}

NSString *DPActiveTabID(NSWindow *window) { return activeTabID; }

static void DPSetUUID(uint8_t *bytes, uint8_t seed) {
    for (int i = 0; i < 16; i++) bytes[i] = (uint8_t)(seed + i);
}

static NSString *DPUUIDText(uint8_t seed) {
    uint8_t bytes[16];
    DPSetUUID(bytes, seed);
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]];
}

static _TtC5TabUI14TabContentView *NewPane(_TtC5TabUI7TabView *tab, BOOL pinned, uint8_t seed) {
    _TtC5TabUI33TabWebContentAttributesController *attributes = [_TtC5TabUI33TabWebContentAttributesController new];
    attributes->isInFavoritesOrPinnedContainer = pinned;
    _TtC5TabUI20TabContentController *controller = [_TtC5TabUI20TabContentController new];
    DPSetUUID(controller->tabID, seed);
    _TtC5TabUI14TabContentView *pane = [[_TtC5TabUI14TabContentView alloc] initWithFrame:NSMakeRect(0, 0, 200, 16)];
    pane->attributes = attributes;
    pane->controller = controller;
    [tab addSubview:pane];
    return pane;
}

static _TtC5TabUI7TabView *NewRow(uint8_t seed) {
    _TtC5TabUI7TabView *tab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];
    _TtC5TabUI13TabController *controller = [_TtC5TabUI13TabController new];
    DPSetUUID(controller->tabID, seed);
    tab->controller = controller;
    return tab;
}

static void *DPFakeStorage(long count) {
    long *storage = calloc(4, sizeof(long));
    storage[2] = count;
    return storage;
}

static _TtC5TabUI15TabDockItemView *NewTile(uint8_t seed, long panes) {
    _TtC5TabUI21TabDockItemController *controller = [_TtC5TabUI21TabDockItemController new];
    DPSetUUID(controller->itemID, seed);
    controller->contentControllers = DPFakeStorage(panes);
    _TtC5TabUI15TabDockItemView *tile = [[_TtC5TabUI15TabDockItemView alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
    tile->controller = controller;
    return tile;
}

static NSWindow *gKeyWindow;
static NSWindow *DPApp_keyWindow(NSApplication *self, SEL _cmd) { return gKeyWindow; }

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPInstallPinnedSplitClose();

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.releasedWhenClosed = NO;
        _TtC6Window24PlatformWindowController *controller = [_TtC6Window24PlatformWindowController new];
        controller.window = window;

        _TtC5TabUI7TabView *pinnedSplit = NewRow(0x01);
        _TtC5TabUI14TabContentView *paneA = NewPane(pinnedSplit, YES, 0x10);
        _TtC5TabUI14TabContentView *paneB = NewPane(pinnedSplit, YES, 0x30);
        _TtC5TabUI7TabView *pinnedSingle = NewRow(0x02);
        _TtC5TabUI14TabContentView *paneC = NewPane(pinnedSingle, YES, 0x50);
        _TtC5TabUI7TabView *looseSplit = NewRow(0x03);
        _TtC5TabUI14TabContentView *paneD = NewPane(looseSplit, NO, 0x70);
        _TtC5TabUI14TabContentView *paneE = NewPane(looseSplit, NO, 0x90);
        [window.contentView addSubview:pinnedSplit];
        [window.contentView addSubview:pinnedSingle];
        [window.contentView addSubview:looseSplit];

        _TtC5TabUI15TabDockItemView *splitTile = NewTile(0xB0, 2);
        _TtC5TabUI15TabDockItemView *singleTile = NewTile(0xD0, 1);
        [window.contentView addSubview:splitTile];
        [window.contentView addSubview:singleTile];

        visibleTabs = @[ pinnedSplit, pinnedSingle, looseSplit ];
        visibleContents = @[ paneA, paneB, paneC, paneD, paneE ];
        visibleTiles = @[ splitTile, singleTile ];
        activeTabID = DPUUIDText(0x10);

        DPHookClass(NSApp.class, @selector(keyWindow), (IMP)DPApp_keyWindow);
        gKeyWindow = window;

        [controller closeFocusedContent:nil];
        CHECK(controller->originalCalls == 1 && closeClicks == 0, "off tweak leaves ⌘W alone");

        DPPinnedSplitClose.on = YES;
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 1 && controller->originalCalls == 1, "pinned split row unloads in place");

        activeTabID = DPUUIDText(0x50);
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 1 && controller->originalCalls == 2, "pinned single tab keeps ⌘W");

        activeTabID = DPUUIDText(0x70);
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 1 && controller->originalCalls == 3, "unpinned split keeps ⌘W");

        activeTabID = DPUUIDText(0xB0);
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 2 && controller->originalCalls == 3, "favorite split tile unloads in place");

        activeTabID = DPUUIDText(0xD0);
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 2 && controller->originalCalls == 4, "favorite single tile keeps ⌘W");

        _TtC5TabUI15TabDockItemView *groupTile = NewTile(0xB0, 3);
        ((_TtC5TabUI21TabDockItemController *)groupTile->controller)->group = YES;
        [window.contentView addSubview:groupTile];
        visibleTiles = @[ groupTile ];
        activeTabID = DPUUIDText(0xB0);
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 2 && controller->originalCalls == 5, "a folder tile keeps ⌘W");
        [groupTile removeFromSuperview];
        visibleTiles = @[ splitTile, singleTile ];

        visibleTiles = @[];
        activeTabID = nil;
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 3 && controller->originalCalls == 5, "one pinned split unloads without an active tab");
        activeTabID = DPUUIDText(0x10);

        _TtC5TabUI7TabView *secondSplit = NewRow(0x04);
        _TtC5TabUI14TabContentView *paneH = NewPane(secondSplit, YES, 0xE0);
        _TtC5TabUI14TabContentView *paneI = NewPane(secondSplit, YES, 0xF0);
        [window.contentView addSubview:secondSplit];
        visibleTabs = @[ pinnedSplit, secondSplit, pinnedSingle, looseSplit ];
        visibleContents = @[ paneA, paneB, paneH, paneI, paneC, paneD, paneE ];
        activeTabID = nil;
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 3 && controller->originalCalls == 6, "two pinned splits keep ⌘W without an active tab");
        [secondSplit removeFromSuperview];
        visibleTabs = @[ pinnedSplit, pinnedSingle, looseSplit ];
        visibleContents = @[ paneA, paneB, paneC, paneD, paneE ];
        visibleTiles = @[ splitTile, singleTile ];

        activeTabID = DPUUIDText(0x01);
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 6, "the split's own tab ID finds it");
        activeTabID = DPUUIDText(0x10);

        activeTabID = DPUUIDText(0x50);
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 7, "a pinned split behind another tab keeps ⌘W");
        activeTabID = DPUUIDText(0x10);

        Class card = objc_allocateClassPair(NSView.class, "DPPeekCard", 0);
        objc_registerClassPair(card);
        NSView *peek = [[card alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [window.contentView addSubview:peek];
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 8, "an open Peek card keeps ⌘W");
        [peek removeFromSuperview];

        NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        sheet.releasedWhenClosed = NO;
        [window beginSheet:sheet completionHandler:nil];
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 9, "an attached sheet keeps ⌘W");
        [window endSheet:sheet];
        [sheet close];

        Class overlay = objc_allocateClassPair(NSView.class, "DPCommandBarOverlay", 0);
        objc_registerClassPair(overlay);
        NSView *bar = [[overlay alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [window.contentView addSubview:bar];
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 10, "a Command Bar overlay keeps ⌘W");
        [bar removeFromSuperview];

        NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        other.releasedWhenClosed = NO;
        gKeyWindow = other;
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 11, "a key window elsewhere keeps ⌘W");
        gKeyWindow = window;
        [other close];

        [pinnedSplit removeFromSuperview];
        _TtC5TabUI7TabView *bareSplit = NewRow(0x05);
        bareSplit->noClose = YES;
        _TtC5TabUI14TabContentView *paneF = NewPane(bareSplit, YES, 0x10);
        _TtC5TabUI14TabContentView *paneG = NewPane(bareSplit, YES, 0x30);
        [window.contentView addSubview:bareSplit];
        visibleTabs = @[ bareSplit, pinnedSingle, looseSplit ];
        visibleContents = @[ paneF, paneG, paneC, paneD, paneE ];
        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 12, "a split with no Close item keeps ⌘W");
        [bareSplit removeFromSuperview];
        [window.contentView addSubview:pinnedSplit];
        visibleTabs = @[ pinnedSplit, pinnedSingle, looseSplit ];
        visibleContents = @[ paneA, paneB, paneC, paneD, paneE ];

        NSImageView *iconA = [NSImageView new];
        paneA->$__lazy_storage_$_standardIconView = iconA;
        NSImageView *iconD = [NSImageView new];
        paneD->$__lazy_storage_$_standardIconView = iconD;
        NSImage *favicon = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect rect) { return YES; }];
        iconD.image = favicon;
        [paneA layout];
        [paneB layout];
        [paneC layout];
        [paneD layout];
        CHECK(iconA.image != nil, "a pinned split pane gets a split icon");
        CHECK(iconD.image == favicon, "an unpinned split pane keeps its favicon");
        CHECK(DPVerifyPinnedSplitClose(&DPPinnedSplitClose) == nil, "verifies while on");

        iconA.hidden = YES;
        [paneA layout];
        CHECK(!iconA.hidden, "a hidden pinned split icon slot is shown");
        DPPinnedSplitClose.on = NO;
        DPApplyPinnedSplitClose(&DPPinnedSplitClose);
        CHECK(iconA.hidden, "turning off restores the hidden icon slot");
        DPPinnedSplitClose.on = YES;
        iconA.hidden = NO;
        [paneA layout];

        iconA.image = favicon;
        [paneA layout];
        CHECK(iconA.image == favicon, "Dia's own icon is left alone");

        iconA.image = nil;
        [paneA layout];
        CHECK(iconA.image != nil, "the split icon comes back on the next layout");
        DPPinnedSplitClose.on = NO;
        DPApplyPinnedSplitClose(&DPPinnedSplitClose);
        [paneA layout];
        [paneB layout];
        CHECK(iconA.image == nil, "turning off clears the split icon");
        CHECK(iconD.image == favicon, "turning off leaves a favicon alone");
        CHECK(DPVerifyPinnedSplitClose(&DPPinnedSplitClose) == nil, "verifies after off");

        [controller closeFocusedContent:nil];
        CHECK(closeClicks == 4 && controller->originalCalls == 13, "hooks stay inert after off");

        // Dia 1.58 keeps the icon in an icon container; 1.59 keeps it in an icon view.
        DPPinnedSplitClose.on = YES;
        NSImageView *containerIcon = [NSImageView new];
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
        [container addSubview:containerIcon];
        paneB->$__lazy_storage_$_standardIconView = nil;
        paneB->$__lazy_storage_$_iconContainerView = (NSImageView *)container;
        [paneB layout];
        CHECK(containerIcon.image != nil, "1.58 icon container gets the split icon");
        DPPinnedSplitClose.on = NO;
        DPApplyPinnedSplitClose(&DPPinnedSplitClose);
        CHECK(containerIcon.image == nil, "1.58 icon container restores");
        NSImageView *directIcon = [NSImageView new];
        paneB->$__lazy_storage_$_iconContainerView = nil;
        paneB->$__lazy_storage_$_iconView = directIcon;
        DPPinnedSplitClose.on = YES;
        [paneB layout];
        CHECK(directIcon.image != nil, "1.59 icon view gets the split icon");
        DPPinnedSplitClose.on = NO;
        DPApplyPinnedSplitClose(&DPPinnedSplitClose);
        CHECK(directIcon.image == nil, "1.59 icon view restores");

        paneB->$__lazy_storage_$_iconView = nil;
        DPPinnedSplitClose.on = YES;
        [paneB layout];
        CHECK(DPVerifyPinnedSplitClose(&DPPinnedSplitClose) == nil, "a pane with no icon view verifies");

        CHECK(objc_getClass(DPDiaWindowController) != Nil, "1.58/1.59 window controller");
        CHECK(objc_getClass(DPDiaTabView) != Nil && objc_getClass(DPDiaTabContentView) != Nil, "1.58/1.59 tab views");
        CHECK(objc_getClass(DPDiaPinnedTab) != Nil, "1.58/1.59 pinned tile");
        CHECK(DPIsHooked(objc_getClass(DPDiaWindowController), @selector(closeFocusedContent:), (IMP)DPWindowController_closeFocusedContent),
              "⌘W reaches the tweak");
        CHECK(DPIsHooked(objc_getClass(DPDiaTabContentView), @selector(layout), (IMP)DPContent_layout),
              "tab content layout reaches the tweak");

        [window close];
    }
    if (failures) return 1;
    puts("PASS: pinned-split-close");
    return 0;
}

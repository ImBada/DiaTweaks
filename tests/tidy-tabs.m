#import "Patches/TidyTabs/TidyTabs.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/CommandBarOverlay.h"
#import "StdPatch/Hook.m"
#import "StdPatch/Views.m"

static int hookCalls;
static void DPCountedHookClass(Class cls, SEL sel, IMP replacement) {
    hookCalls++;
    DPHookClass(cls, sel, replacement);
}
#define DPHookClass DPCountedHookClass

DPPatch DPTidyTabs;
static BOOL tidyBusy;

@implementation DPTidyHover
+ (DPTidyHover *)forList:(NSView *)list { return nil; }
+ (DPTidyHover *)attachToList:(NSView *)list {
    DPTidyHover *hover = [DPTidyHover new];
    hover.progress = 1;
    return hover;
}
- (void)detach {}
- (void)track {}
@end
@implementation DPTidyBrush
- (void)showBusy {}
@end
@implementation DPTidyRowView
@end
DPTidyRowView *DPTidyRowIn(NSView *list, BOOL create) { return nil; }
NSHashTable<DPTidyBrush *> *DPTidyBrushes(void) { return [NSHashTable weakObjectsHashTable]; }
BOOL DPTidyIsBusy(void) { return tidyBusy; }
void DPTidyWave(CALayer *host, CALayer *line, CGColorRef color, BOOL busy) {}

DPPatch DPCommandBar;
char DPOverlayKey;
@implementation DPCommandBarOverlay
- (NSView *)viewUnder:(NSPoint)point { return nil; }
@end
static NSMutableSet<NSString *> *splitTabs;
NSMutableSet<NSString *> *DPSplits(NSWindow *window) { return splitTabs ?: (splitTabs = [NSMutableSet set]); }

static id worldBrowser, worldDelegate;
static NSMutableArray *worldContents;
static void (*worldMove)(NSNumber *session, NSInteger index);
static long long (*worldActiveSession)(void);
id DPBrowserOfWindow(NSWindow *w) { return worldBrowser; }
id DPGroupingDelegate(id browser) { return worldDelegate; }
NSArray *DPTrackedContents(id browser) { return worldContents ?: @[]; }
long long DPSessionOf(id contents) { return [[contents valueForKey:@"sessionId"] longLongValue]; }
long long DPActiveSession(id browser) { return worldActiveSession ? worldActiveSession() : 0; }
void DPMoveTab(id delegate, id browser, NSNumber *session, NSInteger index, void (^done)(void), void (^failed)(void)) {
    if (worldMove) worldMove(session, index);
    if (done) dispatch_async(dispatch_get_main_queue(), done);
}
void DPOnLaunch(void (^block)(void)) { if (block) block(); }

#import "Patches/TidyTabs/Layout.m"
#import "Patches/TidyTabs/Separator.m"
#import "Patches/NewTabNextToCurrent/NewTabNextToCurrent.m"

@interface DPFakeTab : NSObject
@property NSString *URL, *title;
@property (getter=isPinned) BOOL pinned;
@end
@implementation DPFakeTab
@end

@interface DPFakeScriptWindow : NSObject
@property NSString *windowId;
@property NSArray *appleScriptTabs;
@end
@implementation DPFakeScriptWindow
@end

@interface DPFakeDelegate : NSObject <NSApplicationDelegate>
@property NSArray *appleScriptWindows;
@end
@implementation DPFakeDelegate
@end

static int failures;

static void expectEqual(id got, id want, NSString *what) {
    if ([got isEqual:want] || got == want) return;
    failures++;
    printf("FAIL %s: got %s, want %s\n", what.UTF8String, [[got description] UTF8String], [[want description] UTF8String]);
}

static DPFakeTab *tab(NSString *url, NSString *title, BOOL pinned) {
    DPFakeTab *tab = [DPFakeTab new];
    tab.URL = url;
    tab.title = title;
    tab.pinned = pinned;
    return tab;
}

static DPFakeScriptWindow *scripted(NSString *windowID, NSArray *tabs) {
    DPFakeScriptWindow *window = [DPFakeScriptWindow new];
    window.windowId = windowID;
    window.appleScriptTabs = tabs;
    return window;
}

static NSWindow *window(NSString *identifier) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.identifier = identifier;
    window.releasedWhenClosed = NO;
    return window;
}


static char DPFakeDiaKey, DPFakeScrollKey;
static NSInteger frameWrites, lineWrites, lookups;

@interface DPCountingScroll : NSScrollView
@end
@implementation DPCountingScroll
- (void)setFrame:(NSRect)frame {
    if (!NSEqualRects(frame, [objc_getAssociatedObject(self, &DPFakeDiaKey) rectValue])) frameWrites++;
    [super setFrame:frame];
}
@end

@interface DPCountingLayer : CALayer
@end
@implementation DPCountingLayer
- (void)setFrame:(CGRect)frame {
    if (!NSEqualRects(frame, [objc_getAssociatedObject(self, &DPFakeDiaKey) rectValue])) lineWrites++;
    [super setFrame:frame];
}
@end

@interface DPFakeLayout : NSCollectionViewLayout
@property NSArray<NSArray<NSValue *> *> *frames;
@property NSSet<NSString *> *hidden;
@end
@implementation DPFakeLayout
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    NSCollectionViewLayoutAttributes *attrs = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:path];
    attrs.frame = self.frames[(NSUInteger)path.section][(NSUInteger)path.item].rectValue;
    attrs.hidden = [self.hidden containsObject:[NSString stringWithFormat:@"%ld.%ld", (long)path.section, (long)path.item]];
    return attrs;
}
@end

@interface DPFakeCollection : NSCollectionView
@property (strong) DPFakeLayout *fakeLayout;
@property NSArray<NSArray<NSNumber *> *> *kinds;
@end
@implementation DPFakeCollection
- (NSCollectionViewLayout *)collectionViewLayout { return self.fakeLayout; }
- (NSInteger)numberOfSections { return (NSInteger)self.kinds.count; }
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return (NSInteger)self.kinds[(NSUInteger)section].count; }
- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)path {
    lookups++;
    NSInteger kind = self.kinds[(NSUInteger)path.section][(NSUInteger)path.item].integerValue;
    if (!kind) return nil;
    NSCollectionViewItem *item = [NSCollectionViewItem new];
    item.view = [kind == 1 ? objc_getClass("_TtC5TabUI7TabView") : objc_getClass(DPDiaTabGroupCell) new];
    return item;
}
@end

static void restoreScroll(NSView *self, SEL _cmd) {
    NSScrollView *scroll = objc_getAssociatedObject(self, &DPFakeScrollKey);
    NSValue *dia = objc_getAssociatedObject(scroll, &DPFakeDiaKey);
    if (dia) [scroll setFrame:dia.rectValue];
}

static void restoreLine(NSView *self, SEL _cmd) {
    for (CALayer *layer in self.layer.sublayers) {
        NSValue *dia = objc_getAssociatedObject(layer, &DPFakeDiaKey);
        if (dia) layer.frame = dia.rectValue;
    }
}

static Class makeClass(const char *name, Class parent, SEL sel, IMP imp) {
    Class cls = objc_allocateClassPair(parent, name, 0);
    if (imp) class_addMethod(cls, sel, imp, "v@:");
    objc_registerClassPair(cls);
    return cls;
}

typedef struct { NSRect frame; int kind; } DPCase;

static NSInteger referenceBelowLine(DPFakeCollection *collection, CGFloat line) {
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    NSMutableArray<NSNumber *> *isTab = [NSMutableArray array];
    NSCountedSet<NSNumber *> *heights = [NSCountedSet set];
    for (NSInteger section = 0; section < collection.numberOfSections; section++)
        for (NSInteger item = 0; item < [collection numberOfItemsInSection:section]; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
            NSCollectionViewLayoutAttributes *attrs = [collection.collectionViewLayout layoutAttributesForItemAtIndexPath:path];
            NSRect frame = attrs.frame;
            if (attrs.hidden || attrs.alpha < 1 || NSMinY(frame) < line || NSHeight(frame) <= 0) continue;
            NSView *cell = [collection itemAtIndexPath:path].view;
            BOOL tab = cell && strstr(object_getClassName(cell), "TabUI7TabView");
            if (!cell && section == collection.numberOfSections - 1 && item == [collection numberOfItemsInSection:section] - 1) continue;
            [frames addObject:[NSValue valueWithRect:frame]];
            [isTab addObject:cell ? @(tab) : (id)NSNull.null];
            if (tab) [heights addObject:@(round(NSHeight(frame)))];
        }
    NSNumber *height = nil;
    for (NSNumber *each in heights) if (!height || [heights countForObject:each] > [heights countForObject:height]) height = each;
    if (!height) return 0;
    NSInteger loose = 0;
    for (NSUInteger i = 0; i < frames.count; i++) {
        NSRect frame = frames[i].rectValue;
        if (isTab[i] == (id)NSNull.null ? fabs(NSHeight(frame) - height.doubleValue) > 1 : !isTab[i].boolValue) continue;
        BOOL inside = NO;
        for (NSValue *other in frames)
            inside |= NSHeight(other.rectValue) > NSHeight(frame) + 1 && NSPointInRect(NSMakePoint(NSMidX(frame), NSMidY(frame)), other.rectValue);
        loose += !inside;
    }
    return loose;
}

static uint32_t seed = 12345;
static uint32_t roll(uint32_t n) { seed = seed * 1664525u + 1013904223u; return (seed >> 8) % n; }

static void fill(DPFakeCollection *collection, NSUInteger rows, BOOL withFolders) {
    NSMutableArray *frames = [NSMutableArray array], *kinds = [NSMutableArray array];
    NSMutableSet *hidden = [NSMutableSet set];
    CGFloat y = 0;
    NSUInteger sections = 1 + roll(3);
    for (NSUInteger section = 0; section < sections; section++) {
        NSMutableArray *sectionFrames = [NSMutableArray array], *sectionKinds = [NSMutableArray array];
        for (NSUInteger row = 0; row < rows / sections; row++) {
            if (withFolders && roll(8) == 0) {
                NSUInteger children = 1 + roll(4);
                [sectionFrames addObject:[NSValue valueWithRect:NSMakeRect(0, y, 200, 24 * (children + 1))]];
                [sectionKinds addObject:@2];
                for (NSUInteger child = 0; child < children; child++) {
                    [sectionFrames addObject:[NSValue valueWithRect:NSMakeRect(8, y + 24 * (child + 1), 184, 24)]];
                    [sectionKinds addObject:roll(5) ? @1 : @0];
                }
                y += 24 * (children + 1);
                continue;
            }
            if (roll(25) == 0) [hidden addObject:[NSString stringWithFormat:@"%lu.%lu", (unsigned long)section, (unsigned long)sectionFrames.count]];
            [sectionFrames addObject:[NSValue valueWithRect:NSMakeRect(0, y, 200, roll(30) == 0 ? 36 : 24)]];
            [sectionKinds addObject:roll(6) ? @1 : roll(2) ? @0 : @2];
            y += 24;
        }
        [frames addObject:sectionFrames];
        [kinds addObject:sectionKinds];
    }
    DPFakeLayout *layout = [DPFakeLayout new];
    layout.frames = frames;
    layout.hidden = hidden;
    collection.fakeLayout = layout;
    collection.kinds = kinds;
}

static NSView *makeList(DPFakeCollection *collection, NSView **separatorOut) {
    NSView *list = [[objc_getClass(DPDiaTabList) alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    NSScrollView *scroll = [[DPCountingScroll alloc] initWithFrame:list.bounds];
    scroll.documentView = collection;
    [list addSubview:scroll];
    objc_setAssociatedObject(list, &DPFakeScrollKey, scroll, OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(scroll, &DPFakeDiaKey, [NSValue valueWithRect:scroll.frame], OBJC_ASSOCIATION_RETAIN);
    if (separatorOut) {
        NSView *separator = [[objc_getClass(DPDiaTabListSeparator) alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        [collection addSubview:separator];
        *separatorOut = separator;
    }
    return list;
}

static void checkTidyLayout(void) {
    DPTidyTabs.on = YES;
    Class collectionClass = makeClass(DPDiaTabListCollection, DPFakeCollection.class, 0, NULL);
    makeClass(DPDiaTabList, NSView.class, @selector(layout), (IMP)restoreScroll);
    makeClass(DPDiaTabListSeparator, NSView.class, @selector(layout), (IMP)restoreLine);
    makeClass("_TtC5TabUI7TabView", NSView.class, 0, NULL);
    makeClass(DPDiaTabGroupCell, NSView.class, 0, NULL);
    DPInstallTidyLayout();

    DPFakeCollection *collection = [[collectionClass alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    fill(collection, 4, NO);
    NSView *list = makeList(collection, NULL);
    NSScrollView *scroll = DPTidyListScroll(list);
    for (int pass = 0; pass < 40; pass++) [list layout];
    expectEqual(@(frameWrites > 0 && frameWrites <= (NSInteger)DPAdjustLimit), @YES,
        [NSString stringWithFormat:@"a list Dia keeps resetting stops being resized after %lu tries a turn (wrote %ld times)", (unsigned long)DPAdjustLimit, (long)frameWrites]);
    expectEqual(@(NSHeight(scroll.frame) > 0), @YES, @"the scroll view is left with a frame");

    NSView *separator = nil;
    DPFakeCollection *barCollection = [[collectionClass alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    fill(barCollection, 4, NO);
    NSView *barList = makeList(barCollection, &separator);
    separator.wantsLayer = YES;
    NSButton *closeAll = [[NSButton alloc] initWithFrame:NSMakeRect(170, 2, 24, 20)];
    [separator addSubview:closeAll];
    DPCountingLayer *line = [DPCountingLayer layer];
    line.frame = CGRectMake(0, 12, 160, 1);
    objc_setAssociatedObject(line, &DPFakeDiaKey, [NSValue valueWithRect:line.frame], OBJC_ASSOCIATION_RETAIN);
    [separator.layer addSublayer:line];
    tidyBusy = YES;
    lineWrites = 0;
    hookCalls = 0;
    for (int pass = 0; pass < 40; pass++) [separator layout];
    expectEqual(@(lineWrites > 0 && lineWrites <= (NSInteger)DPAdjustLimit), @YES,
        [NSString stringWithFormat:@"a separator line Dia keeps resetting stops being trimmed after %lu tries a turn (wrote %ld times)", (unsigned long)DPAdjustLimit, (long)lineWrites]);
    expectEqual(@(hookCalls), @1, @"Close All's class is hooked once, not on every separator pass");
    (void)barList;
    tidyBusy = NO;
}

static void checkLooseCount(void) {
    Class collectionClass = objc_getClass(DPDiaTabListCollection);
    int mismatches = 0, cases = 0, exact = 0;
    for (int round = 0; round < 60; round++) {
        NSUInteger rows = (NSUInteger)(roll(2) ? 2 + roll(10) : 40 + roll(300));
        DPFakeCollection *collection = [[collectionClass alloc] initWithFrame:NSMakeRect(0, 0, 200, 8000)];
        fill(collection, rows, roll(3) != 0);
        NSView *separator = nil;
        NSView *list = makeList(collection, round % 2 ? &separator : NULL);
        separator.frame = NSMakeRect(0, 24 * (CGFloat)roll(4), 200, 24);
        CGFloat line = separator ? NSMaxY([collection convertRect:separator.bounds fromView:separator]) - 0.5 : -CGFLOAT_MAX;
        NSInteger want = MIN(referenceBelowLine(collection, line), DPTidyMinimumTabs), got = DPTidyTabsBelowLine(list);
        cases++;
        exact += want < DPTidyMinimumTabs;
        if (got != want) {
            mismatches++;
            printf("FAIL loose count case %d: got %ld, want %ld\n", round, (long)got, (long)want);
        }
    }
    failures += mismatches;
    expectEqual(@(cases), @60, @"every generated sidebar was counted");
    expectEqual(@(exact >= 8 && exact < 55), @YES, @"some sidebars count exactly and some hit the minimum");

    DPFakeCollection *big = [[collectionClass alloc] initWithFrame:NSMakeRect(0, 0, 200, 8000)];
    NSMutableArray *frames = [NSMutableArray array], *kinds = [NSMutableArray array];
    for (int i = 0; i < 400; i++) {
        [frames addObject:[NSValue valueWithRect:NSMakeRect(0, 24 * i, 200, 24)]];
        [kinds addObject:@1];
    }
    DPFakeLayout *layout = [DPFakeLayout new];
    layout.frames = @[ frames ];
    big.fakeLayout = layout;
    big.kinds = @[ kinds ];
    NSView *bigList = makeList(big, NULL);
    lookups = 0;
    expectEqual(@(DPTidyTabsBelowLine(bigList)), @(DPTidyMinimumTabs), @"a 400 tab sidebar stops counting at the minimum");
    expectEqual(@(lookups), @(DPTidyMinimumTabs), @"a 400 tab sidebar only materializes cells up to the minimum");

    NSMutableArray *few = [kinds subarrayWithRange:NSMakeRange(0, 5)].mutableCopy;
    big.kinds = @[ few ];
    layout.frames = @[ [frames subarrayWithRange:NSMakeRange(0, 5)] ];
    expectEqual(@(DPTidyTabsBelowLine(bigList)), @5, @"five tabs are five tabs");
}

@interface DPCountedScriptTab : NSObject
@property (copy) NSString *tabId, *URL;
@end
@implementation DPCountedScriptTab
@end

@interface DPCountedScriptWindow : NSObject {
@public
    NSArray *_tabs;
}
@property (copy) NSString *windowId;
@property (strong) DPCountedScriptTab *activeTab;
@property int tabListReads;
@end
@implementation DPCountedScriptWindow
- (NSArray *)appleScriptTabs {
    self.tabListReads++;
    return _tabs;
}
@end

@interface DPCountedAppDelegate : NSObject <NSApplicationDelegate> {
@public
    NSArray *_windows;
}
@property int windowReads;
@end
@implementation DPCountedAppDelegate
- (NSArray *)appleScriptWindows {
    self.windowReads++;
    return _windows;
}
@end

static void checkScriptWindowMemo(void) {
    id savedDelegate = NSApp.delegate;
    DPCountedAppDelegate *counted = [DPCountedAppDelegate new];
    NSMutableArray *tabs = [NSMutableArray array];
    for (int i = 0; i < 100; i++) {
        DPCountedScriptTab *t = [DPCountedScriptTab new];
        t.tabId = [NSString stringWithFormat:@"tab-%d", i];
        t.URL = i == 99 ? @"dia://newtab" : [NSString stringWithFormat:@"https://example.com/%d", i];
        [tabs addObject:t];
    }
    DPCountedScriptWindow *sw = [DPCountedScriptWindow new];
    sw.windowId = @"memo-win";
    sw->_tabs = tabs;
    sw.activeTab = tabs[0];
    counted->_windows = @[ sw ];
    NSApp.delegate = counted;

    NSWindow *win = window(@"memo-win");
    DPNewTabNextToCurrent.on = YES;
    counted.windowReads = 0;
    sw.tabListReads = 0;

    // Seed initial state on first note, then switch to a blank tab in the same turn.
    DPNote(win);
    expectEqual(@(counted.windowReads), @1, @"first DPNote reads appleScriptWindows once");
    expectEqual(@(sw.tabListReads), @1, @"first DPNote reads appleScriptTabs once");

    NSMutableArray *withNew = [tabs mutableCopy];
    DPCountedScriptTab *fresh = [DPCountedScriptTab new];
    fresh.tabId = @"tab-fresh";
    fresh.URL = @"";
    [withNew addObject:fresh];
    sw->_tabs = withNew;
    sw.activeTab = fresh;
    DPNote(win);
    expectEqual(@(counted.windowReads), @1, @"second DPNote in the same run-loop turn reuses memoized DPScriptWindow");
    expectEqual(@(sw.tabListReads), @2, @"switching to a new blank tab reads appleScriptTabs once, not 3x");

    // Changing window.identifier invalidates the memo immediately.
    win.identifier = @"other-id";
    expectEqual(DPScriptWindow(win), nil, @"changing window.identifier misses the previous memo");
    win.identifier = @"memo-win";
    int beforeTurn = counted.windowReads;
    expectEqual(DPScriptWindow(win), sw, @"restoring window.identifier resolves the scripted window again");
    expectEqual(@(counted.windowReads), @(beforeTurn + 1), @"identifier change triggered a fresh lookup");
    expectEqual(DPScriptWindow(win), sw, @"subsequent call in same turn hits memo");
    expectEqual(@(counted.windowReads), @(beforeTurn + 1), @"memo prevented duplicate lookup in same turn");

    // Draining a run-loop turn clears the per-turn memo.
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    int afterTurn = counted.windowReads;
    expectEqual(DPScriptWindow(win), sw, @"lookup after run-loop turn still finds scripted window");
    expectEqual(@(counted.windowReads), @(afterTurn + 1), @"run-loop turn cleared DPScriptWindow memo");

    DPNewTabNextToCurrent.on = NO;
    NSApp.delegate = savedDelegate;
}


@class DPWorldTab;
static DPWorldTab *worldActive;
static NSMutableArray<DPWorldTab *> *worldTabs;
static NSMutableArray<NSArray<NSNumber *> *> *worldMoves;
static NSMutableArray<NSString *> *worldFocuses;
static NSInteger worldPinned;
static long long worldNextSession;

@interface DPWorldContents : NSObject
@property long long sessionId;
@property(copy) NSString *url, *tabId;
@end
@implementation DPWorldContents
@end

@interface DPWorldTab : NSObject
@property(copy) NSString *tabId, *URL;
@end
@implementation DPWorldTab
- (void)focus:(id)sender {
    worldActive = self;
    [worldFocuses addObject:self.tabId];
}
- (void)close:(id)sender {
    [worldTabs removeObject:self];
    for (DPWorldContents *contents in [worldContents copy]) if ([contents.tabId isEqual:self.tabId]) [worldContents removeObject:contents];
    if (worldActive == self) worldActive = worldTabs.lastObject;
}
@end

@interface DiaAppleScriptTab : DPWorldTab
@end
@implementation DiaAppleScriptTab
@end

@interface DPWorldWindow : NSObject
@property(copy) NSString *windowId;
@end
@implementation DPWorldWindow
- (NSArray *)appleScriptTabs { return worldTabs; }
- (id)activeTab { return worldActive; }
- (id)newScriptingObjectOfClass:(Class)cls forValueForKey:(NSString *)key withContentsValue:(id)contents properties:(id)properties {
    DPWorldTab *tab = [cls new];
    tab.tabId = [NSString stringWithFormat:@"made-%lu", (unsigned long)worldTabs.count];
    tab.URL = @"dia://newtab";
    [worldTabs addObject:tab];
    DPWorldContents *page = [DPWorldContents new];
    page.sessionId = ++worldNextSession;
    page.url = tab.URL;
    page.tabId = tab.tabId;
    [worldContents addObject:page];
    worldActive = tab;
    return tab;
}
@end

@interface DPWorldDelegate : NSObject
@property(strong) NSArray *folders;
@end
@implementation DPWorldDelegate
- (void)browser:(id)browser getAllTabGroupsWithCompletion:(void (^)(NSArray *))done { done(self.folders ?: @[]); }
@end

@interface DPWorldFolder : NSObject
@property(strong) NSArray *tabSessionIds;
@end
@implementation DPWorldFolder
@end

static DPWorldContents *worldPage(NSString *tabID) {
    for (DPWorldContents *contents in worldContents) if ([contents.tabId isEqual:tabID]) return contents;
    return nil;
}

static void worldMoveTab(NSNumber *session, NSInteger index) {
    [worldMoves addObject:@[ session, @(index) ]];
    DPWorldTab *moved = nil;
    for (DPWorldContents *contents in worldContents)
        if (contents.sessionId == session.longLongValue)
            for (DPWorldTab *tab in worldTabs) if ([tab.tabId isEqual:contents.tabId]) moved = tab;
    if (!moved) return;
    [worldTabs removeObject:moved];
    [worldTabs insertObject:moved atIndex:MIN((NSUInteger)(worldPinned + index), worldTabs.count)];
}

static long long worldVisibleSession(void) { return worldPage(worldActive.tabId).sessionId; }

static NSString *worldOrder(void) {
    return [[worldTabs valueForKey:@"tabId"] componentsJoinedByString:@" "];
}

static void drain(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static DPWorldTab *worldAdd(NSString *tabID, NSString *url) {
    DPWorldTab *tab = [DPWorldTab new];
    tab.tabId = tabID;
    tab.URL = url;
    [worldTabs addObject:tab];
    if (url.length) {
        DPWorldContents *page = [DPWorldContents new];
        page.sessionId = ++worldNextSession;
        page.url = url;
        page.tabId = tabID;
        [worldContents addObject:page];
    }
    return tab;
}

static DPWorldTab *worldTab(NSString *tabID) {
    for (DPWorldTab *tab in worldTabs) if ([tab.tabId isEqual:tabID]) return tab;
    return nil;
}

static NSWindow *worldStart(NSArray<NSString *> *tabIDs, NSInteger pinned, NSString *activeID) {
    worldTabs = [NSMutableArray array];
    worldContents = [NSMutableArray array];
    worldMoves = [NSMutableArray array];
    worldFocuses = [NSMutableArray array];
    worldPinned = pinned;
    worldNextSession = 0;
    splitTabs = nil;
    worldBrowser = [NSObject new];
    worldDelegate = [DPWorldDelegate new];
    worldMove = worldMoveTab;
    worldActiveSession = worldVisibleSession;
    for (NSString *tabID in tabIDs) worldAdd(tabID, [NSString stringWithFormat:@"https://%@.example/", tabID]);
    worldActive = worldTab(activeID);
    DPWorldWindow *scriptWindow = [DPWorldWindow new];
    scriptWindow.windowId = @"world";
    DPFakeDelegate *appDelegate = [DPFakeDelegate new];
    appDelegate.appleScriptWindows = @[ scriptWindow ];
    NSApp.delegate = appDelegate;
    NSWindow *win = window(@"world");
    DPNewTabNextToCurrent.on = YES;
    DPNote(win);
    return win;
}

static void worldEnd(NSWindow *win) {
    DPNewTabNextToCurrent.on = NO;
    DPCommandBar.on = NO;
    DPSet(win, &DPOverlayKey, nil);
    DPSet(win, &DPStateKey, nil);
    worldBrowser = worldDelegate = nil;
    worldMove = NULL;
    worldActiveSession = NULL;
    worldTabs = nil;
    worldContents = nil;
    worldActive = nil;
}

static DPWorldTab *worldNativeNewTab(NSWindow *win) {
    DPWorldTab *tab = worldAdd([NSString stringWithFormat:@"new-%lu", (unsigned long)worldTabs.count], @"");
    worldActive = tab;
    DPNote(win);
    return tab;
}

static DPCommandBarOverlay *worldOpenBar(NSWindow *win, DPWorldTab *barTab, DPWorldTab *over) {
    DPCommandBarOverlay *bar = [DPCommandBarOverlay new];
    bar.openedTab = barTab;
    bar.returnTab = over;
    DPSet(win, &DPOverlayKey, bar);
    DPNote(win);
    [over focus:nil];
    DPNote(win);
    return bar;
}

static void worldKeep(NSWindow *win, DPWorldTab *barTab, NSString *url) {
    DPSet(win, &DPOverlayKey, nil);
    barTab.URL = url;
    DPWorldContents *page = [DPWorldContents new];
    page.sessionId = ++worldNextSession;
    page.url = url;
    page.tabId = barTab.tabId;
    [worldContents addObject:page];
    [barTab focus:nil];
    DPNote(win);
}

// Dia can leave the tab the bar opened over in front while it keeps the bar's tab, and nothing mounts a view when it then focuses it.
static void worldKeepBehind(NSWindow *win, DPWorldTab *barTab, NSString *url) {
    DPSet(win, &DPOverlayKey, nil);
    barTab.URL = url;
    DPWorldContents *page = [DPWorldContents new];
    page.sessionId = ++worldNextSession;
    page.url = url;
    page.tabId = barTab.tabId;
    [worldContents addObject:page];
    DPNote(win);
    [barTab focus:nil];
}

static void worldCancel(NSWindow *win, DPWorldTab *barTab) {
    DPSet(win, &DPOverlayKey, nil);
    [barTab close:nil];
    DPNote(win);
}

static void checkNewTabNextToCurrentWithCommandBar(void) {
    id savedDelegate = NSApp.delegate;

    // Without the command bar, the new tab is made through scripting and moved at once.
    NSWindow *win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = NO;
    expectEqual(@(DPOpenNextToCurrent(win)), @YES, @"no command bar: the new tab is made through scripting");
    drain(0.2);
    expectEqual(worldOrder(), @"A made-3 B C", @"no command bar: the scripted tab is placed right after the current one");
    worldEnd(win);

    // With it, Dia makes the tab itself so the bar can open over it.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    expectEqual(@(DPOpenNextToCurrent(win)), @NO, @"command bar: New Tab is left to Dia");
    expectEqual(worldOrder(), @"A B C", @"command bar: no scripted tab is made");
    expectEqual(@(DPOpenNextToCurrent(win)), @NO, @"command bar: asking twice still leaves it to Dia");
    worldEnd(win);

    // Dia opens its tab inside the same event, so the script window read above must not be remembered for the page it mounts.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    DPCountedAppDelegate *counted = [DPCountedAppDelegate new];
    counted->_windows = ((DPFakeDelegate *)NSApp.delegate).appleScriptWindows;
    NSApp.delegate = counted;
    expectEqual(@(DPOpenNextToCurrent(win)), @NO, @"command bar: New Tab is left to Dia (counted)");
    counted.windowReads = 0;
    DPScriptWindow(win);
    expectEqual(@(counted.windowReads), @1, @"command bar: the next read of the script window starts over");
    worldEnd(win);

    // Opening and cancelling the bar moves nothing and goes nowhere.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    DPOpenNextToCurrent(win);
    DPWorldTab *barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    drain(0.3);
    expectEqual(worldOrder(), @"A B C new-3", @"open: the bar's tab stays where Dia put it while the bar is open");
    expectEqual(@(worldMoves.count), @0, @"open: nothing is moved while the bar is open");
    NSUInteger focuses = worldFocuses.count;
    worldCancel(win, barTab);
    drain(0.4);
    expectEqual(worldOrder(), @"A B C", @"cancel: the bar's tab is gone and the others stay put");
    expectEqual(@(worldMoves.count), @0, @"cancel: nothing is moved");
    expectEqual(worldActive.tabId, @"A", @"cancel: still on the tab the bar opened over");
    expectEqual(@(worldFocuses.count), @(focuses), @"cancel: no tab is focused again");
    worldEnd(win);

    // Keeping the bar's tab puts it right after the tab it came from, and closing it goes back there.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    DPOpenNextToCurrent(win);
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    worldKeep(win, barTab, @"https://result.example/");
    drain(0.4);
    expectEqual(worldOrder(), @"A new-3 B C", @"keep: the tab lands right after the one the bar opened over");
    expectEqual(worldMoves, (@[ @[ @4, @0 ], @[ @4, @1 ] ]), @"keep: it moves through the top of the unpinned tabs");
    expectEqual(@(((DPNextTabs *)DPGet(win, &DPStateKey)).moving), @NO, @"keep: moving is over");
    [barTab close:nil];
    DPNote(win);
    drain(0.2);
    expectEqual(worldActive.tabId, @"A", @"keep: closing it goes back to the tab it came from");
    worldEnd(win);

    // Dia keeps the tab the bar opened over in front until it focuses the kept tab; the tab is placed all the same.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    DPOpenNextToCurrent(win);
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    worldKeepBehind(win, barTab, @"https://result.example/");
    drain(0.4);
    expectEqual(worldOrder(), @"A new-3 B C", @"keep behind the origin: the tab lands right after the one the bar opened over");
    expectEqual(@(((DPNextTabs *)DPGet(win, &DPStateKey)).moving), @NO, @"keep behind the origin: moving is over");
    worldEnd(win);

    // A bar closed while its tab is still open and empty goes nowhere, however the tab is then closed.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    DPOpenNextToCurrent(win);
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    DPSet(win, &DPOverlayKey, nil);
    DPNote(win);
    [barTab close:nil];
    DPNote(win);
    drain(0.5);
    expectEqual(worldOrder(), @"A B C", @"cancel with the tab still open: the others stay put");
    expectEqual(@(worldMoves.count), @0, @"cancel with the tab still open: nothing is moved");
    expectEqual(worldActive.tabId, @"A", @"cancel with the tab still open: still on the tab the bar opened over");
    worldEnd(win);

    // The bar opened by a trigger that never asks (the plus button, a double click) is placed the same.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"B");
    DPCommandBar.on = YES;
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"B"));
    worldKeep(win, barTab, @"https://result.example/");
    drain(0.4);
    expectEqual(worldOrder(), @"A B new-3 C", @"keep without a New Tab ask: still placed after the tab it came from");
    worldEnd(win);

    // From a pinned tab, the top of the unpinned tabs.
    win = worldStart(@[ @"P1", @"P2", @"B", @"C" ], 2, @"P1");
    DPCommandBar.on = YES;
    DPOpenNextToCurrent(win);
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"P1"));
    worldKeep(win, barTab, @"https://result.example/");
    drain(0.4);
    expectEqual(worldOrder(), @"P1 P2 new-4 B C", @"keep from a pinned tab: top of the unpinned tabs");
    worldEnd(win);

    // From a tab in a folder, right after the folder, with or without the New Tab ask.
    for (int asked = 0; asked < 2; asked++) {
        win = worldStart(@[ @"A", @"B", @"C", @"D" ], 0, @"B");
        DPCommandBar.on = YES;
        DPWorldFolder *folder = [DPWorldFolder new];
        folder.tabSessionIds = @[ @(worldPage(@"B").sessionId), @(worldPage(@"C").sessionId) ];
        ((DPWorldDelegate *)worldDelegate).folders = @[ folder ];
        if (asked) DPOpenNextToCurrent(win);
        barTab = worldNativeNewTab(win);
        worldOpenBar(win, barTab, worldTab(@"B"));
        worldKeep(win, barTab, @"https://result.example/");
        drain(0.4);
        expectEqual(worldOrder(), @"A B C new-4 D", asked ? @"keep from a folder: after the folder (asked)" : @"keep from a folder: after the folder (not asked)");
        worldEnd(win);
    }

    // The tab the bar's tab is kept beside is gone, or the user left for another tab: nothing moves.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    DPSet(win, &DPOverlayKey, nil);
    [barTab close:nil];
    [worldTab(@"C") focus:nil];
    DPNote(win);
    drain(0.4);
    expectEqual(worldOrder(), @"A B C", @"switching away closes the bar's tab and moves nothing");
    expectEqual(@(worldMoves.count), @0, @"switching away: no move");
    expectEqual(worldActive.tabId, @"C", @"switching away: the tab clicked stays in front");
    worldEnd(win);

    // A tab that never gets its own page is left where it is.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    DPSet(win, &DPOverlayKey, nil);
    barTab.URL = @"https://result.example/";
    [barTab focus:nil];
    DPNote(win);
    drain(0.4);
    expectEqual(@(worldMoves.count), @0, @"keep without a page: nothing is moved while it waits");
    expectEqual(@(((DPNextTabs *)DPGet(win, &DPStateKey)).moving), @NO, @"keep without a page: Dia isn't held waiting");
    worldEnd(win);

    // A page at the same address as another tab can't be told apart, so it stays.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    worldKeep(win, barTab, @"https://B.example/");
    drain(0.4);
    expectEqual(@(worldMoves.count), @0, @"keep at another tab's address: nothing is moved");
    expectEqual(worldOrder(), @"A B C new-3", @"keep at another tab's address: the tab stays");
    worldEnd(win);

    // Turned off meanwhile, nothing moves.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    worldKeep(win, barTab, @"https://result.example/");
    DPNewTabNextToCurrent.on = NO;
    drain(0.4);
    expectEqual(@(worldMoves.count), @0, @"keep after the tweak is turned off: nothing is moved");
    worldEnd(win);

    // From a split, the bar never opens, so the scripted tab (with its own page) is still used.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    [DPSplits(win) addObject:@"A"];
    expectEqual(@(DPOpenNextToCurrent(win)), @YES, @"from a split: the new tab is made through scripting");
    drain(0.2);
    expectEqual(worldOrder(), @"A made-3 B C", @"from a split: placed right after the current tab");
    worldEnd(win);

    // A bar kept while another tab is still being moved doesn't start a second move.
    win = worldStart(@[ @"A", @"B", @"C" ], 0, @"A");
    DPCommandBar.on = YES;
    barTab = worldNativeNewTab(win);
    worldOpenBar(win, barTab, worldTab(@"A"));
    ((DPNextTabs *)DPGet(win, &DPStateKey)).moving = YES;
    worldKeep(win, barTab, @"https://result.example/");
    drain(0.2);
    expectEqual(@(worldMoves.count), @0, @"keep while another tab is moving: no overlapping move");
    DPDoneMoving(win, DPGet(win, &DPStateKey));
    drain(0.4);
    expectEqual(worldOrder(), @"A new-3 B C", @"keep while another tab is moving: placed once it's over");
    worldEnd(win);

    NSApp.delegate = savedDelegate;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPFakeDelegate *delegate = [DPFakeDelegate new];
        NSApp.delegate = delegate;

        NSWindow *older = window(@"A"), *newer = window(@"B"), *stranger = window(@"C");
        delegate.appleScriptWindows = @[
            scripted(@"A", @[ tab(@"https://a.example/1", @"A one", NO), tab(@"https://shared.example/", @"Shared", NO), tab(@"https://a.example/2", @"A two", NO) ]),
            scripted(@"B", @[ tab(@"https://shared.example/", @"Shared", YES), tab(@"https://b.example/1", @"B one", NO), tab(@"https://b.example/2", nil, NO), tab(@"", @"No address", NO) ]),
        ];

        expectEqual(DPTidyLooseTabs(older), (@{ @"https://a.example/1": @"A one", @"https://shared.example/": @"Shared", @"https://a.example/2": @"A two" }),
            @"the first window lists its own tabs");
        expectEqual(DPTidyLooseTabs(newer), (@{ @"https://b.example/1": @"B one", @"https://b.example/2": @"https://b.example/2" }),
            @"the second window lists its own tabs, not the first window's, and keeps a favorite out");
        expectEqual(DPTidyLooseTabs(stranger), @{}, @"a window Dia doesn't script has no loose tabs");
        expectEqual(DPTidyLooseTabs(nil), @{}, @"no window has no loose tabs");

        delegate.appleScriptWindows = @[ scripted(@"B", (id)@"not a list") ];
        expectEqual(DPTidyLooseTabs(newer), @{}, @"a window without a tab list has no loose tabs");
        delegate.appleScriptWindows = @[];
        expectEqual(DPTidyLooseTabs(newer), @{}, @"no scripted windows means no loose tabs");

        NSString *emojiPath = [NSString stringWithFormat:@"https://example.com/%@/%@", [@"" stringByPaddingToLength:57 withString:@"a" startingAtIndex:0], @"\U0001F525tail"];
        NSString *trimmed = DPTidyAddress(emojiPath, @"example.com");
        unichar last = trimmed.length ? [trimmed characterAtIndex:trimmed.length - 1] : 0;
        expectEqual(@(trimmed.length <= 70 && [trimmed UTF8String] != NULL && (last < 0xD800 || last > 0xDBFF)), @YES,
            @"address truncation does not split a UTF-16 surrogate pair");
    }
    checkTidyLayout();
    checkLooseCount();
    checkScriptWindowMemo();
    checkNewTabNextToCurrentWithCommandBar();
    if (!failures) printf("all Tidy Tabs checks passed\n");
    return failures ? 1 : 0;
}

#import "StdPatch/StdPatch.h"
#import "Patches/TidyTabs/TidyTabs.h"
#import "Patches/PullRequestRepo/PullRequestRepo.h"
#import "Patches/CompactTabRows/CompactTabRows.h"
#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/CommandBarOverlay.h"

extern DPPatch DPHideSleepingTabs, DPCollapsePinned, DPHideTabGroupBackground, DPUndoCloseTab, DPSavePageAs;
extern DPPatch DPProfileEmoji, DPKeepFoldersOpen, DPUnloadTab, DPCompactSidebarHeader, DPCompactTabRows, DPTidyTabs;
DPPatch DPCommandBar;

static NSString *DPTestSuiteName(void) {
    return [NSString stringWithFormat:@"com.diapatches.sidebar-tab-bugs.%d", getpid()];
}

@interface NSUserDefaults (DPSidebarTabTestSuite)
- (instancetype)dp_testInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPSidebarTabTestSuite)
- (instancetype)dp_testInitWithSuiteName:(NSString *)suite {
    return [self dp_testInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPTestSuiteName() : suite];
}
@end

// Minimal StdPatch & cross-patch stubs for standalone unit testing.
CFTimeInterval DPFoldedAt;
static BOOL gCanUndoGrouping;
BOOL DPCanUndoGrouping(void) { return gCanUndoGrouping; }
void DPForgetGroupingUndo(void) {}
static BOOL gSmallRows;
NSString *DPChoice(DPPatch *patch) { return patch == &DPCompactTabRows && gSmallRows ? @"small" : patch->defaultChoice; }
void *swift_unknownObjectWeakLoadStrong(void *ref) { return ref && *(__unsafe_unretained id *)ref ? (__bridge_retained void *)*(__unsafe_unretained id *)ref : NULL; }
void DPSetHint(NSView *view, NSString *text) {}
void DPShowHint(NSView *view) {}
void DPTidyTabsNow(NSWindow *window) {}
NSString *DPTidyUnavailableReason(void) { return nil; }
void DPOnLaunch(void (^block)(void)) { block(); }
char DPOverlayKey;
void DPDropUnwantedSpares(void) {}
void DPUpdateSpareTimer(void) {}
void DPShowHiddenBars(void) {}
void DPCancelCommandBar(DPCommandBarOverlay *overlay) {}
void DPInstallHiddenStripTab(void) {}
void DPInstallStandIn(void) {}
void DPInstallPress(void) {}
void DPHoldStrips(NSWindow *window) {}
void DPReleaseStrips(void) {}
NSString *DPStripTabID(NSView *tabView) { return nil; }
BOOL DPSelectionLayoutKnown(void) { return YES; }
void DPNoteLook(NSView *background) {}
void DPRefreshStandIns(void) {}
NSMenuItem *DPMenuItem(NSString *title, void (^action)(void)) { return [[NSMenuItem alloc] initWithTitle:title ?: @"" action:nil keyEquivalent:@""]; }
BOOL DPShortcutMatches(NSEvent *event, DPPatch *patch) {
    return event.type == NSEventTypeKeyDown && [[event.charactersIgnoringModifiers lowercaseString] isEqualToString:@"z"]
        && (event.modifierFlags & NSEventModifierFlagCommand);
}

static NSMutableArray<NSEvent *(^)(NSEvent *)> *gMonitors;
static id CaptureMonitor(id self, SEL _cmd, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) {
    if (!gMonitors) gMonitors = [NSMutableArray new];
    id copy = [handler copy];
    [gMonitors addObject:copy];
    return copy;
}

static int failures;
static void Check(BOOL ok, NSString *msg) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", msg.UTF8String);
}

// --- 1. HideSleepingTabs fixtures ---
@interface DPFakeSwitcherState : NSObject
@property NSArray *items;
@property NSString *focusedItemID;
@end
@implementation DPFakeSwitcherState
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeSubject : NSObject
@property id currentValue;
@end
@implementation DPFakeSubject
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeTabVM : NSObject
@property DPFakeSubject *stateSubject;
@end
@implementation DPFakeTabVM
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeTabCtrl : NSObject
@property DPFakeTabVM *viewModel;
@end
@implementation DPFakeTabCtrl
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeSwitcherDelegate : NSObject
@property NSDictionary *recentTabControllers;
@end
@implementation DPFakeSwitcherDelegate
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeSwitcherVM : NSObject
@property DPFakeSubject *stateSubject;
@property DPFakeSwitcherDelegate *delegate;
@end
@implementation DPFakeSwitcherVM
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeGrid : NSCollectionView
@property NSIndexPath *lastMakePath;
@end
@implementation DPFakeGrid
- (NSCollectionViewItem *)makeItemWithIdentifier:(NSUserInterfaceItemIdentifier)identifier forIndexPath:(NSIndexPath *)indexPath {
    self.lastMakePath = indexPath;
    return [NSCollectionViewItem new];
}
@end

static NSCollectionView *gNestedGrid;
@interface _TtC10RecentTabs24RecentTabsViewController : NSViewController <NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>
@property DPFakeSwitcherVM *viewModel;
@property DPFakeGrid *collectionView;
@property NSSize cellSize;
@end
@implementation _TtC10RecentTabs24RecentTabsViewController
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return self.viewModel.stateSubject.currentValue ? [((DPFakeSwitcherState *)self.viewModel.stateSubject.currentValue).items count] : 0; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    if (gNestedGrid) [gNestedGrid makeItemWithIdentifier:@"nested" forIndexPath:[NSIndexPath indexPathForItem:99 inSection:0]];
    return [collectionView makeItemWithIdentifier:@"cell" forIndexPath:indexPath];
}
- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath { return self.cellSize; }
- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {}
@end

static void TestHideSleepingTabs(void) {
    DPHideSleepingTabs.install();
    DPHideSleepingTabs.on = YES;
    _TtC10RecentTabs24RecentTabsViewController *vc = [_TtC10RecentTabs24RecentTabsViewController new];
    vc.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 600)];
    vc.collectionView = [DPFakeGrid new];
    vc.cellSize = NSMakeSize(200, 150);

    // 10 tabs total (5x2 grid), only 3 awake -> must fit in 3 columns x 1 row!
    NSMutableArray *uuids = [NSMutableArray new];
    NSMutableDictionary *ctrls = [NSMutableDictionary new];
    for (int i = 0; i < 10; i++) {
        NSString *u = [NSString stringWithFormat:@"00000000-0000-0000-0000-%012d", i + 1];
        [uuids addObject:u];
        DPFakeTabCtrl *c = [DPFakeTabCtrl new];
        c.viewModel = [DPFakeTabVM new];
        c.viewModel.stateSubject = [DPFakeSubject new];
        c.viewModel.stateSubject.currentValue = i < 3 ? @"state(snapshot: Optional(img))" : @"state(snapshot: nil)";
        ctrls[u] = c;
    }
    DPFakeSwitcherState *st = [DPFakeSwitcherState new];
    st.items = uuids;
    vc.viewModel = [DPFakeSwitcherVM new];
    vc.viewModel.stateSubject = [DPFakeSubject new];
    vc.viewModel.stateSubject.currentValue = st;
    vc.viewModel.delegate = [DPFakeSwitcherDelegate new];
    vc.viewModel.delegate.recentTabControllers = ctrls;

    __weak NSLayoutConstraint *weakW = nil;
    @autoreleasepool {
        NSView *holder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 600)];
        vc.view = holder;
        NSLayoutConstraint *w = [holder.widthAnchor constraintEqualToConstant:152 + 5 * 200];
        NSLayoutConstraint *h = [holder.heightAnchor constraintEqualToConstant:152 + 2 * 150];
        w.active = YES; h.active = YES;
        weakW = w;
        Check([vc collectionView:vc.collectionView numberOfItemsInSection:0] == 3, @"HideSleepingTabs: hides 7 sleeping tabs");
        Check(object_getClass(w) == NSLayoutConstraint.class && object_getClass(h) == NSLayoutConstraint.class,
              @"HideSleepingTabs: watches constraints without KVO isa-swizzling");

        // Width then height: 3 awake tabs fit in 3 columns x 1 row (height = 152 + 150 = 302, NOT 452!).
        w.constant = 152 + 5 * 200;
        h.constant = 152 + 2 * 150;
        Check(fabs(w.constant - (152 + 3 * 200)) < 0.5, @"HideSleepingTabs: shrinks width to 3 columns");
        Check(fabs(h.constant - (152 + 1 * 150)) < 0.5, @"HideSleepingTabs: shrinks height to 1 row (width-first)");

        // Height BEFORE width from stale 1-column width: 5 awake tabs in 5x3 grid must still end at 1 row!
        for (int i = 3; i < 5; i++) ((DPFakeTabCtrl *)ctrls[uuids[i]]).viewModel.stateSubject.currentValue = @"state(snapshot: Optional(img))";
        w.constant = 152 + 1 * 200;
        h.constant = 152 + 3 * 150;
        w.constant = 152 + 5 * 200;
        Check(fabs(w.constant - (152 + 5 * 200)) < 0.5, @"HideSleepingTabs: 5 awake tabs use 5 columns");
        Check(fabs(h.constant - (152 + 1 * 150)) < 0.5, @"HideSleepingTabs: 5 awake tabs shrink height to 1 row even when height set before width");

        // Unrelated nested NSCollectionView does not receive switcher's DPShownPath.
        DPFakeGrid *nested = [DPFakeGrid new];
        gNestedGrid = nested;
        [vc collectionView:vc.collectionView itemForRepresentedObjectAtIndexPath:[NSIndexPath indexPathForItem:2 inSection:0]];
        gNestedGrid = nil;
        Check(nested.lastMakePath.item == 99 && vc.collectionView.lastMakePath.item == 2, @"HideSleepingTabs: DPShownPath scoped to switcher grid only");

        // Off-tweak: setConstant passes through untouched.
        DPHideSleepingTabs.on = NO;
        w.constant = 152 + 5 * 200;
        h.constant = 152 + 3 * 150;
        Check(fabs(w.constant - (152 + 5 * 200)) < 0.5 && fabs(h.constant - (152 + 3 * 150)) < 0.5, @"HideSleepingTabs: off leaves constraint constants untouched");

        w.active = NO; h.active = NO;
        vc.view = [NSView new];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    Check(weakW == nil, @"HideSleepingTabs: watched constraints deallocate cleanly with no KVO leak");
}

// --- 2. HideTabGroupBackground fixtures ---
@interface _TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView : NSView
@end
@implementation _TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView
@end

@interface _TtC5TabUI16TabGroupCellView : NSView {
@public
    id viewModel;
    NSView *$__lazy_storage_$_chevronIconView;
}
@end
@implementation _TtC5TabUI16TabGroupCellView
- (void)updateLayer {}
- (void)layout {}
- (void)prepareForReuse {}
@end

static void TestHideTabGroupBackground(void) {
    DPHideTabGroupBackground.install();
    NSWindow *hiddenWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _TtC5TabUI16TabGroupCellView *cell = [[_TtC5TabUI16TabGroupCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    _TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView *bg =
        [[_TtCC5TabUI16TabGroupCellViewP33_6B047B569AD47EBB5C3E7DC66393AFEF23ContainerBackgroundView alloc] initWithFrame:cell.bounds];
    bg.wantsLayer = YES;
    CGColorRef grey = [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:0.2].CGColor;
    bg.layer.backgroundColor = grey;
    bg.layer.borderWidth = 1.5;
    CALayer *shadow = [CALayer layer];
    [bg.layer addSublayer:shadow];
    [cell addSubview:bg];
    [hiddenWin.contentView addSubview:cell];

    // Off-tweak does nothing.
    DPHideTabGroupBackground.on = NO;
    [cell updateLayer];
    Check(bg.layer.backgroundColor != nil && bg.layer.borderWidth == 1.5 && !shadow.hidden, @"HideTabGroupBackground: off does not mutate layer");

    // On hides grey background, border, and shadow.
    DPHideTabGroupBackground.on = YES;
    [cell updateLayer];
    Check(bg.layer.backgroundColor == nil && bg.layer.borderWidth == 0 && shadow.hidden, @"HideTabGroupBackground: on hides grey background and shadow");

    // Off restores saved backgroundColor, borderWidth, and shadow even in a non-visible/minimized window!
    DPHideTabGroupBackground.on = NO;
    DPHideTabGroupBackground.apply(&DPHideTabGroupBackground);
    Check(bg.layer.backgroundColor != nil && CGColorEqualToColor(bg.layer.backgroundColor, grey), @"HideTabGroupBackground: off restores saved backgroundColor in minimized window");
    Check(bg.layer.borderWidth == 1.5 && !shadow.hidden, @"HideTabGroupBackground: off restores borderWidth and shadow sublayer");
    Check(DPHideTabGroupBackground.verify(&DPHideTabGroupBackground) == nil, @"HideTabGroupBackground: verify passes after restore");
}

// --- 3. KeepFoldersOpen fixtures ---
@interface _TtC5TabUI12TabGroupView : NSView {
@public
    id viewModel;
    BOOL shouldDisplayExpandedContainer;
}
@end
@implementation _TtC5TabUI12TabGroupView
- (void)layout {}
@end

static void TestKeepFoldersOpen(void) {
    DPKeepFoldersOpen.install();
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _TtC5TabUI12TabGroupView *folder = [[_TtC5TabUI12TabGroupView alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
    folder->shouldDisplayExpandedContainer = YES;
    [w.contentView addSubview:folder];

    __weak id weakVM = nil;
    @autoreleasepool {
        NSObject *vm = [NSObject new];
        weakVM = vm;
        folder->viewModel = vm;
        DPKeepFoldersOpen.on = NO;
        [folder layout];
        DPKeepFoldersOpen.on = YES;
        [folder layout];
        folder->viewModel = nil;
    }
    Check(weakVM == nil, @"KeepFoldersOpen: does not strongly retain Dia's viewModel");

    DPKeepFoldersOpen.on = NO;
    DPKeepFoldersOpen.apply(&DPKeepFoldersOpen);
    [folder layout];
    Check(YES, @"KeepFoldersOpen: off apply and layout clear state cleanly");
}

// --- 4. CollapsePinned drag refusal + minimized window fixtures ---
static int gDragEnteredCalls, gDragUpdatedCalls, gDragExitedCalls;
@interface DPFakeSpace : NSObject
@property (copy) NSString *spaceID;
@end
@implementation DPFakeSpace
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"spaceID"] ? self.spaceID : self; }
@end

@interface _TtC7TabList11TabListView : NSView
@property DPFakeSpace *space;
@property int scrolled;
@end
@implementation _TtC7TabList11TabListView
- (id)safeSwiftValueForKey:(NSString *)key { return self.space; }
- (void)scrollViewDidScroll { self.scrolled++; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { gDragEnteredCalls++; return NSDragOperationMove; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { gDragUpdatedCalls++; return NSDragOperationMove; }
- (void)draggingExited:(id<NSDraggingInfo>)info { gDragExitedCalls++; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (void)handleBackgroundDoubleClick:(NSGestureRecognizer *)click {}
@end

// Dia's layout builds a cache of attribute objects in prepareLayout and its own code reads that cache directly.
// Heights per section; nil is the pinned row and line TestCollapsePinned uses.
static NSArray<NSArray<NSNumber *> *> *gFakeHeights;

@interface _TtCC7TabList11TabListView14CollectionView : NSCollectionView
@end
@implementation _TtCC7TabList11TabListView14CollectionView
- (NSInteger)numberOfSections { return gFakeHeights ? (NSInteger)gFakeHeights.count : [super numberOfSections]; }
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return gFakeHeights ? (NSInteger)gFakeHeights[section].count : [super numberOfItemsInSection:section]; }
@end

@interface _TtC7TabList27TabListCollectionViewLayout : NSCollectionViewLayout {
@public
    double contentHeight;
    NSMutableDictionary<NSIndexPath *, NSCollectionViewLayoutAttributes *> *cache;
}
@end
@implementation _TtC7TabList27TabListCollectionViewLayout
- (void)prepareLayout {
    cache = [NSMutableDictionary new];
    NSArray<NSArray<NSNumber *> *> *sections = gFakeHeights ?: @[ @[ @37, @10 ] ];
    CGFloat y = 0;
    for (NSUInteger section = 0; section < sections.count; section++)
        for (NSUInteger item = 0; item < sections[section].count; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
            NSCollectionViewLayoutAttributes *a = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:path];
            a.frame = NSMakeRect(0, y, 200, sections[section][item].doubleValue);
            y += NSHeight(a.frame);
            cache[path] = a;
        }
    contentHeight = y;
}
- (NSSize)collectionViewContentSize { return NSMakeSize(200, contentHeight); }
- (NSArray<NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect {
    NSMutableArray *found = [NSMutableArray new];
    for (NSIndexPath *path in [cache.allKeys sortedArrayUsingSelector:@selector(compare:)])
        if (NSIntersectsRect(cache[path].frame, rect)) [found addObject:cache[path]];
    return found;
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath { return cache[indexPath]; }
@end

@interface DPFakePinDS : NSObject <NSCollectionViewDataSource>
@end
@implementation DPFakePinDS
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)cv { return 1; }
- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section { return 2; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip { return [NSCollectionViewItem new]; }
@end

@interface DPFakeDrag : NSObject
@property NSPoint draggingLocation;
@end
@implementation DPFakeDrag
@end

static void TestCollapsePinned(void) {
    DPCollapsePinned.install();
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _TtC7TabList11TabListView *tabList = [[_TtC7TabList11TabListView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    _TtCC7TabList11TabListView14CollectionView *cv = [[_TtCC7TabList11TabListView14CollectionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    _TtC7TabList27TabListCollectionViewLayout *layout = [_TtC7TabList27TabListCollectionViewLayout new];
    DPFakePinDS *ds = [DPFakePinDS new];
    cv.dataSource = ds;
    cv.collectionViewLayout = layout;
    [tabList addSubview:cv];
    [w.contentView addSubview:tabList];

    DPCollapsePinned.on = YES;
    [layout prepareLayout];
    NSView *header = nil;
    for (NSView *sub in cv.subviews) if ([NSStringFromClass(sub.class) isEqualToString:@"DPPinnedHeader"]) header = sub;
    Check(header != nil && !header.hidden, @"CollapsePinned: creates visible Pinned header when on");

    // Force collapsed header, refuse drag over header, then exit, then turn OFF.
    [header setValue:@YES forKey:@"collapsed"];
    DPFakeDrag *drag = [DPFakeDrag new];
    drag.draggingLocation = [cv convertPoint:NSMakePoint(50, 10) toView:nil];
    gDragEnteredCalls = gDragUpdatedCalls = gDragExitedCalls = 0;
    Check([(id)tabList draggingEntered:(id)drag] == NSDragOperationNone, @"CollapsePinned: refuses drag over collapsed header");
    Check(gDragEnteredCalls == 0, @"CollapsePinned: refused drag not forwarded to Dia");
    [(id)tabList draggingExited:(id)drag];
    Check(gDragExitedCalls == 0, @"CollapsePinned: exiting a refused drag does not send stray draggingExited");

    // Now refuse again WITHOUT exiting, then turn CollapsePinned OFF mid-drag!
    [(id)tabList draggingEntered:(id)drag];
    DPCollapsePinned.on = NO;
    DPCollapsePinned.apply(&DPCollapsePinned);
    Check(header.hidden, @"CollapsePinned: off hides header even in minimized/non-visible window");
    gDragEnteredCalls = gDragUpdatedCalls = 0;
    [(id)tabList draggingEntered:(id)drag];
    [(id)tabList draggingUpdated:(id)drag];
    [(id)tabList draggingUpdated:(id)drag];
    Check(gDragEnteredCalls == 1 && gDragUpdatedCalls == 2, @"CollapsePinned: off clears refused state and forwards draggingUpdated normally");
}


// --- 4b. CollapsePinned beside Hide New Tab Until Opened: the Pinned line and rows below it stay put ---
static NSArray<NSArray<NSString *> *> *gFakeNames;
static CGFloat gInnerShift;

@interface DPFakeRowSource : NSObject
@end
@implementation DPFakeRowSource
- (id)itemIdentifierForIndexPath:(NSIndexPath *)path { return gFakeNames[path.section][path.item]; }
@end

@interface DPFakeRowsDS : NSObject <NSCollectionViewDataSource> {
@public
    DPFakeRowSource *_impl;
}
@end
@implementation DPFakeRowsDS
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)cv { return gFakeNames.count; }
- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section { return gFakeNames[section].count; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip { return [NSCollectionViewItem new]; }
@end

@interface DPFakeVisibleWindow : NSWindow
@end
@implementation DPFakeVisibleWindow
- (BOOL)isVisible { return YES; }
@end

// Stands in for a hook installed under Collapse Pinned Tabs that moves the rows above Dia's line.
static NSCollectionViewLayoutAttributes *FakeInnerItem(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    NSCollectionViewLayoutAttributes *a = DPCallOriginal(FakeInnerItem, self, path);
    if (!gInnerShift || path.section) return a;
    a = [a copy];
    a.frame = NSOffsetRect(a.frame, 0, gInnerShift);
    return a;
}

static void FakeRows(NSArray<NSArray<NSString *> *> *names) {
    gFakeNames = names;
    NSMutableArray *heights = [NSMutableArray new];
    for (NSArray<NSString *> *section in names) {
        NSMutableArray *row = [NSMutableArray new];
        for (NSString *name in section) [row addObject:[name isEqual:@".sep"] ? @1 : @37];
        [heights addObject:row];
    }
    gFakeHeights = heights;
}

static NSCollectionView *gFakeList;
static NSRect RowFrame(NSInteger section, NSInteger item) {
    return [gFakeList.collectionViewLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]].frame;
}
static NSView *PinnedHeaderOf(NSCollectionView *list) {
    for (NSView *sub in list.subviews) if ([NSStringFromClass(sub.class) isEqualToString:@"DPPinnedHeader"]) return sub;
    return nil;
}

static void TestCollapsePinnedWithHideTab(void) {
    NSString *P1 = @".tab(11111111-1111-1111-1111-111111111111)", *P2 = @".tab(22222222-2222-2222-2222-222222222222)", *P3 = @".tab(33333333-3333-3333-3333-333333333333)";
    NSString *R1 = @".tab(44444444-4444-4444-4444-444444444444)", *R2 = @".tab(55555555-5555-5555-5555-555555555555)", *R3 = @".tab(66666666-6666-6666-6666-666666666666)";
    NSString *NEW = @"77777777-7777-7777-7777-777777777777", *SPARE = @"88888888-8888-8888-8888-888888888888";
    NSString *N = [NSString stringWithFormat:@".tab(%@)", NEW], *S = [NSString stringWithFormat:@".tab(%@)", SPARE];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    [defaults setObject:@[ @"space-fake" ] forKey:@"collapsedPinned"];
    FakeRows(@[ @[ P1, P2, P3, @".sep" ], @[ @".newtab", R1, R2, R3 ] ]);

    DPHookClass(objc_getClass(DPDiaTabListLayout), @selector(layoutAttributesForItemAtIndexPath:), (IMP)FakeInnerItem);
    DPCompactTabRows.install();
    DPCollapsePinned.install();
    DPCommandBarHideTab.install();
    DPCommandBar.on = DPCommandBarHideTab.on = DPCollapsePinned.on = YES;

    DPFakeVisibleWindow *w = [[DPFakeVisibleWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    _TtC7TabList11TabListView *tabList = [[_TtC7TabList11TabListView alloc] initWithFrame:NSMakeRect(0, 0, 200, 500)];
    tabList.space = [DPFakeSpace new];
    tabList.space.spaceID = @"space-fake";
    _TtCC7TabList11TabListView14CollectionView *cv = [[_TtCC7TabList11TabListView14CollectionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 500)];
    _TtC7TabList27TabListCollectionViewLayout *layout = [_TtC7TabList27TabListCollectionViewLayout new];
    DPFakeRowsDS *ds = [DPFakeRowsDS new];
    ds->_impl = [DPFakeRowSource new];
    cv.dataSource = ds;
    cv.collectionViewLayout = layout;
    [tabList addSubview:cv];
    [w.contentView addSubview:tabList];
    gFakeList = cv;

    [layout prepareLayout];
    NSView *header = PinnedHeaderOf(cv);
    Check(header && !header.hidden && NSMinY(header.frame) == 0 && NSMaxY(header.frame) == 28, @"CollapsePinned: Pinned line sits at the top of the list");
    Check(RowFrame(0, 3).origin.y == 28 && RowFrame(1, 0).origin.y == 29 && RowFrame(1, 1).origin.y == 66, @"CollapsePinned: folded pinned rows leave no gap under the Pinned line");

    // A hook under ours that moves the rows above the line must not reach the line's own measurements.
    gInnerShift = 100;
    [layout prepareLayout];
    Check([[header valueForKey:@"top"] doubleValue] == 0 && [[header valueForKey:@"end"] doubleValue] == 111, @"CollapsePinned: measures the Pinned line from Dia's rows, not from hooks around them");
    gInnerShift = 0;
    [layout prepareLayout];

    // Cmd+T: the bar's rows freeze, then the new tab's row is left out of the list.
    DPExpectNewTab(w);
    [layout prepareLayout];
    Check(NSMinY(header.frame) == 0 && RowFrame(0, 3).origin.y == 28 && RowFrame(1, 0).origin.y == 29, @"CollapsePinned: Cmd+T with Hide New Tab Until Opened leaves the Pinned line and rows where they were");
    FakeRows(@[ @[ P1, P2, P3, @".sep" ], @[ @".newtab", N, R1, R2, R3 ] ]);
    [layout prepareLayout];
    DPHideTabRow(NEW, w);
    [layout prepareLayout];
    Check(NSMinY(header.frame) == 0 && RowFrame(0, 3).origin.y == 28 && RowFrame(1, 0).origin.y == 29, @"CollapsePinned: the hidden new tab leaves the Pinned line and New Tab row in place");
    Check(NSHeight(RowFrame(1, 1)) == 0 && RowFrame(1, 2).origin.y == 66 && RowFrame(1, 3).origin.y == 103, @"CollapsePinned: rows after the hidden new tab close up under the Pinned line");
    Check(DPCollapsePinned.verify(&DPCollapsePinned) == nil, @"CollapsePinned: verify passes while the bar holds the new tab");
    DPShowTabRow(NEW, NO);
    [layout prepareLayout];
    Check(RowFrame(1, 1).origin.y == 66 && NSHeight(RowFrame(1, 1)) == 37 && RowFrame(1, 2).origin.y == 103, @"CollapsePinned: the new tab's row takes its place once the bar opens it");

    // Open the Bar Instantly: a spare tab parked in the list.
    FakeRows(@[ @[ P1, P2, P3, @".sep" ], @[ @".newtab", S, N, R1, R2, R3 ] ]);
    DPHideBlank(SPARE, YES, w);
    [layout prepareLayout];
    Check(RowFrame(0, 3).origin.y == 28 && RowFrame(1, 0).origin.y == 29 && NSHeight(RowFrame(1, 1)) == 0 && RowFrame(1, 2).origin.y == 66, @"CollapsePinned: a parked spare tab leaves no gap under the Pinned line");
    Check(DPCollapsePinned.verify(&DPCollapsePinned) == nil, @"CollapsePinned: verify passes with a parked spare tab");
    DPShowTabRow(SPARE, NO);

    // Compact Tab Rows trims the rows first and the Pinned line follows them, through Cmd+T and Escape.
    gSmallRows = DPCompactTabRows.on = YES;
    FakeRows(@[ @[ P1, P2, P3, @".sep" ], @[ @".newtab", R1, R2, R3 ] ]);
    [layout prepareLayout];
    Check(RowFrame(0, 3).origin.y == 28 && RowFrame(1, 0).origin.y == 29 && RowFrame(1, 1).origin.y == 59, @"CollapsePinned: Compact Tab Rows rows fold under the Pinned line without a gap");
    DPExpectNewTab(w);
    FakeRows(@[ @[ P1, P2, P3, @".sep" ], @[ @".newtab", N, R1, R2, R3 ] ]);
    [layout prepareLayout];
    DPHideTabRow(NEW, w);
    [layout prepareLayout];
    Check(NSMinY(header.frame) == 0 && RowFrame(0, 3).origin.y == 28 && NSHeight(RowFrame(1, 1)) == 0 && RowFrame(1, 2).origin.y == 59, @"CollapsePinned: Cmd+T with Compact Tab Rows closes the rows up under the Pinned line");
    Check(DPCollapsePinned.verify(&DPCollapsePinned) == nil, @"CollapsePinned: verify passes with Compact Tab Rows while the bar holds the new tab");
    FakeRows(@[ @[ P1, P2, P3, @".sep" ], @[ @".newtab", R1, R2, R3 ] ]);
    DPShowTabRow(NEW, NO);
    [layout prepareLayout];
    Check(!DPHidingATab(w) && RowFrame(1, 0).origin.y == 29 && RowFrame(1, 1).origin.y == 59, @"CollapsePinned: Escape closes the bar and leaves the rows under the Pinned line");
    gSmallRows = DPCompactTabRows.on = NO;

    // Unfolded, the pinned rows show under the line.
    [defaults setObject:@[] forKey:@"collapsedPinned"];
    DPCleanHideTab();
    FakeRows(@[ @[ P1, P2, P3, @".sep" ], @[ @".newtab", N, R1, R2, R3 ] ]);
    [layout prepareLayout];
    Check(RowFrame(0, 0).origin.y == 28 && RowFrame(0, 3).origin.y == 139 && RowFrame(1, 0).origin.y == 140, @"CollapsePinned: unfolded pinned rows sit under the Pinned line");

    DPCommandBar.on = DPCommandBarHideTab.on = DPCollapsePinned.on = NO;
    DPCollapsePinned.apply(&DPCollapsePinned);
    [defaults removeObjectForKey:@"collapsedPinned"];
    gFakeHeights = nil;
    gFakeNames = nil;
    gFakeList = nil;
    [w close];
}


// --- 4c. CollapsePinned and the pill that scrolls to the active tab ---
// Dia judges the active tab from the row it cached against the visible rect, without going through any hook.
static NSCollectionViewLayoutAttributes *DiaRow(NSCollectionViewLayout *layout, NSInteger section, NSInteger item) {
    SEL sel = @selector(layoutAttributesForItemAtIndexPath:);
    NSCollectionViewLayoutAttributes *(*dia)(id, SEL, NSIndexPath *) = (void *)DPDiaIMP(objc_getClass(DPDiaTabListLayout), sel);
    return dia(layout, sel, [NSIndexPath indexPathForItem:item inSection:section]);
}

static NSString *PillEdge(NSCollectionViewLayout *layout, NSScrollView *scroll, NSInteger item) {
    NSRect row = DiaRow(layout, 1, item).frame, visible = scroll.documentVisibleRect;
    return NSMaxY(row) <= NSMinY(visible) ? @"top" : NSMinY(row) >= NSMaxY(visible) ? @"bottom" : nil;
}

static void ScrollTo(NSScrollView *scroll, CGFloat y) {
    [scroll.contentView scrollToPoint:NSMakePoint(0, y)];
    [scroll reflectScrolledClipView:scroll.contentView];
}

static BOOL RowsAgree(NSCollectionViewLayout *layout) {
    for (NSInteger section = 0; section < (NSInteger)gFakeHeights.count; section++)
        for (NSInteger item = 0; item < (NSInteger)gFakeHeights[section].count; item++) {
            NSRect dia = DiaRow(layout, section, item).frame, shown = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]].frame;
            if (!NSEqualRects(dia, shown)) return NO;
        }
    return YES;
}

// The main queue is FIFO, so once the sentinel runs, every block queued before it has run too, however long a slow runner stalls.
// A second pass catches a block that queues another, and the spin that follows lets a pass of AppKit's own layout land.
static void Settle(void) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.05];
    for (int pass = 0; pass < 2; pass++) {
        __block BOOL drained = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
        while (!drained && limit.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    [NSRunLoop.mainRunLoop runUntilDate:until];
}

// Each nudge reaches Dia through the main queue, so wait for it by count rather than by time.
static void WaitForScrolls(_TtC7TabList11TabListView *tabList, int count) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
    while (tabList.scrolled < count && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static void TestCollapsePinnedPill(void) {
    NSMutableArray<NSString *> *regular = [NSMutableArray arrayWithObject:@".newtab"];
    for (int i = 1; i <= 20; i++) [regular addObject:[NSString stringWithFormat:@".tab(%08d-0000-0000-0000-000000000000)", i]];
    FakeRows(@[ @[ @".tab(a0000000-0000-0000-0000-000000000000)", @".tab(b0000000-0000-0000-0000-000000000000)", @".tab(c0000000-0000-0000-0000-000000000000)", @".sep" ], regular ]);
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    [defaults setObject:@[ @"space-pill" ] forKey:@"collapsedPinned"];

    DPFakeVisibleWindow *w = [[DPFakeVisibleWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    _TtC7TabList11TabListView *tabList = [[_TtC7TabList11TabListView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    tabList.space = [DPFakeSpace new];
    tabList.space.spaceID = @"space-pill";
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    _TtCC7TabList11TabListView14CollectionView *cv = [[_TtCC7TabList11TabListView14CollectionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 889)];
    _TtC7TabList27TabListCollectionViewLayout *layout = [_TtC7TabList27TabListCollectionViewLayout new];
    DPFakeRowsDS *ds = [DPFakeRowsDS new];
    ds->_impl = [DPFakeRowSource new];
    cv.dataSource = ds;
    cv.collectionViewLayout = layout;
    scroll.documentView = cv;
    [tabList addSubview:scroll];
    [w.contentView addSubview:tabList];
    gFakeList = cv;
    void (^relayout)(void) = ^{
        [layout prepareLayout];
        cv.frame = NSMakeRect(0, 0, 200, layout.collectionViewContentSize.height);
    };

    // Folded: 3 pinned rows of 37 leave the 28 pt line, and the 8th tab (raw row y 408) sits at 325, inside the 400 pt list.
    DPCollapsePinned.on = YES;
    relayout();
    Settle();
    WaitForScrolls(tabList, 1);
    Check(layout.collectionViewContentSize.height == 806 && cv.frame.size.height == 806, @"CollapsePinned: folded list is 83 pt shorter");
    Check(RowsAgree(layout), @"CollapsePinned: Dia's cached rows are where the list shows them when folded");
    Check(PillEdge(layout, scroll, 8) == nil, @"CollapsePinned: no scroll-to-tab pill for an active tab in view under folded pinned rows");
    Check([PillEdge(layout, scroll, 20) isEqual:@"bottom"], @"CollapsePinned: pill shows below for an active tab past the bottom of the list");
    Check(tabList.scrolled == 1, @"CollapsePinned: Dia judges the active tab again once the rows move");
    relayout();
    Settle();
    Check(tabList.scrolled == 1, @"CollapsePinned: a layout that moves nothing leaves Dia's pill alone");
    // A tab with a pull request status is taller and moves the rows below it, after we moved the rows.
    DPPullRequestRepo.install();
    DPPullRequestRepo.on = YES;
    NSView *statusContent = [[objc_getClass(DPDiaTabContentView) alloc] initWithFrame:NSMakeRect(0, 0, 200, 51)];
    NSView *statusSubtitle = [NSView new];
    [statusContent addSubview:statusSubtitle];
    DPSetPRStatus(statusSubtitle, @"00000003-0000-0000-0000-000000000000", @"Approved");
    relayout();
    CGFloat tall = NSHeight(RowFrame(1, 3));
    Check(tall > 37 && RowFrame(1, 2).origin.y == 29 + 37 * 2 && RowFrame(1, 3).origin.y == 29 + 37 * 3 && RowFrame(1, 4).origin.y == NSMaxY(RowFrame(1, 3)), @"CollapsePinned: a taller pull request tab leaves no gap in the folded list");
    Check(RowsAgree(layout) && layout.collectionViewContentSize.height == 806 + tall - 37, @"CollapsePinned: Dia's rows still match the list beside Pull Request Repo");
    Check(PillEdge(layout, scroll, 8) == nil, @"CollapsePinned: a taller pull request tab does not bring the pill back");
    DPResetPRRows();
    DPPullRequestRepo.on = NO;
    relayout();

    ScrollTo(scroll, 406);
    Check(PillEdge(layout, scroll, 20) == nil && [PillEdge(layout, scroll, 8) isEqual:@"top"], @"CollapsePinned: pill shows above once the active tab scrolls off the top");
    ScrollTo(scroll, 0);
    Check(DPCollapsePinned.verify(&DPCollapsePinned) == nil, @"CollapsePinned: verify passes with Dia's rows moved");

    // Dia moved a row of its own after we did: verify says so.
    NSCollectionViewLayoutAttributes *line = DiaRow(layout, 0, 3);
    line.frame = NSOffsetRect(line.frame, 0, 5);
    Check(DPCollapsePinned.verify(&DPCollapsePinned) != nil, @"CollapsePinned: verify notices Dia's rows apart from the list");
    relayout();

    // Dia rebuilds its rows without our hooks: the list still shows them in place.
    SEL prepare = @selector(prepareLayout);
    ((void (*)(id, SEL))DPDiaIMP(objc_getClass(DPDiaTabListLayout), prepare))(layout, prepare);
    Check(RowFrame(0, 3).origin.y == 28 && layout.collectionViewContentSize.height == 806, @"CollapsePinned: rows Dia rebuilt on its own still show under the Pinned line");
    relayout();
    Check(RowsAgree(layout), @"CollapsePinned: our next layout moves Dia's rebuilt rows again");

    // Unfolded the rows sit under the line, pinned ones included, and the 8th tab is at 436, past the bottom.
    [defaults setObject:@[] forKey:@"collapsedPinned"];
    relayout();
    Settle();
    WaitForScrolls(tabList, 2);
    Check(layout.collectionViewContentSize.height == 917 && RowsAgree(layout), @"CollapsePinned: unfolded list shows Dia's rows under the Pinned line");
    Check([PillEdge(layout, scroll, 8) isEqual:@"bottom"] && PillEdge(layout, scroll, 3) == nil, @"CollapsePinned: pill follows the unfolded rows");
    Check(tabList.scrolled == 2, @"CollapsePinned: Dia judges the active tab again when the list unfolds");

    // Off, or paused: Dia's rows are its own again.
    DPCollapsePinned.on = NO;
    DPCollapsePinned.apply(&DPCollapsePinned);
    relayout();
    Settle();
    WaitForScrolls(tabList, 3);
    Check(DiaRow(layout, 0, 0).frame.origin.y == 0 && layout.collectionViewContentSize.height == 889 && RowsAgree(layout), @"CollapsePinned: off leaves Dia's rows and list height stock");
    Check([PillEdge(layout, scroll, 8) isEqual:@"bottom"] && PillEdge(layout, scroll, 3) == nil, @"CollapsePinned: off leaves the pill to Dia");
    Check(tabList.scrolled == 3 && DPCollapsePinned.verify(&DPCollapsePinned) == nil, @"CollapsePinned: Dia judges the active tab again once it is off");

    [defaults removeObjectForKey:@"collapsedPinned"];
    gFakeHeights = nil;
    gFakeNames = nil;
    gFakeList = nil;
    [w close];
}

// --- 5. UndoCloseTab off-tweak monitor guard ---
@interface ArcWebContents : NSObject
@property (nonatomic) NSView *nativeView;
@property (nonatomic) NSInteger visibility;
@property (nonatomic) BOOL hasFocus;
@end
@implementation ArcWebContents
- (void)closeWithForegroundCommitTiming:(NSInteger)timing {}
- (void)setVisibility:(NSInteger)v { _visibility = v; }
- (void)save {}
@end

static void TestUndoCloseTabAndSavePageAs(void) {
    NSUInteger before = gMonitors.count;
    DPUndoCloseTab.install();
    NSEvent *(^undoMonitor)(NSEvent *) = gMonitors[before];

    NSMenu *bar = [NSMenu new];
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:@"History" action:nil keyEquivalent:@""];
    NSMenu *hist = [[NSMenu alloc] initWithTitle:@"History"];
    NSMenuItem *reopen = [[NSMenuItem alloc] initWithTitle:@"Reopen Closed Tab" action:@selector(description) keyEquivalent:@""];
    [hist addItem:reopen];
    top.submenu = hist;
    [bar addItem:top];
    NSApp.mainMenu = bar;

    DPUndoCloseTab.on = YES;
    ArcWebContents *page = [ArcWebContents new];
    [page closeWithForegroundCommitTiming:0];
    // Turn off (e.g. Pause Tweaks) BEFORE pressing Cmd+Z!
    DPUndoCloseTab.on = NO;
    NSEvent *cmdZ = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                    timestamp:0 windowNumber:0 context:nil characters:@"z" charactersIgnoringModifiers:@"z" isARepeat:NO keyCode:6];
    Check(undoMonitor(cmdZ) == cmdZ, @"UndoCloseTab: turning off/pausing before Cmd+Z passes event through without reopening tab");

    // SavePageAs: detached page (nativeView.window == nil) must NOT match when keyWindow/mainWindow are nil!
    NSUInteger saveBefore = gMonitors.count;
    DPSavePageAs.install();
    NSEvent *(^saveMonitor)(NSEvent *) = gMonitors[saveBefore];
    DPSavePageAs.on = YES;
    ArcWebContents *detached = [ArcWebContents new];
    detached.nativeView = [NSView new]; // window == nil!
    detached.visibility = 2;
    NSEvent *cmdSave = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                       timestamp:0 windowNumber:0 context:nil characters:@"z" charactersIgnoringModifiers:@"z" isARepeat:NO keyCode:6];
    Check(NSApp.keyWindow == nil && NSApp.mainWindow == nil && saveMonitor(cmdSave) == cmdSave,
          @"SavePageAs: windowless detached page does not match when no window is key/main");
}

// --- 6. ProfileEmoji DPTopDot_layout self-hiding regression ---
@interface DPFakeIndicator : NSView
@property NSDictionary *dotViews;
@property NSString *focusedSpaceID;
@end
@implementation DPFakeIndicator
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView : NSView
@end
@implementation _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView
- (void)layout {}
@end

static void TestProfileEmoji(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPProfileEmoji.install();
    DPProfileEmoji.on = YES;
    [defaults setObject:@{ @"SPACE-TEST-1" : @"🚀" } forKey:@"profileEmojis"];

    DPFakeIndicator *indicator = [[DPFakeIndicator alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
    _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView *dot = [[_TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
    indicator.dotViews = @{ @"SPACE-TEST-1" : dot };
    indicator.focusedSpaceID = @"SPACE-TEST-1";
    [indicator addSubview:dot];

    // Layout twice with NO native dot subview: label must NOT hide itself on second layout!
    [dot layout];
    [dot layout];
    NSTextField *label = nil;
    for (NSView *sub in dot.subviews) if ([sub isKindOfClass:NSTextField.class]) label = (NSTextField *)sub;
    Check(label != nil && !label.hidden && [label.stringValue isEqualToString:@"🚀"], @"ProfileEmoji: top dot without native subview does not hide its own emoji label");
}

// --- 7. PullRequestRepo author-prefix-of-repo + off-tweak restoration ---
@interface _TtC5ARCUI24FeatheredTruncatingLabel : NSTextField
@end
@implementation _TtC5ARCUI24FeatheredTruncatingLabel
- (void)layout {}
@end

@interface _TtC5ARCUI27FeatheredTransitioningLabel : NSView
@end
@implementation _TtC5ARCUI27FeatheredTransitioningLabel
@end

@interface DPFakePRDelegate : NSObject
@property NSString *currentlyRenderedLiveItem;
@property NSString *tabID;
@end
@implementation DPFakePRDelegate
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakePRVM : NSObject
@property DPFakePRDelegate *delegate;
@end
@implementation DPFakePRVM
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface _TtC5TabUI14TabContentView : NSView
@property DPFakePRVM *viewModel;
@end
@implementation _TtC5TabUI14TabContentView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (void)layout {}
@end

static void TestPullRequestRepo(void) {
    DPPullRequestRepo.install();
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _TtC5TabUI14TabContentView *content = [[_TtC5TabUI14TabContentView alloc] initWithFrame:NSMakeRect(0, 0, 200, 44)];
    DPFakePRVM *vm = [DPFakePRVM new];
    vm.delegate = [DPFakePRDelegate new];
    vm.delegate.tabID = @"11111111-1111-1111-1111-111111111111";
    // Author "jace" is a prefix of repo "jacethings"!
    vm.delegate.currentlyRenderedLiveItem = @".pullRequest(url: https://github.com/org/jacethings/pull/42, author: \"jace\", status: PullRequest.Status.open)";
    content.viewModel = vm;
    _TtC5ARCUI27FeatheredTransitioningLabel *trans = [[_TtC5ARCUI27FeatheredTransitioningLabel alloc] initWithFrame:NSMakeRect(0, 0, 180, 16)];
    _TtC5ARCUI24FeatheredTruncatingLabel *label = [[_TtC5ARCUI24FeatheredTruncatingLabel alloc] initWithFrame:NSMakeRect(0, 0, 180, 16)];
    [trans addSubview:label];
    [content addSubview:trans];
    [w.contentView addSubview:content];

    DPPullRequestRepo.on = YES;
    label.stringValue = @"jace • Approved";
    Check([label.stringValue isEqualToString:@"jacethings #42 · Open • Approved"], @"PullRequestRepo: replaces author with repo when author prefixes repo");

    // Re-setting already-rewritten string must NOT mis-parse "things #42 ..." as review status!
    NSString *rewritten = label.stringValue;
    label.stringValue = rewritten;
    Check([label.stringValue isEqualToString:rewritten], @"PullRequestRepo: does not re-split repo name prefixed by author");

    // Verify must pass even though "jacethings #42..." starts with "jace".
    Check(DPPullRequestRepo.verify(&DPPullRequestRepo) == nil, @"PullRequestRepo: verify passes when author prefixes repo");

    // Turn off on non-visible/minimized window: layout must restore original author string!
    DPPullRequestRepo.on = NO;
    [label layout];
    Check([label.stringValue isEqualToString:@"jace • Approved"], @"PullRequestRepo: off layout restores author subtitle");
}

// --- 8. UnloadTab DPTabOpen & DPPageOf nil safety ---
@interface DPFakeUnloadDelegate : NSObject
@property NSURL *webContentURL;
@property NSString *tabID;
@end
@implementation DPFakeUnloadDelegate
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeUnloadContentVM : NSObject
@property DPFakeUnloadDelegate *delegate;
@end
@implementation DPFakeUnloadContentVM
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeUnloadContentView : NSView
@property DPFakeUnloadContentVM *viewModel;
@end
@implementation DPFakeUnloadContentView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface DPFakeUnloadScriptTab : NSObject
@property NSString *URL;
@property NSString *tabId;
@end
@implementation DPFakeUnloadScriptTab
@end

@interface DPFakeUnloadScriptWindow : NSObject
@property NSArray *appleScriptTabs;
@end
@implementation DPFakeUnloadScriptWindow
@end

@interface DPFakeUnloadAppDelegate : NSObject <NSApplicationDelegate>
@property NSArray *appleScriptWindows;
@end
@implementation DPFakeUnloadAppDelegate
@end

@interface DPFakeTabSelectionState : NSObject
@property NSString *selectionStyle;
@end
@implementation DPFakeTabSelectionState
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

@interface _TtC5TabUI7TabView : NSView
@property DPFakeTabVM *viewModel;
@property NSDictionary *contentViews;
@end
@implementation _TtC5TabUI7TabView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
- (NSMenu *)menuForEvent:(NSEvent *)event { return [NSMenu new]; }
@end

static void TestUnloadTab(void) {
    DPUnloadTab.install();
    DPUnloadTab.on = YES;
    _TtC5TabUI7TabView *tab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 36)];
    NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint modifierFlags:0
                                            timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
    NSMenu *menu = [tab menuForEvent:rightClick];
    Check([menu itemWithTitle:@"Unload Tab"] == nil, @"UnloadTab: nil contentViews safely produces no Unload Tab item");

    // Scripted tab with nil tabId must NOT throw NSInvalidArgumentException in DPPageOf!
    DPFakeUnloadContentView *cv = [DPFakeUnloadContentView new];
    cv.viewModel = [DPFakeUnloadContentVM new];
    cv.viewModel.delegate = [DPFakeUnloadDelegate new];
    cv.viewModel.delegate.webContentURL = [NSURL URLWithString:@"https://unload.example/"];
    cv.viewModel.delegate.tabID = @"22222222-2222-2222-2222-222222222222";
    tab.contentViews = @{ @"main" : cv };
    tab.viewModel = [DPFakeTabVM new];
    tab.viewModel.stateSubject = [DPFakeSubject new];
    tab.viewModel.stateSubject.currentValue = [DPFakeTabSelectionState new]; // selectionStyle == nil

    DPFakeUnloadScriptTab *badTab = [DPFakeUnloadScriptTab new];
    badTab.URL = @"https://unload.example/";
    badTab.tabId = nil;
    DPFakeUnloadScriptWindow *sw = [DPFakeUnloadScriptWindow new];
    sw.appleScriptTabs = @[ badTab ];
    DPFakeUnloadAppDelegate *appDel = [DPFakeUnloadAppDelegate new];
    appDel.appleScriptWindows = @[ sw ];
    id prevDelegate = NSApp.delegate;
    NSApp.delegate = appDel;
    menu = [tab menuForEvent:rightClick];
    NSApp.delegate = prevDelegate;
    Check(menu != nil && [menu itemWithTitle:@"Unload Tab"] == nil, @"UnloadTab: nil tabId in appleScriptTabs does not crash DPPageOf");
}

// --- 9. CompactSidebarHeader off-tweak no-swizzle ---
@interface DPUnrelatedSidebarChild : NSView
@end
@implementation DPUnrelatedSidebarChild
- (void)setFrame:(NSRect)frame { [super setFrame:frame]; }
@end

@interface _TtC10TabSidebar30SidebarContainerViewController : NSViewController
@end
@implementation _TtC10TabSidebar30SidebarContainerViewController
- (void)viewWillLayout {}
@end

@interface _TtC10TabSidebar17SidebarHeaderView : NSView
@end
@implementation _TtC10TabSidebar17SidebarHeaderView
- (void)layout {}
@end

static void TestCompactSidebarHeader(void) {
    DPCompactSidebarHeader.install();
    DPCompactSidebarHeader.on = NO;
    _TtC10TabSidebar30SidebarContainerViewController *sc = [_TtC10TabSidebar30SidebarContainerViewController new];
    sc.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 600)];
    DPUnrelatedSidebarChild *child = [[DPUnrelatedSidebarChild alloc] initWithFrame:NSMakeRect(0, 0, 220, 40)];
    [sc.view addSubview:child];
    IMP beforeIMP = method_getImplementation(class_getInstanceMethod(DPUnrelatedSidebarChild.class, @selector(setFrame:)));
    [sc viewWillLayout];
    IMP afterIMP = method_getImplementation(class_getInstanceMethod(DPUnrelatedSidebarChild.class, @selector(setFrame:)));
    Check(beforeIMP == afterIMP, @"CompactSidebarHeader: off does not swizzle sidebar subview classes");
}

// --- 10. TidyTabs off-tweak & minimized window cleanup ---
@interface _TtC7TabList20TabListSeparatorView : NSView
@end
@implementation _TtC7TabList20TabListSeparatorView
- (void)layout {}
- (void)updateLayer {}
@end

static void TestTidyTabsCleanup(void) {
    DPTidyTabs.install();
    NSWindow *minimized = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 260, 500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSView *sidebar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 500)];
    _TtC10TabSidebar17SidebarHeaderView *header = [[_TtC10TabSidebar17SidebarHeaderView alloc] initWithFrame:NSMakeRect(0, 460, 220, 40)];
    _TtC7TabList11TabListView *list = [[_TtC7TabList11TabListView alloc] initWithFrame:NSMakeRect(0, 0, 220, 460)];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:list.bounds];
    NSView *doc = [[NSView alloc] initWithFrame:list.bounds];
    _TtC7TabList20TabListSeparatorView *sep = [[_TtC7TabList20TabListSeparatorView alloc] initWithFrame:NSMakeRect(0, 200, 220, 20)];
    sep.wantsLayer = YES;
    CALayer *line = [CALayer layer];
    line.frame = NSMakeRect(10, 10, 180, 1);
    [sep.layer addSublayer:line];
    NSButton *closeAll = [NSButton buttonWithTitle:@"Clear" target:nil action:nil];
    closeAll.frame = NSMakeRect(160, 2, 50, 16);
    [sep addSubview:closeAll];
    [doc addSubview:sep];
    scroll.documentView = doc;
    [list addSubview:scroll];
    [sidebar addSubview:header];
    [sidebar addSubview:list];
    [minimized.contentView addSubview:sidebar];

    // Turn on -> attaches tracking area on sidebar and places brush on separator when busy.
    DPTidyTabs.on = YES;
    DPTidySetBusy(YES);
    [list layout];
    [sep layout];
    DPTidyHover *hover = [DPTidyHover forList:list];
    BOOL hasBrush = NO;
    for (NSView *sub in sep.subviews) if ([sub isKindOfClass:DPTidyBrush.class]) hasBrush = YES;
    Check(hover.tracking != nil && [sidebar.trackingAreas containsObject:hover.tracking], @"TidyTabs: attaches hover tracking area when on");
    Check(hasBrush && NSWidth(line.frame) < 180, @"TidyTabs: places separator brush and trims line when on");

    // Turn off while window is non-visible/minimized -> MUST detach tracking area, remove brush, and restore line width!
    DPTidyTabs.on = NO;
    DPTidySetBusy(NO);
    DPTidyTabs.apply(&DPTidyTabs);
    hasBrush = NO;
    for (NSView *sub in sep.subviews) if ([sub isKindOfClass:DPTidyBrush.class]) hasBrush = YES;
    Check(hover.tracking == nil && sidebar.trackingAreas.count == 0, @"TidyTabs: detaches tracking area on minimized window when turned off");
    Check(!hasBrush && fabs(NSWidth(line.frame) - 180) < 0.5, @"TidyTabs: removes brush subview and restores separator line width when off");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
            class_getInstanceMethod(NSUserDefaults.class, @selector(dp_testInitWithSuiteName:)));
        [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] removePersistentDomainForName:DPTestSuiteName()];
        DPHookClass(object_getClass(NSEvent.class), @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)CaptureMonitor);
        TestHideSleepingTabs();
        TestHideTabGroupBackground();
        TestKeepFoldersOpen();
        TestCollapsePinnedWithHideTab();
        TestCollapsePinnedPill();
        TestCollapsePinned();
        TestUndoCloseTabAndSavePageAs();
        TestProfileEmoji();
        TestPullRequestRepo();
        TestUnloadTab();
        TestCompactSidebarHeader();
        TestTidyTabsCleanup();
        [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] removePersistentDomainForName:DPTestSuiteName()];
    }
    if (failures) return 1;
    puts("PASS: all sidebar & tab bug regression checks passed");
    return 0;
}

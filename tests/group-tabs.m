#import "Commands/GroupTabs/GroupTabs.h"
#import "Commands/GroupTabs/Menu.m"
#import "Commands/GroupTabs/Order.m"
#import "Commands/GroupTabs/Grouping.m"

static NSArray<NSView *> *gViews;
static NSWindow *gWindow;
static int gFinds;
NSArray<NSView *> *DPFindViews(const char *className) {
    gFinds++;
    return gViews;
}
id DPSwiftValue(id object, NSString *key) { return [object respondsToSelector:NSSelectorFromString(key)] ? [object valueForKey:key] : nil; }
NSWindow *DPBrowserWindow(id browser) { return gWindow; }
NSArray<NSString *> *DPSelectionIDKeys(id selection) { return @[]; }
NSString *DPIDKey(id value) { return nil; }
void DPEachValue(id collection, void (^visit)(id value)) {}
#import "Commands/GroupTabs/Selection.m"

NSMenuItem *DPMenuItem(NSString *title, void (^action)(void)) { return [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]; }
void DPHookClass(Class cls, SEL sel, IMP replacement) {}
void DPOnLaunch(void (^block)(void)) {}
void DPSetAllGroupsCollapsed(BOOL collapsed) {}
void DPUngroupDomain(void) {}
void DPUngroupAllDomains(void) {}
id DPCommandBrowser(void) { return nil; }
id DPGroupingDelegate(id browser) { return nil; }
NSArray *DPTrackedContents(id browser) { return @[]; }
long long DPSessionOf(id contents) { return 0; }
void DPInstallGroupTabs(void) {}
NSDictionary *DPDefaultGroupTabsShortcut(void) { return @{}; }
BOOL DPShortcutRecording(void) { return NO; }
BOOL DPEventIsKey(NSEvent *event, NSString *key) { return [event.charactersIgnoringModifiers.lowercaseString isEqualToString:key]; }

@interface DPFakeGroup : NSObject
@property NSString *groupId, *title;
@property NSArray *tabSessionIds;
@end
@implementation DPFakeGroup
@end

@interface DPFakeWindow : NSWindow
@property id viewModel;
@end
@implementation DPFakeWindow
@end

@interface DPFakeState : NSObject
@property id stateSubject, currentValue, tabSelectionState, presenter;
@end
@implementation DPFakeState
@end

@interface DPFakeTabListController : NSObject
@property id selectionState;
@end
@implementation DPFakeTabListController
@end

@interface DPFakeTabList : NSView
@property id viewModel;
@end
@implementation DPFakeTabList
@end

static DPFakeWindow *fakeWindow(void) {
    return [[DPFakeWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
}

@interface DPFakeDelegate : NSObject
@property NSMutableArray<NSArray *> *calls;
@property id groups;
@end
@implementation DPFakeDelegate
- (instancetype)init {
    if ((self = [super init])) _calls = [NSMutableArray array];
    return self;
}
- (void)browser:(id)browser createTabGroupWithSessionIds:(NSArray *)ids properties:(id)properties completion:(void (^)(id))completion {
    [_calls addObject:@[ @"create", ids ?: NSNull.null ]];
    completion(nil);
}
- (void)browser:(id)browser addTabsToGroupWithId:(NSString *)group sessionIds:(NSArray *)ids completion:(void (^)(id))completion {
    [_calls addObject:@[ @"add", group ?: NSNull.null, ids ?: NSNull.null ]];
    completion(nil);
}
- (void)browser:(id)browser removeTabsFromGroupWithSessionIds:(NSArray *)ids completion:(void (^)(id))completion {
    [_calls addObject:@[ @"remove", ids ?: NSNull.null ]];
    completion(nil);
}
- (void)browser:(id)browser getAllTabGroupsWithCompletion:(void (^)(NSArray *))completion {
    completion(_groups);
}
@end

@interface DPCountingMenu : NSMenu
@property int reads;
@end
@implementation DPCountingMenu
- (NSArray<NSMenuItem *> *)itemArray {
    _reads++;
    return super.itemArray;
}
- (NSMenuItem *)itemAtIndex:(NSInteger)index {
    _reads++;
    return [super itemAtIndex:index];
}
@end

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static void expectEqual(id got, id want, NSString *what) {
    expect([got isEqual:want] || got == want, [NSString stringWithFormat:@"%@: got %@, want %@", what, got, want]);
}

static NSDictionary *tab(long long session, NSString *url) {
    return @{@"session": @(session), @"domain": DPDomainKey(url), @"url": url};
}

static DPFakeGroup *group(NSString *groupID, NSString *title, NSArray *sessions) {
    DPFakeGroup *group = [DPFakeGroup new];
    group.groupId = groupID;
    group.title = title;
    group.tabSessionIds = sessions;
    return group;
}

// Dia builds the Tabs menu's items in a scratch menu, lets it go, then adds each item to Tabs, which throws if the scratch menu still lives.
static __weak NSMenu *gScratch;
static NSArray<NSMenuItem *> *DPFillScratchMenu(void) {
    NSMenu *scratch = [[NSMenu alloc] initWithTitle:@""];
    gScratch = scratch;
    for (NSString *title in @[ @"Duplicate", @"New Group with 2 Tabs", @"Close Tab" ]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        [scratch addItem:item];
        DPMenuAdded(scratch, item);
    }
    return [scratch.itemArray copy];
}

static BOOL DPMoveIntoTabsMenu(NSArray<NSMenuItem *> *items) {
    NSMenu *tabs = [[NSMenu alloc] initWithTitle:@"Tabs"];
    @try {
        for (NSMenuItem *item in items) [tabs addItem:item];
    } @catch (NSException *exception) {
        return NO;
    }
    return tabs.numberOfItems == (NSInteger)items.count;
}

static void settle(BOOL (^done)(void)) {
    for (int i = 0; i < 30 && !done(); i++) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static NSEvent *key(NSString *characters, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil
                          characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:0];
}

static long long scannedID(NSString *text) {
    NSScanner *scanner = [NSScanner scannerWithString:text];
    long long number = 0;
    return [scanner scanLongLong:&number] && scanner.atEnd ? number : 0;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPGroupTabs.on = YES;
        NSArray<NSMenuItem *> *items = DPFillScratchMenu();
        expect([items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"tag == %ld", (long)DPGroupMenuTag]].count == 1, @"the scratch menu gets Group Tabs by Domain");
        expect(gScratch == nil, @"tracking Dia's scratch menu doesn't keep it alive once Dia lets go of it");
        expect(DPMoveIntoTabsMenu(items), @"Dia can move the scratch menu's items into the Tabs menu");
        NSMenu *context = [[NSMenu alloc] initWithTitle:@""];
        NSMenuItem *newGroup = [[NSMenuItem alloc] initWithTitle:@"New Group with 2 Tabs" action:nil keyEquivalent:@""];
        [context addItem:newGroup];
        DPMenuAdded(context, newGroup);
        DPGroupTabs.on = NO;
        DPApplyGroupTabs(&DPGroupTabs);
        expect(context.numberOfItems == 1 + DPFollowerCount + 1 && [context itemWithTag:DPGroupMenuTag].hidden && [context itemWithTag:DPUngroupAllMenuTag].hidden,
               @"turning Group Tabs off hides its items in a menu Dia still holds");
        DPGroupTabs.on = YES;

        NSArray<NSMenuItem *> *moving = DPFillScratchMenu();
        DPGroupTabs.on = NO;
        NSMenu *tabsMenu = [[NSMenu alloc] initWithTitle:@"Tabs"];
        for (NSMenuItem *item in moving) {
            [tabsMenu addItem:item];
            DPMenuAdded(tabsMenu, item);
        }
        expect([tabsMenu itemWithTag:DPGroupMenuTag].hidden, @"items Dia moves into a menu while the tweak is off arrive hidden");
        DPGroupTabs.on = YES;
        DPApplyGroupTabs(&DPGroupTabs);
        expect(![tabsMenu itemWithTag:DPGroupMenuTag].hidden && ![tabsMenu itemWithTag:DPUngroupAllMenuTag].hidden,
               @"and turning the tweak on shows them, since the menu was tracked on arrival");

        DPGroupTabs.on = NO;
        DPCountingMenu *plain = [[DPCountingMenu alloc] initWithTitle:@""];
        NSMenuItem *other = [[NSMenuItem alloc] initWithTitle:@"Copy" action:nil keyEquivalent:@""];
        [plain addItem:other];
        plain.reads = 0;
        DPMenuAdded(plain, other);
        expect(plain.reads == 0 && ![plain itemWithTag:DPGroupMenuTag], @"a menu nothing of ours is in isn't read while the tweak is off");
        DPGroupTabs.on = YES;

        for (NSString *text in @[ @"", @" ", @"12", @" 12 ", @"12abc", @"abc", @"-5", @"+5", @"0x10", @"1e3", @"1.5", @"1 2", @"- 5", @"--5", @"+-3", @"-", @"+", @"0", @"-0",
                                  @"007", @"\n12\n", @"\v12\f", @"\t\r\n 7", @"12\u00a0", @"\u00a012", @"\u2003 4", @"4\u3000", @"１２", @"٣", @"12\0", @"1_000",
                                  @"99999999999999999999", @"-99999999999999999999", @"9223372036854775807", @"9223372036854775808", @"-9223372036854775808",
                                  @"-9223372036854775809", @"12345678901234567890123456789012345", @"00000000000000000000000000000000012" ])
            expect(DPLongID(text) == scannedID(text), [NSString stringWithFormat:@"DPLongID reads %@ as NSScanner does", [text debugDescription]]);
        expect(DPLongID(@" 42") == 42 && DPLongID(@"-7") == -7 && DPLongID(@"12abc") == 0 && DPLongID(@"99999999999999999999") == LLONG_MAX,
               @"DPLongID keeps its whitespace, junk and overflow rules");
        expect(DPLongID(@42) == 42 && DPLongID(NSNull.null) == 0 && DPLongID(nil) == 0 && DPLongID(@[]) == 0, @"DPLongID reads numbers and shrugs at the rest");

        NSObject *reader = [NSObject new];
        DPFakeWindow *window = fakeWindow();
        gWindow = window;
        expect(!DPCanReadSelection(reader), @"a window with no readable selection can't be read");
        int unreadableFinds = gFinds;
        expect(unreadableFinds > 0 && !DPCanReadSelection(reader) && gFinds > unreadableFinds, @"and is looked at again each time");
        DPFakeState *subject = [DPFakeState new], *value = [DPFakeState new], *model = [DPFakeState new];
        subject.currentValue = value;
        value.tabSelectionState = [NSObject new];
        model.stateSubject = subject;
        window.viewModel = model;
        gFinds = 0;
        expect(DPCanReadSelection(reader) && gFinds == 0, @"a window whose state holds the selection is read without walking its views");

        window = fakeWindow();
        gWindow = window;
        DPFakeTabList *list = [[DPFakeTabList alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [window.contentView addSubview:list];
        DPFakeTabListController *controller = [DPFakeTabListController new];
        DPFakeState *listModel = [DPFakeState new];
        listModel.presenter = controller;
        list.viewModel = listModel;
        gViews = @[ list ];
        expect(!DPCanReadSelection(reader), @"a tab list holding no selection isn't readable");
        controller.selectionState = [NSObject new];
        gFinds = 0;
        expect(DPCanReadSelection(reader) && gFinds == 2, [NSString stringWithFormat:@"a tab list holding one is readable after one walk: %d finds", gFinds]);
        gFinds = 0;
        for (int i = 0; i < 5; i++) expect(DPCanReadSelection(reader), @"and stays readable");
        expect(gFinds == 0, [NSString stringWithFormat:@"a window proven readable isn't walked again: %d finds", gFinds]);
        gWindow = fakeWindow();
        expect(!DPCanReadSelection(reader), @"another window is checked on its own");
        gWindow = nil;
        gViews = nil;

        DPFakeDelegate *delegate = [DPFakeDelegate new];
        NSObject *browser = [NSObject new];
        DPGroupTabs.on = NO;
        DPForgetGroupingUndo();
        DPOfferUndo(delegate, browser, @[ @1 ], nil);
        expect(!DPCanUndoGrouping(), @"no undo is offered while the tweak is off");
        DPGroupTabs.on = YES;

        DPOfferUndo(delegate, browser, @[ @1, @2 ], nil);
        expect(DPCanUndoGrouping(), @"grouping with the tweak on offers an undo");
        DPForgetGroupingUndo();
        expect(!DPCanUndoGrouping(), @"forgetting the undo drops it");

        __block BOOL finished = NO;
        DPRunOps(delegate, browser, @[ @{@"op": @"add", @"group": @"g", @"ids": @[]}, @{@"op": @"add", @"group": @"g"}, @{@"op": @"add", @"ids": @[ @3 ]},
                                       @{@"op": @"add", @"group": @"g", @"ids": @[ @1, @2 ]}, @{@"op": @"create", @"title": @"T", @"ids": @[]} ],
                 0, ^{ finished = YES; });
        settle(^BOOL{ return finished; });
        expect(finished, @"a run of ops with empty or missing ids still finishes");
        expectEqual(delegate.calls, (@[ @[ @"add", @"g", (@[ @1, @2 ]) ] ]), @"ops without ids or a group never reach Dia");
        [delegate.calls removeAllObjects];

        DPFakeDelegate *asked = [DPFakeDelegate new];
        __block NSArray *got = nil;
        asked.groups = @[ @"a" ];
        DPLoadTabGroups(asked, browser, ^(NSArray *groups) { got = groups; });
        settle(^BOOL{ return got != nil; });
        expectEqual(got, (@[ @"a" ]), @"the groups Dia reports come back on the main queue");
        asked.groups = @"nope";
        __block BOOL called = NO;
        DPLoadTabGroups(asked, browser, ^(NSArray *groups) { called = YES; });
        settle(^BOOL{ return called; });
        expect(!called, @"a reply that isn't a list is dropped");

        DPGroupTabs.on = YES;
        DPFakeDelegate *undoer = [DPFakeDelegate new];
        DPOfferUndo(undoer, browser, @[ @4, @5 ], nil);
        expect(DPUndoMonitor != nil, @"an offered undo watches the keyboard");
        expect(DPUndoKey(key(@"a", 0)) != nil && !DPCanUndoGrouping() && !DPUndoMonitor, @"any other key lets the undo go and stops watching");
        DPOfferUndo(undoer, browser, @[ @4, @5 ], nil);
        expect(DPUndoKey(key(@"z", NSEventModifierFlagCommand | NSEventModifierFlagShift)) != nil && !DPCanUndoGrouping(), @"Shift-Command-Z isn't the undo");
        DPOfferUndo(undoer, browser, @[ @4, @5 ], nil);
        expect(DPUndoKey(key(@"z", NSEventModifierFlagCommand)) == nil, @"Command-Z is swallowed");
        settle(^BOOL{ return undoer.calls.count > 0; });
        expectEqual(undoer.calls, (@[ @[ @"remove", (@[ @4, @5 ]) ] ]), @"and takes the tabs back out of their groups");
        expect(!DPCanUndoGrouping() && !DPUndoMonitor, @"after which nothing is left to undo or watch");
        DPOfferUndo(undoer, browser, @[ @6 ], nil);
        DPGroupTabs.on = NO;
        DPApplyGroupTabs(&DPGroupTabs);
        expect(!DPCanUndoGrouping() && !DPUndoMonitor, @"turning the tweak off drops the undo and stops watching");
        DPGroupTabs.on = YES;

        NSMutableArray *now = [(NSArray *)@[ @"a", NSNull.null ] mutableCopy];
        expectEqual(DPPlanMoves((NSArray *)@[ NSNull.null, @"a" ], now, @{@"a": @1}, 0), (@[ @[ @1, @1 ] ]), @"a tab Dia lists without an ID is planned around, not compared as a string");
        now = [(NSArray *)@[ @"b", @"a", NSNull.null ] mutableCopy];
        expectEqual(DPPlanMoves((NSArray *)@[ @"a", @"b", NSNull.null, NSNull.null ], now, @{@"a": @1, @"b": @2}, 0), @[], @"a window that lost a tab since grouping isn't reordered");
        now = [NSMutableArray array];
        expectEqual(DPPlanMoves(@[], now, @{}, 0), @[], @"an empty window plans nothing");
        now = [@[ @"c", @"b", @"a" ] mutableCopy];
        expectEqual(DPPlanMoves(@[ @"a", @"b", @"c" ], now, @{@"a": @1, @"b": @2, @"c": @3}, 0), (@[ @[ @1, @0 ], @[ @2, @1 ] ]), @"tabs move back to where they were");

        expectEqual(DPDomainKey(@"https://www.example.com/a?b"), @"example.com", @"www is dropped");
        expectEqual(DPDomainKey(@"https://Docs.Example.com./"), @"docs.example.com", @"case and trailing dot");
        expectEqual(DPDomainKey(@"https://bücher.example/"), @"xn--bcher-kva.example", @"international hosts group by their ASCII form");
        expectEqual(DPDomainKey(@"file:///tmp/a.html"), nil, @"files have no domain");
        expectEqual(DPDomainKey(@"about:blank"), nil, @"internal pages have no domain");

        NSDictionary *sites = @{
            @"gist.github.com": @"github.com", @"news.bbc.co.uk": @"bbc.co.uk", @"a.b.example.com.au": @"example.com.au",
            @"a.foo.github.io": @"foo.github.io", @"github.io": @"github.io", @"192.168.1.10": @"192.168.1.10",
            @"localhost": @"localhost", @"mail.google.com": @"google.com",
        };
        for (NSString *host in sites) expectEqual(DPRegistrableDomain(host), sites[host], [@"site of " stringByAppendingString:host]);

        NSDictionary *titles = @{
            @"youtube.com": @"YouTube", @"en.wikipedia.org": @"Wikipedia", @"gist.github.com": @"GitHub", @"bbc.co.uk": @"BBC",
            @"example.com": @"Example", @"localhost": @"localhost", @"192.168.1.10": @"192.168.1.10",
        };
        for (NSString *host in titles) expectEqual(DPGroupTitle(host), titles[host], [@"title for " stringByAppendingString:host]);

        NSArray *ops = DPOps(@[ tab(1, @"https://youtube.com/a"), tab(2, @"https://www.youtube.com/b"), tab(3, @"https://github.com") ], @[]);
        expectEqual(ops, (@[ @{@"op": @"create", @"title": @"YouTube", @"ids": @[ @1, @2 ]} ]), @"two tabs of a site make a group named after it");

        ops = DPOps(@[ tab(1, @"https://github.com/a"), tab(2, @"https://github.com/b") ], @[ group(@"g", @"github.com", @[ @1 ]) ]);
        expectEqual(ops, (@[ @{@"op": @"add", @"group": @"g", @"ids": @[ @2 ]} ]), @"a group titled with the host still takes the site's tabs");

        ops = DPOps(@[ tab(1, @"https://youtube.com/a"), tab(2, @"https://youtube.com/b") ], @[ group(@"g", @"YouTube", @[ @1 ]) ]);
        expectEqual(ops, (@[ @{@"op": @"add", @"group": @"g", @"ids": @[ @2 ]} ]), @"a group titled with the site's name takes its tabs");

        ops = DPOps(@[ tab(1, @"https://apple.com"), tab(2, @"https://apple.com/mac"), tab(3, @"https://apple.org"), tab(4, @"https://apple.org/x") ], @[]);
        NSSet *created = [NSSet setWithArray:[ops valueForKey:@"title"]];
        expectEqual(created, ([NSSet setWithArray:@[ @"apple.com", @"apple.org" ]]), @"sites that share a name keep their hosts");

        ops = DPOps(@[ tab(1, @"https://github.com/a"), tab(2, @"https://github.com/b") ], @[ group(@"w", @"Work", @[ @1 ]) ]);
        expectEqual(ops, @[], @"a tab in a group you named stays put");
    }
    if (!failures) printf("all Group Tabs by Domain checks passed\n");
    return failures ? 1 : 0;
}

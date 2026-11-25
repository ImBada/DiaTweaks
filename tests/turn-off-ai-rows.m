#import <AppKit/AppKit.h>
#import "Patches/TurnOffAI/TurnOffAI.h"

#define CHECK(condition, ...) do { if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n  ", __LINE__, #condition); fprintf(stderr, "" __VA_ARGS__); fputc('\n', stderr); exit(1); } } while (0)

DPPatch DPTurnOffAI = { .key = @"turnOffAI" };
static BOOL gThrow;
static NSArray<NSString *> *gRows;
static NSArray<NSString *> *gLongRows;
static NSInteger gMade, gTitleChecks;

BOOL DPIsAITitle(NSString *title) {
    gTitleChecks++;
    return [title hasPrefix:@"AI "];
}

@interface ThrowingTable : NSTableView
@end
@implementation ThrowingTable
- (NSTableRowView *)rowViewAtRow:(NSInteger)row makeIfNecessary:(BOOL)make {
    if (gThrow) [NSException raise:NSInternalInconsistencyException format:@"row view asked for during an update"];
    return [super rowViewAtRow:row makeIfNecessary:make];
}
@end

@interface SidebarSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@end
@implementation SidebarSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return (NSInteger)gRows.count; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return [NSTextField labelWithString:gRows[row]]; }
@end

@interface LongSource : SidebarSource
@end
@implementation LongSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return (NSInteger)gLongRows.count; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    gMade++;
    return [NSTextField labelWithString:gLongRows[row]];
}
@end

static NSIndexSet *AIRows(void) {
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    [gRows enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
        if ([title isEqual:@"Apps"] || [title isEqual:@"Skills"]) [rows addIndex:i];
    }];
    return rows;
}

static NSTableView *MakeTable(Class cls, NSWindow *window, id source) {
    NSTableView *table = [[cls alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"title"]];
    table.dataSource = source;
    table.delegate = source;
    [window.contentView addSubview:table];
    return table;
}

static void Reload(NSTableView *table, BOOL *escaped) {
    @try { [table reloadData]; } @catch (NSException *exception) { if (escaped) *escaped = YES; }
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    Class sidebar = objc_allocateClassPair(SidebarSource.class, "_TtC11Preferences15SidebarListView", 0);
    objc_registerClassPair(sidebar);
    id source = [sidebar new];
    gRows = @[ @"General", @"Apps", @"Profiles", @"Skills", @"Advanced" ];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 400) styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:NO];
    NSTableView *steady = MakeTable(NSTableView.class, window, source), *throwing = MakeTable(ThrowingTable.class, window, source);
    DPInstallAIRows();

    DPTurnOffAI.on = YES;
    Reload(steady, NULL);
    CHECK([steady.hiddenRowIndexes isEqualToIndexSet:AIRows()], "on: the AI rows are hidden");

    BOOL escaped = NO;
    gThrow = YES;
    Reload(throwing, &escaped);
    gThrow = NO;
    CHECK(!throwing.hiddenRowIndexes.count, "a lookup that throws leaves every row shown");

    Reload(throwing, NULL);
    CHECK([throwing.hiddenRowIndexes isEqualToIndexSet:AIRows()], "the next update finds the AI rows again");

    gThrow = YES;
    Reload(throwing, NULL);
    gThrow = NO;
    CHECK(!throwing.hiddenRowIndexes.count, "a throw after hiding unhides what was hidden");

    Reload(throwing, NULL);
    gThrow = YES;
    Reload(throwing, NULL);
    gThrow = NO;
    DPTurnOffAI.on = NO;
    DPApplyAIRows();
    CHECK(!steady.hiddenRowIndexes.count, "off: rows in another table come back after a throw elsewhere");
    CHECK(!throwing.hiddenRowIndexes.count, "off: rows in the throwing table come back");

    Reload(steady, NULL);
    CHECK(!steady.hiddenRowIndexes.count, "off: an update hides nothing");

    DPTurnOffAI.on = YES;
    DPApplyAIRows();
    CHECK([steady.hiddenRowIndexes isEqualToIndexSet:AIRows()] && [throwing.hiddenRowIndexes isEqualToIndexSet:AIRows()], "on again: both tables hide their AI rows");
    CHECK(!escaped, "a row view that throws mid-update is contained, not thrown out of reloadData");
    Class pane = objc_allocateClassPair(LongSource.class, "_TtC11Preferences20PreferencesTableView", 0);
    objc_registerClassPair(pane);
    id longSource = [pane new];
    NSMutableArray *longRows = [NSMutableArray array];
    for (int i = 0; i < 100; i++) [longRows addObject:i == 2 || i == 60 ? [NSString stringWithFormat:@"AI row %d", i] : [NSString stringWithFormat:@"Row %d", i]];
    gLongRows = longRows;
    NSWindow *tall = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 200) styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered defer:NO];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    NSTableView *list = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    [list addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"title"]];
    list.dataSource = longSource;
    list.delegate = longSource;
    scroll.documentView = list;
    [tall.contentView addSubview:scroll];
    void (^show)(void) = ^{
        list.needsLayout = YES;
        [tall.contentView layoutSubtreeIfNeeded];
    };

    DPTurnOffAI.on = YES;
    show();
    gMade = 0;
    for (int i = 0; i < 50; i++) {
        [list reloadData];
        show();
    }
    CHECK(gMade < 50 * 25, "a long list makes the rows on screen, not all 100, on each reload: made %ld", (long)gMade);
    CHECK([list.hiddenRowIndexes isEqualToIndexSet:[NSIndexSet indexSetWithIndex:2]], "a long list hides the AI row on screen once it is laid out");

    [list scrollRowToVisible:60];
    show();
    CHECK([list.hiddenRowIndexes containsIndex:2] && [list.hiddenRowIndexes containsIndex:60] && list.hiddenRowIndexes.count == 2,
          "an AI row that scrolls in is hidden before the next draw");

    [list reloadData];
    [list scrollRowToVisible:0];
    show();
    CHECK([list.hiddenRowIndexes isEqualToIndexSet:[NSIndexSet indexSetWithIndex:2]], "a long list that was reloaded hides the AI rows it shows");
    [list scrollRowToVisible:60];
    show();
    CHECK([list.hiddenRowIndexes containsIndex:60] && list.hiddenRowIndexes.count <= 2, "and the AI rows it scrolls to");

    DPTurnOffAI.on = NO;
    DPApplyAIRows();
    CHECK(!list.hiddenRowIndexes.count, "off: a long list shows every row again");
    [list scrollRowToVisible:60];
    show();
    CHECK(!list.hiddenRowIndexes.count, "off: rows that scroll in stay shown");

    DPTurnOffAI.on = YES;
    [list scrollRowToVisible:0];
    DPApplyAIRows();
    show();
    [list scrollRowToVisible:60];
    show();
    show();
    [list endUpdates];
    CHECK([list.hiddenRowIndexes containsIndex:2] && [list.hiddenRowIndexes containsIndex:60], "on again: both scrolled AI rows are hidden");
    gTitleChecks = 0;
    for (int i = 0; i < 20; i++) [list endUpdates];
    CHECK(gTitleChecks == 0, "DPIsAIRowView memoizes unchanged row views across repeated endUpdates: %ld checks", (long)gTitleChecks);
    CHECK([list.hiddenRowIndexes containsIndex:2] && [list.hiddenRowIndexes containsIndex:60], "off-screen hidden AI rows stay hidden across endUpdates");
    NSTableRowView *someRow = [list rowViewAtRow:58 makeIfNecessary:NO] ?: [list rowViewAtRow:59 makeIfNecessary:NO];
    CHECK(someRow != nil, "a visible non-AI row view exists near row 60");
    [someRow prepareForReuse];
    gTitleChecks = 0;
    [list endUpdates];
    CHECK(gTitleChecks > 0, "prepareForReuse invalidates the row view memo so recycled rows are re-evaluated");
    DPTurnOffAI.on = NO;
    DPApplyAIRows();
    CHECK(!list.hiddenRowIndexes.count, "off again: a long list shows every row");
    puts("PASS: Turn Off AI row lookup survives a throwing table, keeps its latch open, and shows every row when off");
}}

#import <AppKit/AppKit.h>
#import "Patches/TurnOffAI/TurnOffAI.h"

DPPatch DPTurnOffAI = { .key = @"turnOffAI" };
BOOL DPIsAITitle(NSString *title) { return NO; }

#define CHECK(condition, ...) do { if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n  ", __LINE__, #condition); fprintf(stderr, "" __VA_ARGS__); fputc('\n', stderr); exit(1); } } while (0)

static BOOL gThrow;
static NSArray<NSString *> *gRows;

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
    puts("PASS: Turn Off AI row lookup survives a throwing table, keeps its latch open, and shows every row when off");
}}

#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Settings/Settings.h"

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static void DPNoop(id self, SEL _cmd) {}

static int DPTestApplies;
static void DPCountTestApply(DPPatch *patch) { DPTestApplies++; }

static NSMutableDictionary<NSString *, NSToolbarItem *> *DPDiaToolbarItems;

static id DPDiaToolbarItem(id self, SEL _cmd, NSToolbar *toolbar, NSString *identifier, BOOL insert) { return DPDiaToolbarItems[identifier]; }

static NSInteger DPTwoRows(id self, SEL _cmd, NSTableView *table) { return 2; }

static NSView *DPDiaCell(id self, SEL _cmd, NSTableView *table, NSTableColumn *column, NSInteger row) { return [NSTableCellView new]; }

static void DPSelectionChanged(id self, SEL _cmd, NSNotification *note) {}

static void DPSettle(void) {
    for (int i = 0; i < 10; i++) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static NSArray<NSView *> *DPTestRows(void) {
    static NSArray<NSView *> *rows;
    if (!rows) rows = @[ DPLabel(@"A row of text long enough to want the whole width of the page", 13, NSFontWeightRegular, NSColor.labelColor),
                         [NSButton buttonWithTitle:@"Do It" target:nil action:nil] ];
    return rows;
}

static NSMenu *DPTestChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Size"];
    for (NSString *value in @[ @"Small", @"Large" ]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:value action:nil keyEquivalent:@""];
        item.representedObject = value.lowercaseString;
        [menu addItem:item];
    }
    // The last item stands for the nil choice, so a patch without a default has something to select.
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"None" action:nil keyEquivalent:@""]];
    return menu;
}

static NSArray<NSString *> *DPSearchOnly(id self, SEL _cmd, NSToolbar *toolbar) {
    return @[ DPSearchItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, @"PreferencesNavigateBack", @"PreferencesPaneTitle" ];
}

@interface DPWordToolbarDelegate : NSObject <NSToolbarDelegate> {
@public
    uintptr_t paneToolbarItems;
}
@end
@implementation DPWordToolbarDelegate
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return DPSearchOnly(self, _cmd, toolbar); }
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return DPSearchOnly(self, _cmd, toolbar); }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    return DPDiaToolbarItems[identifier];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        expect(objc_getClass(DPDiaSettingsSidebarCell) == Nil, @"Dia's sidebar cell class is missing, as in a Dia that renamed it");

        Class controller = objc_allocateClassPair(NSObject.class, DPDiaSettingsController, 0);
        class_addMethod(controller, @selector(handleBack), (IMP)DPNoop, "v@:");
        class_addMethod(controller, @selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:), (IMP)DPDiaToolbarItem, "@@:@@B");
        class_addMethod(controller, @selector(toolbarAllowedItemIdentifiers:), (IMP)DPSearchOnly, "@@:@");
        class_addMethod(controller, @selector(toolbarDefaultItemIdentifiers:), (IMP)DPSearchOnly, "@@:@");
        objc_registerClassPair(controller);
        IMP back = class_getMethodImplementation(controller, @selector(handleBack));
        IMP item = class_getMethodImplementation(controller, @selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:));

        DPInstallSettings();
        expect(class_getMethodImplementation(controller, @selector(handleBack)) == back, @"without Dia's sidebar, Back stays Dia's");
        expect(class_getMethodImplementation(controller, @selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:)) == item,
               @"without Dia's sidebar, the toolbar stays Dia's");

        Class sidebar = objc_allocateClassPair(NSObject.class, DPDiaSettingsSidebar, 0);
        class_addMethod(sidebar, @selector(numberOfRowsInTableView:), (IMP)DPTwoRows, "q@:@");
        class_addMethod(sidebar, @selector(tableView:viewForTableColumn:row:), (IMP)DPDiaCell, "@@:@@q");
        class_addMethod(sidebar, @selector(tableViewSelectionDidChange:), (IMP)DPSelectionChanged, "v@:@");
        objc_registerClassPair(sidebar);

        DPInstallSettings();
        expect(class_getMethodImplementation(controller, @selector(handleBack)) != back, @"with Dia's sidebar, Back is hooked");

        id delegate = [sidebar new];
        NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"sidebar"];
        [table addTableColumn:column];
        table.dataSource = delegate;
        table.delegate = delegate;
        [table reloadData];
        expect(table.numberOfRows == 5, [NSString stringWithFormat:@"Dia's 2 rows plus divider, Home and Patches: got %ld", (long)table.numberOfRows]);

        NSDictionary<NSNumber *, NSArray *> *links = @{ @3 : @[ @"Home", @"house" ], @4 : @[ @"Patches", @"wand.and.stars" ] };
        for (NSNumber *row in links) {
            NSString *title = links[row][0];
            NSTableCellView *cell = (NSTableCellView *)[delegate tableView:table viewForTableColumn:column row:row.integerValue];
            expect([cell isKindOfClass:NSTableCellView.class], [NSString stringWithFormat:@"%@ gets a cell instead of nil", title]);
            expect([cell.textField.stringValue isEqualToString:title], [NSString stringWithFormat:@"%@'s cell shows its title", title]);
            expect(cell.imageView.image != nil, [NSString stringWithFormat:@"%@'s cell shows its symbol", title]);
            expect([cell.textField isDescendantOf:cell] && [cell.imageView isDescendantOf:cell],
                   [NSString stringWithFormat:@"%@'s label and symbol are inside the cell", title]);
            expect([cell.identifier isEqualToString:[@"DiaPatchesCell." stringByAppendingString:title]],
                   [NSString stringWithFormat:@"%@'s cell can be reused", title]);
        }
        NSView *dia = [delegate tableView:table viewForTableColumn:column row:0];
        expect([dia isKindOfClass:NSTableCellView.class] && ![dia.identifier hasPrefix:@"DiaPatches"], @"Dia's own rows still come from Dia");

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        NSTableView *shown = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        [shown addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"sidebar"]];
        shown.dataSource = delegate;
        shown.delegate = delegate;
        scroll.documentView = shown;
        NSViewController *sidebarController = [NSViewController new];
        sidebarController.view = scroll;
        NSViewController *detailController = [NSViewController new];
        detailController.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        NSSplitViewController *split = [NSSplitViewController new];
        [split addSplitViewItem:[NSSplitViewItem sidebarWithViewController:sidebarController]];
        [split addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:detailController]];
        NSWindow *window = [NSWindow windowWithContentViewController:split];
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"DPSidebarFallback"];
        id owner = [controller new];
        toolbar.delegate = owner;
        window.toolbar = toolbar;
        [shown reloadData];
        NSTableColumn *shownColumn = shown.tableColumns.firstObject;
        [delegate tableView:shown viewForTableColumn:shownColumn row:4];
        DPSettle();
        Class settingsClass = NSClassFromString(@"DPSettings");
        id (*forTable)(Class, SEL, id) = (void *)objc_msgSend;
        id settings = forTable(settingsClass, NSSelectorFromString(@"forTable:"), shown);
        expect([[settings valueForKey:@"patches"] superview] != nil, @"drawing the Patches row sets its pane up in Dia's detail view");

        __block int prepared = 0;
        Method prepare = class_getInstanceMethod(settingsClass, NSSelectorFromString(@"preparePane:"));
        IMP prepareIMP = method_getImplementation(prepare);
        method_setImplementation(prepare, imp_implementationWithBlock(^(id settings, id pane) {
            prepared++;
            ((void (*)(id, SEL, id))prepareIMP)(settings, NSSelectorFromString(@"preparePane:"), pane);
        }));
        for (int i = 0; i < 5; i++) [delegate tableView:shown viewForTableColumn:shownColumn row:4];
        DPSettle();
        expect(prepared == 0, [NSString stringWithFormat:@"drawing a row whose pane is already set up queues nothing: %d prepares", prepared]);
        method_setImplementation(prepare, prepareIMP);

        expect([owner toolbar:toolbar itemForItemIdentifier:DPSearchItemIdentifier willBeInsertedIntoToolbar:NO] == nil, @"no search item is offered before Patches opens");
        [shown selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
        expect([owner toolbar:toolbar itemForItemIdentifier:DPSearchItemIdentifier willBeInsertedIntoToolbar:NO] != nil, @"opening Patches offers its search item to the toolbar");
        [shown selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        expect([owner toolbar:toolbar itemForItemIdentifier:DPSearchItemIdentifier willBeInsertedIntoToolbar:NO] == nil,
               @"leaving Patches stops the toolbar holding on to its search item");

        NSToolbarItem *backItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"PreferencesNavigateBack"];
        NSToolbarItem *titleItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"PreferencesPaneTitle"];
        NSTextField *label = [NSTextField labelWithString:@"General"];
        titleItem.view = label;
        backItem.autovalidates = NO;
        backItem.enabled = NO;
        DPDiaToolbarItems = [@{ backItem.itemIdentifier : backItem, titleItem.itemIdentifier : titleItem } mutableCopy];
        [toolbar insertItemWithItemIdentifier:backItem.itemIdentifier atIndex:0];
        [toolbar insertItemWithItemIdentifier:titleItem.itemIdentifier atIndex:1];

        [shown selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
        expect([label.stringValue isEqualToString:@"Patches"], @"opening Patches titles the window Patches");
        DPPaneView *patches = [settings valueForKey:@"patches"];
        ((DPOverviewView *)patches.content).open(@"Hide Toolbar", [NSView new]);
        expect([label.stringValue isEqualToString:@"Hide Toolbar"] && backItem.enabled, @"a tweak page shows its own title and turns Back on");
        [shown selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        expect([label.stringValue isEqualToString:@"General"], [NSString stringWithFormat:@"leaving a tweak page gives Dia's title back: %@", label.stringValue]);
        expect(!backItem.enabled && !patches.showsPage, @"leaving a tweak page gives Dia's Back state back");

        // A tweak page's rows are laid out by DPFullRow: the content spans the row between its 12pt insets, and no
        // trailing spacer (which could only be given a negative width) is installed beside it.
        static DPPatch testChild = {
            .key = @"sidebarFallbackChild", .title = @"Child", .detail = @"An option under the test tweak.",
            .requires = @"sidebarFallbackTest", .defaultOn = YES,
        };
        static DPPatch testPatch = {
            .key = @"sidebarFallbackTest", .title = @"Test Tweak", .detail = @"Rows and a choice menu.",
            .section = @"Test", .defaultOn = YES, .choice = @"sidebarFallbackChoice",
            .choices = DPTestChoices, .rows = DPTestRows,
        };
        static DPPatch *testPatches[] = { &testChild, &testPatch };
        DPPatches = testPatches;
        DPPatchCount = 2;
        // The suite may run twice against one defaults domain.
        [DPSettingsDefaults() removeObjectForKey:testPatch.choice];
        [DPSettingsDefaults() removeObjectForKey:testPatch.key];

        DPPageView *tweakPage = [[DPPageView alloc] initWithPatch:&testPatch];
        NSWindow *pageWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 900)
                                                          styleMask:NSWindowStyleMaskBorderless
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
        pageWindow.contentView = tweakPage;
        [tweakPage layoutSubtreeIfNeeded];
        DPSettle();
        [tweakPage layoutSubtreeIfNeeded];
        expect(!tweakPage.hasAmbiguousLayout, @"full-width tweak rows never leave ambiguous Auto Layout constraints");
        NSArray<NSView *> *content = testPatch.rows();
        for (NSView *view in content) {
            NSView *row = view.superview;
            NSRect aligned = [view alignmentRectForFrame:view.frame];  // A text field's cell insets are outside this.
            expect(row.subviews.count == 1, @"a full-width row holds only its content");
            expect(NSMinX(aligned) == 12 && NSWidth(aligned) == NSWidth(row.frame) - 24,
                   [NSString stringWithFormat:@"a full-width row spans 12pt insets: %@ of %@", NSStringFromRect(aligned), NSStringFromRect(row.frame)]);
        }

        NSPopUpButton *picker = (NSPopUpButton *)DPFindView(tweakPage, ^BOOL(NSView *v) { return [v isKindOfClass:NSPopUpButton.class]; });
        expect([picker.selectedItem.title isEqual:@"None"],
               [NSString stringWithFormat:@"a choice whose default is nil selects the item without a representedObject: %@", picker.selectedItem.title]);
        DPSetChoice(&testPatch, @"large");
        BOOL raised = NO;
        @try { DPSetChoice(&testPatch, nil); DPSetChoice(&testPatch, (NSString *)@42); } @catch (NSException *exception) { raised = YES; }
        expect(!raised && [DPChoice(&testPatch) isEqual:@"large"], @"a nil or non-string choice leaves the saved choice alone without throwing");
        [tweakPage sync];
        [picker selectItemWithTitle:@"None"];
        [NSApp sendAction:picker.action to:picker.target from:picker];
        expect([picker.selectedItem.title isEqual:@"Large"] && [DPChoice(&testPatch) isEqual:@"large"],
               @"picking an item without a string representedObject snaps back to the active choice");

        // Raw Swift ivar hardening: unmapped words, IEEE-754 floats, heap C buffers, and non-arrays never crash DPRemoveDiaPaneItems.
        DPWordToolbarDelegate *wordDelegate = [DPWordToolbarDelegate new];
        NSToolbar *wordToolbar = [[NSToolbar alloc] initWithIdentifier:@"DPWordToolbar"];
        wordToolbar.delegate = wordDelegate;
        NSViewController *wordSide = [NSViewController new], *wordDetail = [NSViewController new];
        NSTableView *wordTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        [wordTable addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"sidebar"]];
        wordTable.dataSource = delegate;
        wordTable.delegate = delegate;
        NSScrollView *wordScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        wordScroll.documentView = wordTable;
        wordSide.view = wordScroll;
        wordDetail.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        NSSplitViewController *wordSplit = [NSSplitViewController new];
        [wordSplit addSplitViewItem:[NSSplitViewItem sidebarWithViewController:wordSide]];
        [wordSplit addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:wordDetail]];
        NSWindow *wordWin = [NSWindow windowWithContentViewController:wordSplit];
        wordWin.toolbar = wordToolbar;
        [wordTable reloadData];
        char nonObjectHeap[64];
        memset(nonObjectHeap, 'A', sizeof nonObjectHeap);
        uintptr_t hazards[] = { 0, 0x8000000000000001ULL, 0x100000008ULL, 0x3ff0000000000000ULL, (uintptr_t)nonObjectHeap };
        for (size_t i = 0; i < sizeof hazards / sizeof *hazards; i++) {
            wordDelegate->paneToolbarItems = hazards[i];
            [wordTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            [wordTable selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];
        }
        expect(YES, @"non-object words and unmapped pointers in paneToolbarItems never crash Settings");

        // Safe Mode keeps switches usable so a crashing tweak can be turned off without running apply, while disabling live page controls.
        DPTestApplies = 0;
        testPatch.apply = DPCountTestApply;
        testPatch.on = NO;
        testChild.on = NO;
        DPSafeMode = 1;
        DPSetPatch(&testPatch, YES, YES);
        expect(testPatch.on && DPSavedOn(&testPatch) && DPTestApplies == 0, @"a switch flipped in Safe Mode saves without running apply");
        [tweakPage sync];
        DPPatchSwitch *testSwitch = (DPPatchSwitch *)DPFindView(tweakPage, ^BOOL(NSView *v) {
            return [v isKindOfClass:DPPatchSwitch.class] && ((DPPatchSwitch *)v).patch == &testPatch;
        });
        expect(testSwitch.enabled && testSwitch.state == NSControlStateValueOn && !picker.enabled,
               @"Safe Mode keeps switches usable while disabling live choice pickers");
        DPSetChoice(&testPatch, @"small");
        expect([DPChoice(&testPatch) isEqual:@"small"] && DPTestApplies == 0, @"Safe Mode choice saves without running apply");
        DPSafeMode = 0;
        testPatch.apply = NULL;
        DPSetPatch(&testPatch, NO, YES);

        // A pane nobody can see only notes that it is out of date, and catches up when it or its ancestor is shown again.
        DPOverviewView *overview = [[DPOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 560, 600)];
        DPPaneView *hiddenPane = [[DPPaneView alloc] initWithTitle:@"Patches" content:overview];
        NSWindow *paneWindow = [NSWindow windowWithContentViewController:[NSViewController new]];
        NSView *paneHolder = [[NSView alloc] initWithFrame:paneWindow.contentView.bounds];
        [paneWindow.contentView addSubview:paneHolder];
        [paneHolder addSubview:hiddenPane];
        hiddenPane.frame = paneHolder.bounds;
        hiddenPane.hidden = YES;
        __block int paneSyncs = 0;
        Method syncWithQuery = class_getInstanceMethod(DPOverviewView.class, @selector(syncWithQuery:));
        IMP syncIMP = method_getImplementation(syncWithQuery);
        method_setImplementation(syncWithQuery, imp_implementationWithBlock(^(DPOverviewView *view, NSString *query) {
            if (view == overview) paneSyncs++;
            ((void (*)(id, SEL, NSString *))syncIMP)(view, @selector(syncWithQuery:), query);
        }));
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(paneSyncs == 0, [NSString stringWithFormat:@"a hidden pane skips the rebuild: %d syncs", paneSyncs]);
        hiddenPane.hidden = NO;
        expect(paneSyncs == 1, @"showing the pane runs the rebuild it deferred");
        paneHolder.hidden = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(paneSyncs == 1, @"a pane under a hidden ancestor also skips the rebuild");
        paneHolder.hidden = NO;
        expect(paneSyncs == 2, @"unhiding the ancestor flushes the deferred rebuild");
        hiddenPane.hidden = YES;
        hiddenPane.hidden = NO;
        expect(paneSyncs == 2, @"a pane that is already up to date is not rebuilt again");
        method_setImplementation(syncWithQuery, syncIMP);
        [DPSettingsDefaults() removeObjectForKey:testPatch.choice];
        [DPSettingsDefaults() removeObjectForKey:testPatch.key];

        if (failures) printf("%d failures\n", failures);
        else printf("settings sidebar fallback: ok\n");
        return failures ? 1 : 0;
    }
}

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

static NSMutableDictionary<NSString *, NSToolbarItem *> *DPDiaToolbarItems;

static id DPDiaToolbarItem(id self, SEL _cmd, NSToolbar *toolbar, NSString *identifier, BOOL insert) { return DPDiaToolbarItems[identifier]; }

static NSInteger DPTwoRows(id self, SEL _cmd, NSTableView *table) { return 2; }

static NSView *DPDiaCell(id self, SEL _cmd, NSTableView *table, NSTableColumn *column, NSInteger row) { return [NSTableCellView new]; }

static void DPSelectionChanged(id self, SEL _cmd, NSNotification *note) {}

static void DPSettle(void) {
    for (int i = 0; i < 10; i++) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static NSArray<NSString *> *DPSearchOnly(id self, SEL _cmd, NSToolbar *toolbar) {
    return @[ DPSearchItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, @"PreferencesNavigateBack", @"PreferencesPaneTitle" ];
}

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

        if (failures) printf("%d failures\n", failures);
        else printf("settings sidebar fallback: ok\n");
        return failures ? 1 : 0;
    }
}

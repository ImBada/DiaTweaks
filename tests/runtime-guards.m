#import <AppKit/AppKit.h>
#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Settings/Settings.h"

void DPInstallPreviews(void) {}
void DPSetHint(NSView *view, NSString *text) {}
NSString *DPHintOf(NSView *view) { return nil; }
BOOL DPShortcutRecording(void) { return NO; }
BOOL DPEventIsKey(NSEvent *event, NSString *key) { return [event.charactersIgnoringModifiers.lowercaseString isEqualToString:key]; }
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
NSToolbarItemIdentifier const DPSearchItemIdentifier = @"DiaPatchesSearch";

@implementation DPPaneView
- (instancetype)initWithTitle:(NSString *)title content:(NSView<DPPaneContent> *)content { return [super initWithFrame:NSZeroRect]; }
- (void)goBack {}
- (void)reset {}
@end
@implementation DPHomeView
- (void)refresh {}
@end
@implementation DPOverviewView
- (void)syncWithQuery:(NSString *)query {}
@end

// Stubs for GroupTabs menu/grouping isolation.
id DPCommandBrowser(void) { return nil; }
NSWindow *DPBrowserWindow(id browser) { return nil; }
id DPBrowserOfWindow(NSWindow *window) { return nil; }
id DPBrowserOfContents(id contents) { return nil; }
id DPGroupingDelegate(id browser) { return nil; }
NSArray *DPTrackedContents(id browser) { return @[]; }
long long DPSessionOf(id contents) { return 0; }
long long DPActiveSession(id browser) { return 0; }
NSSet<NSNumber *> *DPSelectedSessions(id browser) { return nil; }
BOOL DPCanReadSelection(id browser) { return YES; }
void DPSetAllGroupsCollapsed(BOOL collapsed) {}
void DPUngroupDomain(void) {}
void DPUngroupAllDomains(void) {}
void DPInstallGroupTabs(void) {}
void DPInstallGroupTabsShortcut(void) {}
NSDictionary *DPDefaultGroupTabsShortcut(void) { return nil; }
DPPatch DPGroupTabsMergeSubdomains = { .key = @"groupTabsMergeSubdomains" };
DPPatch *const *DPPatches;
NSUInteger DPPatchCount;

#import "StdPatch/TypedURL.m"
#import "StdPatch/Hide.m"
#import "StdPatch/HideHosts.m"
#import "Settings/Settings.m"
#import "Commands/GroupTabs/Order.m"
#import "Commands/GroupTabs/Grouping.m"
#import "Commands/GroupTabs/Menu.m"

@interface DPFakeToolbarDelegate : NSObject <NSToolbarDelegate> {
@public
    id paneToolbarItems;
}
@end
@implementation DPFakeToolbarDelegate
@end

static int failures;
static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

@interface DPZeroRowsTable : NSTableView
@property NSInteger fakeRows;
@end
@implementation DPZeroRowsTable
- (NSInteger)numberOfRows { return self.fakeRows; }
@end

@interface DPFakeDelegate : NSObject
@property int ungroupCalls;
- (void)browser:(id)browser removeTabsFromGroupWithSessionIds:(NSArray *)ids completion:(void (^)(id))done;
@end
@implementation DPFakeDelegate
- (void)browser:(id)browser removeTabsFromGroupWithSessionIds:(NSArray *)ids completion:(void (^)(id))done { self.ungroupCalls++; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // 1. Views.m NULL guards & DPOverride nil guards.
        expect(DPFindViews(NULL).count == 0, @"DPFindViews(NULL) returns empty without crashing");
        expect(DPSubview([NSView new], NULL) == nil, @"DPSubview(..., NULL) returns nil");
        expect(!DPIsKind([NSView new], NULL), @"DPIsKind(..., NULL) returns NO");
        expect(DPIvar([NSView new], NULL) == NULL, @"DPIvar(..., NULL) returns NULL");
        static char kKey;
        NSObject *obj = [NSObject new];
        DPOverride(obj, &kKey, nil, @"ours");
        DPOverride(obj, &kKey, @"dia", nil);
        expect(DPGet(obj, &kKey) == nil, @"DPOverride ignores nil values safely");

        // 2. TypedURL.m rejects non-ASCII Unicode digits in ports and IPv4.
        expect(DPAddressURL(@"example.com:8080") != nil, @"ASCII port parses");
        expect(DPAddressURL(@"example.com:\u0661\u0662\u0663") == nil, @"Arabic-Indic port digits are rejected");
        expect(DPAddressURL(@"\u0661.\u0662.\u0663.\u0664") == nil, @"Arabic-Indic IPv4 digits are rejected");

        // 3. Settings.m fitDivider does not crash with negative row index when numberOfRows < DPOurRowCount.
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 500)];
        DPZeroRowsTable *table = [[DPZeroRowsTable alloc] initWithFrame:NSMakeRect(0, 0, 200, 500)];
        table.rowHeight = 28;
        table.fakeRows = 6;
        scroll.documentView = table;
        DPSettings *settings = [DPSettings forTable:table];
        expect([settings fittedDividerHeight] > DPDividerMinHeight, @"divider grows to fill sidebar");
        table.fakeRows = 0;
        [settings fitDivider];
        expect(YES, @"fitDivider handles numberOfRows < DPOurRowCount without negative NSIndexSet crash");

        // 4. Settings.m borrowBack: preserves original disabled state across repeated borrow calls, and allowResizing: restores zoom button.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        NSViewController *plainVC = [NSViewController new];
        plainVC.view = scroll;
        window.contentViewController = plainVC;
        DPPaneView *testPane = [[DPPaneView alloc] initWithTitle:@"Test" content:[DPHomeView new]];
        [settings preparePane:testPane];
        expect(YES, @"preparePane: ignores non-NSSplitViewController contentViewController safely");
        settings.shown = testPane;
        settings.originalTitle = nil;
        settings.shownTitle = @"Test";
        NSTextField *titleField = [NSTextField labelWithString:@"Test"];
        settings.title = titleField;
        [settings closeShownPane];
        expect([titleField.stringValue isEqualToString:@"Test"], @"closeShownPane does not throw when originalTitle is nil");
        [window standardWindowButton:NSWindowZoomButton].enabled = YES;
        [settings allowResizing:YES];
        expect(![window standardWindowButton:NSWindowZoomButton].enabled, @"allowResizing:YES disables zoom button");
        [settings allowResizing:NO];
        expect([window standardWindowButton:NSWindowZoomButton].enabled, @"allowResizing:NO restores zoom button enabled state");
        settings.backWasEnabled = NO;
        settings.backBorrowed = NO;
        [settings borrowBack:YES];
        [settings borrowBack:YES];
        expect(settings.backBorrowed && !settings.backWasEnabled, @"repeated borrowBack:YES preserves original backWasEnabled");
        [settings borrowBack:NO];
        expect(!settings.backBorrowed, @"borrowBack:NO clears backBorrowed");

        // 4b. HideHosts.m off-tweak invariant: DPSidebar_viewDidLayout must not burn DPMayAdjust budget when no hides are active.
        Class footerCls = objc_allocateClassPair(NSView.class, DPDiaSidebarFooter, 0);
        objc_registerClassPair(footerCls);
        Class sidebarCtrlCls = objc_allocateClassPair(NSViewController.class, DPDiaSidebarController, 0);
        objc_registerClassPair(sidebarCtrlCls);
        DPInstallHides();
        DPInstallHideHosts();
        NSView *flippedSidebar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        NSView *footer = [[footerCls alloc] initWithFrame:NSMakeRect(0, 360, 200, 40)];
        [flippedSidebar addSubview:footer];
        NSViewController *sidebarCtrl = [sidebarCtrlCls new];
        sidebarCtrl.view = flippedSidebar;
        // Override isFlipped via a subclass so DPSidebar_viewDidLayout exercises the flipped path.
        Class flippedCls = objc_allocateClassPair(NSView.class, "DPTestFlippedSidebar", 0);
        class_addMethod(flippedCls, @selector(isFlipped), imp_implementationWithBlock(^BOOL(id s) { return YES; }), "c@:");
        objc_registerClassPair(flippedCls);
        NSView *flipped = [[flippedCls alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
        [flipped addSubview:footer];
        sidebarCtrl.view = flipped;
        for (int i = 0; i < 20; i++) [sidebarCtrl viewDidLayout];
        expect(DPMayAdjust(footer), @"20 off-tweak sidebar layouts do not exhaust DPMayAdjust(footer)");

        // 5. GroupTabs Order.m handles missing appleScriptWindows and empty places safely.
        expect(DPTabPlaces(@{ @1 : @"https://example.com" }) == nil, @"DPTabPlaces handles delegate without appleScriptWindows");
        DPRestorePlaces(nil, nil, @{ @"sessions" : @{}, @"order" : @[] });
        __block BOOL moveFailed = NO;
        DPMoveTab(nil, nil, nil, 0, nil, ^{ moveFailed = YES; });
        expect(moveFailed, @"DPMoveTab fails cleanly on nil args");

        // 6. GroupTabs Grouping.m DPOfferUndo does not invoke delegate with nil browser after browser deallocs.
        DPFakeDelegate *delegate = [DPFakeDelegate new];
        DPGroupTabs.on = YES;
        @autoreleasepool {
            NSObject *ephemeralBrowser = [NSObject new];
            DPOfferUndo(delegate, ephemeralBrowser, @[@1], nil);
        }
        expect(DPCanUndoGrouping(), @"undo is armed");
        void (^undo)(void) = DPUndoGrouping;
        DPUndoGrouping = nil;
        undo();
        expect(delegate.ungroupCalls == 0, @"DPOfferUndo skips call when weak browser has deallocated");

        // 7. GroupTabs Menu.m hides existing items in reused menus and skips injecting into new menus while off.
        DPInstallGroupMenus();
        DPGroupTabs.on = YES;
        NSMenu *reused = [[NSMenu alloc] initWithTitle:@"Tab"];
        [reused addItemWithTitle:@"New Group with 1 Tab" action:nil keyEquivalent:@""];
        NSMenuItem *groupItem = [reused itemWithTag:DPGroupMenuTag];
        expect(groupItem && !groupItem.hidden, @"Menu.m inserts visible Group Tabs item when on");

        DPGroupTabs.on = NO;
        DPApplyGroupTabs(&DPGroupTabs);
        [reused addItemWithTitle:@"Close Tab" action:nil keyEquivalent:@""];
        expect(groupItem.hidden, @"reused context menu hides Group Tabs item when tweak is off");
        for (NSInteger i = 0; i < DPFollowerCount; i++)
            expect([reused itemWithTag:DPFollowerTags[i]].hidden, @"reused context menu hides follower items when tweak is off");

        NSMenu *fresh = [[NSMenu alloc] initWithTitle:@"Fresh"];
        [fresh addItemWithTitle:@"New Group with 2 Tabs" action:nil keyEquivalent:@""];
        expect([fresh itemWithTag:DPGroupMenuTag] == nil, @"Menu.m does not mutate fresh context menus while off");

        // 8. Settings.m DPRemoveDiaPaneItems handles non-array/missing KVC keys and DPSettings dealloc removes NSNotificationCenter observers.
        NSToolbar *testToolbar = [[NSToolbar alloc] initWithIdentifier:@"DPTestToolbar"];
        DPFakeToolbarDelegate *tbDelegate = [DPFakeToolbarDelegate new];
        testToolbar.delegate = tbDelegate;
        tbDelegate->paneToolbarItems = @"not-an-array";
        DPRemoveDiaPaneItems(testToolbar);
        tbDelegate->paneToolbarItems = @[ [NSObject new] ];
        DPRemoveDiaPaneItems(testToolbar);
        expect(YES, @"DPRemoveDiaPaneItems handles non-array and missing itemIdentifier KVC key safely");

        NSWindow *tempWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered defer:NO];
        __weak DPSettings *weakSettings = nil;
        NSClipView *tempClip = nil;
        @autoreleasepool {
            NSScrollView *tempScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
            DPZeroRowsTable *tempTable = [[DPZeroRowsTable alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
            tempTable.fakeRows = 5;
            tempScroll.documentView = tempTable;
            tempWin.contentView = tempScroll;
            tempClip = tempScroll.contentView;
            DPSettings *s = [DPSettings forTable:tempTable];
            weakSettings = s;
            [s fittedDividerHeight]; // Registers NSNotificationCenter observer on tempClip.
            DPSet(tempTable, &DPSettingsKey, nil);
            tempWin.contentView = [NSView new];
        }
        expect(weakSettings == nil, @"DPSettings deallocates cleanly");
        [NSNotificationCenter.defaultCenter postNotificationName:NSViewBoundsDidChangeNotification object:tempClip];
        expect(YES, @"posting NSViewBoundsDidChangeNotification after DPSettings dealloc does not crash");
    }
    if (!failures) printf("all runtime guard checks passed\n");
    return failures ? 1 : 0;
}

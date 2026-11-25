#import <AppKit/AppKit.h>
#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import "Settings/Settings.h"
#import <dlfcn.h>

void DPInstallPreviews(void) {}
void DPSetHint(NSView *view, NSString *text) {}
NSString *DPHintOf(NSView *view) { return nil; }
BOOL DPShortcutRecording(void) { return NO; }
BOOL DPEventIsKey(NSEvent *event, NSString *key) { return [event.charactersIgnoringModifiers.lowercaseString isEqualToString:key]; }
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
NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
BOOL DPPauseSaved(void) { return NO; }
NSUInteger DPLocalLoad(void) { return 0; }
DPPatch **DPLocalPatches(void) { return NULL; }
void DPLocalRepairLinks(void) {}

#import "StdPatch/Patch.m"
#import "StdPatch/TypedURL.m"
#import "StdPatch/Hide.m"
#import "StdPatch/HideHosts.m"
#import "Settings/Settings.m"
#import "Commands/GroupTabs/Order.m"
#import "Commands/GroupTabs/Grouping.m"
#import "Commands/GroupTabs/Menu.m"
#import "Patches/HideNewTabLogo/HideNewTabLogo.m"

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

static int runtimeLookups;
static char aliasNames[32][48];
static Class aliasClasses[32];
static int aliasCount;

// Defined here so every lookup by name from this executable, including DPClassNamed's, is counted and can be pointed at a class of the test's choosing.
Class objc_getClass(const char *name) {
    static Class (*lookUp)(const char *);
    if (!lookUp) lookUp = dlsym(RTLD_NEXT, "objc_getClass");
    runtimeLookups++;
    for (int i = 0; i < aliasCount; i++)
        if (!strcmp(aliasNames[i], name)) return aliasClasses[i];
    return lookUp(name);
}

// The runtime resolves "Module.Class" to the Swift class "_TtC<len>Module<len>Class".
static Class registerClass(const char *name, Class superclass) {
    Class cls = objc_lookUpClass(name);
    if (cls) return cls;
    cls = objc_allocateClassPair(superclass, name, 0);
    objc_registerClassPair(cls);
    return cls;
}

static BOOL answeredFromCache(id object, const char *lookup) {
    if (!DPIsKind(object, lookup)) return NO;
    int before = runtimeLookups;
    return DPIsKind(object, lookup) && runtimeLookups == before;
}

static BOOL cachesSwiftClass(const char *lookup, const char *mangled) {
    return answeredFromCache([registerClass(mangled, NSObject.class) new], lookup);
}

static unsigned classSlot(const char *name) {
    uint32_t hash = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)name; *p; p++) hash = (hash ^ *p) * 16777619u;
    return hash & 255;
}

// Points a name that shares the lookup's cache slot at the class, so the class sits in that slot when the lookup comes.
static BOOL cacheInSlotOf(const char *lookup, Class cls, id object) {
    for (int n = 0; n < 10000; n++) {
        char alias[48];
        snprintf(alias, sizeof alias, "Alias%d", n);
        if (classSlot(alias) != classSlot(lookup)) continue;
        int row = 0;
        while (row < aliasCount && strcmp(aliasNames[row], alias)) row++;
        if (row == aliasCount) aliasCount++;
        strlcpy(aliasNames[row], alias, sizeof aliasNames[row]);
        aliasClasses[row] = cls;
        return DPIsKind(object, alias);
    }
    return NO;
}

static BOOL rejectsSlotNeighbour(const char *className, const char *lookup) {
    id object = [registerClass(className, NSObject.class) new];
    if (!cacheInSlotOf(lookup, [object class], object)) return NO;
    int before = runtimeLookups;
    return !DPIsKind(object, lookup) && runtimeLookups == before + 1;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        const char *originalHome = getenv("DIAPATCH_HOME");
        NSString *savedHome = originalHome ? @(originalHome) : nil;
        unsetenv("DIAPATCH_HOME");
        NSString *systemTool = DPAppSupport(@"DiaPatches/bin/diapatch");
        expect([systemTool hasSuffix:@"/Library/Application Support/DiaPatches/bin/diapatch"], @"DPAppSupport defaults to the system Application Support folder");
        setenv("DIAPATCH_HOME", "/tmp/dp-home-one", 1);
        expect([DPAppSupport(@"DiaPatches") isEqualToString:@"/tmp/dp-home-one"] && [DPAppSupport(@"DiaPatches/bin/diapatch") isEqualToString:@"/tmp/dp-home-one/bin/diapatch"],
               @"DPAppSupport follows DIAPATCH_HOME set after an earlier call");
        expect([DPAppSupport(@"Google/Chrome") isEqualToString:@"/tmp/dp-home-one/Google/Chrome"], @"paths outside DiaPatches land under DIAPATCH_HOME");
        setenv("DIAPATCH_HOME", "/tmp/dp-home-two", 1);
        expect([DPAppSupport(@"DiaPatches/local") isEqualToString:@"/tmp/dp-home-two/local"], @"DPAppSupport follows each setenv immediately");
        setenv("DIAPATCH_HOME", "", 1);
        expect([DPAppSupport(@"DiaPatches/bin/diapatch") isEqualToString:systemTool], @"an empty DIAPATCH_HOME is ignored");
        unsetenv("DIAPATCH_HOME");
        expect([DPAppSupport(@"DiaPatches/bin/diapatch") isEqualToString:systemTool], @"unsetting DIAPATCH_HOME returns to the system folder");
        if (savedHome) setenv("DIAPATCH_HOME", savedHome.UTF8String, 1);

        const char *originalDomain = getenv("DIATWEAKS_DOMAIN");
        NSString *savedDomain = originalDomain ? @(originalDomain) : nil;
        NSString *domainFolder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        NSString *domainOne = [domainFolder stringByAppendingPathComponent:@"one"], *domainTwo = [domainFolder stringByAppendingPathComponent:@"two"];
        [NSFileManager.defaultManager createDirectoryAtPath:domainFolder withIntermediateDirectories:YES attributes:nil error:nil];
        unsetenv("DIATWEAKS_DOMAIN");
        expect([DPSettingsDomain() isEqualToString:@"com.diapatches"], @"DPSettingsDomain defaults to com.diapatches");
        setenv("DIATWEAKS_DOMAIN", "", 1);
        expect([DPSettingsDomain() isEqualToString:@"com.diapatches"], @"an empty DIATWEAKS_DOMAIN is ignored");
        setenv("DIATWEAKS_DOMAIN", domainOne.UTF8String, 1);
        expect([DPSettingsDomain() isEqualToString:domainOne], @"DPSettingsDomain follows DIATWEAKS_DOMAIN");
        [DPSettingsDefaults() setBool:YES forKey:@"domainProbe"];
        setenv("DIATWEAKS_DOMAIN", domainTwo.UTF8String, 1);
        expect(![DPSettingsDefaults() boolForKey:@"domainProbe"], @"DPSettingsDefaults moves to the new domain on the next call");
        [DPSettingsDefaults() setBool:NO forKey:@"domainOther"];
        setenv("DIATWEAKS_DOMAIN", domainOne.UTF8String, 1);
        expect([DPSettingsDefaults() boolForKey:@"domainProbe"] && [DPSettingsDefaults() objectForKey:@"domainOther"] == nil,
               @"switching back finds the first domain's switches and none of the second's");
        NSUserDefaults *probe = [[NSUserDefaults alloc] initWithSuiteName:domainTwo];
        expect([probe objectForKey:@"domainOther"] != nil && ![probe objectForKey:@"domainProbe"], @"each domain keeps its own switches");
        setenv("DIATWEAKS_DOMAIN", domainTwo.UTF8String, 1);

        expect(DPFindViews(NULL).count == 0, @"DPFindViews(NULL) returns empty without crashing");
        expect(DPSubview([NSView new], NULL) == nil, @"DPSubview(..., NULL) returns nil");
        expect(!DPIsKind([NSView new], NULL), @"DPIsKind(..., NULL) returns NO");
        expect(DPIvar([NSView new], NULL) == NULL, @"DPIvar(..., NULL) returns NULL");
        static char kKey;
        NSObject *obj = [NSObject new];
        DPOverride(obj, &kKey, nil, @"ours");
        DPOverride(obj, &kKey, @"dia", nil);
        expect(DPGet(obj, &kKey) == nil, @"DPOverride ignores nil values safely");

        expect(DPAddressURL(@"example.com:8080") != nil, @"ASCII port parses");
        expect(DPAddressURL(@"example.com:\u0661\u0662\u0663") == nil, @"Arabic-Indic port digits are rejected");
        expect(DPAddressURL(@"\u0661.\u0662.\u0663.\u0664") == nil, @"Arabic-Indic IPv4 digits are rejected");

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

        expect(DPTabPlaces(@{ @1 : @"https://example.com" }) == nil, @"DPTabPlaces handles delegate without appleScriptWindows");
        DPRestorePlaces(nil, nil, @{ @"sessions" : @{}, @"order" : @[] });
        __block BOOL moveFailed = NO;
        DPMoveTab(nil, nil, nil, 0, nil, ^{ moveFailed = YES; });
        expect(moveFailed, @"DPMoveTab fails cleanly on nil args");

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

        expect(cachesSwiftClass("Cache.One", "_TtC5Cache3One"), @"a dotted Swift class name is answered from the cache");
        expect(cachesSwiftClass("A.B", "_TtC1A1B"), @"one-letter Swift module and class names are cached");
        expect(cachesSwiftClass("Personalization.IconButton", "_TtC15Personalization10IconButton"), @"two-digit Swift name lengths are cached");
        char longLookup[300] = "Pi.", longMangled[300] = "_TtC2Pi256", overLookup[300] = "Rho.", overMangled[300] = "_TtC3Rho257";
        memset(longLookup + 3, 'B', 256);
        memset(longMangled + 10, 'B', 256);
        memset(overLookup + 4, 'B', 257);
        memset(overMangled + 11, 'B', 257);
        expect(cachesSwiftClass(longLookup, longMangled), @"a 256-character Swift name part is cached");
        expect(!cachesSwiftClass(overLookup, overMangled), @"a 257-character Swift name part is not cached");

        static const char *const swiftMisfits[][2] = {
            {"_TtC03Foo3Bar", "Foo.Bar"},
            {"_TtC3Foo3BarExtra", "Foo.Bar"},
            {"_TtC3Foo4Bar", "Foo.Bar"},
            {"_TtC999999999999Foo3Bar", "Foo.Bar"},
            {"_TtC0.A", ".A"},
            {"_TtC3Foo", "Foo.Bar"},
            {"_TtC3Foo3Baz", "Foo.Bar"},
            {"_TtC2Fo3Bar", "Foo.Bar"},
            {"_TtC4Foo.3Bar", "Foo.Bar"},
            {"_TtCC3Foo3Bar3Baz", "Foo.Bar"},
            {"_TtC3Foo3Bar", "FooBar"},
            {"_TtC3Foo3Bar", "Foo:Bar"},
            {"Swft3Foo3Bar", "Foo.Bar"},
            {"_TtC3Foo3Bar", "Foo.Bar.Baz"},
            {"_TtC3Foo3Bar3", "Foo.Bar"},
            {"_TtC3Foo3Bar", "Foo.Ba"},
            {"_TtC", "Foo.Bar"},
            {"_TtC3Foo3Bar", ""},
        };
        for (size_t i = 0; i < sizeof swiftMisfits / sizeof *swiftMisfits; i++)
            expect(rejectsSlotNeighbour(swiftMisfits[i][0], swiftMisfits[i][1]),
                   [NSString stringWithFormat:@"%s in a cache slot never answers a lookup for \"%s\"", swiftMisfits[i][0], swiftMisfits[i][1]]);

        id kept = [registerClass("_TtC5Evict4Kept", NSObject.class) new];
        expect(answeredFromCache(kept, "Evict.Kept"), @"the class a neighbour will evict is cached first");
        id neighbour = [registerClass("_TtC5Evict5Other", NSObject.class) new];
        expect(cacheInSlotOf("Evict.Kept", [neighbour class], neighbour), @"a class sharing the slot is found through the runtime");
        int beforeEvicted = runtimeLookups;
        expect(DPIsKind(kept, "Evict.Kept") && runtimeLookups == beforeEvicted + 1 && answeredFromCache(kept, "Evict.Kept"),
               @"the slot neighbour evicted the cached class, which is looked up once more and cached again");

        Class swiftLogoCls = registerClass("_TtC10NewTabPage8LogoView", NSView.class), swiftPageCls = registerClass("_TtC10NewTabPage21NewTabPageContentView", NSView.class);
        Class iconCls = registerClass(DPDiaNewTabLogo, NSView.class), particlesCls = registerClass(DPDiaNewTabLogoParticles, NSView.class);
        NSView *newTabPage = [[swiftPageCls alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)], *content = [NSView new];
        [newTabPage addSubview:content];
        for (Class logoClass in @[ swiftLogoCls, iconCls, particlesCls ]) {
            NSString *name = @(class_getName(logoClass));
            NSView *inside = [[logoClass alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)], *outside = [[logoClass alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)];
            [content addSubview:inside];
            expect(DPHideNewTabLogo.hides(inside), [NSString stringWithFormat:@"Hide New Tab Logo hides %@ on a new tab page", name]);
            expect(!DPHideNewTabLogo.hides(outside), [NSString stringWithFormat:@"Hide New Tab Logo leaves a loose %@ alone", name]);
            NSView *elsewhere = [NSView new];
            [elsewhere addSubview:outside];
            expect(!DPHideNewTabLogo.hides(outside), [NSString stringWithFormat:@"Hide New Tab Logo leaves %@ outside a new tab page alone", name]);
        }
        NSView *plainInside = [NSView new];
        [content addSubview:plainInside];
        expect(!DPHideNewTabLogo.hides(plainInside) && !DPHideNewTabLogo.hides(content) && !DPHideNewTabLogo.hides(newTabPage),
               @"Hide New Tab Logo leaves the rest of a new tab page alone");
        expect(answeredFromCache([swiftLogoCls new], DPDiaNewTabLogoView), @"the new tab logo class is answered from the cache");
        expect(answeredFromCache([swiftPageCls new], DPDiaNewTabPage), @"the new tab page class is answered from the cache");

        if (savedDomain) setenv("DIATWEAKS_DOMAIN", savedDomain.UTF8String, 1);
        else unsetenv("DIATWEAKS_DOMAIN");
        [NSFileManager.defaultManager removeItemAtPath:domainFolder error:nil];
    }
    if (!failures) printf("all runtime guard checks passed\n");
    return failures ? 1 : 0;
}

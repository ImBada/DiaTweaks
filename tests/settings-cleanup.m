#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Local/Local.h"
#import "StdPatch/StdPatch.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"

// DiaPatches' constructor skips helper processes, so the test runs as one and loads the real patch
// table itself: no hooks into Dia, and no reading the operator's settings.
static NSString *DPTestDomain(void) { return [NSString stringWithFormat:@"com.diapatches.settings-test.%d", getpid()]; }

@interface NSUserDefaults (DPSettingsTest)
- (instancetype)dp_settingsInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPSettingsTest)
- (instancetype)dp_settingsInitWithSuiteName:(NSString *)suite {
    return [self dp_settingsInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPTestDomain() : suite];
}
@end

static int failures;
static NSString *gAlertTitle, *gAlertText;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static void expectEqual(id actual, id expected, NSString *what) {
    if ([actual isEqual:expected]) return;
    failures++;
    printf("FAIL %s: got %s, wanted %s\n", what.UTF8String, [[actual description] UTF8String], [[expected description] UTF8String]);
}

static DPPatch *DPRoot(DPPatch *patch) {
    while (DPRequired(patch)) patch = DPRequired(patch);
    return patch;
}

static NSArray<NSString *> *DPSections(void) {
    NSMutableArray<NSString *> *sections = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        NSString *section = DPRoot(DPPatches[i])->section ?: @"Other";
        if (![sections containsObject:section]) [sections addObject:section];
    }
    return sections;
}

// Each tweak's place in the source, which Settings uses to order a page's cards.
static NSArray<NSString *> *DPDeclaredOrders(void) {
    NSMutableArray<NSString *> *orders = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        [orders addObject:[NSString stringWithFormat:@"%@:%d", DPPatches[i]->key, DPDeclaredOrder(DPPatches[i])]];
    return orders;
}

// Mirrors DPInstallPatches: every patch in Settings order, then the late ones.
static NSArray<NSValue *> *DPInstallOrder(void) {
    NSMutableArray<NSValue *> *order = [NSMutableArray new];
    for (int late = 0; late < 2; late++)
        for (NSUInteger i = 0; i < DPPatchCount; i++)
            if (DPPatches[i]->install && DPPatches[i]->installLate == late) [order addObject:[NSValue valueWithPointer:DPPatches[i]]];
    return order;
}

static NSUInteger DPRank(NSArray<NSValue *> *order, NSString *key) {
    for (NSUInteger i = 0; i < order.count; i++)
        if ([((DPPatch *)order[i].pointerValue)->key isEqualToString:key]) return i;
    return NSNotFound;
}

static void expectBefore(NSArray<NSValue *> *order, NSString *first, NSString *second) {
    NSUInteger a = DPRank(order, first), b = DPRank(order, second);
    expect(a != NSNotFound && b != NSNotFound && a < b, [NSString stringWithFormat:@"%@ installs before %@", first, second]);
}

static NSArray<NSView *> *DPGroups(NSView *overview) {
    NSMutableArray<NSView *> *groups = [NSMutableArray new];
    for (NSView *view in ((NSStackView *)overview).arrangedSubviews)
        if ([view isMemberOfClass:DPFillView.class]) [groups addObject:view];
    return groups;
}

// DPGroup puts a separator between rows, so the rows sit at every other index.
static NSArray<NSView *> *DPRowsIn(NSView *group) {
    NSMutableArray<NSView *> *rows = [NSMutableArray new];
    NSArray<NSView *> *arranged = ((NSStackView *)group.subviews.firstObject).arrangedSubviews;
    for (NSUInteger i = 0; i < arranged.count; i += 2) [rows addObject:arranged[i]];
    return rows;
}

static void DPType(DPPaneView *pane, NSString *text) {
    pane.searchItem.searchField.stringValue = text;
    [pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:pane.searchItem.searchField]];
}

static NSArray<NSString *> *DPVisibleLabels(DPOverviewView *overview) {
    NSMutableArray<NSString *> *labels = [NSMutableArray new];
    for (NSView *group in DPGroups(overview))
        for (NSView *row in DPRowsIn(group))
            if (!row.hidden && row.accessibilityLabel.length) [labels addObject:row.accessibilityLabel];
    return labels;
}

static NSView *DPRowTitled(NSView *root, NSString *title) {
    return DPFindView(root, ^BOOL(NSView *view) { return [view.accessibilityLabel isEqualToString:title]; });
}

static BOOL DPRowShowsText(NSView *row, NSString *text) {
    return DPFindView(row, ^BOOL(NSView *view) {
               return [view isKindOfClass:NSTextField.class] && !view.hidden && [((NSTextField *)view).stringValue isEqualToString:text];
           }) != nil;
}

static NSUInteger DPVisibleRowsIn(NSView *group) {
    NSUInteger count = 0;
    for (NSView *row in DPRowsIn(group)) count += !row.hidden;
    return count;
}

static NSView *DPGroupTitled(NSView *page, NSString *title) {
    NSArray<NSView *> *arranged = ((NSStackView *)page).arrangedSubviews;
    for (NSUInteger i = 0; i + 1 < arranged.count; i++)
        if ([arranged[i] isMemberOfClass:NSTextField.class] && [((NSTextField *)arranged[i]).stringValue isEqualToString:title])
            return arranged[i + 1];
    return nil;
}

static NSArray<NSString *> *DPHeadersIn(NSView *page) {
    NSMutableArray<NSString *> *headers = [NSMutableArray new];
    for (NSView *view in ((NSStackView *)page).arrangedSubviews)
        if ([view isMemberOfClass:NSTextField.class]) [headers addObject:((NSTextField *)view).stringValue];
    return headers;
}

static NSButton *DPButtonTitled(NSView *root, NSString *title) {
    return (NSButton *)DPFindView(root, ^BOOL(NSView *view) { return [view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqualToString:title]; });
}

static NSTextField *DPLabelShowing(NSView *root, NSString *text) {
    return (NSTextField *)DPFindView(root, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqualToString:text];
    });
}

static CGFloat DPAlignedX(NSView *container, NSView *view) {
    return [container convertRect:[view alignmentRectForFrame:view.bounds] fromView:view].origin.x;
}

static BOOL DPWaitFor(NSTimeInterval seconds, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return condition();
}

static NSString *DPCatalogSource(NSString *name, NSString *key, NSString *title, NSString *detail) {
    return [NSString stringWithFormat:@"#import \"StdPatch/StdPatch.h\"\nDP_PATCH(%@) { .key = @\"%@\", .title = @\"%@\", .detail = @\"%@\", "
                                      @".symbol = @\"star.fill\", .tint = @\"systemPinkColor\", .section = @\"Toolbar\" };\n",
                                      name, key, title, detail];
}

static NSDictionary *DPCatalogEntry(NSString *name, NSString *key, NSString *title, NSString *detail) {
    return @{ @"id" : name, @"files" : @[ [name stringByAppendingString:@".m"] ],
              @"patches" : @[ @{ @"key" : key, @"title" : title, @"detail" : detail, @"symbol" : @"star.fill", @"tint" : @"systemPinkColor",
                                 @"section" : @"Toolbar", @"defaultOn" : @NO, @"requires" : NSNull.null, @"relaunch" : @NO } ] };
}

static NSArray<NSView *> *DPAvailableRows(NSView *page) { return DPRowsIn(DPGroupTitled(page, @"Available")); }

static void DPSetOn(NSString *key, BOOL on) {
    DPPatch *patch = DPPatchNamed(key);
    expect(patch != NULL, [NSString stringWithFormat:@"%@ exists", key]);
    if (patch) patch->on = on;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        unsetenv("DIATWEAKS_DOMAIN");
        // Local tweaks live in DIAPATCH_HOME, so point it at a scratch folder and never read the real one.
        NSString *home = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dp-settings-%d", getpid()]];
        setenv("DIAPATCH_HOME", home.fileSystemRepresentation, 1);
        NSString *catalogFolder = [home stringByAppendingPathComponent:@"catalog"];
        setenv("DIAPATCH_CATALOG_URL", catalogFolder.fileSystemRepresentation, 1);
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_settingsInitWithSuiteName:)));
        // Previews come off the network, and this test runs offline.
        Class preview = NSClassFromString(@"DPPreviewView");
        class_replaceMethod(preview, @selector(load), imp_implementationWithBlock(^(id self) {}), "v@:");

        [DPSettingsDefaults() setBool:YES forKey:@"showExperimentalTweaks"];
        DPLoadPatches();
        expect(DPPatchCount == 107, @"the dylib lists 107 tweaks");
        // Dia's classes aren't here, so every tweak would look unavailable; this test is about the layout.
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->unavailable = NO;

        NSArray<NSString *> *declared = DPDeclaredOrders();
        DPLoadPatches();
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->unavailable = NO;
        expectEqual(DPDeclaredOrders(), declared, @"a second read keeps each tweak's declared order");

        NSArray<NSString *> *sections = DPSections();
        expectEqual(sections, (@[ @"Page", @"Toolbar", @"Sidebar & Tab Bar", @"Profiles", @"Tabs", @"Command Bar",
                                  @"New Tab Page", @"AI", @"Window", @"App", @"Passwords", @"Links", @"Network" ]),
                    @"the sections read in order");
        for (NSString *leaked in @[ @"Showing the Toolbar", @"While It's Hidden", @"Appearance", @"Behavior", @"Blur", @"Darken", @"Shadow", @"Interaction", @"Typing" ])
            expect(![sections containsObject:leaked], [NSString stringWithFormat:@"%@ isn't a section of its own", leaked]);

        NSArray<NSValue *> *order = DPInstallOrder();
        expectBefore(order, @"compactTabRows", @"collapsePinned");
        expectBefore(order, @"collapsePinned", @"pullRequestRepo");
        expectBefore(order, @"pullRequestRepo", @"commandBarHideTab");
        expectBefore(order, @"sidebarGrain", @"profileEmoji");
        expectBefore(order, @"profileEmoji", @"profileColorPicker");
        expectBefore(order, @"profileColorPicker", @"privateWindowTheme");
        expectBefore(order, @"turnOffAI", @"skipAccount");
        // Window Material copies the corner radius Window Corners sets, so only installLate can order them.
        expect(DPPatchNamed(@"windowMaterial")->installLate, @"Window Material installs late");
        expect(DPRank(order, @"windowCorners") < DPRank(order, @"windowMaterial"), @"Window Corners installs before Window Material");

        DPOverviewView *overview = [[DPOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 560, 800)];
        [overview syncWithQuery:@""];
        NSArray<NSView *> *groups = DPGroups(overview);
        expectEqual(@(groups.count), @15, @"Overview has 13 sections, Paused and Experimental");
        NSUInteger rows = 0;
        for (NSUInteger i = 1; i < groups.count; i++) rows += DPRowsIn(groups[i]).count;
        expectEqual(@(rows), @63, @"Overview has 62 tweak and folder rows and the experimental row");
        for (NSString *folder in @[ @"Pinned Tabs", @"Hide AI Prompts & Buttons", @"Password Managers" ])
            expect(DPRowTitled(overview, folder) != nil, [NSString stringWithFormat:@"Overview has a %@ folder row", folder]);
        expect(DPRowTitled(overview, @"Allow 1Password") == nil, @"Allow 1Password has no row of its own");

        for (NSArray<NSString *> *probe in @[ @[ @"1Password", @"Password Managers" ], @[ @"Trial", @"Hide AI Prompts & Buttons" ],
                                              @[ @"Unload Pinned Splits", @"Pinned Tabs" ], @[ @"Minus", @"Pinned Tabs" ] ]) {
            [overview syncWithQuery:probe[0]];
            expectEqual(DPVisibleLabels(overview), @[ probe[1] ], [NSString stringWithFormat:@"searching %@ leaves only %@", probe[0], probe[1]]);
        }
        [overview syncWithQuery:@""];

        DPSetOn(@"turnOffAI", YES);
        [overview syncWithQuery:@""];
        expect(DPRowShowsText(DPRowTitled(overview, @"Hide AI Prompts & Buttons"), @"Turn Off AI hides these too."),
               @"Turn Off AI makes the AI folder say it hides these too");
        DPSetOn(@"turnOffAI", NO);
        DPSetOn(@"onePassword", YES);
        [overview syncWithQuery:@""];
        expect(DPRowShowsText(DPRowTitled(overview, @"Password Managers"), @"Allow 1Password"),
               @"the password folder names the one tweak that is on");
        DPSetOn(@"onePassword", NO);
        [overview syncWithQuery:@""];

        __block NSString *title = nil;
        __block BOOL canGoBack = NO;
        DPPaneView *pane = [[DPPaneView alloc] initWithTitle:@"Patches" content:overview];
        pane.titleChanged = ^(NSString *shown, BOOL back) {
            title = shown;
            canGoBack = back;
        };
        expect(!pane.showsPage, @"the pane starts on the list");
        [DPRowTitled(overview, @"Password Managers") accessibilityPerformPress];
        expect(pane.showsPage, @"opening a folder shows a page");
        expectEqual(title, @"Password Managers", @"the folder page is titled after the folder");
        expect(canGoBack, @"the folder page can go back");
        NSView *folderPage = DPFindView(pane, ^BOOL(NSView *view) { return [view isKindOfClass:NSClassFromString(@"DPFolderView")]; });
        expect(folderPage != nil, @"the folder page is a DPFolderView");
        [DPRowTitled(folderPage, @"Allow 1Password") accessibilityPerformPress];
        expect(pane.showsPage, @"opening a tweak from a folder shows a page");
        expectEqual(title, @"Allow 1Password", @"the tweak page is titled after the tweak");
        [pane goBack];
        expect(pane.showsPage, @"going back from a tweak returns to its folder");
        expectEqual(title, @"Password Managers", @"going back returns to the folder's title");
        expect(canGoBack, @"the folder page can still go back");
        [pane goBack];
        expect(!pane.showsPage, @"going back from a folder returns to the list");
        expectEqual(title, @"Patches", @"going back returns to the list's title");
        expect(!canGoBack, @"the list can't go back");

        DPOverviewView *typed = [[DPOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 560, 800)];
        DPPaneView *typedPane = [[DPPaneView alloc] initWithTitle:@"Patches" content:typed];
        __block int toggleSyncs = 0;
        Method syncMethod = class_getInstanceMethod(DPPatchSwitch.class, @selector(sync));
        IMP syncIMP = method_getImplementation(syncMethod);
        method_setImplementation(syncMethod, imp_implementationWithBlock(^(DPPatchSwitch *toggle) {
            toggleSyncs++;
            ((void (*)(id, SEL))syncIMP)(toggle, @selector(sync));
        }));
        DPType(typedPane, @"1Password");
        expectEqual(DPVisibleLabels(typed), @[ @"Password Managers" ], @"typing in the search field filters the list");
        expect(toggleSyncs == 0, [NSString stringWithFormat:@"typing doesn't sync every switch again: %d syncs", toggleSyncs]);
        DPType(typedPane, @"");
        DPSetOn(@"turnOffAI", YES);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(toggleSyncs > 0, @"a change to the tweaks still syncs the switches");
        expect(DPRowShowsText(DPRowTitled(typed, @"Hide AI Prompts & Buttons"), @"Turn Off AI hides these too."), @"and the list says what that changed");
        DPSetOn(@"turnOffAI", NO);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        method_setImplementation(syncMethod, syncIMP);

        for (NSUInteger i = 0; i < DPPatchCount; i++) {
            DPPatch *patch = DPPatches[i];
            if (patch->choices) expect(patch->choices() != patch->choices(), [NSString stringWithFormat:@"%@ builds a new choice menu every time", patch->title]);
        }

        DPPatch *commandBar = DPPatchNamed(@"commandBar");
        DPSetOn(@"commandBar", YES);
        DPSetOn(@"commandBarHideTab", NO);
        DPSetOn(@"commandBarBlur", YES);
        DPSetOn(@"commandBarDarken", YES);
        DPSetOn(@"commandBarShadow", YES);
        DPPageView *page = [[DPPageView alloc] initWithPatch:commandBar];
        expectEqual(DPHeadersIn(page), (@[ @"Options", @"Behavior", @"Appearance" ]), @"the command bar page has three cards");
        expectEqual(DPWhyDisabled(DPPatchNamed(@"commandBarSpare")), @"Needs Hide New Tab Until Opened.",
                    @"Open the Bar Instantly needs Hide New Tab Until Opened");
        expectEqual(@(DPGroups(page).count), @5, @"the command bar page has a heading, three cards and a footer");
        NSView *appearance = DPGroupTitled(page, @"Appearance");
        expect(appearance != nil, @"the command bar page has an Appearance card");
        expectEqual(@(DPVisibleRowsIn(appearance)), @7, @"Appearance shows Blur, Darken and Shadow with their sliders");
        DPSetOn(@"commandBarBlur", NO);
        [page sync];
        expectEqual(@(DPVisibleRowsIn(appearance)), @5, @"turning Blur off hides its two sliders");
        DPSetOn(@"commandBarBlur", YES);
        [page sync];
        expectEqual(@(DPVisibleRowsIn(appearance)), @7, @"turning Blur on shows its two sliders again");

        DPPageView *guarded = [[DPPageView alloc] initWithPatch:commandBar];
        NSArray<NSView *> *optionRows = [guarded valueForKey:@"optionChoices"];
        expect(optionRows.count > 0, @"the command bar page has option rows");
        NSView *stranger = [NSView new];
        for (NSView *row in optionRows) [stranger addSubview:row];
        DPSetOn(@"commandBarBlur", NO);
        BOOL survived = YES;
        @try {
            [guarded sync];
        } @catch (NSException *exception) {
            survived = NO;
        }
        expect(survived, @"a page keeps syncing when an option row has left its stack");
        DPSetOn(@"commandBarBlur", YES);
        for (NSView *row in optionRows) objc_removeAssociatedObjects(row);
        [guarded sync];
        expect(YES, @"a page keeps syncing when an option row has lost its tweak");

        expectEqual(DPPatchNamed(@"toggleToolbarVisibility")->title, @"Toggle Toolbar Visibility", @"Toggle Toolbar Visibility is Title Case");

        DPSetOn(@"localTweaks", YES);
        NSString *localFolder = [home stringByAppendingPathComponent:@"local"];
        NSWindow *localWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 900) styleMask:NSWindowStyleMaskTitled
                                                              backing:NSBackingStoreBuffered defer:YES];
        DPPageView *localPage = [[DPPageView alloc] initWithPatch:DPPatchNamed(@"localTweaks")];
        localPage.translatesAutoresizingMaskIntoConstraints = NO;
        [localWindow.contentView addSubview:localPage];
        [NSLayoutConstraint activateConstraints:@[
            [localPage.leadingAnchor constraintEqualToAnchor:[localWindow.contentView leadingAnchor] constant:20],
            [localPage.trailingAnchor constraintEqualToAnchor:[localWindow.contentView trailingAnchor] constant:-20],
            [localPage.topAnchor constraintEqualToAnchor:[localWindow.contentView topAnchor] constant:20],
        ]];
        [localWindow.contentView layoutSubtreeIfNeeded];
        expectEqual(DPHeadersIn(localPage), (@[ @"Installed", @"Available", @"Manage", @"Build & Apply" ]), @"the Local Tweaks page has four cards");
        expectEqual(@(DPGroups(localPage).count), @6, @"the Local Tweaks page has a heading, four cards and a footer");
        NSView *available = DPGroupTitled(localPage, @"Available");
        expect(DPRowShowsText(DPRowsIn(available).firstObject, @"Checking available tweaks…"), @"Available says it is looking while the list loads");
        expect(DPWaitFor(10, ^BOOL { return DPRowShowsText(DPRowsIn(available).firstObject, @"No optional tweaks yet"); }), @"an empty catalog says so");
        expectEqual(@(DPRowsIn(available).count), @1, @"an empty catalog is one row");
        NSView *installed = DPGroupTitled(localPage, @"Installed"), *manage = DPGroupTitled(localPage, @"Manage");
        NSView *build = DPGroupTitled(localPage, @"Build & Apply");
        expect(installed && available && manage && build, @"every Local Tweaks card sits under its header");
        NSTextField *addTitle = DPLabelShowing(manage, @"Add Tweak");
        expectEqual(@(DPAlignedX(manage, addTitle)), @12, @"a Local Tweaks row sits 12pt in from its card");
        NSButton *addButton = DPButtonTitled(manage, @"Add Tweak…");
        expectEqual(@(NSMaxX(manage.bounds) - NSMaxX([manage convertRect:addButton.bounds fromView:addButton])), @12, @"its button sits 12pt in from the other side");
        expectEqual(@(DPRowsIn(manage).count), @3, @"Manage has Add, Starter and Folder rows");
        expectEqual(@(DPRowsIn(build).count), @2, @"Build & Apply has Rebuild and Relaunch rows");
        expect(DPRowShowsText(DPRowsIn(installed).firstObject, @"No local tweaks installed"), @"an empty folder says so");
        expect(DPButtonTitled(installed, @"Remove") == nil, @"an empty folder has nothing to remove");

        NSString *broken = @"Broken.m:4:5: error: use of undeclared identifier 'oops'\n    oops();\n    ^";
        NSDictionary *(^record)(NSString *, NSString *, NSString *, NSString *, NSArray *, NSString *) =
            ^NSDictionary *(NSString *identifier, NSString *kind, NSString *file, NSString *status, NSArray *patches, NSString *error) {
                NSMutableDictionary *item = [@{ @"id" : identifier, @"kind" : kind, @"path" : [localFolder stringByAppendingPathComponent:file],
                                                @"status" : status, @"patches" : patches } mutableCopy];
                if (error) item[@"error"] = error;
                return item;
            };
        for (NSString *file in @[ @"Beta.patch", @"Broken.m", @"MyTweak.m" ]) {
            [NSFileManager.defaultManager createDirectoryAtPath:localFolder withIntermediateDirectories:YES attributes:nil error:NULL];
            [@"" writeToFile:[localFolder stringByAppendingPathComponent:file] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        DPLocalWriteState(@[
            record(@"Beta", @"patch", @"Beta.patch", @"ready", @[ @{ @"key" : @"beta", @"title" : @"Beta Patch", @"symbol" : @"bolt.fill", @"tint" : @"systemPinkColor" } ], nil),
            record(@"Broken", @"source", @"Broken.m", @"failed", @[], broken),
            record(@"MyTweak", @"source", @"MyTweak.m", @"loaded", @[ @{ @"key" : @"myTweak", @"title" : @"MyTweak", @"symbol" : @"", @"tint" : @"" } ], nil),
        ]);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        [localWindow.contentView layoutSubtreeIfNeeded];
        NSArray<NSView *> *arranged = ((NSStackView *)installed.subviews.firstObject).arrangedSubviews;
        expectEqual(@(arranged.count), @5, @"three installed tweaks have a separator between each");
        expectEqual(@(DPRowsIn(installed).count), @3, @"the Installed card lists every tweak in the folder");
        expect(DPRowShowsText(DPRowsIn(installed)[0], @"Beta Patch") && DPRowShowsText(DPRowsIn(installed)[0], @"Beta · Patch · Ready — relaunch Dia"),
               @"a tweak titled apart from its file shows both");
        expect(DPRowShowsText(DPRowsIn(installed)[2], @"MyTweak") && DPRowShowsText(DPRowsIn(installed)[2], @"Source · Loaded"),
               @"a tweak titled like its file doesn't repeat itself");
        NSTextField *problem = DPLabelShowing(DPRowsIn(installed)[1], broken);
        expect(problem && problem.selectable && problem.font.isFixedPitch, @"a build error is monospaced and selectable");
        expectEqual(@(DPAlignedX(installed, problem)), @42, @"a build error lines up under its tweak's title");
        expectEqual(@([DPGroups(localPage) count]), @6, @"installed tweaks don't add cards");

        DPSetOn(@"localTweaks", NO);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(DPButtonTitled(installed, @"Remove").enabled && DPButtonTitled(manage, @"Open Folder").enabled && DPButtonTitled(build, @"Relaunch Dia").enabled,
               @"turning Local Tweaks off leaves Remove, Open Folder and Relaunch Dia usable");
        expect(!addButton.enabled && !DPButtonTitled(manage, @"New Starter Tweak…").enabled && !DPButtonTitled(build, @"Rebuild All").enabled,
               @"turning Local Tweaks off disables Add, Starter and Rebuild");
        DPSetOn(@"localTweaks", YES);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(addButton.enabled && DPButtonTitled(build, @"Rebuild All").enabled, @"turning Local Tweaks back on enables them again");
        expect(DPRowShowsText(DPRowsIn(build)[1], @"Changes are ready and will load when Dia reopens."), @"a ready tweak says Dia will load it on relaunch");
        [NSFileManager.defaultManager removeItemAtPath:localFolder error:NULL];
        DPLocalWriteState(@[]);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(DPRowShowsText(DPRowsIn(installed).firstObject, @"No local tweaks installed"), @"removing every tweak brings the empty state back");
        expect(DPRowShowsText(DPRowsIn(build)[1], @"New or rebuilt tweaks take effect after Dia reopens."), @"no ready tweak, no ready message");

        // Rebuild All builds in the page's own process here (a scratch home has no bin/diapatch) and says how it went.
        void (^rebuild)(NSString *) = ^(NSString *message) {
            NSButton *button = DPButtonTitled(build, @"Rebuild All");
            [button sendAction:button.action to:button.target];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
            while (!DPRowShowsText(DPRowsIn(build)[0], message) && deadline.timeIntervalSinceNow > 0)
                [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            expect(DPRowShowsText(DPRowsIn(build)[0], message), [@"Rebuild All says: " stringByAppendingString:message]);
            expect(button.enabled, @"Rebuild All is usable again once it finishes");
        };
        rebuild(@"No local tweaks to build.");
        [NSFileManager.defaultManager createDirectoryAtPath:localFolder withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"#import \"StdPatch/StdPatch.h\"\nDP_PATCH(Hello) { .key = @\"helloLocal\", .title = @\"Hello\", .detail = @\"\", .section = @\"Local\" };\n"
            writeToFile:[localFolder stringByAppendingPathComponent:@"Hello.m"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        rebuild(@"Rebuilt — relaunch Dia to load changes.");
        expect(DPRowShowsText(DPRowsIn(installed).firstObject, @"Source · Ready — relaunch Dia"), @"a rebuilt tweak waits for a relaunch");
        NSMutableDictionary *hello = [DPLocalReadState()[@"items"][0] mutableCopy];
        hello[@"status"] = @"loaded";
        DPLocalWriteState(@[ hello ]);
        rebuild(@"All local tweaks built cleanly.");
        expect(DPRowShowsText(DPRowsIn(installed).firstObject, @"Source · Loaded"), @"a rebuilt tweak that Dia already runs stays loaded");

        // Finder never opens in a test, and a new starter has to show up in Installed without a Rebuild All.
        class_replaceMethod(NSWorkspace.class, @selector(activateFileViewerSelectingURLs:), imp_implementationWithBlock(^(NSWorkspace *workspace, NSArray<NSURL *> *urls) {}), "v@:@");
        [NSFileManager.defaultManager removeItemAtPath:localFolder error:NULL];
        DPLocalWriteState(@[]);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(DPRowShowsText(DPRowsIn(installed).firstObject, @"No local tweaks installed"), @"the folder is empty before a starter is made");
        NSButton *starter = DPButtonTitled(manage, @"New Starter Tweak…");
        [starter sendAction:starter.action to:starter.target];
        expect(DPWaitFor(60, ^BOOL { return DPRowsIn(installed).count == 1 && DPRowShowsText(DPRowsIn(installed).firstObject, @"Source · Ready — relaunch Dia"); }),
               @"a new starter tweak is built and listed as ready on its own");
        expect([NSFileManager.defaultManager fileExistsAtPath:[localFolder stringByAppendingPathComponent:@"MyTweak.m"]], @"the starter is written to the local folder");

        class_replaceMethod(NSAlert.class, @selector(runModal), imp_implementationWithBlock(^NSModalResponse(NSAlert *alert) {
            gAlertTitle = alert.messageText;
            gAlertText = alert.informativeText;
            return NSAlertSecondButtonReturn;
        }), "q@:");
        class_replaceMethod(NSFileManager.class, @selector(trashItemAtURL:resultingItemURL:error:),
                            imp_implementationWithBlock(^BOOL(NSFileManager *files, NSURL *url, NSURL *__autoreleasing *result, NSError *__autoreleasing *error) {
                                return [files removeItemAtURL:url error:error];
                            }), "c@:@^@^@");

        [NSFileManager.defaultManager removeItemAtPath:localFolder error:NULL];
        DPLocalWriteState(@[]);
        for (NSArray<NSString *> *file in @[ @[ @"Alpha", @"alphaTweak", @"Alpha Tweak", @"Does alpha things." ], @[ @"Beta", @"betaTweak", @"Beta Tweak", @"Does beta things." ],
                                             @[ @"Gamma", @"gammaTweak", @"Gamma Tweak", @"Does gamma things." ] ]) {
            [NSFileManager.defaultManager createDirectoryAtPath:catalogFolder withIntermediateDirectories:YES attributes:nil error:NULL];
            [DPCatalogSource(file[0], file[1], file[2], file[3]) writeToFile:[catalogFolder stringByAppendingPathComponent:[file[0] stringByAppendingString:@".m"]]
                                                                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        NSArray<NSDictionary *> *catalog = @[
            DPCatalogEntry(@"Alpha", @"alphaTweak", @"Alpha Tweak", @"Does alpha things."),
            DPCatalogEntry(@"Beta", @"betaTweak", @"Beta Tweak", @"Does beta things."),
            DPCatalogEntry(@"Gamma", @"gammaTweak", @"Gamma Tweak", @"Does gamma things."),
            DPCatalogEntry(@"Delta", @"deltaTweak", @"Delta Tweak", @"Is missing from the server."),
        ];
        [[NSJSONSerialization dataWithJSONObject:@{ @"tweaks" : catalog } options:0 error:NULL] writeToFile:[catalogFolder stringByAppendingPathComponent:@"index.json"] atomically:YES];
        NSString *installError = nil;
        expect(DPLocalInstallCatalogItem(catalog[2], &installError), [@"Gamma installs ahead of the page: " stringByAppendingString:installError ?: @""]);
        [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] setBool:YES forKey:@"betaTweak"];

        DPSetOn(@"localTweaks", YES);
        DPPageView *catalogPage = [[DPPageView alloc] initWithPatch:DPPatchNamed(@"localTweaks")];
        NSWindow *catalogWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 900) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        catalogPage.translatesAutoresizingMaskIntoConstraints = NO;
        [catalogWindow.contentView addSubview:catalogPage];
        [NSLayoutConstraint activateConstraints:@[
            [catalogPage.leadingAnchor constraintEqualToAnchor:[catalogWindow.contentView leadingAnchor] constant:20],
            [catalogPage.trailingAnchor constraintEqualToAnchor:[catalogWindow.contentView trailingAnchor] constant:-20],
            [catalogPage.topAnchor constraintEqualToAnchor:[catalogWindow.contentView topAnchor] constant:20],
        ]];
        NSView *catalogInstalled = DPGroupTitled(catalogPage, @"Installed");
        expect(DPWaitFor(10, ^BOOL { return DPAvailableRows(catalogPage).count == 4; }), @"Available lists every optional tweak once it loads");
        [catalogWindow.contentView layoutSubtreeIfNeeded];
        NSArray<NSView *> *offers = DPAvailableRows(catalogPage);
        expect(DPRowShowsText(offers[0], @"Beta Tweak") && DPRowShowsText(offers[0], @"Previously on · Does beta things."), @"a tweak that was on says so and comes first");
        expect(DPButtonTitled(offers[0], @"Install").enabled, @"it can be installed");
        expect(DPRowShowsText(offers[1], @"Alpha Tweak") && DPRowShowsText(offers[1], @"Does alpha things.") && DPButtonTitled(offers[1], @"Install").enabled, @"another tweak lists its detail and an Install button");
        expect(DPRowShowsText(offers[2], @"Gamma Tweak") && DPButtonTitled(offers[2], @"Installed") && !DPButtonTitled(offers[2], @"Installed").enabled, @"an installed tweak shows a disabled Installed button");
        expect(DPButtonTitled(offers[2], @"Install") == nil, @"it has no Install button");
        expectEqual(@(DPRowsIn(catalogInstalled).count), @1, @"Installed lists Gamma");

        NSButton *install = DPButtonTitled(offers[1], @"Install");
        [install sendAction:install.action to:install.target];
        offers = DPAvailableRows(catalogPage);
        expect(DPFindView(offers[1], ^BOOL(NSView *view) { return [view isKindOfClass:NSProgressIndicator.class]; }) != nil, @"installing shows a spinner");
        expect(!DPButtonTitled(offers[1], @"Install").enabled && !DPButtonTitled(offers[0], @"Install").enabled, @"installing disables every Install button");
        expect(!DPButtonTitled(DPGroupTitled(catalogPage, @"Manage"), @"Add Tweak…").enabled, @"installing holds off Add Tweak");
        expect(DPWaitFor(120, ^BOOL { return DPButtonTitled(DPAvailableRows(catalogPage)[1], @"Installed") != nil; }), @"installing flips Install to Installed");
        offers = DPAvailableRows(catalogPage);
        expect(!DPButtonTitled(offers[1], @"Installed").enabled, @"Installed is disabled");
        expect(DPFindView(offers[1], ^BOOL(NSView *view) { return [view isKindOfClass:NSProgressIndicator.class]; }) == nil, @"the spinner goes away");
        expect(DPButtonTitled(offers[0], @"Install").enabled, @"the other Install buttons come back");
        expectEqual(gAlertTitle, @"Local tweaks are ready", @"a finished install offers a relaunch");
        expectEqual(@(DPRowsIn(catalogInstalled).count), @2, @"Installed gains the new tweak");
        NSUserDefaults *saved = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
        expect([saved boolForKey:@"alphaTweak"], @"the new tweak is on for the next launch");

        NSView *alphaRow = nil;
        for (NSView *row in DPRowsIn(catalogInstalled)) if (DPRowShowsText(row, @"Alpha Tweak")) alphaRow = row;
        NSButton *remove = DPButtonTitled(alphaRow, @"Remove");
        expect(remove != nil, @"the installed tweak has a Remove button");
        [remove sendAction:remove.action to:remove.target];
        expect(DPWaitFor(10, ^BOOL { return DPButtonTitled(DPAvailableRows(catalogPage)[1], @"Install") != nil; }), @"removing a tweak turns Installed back into Install");
        expect(DPButtonTitled(DPAvailableRows(catalogPage)[1], @"Install").enabled, @"and it can be installed again");
        expectEqual(@(DPRowsIn(catalogInstalled).count), @1, @"Installed loses it");

        gAlertTitle = nil;
        NSButton *missing = DPButtonTitled(DPAvailableRows(catalogPage)[3], @"Install");
        [missing sendAction:missing.action to:missing.target];
        expect(DPWaitFor(60, ^BOOL { return gAlertTitle != nil; }), @"a failed install says so");
        expect([gAlertText containsString:@"Delta.m"], @"it names the file that failed");
        expect(DPWaitFor(10, ^BOOL { return DPButtonTitled(DPAvailableRows(catalogPage)[3], @"Install").enabled; }), @"a failed install can be tried again");
        expect(DPFindView(DPAvailableRows(catalogPage)[3], ^BOOL(NSView *view) { return [view isKindOfClass:NSProgressIndicator.class]; }) == nil, @"and stops spinning");

        DPSetOn(@"localTweaks", NO);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(!DPButtonTitled(DPAvailableRows(catalogPage)[1], @"Install").enabled, @"turning Local Tweaks off disables Install");
        DPSetOn(@"localTweaks", YES);
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        expect(DPButtonTitled(DPAvailableRows(catalogPage)[1], @"Install").enabled, @"and turning it back on enables it");

        [NSFileManager.defaultManager removeItemAtPath:[DPLocalCacheFolder() stringByAppendingPathComponent:@"catalog.json"] error:NULL];
        setenv("DIAPATCH_CATALOG_URL", "http://127.0.0.1:1/", 1);
        DPPageView *offlinePage = [[DPPageView alloc] initWithPatch:DPPatchNamed(@"localTweaks")];
        expect(DPWaitFor(15, ^BOOL { return DPRowShowsText(DPAvailableRows(offlinePage).firstObject, @"Couldn’t load available tweaks"); }), @"an unreachable catalog with nothing cached says so");
        expect(DPRowShowsText(DPAvailableRows(offlinePage).firstObject, @"Couldn’t reach GitHub to load optional tweaks."), @"it says why");
        NSButton *retry = DPButtonTitled(offlinePage, @"Retry");
        expect(retry != nil, @"and offers a Retry");
        setenv("DIAPATCH_CATALOG_URL", catalogFolder.fileSystemRepresentation, 1);
        [retry sendAction:retry.action to:retry.target];
        expect(DPWaitFor(15, ^BOOL { return DPAvailableRows(offlinePage).count == 4; }), @"Retry loads the list once the catalog is back");
        [saved removePersistentDomainForName:DPTestDomain()];

        NSString *windowSource = @"#import \"StdPatch/StdPatch.h\"\n"
                                 @"DP_PATCH(CatalogWindowOption) { .key = @\"catalogWindowOption\", .title = @\"Catalog Window Option\", .detail = @\"\", .requires = @\"catalogWindow\" };\n"
                                 @"DP_PATCH(CatalogWindow) { .key = @\"catalogWindow\", .title = @\"Catalog Window\", .detail = @\"\", .section = @\"Window\" };\n";
        [NSFileManager.defaultManager createDirectoryAtPath:[catalogFolder stringByAppendingPathComponent:@"CatalogWindow"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [windowSource writeToFile:[catalogFolder stringByAppendingPathComponent:@"CatalogWindow/CatalogWindow.m"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *(^windowRecord)(NSString *, NSString *, id, id) = ^NSDictionary *(NSString *key, NSString *title, id section, id requires) {
            return @{ @"key" : key, @"title" : title, @"detail" : @"", @"symbol" : @"", @"tint" : @"systemOrangeColor", @"section" : section,
                      @"defaultOn" : @NO, @"requires" : requires, @"disabledBy" : NSNull.null, @"coveredBy" : NSNull.null, @"relaunch" : @NO };
        };
        NSDictionary *windowEntry = @{ @"id" : @"CatalogWindow", @"files" : @[ @"CatalogWindow/CatalogWindow.m" ],
                                       @"patches" : @[ windowRecord(@"catalogWindowOption", @"Catalog Window Option", NSNull.null, @"catalogWindow"),
                                                       windowRecord(@"catalogWindow", @"Catalog Window", @"Window", NSNull.null) ] };
        NSData *windowIndex = [NSJSONSerialization dataWithJSONObject:@{ @"tweaks" : @[ windowEntry ] } options:0 error:NULL];
        [windowIndex writeToFile:[catalogFolder stringByAppendingPathComponent:@"index.json"] atomically:YES];
        NSString *windowError = nil;
        NSArray<NSDictionary *> *windowCatalog = DPLocalFetchCatalog(&windowError);
        expect(windowCatalog.count == 1 && DPLocalInstallCatalogItem(windowCatalog[0], &windowError), [@"a tweak with a sectionless option installs: " stringByAppendingString:windowError ?: @""]);
        DPLocalReset();
        DPLoadPatches();
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->unavailable = NO;
        DPPatch *windowParent = DPPatchNamed(@"catalogWindow"), *windowOption = DPPatchNamed(@"catalogWindowOption");
        expect(windowParent && windowOption && !windowOption->section && DPRequired(windowOption) == windowParent, @"the installed option has no section and needs its tweak");
        DPPageView *windowPage = windowParent ? [[DPPageView alloc] initWithPatch:windowParent] : nil;
        NSView *windowOptions = DPGroupTitled(windowPage, @"Options");
        expect(windowOptions && DPLabelShowing(windowOptions, @"Catalog Window Option"), @"the option sits under Options");
        expectEqual(@([DPHeadersIn(windowPage) containsObject:@"Local"]), @NO, @"the page has no Local card for it");

        [NSFileManager.defaultManager removeItemAtPath:home error:NULL];
        [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] removePersistentDomainForName:DPTestDomain()];

        if (failures) {
            printf("%d failure%s\n", failures, failures == 1 ? "" : "s");
            return 1;
        }
        printf("settings-cleanup: all checks passed\n");
    }
    return 0;
}

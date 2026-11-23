#import <AppKit/AppKit.h>
#import <objc/runtime.h>
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

static void DPSetOn(NSString *key, BOOL on) {
    DPPatch *patch = DPPatchNamed(key);
    expect(patch != NULL, [NSString stringWithFormat:@"%@ exists", key]);
    if (patch) patch->on = on;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Local tweaks live in DIAPATCH_HOME, so point it at a scratch folder and never read the real one.
        NSString *home = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dp-settings-%d", getpid()]];
        setenv("DIAPATCH_HOME", home.fileSystemRepresentation, 1);
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_settingsInitWithSuiteName:)));
        // Previews come off the network, and this test runs offline.
        Class preview = NSClassFromString(@"DPPreviewView");
        class_replaceMethod(preview, @selector(load), imp_implementationWithBlock(^(id self) {}), "v@:");

        DPLoadPatches();
        expect(DPPatchCount == 105, @"the dylib lists 105 tweaks");
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
        expectEqual(@(groups.count), @14, @"Overview has 13 sections and Paused");
        NSUInteger rows = 0;
        for (NSUInteger i = 1; i < groups.count; i++) rows += DPRowsIn(groups[i]).count;
        expectEqual(@(rows), @61, @"Overview has 61 tweak and folder rows");
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

        expectEqual(DPPatchNamed(@"toggleToolbarVisibility")->title, @"Toggle Toolbar Visibility", @"Toggle Toolbar Visibility is Title Case");

        if (failures) {
            printf("%d failure%s\n", failures, failures == 1 ? "" : "s");
            return 1;
        }
        printf("settings-cleanup: all checks passed\n");
    }
    return 0;
}

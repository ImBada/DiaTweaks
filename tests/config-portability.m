#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <notify.h>
#import "SafeMode/SafeMode.h"
#import "StdPatch/StdPatch.h"
#import "Settings/Settings.h"

extern DPPatch DPPeek, DPLittleDia;
double DPPeekDarkness(void);
double DPPeekResponse(void);
BOOL DPPeekGenie(void);
BOOL DPPeekShowsToolbar(void);
NSSize DPLittleDiaSize(void);

static NSString *gDomain;

@interface NSUserDefaults (DPConfigTest)
- (instancetype)dp_configInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPConfigTest)
- (instancetype)dp_configInitWithSuiteName:(NSString *)suite {
    return [self dp_configInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? gDomain : suite];
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

static NSArray<NSString *> *DPExperimentalKeys(void) {
    return @[ @"briefLanguage", @"commandBarHideTab", @"commandBarSpare", @"deleteProfileMenu", @"hideToolbar", @"keepWindowsActive",
              @"littleDiaRemember", @"littleDiaTabLinks", @"privateWindowTheme", @"skipAccount", @"splitClientHello", @"tabTitles" ];
}

static NSArray<NSString *> *DPExcludedKeys(void) {
    return @[ @"profileColors", @"profileEmojis", @"sidebarGrainProfiles", @"collapsedPinned", @"localTweaks", @"launchFlagsApplied",
              @"commandBarChatLocked", @"littleDiaFrame", @"autoUpdateDia", @"autoUpdateTweaks", @"showExperimentalTweaks", @"peekTurnedOffForNative" ];
}

static NSDictionary *DPExcludedValues(void) {
    return @{ @"profileColors" : @{ @"space-1" : @"#FF0000" }, @"profileEmojis" : @{ @"space-1" : @"🙂" }, @"sidebarGrainProfiles" : @{ @"space-1" : @{ @"sidebarGrainAmount" : @0.5 } },
              @"collapsedPinned" : @[ @"space-1" ], @"localTweaks" : @NO, @"launchFlagsApplied" : @[ @"--applied" ], @"commandBarChatLocked" : @YES,
              @"littleDiaFrame" : @"{{1, 2}, {3, 4}}", @"autoUpdateDia" : @2, @"autoUpdateTweaks" : @3, @"showExperimentalTweaks" : @YES, @"peekTurnedOffForNative" : @YES };
}

static NSArray<NSView *> *DPGroups(NSView *root) {
    NSMutableArray<NSView *> *groups = [NSMutableArray new];
    for (NSView *view in ((NSStackView *)root).arrangedSubviews)
        if ([view isMemberOfClass:DPFillView.class]) [groups addObject:view];
    return groups;
}

static NSArray<NSView *> *DPRowsIn(NSView *group) {
    NSMutableArray<NSView *> *rows = [NSMutableArray new];
    NSArray<NSView *> *arranged = ((NSStackView *)group.subviews.firstObject).arrangedSubviews;
    for (NSUInteger i = 0; i < arranged.count; i += 2) [rows addObject:arranged[i]];
    return rows;
}

static NSUInteger DPVisibleRowsIn(NSView *group) {
    NSUInteger count = 0;
    for (NSView *row in DPRowsIn(group)) count += !row.hidden;
    return count;
}

static NSArray<NSString *> *DPVisibleLabels(NSView *overview) {
    NSMutableArray<NSString *> *labels = [NSMutableArray new];
    for (NSView *group in DPGroups(overview))
        for (NSView *row in DPRowsIn(group))
            if (!row.hidden && row.accessibilityLabel.length) [labels addObject:row.accessibilityLabel];
    return labels;
}

static NSView *DPRowTitled(NSView *root, NSString *title) {
    return DPFindView(root, ^BOOL(NSView *view) { return [view.accessibilityLabel isEqualToString:title]; });
}

static NSTextField *DPLabelShowing(NSView *root, NSString *text) {
    return (NSTextField *)DPFindView(root, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqualToString:text];
    });
}

static NSButton *DPButtonTitled(NSView *root, NSString *title) {
    return (NSButton *)DPFindView(root, ^BOOL(NSView *view) { return [view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqualToString:title]; });
}

static BOOL DPVisible(NSView *view) {
    if (!view) return NO;
    for (NSView *up = view; up; up = up.superview)
        if (up.hidden) return NO;
    return YES;
}

static NSView *DPGroupTitled(NSView *root, NSString *title) {
    NSArray<NSView *> *arranged = ((NSStackView *)root).arrangedSubviews;
    for (NSUInteger i = 0; i + 1 < arranged.count; i++) {
        NSView *header = arranged[i];
        NSTextField *label = [header isKindOfClass:NSTextField.class] ? (NSTextField *)header : (NSTextField *)DPFindView(header, ^BOOL(NSView *v) { return [v isKindOfClass:NSTextField.class]; });
        if ([label.stringValue isEqualToString:title]) return arranged[i + 1];
    }
    return nil;
}

static void DPType(DPPaneView *pane, NSString *text) {
    pane.searchItem.searchField.stringValue = text;
    [pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:pane.searchItem.searchField]];
}

static void DPSaveOn(NSString *key, BOOL on) {
    [DPSettingsDefaults() setBool:on forKey:key];
    DPApplySavedSettings();
}

static NSData *DPData(NSString *json) { return [json dataUsingEncoding:NSUTF8StringEncoding]; }

static NSDictionary *DPParse(NSData *data) { return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]; }

static NSDictionary *DPSaved(void) { return [DPSettingsDefaults() persistentDomainForName:gDomain] ?: @{}; }

static DPConfigImport *DPImport(NSString *json, BOOL replace) { return DPImportConfigData(DPData(json), replace, NULL); }

static void DPRejects(NSString *json, NSString *what) {
    NSDictionary *before = DPSaved();
    NSError *error = nil;
    DPConfigImport *result = DPImportConfigData(DPData(json), NO, &error);
    expect(!result && error.localizedDescription.length, [what stringByAppendingString:@" is rejected with a reason"]);
    expectEqual(DPSaved(), before, [what stringByAppendingString:@" changes nothing"]);
    result = DPImportConfigData(DPData(json), YES, &error);
    expectEqual(DPSaved(), before, [what stringByAppendingString:@" changes nothing on Replace All either"]);
}

static const DPSetting *DPDeclared(DPPatch *patch, NSString *key) {
    for (const DPSetting *setting = patch->settings; setting && setting->kind; setting++)
        if ([setting->key isEqualToString:key]) return setting;
    return NULL;
}

static int gApplied, gPatchesChanged;
static void DPCountApply(DPPatch *patch) { gApplied++; }

@interface DPConfigSpy : NSObject
@end
@implementation DPConfigSpy
- (void)patchesChanged:(NSNotification *)note { gPatchesChanged++; }
@end

static void DPPumpNotifications(double seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([deadline timeIntervalSinceNow] > 0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static void DPCheckSingleApply(void) {
    DPConfigSpy *spy = [DPConfigSpy new];
    [NSNotificationCenter.defaultCenter addObserver:spy selector:@selector(patchesChanged:) name:DPPatchesDidChangeNotification object:nil];
    DPWatchSavedSettings();

    DPPatch *corners = DPPatchNamed(@"windowCorners");
    void (*cornersApply)(DPPatch *) = corners->apply;
    DPSaveOn(@"windowCorners", YES);
    corners->apply = DPCountApply;
    DPSafeMode = 0;
    gApplied = 0;
    gPatchesChanged = 0;
    DPImport(@"{\"version\": 1, \"settings\": {\"windowCornerRadius\": 9}}", NO);
    DPSafeMode = 1;
    expectEqual(@(gApplied), @1, @"importing applies each changed tweak once");
    expectEqual(@(gPatchesChanged), @1, @"and tells the rows once");
    DPPumpNotifications(0.5);
    expectEqual(@(gApplied), @1, @"and the import isn't applied a second time later");
    expectEqual(@(gPatchesChanged), @1, @"or announced twice");

    notify_post([DPSettingsDomain() stringByAppendingString:@".changed"].UTF8String);
    for (NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2]; gPatchesChanged < 2 && [deadline timeIntervalSinceNow] > 0;)
        DPPumpNotifications(0.05);
    expectEqual(@(gPatchesChanged), @2, @"so a notification from elsewhere still reaches Dia's watcher");

    corners->apply = cornersApply;
    DPSaveOn(@"windowCorners", NO);
    [NSNotificationCenter.defaultCenter removeObserver:spy];
    DPPumpNotifications(0.2);
}

static void DPCheckExperimentalData(void) {
    NSMutableArray<NSString *> *flagged = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        if (patch->experimental) [flagged addObject:patch->key];
        expect(![patch->detail hasSuffix:@"Experimental."], [NSString stringWithFormat:@"%@ doesn't say Experimental in its detail", patch->key]);
    }
    expectEqual([flagged sortedArrayUsingSelector:@selector(compare:)], DPExperimentalKeys(), @"the 12 tweaks that stay Experimental are flagged");
}

static void DPCheckVisibility(void) {
    expect(!DPShowsExperimental(), @"experimental tweaks start hidden");
    for (NSString *key in DPExperimentalKeys()) expect(!DPExperimentalShown(DPPatchNamed(key)), [key stringByAppendingString:@" is hidden while off"]);
    expect(DPExperimentalShown(DPPatchNamed(@"commandBar")) && DPExperimentalShown(DPPatchNamed(@"peek")), @"ordinary tweaks are always shown");
    for (NSString *key in @[ @"bitwarden", @"icloudPasswords", @"onePassword", @"passkeys", @"protonPass" ])
        expect(DPExperimentalShown(DPPatchNamed(key)), [key stringByAppendingString:@" is shown without Show Experimental Tweaks"]);
    expectEqual(@(DPHiddenExperimentalCount()), @12, @"12 experimental tweaks are hidden");

    DPOverviewView *overview = [[DPOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 560, 800)];
    DPPaneView *pane = [[DPPaneView alloc] initWithTitle:@"Patches" content:overview];
    [overview syncWithQuery:@""];
    NSArray<NSString *> *labels = DPVisibleLabels(overview);
    for (NSString *key in @[ @"hideToolbar", @"briefLanguage", @"skipAccount", @"tabTitles", @"splitClientHello", @"keepWindowsActive", @"privateWindowTheme" ])
        expect(![labels containsObject:DPPatchNamed(key)->title], [key stringByAppendingString:@" has no row while hidden"]);
    expect([labels containsObject:@"Password Managers"], @"the Password Managers folder is shown by default");
    expect(labels.count > 40 && [labels containsObject:@"Window Corners"], @"the other rows stay");
    expect(DPVisible(DPGroupTitled(overview, @"Passwords")), @"the Passwords section is shown by default");
    expect(DPVisible(DPLabelShowing(overview, @"12 experimental tweaks are hidden.")), @"Overview says 12 are hidden");

    DPType(pane, @"1Password");
    expectEqual(DPVisibleLabels(overview), @[ @"Password Managers" ], @"searching a graduated password tweak finds Password Managers");
    DPType(pane, @"Skip Account");
    expectEqual(DPVisibleLabels(overview), @[], @"searching a hidden tweak finds nothing");
    expect(DPVisible(DPLabelShowing(overview, @"No Results")), @"and says so");
    DPType(pane, @"experimental");
    expectEqual(DPVisibleLabels(overview), @[], @"searching experimental shows no tweak rows");
    expect(DPVisible(DPLabelShowing(overview, @"12 experimental tweaks are hidden.")), @"but finds the hidden-tweaks row");
    DPType(pane, @"");

    DPFolderView *folder = [[DPFolderView alloc] initWithFolder:DPFolderSpecNamed(@"passwordManagers")];
    NSView *members = DPGroups(folder).firstObject;
    expectEqual(@(DPVisibleRowsIn(members)), @5, @"the password folder lists all five managers by default");
    expect(DPVisible(DPRowTitled(folder, @"Allow 1Password")) && DPVisible(DPRowTitled(folder, @"Allow Bitwarden")), @"individual password rows are visible");
    expect(DPLabelShowing(folder, @"Experimental") == nil, @"graduated password rows have no Experimental badge");

    DPSaveOn(@"skipAccount", YES);
    expect(DPExperimentalShown(DPPatchNamed(@"skipAccount")) && DPHiddenExperimentalCount() == 11, @"a tweak that is on is shown");
    expect([DPVisibleLabels(overview) containsObject:@"Skip Account"], @"its row returns");
    expect(DPVisible(DPLabelShowing(overview, @"11 experimental tweaks are hidden.")), @"the count follows");

    DPPaused = YES;
    DPPatchNamed(@"skipAccount")->on = NO;
    [overview syncWithQuery:@""];
    expect(DPExperimentalShown(DPPatchNamed(@"skipAccount")), @"a paused tweak that is saved on stays shown");
    expect([DPVisibleLabels(overview) containsObject:@"Skip Account"], @"so its row stays while paused");
    DPPaused = NO;
    DPSaveOn(@"skipAccount", NO);
    expect(![DPVisibleLabels(overview) containsObject:@"Skip Account"], @"turning it off hides the row again");

    DPButtonTitled(overview, @"Show").enabled = YES;
    [DPButtonTitled(overview, @"Show") performClick:nil];
    expect(DPShowsExperimental(), @"Show turns Show Experimental Tweaks on");
    labels = DPVisibleLabels(overview);
    expect([labels containsObject:@"Password Managers"] && [labels containsObject:@"Hide Toolbar"] && [labels containsObject:@"Skip Account"], @"every experimental row appears live");
    expect(!DPVisible(DPLabelShowing(overview, @"12 experimental tweaks are hidden.")), @"and the hidden-tweaks row goes");
    [folder sync];
    expectEqual(@(DPVisibleRowsIn(members)), @5, @"the folder page lists all five managers");

    DPHomeView *home = [DPHomeView new];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 900) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    home.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:home];
    [NSLayoutConstraint activateConstraints:@[
        [home.leadingAnchor constraintEqualToAnchor:[window.contentView leadingAnchor] constant:20],
        [home.trailingAnchor constraintEqualToAnchor:[window.contentView trailingAnchor] constant:-20],
        [home.topAnchor constraintEqualToAnchor:[window.contentView topAnchor] constant:20],
    ]];
    [window.contentView layoutSubtreeIfNeeded];
    NSSwitch *toggle = (NSSwitch *)DPFindView(home, ^BOOL(NSView *v) { return [v isKindOfClass:NSSwitch.class] && [v.accessibilityLabel isEqual:@"Show Experimental Tweaks"]; });
    expect(toggle && toggle.state == NSControlStateValueOn, @"Home's switch shows the saved choice");
    [toggle performClick:nil];
    expect(!DPShowsExperimental() && DPHiddenExperimentalCount() == 12, @"Home's switch turns it off");
    DPSetShowsExperimental(YES);
    expect(toggle.state == NSControlStateValueOn, @"and follows a change made elsewhere");
    expect(DPButtonTitled(home, @"Export…") && DPButtonTitled(home, @"Import…"), @"Home has Export and Import");
    NSView *buttons = DPButtonTitled(home, @"Import…");
    expect(NSContainsRect(home.bounds, [home convertRect:buttons.bounds fromView:buttons]) && NSContainsRect(home.bounds, [home convertRect:toggle.bounds fromView:toggle]),
           @"and lays them out inside the pane");
    DPSetShowsExperimental(NO);
}

static void DPCheckPages(void) {
    DPPageView *page = [[DPPageView alloc] initWithPatch:DPPatchNamed(@"commandBar")];
    NSView *behavior = DPGroupTitled(page, @"Behavior");
    expect(behavior && DPVisible(DPLabelShowing(behavior, @"Scroll Page Behind")), @"the command bar page keeps its ordinary options");
    expect(!DPVisible(DPLabelShowing(behavior, @"Hide New Tab Until Opened")) && !DPVisible(DPLabelShowing(behavior, @"Open the Bar Instantly")), @"and hides the experimental ones");
    expectEqual(@(DPVisibleRowsIn(behavior)), @2, @"Behavior shows two rows");

    DPSaveOn(@"commandBarHideTab", YES);
    [page sync];
    expect(DPVisible(DPLabelShowing(behavior, @"Hide New Tab Until Opened")) && !DPVisible(DPLabelShowing(behavior, @"Open the Bar Instantly")), @"an option that is on is shown");
    DPSaveOn(@"commandBarHideTab", NO);
    DPSaveOn(@"commandBarSpare", YES);
    [page sync];
    expect(DPVisible(DPLabelShowing(behavior, @"Open the Bar Instantly")) && DPVisible(DPLabelShowing(behavior, @"Hide New Tab Until Opened")), @"an option that is on keeps the one it needs in view");
    DPSaveOn(@"commandBarSpare", NO);
    [page sync];
    expectEqual(@(DPVisibleRowsIn(behavior)), @2, @"turning them off hides them again");
    DPSetShowsExperimental(YES);
    [page sync];
    expectEqual(@(DPVisibleRowsIn(behavior)), @4, @"Show Experimental Tweaks reveals them live");
    DPSetShowsExperimental(NO);
    [page sync];
    expectEqual(@(DPVisibleRowsIn(behavior)), @2, @"and hides them again");

    DPPageView *little = [[DPPageView alloc] initWithPatch:DPPatchNamed(@"littleDia")];
    expect(!DPVisible(DPLabelShowing(little, @"Remember Size and Position")) && !DPVisible(DPLabelShowing(little, @"Open Links from Tabs")), @"Little Dia hides its experimental options");
    expect(DPVisible(DPLabelShowing(little, @"Follow Link Rules")), @"and keeps the rest");
    DPSetShowsExperimental(YES);
    [little sync];
    expect(DPVisible(DPLabelShowing(little, @"Remember Size and Position")) && DPVisible(DPLabelShowing(little, @"Open Links from Tabs")), @"Show Experimental Tweaks reveals them");
    DPSetShowsExperimental(NO);

    expect(DPLabelShowing([[DPPageView alloc] initWithPatch:DPPatchNamed(@"skipAccount")], @"Experimental") != nil, @"an experimental tweak's page says so");
    expect(DPLabelShowing([[DPPageView alloc] initWithPatch:DPPatchNamed(@"onePassword")], @"Experimental") == nil, @"a graduated password tweak doesn't");
    expect(DPLabelShowing([[DPPageView alloc] initWithPatch:DPPatchNamed(@"windowCorners")], @"Experimental") == nil, @"an ordinary one doesn't");

    NSView *group = DPGroup(@[ [NSView new], [NSView new], [NSView new] ]);
    NSArray<NSView *> *rows = DPRowsIn(group), *stack = ((NSStackView *)group.subviews.firstObject).arrangedSubviews;
    rows[0].hidden = YES;
    expect(DPTidyGroup(group) && stack[1].hidden && !stack[3].hidden, @"a group with its first row hidden drops the separator above the next");
    rows[1].hidden = YES;
    expect(DPTidyGroup(group) && stack[1].hidden && stack[3].hidden, @"and with two hidden, every separator");
    rows[2].hidden = YES;
    expect(!DPTidyGroup(group) && group.hidden, @"a group with every row hidden hides itself");
}

static void DPCheckManifest(void) {
    NSString *path = [[NSString stringWithUTF8String:getenv("DIAPATCH_HOME")] stringByAppendingPathComponent:@"patches.json"];
    expect(DPWriteManifest(path), @"the manifest writes");
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *manifest = DPParse([NSData dataWithContentsOfFile:path]);
    expectEqual(manifest[@"version"], @1, @"the manifest stays version 1");
    NSMutableDictionary<NSString *, NSDictionary *> *byKey = [NSMutableDictionary new];
    for (NSDictionary *patch in manifest[@"patches"]) byKey[patch[@"key"]] = patch;
    NSMutableArray<NSString *> *experimental = [NSMutableArray new];
    for (NSString *key in byKey) {
        NSDictionary *patch = byKey[key];
        expect(patch[@"experimental"] && patch[@"choice"] && patch[@"shortcut"] && [patch[@"settings"] isKindOfClass:NSArray.class], [key stringByAppendingString:@" has every portable field"]);
        if ([patch[@"experimental"] boolValue]) [experimental addObject:key];
    }
    expectEqual([experimental sortedArrayUsingSelector:@selector(compare:)], DPExperimentalKeys(), @"the manifest flags the experimental tweaks");
    expect(![text containsString:@"0.2399"] && ![text containsString:@"0.4500"] && [text containsString:@"\"default\" : 0.24"], @"the manifest writes numbers without float noise");

    NSDictionary *position = byKey[@"commandBar"][@"choice"];
    expectEqual(position[@"key"], @"commandBarPosition", @"commandBar names its choice key");
    expectEqual(position[@"default"], @"macos", @"and its default");
    expectEqual(position[@"values"], (@[ @"macos", @"window", @"page" ]), @"and its values");
    expectEqual(byKey[@"pinTabShortcut"][@"shortcut"], (@{ @"key" : @"pinTabShortcutKey", @"default" : @{ @"key" : @"D", @"keyCode" : @2, @"modifiers" : @1048576 } }), @"a shortcut lists its key and default");
    expect(byKey[@"briefLanguage"][@"choice"][@"default"] == NSNull.null && [byKey[@"briefLanguage"][@"choice"][@"values"] count] == 18, @"the Brief language default stays null: it follows the Mac");
    expect(byKey[@"windowCorners"][@"choice"] == NSNull.null && byKey[@"windowCorners"][@"shortcut"] == NSNull.null, @"a tweak without them says null");
    expectEqual(byKey[@"windowCorners"][@"settings"], (@[ @{ @"key" : @"windowCornerRadius", @"type" : @"number", @"default" : @26, @"min" : @0, @"max" : @26 } ]), @"Window Corners declares its radius");
    expectEqual(byKey[@"launchFlags"][@"settings"], (@[ @{ @"key" : @"launchFlagsArgs", @"type" : @"string", @"default" : @"", @"min" : NSNull.null, @"max" : NSNull.null } ]), @"Launch Flags declares its text");
    expectEqual(byKey[@"commandBarBlur"][@"settings"][1], (@{ @"key" : @"commandBarBlurWindow", @"type" : @"bool", @"default" : @NO, @"min" : NSNull.null, @"max" : NSNull.null }), @"a bool setting has no range");
    expect(byKey[@"peek"] && byKey[@"peekPinnedLinks"] && byKey[@"peekDragLinks"], @"Peek and its two companions are built in, so the manifest lists them");
    expect(byKey[@"peek"] && ![byKey[@"peek"][@"defaultOn"] boolValue], @"Peek is off by default");
    expectEqual([byKey[@"peek"][@"settings"] valueForKey:@"key"], (@[ @"peekToolbar", @"peekGenie", @"peekDarkness", @"peekSpeed" ]), @"Peek declares four settings");
    expectEqual(byKey[@"peek"][@"settings"][0], (@{ @"key" : @"peekToolbar", @"type" : @"bool", @"default" : @YES, @"min" : NSNull.null, @"max" : NSNull.null }), @"Peek's switch has no range");
    expectEqual([byKey[@"littleDia"][@"settings"] valueForKey:@"key"], (@[ @"littleDiaWidth", @"littleDiaHeight" ]), @"Little Dia declares its size");
    NSMutableArray<NSString *> *commandBarKeys = [NSMutableArray new];
    for (NSString *key in @[ @"commandBar", @"commandBarBlur", @"commandBarDarken", @"commandBarShadow" ])
        for (NSDictionary *setting in byKey[key][@"settings"]) [commandBarKeys addObject:setting[@"key"]];
    expectEqual(commandBarKeys, (@[ @"commandBarHeight", @"commandBarBlurRadius", @"commandBarBlurWindow", @"commandBarDarkness", @"commandBarShadowIntensity" ]), @"the command bar declares its five");

    expect(DPPeekDarkness() == DPDeclared(&DPPeek, @"peekDarkness")->defaultNumber, @"Peek's declared darkness is what it uses");
    expect(fabs(DPPeekResponse() - 0.24 / DPDeclared(&DPPeek, @"peekSpeed")->defaultNumber) < 1e-9, @"and its declared speed");
    expect(DPPeekGenie() == DPDeclared(&DPPeek, @"peekGenie")->defaultBool && DPPeekShowsToolbar() == DPDeclared(&DPPeek, @"peekToolbar")->defaultBool, @"and its two switches");
    expect(DPLittleDiaSize().width == DPDeclared(&DPLittleDia, @"littleDiaWidth")->defaultNumber && DPLittleDiaSize().height == DPDeclared(&DPLittleDia, @"littleDiaHeight")->defaultNumber,
           @"and Little Dia's declared size");
}

static void DPCheckImport(NSUserDefaults *defaults) {
    NSDictionary *excluded = DPExcludedValues();
    [defaults removePersistentDomainForName:gDomain];
    [excluded enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) { [defaults setObject:value forKey:key]; }];
    [defaults setBool:YES forKey:@"hideChatButton"];
    DPConfigImport *merged = DPImport(@"{\"version\": 1, \"tweaks\": {\"commandBar\": true}}", NO);
    expect(merged && merged.appliedCount == 1 && !merged.resetCount, @"Merge applies the one tweak the file names");
    expect([defaults boolForKey:@"commandBar"] && [defaults boolForKey:@"hideChatButton"], @"and leaves the others alone");
    expect(DPPatchNamed(@"commandBar")->on, @"and turns it on now");

    [defaults setBool:YES forKey:@"commandBarBlurWindow"];
    [defaults setObject:@"small" forKey:@"compactTabRowsSize"];
    NSString *replaceFile = @"{\"version\": 1, \"tweaks\": {\"commandBar\": false, \"nothingLikeThis\": true, \"localTweaks\": true},"
                            @" \"settings\": {\"commandBarPosition\": \"page\", \"profileColors\": {}, \"showExperimentalTweaks\": false, \"oldKnob\": 3}}";
    DPConfigImport *replaced = DPImport(replaceFile, YES);
    expect(replaced && replaced.appliedCount == 2, @"Replace All applies what the file names");
    expectEqual(replaced.unknownKeys, (@[ @"localTweaks", @"nothingLikeThis", @"oldKnob", @"profileColors", @"showExperimentalTweaks" ]), @"and reports what it skipped, Local Tweaks and machine state included");
    expect(![defaults objectForKey:@"hideChatButton"] && ![defaults objectForKey:@"commandBarBlurWindow"] && ![defaults objectForKey:@"compactTabRowsSize"], @"Replace All resets the tweaks and settings the file leaves out");
    expectEqual(@(replaced.resetCount), @3, @"and counts them");
    expect(![defaults boolForKey:@"commandBar"] && !DPPatchNamed(@"commandBar")->on, @"the file's false wins");
    expectEqual([defaults objectForKey:@"commandBarPosition"], @"page", @"and its choice is saved");
    [excluded enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        expectEqual([defaults objectForKey:key], value, [key stringByAppendingString:@" survives Replace All"]);
    }];

    DPConfigImport *loose = DPImport(@"{\"version\": 1, \"settings\": {\"commandBarPosition\": \"sideways\", \"commandBarHeight\": 0.9, \"commandBarBlurRadius\": 100, \"windowCornerRadius\": 12.5}}", NO);
    expect(loose && loose.appliedCount == 4, @"values off the menu or off the scale are accepted");
    expectEqual([defaults objectForKey:@"commandBarPosition"], @"sideways", @"a choice this Mac doesn't list is still saved");
    expect([defaults doubleForKey:@"commandBarHeight"] == 0.5 && [defaults doubleForKey:@"commandBarBlurRadius"] == 60 && [defaults doubleForKey:@"windowCornerRadius"] == 12.5, @"numbers are clamped to their range");
    expectEqual(@(loose.warnings.count), @3, @"and each says so");
    NSString *warned = [loose.warnings componentsJoinedByString:@"\n"];
    expect([warned containsString:@"Open New Tabs in Command Bar"] && [warned containsString:@"sideways"] && [warned containsString:@"commandBarHeight was 0.9"], @"naming the tweak and the value");

    DPConfigImport *keys = DPImport(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {}, \"extensionsMenuShortcut\": {\"key\": \"F5\", \"keyCode\": 96, \"modifiers\": 0},"
                                    @" \"undoCloseTabShortcut\": {\"key\": \"U\", \"keyCode\": 32, \"modifiers\": 1179648}, \"launchFlagsArgs\": \"--a=b --c=\\\"d e\\\"\", \"commandBarBlurWindow\": false}}", NO);
    expect(keys && keys.appliedCount == 5 && !keys.warnings.count, @"shortcuts, text and switches import");
    expectEqual([defaults objectForKey:@"pinTabShortcutKey"], @{}, @"a cleared shortcut stays cleared");
    expectEqual([defaults objectForKey:@"extensionsMenuShortcut"], (@{ @"key" : @"F5", @"keyCode" : @96, @"modifiers" : @0 }), @"a function key needs no modifier");
    expectEqual([defaults objectForKey:@"launchFlagsArgs"], @"--a=b --c=\"d e\"", @"flags keep their quotes");
    expect([[defaults objectForKey:@"commandBarBlurWindow"] isKindOfClass:NSNumber.class] && ![defaults boolForKey:@"commandBarBlurWindow"], @"a switch is saved");

    expectEqual([DPImport(@"{\"version\": 1}", NO) relaunchTitles], @[], @"an empty file changes nothing");
    expectEqual([DPImport(@"{\"version\": 1, \"tweaks\": {\"launchFlags\": true, \"littleDia\": true, \"commandBar\": true}}", NO) relaunchTitles],
                (@[ @"Launch Flags", @"Little Dia" ]), @"turning on a tweak that applies at launch asks for a relaunch");
    expectEqual([DPImport(@"{\"version\": 1, \"tweaks\": {\"launchFlags\": true, \"littleDia\": true}}", NO) relaunchTitles], @[], @"but only when it changed");
    expectEqual([DPImport(@"{\"version\": 1, \"settings\": {\"launchFlagsArgs\": \"--other\"}}", NO) relaunchTitles], @[ @"Launch Flags" ], @"new launch flags ask for one too");
    expectEqual([DPImport(@"{\"version\": 1, \"settings\": {\"littleDiaWidth\": 900}}", NO) relaunchTitles], @[], @"a Little Dia size doesn't");

    DPPatch *corners = DPPatchNamed(@"windowCorners");
    void (*cornersApply)(DPPatch *) = corners->apply;
    DPSaveOn(@"windowCorners", YES);
    corners->apply = DPCountApply;
    DPSafeMode = 0;
    gApplied = 0;
    DPImport(@"{\"version\": 1, \"settings\": {\"windowCornerRadius\": 10}}", NO);
    expectEqual(@(gApplied), @1, @"a changed number re-applies the tweak that is on");
    DPImport(@"{\"version\": 1, \"settings\": {\"windowCornerRadius\": 10}, \"tweaks\": {\"littleDia\": true}}", NO);
    expectEqual(@(gApplied), @2, @"and does so again");
    DPSafeMode = 1;
    corners->apply = cornersApply;
    DPSaveOn(@"windowCorners", NO);

    DPRejects(@"{", @"broken JSON");
    DPRejects(@"[]", @"a list");
    DPRejects(@"{\"tweaks\": {}}", @"a file with no version");
    DPRejects(@"{\"version\": 2}", @"version 2");
    DPRejects(@"{\"version\": true}", @"a true version");
    DPRejects(@"{\"version\": 1.5}", @"a fractional version");
    DPRejects(@"{\"version\": 1, \"extra\": 1}", @"a stray top-level key");
    DPRejects(@"{\"version\": 1, \"tweaks\": []}", @"tweaks as a list");
    DPRejects(@"{\"version\": 1, \"settings\": 4}", @"settings as a number");
    DPRejects(@"{\"version\": 1, \"tweaks\": {\"commandBar\": 1}}", @"a number for a switch");
    DPRejects(@"{\"version\": 1, \"tweaks\": {\"commandBar\": \"true\"}}", @"text for a switch");
    DPRejects(@"{\"version\": 1, \"tweaks\": {\"windowCorners\": true, \"commandBar\": null}}", @"one good tweak and one null");
    DPRejects(@"{\"version\": 1, \"settings\": {\"commandBarPosition\": 5}}", @"a number for a choice");
    DPRejects(@"{\"version\": 1, \"settings\": {\"commandBarDarkness\": \"dark\"}}", @"text for a number");
    DPRejects(@"{\"version\": 1, \"settings\": {\"commandBarDarkness\": true}}", @"a bool for a number");
    DPRejects(@"{\"version\": 1, \"settings\": {\"commandBarBlurWindow\": 1}}", @"a number for a bool");
    DPRejects(@"{\"version\": 1, \"settings\": {\"launchFlagsArgs\": \"--flag \\\"unclosed\"}}", @"an unclosed quote in launch flags");
    DPRejects(@"{\"version\": 1, \"settings\": {\"launchFlagsArgs\": \"notaflag\"}}", @"launch flags without --");
    DPRejects(@"{\"version\": 1, \"settings\": {\"launchFlagsArgs\": 5}}", @"a number for launch flags");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\"}}}", @"half a shortcut");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\", \"keyCode\": 2, \"modifiers\": 0}}}", @"a letter shortcut with no modifier");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\", \"keyCode\": 2, \"modifiers\": 131072}}}", @"a letter shortcut with only Shift");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\", \"keyCode\": true, \"modifiers\": 1048576}}}", @"a bool key code");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\", \"keyCode\": 70000, \"modifiers\": 1048576}}}", @"a huge key code");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\", \"keyCode\": 2, \"modifiers\": 1048577}}}", @"unknown modifier bits");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"\", \"keyCode\": 2, \"modifiers\": 1048576}}}", @"an empty key name");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\\n\", \"keyCode\": 2, \"modifiers\": 1048576}}}", @"a key name with a control character");
    DPRejects(@"{\"version\": 1, \"settings\": {\"pinTabShortcutKey\": {\"key\": \"D\", \"keyCode\": 2, \"modifiers\": 1048576, \"extra\": 1}}}", @"a shortcut with a stray field");
    NSError *tooBig = nil;
    expect(!DPImportConfigData([NSMutableData dataWithLength:2 << 20], NO, &tooBig) && tooBig, @"a file far bigger than any settings file is rejected");
}

static void DPCheckPreview(NSUserDefaults *defaults) {
    [defaults removePersistentDomainForName:gDomain];
    DPApplySavedSettings();

    NSData *clean = DPExportConfigJSON(NULL);
    DPConfigPreview *merge = DPPreviewConfigData(clean, NO, NULL);
    DPConfigPreview *replace = DPPreviewConfigData(clean, YES, NULL);
    expect(merge && replace, @"an export can be previewed");
    expect([merge isEmpty] && [replace isEmpty], @"and already matches the Mac it came from");
    expectEqual(@(merge.unknownKeys.count), @0, @"with nothing to skip");
    expect(!merge.setsLaunchFlags, @"and no launch flags to warn about");

    [defaults setObject:@"small" forKey:@"compactTabRowsSize"];
    [defaults setObject:@"window" forKey:@"commandBarPosition"];
    NSString *file = @"{\"version\": 1, \"tweaks\": {\"commandBar\": true}, \"settings\": {\"compactTabRowsSize\": \"compact\"}}";
    NSDictionary *before = DPSaved();
    merge = DPPreviewConfigData(DPData(file), NO, NULL);
    replace = DPPreviewConfigData(DPData(file), YES, NULL);
    expectEqual(@(merge.changes), @2, @"Merge counts the tweak and the choice it would change");
    expectEqual(@(merge.resets), @0, @"and resets nothing");
    expectEqual(@(replace.changes), @2, @"Replace All counts the same changes");
    expectEqual(@(replace.resets), @1, @"plus each saved value it would put back to its default");
    expectEqual(DPSaved(), before, @"a preview changes nothing");

    for (NSString *flagsFile in @[ @"{\"version\": 1, \"tweaks\": {\"launchFlags\": true}}",
                                   @"{\"version\": 1, \"settings\": {\"launchFlagsArgs\": \"--disable-gpu\"}}" ])
        expect(DPPreviewConfigData(DPData(flagsFile), NO, NULL).setsLaunchFlags, [flagsFile stringByAppendingString:@" is flagged for the trust warning"]);
    DPConfigPreview *note = DPPreviewConfigData(DPData(@"{\"version\": 1, \"settings\": {\"launchFlagsArgs\": \"# only a note\"}}"), NO, NULL);
    expect(note && !note.setsLaunchFlags, @"a comment-only launch flags value sets nothing");

    DPConfigPreview *skipped = DPPreviewConfigData(DPData(@"{\"version\": 1, \"settings\": {\"oldKnob\": 3}}"), NO, NULL);
    expect(skipped && [skipped isEmpty] && [skipped.unknownKeys isEqual:@[ @"oldKnob" ]], @"a file that only names unknown keys is a no-op that says what it skipped");

    [defaults setObject:@[ @"--disable-gpu", @"--foo=a b" ] forKey:@"launchFlagsArgs"];
    NSDictionary *exported = DPParse(DPExportConfigJSON(NULL));
    expectEqual(exported[@"settings"][@"launchFlagsArgs"], @"--disable-gpu\n\"--foo=a b\"", @"a launch flags array saved by an older version exports as the text the tweak reads");
    DPConfigPreview *roundTrip = DPPreviewConfigData([NSJSONSerialization dataWithJSONObject:exported options:0 error:NULL], NO, NULL);
    expect(roundTrip && [roundTrip isEmpty], @"and importing that text changes nothing");

    [defaults setObject:@"maybe" forKey:@"commandBar"];
    [defaults setObject:@{ @"a" : @"b" } forKey:@"windowCornerRadius"];
    [defaults setObject:@[ @"not a shortcut" ] forKey:@"pinTabShortcutKey"];
    exported = DPParse(DPExportConfigJSON(NULL));
    expectEqual(exported[@"tweaks"][@"commandBar"], @NO, @"a switch saved as text exports what boolValue gives it");
    expect(!exported[@"settings"][@"windowCornerRadius"] && !exported[@"settings"][@"pinTabShortcutKey"], @"a number saved as a dictionary and a shortcut saved as a list are left out");
    NSString *oddFile = @"{\"version\": 1, \"tweaks\": {\"commandBar\": true}, \"settings\": {\"windowCornerRadius\": 8, \"pinTabShortcutKey\": {}}}";
    DPConfigPreview *odd = DPPreviewConfigData(DPData(oddFile), NO, NULL);
    expect(odd && odd.changes == 3, @"odd saved values still preview as changes");
    DPConfigImport *fixed = DPImportConfigData(DPData(oddFile), NO, NULL);
    expect(fixed && fixed.appliedCount == 3, @"and import over them");
    exported = DPParse(DPExportConfigJSON(NULL));
    expectEqual(exported[@"tweaks"][@"commandBar"], @YES, @"the switch takes the file's value");
    expectEqual(exported[@"settings"][@"windowCornerRadius"], @8, @"the number does too");
    expectEqual(exported[@"settings"][@"pinTabShortcutKey"], @{}, @"and so does the cleared shortcut");

    [defaults removePersistentDomainForName:gDomain];
    DPApplySavedSettings();
}

static void DPCheckMigration(NSUserDefaults *defaults) {
    [defaults removePersistentDomainForName:gDomain];
    [defaults setBool:YES forKey:@"peek"];
    [defaults setBool:YES forKey:@"peekPinnedLinks"];
    [defaults setBool:YES forKey:@"peekDragLinks"];
    DPMigrateSettings(defaults);
    expect(![defaults boolForKey:@"peek"] && [defaults boolForKey:@"peekTurnedOffForNative"], @"the migration turns Peek off once and records it");
    expect([defaults boolForKey:@"peekPinnedLinks"] && [defaults boolForKey:@"peekDragLinks"], @"and leaves Peek's other switches alone");

    [defaults setBool:YES forKey:@"peek"];
    DPMigrateSettings(defaults);
    expect([defaults boolForKey:@"peek"], @"a Peek switched back on afterwards stays on");

    [defaults removePersistentDomainForName:gDomain];
    DPMigrateSettings(defaults);
    expect([defaults boolForKey:@"peekTurnedOffForNative"] && ![defaults objectForKey:@"peek"], @"a clean domain is marked without gaining a Peek switch");
    DPMigrateSettings(nil);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *home = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dp-config-%d", getpid()]];
        [NSFileManager.defaultManager removeItemAtPath:home error:NULL];
        [NSFileManager.defaultManager createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:NULL];
        gDomain = [home stringByAppendingPathComponent:@"defaults"];
        setenv("DIAPATCH_HOME", home.fileSystemRepresentation, 1);
        setenv("DIATWEAKS_DOMAIN", gDomain.fileSystemRepresentation, 1);
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_configInitWithSuiteName:)));
        class_replaceMethod(NSClassFromString(@"DPPreviewView"), @selector(load), imp_implementationWithBlock(^(id self) {}), "v@:");

        DPLoadPatches();
        DPSafeMode = 1;
        NSUserDefaults *defaults = DPSettingsDefaults();
        expectEqual(DPSettingsDomain(), gDomain, @"the tweaks follow DIATWEAKS_DOMAIN");

        DPPatch *unavailable = DPPatchNamed(@"hideChatButton");
        [defaults setBool:YES forKey:@"hideChatButton"];
        expect(unavailable->unavailable && !DPSavedOn(unavailable), @"Hide Chat Button is unavailable without Dia here");
        NSDictionary *exported = DPParse(DPExportConfigJSON(NULL));
        expectEqual(exported[@"tweaks"][@"hideChatButton"], @YES, @"a tweak this Mac can't run still exports what was saved");
        [defaults removeObjectForKey:@"hideChatButton"];
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->unavailable = NO;
        DPApplySavedSettings();

        DPCheckExperimentalData();
        DPCheckVisibility();
        DPCheckPages();
        DPCheckManifest();

        NSData *first = DPExportConfigJSON(NULL), *second = DPExportConfigJSON(NULL);
        expect(first && [first isEqualToData:second], @"two exports of the same settings are the same bytes");
        expect(first.length > 2 && !memcmp((const char *)first.bytes + first.length - 2, "}\n", 2), @"the file ends with a newline");
        exported = DPParse(first);
        expectEqual([exported.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[ @"settings", @"tweaks", @"version" ]), @"a file has a version, tweaks and settings");
        expectEqual(@([exported[@"tweaks"] count]), @(DPPatchCount - 1), @"every tweak but Local Tweaks has a switch");
        expectEqual(exported[@"settings"], @{}, @"nothing saved, nothing in settings");
        expect([exported[@"tweaks"][@"commandBarBlur"] boolValue] && ![exported[@"tweaks"][@"commandBar"] boolValue] && !exported[@"tweaks"][@"localTweaks"], @"tweaks export their default and skip Local Tweaks");

        [DPExcludedValues() enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) { [defaults setObject:value forKey:key]; }];
        [defaults setBool:YES forKey:@"commandBar"];
        [defaults setBool:YES forKey:@"windowCorners"];
        [defaults setObject:@"window" forKey:@"commandBarPosition"];
        [defaults setObject:@"small" forKey:@"compactTabRowsSize"];
        [defaults setObject:@{} forKey:@"pinTabShortcutKey"];
        NSDictionary *custom = @{ @"key" : @"U", @"keyCode" : @32, @"modifiers" : @(NSEventModifierFlagCommand | NSEventModifierFlagShift) };
        [defaults setObject:custom forKey:@"undoCloseTabShortcut"];
        [defaults setDouble:24.0 / 100 forKey:@"commandBarDarkness"];
        [defaults setDouble:12 forKey:@"windowCornerRadius"];
        [defaults setDouble:0 forKey:@"peekGenie"];
        [defaults setBool:YES forKey:@"commandBarBlurWindow"];
        [defaults setObject:@"--foo=bar --baz" forKey:@"launchFlagsArgs"];
        [defaults setObject:@7 forKey:@"savePageAsShortcut"];
        [defaults setObject:@[ @"--legacy" ] forKey:@"littleDiaWidth"];
        NSData *populated = DPExportConfigJSON(NULL);
        exported = DPParse(populated);
        NSDictionary *settings = exported[@"settings"];
        expectEqual(settings, (@{ @"commandBarPosition" : @"window", @"compactTabRowsSize" : @"small", @"pinTabShortcutKey" : @{}, @"undoCloseTabShortcut" : custom,
                                  @"commandBarDarkness" : @0.24, @"windowCornerRadius" : @12, @"peekGenie" : @NO, @"commandBarBlurWindow" : @YES,
                                  @"launchFlagsArgs" : @"--foo=bar --baz" }), @"settings export what was saved, a cleared shortcut as {}, and skip what is malformed");
        for (NSString *key in DPExcludedKeys()) expect(!settings[key] && !exported[@"tweaks"][key], [key stringByAppendingString:@" isn't exported"]);
        expect([[[NSString alloc] initWithData:populated encoding:NSUTF8StringEncoding] containsString:@"\"commandBarDarkness\" : 0.24,"], @"a saved fraction exports without float noise");

        [defaults removeObjectForKey:@"savePageAsShortcut"];
        [defaults removeObjectForKey:@"littleDiaWidth"];
        for (NSString *key in @[ @"commandBar", @"windowCorners", @"commandBarPosition", @"compactTabRowsSize", @"pinTabShortcutKey", @"undoCloseTabShortcut", @"commandBarDarkness",
                                 @"windowCornerRadius", @"peekGenie", @"commandBarBlurWindow", @"launchFlagsArgs" ])
            [defaults removeObjectForKey:key];
        DPConfigImport *restored = DPImportConfigData(populated, NO, NULL);
        expect(restored && restored.appliedCount == DPPatchCount - 1 + settings.count, @"importing an export applies every tweak and setting");
        expectEqual(restored.unknownKeys, @[], @"with nothing unknown");
        expectEqual(restored.warnings, @[], @"or to warn about");
        expectEqual([defaults objectForKey:@"pinTabShortcutKey"], @{}, @"a cleared shortcut comes back cleared");
        expectEqual([defaults objectForKey:@"undoCloseTabShortcut"], custom, @"a custom shortcut comes back");
        expect([defaults doubleForKey:@"commandBarDarkness"] == 0.24 && [defaults doubleForKey:@"windowCornerRadius"] == 12, @"numbers come back");
        expectEqual(DPExportConfigJSON(NULL), populated, @"an export of the import is the same bytes");

        DPCheckImport(defaults);
        DPCheckSingleApply();
        DPCheckPreview(defaults);
        DPCheckMigration(defaults);

        [NSFileManager.defaultManager removeItemAtPath:home error:NULL];
        if (failures) {
            printf("%d failure%s\n", failures, failures == 1 ? "" : "s");
            return 1;
        }
        printf("config-portability: all checks passed\n");
    }
    return 0;
}

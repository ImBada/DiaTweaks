#import "StdPatch/StdPatch.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"

static NSString *DPTestDomain(void) { return [NSString stringWithFormat:@"com.diapatches.launch-flags-test.%d", getpid()]; }

@interface NSUserDefaults (DPLaunchFlagsTest)
- (instancetype)dp_launchFlagsInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPLaunchFlagsTest)
- (instancetype)dp_launchFlagsInitWithSuiteName:(NSString *)suite {
    return [self dp_launchFlagsInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPTestDomain() : suite];
}
@end

static NSArray<NSString *> *seen;
static int seenCount;

@interface ArcBrowserApplicationConfiguration : NSObject
- (id)init:(int)argc argv:(NSArray<NSString *> *)argv profilePath:(NSString *)profilePath applicationID:(NSUInteger)applicationID
         isProduction:(BOOL)isProduction sessionRestorationPolicy:(NSUInteger)restorationPolicy shouldLoadAllProfilesAtStartup:(BOOL)loadAllProfiles
         quitRunLoopOnTermination:(BOOL)quitRunLoop userDefaultsSuiteName:(NSString *)suiteName;
@end
@implementation ArcBrowserApplicationConfiguration
- (id)init:(int)argc argv:(NSArray<NSString *> *)argv profilePath:(NSString *)profilePath applicationID:(NSUInteger)applicationID
         isProduction:(BOOL)isProduction sessionRestorationPolicy:(NSUInteger)restorationPolicy shouldLoadAllProfilesAtStartup:(BOOL)loadAllProfiles
         quitRunLoopOnTermination:(BOOL)quitRunLoop userDefaultsSuiteName:(NSString *)suiteName {
    seen = argv;
    seenCount = argc;
    return [super init];
}
@end

BOOL DPTesting = YES;
NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";

static NSArray<NSString *> *lastHandOff;
void DPHandOffAndQuit(NSArray<NSString *> *args) { lastHandOff = args; }
NSString *DPHintOf(NSView *view) { return nil; }
BOOL DPSavedOn(DPPatch *patch) { return patch->on; }
NSString *DPAppSupport(NSString *path) { return [@"/Users/test/Library/Application Support" stringByAppendingPathComponent:path]; }

#import "StdPatch/Extensions.m"
#import "Settings/Controls.m"
#import "Patches/LaunchFlags/Parse.m"
#import "Patches/LaunchFlags/LaunchFlags.m"
#import "Patches/LaunchFlags/Rows.m"

static NSString *const kDia = @"/Applications/Dia.app/Contents/MacOS/Dia";

static void DPResetFlags(void) {
    DPHookConfiguration();
    [DPExtensionFolders removeAllObjects];
    [DPAddedFlags removeAllObjects];
    [DPDroppedFlags removeAllObjects];
}

static NSArray<NSString *> *DPRunConfig(NSArray<NSString *> *argv) {
    (void)[[ArcBrowserApplicationConfiguration alloc] init:(int)argv.count argv:argv profilePath:@"" applicationID:1 isProduction:YES
                                  sessionRestorationPolicy:0 shouldLoadAllProfilesAtStartup:NO quitRunLoopOnTermination:NO userDefaultsSuiteName:nil];
    NSCAssert(seenCount == (int)seen.count, @"argc follows the argv it was given");
    return seen;
}

static NSArray<NSString *> *DPLaunch(NSArray<NSString *> *wanted, NSArray<NSString *> *argv) {
    DPResetFlags();
    for (NSString *folder in wanted) DPLoadExtension(folder);
    return DPRunConfig(argv);
}

static void expectLaunch(NSArray<NSString *> *wanted, NSArray<NSString *> *argv, NSArray<NSString *> *expected, NSString *what) {
    NSArray<NSString *> *got = DPLaunch(wanted, argv);
    NSCAssert([got isEqual:expected], @"%@, got %@", what, got);
}

static void testExtensionsAndDrop(void) {
    NSString *little = DPAppSupport(@"DiaPatches/little-dia-2ee7906f"), *older = DPAppSupport(@"DiaPatches/little-dia-48da710a");
    NSString *passkeys = DPAppSupport(@"DiaPatches/passkeys-extension"), *mine = @"/Users/test/Developer/my-extension";
    NSString *other = @"/Users/test/Developer/another-extension";
    NSString *sibling = DPAppSupport(@"DiaPatches-old/extension"), *prefixed = DPAppSupport(@"DiaPatchesExtra/extension");
    NSString *(^load)(NSString *) = ^(NSString *list) { return [@"--load-extension=" stringByAppendingString:list]; };
    NSString *(^pair)(NSString *, NSString *) = ^(NSString *a, NSString *b) { return [NSString stringWithFormat:@"%@,%@", a, b]; };

    expectLaunch(@[], @[ kDia ], @[ kDia ], @"nothing wanted, nothing added");
    expectLaunch(@[ little ], @[ kDia ], @[ kDia, load(little) ], @"a wanted folder is loaded");
    expectLaunch(@[ little, passkeys ], @[ kDia ], @[ kDia, load(pair(little, passkeys)) ], @"every wanted folder shares one flag");

    expectLaunch(@[ little ], @[ kDia, load(little), @"--restart" ], @[ kDia, @"--restart", load(little) ], @"a relaunch lists its folder once");
    expectLaunch(@[ little ], @[ kDia, load(@"/a"), @"--restart", @"--restart" ], @[ kDia, @"--restart", @"--restart", load(pair(@"/a", little)) ], @"other flags keep their order");

    expectLaunch(@[ little ], @[ kDia, load(pair(little, little)) ], @[ kDia, load(little) ], @"a folder carried twice comes back once");
    expectLaunch(@[ little ], @[ kDia, load(pair(pair(little, little), little)) ], @[ kDia, load(little) ], @"later relaunches don't add another copy");

    expectLaunch(@[ little ], @[ kDia, load(older) ], @[ kDia, load(little) ], @"a folder an update replaced is dropped");
    expectLaunch(@[ little ], @[ kDia, load(pair(older, little)), @"--restart" ], @[ kDia, @"--restart", load(little) ], @"the old folder goes, the current one stays");
    expectLaunch(@[], @[ kDia, load(older), @"--restart" ], @[ kDia, @"--restart" ], @"with the tweak off no folder is carried");
    expectLaunch(@[ passkeys ], @[ kDia, load(pair(pair(passkeys, older), little)) ], @[ kDia, load(passkeys) ], @"only the tweaks that are on keep a folder");
    expectLaunch(@[ little, passkeys ], @[ kDia, load(pair(pair(passkeys, older), little)) ], @[ kDia, load(pair(little, passkeys)) ], @"each wanted folder once, in the order it was added");

    expectLaunch(@[ little ], @[ kDia, load(pair(mine, older)) ], @[ kDia, load(pair(mine, little)) ], @"the user's own folder survives and stays first");
    expectLaunch(@[ little ], @[ kDia, load(mine), load(other), load(older) ], @[ kDia, load(pair(pair(mine, other), little)) ], @"several flags of the user's still merge");
    expectLaunch(@[], @[ kDia, load(pair(pair(sibling, older), prefixed)) ], @[ kDia, load(pair(sibling, prefixed)) ], @"folders beside DiaPatches aren't ours");
    expectLaunch(@[], @[ kDia, load(mine) ], @[ kDia, load(mine) ], @"a user's folder alone is untouched");
    expectLaunch(@[], @[ kDia, load(pair(mine, mine)) ], @[ kDia, load(pair(mine, mine)) ], @"the user's own repeats are theirs to keep");
    expectLaunch(@[ little ], @[ kDia, @"--load-extension=" ], @[ kDia, load(little) ], @"empty --load-extension= does not inject a leading comma");

    // Dropping a boolean flag or scalar comma-bearing flag must not mangle unrelated flags.
    DPResetFlags();
    DPDropLaunchFlag(@"--disable-gpu");
    DPDropLaunchFlag(@"--enable-features=Foo");
    DPDropLaunchFlag(@"--user-agent=a");
    DPDropLaunchFlag(@"--js-flags=--expose-gc,--max-old-space-size=4096");
    NSArray<NSString *> *got = DPRunConfig(@[
        kDia, @"--disable-gpu", @"--user-agent=a, b", @"--enable-features=Foo", @"--js-flags=--expose-gc,--max-old-space-size=4096",
    ]);
    NSCAssert([got isEqual:(@[ kDia, @"--user-agent=a, b" ])], @"scalar drop removes exact match and keeps unrelated comma-bearing flag, got %@", got);

    // User --load-extension= merges with DiaPatches extensions and cannot clobber or inject DiaPatches paths.
    DPResetFlags();
    DPLoadExtension(little);
    DPAddLaunchFlag(load(mine));
    DPAddLaunchFlag(load(DPAppSupport(@"DiaPatches/../DiaPatches/spoof")));
    DPAddLaunchFlag(@"--load-extension=");
    DPAddLaunchFlag(@"--load-extension");
    got = DPRunConfig(@[ kDia ]);
    NSCAssert([got isEqual:(@[ kDia, load(pair(mine, little)) ])], @"user --load-extension merges safely without clobbering DiaPatches, got %@", got);
}

static void testParsing(void) {
    NSArray<NSString *> *ignored = nil;
    BOOL unclosed = NO;

    NSArray<NSString *> *parsed = DPParseLaunchFlags(@"--force-renderer-accessibility=complete", &ignored, &unclosed);
    NSCAssert([parsed isEqual:@[ @"--force-renderer-accessibility=complete" ]] && !ignored.count && !unclosed, @"single flag, got %@", parsed);

    NSString *multi = @"# Accessibility for Cotypist\n"
                      @"--force-renderer-accessibility=complete\n\n"
                      @"  --enable-features=WebUIDarkMode  --disable-gpu  \n"
                      @"--js-flags=\"--expose-gc --max-old-space-size=4096\"\n"
                      @"--user-agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7), Custom'\n"
                      @"\"--proxy-server=http://127.0.0.1:8080\"\n"
                      @"--color=#ff0000 # trailing comment\n"
                      @"--path=/tmp/my\\ folder\n"
                      @"--disable-gpu\n";
    parsed = DPParseLaunchFlags(multi, &ignored, &unclosed);
    NSArray<NSString *> *expected = @[
        @"--force-renderer-accessibility=complete",
        @"--enable-features=WebUIDarkMode",
        @"--disable-gpu",
        @"--js-flags=--expose-gc --max-old-space-size=4096",
        @"--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7), Custom",
        @"--proxy-server=http://127.0.0.1:8080",
        @"--color=#ff0000",
        @"--path=/tmp/my folder",
    ];
    NSCAssert([parsed isEqual:expected] && !ignored.count && !unclosed, @"multi-line quoted/commented flags, got %@ ignored=%@", parsed, ignored);

    parsed = DPParseLaunchFlags(@"--good stray -single -- ---triple --=noname https://example.com --ok=1", &ignored, &unclosed);
    NSCAssert([parsed isEqual:(@[ @"--good", @"--ok=1" ])], @"rejects invalid tokens, got %@", parsed);
    NSCAssert([ignored isEqual:(@[ @"stray", @"-single", @"--", @"---triple", @"--=noname", @"https://example.com" ])],
              @"reports all ignored tokens, got %@", ignored);
    NSCAssert(!unclosed, @"no unclosed quote");

    parsed = DPParseLaunchFlags(@"--ok --user-agent=\"unclosed", &ignored, &unclosed);
    NSCAssert([parsed isEqual:@[ @"--ok" ]] && unclosed, @"detects unclosed quote, got %@ unclosed=%d", parsed, unclosed);

    parsed = DPParseLaunchFlags(@"   \n# just comments\n\t", &ignored, &unclosed);
    NSCAssert(parsed.count == 0 && !ignored.count && !unclosed, @"empty/comments only");

    // Formatting NSArray round-trips cleanly, including backslashes and quotes.
    NSString *formatted = DPFormatLaunchFlagsArray(@[ @"--disable-gpu", @"--js-flags=--expose-gc --max-old-space-size=4096", @"--regex=a\\\\b" ]);
    parsed = DPParseLaunchFlags(formatted, &ignored, &unclosed);
    NSCAssert([parsed isEqual:(@[ @"--disable-gpu", @"--js-flags=--expose-gc --max-old-space-size=4096", @"--regex=a\\\\b" ])], @"array round-trip, got %@", parsed);

    // Host resolver rules from TurnOffAI and Launch Flags merge cleanly.
    DPResetFlags();
    DPAddLaunchFlag(@"--host-resolver-rules=MAP ai-service.diabrowser.engineering ~NOTFOUND");
    DPAddLaunchFlag(@"--host-resolver-rules=MAP example.test 127.0.0.1");
    NSArray<NSString *> *merged = DPRunConfig(@[ kDia ]);
    NSCAssert([merged isEqual:(@[ kDia, @"--host-resolver-rules=MAP ai-service.diabrowser.engineering ~NOTFOUND,MAP example.test 127.0.0.1" ])],
              @"host-resolver-rules merge cleanly, got %@", merged);
}

static void testLifecycleAndSelfRelaunch(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    [defaults removeObjectForKey:DPArgsKey];
    [defaults removeObjectForKey:DPAppliedKey];

    // Off with no prior applied flags: does nothing.
    DPResetFlags();
    DPLaunchFlags.on = NO;
    DPPaused = NO;
    DPSafeMode = 0;
    DPInstallLaunchFlags();
    NSCAssert([DPRunConfig(@[ kDia ]) isEqual:@[ kDia ]] && !DPAddedFlags.count && !DPDroppedFlags.count, @"off tweak does nothing");

    // Launch 1: enable with multiple flags alongside SplitClientHello's feature flag.
    DPResetFlags();
    DPLaunchFlags.on = YES;
    DPLaunchFlagsSaveText(@"--force-renderer-accessibility=complete\n--enable-features=CustomFeat\n--user-agent=\"Foo, Bar\"");
    DPInstallLaunchFlags();
    DPAddLaunchFlag(@"--enable-features=NetworkServiceInProcess2");
    NSArray<NSString *> *launch1 = DPRunConfig(@[ kDia ]);
    NSCAssert([launch1 isEqual:(@[
        kDia,
        @"--force-renderer-accessibility=complete",
        @"--enable-features=CustomFeat,NetworkServiceInProcess2",
        @"--user-agent=Foo, Bar",
    ])], @"launch 1 injects custom flags and merges features, got %@", launch1);

    // Launch 2 (self-relaunch carrying launch1 argv): edit flags (keep accessibility, swap CustomFeat -> OtherFeat, change user-agent).
    DPResetFlags();
    DPLaunchFlags.on = YES;
    DPLaunchFlagsSaveText(@"--force-renderer-accessibility=complete\n--enable-features=OtherFeat\n--user-agent=\"Foo, Baz\"");
    DPInstallLaunchFlags();
    DPAddLaunchFlag(@"--enable-features=NetworkServiceInProcess2");
    NSArray<NSString *> *launch2 = DPRunConfig(launch1);
    NSCAssert([launch2 isEqual:(@[
        kDia,
        @"--enable-features=NetworkServiceInProcess2,OtherFeat",
        @"--force-renderer-accessibility=complete",
        @"--user-agent=Foo, Baz",
    ])], @"self-relaunch drops old flags without duplicating or mangling new ones, got %@", launch2);

    // Launch 3 (self-relaunch carrying launch2 argv): Pause Tweaks active -> drops stale custom flags and clears applied state!
    DPResetFlags();
    DPPaused = YES;
    DPLaunchFlags.on = NO;
    DPDropStaleLaunchFlags();
    NSArray<NSString *> *launch3 = DPRunConfig(launch2);
    NSCAssert([launch3 isEqual:(@[ kDia, @"--enable-features=NetworkServiceInProcess2" ])],
              @"pause strips stale custom flags on self-relaunch without touching other features, got %@", launch3);
    NSCAssert([defaults arrayForKey:DPAppliedKey] == nil, @"stale applied state cleared after pause cleanup");

    // Launch 4: re-enable, then disable -> turns off cleanly on self-relaunch.
    DPResetFlags();
    DPPaused = NO;
    DPLaunchFlags.on = YES;
    DPLaunchFlagsSaveText(@"--force-renderer-accessibility=complete");
    DPInstallLaunchFlags();
    NSArray<NSString *> *launch4 = DPRunConfig(@[ kDia ]);
    NSCAssert([launch4 isEqual:(@[ kDia, @"--force-renderer-accessibility=complete" ])], @"re-enabled launch 4, got %@", launch4);

    DPResetFlags();
    DPLaunchFlags.on = NO;
    DPInstallLaunchFlags();
    NSArray<NSString *> *launch5 = DPRunConfig(launch4);
    NSCAssert([launch5 isEqual:@[ kDia ]], @"disabling strips previously applied flag on self-relaunch, got %@", launch5);
    NSCAssert([defaults arrayForKey:DPAppliedKey] == nil, @"applied key cleared when off");

    // SafeMode: never injects flags and never touches applied state.
    DPResetFlags();
    DPLaunchFlags.on = YES;
    DPSafeMode = 1;
    DPInstallLaunchFlags();
    NSCAssert([DPRunConfig(@[ kDia ]) isEqual:@[ kDia ]] && !DPAddedFlags.count && !DPDroppedFlags.count, @"SafeMode skips launch flags");
    DPSafeMode = 0;

    // NSArray stored in defaults works too.
    [defaults setObject:@[ @"--disable-gpu", @"--js-flags=--expose-gc --max-old-space-size=4096" ] forKey:DPArgsKey];
    DPResetFlags();
    DPLaunchFlags.on = YES;
    DPInstallLaunchFlags();
    NSArray<NSString *> *fromArray = DPRunConfig(@[ kDia ]);
    NSCAssert([fromArray isEqual:(@[ kDia, @"--disable-gpu", @"--js-flags=--expose-gc --max-old-space-size=4096" ])],
              @"reads NSArray defaults cleanly, got %@", fromArray);
}

static void testSettingsRow(void) {
    [NSApplication sharedApplication];
    DPResetFlags();
    DPPaused = NO;
    DPSafeMode = 0;
    DPLaunchFlags.on = YES;
    DPLaunchFlagsSaveText(@"--force-renderer-accessibility=complete");
    DPInstallLaunchFlags();

    NSArray<NSView *> *rows = DPLaunchFlagsRows();
    NSCAssert(rows.count == 1 && [rows[0] isKindOfClass:DPLaunchFlagsRow.class], @"returns one DPLaunchFlagsRow");
    DPLaunchFlagsRow *row = (DPLaunchFlagsRow *)rows[0];
    NSCAssert([row.textView.string isEqual:@"--force-renderer-accessibility=complete"], @"loads saved flags text");
    NSCAssert(row.placeholder.hidden, @"hides placeholder when text present");
    NSCAssert(!row.textView.automaticDashSubstitutionEnabled && !row.textView.automaticQuoteSubstitutionEnabled,
              @"disables smart dash and quote substitutions");
    NSCAssert(row.relaunch.hidden && [row.status.stringValue isEqual:@"Active in this session."],
              @"shows active status without relaunch button when matching launched flags");

    // Editing flags saves to defaults and shows Relaunch button.
    row.textView.string = @"--force-renderer-accessibility=complete\n--disable-gpu";
    [row textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:row.textView]];
    NSCAssert([DPLaunchFlagsSavedText() isEqual:@"--force-renderer-accessibility=complete\n--disable-gpu"], @"editing persists text");
    NSCAssert(!row.relaunch.hidden && row.relaunch.enabled, @"editing shows enabled Relaunch button");
    lastHandOff = nil;
    [row.relaunch performClick:nil];
    NSCAssert([lastHandOff isEqual:@[ @"apply" ]], @"clicking Relaunch hands off to diapatch apply");

    // Syntax warning hides Relaunch on unclosed quote and flags ignored tokens.
    row.textView.string = @"--user-agent=\"unclosed";
    [row textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:row.textView]];
    NSCAssert(row.relaunch.hidden && [row.status.stringValue isEqual:@"Unclosed quote."], @"warns on unclosed quote");

    row.textView.string = @"--force-renderer-accessibility=complete stray";
    [row textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:row.textView]];
    NSCAssert([row.status.stringValue containsString:@"stray"], @"warns on ignored non-flag token");

    // Disabling row (off or paused) disables editor and dims container.
    row.enabled = NO;
    NSCAssert(!row.textView.editable && !row.textView.selectable && row.box.alphaValue < 1 && row.relaunch.hidden,
              @"disabled row locks editor, dims box, and hides relaunch");
    row.enabled = YES;
    NSCAssert(row.textView.editable && row.box.alphaValue == 1, @"re-enabling restores editor");

    // Clearing text shows placeholder again.
    row.textView.string = @"";
    [row textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:row.textView]];
    NSCAssert(!row.placeholder.hidden && !DPLaunchFlagsSavedText().length, @"clearing restores placeholder and removes default");

    // External defaults update synced via DPPatchesDidChangeNotification updates editor text and status.
    DPLaunchFlagsSaveText(@"--enable-logging=stderr");
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    NSCAssert([row.textView.string isEqual:@"--enable-logging=stderr"] && !row.relaunch.hidden,
              @"notification reloads externally edited flags and shows Relaunch");
    NSCAssert([row textView:row.textView doCommandBySelector:@selector(insertTab:)]
              && [row textView:row.textView doCommandBySelector:@selector(insertBacktab:)]
              && ![row textView:row.textView doCommandBySelector:@selector(insertNewline:)],
              @"Tab/Shift-Tab move focus while Return inserts newline");

    // Uncommitted text flushes on textDidEndEditing:, viewWillMoveToWindow:nil, and relaunchDia:, but NOT when disabled.
    row.textView.string = @"--force-dark-mode";
    [row textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification object:row.textView]];
    NSCAssert([DPLaunchFlagsSavedText() isEqual:@"--force-dark-mode"], @"textDidEndEditing flushes uncommitted text");

    NSWindow *hostWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 200)
                                                    styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    hostWin.releasedWhenClosed = NO;
    [hostWin.contentView addSubview:row];
    row.textView.string = @"--disable-gpu-vsync";
    [row removeFromSuperview];
    NSCAssert([DPLaunchFlagsSavedText() isEqual:@"--disable-gpu-vsync"], @"viewWillMoveToWindow:nil flushes uncommitted text");

    [hostWin.contentView addSubview:row];
    row.textView.string = @"--enable-features=FlushOnRelaunch";
    lastHandOff = nil;
    [row.relaunch performClick:nil];
    NSCAssert([DPLaunchFlagsSavedText() isEqual:@"--enable-features=FlushOnRelaunch"] && [lastHandOff isEqual:@[ @"apply" ]],
              @"relaunchDia flushes uncommitted text before handing off to diapatch");

    row.enabled = NO;
    row.textView.string = @"--must-not-save-while-disabled";
    [row textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification object:row.textView]];
    [row removeFromSuperview];
    NSCAssert([DPLaunchFlagsSavedText() isEqual:@"--enable-features=FlushOnRelaunch"],
              @"disabled row does not overwrite saved flags on blur or detach");
    row.enabled = YES;

    // Dark Aqua updateLayer resolves dynamic CGColors safely.
    row.box.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [row.box updateLayer];
    NSCAssert(row.box.layer.backgroundColor != NULL && row.box.layer.borderColor != NULL,
              @"DPLaunchFlagsBox updateLayer resolves dynamic colors under effectiveAppearance");
    [hostWin close];
}

int main(void) {
    @autoreleasepool {
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_launchFlagsInitWithSuiteName:)));
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:DPTestDomain()];

        testExtensionsAndDrop();
        testParsing();
        testLifecycleAndSelfRelaunch();
        testSettingsRow();

        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:DPTestDomain()];
        puts("all launch flag checks passed");
    }
}

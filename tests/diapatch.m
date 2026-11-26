#import <Foundation/Foundation.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <sys/stat.h>
#import "IconCatalog.h"

#define main diapatch_main
#import "main.m"
#undef main

static int gFailures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    gFailures++;
    fprintf(stderr, "FAIL %s\n", what.UTF8String);
}

static NSData *makeArm64MachO(uint32_t textOffset, uint32_t paddingSize) {
    struct mach_header_64 hdr = {
        .magic = MH_MAGIC_64,
        .cputype = CPU_TYPE_ARM64,
        .cpusubtype = CPU_SUBTYPE_ARM64_ALL,
        .filetype = MH_EXECUTE,
        .ncmds = 1,
        .sizeofcmds = sizeof(struct segment_command_64) + sizeof(struct section_64),
    };
    struct segment_command_64 seg = {
        .cmd = LC_SEGMENT_64,
        .cmdsize = sizeof(struct segment_command_64) + sizeof(struct section_64),
        .segname = SEG_TEXT,
        .vmaddr = 0x100000000ULL,
        .vmsize = 0x4000,
        .fileoff = 0,
        .filesize = textOffset + 16,
        .nsects = 1,
    };
    struct section_64 sect = {
        .sectname = SECT_TEXT,
        .segname = SEG_TEXT,
        .addr = 0x100000000ULL + textOffset,
        .size = 16,
        .offset = textOffset,
        .flags = S_REGULAR,
    };
    uint32_t total = MAX(textOffset + 16, (uint32_t)(sizeof hdr + hdr.sizeofcmds + paddingSize));
    NSMutableData *data = [NSMutableData dataWithLength:total];
    uint8_t *buf = data.mutableBytes;
    memcpy(buf, &hdr, sizeof hdr);
    memcpy(buf + sizeof hdr, &seg, sizeof seg);
    memcpy(buf + sizeof hdr + sizeof seg, &sect, sizeof sect);
    memset(buf + textOffset, 0x90, 16);
    return data;
}

static void testMachO(NSString *dir) {
    NSString *dylib = @"/tmp/test/DiaPatches.dylib";

    NSString *valid = [dir stringByAppendingPathComponent:@"valid"];
    [makeArm64MachO(512, 256) writeToFile:valid atomically:YES];
    struct stat before, after;
    expect(lstat(valid.fileSystemRepresentation, &before) == 0, @"valid Mach-O exists");
    expect(addLoadCommand(valid, dylib), @"addLoadCommand injects into thin arm64 binary");
    expect(lstat(valid.fileSystemRepresentation, &after) == 0 && after.st_ino != before.st_ino,
           @"addLoadCommand atomically replaces via temp file instead of mutating in place");
    expect(!exists([valid stringByAppendingString:@".tmp"]), @"addLoadCommand cleans up .tmp");
    NSData *patched = [NSData dataWithContentsOfFile:valid];
    const struct mach_header_64 *hdr = patched.bytes;
    expect(hdr->ncmds == 2, @"addLoadCommand increments ncmds");
    uint32_t cmdsAfterFirst = hdr->sizeofcmds;
    expect(addLoadCommand(valid, dylib), @"addLoadCommand is idempotent on already-patched binary");
    patched = [NSData dataWithContentsOfFile:valid];
    hdr = patched.bytes;
    expect(hdr->ncmds == 2 && hdr->sizeofcmds == cmdsAfterFirst, @"second addLoadCommand does not duplicate load command");

    // Malformed LC_SEGMENT_64 shorter than sizeof(struct segment_command_64) at EOF (previously OOB read).
    NSString *shortSeg = [dir stringByAppendingPathComponent:@"short-seg"];
    NSMutableData *bad = [NSMutableData dataWithLength:sizeof(struct mach_header_64) + sizeof(struct load_command)];
    struct mach_header_64 badHdr = {
        .magic = MH_MAGIC_64,
        .cputype = CPU_TYPE_ARM64,
        .ncmds = 1,
        .sizeofcmds = sizeof(struct load_command),
    };
    struct load_command badLc = { .cmd = LC_SEGMENT_64, .cmdsize = sizeof(struct load_command) };
    memcpy(bad.mutableBytes, &badHdr, sizeof badHdr);
    memcpy((uint8_t *)bad.mutableBytes + sizeof badHdr, &badLc, sizeof badLc);
    [bad writeToFile:shortSeg atomically:YES];
    expect(!addLoadCommand(shortSeg, dylib), @"rejects truncated LC_SEGMENT_64 without OOB read");

    // Unaligned cmdsize.
    NSString *unaligned = [dir stringByAppendingPathComponent:@"unaligned"];
    NSMutableData *badAlign = [NSMutableData dataWithLength:sizeof(struct mach_header_64) + 16];
    badHdr.sizeofcmds = 16;
    struct load_command unalignLc = { .cmd = LC_UUID, .cmdsize = 12 };
    memcpy(badAlign.mutableBytes, &badHdr, sizeof badHdr);
    memcpy((uint8_t *)badAlign.mutableBytes + sizeof badHdr, &unalignLc, sizeof unalignLc);
    [badAlign writeToFile:unaligned atomically:YES];
    expect(!addLoadCommand(unaligned, dylib), @"rejects unaligned load command cmdsize");

    // Insufficient room (non-zero byte in padding).
    NSString *tight = [dir stringByAppendingPathComponent:@"tight"];
    NSMutableData *dirtyPad = [makeArm64MachO(512, 256) mutableCopy];
    ((uint8_t *)dirtyPad.mutableBytes)[sizeof(struct mach_header_64) + sizeof(struct segment_command_64) + sizeof(struct section_64) + 4] = 0xAA;
    [dirtyPad writeToFile:tight atomically:YES];
    expect(!addLoadCommand(tight, dylib), @"rejects binary with non-zero padding");

    NSString *fat = [dir stringByAppendingPathComponent:@"fat"];
    struct fat_header fatHdr = { .magic = FAT_CIGAM, .nfat_arch = 0 };
    [[NSData dataWithBytes:&fatHdr length:sizeof fatHdr] writeToFile:fat atomically:YES];
    expect(!addLoadCommand(fat, dylib), @"rejects fat Mach-O");

    NSString *link = [dir stringByAppendingPathComponent:@"symlink"];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:valid error:NULL];
    expect(!addLoadCommand(link, dylib), @"refuses to patch through a symlink");
}

static void testMoveAndResumeApplyTweaks(NSString *dir) {
    gHome = [dir stringByAppendingPathComponent:@"home"];
    gCache = [dir stringByAppendingPathComponent:@"cache"];
    gApp = [dir stringByAppendingPathComponent:@"Dia.app"];
    gPristine = inHome(@"pristine/Dia.app");
    gStaged = inHome(@"staged/Dia.app");
    gReady = inHome(@"staged/ready");
    gStagedTweaks = inHome(@"staged/DiaTweaks");
    makeDir(inHome(@"bin"));

    NSString *src = [dir stringByAppendingPathComponent:@"new.bin"];
    NSString *dst = [dir stringByAppendingPathComponent:@"dst.bin"];
    [@"old" writeToFile:dst atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"new" writeToFile:src atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect(place(src, dst) == 0, @"place replaces regular file");
    expect(!exists(src), @"place removes source regular file immediately");
    expect([[NSString stringWithContentsOfFile:dst encoding:NSUTF8StringEncoding error:NULL] isEqual:@"new"], @"dst holds new contents");

    NSString *realDir = [dir stringByAppendingPathComponent:@"real-dir"];
    makeDir(realDir);
    NSString *dirLink = [dir stringByAppendingPathComponent:@"dir-link"];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:dirLink withDestinationPath:realDir error:NULL];
    NSString *swapSrc = [dir stringByAppendingPathComponent:@"swap-src"];
    makeDir(swapSrc);
    [@"marker" writeToFile:[swapSrc stringByAppendingPathComponent:@"marker"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect(place(swapSrc, dirLink) == 0, @"place replaces a symlink with a directory instead of failing with EINVAL");
    BOOL swapped = NO;
    expect([NSFileManager.defaultManager fileExistsAtPath:dirLink isDirectory:&swapped] && swapped
               && exists([dirLink stringByAppendingPathComponent:@"marker"]),
           @"the symlink is replaced by the directory itself");

    NSString *broken = [dir stringByAppendingPathComponent:@"broken-link"];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:broken withDestinationPath:@"/nonexistent/target" error:NULL];
    NSString *dirSrc = [dir stringByAppendingPathComponent:@"dir-src"];
    makeDir(dirSrc);
    expect(moveBundle(dirSrc, broken), @"moveBundle replaces broken symlink with directory");
    BOOL isDir = NO;
    expect([NSFileManager.defaultManager fileExistsAtPath:broken isDirectory:&isDir] && isDir, @"broken symlink replaced with dir");

    // Interrupted applyTweaks after RENAME_SWAP on app-icons must NOT swap old app-icons back on resume.
    NSString *installedIcons = inHome(@"app-icons");
    makeDir(installedIcons);
    [@"new-icon" writeToFile:[installedIcons stringByAppendingPathComponent:@"marker"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    makeDir(gStagedTweaks);
    NSString *leftoverOldIcons = [gStagedTweaks stringByAppendingPathComponent:@"app-icons"];
    makeDir(leftoverOldIcons);
    [@"old-icon" writeToFile:[leftoverOldIcons stringByAppendingPathComponent:@"marker"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    NSString *stagedDylib = [gStagedTweaks stringByAppendingPathComponent:@DYLIB];
    [@"new-dylib" writeToFile:stagedDylib atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"old-dylib" writeToFile:inHome(@DYLIB) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@{ @"digest" : @"sha256:new", @"tag" : @"v9.9.9" } writeToFile:[gStagedTweaks stringByAppendingPathComponent:@"release.plist"] atomically:YES];

    // Record expected inodes in .applying: app-icons points to installedIcons's inode (already swapped!), dylib still matches stagedDylib.
    NSDictionary *applying = @{
        @"app-icons" : inodeOf(installedIcons),
        @DYLIB : inodeOf(stagedDylib),
    };
    [applying writeToFile:[gStagedTweaks stringByAppendingPathComponent:@".applying"] atomically:YES];

    // Force offline latestTweaks so applyTweaks uses staged directly.
    setenv("DIAPATCH_RELEASES", "file:///nonexistent/releases.json", 1);
    expect(applyTweaks(), @"resumed applyTweaks succeeds");
    expect([[NSString stringWithContentsOfFile:[installedIcons stringByAppendingPathComponent:@"marker"] encoding:NSUTF8StringEncoding error:NULL] isEqual:@"new-icon"],
           @"resumed applyTweaks keeps new app-icons and discards leftover swapped-out old dir");
    expect([[NSString stringWithContentsOfFile:inHome(@DYLIB) encoding:NSUTF8StringEncoding error:NULL] isEqual:@"new-dylib"],
           @"resumed applyTweaks installs remaining staged files");
    expect(!exists(gStagedTweaks), @"resumed applyTweaks removes staged folder");
}

static void testFetchArgs(NSString *dir) {
    NSString *saved = env("DIAPATCH_HOME");
    setenv("DIAPATCH_HOME", [dir stringByAppendingPathComponent:@"fetch-home"].fileSystemRepresentation, 1);
    expect([fetchArgv(@"https://example.com/releases.json", 60, nil) containsObject:@"=https,file"],
           @"a test home may still fetch the file:// fixtures DIAPATCH_FEED and DIAPATCH_RELEASES name");
    unsetenv("DIAPATCH_HOME");
    NSArray<NSString *> *argv = fetchArgv(@"https://example.com/DiaTweaks.zip", 60, @"/tmp/DiaTweaks.zip");
    expect(![argv containsObject:@"=https,file"] && [argv containsObject:@"=https"],
           @"a URL read out of a release's JSON can't reach the local disk");
    expect([argv containsObject:@"--proto-redir"] && [argv.lastObject isEqual:@"/tmp/DiaTweaks.zip"],
           @"the download still writes to its file");
    if (saved) setenv("DIAPATCH_HOME", saved.fileSystemRepresentation, 1);
}

static void testFeedCache(NSString *dir) {
    gCache = [dir stringByAppendingPathComponent:@"feed-cache"];
    NSString *url = @"https://releases.example.com/BoostBrowser-updates.xml";
    expect(!cachedFeed(url), @"nothing is cached before the first check");
    rememberFeed(url, @"<rss/>");
    expect([cachedFeed(url) isEqual:@"<rss/>"], @"a feed is reused by the next status or update, not fetched twice");
    expect(!cachedFeed(@"https://example.com/release-candidate/BoostBrowser-updates.xml"), @"another channel isn't served the cached feed");
    [@{ @"url" : url, @"text" : @"<rss/>", @"saved" : [NSDate dateWithTimeIntervalSinceNow:-(kFeedCacheAge + 1)] }
        writeToFile:feedCachePath() atomically:YES];
    expect(!cachedFeed(url), @"an old feed is fetched again");
}

static void testNewer(void) {
    expect(!newer(@"14.0", @"14.0.0"), @"14.0 is not newer than 14.0.0");
    expect(!newer(@"14.0.0.0", @"14.0.0"), @"14.0.0.0 is not newer than 14.0.0");
    expect(newer(@"14.0.1", @"14.0"), @"14.0.1 is newer than 14.0");
    expect(newer(@"1.1.10", @"1.1.9"), @"1.1.10 is newer than 1.1.9");
    expect(!newer(@"1.1.9", @"1.1.10"), @"1.1.9 is not newer than 1.1.10");
    expect(newer(@"91402", @"91177"), @"91402 is newer than 91177");
    expect(!newer(@"91177", @"91177"), @"91177 is not newer than 91177");
    expect(newer(@"91402", nil), @"build is newer than nil");
    expect(!newer(nil, @"15.0.0"), @"nil is not newer than system version");
}

static void testBriefLanguage(NSString *dir) {
    NSString *app = [dir stringByAppendingPathComponent:@"BriefApp.app"];
    NSString *home = [dir stringByAppendingPathComponent:@"brief-home"];
    NSString *skillDir = [app stringByAppendingPathComponent:@"Contents/Resources/agent-server-resources/dist/prompts/skills/morning-brief"];
    NSString *skillPath = [skillDir stringByAppendingPathComponent:@"SKILL.md"];
    makeDir(skillDir);
    makeDir(home);

    NSString *domain = [dir stringByAppendingPathComponent:@"brief-prefs"];
    CFStringRef cfdom = (__bridge CFStringRef)domain;
    setenv("DIATWEAKS_DOMAIN", domain.UTF8String, 1);

    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguage"), kCFBooleanFalse, cfdom);
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect(DPPrepareBriefLanguage(app, home) == nil, @"briefLanguage off does nothing");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] isEqual:@"base"], @"SKILL.md untouched when off");

    CFPreferencesSetAppValue(CFSTR("briefLanguage"), kCFBooleanTrue, cfdom);
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    NSString *unsetResult = DPPrepareBriefLanguage(app, home);
    expect([unsetResult hasPrefix:@"set the Morning Brief's language to "], @"unset briefLanguageChoice defaults to system language");

    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("Japanese"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect([DPPrepareBriefLanguage(app, home) isEqual:@"set the Morning Brief's language to Japanese"], @"sets explicit Japanese");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] containsString:@"## Output language: Japanese"],
           @"appends Japanese heading");

    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("Klingon"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect([DPPrepareBriefLanguage(app, home) hasPrefix:@"kept the Morning Brief's language:"], @"rejects unknown language");

    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("Japanese"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    [NSData.data writeToFile:[home stringByAppendingPathComponent:@"paused"] atomically:YES];
    expect(DPPrepareBriefLanguage(app, home) == nil, @"paused skips patching SKILL.md");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] isEqual:@"base"], @"SKILL.md untouched when paused");
    [NSFileManager.defaultManager removeItemAtPath:[home stringByAppendingPathComponent:@"paused"] error:NULL];

    [@{ @"level" : @1 } writeToFile:[home stringByAppendingPathComponent:@"safe-mode.plist"] atomically:YES];
    expect(DPPrepareBriefLanguage(app, home) == nil, @"safe mode skips patching SKILL.md");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] isEqual:@"base"], @"SKILL.md untouched in safe mode");
    [NSFileManager.defaultManager removeItemAtPath:[home stringByAppendingPathComponent:@"safe-mode.plist"] error:NULL];

    expect([DPPrepareBriefLanguage(app, home) isEqual:@"set the Morning Brief's language to Japanese"], @"sets Japanese before switch");
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("French"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect([DPPrepareBriefLanguage(app, home) isEqual:@"set the Morning Brief's language to French"], @"switches to French cleanly");
    NSString *switched = [NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL];
    expect([switched containsString:@"## Output language: French"] && ![switched containsString:@"## Output language: Japanese"],
           @"re-applying BriefLanguage replaces previous language section without duplicating");

    CFPreferencesSetAppValue(CFSTR("briefLanguage"), NULL, cfdom);
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
}

static void testMigratesPeekOnce(NSString *dir) {
    NSString *domain = [dir stringByAppendingPathComponent:@"peek-prefs"];
    CFStringRef cfdom = (__bridge CFStringRef)domain;
    setenv("DIATWEAKS_DOMAIN", domain.fileSystemRepresentation, 1);
    CFPreferencesSetAppValue(CFSTR("peek"), kCFBooleanTrue, cfdom);
    CFPreferencesSetAppValue(CFSTR("peekPinnedLinks"), kCFBooleanTrue, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    DPMigratePrefs();
    expect(![DPPref(@"peek") boolValue] && [DPPref(@"peekTurnedOffForNative") boolValue], @"the first migration turns Peek off and records it");
    expect([DPPref(@"peekPinnedLinks") boolValue], @"and leaves Peek's other switches alone");

    CFPreferencesSetAppValue(CFSTR("peek"), kCFBooleanTrue, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    DPMigratePrefs();
    expect([DPPref(@"peek") boolValue], @"a Peek switched back on is kept by later migrations");

    for (NSString *key in @[ @"peek", @"peekPinnedLinks", @"peekTurnedOffForNative" ]) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    DPMigratePrefs();
    expect([DPPref(@"peekTurnedOffForNative") boolValue] && !DPPref(@"peek"), @"a clean domain is marked without gaining a Peek switch");
    for (NSString *key in @[ @"peek", @"peekTurnedOffForNative" ]) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    unsetenv("DIATWEAKS_DOMAIN");
}

static void testFeedFollowsDomain(NSString *dir) {
    NSString *domain = [dir stringByAppendingPathComponent:@"feed-prefs"];
    setenv("DIATWEAKS_DOMAIN", domain.fileSystemRepresentation, 1);
    unsetenv("DIAPATCH_FEED");
    CFPreferencesSetAppValue(CFSTR("diaFeed"), CFSTR("https://example.invalid/early-birds.xml"), (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    expect([diaFeed() isEqual:@"https://example.invalid/early-birds.xml"], @"the Early Birds feed is read from DIATWEAKS_DOMAIN");
    CFPreferencesSetAppValue(CFSTR("diaFeed"), NULL, (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    unsetenv("DIATWEAKS_DOMAIN");
}

static void testIconCatalog(NSString *dir) {
    NSString *bad = [dir stringByAppendingPathComponent:@"bad.car"];
    [@"corrupt" writeToFile:bad atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect([DPMergeCatalog(bad, bad) isEqual:@"couldn't open the catalogs"], @"DPMergeCatalog rejects corrupt .car");

    NSString *merged = [dir stringByAppendingPathComponent:@"merged.car"];
    expect([NSFileManager.defaultManager copyItemAtPath:@"assets/app-icons/AppIconBlue.car" toPath:merged error:NULL],
           @"copy synthetic Assets.car");
    expect(DPMergeCatalog(@"assets/app-icons/AppIconRed.car", merged) == nil, @"DPMergeCatalog merges AppIconRed into copy of AppIconBlue");
    id<DPAssetStorage> catalog = DPOpenCatalog(merged, NO);
    expect([catalog.allRenditionNames containsObject:@"AppIconBlue"] && [catalog.allRenditionNames containsObject:@"AppIconRed"],
           @"merged catalog retains existing icon and adds merged icon");
}

static void testUninstallPreservesStateWhenPristineMissing(NSString *dir) {
    gHome = [dir stringByAppendingPathComponent:@"u-home"];
    gApp = [dir stringByAppendingPathComponent:@"FakeDia.app"];
    gPristine = inHome(@"pristine/Dia.app");
    makeDir(gHome);
    makeDir(gApp);
    NSString *helper = inHome(@"passwords-helper");
    [@"keep" writeToFile:helper atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect(!uninstall(NO), @"uninstall fails when pristine is missing and app is not official");
    expect(exists(helper), @"failed uninstall does not tear down relay/files before pristine check");
}

static BOOL makeFakeDia(NSString *app, NSString *executable) {
    NSString *macOS = [app stringByAppendingPathComponent:@"Contents/MacOS"];
    return makeDir(macOS)
        && [@{ @"CFBundleExecutable" : @"Dia", @"CFBundleIdentifier" : @"company.thebrowser.dia", @"CFBundleShortVersionString" : @"1.0", @"CFBundleVersion" : @"1" }
               writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES]
        && [NSFileManager.defaultManager copyItemAtPath:executable toPath:[macOS stringByAppendingPathComponent:@"Dia"] error:NULL];
}

static NSArray<NSString *> *lsregisterCalls(NSString *log) {
    NSString *text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    return [[text componentsSeparatedByString:@"\n"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
}

static void testRegistersAfterSwap(NSString *dir) {
    NSString *log = [dir stringByAppendingPathComponent:@"lsregister.log"], *source = [dir stringByAppendingPathComponent:@"fake-dia.c"];
    NSString *executable = [dir stringByAppendingPathComponent:@"fake-dia"], *domain = [dir stringByAppendingPathComponent:@"register-prefs"];
    gHome = [dir stringByAppendingPathComponent:@"register-home"];
    gCache = [dir stringByAppendingPathComponent:@"register-cache"];
    gApp = [dir stringByAppendingPathComponent:@"Registered/Dia.app"];
    gPristine = inHome(@"pristine/Dia.app");
    gStaged = inHome(@"staged/Dia.app");
    gReady = inHome(@"staged/ready");
    [@"int main(void) { return 0; }\n" writeToFile:source atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    BOOL ready = run(@[ @"/usr/bin/clang", @"-Wl,-headerpad,0x4000", @"-o", executable, source ], NULL) == 0 && makeDir(gHome)
        && makeFakeDia(gApp, executable) && makeFakeDia(gPristine, executable)
        && [@"dylib" writeToFile:inHome(@DYLIB) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect(ready, @"a stand-in Dia and its pristine copy are made");
    if (!ready) return;

    setenv("DIATWEAKS_DOMAIN", domain.fileSystemRepresentation, 1);
    setenv("DIAPATCH_IDENTITY", "-", 1);
    setenv("DIAPATCH_LSREGISTER_LOG", log.fileSystemRepresentation, 1);
    gFailure = nil;
    expect(install(NO) && isPatched(gApp), @"install builds and applies a patched Dia");
    NSArray<NSString *> *expected = @[ [@"-u " stringByAppendingString:gPristine], [@"-u " stringByAppendingString:gStaged], [@"-f " stringByAppendingString:gApp] ];
    expect([lsregisterCalls(log) isEqual:expected], @"install forgets the pristine and staged copies, then registers the installed Dia last");

    removeTree(log);
    expect(build(gPristine) && exists(gStaged), @"a staged update is built");
    expect([lsregisterCalls(log) isEqual:@[ [@"-u " stringByAppendingString:gStaged] ]], @"building forgets the staged copy");
    removeTree(log);
    expect(apply() && !exists(gStaged), @"apply installs the staged update");
    expect([lsregisterCalls(log) isEqual:@[ [@"-f " stringByAppendingString:gApp] ]], @"apply registers the installed Dia after the swap");

    removeTree(log);
    expect(uninstall(NO) && !isPatched(gApp), @"uninstall puts the official Dia back");
    expect([lsregisterCalls(log) isEqual:@[ [@"-f " stringByAppendingString:gApp] ]], @"uninstall registers the restored Dia");

    unsetenv("DIAPATCH_LSREGISTER_LOG");
    unsetenv("DIAPATCH_IDENTITY");
    unsetenv("DIATWEAKS_DOMAIN");
}

static void testRootGuard(void) {
    unsetenv("DIAPATCH_ALLOW_ROOT");
    expect(refusesRoot(@"install", 0) && refusesRoot(@"apply", 0) && refusesRoot(@"local", 0), @"root can't change Dia or local tweaks");
    expect(!refusesRoot(@"status", 0) && !refusesRoot(@"check", 0) && !refusesRoot(@"--help", 0), @"root can still read status, check and help");
    expect(!refusesRoot(@"install", 501), @"a normal user can install");
    setenv("DIAPATCH_ALLOW_ROOT", "1", 1);
    expect(!refusesRoot(@"install", 0), @"DIAPATCH_ALLOW_ROOT lets root through");
    unsetenv("DIAPATCH_ALLOW_ROOT");
}

static void testLogCap(NSString *dir) {
    gHome = [dir stringByAppendingPathComponent:@"log-home"];
    makeDir(gHome);
    NSString *log = inHome(@"diapatch.log"), *old = inHome(@"diapatch.old.log");
    [[NSMutableData dataWithLength:(1 << 20) + 1] writeToFile:log atomically:YES];
    [@"older" writeToFile:old atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    struct stat before, after;
    gLog = fopen(log.fileSystemRepresentation, "ae");
    setvbuf(gLog, NULL, _IOLBF, 0);
    fstat(fileno(gLog), &before);
    capLog();
    note(@"after the cap");
    fstat(fileno(gLog), &after);
    fclose(gLog);
    expect(after.st_ino == before.st_ino, @"capping keeps the log's inode, which other runs lock");
    expect(after.st_size > 0 && after.st_size < 100, @"a log over 1 MB starts over");
    expect([[NSFileManager.defaultManager attributesOfItemAtPath:old error:NULL] fileSize] == (1 << 20) + 1, @"the full log replaces diapatch.old.log");

    gLog = fopen(log.fileSystemRepresentation, "ae");
    capLog();
    fstat(fileno(gLog), &before);
    fclose(gLog);
    gLog = NULL;
    expect(before.st_size == after.st_size, @"a small log is left alone");
}

static void testLoginKeychain(NSString *dir) {
    NSString *folder = [dir stringByAppendingPathComponent:@"Keychains"];
    NSString *legacy = [folder stringByAppendingPathComponent:@"login.keychain"], *current = [folder stringByAppendingPathComponent:@"login.keychain-db"];
    makeDir(folder);
    expect(!firstKeychain(@"security: SecKeychainCopyDefault: A default keychain could not be found.", folder), @"no keychain at all signs ad hoc");
    [NSData.data writeToFile:legacy atomically:YES];
    expect([firstKeychain(@"\"/nonexistent/login.keychain-db\"", folder) isEqual:legacy], @"a Mac migrated from before Sierra uses login.keychain");
    [NSData.data writeToFile:current atomically:YES];
    expect([firstKeychain(nil, folder) isEqual:current], @"login.keychain-db wins over login.keychain");
    expect([firstKeychain([NSString stringWithFormat:@"    \"%@\"\n", legacy], folder) isEqual:legacy], @"the default keychain security reports wins");
}

static void testHalfStagedApply(NSString *dir) {
    gHome = [dir stringByAppendingPathComponent:@"apply-home"];
    gApp = [dir stringByAppendingPathComponent:@"Applied.app"];
    gStaged = inHome(@"staged/Dia.app");
    gReady = inHome(@"staged/ready");
    makeDir([gStaged stringByAppendingPathComponent:@"Contents"]);
    gFailure = nil;
    expect(apply(), @"apply succeeds when a stopped build left an unfinished staged Dia");
    expect(!exists(gStaged) && !exists(gReady) && !exists(gApp), @"apply cleans up the unfinished staged Dia and never installs it");
    expect(!gFailure, @"cleaning up an unfinished staged Dia isn't an error");

    makeDir(gStaged);
    [@"1" writeToFile:gReady atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect(apply() && !exists(gStaged) && !exists(gReady) && !exists(gApp), @"apply discards an old Dia a stopped apply swapped into staged/");
}

static void testMoveDiagnosis(NSString *dir) {
    NSString *locked = [dir stringByAppendingPathComponent:@"locked"], *bundle = [dir stringByAppendingPathComponent:@"Incoming.app"];
    makeDir(locked);
    makeDir(bundle);
    gApp = [locked stringByAppendingPathComponent:@"Dia.app"];
    chmod(locked.fileSystemRepresentation, 0555);
    gFailure = nil;
    expect(!moveBundle(bundle, gApp) && exists(bundle), @"moveBundle can't replace Dia in a folder the user can't write");
    expect([gFailure containsString:@"isn't writable by your user account"] && [gFailure containsString:@"sudo chown -R"]
               && ![gFailure containsString:@"App Management"],
           @"an unwritable folder names ownership, not App Management");
    gHome = [locked stringByAppendingPathComponent:@"home"];
    expect(!makeDir(inHome(@"staged")) && [gFailure containsString:[@"your account can't write to " stringByAppendingString:locked]],
           @"makeDir names the folder the user can't write");
    chmod(locked.fileSystemRepresentation, 0755);
    NSString *missing = [NSHomeDirectory() stringByAppendingPathComponent:[@"Library/dp-missing-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    expect([unwritable(missing) containsString:[NSString stringWithFormat:@"sudo chown -R \"%@\" \"%@/Library\"", NSUserName(), NSHomeDirectory()]],
           @"a folder in the home folder gets the exact chown command for its nearest existing parent");

    gApp = bundle;
    expect([moveProblem(locked, gApp, EPERM) containsString:@"App Management"], @"EPERM in a writable folder points at App Management");
    expect([moveProblem(locked, gApp, EROFS) containsString:@"read-only volume"], @"EROFS names the read-only volume");
    expect(onReadOnlyVolume(@"/System/Library/CoreServices/Finder.app") && !onReadOnlyVolume(@"/Applications") && !onReadOnlyVolume(dir),
           @"onReadOnlyVolume tells the sealed system volume from the data volume");
}

static void testRememberedDia(NSString *dir) {
    gHome = [dir stringByAppendingPathComponent:@"remember-home"];
    NSString *own = [dir stringByAppendingPathComponent:@"Applications/Dia.app"];
    makeDir(own);
    makeDir(gHome);
    [own writeToFile:inHome(@"dia-app") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect([findDia() isEqual:own], @"apply from Dia's quit hook targets the Dia install patched, even outside /Applications");
    removeTree(own);
    expect(![findDia() isEqual:own], @"a Dia that has since moved isn't used");
}

static volatile sig_atomic_t gHangups;

static void countHangup(int number) { gHangups++; }

static void testShield(void) {
    signal(SIGHUP, countHangup);
    sigset_t previous = shield();
    raise(SIGHUP);
    expect(!gHangups, @"a hangup waits while a bundle is swapped");
    sigprocmask(SIG_SETMASK, &previous, NULL);
    expect(gHangups == 1, @"the hangup lands once the swap is done");
    signal(SIGHUP, SIG_DFL);
}

int main(void) {
    @autoreleasepool {
        gCommand = "test";
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"diapatch-test-%@", NSUUID.UUID.UUIDString]];
        makeDir(dir);
        setenv("DIAPATCH_HOME", dir.fileSystemRepresentation, 1);
        testMachO(dir);
        testMoveAndResumeApplyTweaks(dir);
        testNewer();
        testFetchArgs(dir);
        testFeedCache(dir);
        testBriefLanguage(dir);
        testFeedFollowsDomain(dir);
        testMigratesPeekOnce(dir);
        testIconCatalog(dir);
        testUninstallPreservesStateWhenPristineMissing(dir);
        testRootGuard();
        testLogCap(dir);
        testLoginKeychain(dir);
        testHalfStagedApply(dir);
        testMoveDiagnosis(dir);
        testShield();
        testRememberedDia(dir);
        testRegistersAfterSwap(dir);
        removeTree(dir);
    }
    if (!gFailures) puts("all diapatch checks passed");
    return gFailures ? 1 : 0;
}

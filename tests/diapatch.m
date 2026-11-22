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

    // Valid injection + atomic replacement + idempotency.
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

    // Fat binary rejected.
    NSString *fat = [dir stringByAppendingPathComponent:@"fat"];
    struct fat_header fatHdr = { .magic = FAT_CIGAM, .nfat_arch = 0 };
    [[NSData dataWithBytes:&fatHdr length:sizeof fatHdr] writeToFile:fat atomically:YES];
    expect(!addLoadCommand(fat, dylib), @"rejects fat Mach-O");

    // Symlink rejected.
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

    // Regular file moveBundle uses atomic rename (does NOT leave old file at src).
    NSString *src = [dir stringByAppendingPathComponent:@"new.bin"];
    NSString *dst = [dir stringByAppendingPathComponent:@"dst.bin"];
    [@"old" writeToFile:dst atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"new" writeToFile:src atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect(place(src, dst) == 0, @"place replaces regular file");
    expect(!exists(src), @"place removes source regular file immediately");
    expect([[NSString stringWithContentsOfFile:dst encoding:NSUTF8StringEncoding error:NULL] isEqual:@"new"], @"dst holds new contents");

    // Broken symlink at destination is cleanly replaced by both file and directory.
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

    NSString *domain = [NSString stringWithFormat:@"com.diapatches.test.brief.%d", getpid()];
    CFStringRef cfdom = (__bridge CFStringRef)domain;
    setenv("DIATWEAKS_DOMAIN", domain.UTF8String, 1);

    // Off: returns nil and leaves SKILL.md untouched.
    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguage"), kCFBooleanFalse, cfdom);
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect(DPPrepareBriefLanguage(app, home) == nil, @"briefLanguage off does nothing");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] isEqual:@"base"], @"SKILL.md untouched when off");

    // On with unset briefLanguageChoice (e.g. `diatweaks enable briefLanguage`): defaults to system language instead of failing!
    CFPreferencesSetAppValue(CFSTR("briefLanguage"), kCFBooleanTrue, cfdom);
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
    NSString *unsetResult = DPPrepareBriefLanguage(app, home);
    expect([unsetResult hasPrefix:@"set the Morning Brief's language to "], @"unset briefLanguageChoice defaults to system language");

    // On with explicit Japanese.
    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("Japanese"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect([DPPrepareBriefLanguage(app, home) isEqual:@"set the Morning Brief's language to Japanese"], @"sets explicit Japanese");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] containsString:@"## Output language: Japanese"],
           @"appends Japanese heading");

    // On with invalid choice.
    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("Klingon"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect([DPPrepareBriefLanguage(app, home) hasPrefix:@"kept the Morning Brief's language:"], @"rejects unknown language");

    // Paused: does nothing even when briefLanguage is enabled.
    [@"base" writeToFile:skillPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("Japanese"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    [NSData.data writeToFile:[home stringByAppendingPathComponent:@"paused"] atomically:YES];
    expect(DPPrepareBriefLanguage(app, home) == nil, @"paused skips patching SKILL.md");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] isEqual:@"base"], @"SKILL.md untouched when paused");
    [NSFileManager.defaultManager removeItemAtPath:[home stringByAppendingPathComponent:@"paused"] error:NULL];

    // Safe mode level > 0: skips patching SKILL.md just like AppIcon.
    [@{ @"level" : @1 } writeToFile:[home stringByAppendingPathComponent:@"safe-mode.plist"] atomically:YES];
    expect(DPPrepareBriefLanguage(app, home) == nil, @"safe mode skips patching SKILL.md");
    expect([[NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL] isEqual:@"base"], @"SKILL.md untouched in safe mode");
    [NSFileManager.defaultManager removeItemAtPath:[home stringByAppendingPathComponent:@"safe-mode.plist"] error:NULL];

    // Idempotent re-application replaces prior output language heading instead of duplicating.
    expect([DPPrepareBriefLanguage(app, home) isEqual:@"set the Morning Brief's language to Japanese"], @"sets Japanese before switch");
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), CFSTR("French"), cfdom);
    CFPreferencesAppSynchronize(cfdom);
    expect([DPPrepareBriefLanguage(app, home) isEqual:@"set the Morning Brief's language to French"], @"switches to French cleanly");
    NSString *switched = [NSString stringWithContentsOfFile:skillPath encoding:NSUTF8StringEncoding error:NULL];
    expect([switched containsString:@"## Output language: French"] && ![switched containsString:@"## Output language: Japanese"],
           @"re-applying BriefLanguage replaces previous language section without duplicating");

    // Clean up isolated preferences domain.
    CFPreferencesSetAppValue(CFSTR("briefLanguage"), NULL, cfdom);
    CFPreferencesSetAppValue(CFSTR("briefLanguageChoice"), NULL, cfdom);
    CFPreferencesAppSynchronize(cfdom);
}

static void testIconCatalog(NSString *dir) {
    // Corrupt .car files must fail gracefully without crashing.
    NSString *bad = [dir stringByAppendingPathComponent:@"bad.car"];
    [@"corrupt" writeToFile:bad atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    expect([DPMergeCatalog(bad, bad) isEqual:@"couldn't open the catalogs"], @"DPMergeCatalog rejects corrupt .car");

    // Merging one real asset catalog into a copy of another adds its renditions cleanly.
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

int main(void) {
    @autoreleasepool {
        gCommand = "test";
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"diapatch-test-%@", NSUUID.UUID.UUIDString]];
        makeDir(dir);
        testMachO(dir);
        testMoveAndResumeApplyTweaks(dir);
        testNewer();
        testBriefLanguage(dir);
        testIconCatalog(dir);
        testUninstallPreservesStateWhenPristineMissing(dir);
        removeTree(dir);
    }
    if (!gFailures) puts("all diapatch checks passed");
    return gFailures ? 1 : 0;
}

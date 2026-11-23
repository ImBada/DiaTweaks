#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <unistd.h>
#import "Local/Local.h"
#import "SafeMode/SafeMode.h"
#import "StdPatch/StdPatch.h"

// DiaPatches' constructor skips helper processes, so the test runs as one and loads the real patch
// table itself. DIAPATCH_HOME points at a scratch folder, so the operator's DiaPatches is never read.

static NSString *DPTestDomain(void) { return [NSString stringWithFormat:@"com.diapatches.local-test.%d", getpid()]; }

@interface NSUserDefaults (DPLocalTest)
- (instancetype)dp_localInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPLocalTest)
- (instancetype)dp_localInitWithSuiteName:(NSString *)suite {
    return [self dp_localInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPTestDomain() : suite];
}
@end

static int failures;
static NSString *gHome, *gLocal, *gLog, *gClangLog;

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

static void writeFile(NSString *path, NSString *text) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static NSArray<NSString *> *lines(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return text.length ? [text componentsSeparatedByString:@"\n"] : @[];
}

static NSUInteger count(NSString *path) {
    NSUInteger total = 0;
    for (NSString *line in lines(path)) if (line.length) total++;
    return total;
}

static void clearLog(void) { [NSFileManager.defaultManager removeItemAtPath:gLog error:NULL]; }

// A repaired link chain must end, and must never come back to where it started.
static BOOL DPNoCycle(DPPatch *patch) {
    DPPatch *walk = patch;
    for (int hops = 0; hops < 32; hops++) {
        walk = DPRequired(walk);
        if (!walk) return YES;
        if (walk == patch) return NO;
    }
    return NO;
}

static BOOL fileExistsUnder(NSString *folder, NSString *name) {
    for (NSString *relative in [NSFileManager.defaultManager enumeratorAtPath:folder])
        if ([relative.lastPathComponent isEqual:name]) return YES;
    return NO;
}

static NSUInteger sectionIndex(DPPatch *patch) { return (NSUInteger)(patch->order >> 24); }

static NSDictionary *stateItem(NSString *identifier) {
    NSData *data = [NSData dataWithContentsOfFile:[gHome stringByAppendingPathComponent:@"local-state.json"]];
    NSDictionary *state = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    for (NSDictionary *item in state[@"items"])
        if ([item[@"id"] isEqual:identifier]) return item;
    return nil;
}

static int run(NSArray<NSString *> *argv) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    task.standardOutput = task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:NULL]) return -1;
    [task waitUntilExit];
    return task.terminationStatus;
}

static NSString *const DPTweakSource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"#include <stdio.h>\n"
    @"#include <stdlib.h>\n"
    @"\n"
    @"static void DPNote(const char *what) {\n"
    @"    const char *path = getenv(\"DIAPATCH_TEST_LOG\");\n"
    @"    if (!path) return;\n"
    @"    FILE *file = fopen(path, \"a\");\n"
    @"    if (!file) return;\n"
    @"    fprintf(file, \"%s\\n\", what);\n"
    @"    fclose(file);\n"
    @"}\n"
    @"\n"
    @"static void DPInstall(void) { DPNote(\"install\"); }\n"
    @"static void DPApply(DPPatch *patch) { DPNote(patch->on ? \"apply-on\" : \"apply-off\"); }\n"
    @"static NSString *DPVerify(DPPatch *patch) { DPNote(\"verify\"); return nil; }\n"
    @"\n"
    @"DP_PATCH(MyTweak) {\n"
    @"    .key = @\"myTweak\",\n"
    @"    .defaultOn = NO,\n"
    @"    .title = @\"My Tweak\",\n"
    @"    .detail = @\"A local tweak.\",\n"
    @"    .section = @\"Local\",\n"
    @"    .install = DPInstall,\n"
    @"    .apply = DPApply,\n"
    @"    .verify = DPVerify,\n"
    @"};\n";

static NSString *const DPPatchFixture =
    @"diff --git a/Makefile b/Makefile\n"
    @"index 1111111..2222222 100644\n"
    @"--- a/Makefile\n"
    @"+++ b/Makefile\n"
    @"@@ -1,1 +1,1 @@\n"
    @"-CFLAGS := old\n"
    @"+CFLAGS := new\n"
    @"diff --git a/.github/ISSUE_TEMPLATE/bug.yml b/.github/ISSUE_TEMPLATE/bug.yml\n"
    @"index 1111111..2222222 100644\n"
    @"--- a/.github/ISSUE_TEMPLATE/bug.yml\n"
    @"+++ b/.github/ISSUE_TEMPLATE/bug.yml\n"
    @"@@ -1,1 +1,1 @@\n"
    @"-        - Old\n"
    @"+        - New\n"
    @"diff --git a/src/dylib/StdPatch/Dia.h b/src/dylib/StdPatch/Dia.h\n"
    @"index 1111111..2222222 100644\n"
    @"--- a/src/dylib/StdPatch/Dia.h\n"
    @"+++ b/src/dylib/StdPatch/Dia.h\n"
    @"@@ -1,1 +1,2 @@\n"
    @" #define DPDiaExisting \"X\"\n"
    @"+#define DPDiaFakeTestView \"NSView\"\n"
    @"diff --git a/src/dylib/Patches/MyPR/MyPR.m b/src/dylib/Patches/MyPR/MyPR.m\n"
    @"new file mode 100644\n"
    @"index 0000000..3333333\n"
    @"--- /dev/null\n"
    @"+++ b/src/dylib/Patches/MyPR/MyPR.m\n"
    @"@@ -0,0 +1,9 @@\n"
    @"+#import \"StdPatch/StdPatch.h\"\n"
    @"+\n"
    @"+NSString *DPMyPRViewName(void) { return @(DPDiaFakeTestView); }\n"
    @"+\n"
    @"+DP_PATCH(MyPR) {\n"
    @"+    .key = @\"myPR\",\n"
    @"+    .title = @\"My PR\",\n"
    @"+    .detail = @\"From a patch.\",\n"
    @"+    .section = @\"Local\",\n"
    @"+};\n";

static NSString *const DPBuiltInFixture =
    @"diff --git a/src/dylib/Patches/EdgeToEdge/EdgeToEdge.m b/src/dylib/Patches/EdgeToEdge/EdgeToEdge.m\n"
    @"index 1111111..2222222 100644\n"
    @"--- a/src/dylib/Patches/EdgeToEdge/EdgeToEdge.m\n"
    @"+++ b/src/dylib/Patches/EdgeToEdge/EdgeToEdge.m\n"
    @"@@ -1,1 +1,1 @@\n"
    @"-old\n"
    @"+new\n";

static NSString *const DPCycleSource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"DP_PATCH(CycleA) { .key = @\"cycleA\", .title = @\"Cycle A\", .detail = @\"\", .section = @\"Local\", .requires = @\"cycleB\" };\n"
    @"DP_PATCH(CycleB) { .key = @\"cycleB\", .title = @\"Cycle B\", .detail = @\"\", .section = @\"Local\", .requires = @\"cycleA\" };\n";

static NSString *const DPDuplicateSource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"DP_PATCH(Duplicate) { .key = @\"hideToolbar\", .title = @\"Duplicate\", .detail = @\"\", .section = @\"Local\" };\n";

static NSString *const DPMissingSymbolSource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"extern void DPNotARealSymbol(void);\n"
    @"static void DPUse(void) { DPNotARealSymbol(); }\n"
    @"DP_PATCH(Missing) { .key = @\"missing\", .title = @\"Missing\", .detail = @\"\", .section = @\"Local\", .install = DPUse };\n";

static NSString *const DPBrokenSource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"DP_PATCH(Broken) { .key = @\"broken\", .title = @\"Broken\", .detail = @\"\", .section = @\"Local\" }\n";

static NSString *const DPNoABISource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"DPPatch NoABI = { .key = @\"noABI\", .title = @\"No ABI\", .detail = @\"\", .section = @\"Local\" };\n"
    @"__attribute__((used, section(\"__DATA,__dppatches\"))) static DPPatch *const NoABIEntry = &NoABI;\n";

static NSString *const DPTraversalFixture =
    @"diff --git a/src/dylib/../../escaped/Evil.m b/src/dylib/../../escaped/Evil.m\n"
    @"new file mode 100644\n"
    @"index 0000000..4444444\n"
    @"--- /dev/null\n"
    @"+++ b/src/dylib/../../escaped/Evil.m\n"
    @"@@ -0,0 +1,2 @@\n"
    @"+#import \"StdPatch/StdPatch.h\"\n"
    @"+DP_PATCH(Evil) { .key = @\"evil\", .title = @\"Evil\", .detail = @\"\", .section = @\"Local\" };\n";

static NSString *const DPOldABISource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"DPPatch OldABI = { .key = @\"oldABI\", .title = @\"Old ABI\", .detail = @\"\", .section = @\"Local\" };\n"
    @"__attribute__((used, section(\"__DATA,__dppatches\"))) static DPPatch *const OldABIEntry = &OldABI;\n"
    @"__attribute__((used, section(\"__DATA,__dpabi\"))) static const struct { uint32_t abi, patchSize; } OldABIStamp = { 1, 999 };\n";

static BOOL compileFixture(NSString *source, NSString *output, NSString *headers) {
    NSString *folder = [gHome stringByAppendingPathComponent:@"fixtures"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *file = [folder stringByAppendingPathComponent:output.lastPathComponent.stringByDeletingPathExtension];
    file = [file stringByAppendingString:@".m"];
    writeFile(file, source);
    return run(@[ @"/usr/bin/xcrun", @"--sdk", @"macosx", @"clang", @"-arch", @"arm64", @"-fobjc-arc", @"-O0", @"-w",
                  @"-I", headers, @"-dynamiclib", @"-undefined", @"dynamic_lookup",
                  @"-framework", @"Foundation", @"-framework", @"AppKit", @"-o", output, file ]) == 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_localInitWithSuiteName:)));

        gHome = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dp-local-%d", getpid()]];
        [NSFileManager.defaultManager removeItemAtPath:gHome error:NULL];
        [NSFileManager.defaultManager createDirectoryAtPath:gHome withIntermediateDirectories:YES attributes:nil error:NULL];
        gLocal = [gHome stringByAppendingPathComponent:@"local"];
        gLog = [gHome stringByAppendingPathComponent:@"calls.log"];
        gClangLog = [gHome stringByAppendingPathComponent:@"clang.log"];
        setenv("DIAPATCH_HOME", gHome.fileSystemRepresentation, 1);
        setenv("DIAPATCH_TEST_LOG", gLog.fileSystemRepresentation, 1);

        // A wrapper around the real clang, so the test can prove the warm path never compiles.
        NSString *realClang = nil;
        NSTask *find = [NSTask new];
        find.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xcrun"];
        find.arguments = @[ @"--find", @"clang" ];
        NSPipe *pipe = NSPipe.pipe;
        find.standardOutput = pipe;
        [find launch];
        realClang = [[[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [find waitUntilExit];
        NSString *wrapper = [gHome stringByAppendingPathComponent:@"clang-wrapper.sh"];
        writeFile(wrapper, [NSString stringWithFormat:@"#!/bin/sh\nprintf 'run\\n' >> \"$DIAPATCH_CLANG_LOG\"\nexec \"$DIAPATCH_REAL_CLANG\" \"$@\"\n"]);
        [NSFileManager.defaultManager setAttributes:@{ NSFilePosixPermissions : @0755 } ofItemAtPath:wrapper error:NULL];
        setenv("DIAPATCH_CLANG", wrapper.fileSystemRepresentation, 1);
        setenv("DIAPATCH_CLANG_LOG", gClangLog.fileSystemRepresentation, 1);
        setenv("DIAPATCH_REAL_CLANG", realClang.fileSystemRepresentation, 1);

        writeFile([gLocal stringByAppendingPathComponent:@"MyTweak.m"], DPTweakSource);
        DPLoadPatches();
        DPPatch *tweak = DPPatchNamed(@"myTweak");
        expect(tweak != NULL, @"a single .m tweak loads");
        expect(DPPatchCount == 106, @"the table holds the 105 official tweaks and the local one");
        expect(DPIsLocalPatch(tweak), @"the tweak is marked local");
        expectEqual(tweak->section, @"Local", @"a local tweak defaults to the Local section");
        expectEqual(tweak->tint, @"systemOrangeColor", @"a local tweak defaults to the orange tint");
        expectEqual(stateItem(@"MyTweak")[@"status"], @"loaded", @"the state file says it loaded");
        // Settings and `diatweaks local` read the state back through DPLocalItems, so it must see "loaded" too.
        NSDictionary *listed = nil;
        for (NSDictionary *item in DPLocalItems()) if ([item[@"id"] isEqual:@"MyTweak"]) listed = item;
        expectEqual(listed[@"status"], @"loaded", @"DPLocalItems reads the loaded status back");
        expect(count(gClangLog) == 1, @"the first load compiles it once");

        clearLog();
        if (tweak) {
            tweak->install();
            tweak->apply(tweak);
            tweak->verify(tweak);
        }
        expectEqual(lines(gLog), (@[ @"install", @"apply-off", @"verify", @"" ]), @"install, apply and verify run");

        clearLog();
        DPSetPatch(tweak, YES, YES);
        DPSetPatch(tweak, NO, YES);
        DPSetPatch(tweak, YES, YES);
        expectEqual(lines(gLog), (@[ @"apply-on", @"apply-off", @"apply-on", @"" ]), @"the switch applies both ways");

        NSUInteger builds = count(gClangLog);
        DPLocalReset();
        DPLoadPatches();
        expect(DPPatchNamed(@"myTweak") != NULL, @"the tweak is still there on a warm load");
        expect(count(gClangLog) == builds, @"a warm load doesn't compile anything");

        setenv("DIAPATCH_DYLIB_UUID", "11111111-2222-3333-4444-555555555555", 1);
        DPLocalReset();
        DPLoadPatches();
        expect(count(gClangLog) == builds + 1, @"a new DiaTweaks recompiles the tweak");
        expect(DPPatchNamed(@"myTweak") != NULL, @"the tweak survives a DiaTweaks update");
        expect(DPSavedOn(DPPatchNamed(@"myTweak")), @"its saved switch survives too");
        unsetenv("DIAPATCH_DYLIB_UUID");

        writeFile([gLocal stringByAppendingPathComponent:@"pr-557.patch"], DPPatchFixture);
        DPLocalReset();
        DPLoadPatches();
        expect(DPPatchNamed(@"myPR") != NULL, @"a PR .patch with a Dia.h define loads");
        expectEqual(stateItem(@"pr-557")[@"status"], @"loaded", @"the patch is recorded as loaded");

        writeFile([gLocal stringByAppendingPathComponent:@"pr-354.patch"], DPBuiltInFixture);
        DPLocalReset();
        DPLoadPatches();
        expectEqual(stateItem(@"pr-354")[@"status"], @"failed", @"a patch to a built-in tweak fails");
        expect([stateItem(@"pr-354")[@"error"] containsString:@"Modifies built-in file EdgeToEdge.m"], @"it says which built-in file it changes");

        writeFile([gLocal stringByAppendingPathComponent:@"Broken.m"], DPBrokenSource);
        writeFile([gLocal stringByAppendingPathComponent:@"Duplicate.m"], DPDuplicateSource);
        writeFile([gLocal stringByAppendingPathComponent:@"Cycle.m"], DPCycleSource);
        NSString *headers = DPLocalHeaders(NULL);
        expect(headers.length > 0, @"the dylib carries its headers");
        expect(compileFixture(DPMissingSymbolSource, [gLocal stringByAppendingPathComponent:@"Missing.dylib"], headers), @"the missing-symbol fixture builds");
        expect(compileFixture(DPOldABISource, [gLocal stringByAppendingPathComponent:@"OldABI.dylib"], headers), @"the old-ABI fixture builds");
        expect(compileFixture(DPNoABISource, [gLocal stringByAppendingPathComponent:@"NoABI.dylib"], headers), @"the no-ABI fixture builds");
        writeFile([gLocal stringByAppendingPathComponent:@"pr-evil.patch"], DPTraversalFixture);
        NSString *zipSource = [gHome stringByAppendingPathComponent:@"zipsrc"];
        writeFile([zipSource stringByAppendingPathComponent:@"Sneaky.m"], @"#import \"StdPatch/StdPatch.h\"\n");
        expect(symlink("/etc/passwd", [zipSource stringByAppendingPathComponent:@"link"].fileSystemRepresentation) == 0, @"the symlink fixture is made");
        expect(run(@[ @"/usr/bin/ditto", @"-c", @"-k", zipSource, [gLocal stringByAppendingPathComponent:@"Sneaky.zip"] ]) == 0, @"the symlink zip is made");
        DPLocalReset();
        DPLoadPatches();
        expectEqual(stateItem(@"Broken")[@"status"], @"failed", @"a syntax error fails the build");
        expect([stateItem(@"Broken")[@"error"] containsString:@"Broken.m"], @"the compiler error names the file");
        expectEqual(stateItem(@"Missing")[@"status"], @"incompatible", @"a dylib with a missing symbol is refused");
        expect([stateItem(@"Missing")[@"error"] containsString:@"symbol not found"], @"it says the symbol is missing");
        expectEqual(stateItem(@"OldABI")[@"status"], @"incompatible", @"a dylib built for another ABI is refused");
        expect([stateItem(@"OldABI")[@"error"] containsString:@"older DiaTweaks ABI"], @"it says to recompile");
        expectEqual(stateItem(@"NoABI")[@"status"], @"incompatible", @"a dylib with no ABI stamp is refused");
        expect([stateItem(@"NoABI")[@"error"] containsString:@"older DiaTweaks ABI"], @"it says to recompile too");
        expectEqual(stateItem(@"pr-evil")[@"status"], @"failed", @"a .patch that climbs out of the folder is refused");
        expect(!fileExistsUnder(gHome, @"Evil.m"), @"nothing is written outside the build folder");
        expectEqual(stateItem(@"Sneaky")[@"status"], @"failed", @"a .zip with a symlink is refused");
        expect([stateItem(@"Sneaky")[@"error"] containsString:@"symbolic link"], @"it says the archive has a symlink");
        expect(DPPatchNamed(@"hideToolbar") != NULL, @"the official tweak keeps its key");
        expectEqual(DPPatchNamed(@"hideToolbar")->title, @"Hide Toolbar", @"a duplicate key doesn't replace the official tweak");
        expect([stateItem(@"Duplicate")[@"error"] containsString:@"hideToolbar"], @"the duplicate key is reported");
        expect(DPPatchNamed(@"cycleA") != NULL && DPPatchNamed(@"cycleB") != NULL, @"a cyclic pair still loads");
        expect(DPNoCycle(DPPatchNamed(@"cycleA")) && DPNoCycle(DPPatchNamed(@"cycleB")), @"the cycle is broken, not followed");
        expect([stateItem(@"Cycle")[@"error"] containsString:@"isn’t there"], @"the dropped link is noted in the state file");
        expect(DPPatchNamed(@"myTweak") != NULL, @"the good tweaks still load alongside the broken ones");

        NSUInteger localSection = sectionIndex(DPPatchNamed(@"myTweak")), lastSection = 0;
        for (NSUInteger i = 0; i < DPPatchCount; i++) lastSection = MAX(lastSection, sectionIndex(DPPatches[i]));
        expect(localSection == lastSection, @"the Local section sorts last in Settings");

        DPPatch *master = DPPatchNamed(@"localTweaks"), *mine = DPPatchNamed(@"myTweak");
        expect(master != NULL && mine != NULL, @"the master switch and the local tweak are both in the table");
        DPSetPatch(mine, YES, YES);
        DPSetPatch(master, NO, YES);
        expect(!mine->on, @"turning Local Tweaks off stops the loaded local tweak");
        expect(DPSavedOn(mine), @"its own saved switch is left alone");
        DPSetPatch(master, YES, YES);
        expect(mine->on, @"turning Local Tweaks back on restores it");

        NSString *manifest = [gHome stringByAppendingPathComponent:@"patches.json"];
        expect(DPWriteManifest(manifest), @"the manifest writes");
        NSDictionary *written = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] options:0 error:NULL];
        NSMutableArray<NSString *> *keys = [NSMutableArray new];
        for (NSDictionary *patch in written[@"patches"]) [keys addObject:patch[@"key"]];
        expect([keys containsObject:@"localTweaks"], @"the Local Tweaks switch itself is in the manifest");
        expect(![keys containsObject:@"myTweak"], @"a local tweak is not in the manifest");
        expect(![keys containsObject:@"myPR"], @"a local patch is not in the manifest");

        printf(failures ? "%d local tweak checks failed\n" : "local tweaks: all checks passed\n", failures);
        [NSFileManager.defaultManager removeItemAtPath:gHome error:NULL];
        return failures ? 1 : 0;
    }
}

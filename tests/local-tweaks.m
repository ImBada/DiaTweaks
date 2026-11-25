#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <sys/stat.h>
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

static NSString *identity(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0) return @"";
    return [NSString stringWithFormat:@"%llu %ld.%ld", (unsigned long long)info.st_ino, info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
}

static BOOL exists(NSString *path) { return [NSFileManager.defaultManager fileExistsAtPath:path]; }

static NSArray<NSString *> *clangRunsSince(NSUInteger before) {
    NSArray<NSString *> *all = [lines(gClangLog) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    return all.count > before ? [all subarrayWithRange:NSMakeRange(before, all.count - before)] : @[];
}

static _Atomic int gServed, gServedConditional;
static NSData *gServerBody;

static int startCatalogServer(void) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = { .sin_len = sizeof address, .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
    socklen_t length = sizeof address;
    if (bind(listener, (struct sockaddr *)&address, sizeof address) != 0 || listen(listener, 8) != 0
        || getsockname(listener, (struct sockaddr *)&address, &length) != 0)
        return 0;
    [NSThread detachNewThreadWithBlock:^{
        for (int client; (client = accept(listener, NULL, NULL)) >= 0; close(client)) {
            char request[8192] = { 0 };
            for (ssize_t used = 0, got; used < (ssize_t)sizeof request - 1 && !strstr(request, "\r\n\r\n"); used += got)
                if ((got = read(client, request + used, sizeof request - 1 - used)) <= 0) break;
            BOOL conditional = strcasestr(request, "If-None-Match: \"v1\"") != NULL;
            gServed++;
            gServedConditional += conditional;
            NSString *head = conditional ? @"HTTP/1.1 304 Not Modified\r\nETag: \"v1\"\r\nConnection: close\r\n\r\n"
                                         : [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nETag: \"v1\"\r\nContent-Type: application/json\r\n"
                                                                      @"Content-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)gServerBody.length];
            NSMutableData *reply = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            if (!conditional) [reply appendData:gServerBody];
            write(client, reply.bytes, reply.length);
        }
    }];
    return ntohs(address.sin_port);
}

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


static NSString *captured(void (^block)(void)) {
    NSString *path = [gHome stringByAppendingPathComponent:@"captured.txt"];
    fflush(NULL);
    int out = dup(1), err = dup(2), file = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    dup2(file, 1);
    dup2(file, 2);
    block();
    fflush(NULL);
    dup2(out, 1);
    dup2(err, 2);
    close(out);
    close(err);
    close(file);
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
}

static NSString *tweakSource(NSString *name, NSString *key, NSString *title, NSString *detail) {
    return [NSString stringWithFormat:@"#import \"StdPatch/StdPatch.h\"\n"
                                      @"DP_PATCH(%@) { .key = @\"%@\", .title = @\"%@\", .detail = @\"%@\", .symbol = @\"star.fill\", "
                                      @".tint = @\"systemPinkColor\", .section = @\"Toolbar\" };\n",
                                      name, key, title, detail];
}

static NSDictionary *listing(NSString *key, NSString *title, NSString *detail, NSString *requires) {
    return @{ @"key" : key, @"title" : title, @"detail" : detail, @"symbol" : @"star.fill", @"tint" : @"systemPinkColor",
              @"section" : @"Toolbar", @"defaultOn" : @NO, @"requires" : requires ?: NSNull.null, @"relaunch" : @NO };
}

static void writeCatalog(NSString *folder, NSArray *tweaks) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{ @"tweaks" : tweaks } options:NSJSONWritingPrettyPrinted error:NULL];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [json writeToFile:[folder stringByAppendingPathComponent:@"index.json"] atomically:YES];
}

static NSArray<NSString *> *ids(NSArray<NSDictionary *> *entries) {
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (NSDictionary *entry in entries) [names addObject:entry[@"id"]];
    return names;
}

static NSArray<NSString *> *folderListing(NSString *folder) {
    return [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:NULL] sortedArrayUsingSelector:@selector(compare:)] ?: @[];
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

static NSString *const DPFolderSource =
    @"#import \"StdPatch/StdPatch.h\"\n"
    @"#import \"Header.h\"\n"
    @"DP_PATCH(FolderTweak) { .key = @\"folderTweak\", .title = DPFolderTitle, .detail = @\"\", .section = @\"Local\" };\n";

static NSString *keyedSource(NSString *name, NSString *key) {
    return [NSString stringWithFormat:@"#import \"StdPatch/StdPatch.h\"\nDP_PATCH(%@) { .key = @\"%@\", .title = @\"%@\", .detail = @\"\", .section = @\"Local\" };\n", name, key, name];
}

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
        unsetenv("DIATWEAKS_DOMAIN");
        if (argc > 1 && !strcmp(argv[1], "--type=local-build")) return DPLocalBuildMain(@[ @"diapatch", @"local", @"build" ]) ? 0 : 1;
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
        writeFile(wrapper, @"#!/bin/sh\nprintf 'run %s\\n' \"$*\" >> \"$DIAPATCH_CLANG_LOG\"\nexec \"$DIAPATCH_REAL_CLANG\" \"$@\"\n");
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
        NSString *statePath = [gHome stringByAppendingPathComponent:@"local-state.json"], *warmState = identity(statePath);
        DPLocalReset();
        DPLoadPatches();
        expectEqual(identity(statePath), warmState, @"a warm load leaves local-state.json alone");

        setenv("DIAPATCH_DYLIB_UUID", "11111111-2222-3333-4444-555555555555", 1);
        DPLocalReset();
        DPLoadPatches();
        expect(count(gClangLog) == builds + 1, @"a new DiaTweaks recompiles the tweak");
        expect(DPPatchNamed(@"myTweak") != NULL, @"the tweak survives a DiaTweaks update");
        expect(DPSavedOn(DPPatchNamed(@"myTweak")), @"its saved switch survives too");
        unsetenv("DIAPATCH_DYLIB_UUID");

        // Rebuild All runs with the tweaks already loaded, so a loaded tweak must not collide with itself.
        DPLocalReset();
        DPLoadPatches();
        builds = count(gClangLog);
        NSString *report = nil;
        expect(DPLocalBuildAll(nil, &report), [@"rebuilding a loaded tweak succeeds: " stringByAppendingString:report ?: @""]);
        expect(![report containsString:@"already has"], @"a loaded tweak doesn't collide with its own key");
        expectEqual(stateItem(@"MyTweak")[@"status"], @"loaded", @"an untouched loaded tweak stays loaded after a rebuild");
        expect(count(gClangLog) == builds, @"a rebuild of unchanged tweaks compiles nothing");

        expect(DPLocalBuildAllForced(nil, YES, &report), @"a forced rebuild of a loaded tweak succeeds");
        expect(count(gClangLog) == builds + 1, @"a forced rebuild compiles the tweak again");
        expectEqual(stateItem(@"MyTweak")[@"status"], @"loaded", @"a forced rebuild of an untouched tweak keeps it loaded");
        expect(DPLocalBuildMain(@[ @"diapatch", @"local", @"build", @"--force" ]), @"`local build --force` succeeds");
        expect(count(gClangLog) == builds + 2, @"`local build --force` compiles it too, and --force isn't taken for a name");
        expect(DPLocalBuildMain(@[ @"diapatch", @"local", @"build" ]) && count(gClangLog) == builds + 2, @"`local build` without --force stays warm");

        NSString *loadedDylib = stateItem(@"MyTweak")[@"dylib"], *backup = [gHome stringByAppendingPathComponent:@"MyTweak.backup"];
        NSDictionary *unchanged = stateItem(@"MyTweak");
        writeFile(backup, @"not a dylib");
        expect(renamex_np(loadedDylib.fileSystemRepresentation, backup.fileSystemRepresentation, RENAME_SWAP) == 0, @"the built tweak is swapped for garbage");
        expect(run(@[ NSBundle.mainBundle.executablePath, @"--type=local-build" ]) == 0, @"a fresh `local build` of unchanged tweaks succeeds");
        expectEqual(stateItem(@"MyTweak"), unchanged, @"it reuses the recorded tweak without loading the dylib");
        expect(count(gClangLog) == builds + 2, @"and without compiling it");
        renamex_np(loadedDylib.fileSystemRepresentation, backup.fileSystemRepresentation, RENAME_SWAP);

        writeFile([gLocal stringByAppendingPathComponent:@"MyTweak.m"], [DPTweakSource stringByReplacingOccurrencesOfString:@"A local tweak." withString:@"An edited local tweak."]);
        expect(DPLocalBuildAll(nil, &report), @"rebuilding an edited tweak succeeds");
        expect(count(gClangLog) == builds + 3, @"an edited tweak is compiled");
        expectEqual(stateItem(@"MyTweak")[@"status"], @"ready", @"an edited tweak waits for a relaunch");
        DPLocalReset();
        DPLoadPatches();
        expect(count(gClangLog) == builds + 3, @"a load right after the rebuild finds it ready and compiles nothing");
        expectEqual(DPPatchNamed(@"myTweak")->detail, @"An edited local tweak.", @"the relaunch loads the edited tweak");
        expectEqual(stateItem(@"MyTweak")[@"status"], @"loaded", @"it is loaded again after the relaunch");

        NSString *folderTweak = [gLocal stringByAppendingPathComponent:@"FolderTweak"], *header = [folderTweak stringByAppendingPathComponent:@"Header.h"];
        writeFile([folderTweak stringByAppendingPathComponent:@"FolderTweak.m"], DPFolderSource);
        writeFile(header, @"#define DPFolderTitle @\"Folder Tweak\"\n");
        builds = count(gClangLog);
        DPLocalReset();
        DPLoadPatches();
        expectEqual(stateItem(@"FolderTweak")[@"status"], @"loaded", @"a folder tweak loads");
        expect(count(gClangLog) == builds + 1, @"a folder tweak is compiled once");
        writeFile(header, @"#define DPFolderTitle @\"Folder Tweak Two\"\n");
        expect(DPLocalBuildAll(nil, &report), @"rebuilding after a header edit succeeds");
        expect(count(gClangLog) == builds + 2, @"a header edit recompiles the folder tweak");
        expectEqual(stateItem(@"FolderTweak")[@"status"], @"ready", @"a header edit leaves the folder tweak waiting for a relaunch");
        expectEqual(stateItem(@"MyTweak")[@"status"], @"loaded", @"its neighbour is still loaded");
        writeFile(header, @"#define DPFolderTitle @\"Folder Tweak Three\"\n");
        DPLocalReset();
        DPLoadPatches();
        expect(count(gClangLog) == builds + 3, @"a header edit recompiles the folder tweak on a load too");
        expectEqual(DPPatchNamed(@"folderTweak")->title, @"Folder Tweak Three", @"the load picks up the edited header");
        [NSFileManager.defaultManager removeItemAtPath:folderTweak error:NULL];

        // diapatch builds with nothing loaded, so two tweaks claiming one key have to be caught by the build itself.
        writeFile([gLocal stringByAppendingPathComponent:@"Dup1.m"], keyedSource(@"DupOne", @"dupKey"));
        writeFile([gLocal stringByAppendingPathComponent:@"Dup2.m"], keyedSource(@"DupTwo", @"dupKey"));
        DPLocalReset();
        expect(!DPLocalBuildAll(nil, &report), @"two tweaks with one key fail the build");
        expectEqual(stateItem(@"Dup1")[@"status"], @"ready", @"the first one keeps the key");
        expectEqual(stateItem(@"Dup2")[@"status"], @"failed", @"the second one is refused");
        expect([stateItem(@"Dup2")[@"error"] containsString:@"already has"] && [report containsString:@"dupKey"], @"it says the key is taken");
        expect(!DPLocalBuildAll(@[ @"Dup2" ], &report), @"building just the second still sees the first one's key");
        expectEqual(stateItem(@"Dup2")[@"status"], @"failed", @"it stays refused");
        expect(DPLocalBuildAll(@[ @"Dup1" ], &report), @"building just the first is fine");
        expectEqual(stateItem(@"Dup1")[@"status"], @"ready", @"and it stays ready");
        for (NSString *name in @[ @"Dup1.m", @"Dup2.m" ]) [NSFileManager.defaultManager removeItemAtPath:[gLocal stringByAppendingPathComponent:name] error:NULL];
        writeFile([gLocal stringByAppendingPathComponent:@"MyTweak.m"], DPTweakSource);

        writeFile([gLocal stringByAppendingPathComponent:@"pr-557.patch"], DPPatchFixture);
        DPLocalReset();
        DPLoadPatches();
        expect(DPPatchNamed(@"myPR") != NULL, @"a PR .patch with a Dia.h define loads");
        expectEqual(stateItem(@"pr-557")[@"status"], @"loaded", @"the patch is recorded as loaded");
        builds = count(gClangLog);
        expect(DPLocalBuildAllForced(nil, YES, &report), @"a forced rebuild covers a patch tweak");
        expect(count(gClangLog) == builds + 2, @"a forced rebuild compiles the source and the patch tweak once each");
        expectEqual(stateItem(@"pr-557")[@"status"], @"loaded", @"an untouched patch stays loaded");

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

        [NSFileManager.defaultManager removeItemAtPath:gLocal error:NULL];
        setenv("DIAPATCH_DYLIB_UUID", "pch-test", 1);
        NSString *cache = DPLocalCacheFolder(), *kept = [cache stringByAppendingPathComponent:@"bin/Kept-cafebabe.dylib"];
        NSString *staleStaging = [cache stringByAppendingPathComponent:@"staging/stale"], *freshStaging = [cache stringByAppendingPathComponent:@"staging/fresh"];
        for (NSString *name in @[ @"PchOne", @"PchTwo" ]) writeFile([gLocal stringByAppendingPathComponent:[name stringByAppendingString:@".m"]], keyedSource(name, name.lowercaseString));
        for (NSString *path in @[ @"headers/old-id/StdPatch/StdPatch.h", @"bin/Old-deadbeef.dylib", @"bin/Kept-cafebabe.dylib", @"extracted/Gone/1-1/Gone.m", @"staging/stale/Stale.m", @"staging/fresh/Fresh.m" ])
            writeFile([cache stringByAppendingPathComponent:path], @"");
        [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate : [NSDate dateWithTimeIntervalSinceNow:-3600] } ofItemAtPath:staleStaging error:NULL];
        DPLocalWriteState(@[ @{ @"id" : @"Kept", @"kind" : @"dylib", @"path" : @"/nonexistent/Kept.dylib", @"status" : @"loaded", @"patches" : @[], @"dylib" : kept } ]);
        DPLocalReset();
        builds = count(gClangLog);
        expect(DPLocalBuildAll(nil, &report), [@"two new tweaks build: " stringByAppendingString:report ?: @""]);
        NSArray<NSString *> *runs = clangRunsSince(builds);
        expect(runs.count == 3 && [runs[0] containsString:@"objective-c-header"], @"two tweaks build one shared PCH first");
        expect(runs.count == 3 && [runs[1] containsString:@"-include-pch"] && [runs[2] containsString:@"-include-pch"], @"and both compile against it");
        expectEqual(stateItem(@"PchOne")[@"status"], @"ready", @"the first PCH tweak is ready");
        expectEqual(stateItem(@"PchTwo")[@"status"], @"ready", @"the second PCH tweak is ready");
        expect(!exists([cache stringByAppendingPathComponent:@"headers/old-id"]) && exists([cache stringByAppendingPathComponent:@"headers/pch-test/.done"]),
               @"a full build keeps only the current headers");
        expect(!exists([cache stringByAppendingPathComponent:@"bin/Old-deadbeef.dylib"]), @"a full build drops a dylib nothing uses");
        expect(exists(kept), @"it keeps a dylib the previous state still names");
        expect(exists(stateItem(@"PchOne")[@"dylib"]) && exists(stateItem(@"PchTwo")[@"dylib"]), @"it keeps the dylibs it just built");
        expect(!exists([cache stringByAppendingPathComponent:@"extracted/Gone"]), @"it drops the sources of a tweak that's gone");
        expect(!exists(staleStaging) && exists(freshStaging), @"it drops an abandoned download but not one in progress");
        DPLocalReset();
        DPLoadPatches();
        expect(DPPatchNamed(@"pchone") && DPPatchNamed(@"pchtwo"), @"tweaks built against the PCH load");
        NSString *firstBuild = stateItem(@"PchOne")[@"dylib"];
        writeFile([gLocal stringByAppendingPathComponent:@"PchOne.m"], keyedSource(@"PchOneEdited", @"pchOneEdited"));
        builds = count(gClangLog);
        expect(DPLocalBuildAll(nil, &report), @"an edited PCH tweak rebuilds");
        runs = clangRunsSince(builds);
        expect(runs.count == 1 && [runs[0] containsString:@"-include-pch"], @"one edited tweak reuses the PCH and compiles once");
        expect(exists(firstBuild) && exists(stateItem(@"PchOne")[@"dylib"]), @"the dylib Dia still has loaded survives the rebuild");
        [NSFileManager.defaultManager removeItemAtPath:freshStaging error:NULL];
        unsetenv("DIAPATCH_DYLIB_UUID");


        // Optional tweaks: a catalog served from a folder, through the same NSURLSession path as GitHub.
        [NSFileManager.defaultManager removeItemAtPath:gLocal error:NULL];
        DPLocalWriteState(@[]);
        DPLocalReset();
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
        NSString *catalogDir = [gHome stringByAppendingPathComponent:@"catalog"], *stagingDir = [DPLocalCacheFolder() stringByAppendingPathComponent:@"staging"];
        setenv("DIAPATCH_CATALOG_URL", catalogDir.fileSystemRepresentation, 1);
        NSString *catalogError = @"unset";

        expect(DPLocalCachedCatalog() == nil, @"nothing is cached before the first fetch");
        expectEqual(DPLocalFetchCatalog(&catalogError), @[], @"a catalog that isn’t there yet is an empty one");
        expect(catalogError == nil, @"a missing index isn’t an error");
        expectEqual(DPLocalCachedCatalog(), @[], @"the empty catalog is cached");
        writeCatalog(catalogDir, @[]);
        expectEqual(DPLocalFetchCatalog(&catalogError), @[], @"an empty index is an empty catalog");

        writeFile([catalogDir stringByAppendingPathComponent:@"CatalogSingle.m"], tweakSource(@"CatalogSingle", @"catalogSingle", @"Catalog Single", @"Downloaded from the catalog."));
        writeFile([catalogDir stringByAppendingPathComponent:@"PrevOn.m"], tweakSource(@"PrevOn", @"prevOn", @"Prev On", @"Was on before."));
        writeFile([catalogDir stringByAppendingPathComponent:@"ExplicitOff.m"], tweakSource(@"ExplicitOff", @"explicitOff", @"Explicit Off", @"Was switched off."));
        writeFile([catalogDir stringByAppendingPathComponent:@"Collide.m"], tweakSource(@"Collide", @"hideToolbar", @"Hide Toolbar", @"Same key as a built-in."));
        writeFile([catalogDir stringByAppendingPathComponent:@"Empty.m"], @"");
        writeFile([catalogDir stringByAppendingPathComponent:@"CatalogFolder/Info.h"], @"#define DPCatalogFolderTitle @\"Catalog Folder\"\n");
        writeFile([catalogDir stringByAppendingPathComponent:@"CatalogFolder/CatalogFolder.m"],
                  @"#import \"StdPatch/StdPatch.h\"\n#import \"Info.h\"\n"
                  @"DP_PATCH(CatalogOption) { .key = @\"catalogFolderOption\", .title = @\"Catalog Folder Option\", .detail = @\"\", .section = @\"Toolbar\", .requires = @\"catalogFolder\" };\n"
                  @"DP_PATCH(CatalogFolder) { .key = @\"catalogFolder\", .title = DPCatalogFolderTitle, .detail = @\"A folder.\", .section = @\"Toolbar\" };\n");
        writeFile([gHome stringByAppendingPathComponent:@"evil.m"], tweakSource(@"Evil", @"evil", @"Evil", @""));
        NSDictionary *(^entry)(NSString *, NSArray *, NSArray *) = ^NSDictionary *(NSString *name, NSArray *files, NSArray *patches) {
            return @{ @"id" : name, @"files" : files, @"patches" : patches };
        };
        NSArray *one = @[ listing(@"x", @"X", @"", nil) ];
        writeCatalog(catalogDir, @[
            entry(@"CatalogSingle", @[ @"CatalogSingle.m" ], @[ listing(@"catalogSingle", @"Catalog Single", @"Downloaded from the catalog.", nil) ]),
            entry(@"CatalogFolder", @[ @"CatalogFolder/CatalogFolder.m", @"CatalogFolder/Info.h" ],
                  @[ listing(@"catalogFolderOption", @"Catalog Folder Option", @"", @"catalogFolder"), listing(@"catalogFolder", @"Catalog Folder", @"A folder.", nil) ]),
            entry(@"PrevOn", @[ @"PrevOn.m" ], @[ listing(@"prevOn", @"Prev On", @"Was on before.", nil) ]),
            entry(@"ExplicitOff", @[ @"ExplicitOff.m" ], @[ listing(@"explicitOff", @"Explicit Off", @"Was switched off.", nil) ]),
            entry(@"Collide", @[ @"Collide.m" ], @[ listing(@"hideToolbar", @"Hide Toolbar", @"Same key as a built-in.", nil) ]),
            entry(@"Missing", @[ @"Missing.m" ], @[ listing(@"missing", @"Missing", @"", nil) ]),
            entry(@"Empty", @[ @"Empty.m" ], @[ listing(@"empty", @"Empty", @"", nil) ]),
            entry(@"Evil", @[ @"../evil.m" ], one),
            entry(@"Abs", @[ @"/abs.m" ], one),
            entry(@"OtherDir", @[ @"Other/x.m" ], one),
            entry(@"Mismatch", @[ @"Other.m" ], one),
            entry(@"../Up", @[ @"../Up.m" ], one),
            entry(@"README", @[ @"README.m" ], one),
            entry(@".hidden", @[ @".hidden.m" ], one),
            entry(@"Hidden", @[ @"Hidden/.secret.m" ], one),
            entry(@"Text", @[ @"Text.txt" ], one),
            entry(@"NoPatches", @[ @"NoPatches.m" ], @[]),
            entry(@"CatalogSingle", @[ @"CatalogSingle.m" ], one),
        ]);
        NSArray<NSDictionary *> *catalog = DPLocalFetchCatalog(&catalogError);
        expectEqual(ids(catalog), (@[ @"CatalogSingle", @"CatalogFolder", @"PrevOn", @"ExplicitOff", @"Collide", @"Missing", @"Empty" ]),
                    @"only well-formed entries survive validation, once each");
        expectEqual(ids(DPLocalCachedCatalog()), ids(catalog), @"the validated catalog is cached");
        expectEqual(DPLocalPrimaryPatch(catalog[1])[@"key"], @"catalogFolder", @"the primary patch is the first one that requires nothing");

        [defaults setBool:YES forKey:@"prevOn"];
        [defaults setBool:NO forKey:@"explicitOff"];
        expectEqual(ids(DPLocalAvailableCatalog(catalog)), (@[ @"PrevOn", @"CatalogSingle", @"CatalogFolder", @"ExplicitOff", @"Missing", @"Empty" ]),
                    @"a key the dylib already has is hidden, and a tweak that was on comes first");

        NSString *output = captured(^{ expect(DPLocalBuildMain(@[ @"diapatch", @"local", @"available" ]), @"`local available` succeeds"); });
        expect([output containsString:@"CatalogSingle  Catalog Single\n    Downloaded from the catalog.\n"], @"`local available` lists the id, title and detail");
        expect(![output containsString:@"Collide"], @"`local available` hides a tweak the dylib already has");
        expect([output hasPrefix:@"PrevOn  Prev On\n    Was on before.\n"], @"`local available` lists the tweak that was on first");

        __block BOOL ok = NO;
        output = captured(^{ ok = DPLocalBuildMain(@[ @"diapatch", @"local", @"install", @"collide" ]); });
        expect(!ok && [output containsString:@"Hide Toolbar is already built into this DiaTweaks."], @"installing a tweak the dylib has is refused");
        output = captured(^{ ok = DPLocalBuildMain(@[ @"diapatch", @"local", @"install", @"catalogSingle", @"nothing" ]); });
        expect(!ok && [output containsString:@"No optional tweak matching “nothing”. Run 'diatweaks local available' to see the list."], @"an unknown name is refused");
        expect(!DPLocalItems().count, @"a refused install installs nothing, not even the names before the bad one");
        output = captured(^{ ok = DPLocalBuildMain(@[ @"diapatch", @"local", @"install" ]); });
        expect(!ok && [output containsString:@"usage: diapatch local install"], @"install needs a name");

        for (NSDictionary *bad in @[ entry(@"Evil", @[ @"../evil.m" ], one), entry(@"Abs", @[ @"/abs.m" ], one), entry(@"OtherDir", @[ @"Other/x.m" ], one) ]) {
            catalogError = nil;
            expect(!DPLocalInstallCatalogItem(bad, &catalogError) && catalogError.length, [@"an unsafe path is refused: " stringByAppendingString:bad[@"id"]]);
        }
        expect(!fileExistsUnder(gLocal, @"evil.m") && !folderListing(gLocal).count, @"an unsafe path writes nothing to the local folder");
        for (NSString *name in @[ @"Missing", @"Empty" ]) {
            NSDictionary *item = nil;
            for (NSDictionary *candidate in catalog) if ([candidate[@"id"] isEqual:name]) item = candidate;
            catalogError = nil;
            expect(!DPLocalInstallCatalogItem(item, &catalogError), [name stringByAppendingString:@" fails to download"]);
            expect([catalogError containsString:[name stringByAppendingString:@".m"]], [@"it names the file: " stringByAppendingString:catalogError ?: @""]);
        }
        expect(!folderListing(gLocal).count, @"a failed download leaves the local folder alone");
        expect(!folderListing(stagingDir).count, @"a failed download cleans up after itself");

        expect(![defaults objectForKey:@"catalogSingle"], @"a tweak that was never switched has no saved value yet");
        NSString *headerFolder = DPLocalHeaders(NULL);
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:headerFolder error:NULL])
            if ([name hasSuffix:@".pch"]) [NSFileManager.defaultManager removeItemAtPath:[headerFolder stringByAppendingPathComponent:name] error:NULL];
        builds = count(gClangLog);
        output = captured(^{ ok = DPLocalBuildMain(@[ @"diapatch", @"local", @"install", @"CATALOGSINGLE", @"Catalog Folder", @"prevon", @"explicitoff" ]); });
        expect(ok, [@"installing by key, title and id works: " stringByAppendingString:output]);
        expect([output containsString:@"Installed Catalog Single — relaunch Dia to load it.\n"] && [output containsString:@"Installed Catalog Folder — relaunch Dia to load it.\n"],
               @"it says what it installed");
        runs = clangRunsSince(builds);
        expect(runs.count == 5 && [runs[0] containsString:@"objective-c-header"], @"DPLocalInstallCatalogItems builds all four in one pass");
        expect([NSFileManager.defaultManager fileExistsAtPath:[gLocal stringByAppendingPathComponent:@"CatalogSingle.m"]], @"a single file lands as <id>.m");
        expect([NSFileManager.defaultManager fileExistsAtPath:[gLocal stringByAppendingPathComponent:@"CatalogFolder/Info.h"]]
                   && [NSFileManager.defaultManager fileExistsAtPath:[gLocal stringByAppendingPathComponent:@"CatalogFolder/CatalogFolder.m"]],
               @"a folder lands as <id>/ with every file");
        expect([NSFileManager.defaultManager fileExistsAtPath:[gLocal stringByAppendingPathComponent:@"README.md"]], @"the local folder gets its README");
        expectEqual(stateItem(@"CatalogSingle")[@"status"], @"ready", @"an installed tweak is built and waits for a relaunch");
        expectEqual(stateItem(@"CatalogFolder")[@"status"], @"ready", @"an installed folder tweak is built too");
        expectEqual(stateItem(@"CatalogSingle")[@"patches"][0][@"section"], @"Toolbar", @"the state keeps the tweak’s own section");
        expect([defaults boolForKey:@"catalogSingle"] && [defaults objectForKey:@"catalogFolder"] && [defaults boolForKey:@"catalogFolder"], @"a new tweak is on after the relaunch");
        expect([defaults boolForKey:@"prevOn"], @"a tweak that was on stays on");
        expect([defaults objectForKey:@"explicitOff"] && ![defaults boolForKey:@"explicitOff"], @"a tweak that was switched off stays off");
        expect(![defaults objectForKey:@"catalogFolderOption"], @"only the primary tweak is switched on");
        expect(!folderListing(stagingDir).count, @"a finished install cleans up after itself");

        NSArray<NSDictionary *> *items = DPLocalItems();
        expect(DPLocalIsCatalogItemInstalled(catalog[0], items) && DPLocalIsCatalogItemInstalled(catalog[1], items), @"installed tweaks are found in the local folder");
        expect(!DPLocalIsCatalogItemInstalled(@{ @"id" : @"Other", @"files" : @[ @"Other.m" ], @"patches" : @[ listing(@"nothingHere", @"None", @"", nil) ] }, items),
               @"a tweak that isn’t there isn’t installed");
        expect(DPLocalIsCatalogItemInstalled(@{ @"id" : @"Renamed", @"files" : @[ @"Renamed.m" ], @"patches" : @[ listing(@"catalogSingle", @"Catalog Single", @"", nil) ] }, items),
               @"a tweak is installed when its key is already loaded or ready under another name");
        output = captured(^{ DPLocalBuildMain(@[ @"diapatch", @"local", @"catalog" ]); });
        expect([output containsString:@"CatalogSingle  Catalog Single  (installed)\n"], @"`local catalog` marks what’s installed");

        DPLocalReset();
        DPLoadPatches();
        DPPatch *downloaded = DPPatchNamed(@"catalogSingle");
        expect(downloaded && DPIsLocalPatch(downloaded) && DPSavedOn(downloaded), @"a downloaded tweak loads and is on after a relaunch");
        expectEqual(downloaded->section, @"Toolbar", @"it keeps the section it had");
        expectEqual(DPPatchNamed(@"catalogFolder")->title, @"Catalog Folder", @"a downloaded folder tweak loads with its header");
        expect(DPPatchNamed(@"catalogFolderOption") && DPRequired(DPPatchNamed(@"catalogFolderOption")) == DPPatchNamed(@"catalogFolder"), @"its option still requires it");
        expectEqual(stateItem(@"CatalogSingle")[@"status"], @"loaded", @"it is loaded after the relaunch");

        writeFile([catalogDir stringByAppendingPathComponent:@"CatalogSingle.m"], tweakSource(@"CatalogSingle", @"catalogSingle", @"Catalog Single", @"Updated upstream."));
        [NSFileManager.defaultManager createDirectoryAtPath:[gLocal stringByAppendingPathComponent:@"CatalogSingle"] withIntermediateDirectories:YES attributes:nil error:NULL];
        writeFile([gLocal stringByAppendingPathComponent:@"CatalogSingle/Old.m"], @"// left over\n");
        expect(DPLocalInstallCatalogItem(catalog[0], &catalogError), @"installing again replaces the tweak");
        expect([[NSString stringWithContentsOfFile:[gLocal stringByAppendingPathComponent:@"CatalogSingle.m"] encoding:NSUTF8StringEncoding error:NULL] containsString:@"Updated upstream."],
               @"the new file replaces the old one");
        expect(![NSFileManager.defaultManager fileExistsAtPath:[gLocal stringByAppendingPathComponent:@"CatalogSingle"]], @"a folder of the same name is replaced too");

        setenv("DIAPATCH_CATALOG_URL", [@"file://" stringByAppendingString:catalogDir].fileSystemRepresentation, 1);
        expectEqual(@(ids(DPLocalFetchCatalog(&catalogError)).count), @7, @"a file:// URL works");
        setenv("DIAPATCH_CATALOG_URL", [[@"file://" stringByAppendingString:catalogDir] stringByAppendingString:@"/"].fileSystemRepresentation, 1);
        expectEqual(@(ids(DPLocalFetchCatalog(&catalogError)).count), @7, @"a file:// URL with a slash works");
        setenv("DIAPATCH_CATALOG_URL", "http://127.0.0.1:1/", 1);
        expect(DPLocalFetchCatalog(&catalogError) == nil, @"an unreachable catalog is nil");
        expectEqual(catalogError, @"Couldn’t reach GitHub to load optional tweaks.", @"it says GitHub couldn’t be reached");
        expectEqual(@(ids(DPLocalCachedCatalog()).count), @7, @"a failed fetch keeps the cached catalog");
        output = captured(^{ ok = DPLocalBuildMain(@[ @"diapatch", @"local", @"available" ]); });
        expect(ok && [output containsString:@"CatalogSingle  Catalog Single"], @"`local available` falls back to the cache when offline");
        output = captured(^{ ok = DPLocalBuildMain(@[ @"diapatch", @"local", @"install", @"prevOn" ]); });
        expect(!ok && [output containsString:@"Couldn’t reach GitHub"], @"install needs the network");
        setenv("DIAPATCH_CATALOG_URL", catalogDir.fileSystemRepresentation, 1);
        writeFile([catalogDir stringByAppendingPathComponent:@"index.json"], @"{ not json");
        expect(DPLocalFetchCatalog(&catalogError) == nil && [catalogError containsString:@"isn’t readable"], @"an unreadable index is an error");
        expectEqual(@(ids(DPLocalCachedCatalog()).count), @7, @"an unreadable index keeps the cached catalog");
        [NSFileManager.defaultManager removeItemAtPath:[catalogDir stringByAppendingPathComponent:@"index.json"] error:NULL];
        expectEqual(DPLocalFetchCatalog(&catalogError), @[], @"a catalog that went missing is empty");
        expectEqual(DPLocalCachedCatalog(), @[], @"and the cache follows it");

        gServerBody = [NSJSONSerialization dataWithJSONObject:@{ @"tweaks" : @[ catalog[0] ] } options:0 error:NULL];
        int port = startCatalogServer();
        expect(port > 0, @"the loopback catalog server starts");
        setenv("DIAPATCH_CATALOG_URL", [NSString stringWithFormat:@"http://127.0.0.1:%d", port].UTF8String, 1);
        NSArray<NSDictionary *> *served = DPLocalFetchCatalog(&catalogError);
        expectEqual(ids(served), @[ @"CatalogSingle" ], [@"an HTTP catalog loads: " stringByAppendingString:catalogError ?: @""]);
        NSString *catalogPath = [DPLocalCacheFolder() stringByAppendingPathComponent:@"catalog.json"], *cachedCatalog = identity(catalogPath);
        NSDictionary *saved = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:catalogPath] ?: NSData.data options:0 error:NULL];
        expectEqual(saved[@"etag"], @"\"v1\"", @"the catalog's ETag is cached with it");
        expectEqual(DPLocalFetchCatalog(&catalogError), served, @"a 304 returns the cached catalog");
        expect(gServed == 2 && gServedConditional == 1, @"the second fetch asks with If-None-Match");
        expectEqual(identity(catalogPath), cachedCatalog, @"a 304 leaves catalog.json alone");
        setenv("DIAPATCH_CATALOG_URL", catalogDir.fileSystemRepresentation, 1);

        [NSFileManager.defaultManager removeItemAtPath:gLocal error:NULL];
        writeFile([gLocal stringByAppendingPathComponent:@"pr-900.patch"],
                  @"diff --git a/tweaks/index.json b/tweaks/index.json\nindex 1111111..2222222 100644\n--- a/tweaks/index.json\n+++ b/tweaks/index.json\n@@ -1,1 +1,1 @@\n-old\n+new\n"
                  @"diff --git a/tweaks/PRTweak/PRTweak.m b/tweaks/PRTweak/PRTweak.m\nnew file mode 100644\nindex 0000000..3333333\n--- /dev/null\n+++ b/tweaks/PRTweak/PRTweak.m\n@@ -0,0 +1,2 @@\n"
                  @"+#import \"StdPatch/StdPatch.h\"\n+DP_PATCH(PRTweak) { .key = @\"prTweak\", .title = @\"PR Tweak\", .detail = @\"\", .section = @\"Local\" };\n");
        DPLocalReset();
        DPLoadPatches();
        expectEqual(stateItem(@"pr-900")[@"status"], @"loaded", @"a PR that adds a tweak under tweaks/ loads");
        expect(DPPatchNamed(@"prTweak") != NULL, @"its tweak is there");

        NSString *linked = [gHome stringByAppendingPathComponent:@"linked"];
        writeFile([linked stringByAppendingPathComponent:@"MetalOnly.m"],
                  @"#import \"StdPatch/StdPatch.h\"\n#import <Metal/Metal.h>\nstatic void DPUse(void) { (void)MTLCreateSystemDefaultDevice(); }\n"
                  @"DP_PATCH(MetalOnly) { .key = @\"metalOnly\", .title = @\"Metal Only\", .detail = @\"\", .section = @\"Local\", .install = DPUse };\n");
        writeFile([linked stringByAppendingPathComponent:@"CarbonToo.m"],
                  @"#import \"StdPatch/StdPatch.h\"\n#import <Carbon/Carbon.h>\nstatic void DPUse(void) { CFRelease(TISCopyCurrentKeyboardInputSource()); }\n"
                  @"DP_PATCH(CarbonToo) { .key = @\"carbonToo\", .title = @\"Carbon Too\", .detail = @\"\", .section = @\"Local\", .install = DPUse };\n");
        for (NSString *name in @[ @"MetalOnly.m", @"CarbonToo.m" ]) DPLocalAdd([linked stringByAppendingPathComponent:name], &catalogError);
        DPLocalReset();
        expect(DPLocalBuildAll(nil, &report), [@"a tweak that uses Metal or Carbon builds: " stringByAppendingString:report ?: @""]);
        NSString *metalLibs = DPLocalRun(@[ @"/usr/bin/otool", @"-L", stateItem(@"MetalOnly")[@"dylib"] ?: @"/nonexistent" ]);
        NSString *carbonLibs = DPLocalRun(@[ @"/usr/bin/otool", @"-L", stateItem(@"CarbonToo")[@"dylib"] ?: @"/nonexistent" ]);
        expect([metalLibs containsString:@"Metal.framework"] && ![metalLibs containsString:@"Carbon.framework"], @"a tweak links Metal when it uses it, and nothing it doesn’t");
        expect([carbonLibs containsString:@"Carbon.framework"] && ![carbonLibs containsString:@"Metal.framework"], @"a tweak links Carbon when it uses it, and nothing it doesn’t");
        // An option that names no section of its own stays sectionless through the build, the index and the load, so Settings groups it under Options.
        [NSFileManager.defaultManager removeItemAtPath:gLocal error:NULL];
        DPLocalWriteState(@[]);
        NSString *windowSource = @"#import \"StdPatch/StdPatch.h\"\n"
                                 @"DP_PATCH(CatalogWindowOption) { .key = @\"catalogWindowOption\", .title = @\"Catalog Window Option\", .detail = @\"\", .requires = @\"catalogWindow\" };\n"
                                 @"DP_PATCH(CatalogWindow) { .key = @\"catalogWindow\", .title = @\"Catalog Window\", .detail = @\"\", .section = @\"Window\" };\n";
        writeFile([gLocal stringByAppendingPathComponent:@"CatalogWindow/CatalogWindow.m"], windowSource);
        writeFile([catalogDir stringByAppendingPathComponent:@"CatalogWindow/CatalogWindow.m"], windowSource);
        DPLocalReset();
        expect(DPLocalBuildAll(nil, &report), [@"a tweak with a sectionless option builds: " stringByAppendingString:report ?: @""]);
        NSArray<NSDictionary *> *windowRecords = stateItem(@"CatalogWindow")[@"patches"];
        NSDictionary *optionRecord = nil, *parentRecord = nil;
        for (NSDictionary *record in windowRecords) {
            if ([record[@"key"] isEqual:@"catalogWindowOption"]) optionRecord = record;
            if ([record[@"key"] isEqual:@"catalogWindow"]) parentRecord = record;
        }
        expectEqual(parentRecord[@"section"], @"Window", @"a tweak keeps the section it names");
        expectEqual(optionRecord[@"section"], NSNull.null, @"an option without a section is recorded without one, not as Local");
        writeCatalog(catalogDir, @[ @{ @"id" : @"CatalogWindow", @"files" : @[ @"CatalogWindow/CatalogWindow.m" ], @"patches" : windowRecords } ]);
        [NSFileManager.defaultManager removeItemAtPath:gLocal error:NULL];
        DPLocalWriteState(@[]);
        DPLocalReset();
        NSArray<NSDictionary *> *windowCatalog = DPLocalFetchCatalog(&catalogError);
        expectEqual(ids(windowCatalog), @[ @"CatalogWindow" ], @"an index with a null section is still a valid catalog");
        expectEqual(DPLocalPrimaryPatch(windowCatalog.firstObject)[@"key"], @"catalogWindow", @"the primary patch is the one with no requirement");
        expect(windowCatalog.count && DPLocalInstallCatalogItem(windowCatalog[0], &catalogError), [@"it installs from the index: " stringByAppendingString:catalogError ?: @""]);
        DPLocalReset();
        DPLoadPatches();
        DPPatch *windowParent = DPPatchNamed(@"catalogWindow"), *windowOption = DPPatchNamed(@"catalogWindowOption");
        expectEqual(windowParent->section, @"Window", @"the installed tweak keeps its section after the load");
        expect(windowOption != NULL && windowOption->section == nil, @"the installed option still has no section after the load");
        expect(windowOption != NULL && DPRequired(windowOption) == windowParent, @"and it still requires its tweak");
        expectEqual(stateItem(@"CatalogWindow")[@"patches"], windowRecords, @"the state written by the load matches the one the index came from");

        output = captured(^{
            chmod(gLocal.fileSystemRepresentation, 0555);
            ok = DPLocalBuildMain(@[ @"diapatch", @"local", @"doctor" ]);
            chmod(gLocal.fileSystemRepresentation, 0755);
        });
        expect(!ok && [output containsString:[gLocal stringByAppendingString:@" (not writable"]], @"`local doctor` flags a local folder it can't write");
        expect([output containsString:[gHome stringByAppendingString:@" (writable)"]], @"`local doctor` checks the support folder too");

        DPLocalWriteState(@[]);
        chmod(gHome.fileSystemRepresentation, 0555);
        report = nil;
        BOOL built = DPLocalBuildAll(nil, &report);
        chmod(gHome.fileSystemRepresentation, 0755);
        expect(built && [report containsString:@"Couldn’t save the build results"], @"a build that can't save local-state.json says so");

        chmod(gLocal.fileSystemRepresentation, 0);
        report = nil;
        built = DPLocalBuildAll(nil, &report);
        output = captured(^{ ok = DPLocalBuildMain(@[ @"diapatch", @"local" ]); });
        NSUInteger listedWhileUnreadable = DPLocalItems().count;
        chmod(gLocal.fileSystemRepresentation, 0755);
        expect(!built && [report hasPrefix:[NSString stringWithFormat:@"Couldn’t read %@", gLocal]] && [report containsString:@"chown -R"],
               @"building an unreadable local folder fails and says how to fix it");
        expect(!ok && [output hasPrefix:[NSString stringWithFormat:@"Couldn’t read %@", gLocal]], @"`local` reports an unreadable folder instead of an empty list");
        expect(!listedWhileUnreadable, @"Settings lists nothing it can't read");
        expect(DPLocalBuildAll(nil, &report), @"the folder builds again once it's readable");

        NSString *otherDomain = [DPTestDomain() stringByAppendingString:@".other"];
        setenv("DIATWEAKS_DOMAIN", otherDomain.UTF8String, 1);
        [DPSettingsDefaults() setBool:YES forKey:@"domainProbe"];
        unsetenv("DIATWEAKS_DOMAIN");
        NSUserDefaults *other = [[NSUserDefaults alloc] initWithSuiteName:otherDomain];
        expect([other boolForKey:@"domainProbe"] && ![defaults objectForKey:@"domainProbe"], @"DIATWEAKS_DOMAIN keeps the saved switches out of the real domain");
        [other removePersistentDomainForName:otherDomain];
        [defaults removePersistentDomainForName:DPTestDomain()];
        unsetenv("DIAPATCH_CATALOG_URL");

        printf(failures ? "%d local tweak checks failed\n" : "local tweaks: all checks passed\n", failures);
        [NSFileManager.defaultManager removeItemAtPath:gHome error:NULL];
        return failures ? 1 : 0;
    }
}

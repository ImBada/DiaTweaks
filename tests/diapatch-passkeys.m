#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

void DPForgetApp(NSString *app) {}
BOOL DPRunsThisDiapatch(audit_token_t token) { return NO; }
pid_t DPParentOf(pid_t pid) { return 0; }

#import "Disclaim.m"
#import "PasswordsLaunch.m"
#import "PasswordsHandoff.m"
#define send passkeysSend
#import "Passkeys.m"
#undef send

static NSString *makeTempDir(void) {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:@"diatweaks-pk-XXXXXX"];
    char *tmpl = strdup(base.fileSystemRepresentation);
    char *created = mkdtemp(tmpl);
    NSCAssert(created != NULL, @"mkdtemp failed");
    NSString *dir = [NSFileManager.defaultManager stringWithFileSystemRepresentation:created length:strlen(created)];
    free(tmpl);
    return dir;
}

static void writeBundle(NSString *app, NSString *contents) {
    NSString *exe = [app stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    [NSFileManager.defaultManager createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert([contents writeToFile:exe atomically:YES encoding:NSUTF8StringEncoding error:nil], @"writeBundle failed");
}

static int countOpenFDs(void) {
    int count = 0;
    for (int fd = 0; fd < 256; fd++)
        if (fcntl(fd, F_GETFD) >= 0) count++;
    return count;
}

static void assertNoTempBundles(NSString *copyFolder) {
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:copyFolder error:nil];
    for (NSString *name in items)
        NSCAssert(![name hasPrefix:@"Dia.app."], @"leaked temp bundle %@ in %@", name, copyFolder);
}

static const char *gSelfExe;

static void testApplicationsCopy(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = makeTempDir();
    NSString *pristine = [root stringByAppendingPathComponent:@"pristine/Dia.app"];
    NSString *copyFolder = [root stringByAppendingPathComponent:@"copy"];
    NSString *clone = [copyFolder stringByAppendingPathComponent:@"Dia.app"];
    NSString *cloneExe = [clone stringByAppendingPathComponent:@"Contents/MacOS/Dia"];

    NSCAssert(applicationsCopyIn(copyFolder, pristine) == nil, @"missing pristine must return nil");
    NSCAssert(![fm fileExistsAtPath:clone], @"clone must not exist when pristine is missing");

    writeBundle(pristine, @"v1-binary");
    const char *q = "0081;00000000;Test;";
    setxattr(pristine.fileSystemRepresentation, "com.apple.quarantine", q, strlen(q), 0, 0);
    // Pre-existing stale temp dir from PID reuse must not fail clonefile with EEXIST.
    NSString *stale = [clone stringByAppendingFormat:@".%d", getpid()];
    writeBundle(stale, @"stale");

    NSString *got = applicationsCopyIn(copyFolder, pristine);
    NSCAssert([got isEqualToString:clone], @"initial clone should succeed, got %@", got);
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v1-binary"], @"clone has v1");
    NSCAssert(getxattr(clone.fileSystemRepresentation, "com.apple.quarantine", NULL, 0, 0, 0) < 0, @"quarantine stripped");
    assertNoTempBundles(copyFolder);

    [fm removeItemAtPath:pristine error:nil];
    NSCAssert(applicationsCopyIn(copyFolder, pristine) == nil, @"missing pristine returns nil");
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v1-binary"], @"existing clone preserved");
    assertNoTempBundles(copyFolder);

    writeBundle(pristine, @"v2-updated-binary");
    got = applicationsCopyIn(copyFolder, pristine);
    NSCAssert([got isEqualToString:clone], @"updated clone should succeed");
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v2-updated-binary"], @"clone has v2");
    assertNoTempBundles(copyFolder);

    writeBundle(pristine, @"v3-concurrent-test-binary");
    pid_t children[6];
    const char *argv[] = { gSelfExe, "--child-copy", copyFolder.fileSystemRepresentation, pristine.fileSystemRepresentation, NULL };
    for (int i = 0; i < 6; i++) {
        NSCAssert(posix_spawn(&children[i], gSelfExe, NULL, NULL, (char *const *)argv, environ) == 0, @"posix_spawn failed");
    }
    for (int i = 0; i < 6; i++) {
        int status = 0;
        NSCAssert(waitpid(children[i], &status, 0) == children[i] && WIFEXITED(status) && WEXITSTATUS(status) == 0,
                  @"concurrent child %d failed (status %d)", i, status);
    }
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v3-concurrent-test-binary"], @"clone has v3");
    assertNoTempBundles(copyFolder);

    NSString *roFolder = [root stringByAppendingPathComponent:@"readonly"];
    [fm createDirectoryAtPath:roFolder withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(roFolder.fileSystemRepresentation, 0555);
    NSCAssert(applicationsCopyIn(roFolder, pristine) == nil, @"readonly copyFolder must return nil");
    chmod(roFolder.fileSystemRepresentation, 0755);
    assertNoTempBundles(roFolder);

    [fm removeItemAtPath:root error:nil];
}

static NSDictionary *decodeFramed(uint32_t header, const void *body, size_t bodyLen) {
    NSMutableData *buf = [NSMutableData dataWithCapacity:4 + bodyLen];
    [buf appendBytes:&header length:4];
    if (bodyLen) [buf appendBytes:body length:bodyLen];
    FILE *f = fmemopen((void *)buf.bytes, buf.length, "r");
    NSCAssert(f != NULL, @"fmemopen failed");
    NSDictionary *msg = readMessageFrom(f);
    fclose(f);
    return msg;
}

static void testPasskeyMessageValidation(void) {
    NSCAssert(decodeFramed(0, "", 0) == nil, @"zero-length header rejected");
    NSCAssert(decodeFramed(0xffffffffU, "{}", 2) == nil, @"4 GiB header rejected");
    NSCAssert(decodeFramed(kMaxMessageLength + 1, "{}", 2) == nil, @"over-1-MiB header rejected");

    NSCAssert(decodeFramed(100, "{}", 2) == nil, @"truncated body rejected");
    NSCAssert(decodeFramed(3, "{no", 3) == nil, @"invalid JSON rejected");
    NSCAssert(decodeFramed(5, "[1,2]", 5) == nil, @"array JSON rejected");
    NSCAssert(decodeFramed(4, "null", 4) == nil, @"null JSON rejected");
    NSCAssert(decodeFramed(4, "\"hi\"", 4) == nil, @"string JSON rejected");

    const char *ok = "{\"kind\":\"get\",\"origin\":\"https://example.com\",\"options\":{}}";
    NSDictionary *parsed = decodeFramed((uint32_t)strlen(ok), ok, strlen(ok));
    NSCAssert(validRequest(parsed), @"valid framed request accepted");

    NSMutableData *maxMsg = [NSMutableData dataWithLength:kMaxMessageLength];
    memset(maxMsg.mutableBytes, ' ', kMaxMessageLength);
    memcpy(maxMsg.mutableBytes, "{\"a\":1}", 7);
    NSDictionary *maxParsed = decodeFramed(kMaxMessageLength, maxMsg.bytes, maxMsg.length);
    NSCAssert([maxParsed[@"a"] isEqual:@1], @"exact 1 MiB message accepted");

    NSCAssert(!validRequest(nil), @"nil request rejected");
    NSCAssert(!validRequest(@{}), @"empty dict rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"get", @"origin" : @"https://example.com" }), @"missing options rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"get", @"options" : @{} }), @"missing origin rejected");
    NSCAssert(!validRequest(@{ @"origin" : @"https://example.com", @"options" : @{} }), @"missing kind rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"bogus", @"origin" : @"https://example.com", @"options" : @{} }), @"unknown kind rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"create", @"origin" : @"", @"options" : @{} }), @"empty origin rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"create", @"origin" : @"https://example.com", @"options" : @[] }), @"non-dict options rejected");
    NSCAssert(validRequest(@{ @"kind" : @"create", @"origin" : @"https://example.com", @"options" : @{ @"challenge" : @"abc" } }), @"valid create accepted");
    NSCAssert(validRequest(@{ @"kind" : @"get", @"origin" : @"https://api-4b6bfd4c.duosecurity.com", @"path" : @"/frame/v4/auth/prompt", @"options" : @{} }), @"valid get with path accepted");

    NSDictionary *bad = runInHelper(0, nil, nil, nil, nil);
    NSCAssert([bad[@"error"][@"name"] isEqual:@"NotAllowedError"], @"runInHelper guards nil without crashing");
}

static NSData *helperMessage(NSUInteger length) {
    NSMutableData *json = [NSMutableData dataWithLength:length];
    memset(json.mutableBytes, 'a', length);
    memcpy(json.mutableBytes, "{\"p\":\"", 6);
    memcpy((char *)json.mutableBytes + length - 2, "\"}", 2);
    return json;
}

static NSArray *readHelperStream(NSData *stream, NSUInteger reads) {
    gFromHelper = fmemopen((void *)stream.bytes, stream.length, "r");
    NSCAssert(gFromHelper != NULL, @"fmemopen failed");
    NSMutableArray *replies = [NSMutableArray array];
    for (NSUInteger i = 0; i < reads; i++) [replies addObject:readFromHelper() ?: NSNull.null];
    fclose(gFromHelper);
    gFromHelper = NULL;
    return replies;
}

static void testHelperMessageFraming(void) {
    NSMutableData *stream = [NSMutableData data];
    for (NSNumber *length in @[ @40000, @16384, @16385, @8 ]) {
        [stream appendData:helperMessage(length.unsignedIntegerValue)];
        [stream appendBytes:"" length:1];
    }
    [stream appendBytes:"{\"id\":3" length:7];
    NSArray *replies = readHelperStream(stream, 6);
    NSArray *lengths = @[ @(40000 - 8), @(16384 - 8), @(16385 - 8), @0 ];
    for (NSUInteger i = 0; i < lengths.count; i++)
        NSCAssert([replies[i] isKindOfClass:NSDictionary.class] && [replies[i][@"p"] length] == [lengths[i] unsignedIntegerValue],
                  @"NUL-framed message %lu survives 16 KB chunk boundaries", (unsigned long)i);
    NSCAssert(replies[4] == NSNull.null && replies[5] == NSNull.null, @"EOF mid-message yields nil, then nil again");

    NSMutableData *atCap = [helperMessage(kMaxHelperMessageLength) mutableCopy];
    [atCap appendBytes:"" length:1];
    NSCAssert([readHelperStream(atCap, 1).firstObject isKindOfClass:NSDictionary.class], @"a message of exactly the cap is read");
    NSMutableData *overCap = [helperMessage(kMaxHelperMessageLength + 1) mutableCopy];
    [overCap appendBytes:"" length:1];
    NSCAssert(readHelperStream(overCap, 1).firstObject == NSNull.null, @"a message one byte over the cap is rejected");
}

static void testSpawnEnvironmentOverrides(void) {
    setenv("CFFIXED_USER_HOME", "/stale", 1);
    setenv("DIAPATCH_PASSWORDS_HANDOFF", "/stale.sock", 1);
    setenv("DIAPATCH_PASSWORDS_HANDOFF_EXTRA", "kept", 1);
    int out[2];
    NSCAssert(pipe(out) == 0, @"pipe failed");
    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_adddup2(&files, out[1], 1);
    const char *argv[] = { "/usr/bin/env", NULL };
    pid_t pid = DPSpawnDisclaimed(argv, @[ @"CFFIXED_USER_HOME=/fresh", @"DIAPATCH_PASSWORDS_HANDOFF=/fresh.sock" ], &files);
    posix_spawn_file_actions_destroy(&files);
    close(out[1]);
    NSCAssert(pid > 0, @"DPSpawnDisclaimed starts the child");
    NSData *printed = [[NSFileHandle alloc] initWithFileDescriptor:out[0] closeOnDealloc:YES].readDataToEndOfFile;
    waitpid(pid, NULL, 0);
    NSArray *lines = [[[NSString alloc] initWithData:printed encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
    NSArray *fixed = [lines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'CFFIXED_USER_HOME='"]];
    NSArray *handoff = [lines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'DIAPATCH_PASSWORDS_HANDOFF='"]];
    NSCAssert([fixed isEqual:@[ @"CFFIXED_USER_HOME=/fresh" ]], @"override replaces the inherited value: %@", fixed);
    NSCAssert([handoff isEqual:@[ @"DIAPATCH_PASSWORDS_HANDOFF=/fresh.sock" ]], @"handoff override replaces the inherited value: %@", handoff);
    NSCAssert([lines containsObject:@"DIAPATCH_PASSWORDS_HANDOFF_EXTRA=kept"], @"a longer name sharing the prefix is kept");
    unsetenv("CFFIXED_USER_HOME");
    unsetenv("DIAPATCH_PASSWORDS_HANDOFF");
    unsetenv("DIAPATCH_PASSWORDS_HANDOFF_EXTRA");
}

static NSDictionary *runHostChild(NSString *home, NSData *stdinBytes, BOOL closeStdinEarly, int *exitCode, BOOL *leakedFDs) {
    int inPipe[2], outPipe[2];
    NSCAssert(pipe(inPipe) == 0 && pipe(outPipe) == 0, @"pipe failed");
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, inPipe[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, inPipe[0]);
    posix_spawn_file_actions_addclose(&actions, inPipe[1]);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);
    const char *argv[] = { gSelfExe, "--child-host", home.fileSystemRepresentation, NULL };
    pid_t pid = 0;
    NSCAssert(posix_spawn(&pid, gSelfExe, &actions, NULL, (char *const *)argv, environ) == 0, @"posix_spawn host failed");
    posix_spawn_file_actions_destroy(&actions);
    close(inPipe[0]);
    close(outPipe[1]);
    if (stdinBytes.length) (void)write(inPipe[1], stdinBytes.bytes, stdinBytes.length);
    if (closeStdinEarly) close(inPipe[1]), inPipe[1] = -1;

    NSMutableData *out = [NSMutableData data];
    char buf[4096];
    for (ssize_t n; (n = read(outPipe[0], buf, sizeof buf)) > 0;) [out appendBytes:buf length:(NSUInteger)n];
    close(outPipe[0]);
    if (inPipe[1] >= 0) close(inPipe[1]);

    int status = 0;
    NSCAssert(waitpid(pid, &status, 0) == pid && WIFEXITED(status), @"child exited abnormally (status=%d)", status);
    int code = WEXITSTATUS(status);
    if (leakedFDs) *leakedFDs = (code == 99);
    if (exitCode) *exitCode = code;
    if (out.length < 4) return nil;
    uint32_t len = 0;
    memcpy(&len, out.bytes, 4);
    if (4 + len > out.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:[out subdataWithRange:NSMakeRange(4, len)] options:0 error:nil];
}

static NSData *frameJSON(NSDictionary *dict) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    uint32_t len = (uint32_t)body.length;
    NSMutableData *out = [NSMutableData dataWithCapacity:4 + len];
    [out appendBytes:&len length:4];
    [out appendData:body];
    return out;
}

static void testPasskeyHostErrorPathsAndFDCleanup(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = makeTempDir();
    NSData *validReq = frameJSON(@{ @"kind" : @"get", @"origin" : @"https://example.com", @"options" : @{} });

    uint32_t huge = 0xffffffffU;
    int code = 0;
    BOOL leaked = YES;
    NSDictionary *reply = runHostChild(root, [NSData dataWithBytes:&huge length:4], YES, &code, &leaked);
    NSCAssert(code == 1 && !leaked && reply == nil, @"oversized header must fail cleanly (code=%d leaked=%d)", code, leaked);

    reply = runHostChild(root, frameJSON(@{ @"kind" : @"get", @"origin" : @"https://example.com" }), YES, &code, &leaked);
    NSCAssert(code == 1 && !leaked && reply == nil, @"missing options must fail cleanly (code=%d leaked=%d)", code, leaked);

    NSString *fileHome = [root stringByAppendingPathComponent:@"not-a-dir"];
    [@"x" writeToFile:fileHome atomically:YES encoding:NSUTF8StringEncoding error:nil];
    reply = runHostChild(fileHome, validReq, NO, &code, &leaked);
    NSCAssert(code == 1 && !leaked && [reply[@"error"][@"name"] isEqual:@"NotAllowedError"],
              @"open() failure must return error JSON without fd leak (code=%d leaked=%d reply=%@)", code, leaked, reply);

    NSString *emptyHome = [root stringByAppendingPathComponent:@"empty-home"];
    [fm createDirectoryAtPath:emptyHome withIntermediateDirectories:YES attributes:nil error:nil];
    reply = runHostChild(emptyHome, validReq, NO, &code, &leaked);
    NSCAssert(code == 1 && !leaked && [reply[@"error"][@"name"] isEqual:@"NotAllowedError"],
              @"launchHelper failure must close all pipes and lock (code=%d leaked=%d reply=%@)", code, leaked, reply);

    int held = openPasskeyLock(emptyHome);
    NSCAssert(held >= 0 && flock(held, LOCK_EX | LOCK_NB) == 0, @"parent lock failed");
    reply = runHostChild(emptyHome, validReq, YES, &code, &leaked);
    close(held);
    NSCAssert(code == 0 && !leaked && [reply[@"error"][@"name"] isEqual:@"NotAllowedError"],
              @"cancelled while waiting on lock must exit cleanly without fd leak (code=%d leaked=%d reply=%@)", code, leaked, reply);

    [fm removeItemAtPath:root error:nil];
}

static void writeInfoPlist(NSString *app, NSString *shortVersion, NSString *build) {
    NSString *path = [app stringByAppendingPathComponent:@"Contents/Info.plist"];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *info = @{
        @"CFBundleIdentifier" : @"company.thebrowser.dia",
        @"CFBundleExecutable" : @"Dia",
        @"CFBundlePackageType" : @"APPL",
        @"CFBundleShortVersionString" : shortVersion,
        @"CFBundleVersion" : build,
    };
    NSCAssert([info writeToFile:path atomically:YES], @"writeInfoPlist failed");
}

static NSData *makeMachOWithUUID(uint8_t tag) {
    struct mach_header_64 hdr = {
        .magic = MH_MAGIC_64,
        .cputype = CPU_TYPE_ARM64,
        .filetype = MH_EXECUTE,
        .ncmds = 1,
        .sizeofcmds = sizeof(struct uuid_command),
    };
    struct uuid_command uuid = { .cmd = LC_UUID, .cmdsize = sizeof(struct uuid_command) };
    memset(uuid.uuid, tag, sizeof uuid.uuid);
    NSMutableData *data = [NSMutableData dataWithLength:sizeof hdr + sizeof uuid];
    memcpy(data.mutableBytes, &hdr, sizeof hdr);
    memcpy((uint8_t *)data.mutableBytes + sizeof hdr, &uuid, sizeof uuid);
    return data;
}

static void setExactMtime(NSString *path, time_t sec, long nsec) {
    struct timespec ts[2] = { { sec, nsec }, { sec, nsec } };
    NSCAssert(utimensat(AT_FDCWD, path.fileSystemRepresentation, ts, 0) == 0, @"utimensat failed");
}

static int runTool(NSArray<NSString *> *argv) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    task.standardInput = task.standardOutput = task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:NULL]) return -1;
    [task waitUntilExit];
    return task.terminationStatus;
}

static void testHeadlessApp(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = makeTempDir();
    NSString *app = [root stringByAppendingPathComponent:@"copy/Dia.app"];
    NSString *exe = [app stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    NSString *frameworks = [app stringByAppendingPathComponent:@"Contents/Frameworks"];
    NSString *resources = [app stringByAppendingPathComponent:@"Contents/Resources"];
    writeBundle(app, @"genuine-binary");
    writeInfoPlist(app, @"1.59.0", @"91402");
    [fm createDirectoryAtPath:frameworks withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:resources withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *original = [NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSCAssert(original[@"LSUIElement"] == nil, @"fixture must not already be a UIElement");

    NSString *wrapper = headlessApp(app);
    NSCAssert([wrapper isEqualToString:[root stringByAppendingPathComponent:@"copy/Headless.app"]], @"wrapper sits beside the app, got %@", wrapper);
    NSDictionary *headless = [NSDictionary dictionaryWithContentsOfFile:[wrapper stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSCAssert([headless[@"LSUIElement"] boolValue], @"wrapper Info.plist sets LSUIElement");
    NSCAssert([headless[@"CFBundleIdentifier"] isEqual:@"company.thebrowser.dia"], @"wrapper keeps the bundle ID 1Password matches");
    NSCAssert([headless[@"CFBundleVersion"] isEqual:@"91402"], @"wrapper keeps the build Dia reads");

    NSString *link = [wrapper stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    NSString *target = [fm destinationOfSymbolicLinkAtPath:link error:nil];
    NSCAssert([target hasPrefix:@"../"], @"executable link is relative so the folder can move, got %@", target);
    NSCAssert([[link stringByResolvingSymlinksInPath] isEqual:[exe stringByResolvingSymlinksInPath]], @"executable link resolves to the genuine binary");
    NSCAssert([[NSString stringWithContentsOfFile:link encoding:NSUTF8StringEncoding error:nil] isEqual:@"genuine-binary"], @"executable link reads through to the genuine binary");
    NSCAssert([[frameworks stringByResolvingSymlinksInPath] isEqual:[[wrapper stringByAppendingPathComponent:@"Contents/Frameworks"] stringByResolvingSymlinksInPath]],
              @"Frameworks link resolves to the app's frameworks");
    NSCAssert([[resources stringByResolvingSymlinksInPath] isEqual:[[wrapper stringByAppendingPathComponent:@"Contents/Resources"] stringByResolvingSymlinksInPath]],
              @"Resources link resolves to the app's resources");

    NSCAssert([headlessApp(app) isEqualToString:wrapper], @"second call returns the same wrapper");
    writeInfoPlist(app, @"1.60.0", @"92000");
    NSCAssert([headlessApp(app) isEqualToString:wrapper], @"wrapper survives an app update");
    headless = [NSDictionary dictionaryWithContentsOfFile:[wrapper stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSCAssert([headless[@"CFBundleVersion"] isEqual:@"92000"] && [headless[@"LSUIElement"] boolValue], @"wrapper follows the app's new Info.plist");

    NSString *bare = [root stringByAppendingPathComponent:@"bare/Dia.app"];
    writeBundle(bare, @"bare-binary");
    NSCAssert(headlessApp(bare) == nil, @"missing Info.plist returns nil");
    NSCAssert(![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"bare/Headless.app"]], @"no wrapper is left behind");

    NSString *readonly = [root stringByAppendingPathComponent:@"readonly"];
    [fm createDirectoryAtPath:readonly withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(readonly.fileSystemRepresentation, 0555);
    NSCAssert(headlessApp([readonly stringByAppendingPathComponent:@"Dia.app"]) == nil, @"unwritable folder returns nil");
    chmod(readonly.fileSystemRepresentation, 0755);

    NSString *raceWrapper = [root stringByAppendingPathComponent:@"copy/Headless.app"];
    NSString *raceLink = [raceWrapper stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    enum { kWorkers = 8, kRounds = 10 };
    const char *raceArgv[] = { gSelfExe, "--child-headless", app.fileSystemRepresentation, NULL };
    for (int round = 0; round < kRounds; round++) {
        if (round % 2 == 0) [fm removeItemAtPath:raceWrapper error:nil];
        else writeInfoPlist(app, round % 4 == 1 ? @"1.60.0" : @"1.59.0", round % 4 == 1 ? @"92000" : @"91402");
        pid_t children[kWorkers];
        for (int i = 0; i < kWorkers; i++)
            NSCAssert(posix_spawn(&children[i], gSelfExe, NULL, NULL, (char *const *)raceArgv, environ) == 0, @"posix_spawn failed");
        int statuses[kWorkers] = { 0 }, reaped = 0, visible = 0, vanished = 0;
        while (reaped < kWorkers) {
            struct stat info;
            if (stat(raceLink.fileSystemRepresentation, &info) == 0) visible = 1;
            else if (visible && errno == ENOENT) vanished++;
            for (int i = 0; i < kWorkers; i++) {
                if (children[i] > 0 && waitpid(children[i], &statuses[i], WNOHANG) == children[i]) {
                    children[i] = 0;
                    reaped++;
                }
            }
        }
        for (int i = 0; i < kWorkers; i++)
            NSCAssert(WIFEXITED(statuses[i]) && WEXITSTATUS(statuses[i]) == 0, @"concurrent headlessApp worker %d failed (status %d)", i, statuses[i]);
        NSCAssert(vanished == 0, @"the executable link went missing %d times while other launches were spawning", vanished);
    }

    [fm removeItemAtPath:root error:nil];
}

static void testApplicationsCopyUpgradeInvalidation(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = makeTempDir();
    NSString *pristine = [root stringByAppendingPathComponent:@"pristine/Dia.app"];
    NSString *copyFolder = [root stringByAppendingPathComponent:@"copy"];
    NSString *clone = [copyFolder stringByAppendingPathComponent:@"Dia.app"];
    NSString *pristineExe = [pristine stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    NSString *cloneExe = [clone stringByAppendingPathComponent:@"Contents/MacOS/Dia"];

    // Hotfix build update: SAME executable size + SAME exact mtime + SAME short version, DIFFERENT CFBundleVersion.
    [fm createDirectoryAtPath:pristineExe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert([makeMachOWithUUID(0x11) writeToFile:pristineExe atomically:YES], @"write uuid 0x11");
    setExactMtime(pristineExe, 1700000000, 123456000);
    writeInfoPlist(pristine, @"1.58.0", @"91177");
    NSString *orphan = [copyFolder stringByAppendingPathComponent:@"Dia.app.999999"];
    writeBundle(orphan, @"orphan");
    NSCAssert([applicationsCopyIn(copyFolder, pristine) isEqualToString:clone], @"initial clone with Info.plist");
    assertNoTempBundles(copyFolder);

    writeInfoPlist(pristine, @"1.58.0", @"91178");
    NSCAssert([applicationsCopyIn(copyFolder, pristine) isEqualToString:clone], @"hotfix build refreshes clone");
    NSDictionary *cloneInfo = [NSDictionary dictionaryWithContentsOfFile:[clone stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSCAssert([cloneInfo[@"CFBundleVersion"] isEqual:@"91178"], @"clone updated to hotfix build 91178, got %@", cloneInfo[@"CFBundleVersion"]);

    writeInfoPlist(pristine, @"1.59.0", @"91178");
    NSCAssert([applicationsCopyIn(copyFolder, pristine) isEqualToString:clone], @"short version change refreshes clone");
    cloneInfo = [NSDictionary dictionaryWithContentsOfFile:[clone stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSCAssert([cloneInfo[@"CFBundleShortVersionString"] isEqual:@"1.59.0"], @"clone updated to 1.59.0");

    NSCAssert([makeMachOWithUUID(0x22) writeToFile:pristineExe atomically:YES], @"write uuid 0x22");
    setExactMtime(pristineExe, 1700000000, 123456000);
    NSCAssert([applicationsCopyIn(copyFolder, pristine) isEqualToString:clone], @"LC_UUID change refreshes clone");
    NSCAssert([machOUUID(cloneExe) isEqualToData:machOUUID(pristineExe)], @"clone LC_UUID matches updated pristine");

    NSString *src = [root stringByAppendingPathComponent:@"stub.c"];
    NSCAssert([@"int main(void){return 0;}\n" writeToFile:src atomically:YES encoding:NSUTF8StringEncoding error:nil], @"write stub.c");
    NSCAssert(runTool(@[ @"/usr/bin/clang", @"-arch", @"arm64", src, @"-o", pristineExe ]) == 0, @"compile arm64 stub");
    writeInfoPlist(pristine, @"1.59.0", @"91402");
    NSCAssert(runTool(@[ @"/usr/bin/codesign", @"--force", @"--sign", @"-", pristine ]) == 0, @"sign pristine stub");
    NSCAssert([applicationsCopyIn(copyFolder, pristine) isEqualToString:clone], @"clone signed bundle");
    NSData *origHash = codeHashOnDisk(pristine);
    NSCAssert(origHash != nil && [origHash isEqualToData:codeHashOnDisk(clone)], @"signed clone matches pristine cdhash");

    // Corrupt clone's signature by removing CodeResources; applicationsCopyIn must repair it.
    NSString *cloneRes = [clone stringByAppendingPathComponent:@"Contents/_CodeSignature/CodeResources"];
    [fm removeItemAtPath:cloneRes error:nil];
    struct stat st;
    NSCAssert(!copyMatches(pristine, clone, &st), @"missing CodeResources invalidates clone");
    NSCAssert([applicationsCopyIn(copyFolder, pristine) isEqualToString:clone], @"repairs damaged signed clone");
    NSCAssert([fm fileExistsAtPath:cloneRes] && [origHash isEqualToData:codeHashOnDisk(clone)], @"repaired signed clone is valid");

    [fm removeItemAtPath:clone error:nil];
    NSCAssert([fm createSymbolicLinkAtPath:clone withDestinationPath:@"/nonexistent/broken" error:nil], @"create broken symlink");
    NSCAssert([applicationsCopyIn(copyFolder, pristine) isEqualToString:clone], @"replaces broken symlink with fresh clone");
    NSCAssert([origHash isEqualToData:codeHashOnDisk(clone)], @"clone valid after broken symlink replacement");

    [fm removeItemAtPath:root error:nil];
}

static void testPasswordsHandoffWithClosedStdin(void) {
    NSString *root = makeTempDir();
    NSString *sock = [root stringByAppendingPathComponent:@"handoff.sock"];
    int listener = listenAt(sock);
    NSCAssert(listener >= 0, @"listenAt failed");

    int helperIn[2], helperOut[2];
    NSCAssert(pipe(helperIn) == 0 && pipe(helperOut) == 0, @"pipes failed");
    const char *msg = "hello-from-stdin\n";
    NSCAssert(write(helperIn[1], msg, strlen(msg)) == (ssize_t)strlen(msg), @"write helperIn failed");
    close(helperIn[1]);

    // Spawn child with fd 0 CLOSED so socket() inside DPRunPasswordsHandoff gets fd 0.
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions, STDIN_FILENO);
    const char *argv[] = { gSelfExe, "--child-handoff", sock.fileSystemRepresentation, NULL };
    pid_t pid = 0;
    NSCAssert(posix_spawn(&pid, gSelfExe, &actions, NULL, (char *const *)argv, environ) == 0, @"posix_spawn handoff child failed");
    posix_spawn_file_actions_destroy(&actions);

    int client = accept(listener, NULL, NULL);
    close(listener);
    NSCAssert(client >= 0, @"accept handoff child failed");

    NSDictionary *launch = @{ @"helper" : @"/bin/cat", @"arguments" : @[], @"environment" : @[] };
    NSData *payload = [NSJSONSerialization dataWithJSONObject:launch options:0 error:nil];
    uint32_t length = (uint32_t)payload.length;
    int fds[3] = { helperIn[0], helperOut[1], STDERR_FILENO };
    char control[CMSG_SPACE(sizeof fds)] = { 0 };
    struct iovec iov = { &length, sizeof length };
    struct msghdr hdr = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control };
    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&hdr);
    *cmsg = (struct cmsghdr){ .cmsg_len = CMSG_LEN(sizeof fds), .cmsg_level = SOL_SOCKET, .cmsg_type = SCM_RIGHTS };
    memcpy(CMSG_DATA(cmsg), fds, sizeof fds);
    NSCAssert(sendmsg(client, &hdr, 0) == sizeof length, @"sendmsg failed");
    NSCAssert(write(client, payload.bytes, payload.length) == (ssize_t)payload.length, @"write payload failed");
    close(client);
    close(helperIn[0]);
    close(helperOut[1]);

    char buf[64] = { 0 };
    ssize_t got = read(helperOut[0], buf, sizeof buf - 1);
    close(helperOut[0]);
    int status = 0;
    NSCAssert(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0, @"handoff cat exited %d", status);
    NSCAssert(got == (ssize_t)strlen(msg) && !strcmp(buf, msg), @"helper received intact stdin even when fd 0 started closed (got '%s')", buf);

    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        gSelfExe = argv[0];
        if (argc == 4 && !strcmp(argv[1], "--child-copy")) {
            NSString *copyFolder = @(argv[2]), *pristine = @(argv[3]);
            NSString *clone = [copyFolder stringByAppendingPathComponent:@"Dia.app"];
            return [applicationsCopyIn(copyFolder, pristine) isEqualToString:clone] ? 0 : 1;
        }
        if (argc == 3 && !strcmp(argv[1], "--child-headless")) {
            NSString *app = @(argv[2]);
            NSString *link = [[app.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Headless.app"] stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
            if (!headlessApp(app)) return 1;
            struct timeval start, now;
            gettimeofday(&start, NULL);
            do {
                struct stat info;
                if (stat(link.fileSystemRepresentation, &info) != 0) return 2;
                gettimeofday(&now, NULL);
            } while ((now.tv_sec - start.tv_sec) * 1000000 + (now.tv_usec - start.tv_usec) < 50000);
            return 0;
        }
        if (argc == 3 && !strcmp(argv[1], "--child-handoff")) {
            setenv(DPHandoffVariable, argv[2], 1);
            return DPRunPasswordsHandoff();
        }
        if (argc == 3 && !strcmp(argv[1], "--child-host")) {
            int before = countOpenFDs();
            int rc = DPRunPasskeyHost(@(argv[2]));
            int after = countOpenFDs();
            return after != before ? 99 : rc;
        }
        testApplicationsCopy();
        testHeadlessApp();
        testApplicationsCopyUpgradeInvalidation();
        testPasswordsHandoffWithClosedStdin();
        testPasskeyMessageValidation();
        testHelperMessageFraming();
        testSpawnEnvironmentOverrides();
        testPasskeyHostErrorPathsAndFDCleanup();
        puts("all diapatch passkeys hardening checks passed");
    }
    return 0;
}

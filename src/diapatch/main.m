#import "AppIcon.h"
#import "BriefLanguage.h"
#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import "LaunchServices.h"
#import "Passkeys.h"
#import "Passwords.h"
#include <libproc.h>
#include <mach-o/loader.h>
#include <sys/clonefile.h>
#include <sys/file.h>
#include <sys/stat.h>

#define DYLIB "DiaPatches.dylib"
static NSString *const kFeed = @"https://releases.diabrowser.com/BoostBrowser-updates.xml";
static NSString *const kSparkle = @"http://www.andymatuschak.org/xml-namespaces/sparkle";
static NSString *const kLocalIdentity = @"DiaPatches Local Signing";
static NSString *const kReleases = @"https://api.github.com/repos/JaceThings/DiaTweaks/releases/latest";
static NSString *const kReleaseAsset = @"DiaTweaks.zip";
static NSString *const kCompare = @"https://api.github.com/repos/JaceThings/DiaTweaks/compare";
static NSString *const kDiaReleaseNotes = @"https://www.diabrowser.com/release-notes/latest";

static NSString *gHome, *gApp, *gCache, *gPristine, *gStaged, *gReady;
static const char *gCommand;
static FILE *gLog;
static NSString *gFailure;

static BOOL emit(FILE *out, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static BOOL emit(FILE *out, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    BOOL failure = out == stderr;
    if (failure) gFailure = line;
    if (gLog) {
        char stamp[20];
        time_t now = time(NULL);
        strftime(stamp, sizeof stamp, "%F %T", localtime(&now));
        fprintf(gLog, "%s %s[%d] %s%s\n", stamp, gCommand, getpid(), failure ? "error: " : "", line.UTF8String);
    }
    if (out) fprintf(out, "%s%s\n", failure ? "diapatch: " : "", line.UTF8String);
    return !failure;
}

#define note(...) emit(NULL, __VA_ARGS__)
#define say(...) emit(stdout, __VA_ARGS__)
#define fail(...) emit(stderr, __VA_ARGS__)

static NSString *env(const char *name) {
    const char *value = getenv(name);
    return value && *value ? @(value) : nil;
}

static NSString *trimmed(NSString *text) { return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

static NSString *inHome(NSString *name) { return [gHome stringByAppendingPathComponent:name]; }

static BOOL exists(NSString *path) { return [NSFileManager.defaultManager fileExistsAtPath:path]; }

static BOOL makeDir(NSString *path) {
    NSError *error;
    return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]
        || fail(@"cannot create %@: %@", path, error.localizedDescription);
}

static BOOL removeTree(NSString *path) {
    NSError *error;
    return [NSFileManager.defaultManager removeItemAtPath:path error:&error] || error.code == NSFileNoSuchFileError
        || fail(@"cannot remove %@: %@", path, error.localizedDescription);
}

static BOOL removeQuietly(NSString *path) {
    NSError *error;
    if ([NSFileManager.defaultManager removeItemAtPath:path error:&error] || error.code == NSFileNoSuchFileError) return YES;
    for (NSString *item in [NSFileManager.defaultManager enumeratorAtPath:path])
        [NSFileManager.defaultManager setAttributes:@{ NSFileImmutable : @NO } ofItemAtPath:[path stringByAppendingPathComponent:item] error:nil];
    return [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

// Unremovable leftovers (root-owned files) are set aside, or every later install would fail.
static BOOL emptyTrash(void) {
    NSString *trash = inHome(@".trash"), *aside = [trash stringByAppendingFormat:@"-%@", NSUUID.UUID.UUIDString];
    if (removeQuietly(trash)) return YES;
    if (rename(trash.fileSystemRepresentation, aside.fileSystemRepresentation) != 0) return fail(@"cannot remove %@: %s", trash, strerror(errno));
    note(@"cannot remove everything in %@, so it's set aside as %@", trash, aside.lastPathComponent);
    return YES;
}

static void removeSetAside(void) {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:gHome error:nil])
        if ([name hasPrefix:@".trash-"]) removeQuietly(inHome(name));
}

// Rename to .trash first: a cut-short delete must not leave half a bundle where a whole one belongs.
static BOOL discard(NSString *path) {
    NSString *trash = inHome(@".trash");
    if (!emptyTrash()) return NO;
    if (rename(path.fileSystemRepresentation, trash.fileSystemRepresentation) == 0) return emptyTrash();
    if (errno == ENOENT) return YES;
    return errno == EXDEV ? removeTree(path) : fail(@"cannot remove %@: %s", path, strerror(errno));
}

static int run(NSArray<NSString *> *argv, NSString **output) {
    if (output) *output = nil;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    NSPipe *pipe = NSPipe.pipe;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = task.standardError = pipe;
    if (![task launchAndReturnError:NULL]) return -1;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (output)
        *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] ?: @"";
    return task.terminationStatus;
}

static BOOL check(NSArray<NSString *> *argv) {
    NSString *output;
    int status = run(argv, &output);
    return status == 0
        || fail(@"%@ failed (%d): %@", argv[0].lastPathComponent, status, trimmed(output));
}

// Dia's feed server turns away some HTTP clients but accepts curl.
static int fetch(NSString *url, int seconds, NSString *file, NSString **output) {
    NSArray *argv = @[ @"/usr/bin/curl", @"-fsSL", @"--proto", @"=https,file", @"--proto-redir", @"=https", @"--max-time",
                       @(seconds).stringValue, url ];
    return run(file ? [argv arrayByAddingObjectsFromArray:@[ @"-o", file ]] : argv, output);
}

// codesign --strict rejects the extended attributes Finder copies carry.
static BOOL clone(NSString *from, NSString *to) {
    BOOL copied = clonefile(from.fileSystemRepresentation, to.fileSystemRepresentation, 0) == 0
        || ((errno == EXDEV || errno == ENOTSUP) ? check(@[ @"/usr/bin/ditto", from, to ]) : fail(@"cannot clone %@: %s", from, strerror(errno)));
    return copied && check(@[ @"/usr/bin/xattr", @"-cr", to ]);
}

static int place(NSString *from, NSString *to) {
    const char *source = from.fileSystemRepresentation, *target = to.fileSystemRepresentation;
    struct stat sourceInfo, targetInfo;
    if (lstat(source, &sourceInfo) != 0) return errno;
    BOOL swap = lstat(target, &targetInfo) == 0 && (S_ISDIR(sourceInfo.st_mode) || S_ISDIR(targetInfo.st_mode));
    return (swap ? renamex_np(source, target, RENAME_SWAP) : rename(source, target)) == 0 ? 0 : errno;
}

static BOOL moveBundle(NSString *from, NSString *to) {
    NSString *incoming = [to stringByAppendingString:@".incoming"];
    int error = place(from, to);
    if (error == EXDEV) error = removeTree(incoming) && check(@[ @"/usr/bin/ditto", from, incoming ]) ? place(incoming, to) : -1;
    if (error) {
        removeTree(incoming);
        if (error > 0)
            fail(@"cannot move %@ to %@: %s%@", from, to, strerror(error),
                 error == EPERM ? @" (see System Settings > Privacy & Security > App Management)" : @"");
        return NO;
    }
    return removeTree(incoming) && discard(from);
}

static NSDictionary *infoOf(NSString *app) {
    return [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:[app stringByAppendingPathComponent:@"Contents/Info.plist"]]
                                               error:NULL];
}

static NSString *buildOf(NSString *app) { return infoOf(app)[@"CFBundleVersion"]; }

static NSString *versionOf(NSString *app) {
    NSDictionary *info = infoOf(app);
    return info ? [NSString stringWithFormat:@"%@ (%@)", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]] : nil;
}

static BOOL isPatched(NSString *app) { return [infoOf(app)[@"DiaPatches"] boolValue]; }

static BOOL claimsOfficial(NSString *app) {
    NSString *details;
    return run(@[ @"/usr/bin/codesign", @"-dv", app ], &details) == 0 && [details containsString:@"\nTeamIdentifier=S6N382Y83G\n"];
}

static BOOL verifyOfficial(NSString *app) {
    note(@"verifying %@", app);
    return ([infoOf(app)[@"CFBundleIdentifier"] isEqual:@"company.thebrowser.dia"] || fail(@"%@ is not Dia", app))
        && check(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", @"-R",
                    @"=anchor apple generic and certificate leaf[subject.OU] = \"S6N382Y83G\"", app ])
        && check(@[ @"/usr/sbin/spctl", @"--assess", @"--type", @"execute", app ]);
}

static BOOL appRunning(void) {
    char root[PATH_MAX], path[PROC_PIDPATHINFO_MAXSIZE];
    if (!realpath(gApp.fileSystemRepresentation, root)) return NO;
    size_t rootLen = strlcat(root, "/", sizeof root);
    if (rootLen >= sizeof root) return NO;
    int listed = proc_listallpids(NULL, 0);
    int capacity = (listed > 0 ? listed : 0) + 64;
    pid_t *pids = calloc((size_t)capacity, sizeof *pids);
    if (!pids) return NO;
    int count = proc_listallpids(pids, capacity * (int)sizeof *pids);
    if (count > capacity) count = capacity;
    BOOL running = NO;
    for (int i = 0; i < count; i++) {
        if (proc_pidpath(pids[i], path, sizeof path) > 0 && strncmp(path, root, rootLen) == 0) {
            running = YES;
            break;
        }
    }
    free(pids);
    return running;
}

static void waitForQuit(pid_t pid) {
    note(@"waiting for %@ to quit", gApp);
    for (int i = 0; i < 240 && ((pid > 0 && kill(pid, 0) == 0) || appRunning()); i++) usleep(250000);
}

static BOOL addLoadCommand(NSString *path, NSString *dylib) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode))
        return fail(@"%@ is not a regular file", path);
    const char *name = dylib.fileSystemRepresentation;
    size_t nameLen = strlen(name);
    uint32_t size = (uint32_t)(sizeof(struct dylib_command) + nameLen + 8) & ~7u;
    uint64_t end = 0;
    uint32_t counts[2] = { 0, 0 };
    BOOL alreadyLoaded = NO, valid = NO;
    @autoreleasepool {
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        const uint8_t *bytes = data.bytes;
        const struct mach_header_64 *header = data.bytes;
        if (data.length < sizeof *header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64)
            return fail(@"%@ is not a thin arm64 executable", path);
        end = sizeof *header + (uint64_t)header->sizeofcmds;
        uint64_t firstSection = data.length;
        if (end > data.length) return fail(@"%@ has malformed load commands", path);
        for (uint64_t offset = sizeof *header, i = 0; i < header->ncmds; i++) {
            if (offset + sizeof(struct load_command) > end) return fail(@"%@ has malformed load commands", path);
            const struct load_command *lc = (const void *)(bytes + offset);
            if (lc->cmdsize < sizeof(struct load_command) || (lc->cmdsize & 7) != 0 || offset + lc->cmdsize > end)
                return fail(@"%@ has malformed load commands", path);
            if (lc->cmd == LC_LOAD_WEAK_DYLIB || lc->cmd == LC_LOAD_DYLIB) {
                if (lc->cmdsize < sizeof(struct dylib_command)) return fail(@"%@ has malformed load commands", path);
                const struct dylib_command *dc = (const void *)lc;
                uint32_t nameOff = dc->dylib.name.offset;
                if (nameOff < sizeof(struct dylib_command) || nameOff >= lc->cmdsize) return fail(@"%@ has malformed load commands", path);
                const char *existing = (const char *)lc + nameOff;
                size_t maxLen = lc->cmdsize - nameOff, existingLen = strnlen(existing, maxLen);
                if (existingLen == maxLen) return fail(@"%@ has malformed load commands", path);
                if (lc->cmd == LC_LOAD_WEAK_DYLIB && existingLen == nameLen && memcmp(existing, name, nameLen) == 0) alreadyLoaded = YES;
            } else if (lc->cmd == LC_SEGMENT_64) {
                if (lc->cmdsize < sizeof(struct segment_command_64)) return fail(@"%@ has malformed load commands", path);
                const struct segment_command_64 *segment = (const void *)lc;
                if (sizeof *segment + (uint64_t)segment->nsects * sizeof(struct section_64) > segment->cmdsize)
                    return fail(@"%@ has malformed load commands", path);
                if (!strncmp(segment->segname, SEG_TEXT, sizeof segment->segname)) {
                    const struct section_64 *sections = (const void *)(segment + 1);
                    for (uint32_t s = 0; s < segment->nsects; s++) {
                        uint32_t type = sections[s].flags & SECTION_TYPE;
                        if (sections[s].size && type != S_ZEROFILL && type != S_GB_ZEROFILL)
                            firstSection = MIN(firstSection, sections[s].offset);
                    }
                }
            }
            offset += lc->cmdsize;
        }
        if (alreadyLoaded) return YES;
        BOOL room = header->ncmds < UINT32_MAX && header->sizeofcmds <= UINT32_MAX - size && end + size <= firstSection;
        for (uint64_t i = end; room && i < end + size; i++) room = !bytes[i];
        if (!room) return fail(@"%@ has no room for another load command", path);
        counts[0] = header->ncmds + 1;
        counts[1] = header->sizeofcmds + size;
        valid = YES;
    }
    if (!valid) return NO;
    NSMutableData *command = [NSMutableData dataWithLength:size];
    *(struct dylib_command *)command.mutableBytes = (struct dylib_command){
        .cmd = LC_LOAD_WEAK_DYLIB, .cmdsize = size,
        .dylib = { .name.offset = sizeof(struct dylib_command), .timestamp = 2, .current_version = 0x10000,
                   .compatibility_version = 0x10000 },
    };
    memcpy((char *)command.mutableBytes + sizeof(struct dylib_command), name, nameLen + 1);
    // Patch a sibling copy and rename into place so a mapped Mach-O is never mutated in place.
    NSString *tmp = [path stringByAppendingString:@".tmp"];
    const char *src = path.fileSystemRepresentation, *dst = tmp.fileSystemRepresentation;
    unlink(dst);
    BOOL copied = clonefile(src, dst, 0) == 0
        || ((errno == EXDEV || errno == ENOTSUP) && [NSFileManager.defaultManager copyItemAtPath:path toPath:tmp error:NULL]);
    if (!copied) return fail(@"cannot copy %@: %s", path, strerror(errno));
    int fd = open(dst, O_WRONLY | O_CLOEXEC), savedErr = 0;
    BOOL written = NO;
    if (fd >= 0) {
        ssize_t n1 = pwrite(fd, command.bytes, size, (off_t)end);
        ssize_t n2 = n1 == (ssize_t)size ? pwrite(fd, counts, sizeof counts, offsetof(struct mach_header_64, ncmds)) : -1;
        if (n1 != (ssize_t)size) savedErr = n1 < 0 ? errno : EIO;
        else if (n2 != (ssize_t)sizeof counts) savedErr = n2 < 0 ? errno : EIO;
        else written = YES;
        if (close(fd) != 0 && written) savedErr = errno, written = NO;
    } else {
        savedErr = errno;
    }
    if (written && rename(dst, src) != 0) savedErr = errno, written = NO;
    if (!written) {
        unlink(dst);
        return fail(@"cannot write %@: %s", path, strerror(savedErr));
    }
    return YES;
}

static BOOL configureInfo(NSString *app) {
    NSURL *url = [NSURL fileURLWithPath:[app stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSError *error;
    NSMutableDictionary *info = [[NSMutableDictionary alloc] initWithContentsOfURL:url error:&error];
    info[@"SUEnableAutomaticChecks"] = info[@"SUAutomaticallyUpdate"] = @NO;
    info[@"DiaPatches"] = @YES;
    [info removeObjectForKey:@"SUFeedURL"];
    return [info writeToURL:url error:&error] || fail(@"cannot update %@: %@", url.path, error.localizedDescription);
}

static NSString *localIdentity(NSString *keychain) {
    NSString *list;
    run(@[ @"/usr/bin/security", @"find-identity", @"-p", @"codesigning", keychain ], &list);
    if (!list.length) return nil;
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"([0-9A-F]{40}) \"DiaPatches Local Signing\"" options:0 error:NULL];
    });
    NSTextCheckingResult *match = [pattern firstMatchInString:list options:0 range:NSMakeRange(0, list.length)];
    return match ? [list substringWithRange:[match rangeAtIndex:1]] : nil;
}

static NSString *createLocalIdentity(NSString *keychain) {
    note(@"creating the signing identity \"%@\" in %@", kLocalIdentity, keychain);
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"diapatch-identity-%d", getpid()]];
    NSString *config = [dir stringByAppendingPathComponent:@"req.cnf"], *key = [dir stringByAppendingPathComponent:@"key.pem"],
             *cert = [dir stringByAppendingPathComponent:@"cert.pem"], *p12 = [dir stringByAppendingPathComponent:@"id.p12"];
    NSString *request = @"[req]\ndistinguished_name = dn\nprompt = no\nx509_extensions = ext\n[dn]\nCN = DiaPatches Local Signing\n"
                        @"[ext]\nbasicConstraints = critical,CA:FALSE\nkeyUsage = critical,digitalSignature\n"
                        @"extendedKeyUsage = critical,codeSigning\nsubjectKeyIdentifier = hash\n";
    BOOL ok = removeTree(dir)
        && [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @0700 } error:NULL]
        && [request writeToFile:config atomically:NO encoding:NSUTF8StringEncoding error:NULL]
        && check(@[ @"/usr/bin/openssl", @"req", @"-x509", @"-new", @"-newkey", @"rsa:2048", @"-nodes", @"-sha256", @"-days", @"7300",
                    @"-config", config, @"-keyout", key, @"-out", cert ])
        && check(@[ @"/usr/bin/openssl", @"pkcs12", @"-export", @"-inkey", key, @"-in", cert, @"-name", kLocalIdentity,
                    @"-passout", @"pass:diapatch", @"-out", p12 ])
        && check(@[ @"/usr/bin/security", @"import", p12, @"-k", keychain, @"-f", @"pkcs12", @"-P", @"diapatch", @"-T",
                    @"/usr/bin/codesign" ]);
    removeTree(dir);
    return ok ? localIdentity(keychain) : nil;
}

static BOOL sign(NSString *app) {
    NSString *identity = env("DIAPATCH_IDENTITY") ?: trimmed([NSString stringWithContentsOfFile:inHome(@"identity") encoding:NSUTF8StringEncoding error:NULL]);
    NSArray *codesign = @[ @"/usr/bin/codesign", @"--force", @"--timestamp=none", @"--sign" ];
    if (identity.length) {
        codesign = [codesign arrayByAddingObject:identity];
    } else {
        NSString *keychain = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];
        identity = localIdentity(keychain) ?: createLocalIdentity(keychain);
        if (identity) {
            codesign = [codesign arrayByAddingObjectsFromArray:@[ identity, @"--keychain", keychain ]];
        } else {
            codesign = [codesign arrayByAddingObject:@"-"];
            say(@"warning: signing ad hoc, so Dia will ask for keychain access and screen sharing again after every update");
        }
    }
    // Entitlements tied to The Browser Company's profile make AMFI refuse to launch a re-signed Dia.
    NSURL *entitlements = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"diapatch-%d.entitlements", getpid()]]];
    NSDictionary *granted = @{
        @"com.apple.security.device.audio-input" : @YES,
        @"com.apple.security.device.camera" : @YES,
        @"com.apple.security.personal-information.location" : @YES,
    };
    BOOL ok = ([granted writeToURL:entitlements error:NULL] || fail(@"cannot write %@", entitlements.path))
        && check([codesign arrayByAddingObjectsFromArray:@[ @"--entitlements", entitlements.path, app ]]);
    [NSFileManager.defaultManager removeItemAtURL:entitlements error:NULL];
    if (ok) note(@"signed %@ with %@", app, codesign[4]);
    return ok;
}

// ready records the inode, which renames keep: a bundle a stopped apply swapped into staged/ never installs.
static NSString *stagedID(void) {
    struct stat info;
    return lstat(gStaged.fileSystemRepresentation, &info) == 0 ? @(info.st_ino).stringValue : nil;
}

static BOOL stagedReady(void) {
    return [[NSString stringWithContentsOfFile:gReady encoding:NSUTF8StringEncoding error:NULL] isEqualToString:stagedID()];
}

static BOOL unstage(void) { return discard(gStaged) && removeTree(gReady); }

static BOOL switchIcon(void) {
    NSString *problem = DPSwitchIcon(gApp, gHome);
    return !problem || fail(@"%@", problem);
}

static BOOL noteIcon(NSString *outcome) {
    if ([outcome hasPrefix:@"kept "]) say(@"warning: %@", outcome);
    else if (outcome) note(@"%@", outcome);
    return YES;
}

static BOOL build(NSString *source) {
    NSString *executable = infoOf(source)[@"CFBundleExecutable"], *dylib = inHome(@DYLIB);
    if (!executable) return fail(@"no official Dia at %@; reinstall Dia from https://www.diabrowser.com", source);
    if (!exists(dylib)) return fail(@"%@ is missing; reinstall DiaPatches", dylib);
    note(@"building patched Dia %@", versionOf(source));
    NSString *work = [gStaged stringByAppendingString:@".building"], *contents = [work stringByAppendingPathComponent:@"Contents"];
    BOOL ok = removeTree(work) && makeDir(gStaged.stringByDeletingLastPathComponent) && clone(source, work)
        && addLoadCommand([contents stringByAppendingPathComponent:[@"MacOS" stringByAppendingPathComponent:executable]], dylib)
        && configureInfo(work) && removeTree([contents stringByAppendingPathComponent:@"embedded.provisionprofile"])
        && noteIcon(DPPrepareIcons(work, gApp, gHome)) && noteIcon(DPPrepareBriefLanguage(work, gHome)) && sign(work) && moveBundle(work, gStaged) && (DPForgetApp(gStaged), YES)
        && ([stagedID() writeToFile:gReady atomically:YES encoding:NSUTF8StringEncoding error:NULL] || fail(@"cannot write %@", gReady));
    if (!ok) removeTree(work);
    return ok;
}

@interface Release : NSObject
@property(nonatomic, copy) NSString *build, *version, *url, *channel, *minimumOS;
@property(nonatomic) long long size;
@end

@implementation Release
@end

static BOOL parseUint64(NSString *part, uint64_t *value) {
    if (!part.length) return NO;
    const char *s = part.UTF8String;
    for (const char *p = s; *p; p++) if (*p < '0' || *p > '9') return NO;
    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(s, &end, 10);
    if (errno || !end || *end) return NO;
    *value = (uint64_t)parsed;
    return YES;
}

static BOOL newer(NSString *a, NSString *b) {
    if (!a.length) return NO;
    if (!b.length) return YES;
    NSArray<NSString *> *pa = [a componentsSeparatedByString:@"."], *pb = [b componentsSeparatedByString:@"."];
    NSUInteger count = MAX(pa.count, pb.count);
    for (NSUInteger i = 0; i < count; i++) {
        NSString *sa = i < pa.count ? pa[i] : @"0", *sb = i < pb.count ? pb[i] : @"0";
        uint64_t va = 0, vb = 0;
        if (parseUint64(sa, &va) && parseUint64(sb, &vb)) {
            if (va != vb) return va > vb;
        } else {
            NSComparisonResult cmp = [sa compare:sb options:NSNumericSearch];
            if (cmp != NSOrderedSame) return cmp == NSOrderedDescending;
        }
    }
    return NO;
}

static NSString *sparkle(NSXMLElement *item, NSXMLElement *enclosure, NSString *name) {
    NSString *value = [enclosure attributeForLocalName:name URI:kSparkle].stringValue
        ?: [item elementsForLocalName:name URI:kSparkle].firstObject.stringValue;
    value = trimmed(value);
    return value.length ? value : nil;
}

static NSArray<Release *> *releasesIn(NSXMLDocument *feed) {
    NSMutableArray<Release *> *releases = [NSMutableArray array];
    for (NSXMLElement *item in [feed nodesForXPath:@"/rss/channel/item" error:NULL]) {
        NSXMLElement *enclosure = [item nodesForXPath:@"enclosure[@url and not(@*[local-name()='deltaFrom'])]" error:NULL].firstObject;
        Release *release = [Release new];
        release.url = [enclosure attributeForName:@"url"].stringValue;
        release.build = sparkle(item, enclosure, @"version");
        release.channel = sparkle(item, nil, @"channel");
        release.minimumOS = sparkle(item, nil, @"minimumSystemVersion");
        release.size = [enclosure attributeForName:@"length"].stringValue.longLongValue;
        NSString *shortVersion = sparkle(item, enclosure, @"shortVersionString") ?: @"?";
        NSString *suffix = [NSString stringWithFormat:@" (%@)", release.build];
        release.version = [shortVersion hasSuffix:suffix] ? shortVersion : [shortVersion stringByAppendingString:suffix];
        if (release.url && release.build) [releases addObject:release];
    }
    return releases;
}

static Release *offer(NSArray<Release *> *releases) {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *system = [NSString stringWithFormat:@"%ld.%ld.%ld", os.majorVersion, os.minorVersion, os.patchVersion];
    Release *best;
    for (Release *release in releases)
        if (!release.channel && !newer(release.minimumOS, system) && (!best || newer(release.build, best.build))) best = release;
    return best;
}

static NSString *diaFeed(void) {
    NSString *saved = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("diaFeed"), CFSTR("com.diapatches")));
    return env("DIAPATCH_FEED") ?: ([saved isKindOfClass:NSString.class] ? saved : nil) ?: infoOf(gPristine)[@"SUFeedURL"] ?: kFeed;
}

static Release *latest(int seconds, NSString **channel, NSString **problem) {
    NSString *url = diaFeed(), *output;
    NSError *error;
    *channel = [url containsString:@"/release-candidate/"] ? @"Early Birds" : nil;
    NSXMLDocument *feed = fetch(url, seconds, nil, &output) == 0 && output.length
        ? [[NSXMLDocument alloc] initWithXMLString:output options:0 error:&error] : nil;
    Release *release = offer(releasesIn(feed));
    if (!release)
        *problem = [NSString stringWithFormat:@"no update from %@: %@", url,
                                              feed ? @"nothing for this Mac" : error.localizedDescription ?: trimmed(output) ?: @"empty response"];
    return release;
}

static NSString *gStagedTweaks;

static NSDictionary *installedRelease(void) { return [NSDictionary dictionaryWithContentsOfFile:inHome(@"release.plist")]; }
static NSDictionary *stagedRelease(void) {
    return [NSDictionary dictionaryWithContentsOfFile:[gStagedTweaks stringByAppendingPathComponent:@"release.plist"]];
}

static NSDictionary<NSString *, NSString *> *tweaksTargets(void) {
    return @{ @"diapatch" : inHome(@"bin/diapatch"), @"diatweaks" : inHome(@"bin/diatweaks"), @DYLIB : inHome(@DYLIB),
              @"patches.json" : inHome(@"patches.json"), @"app-icons" : inHome(@"app-icons") };
}

static NSString *sha256(NSString *file) {
    NSData *data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [@"sha256:" stringByAppendingString:hex];
}

static NSDictionary *latestTweaks(int seconds, NSString **problem) {
    NSString *url = env("DIAPATCH_RELEASES") ?: kReleases, *output;
    if (fetch(url, seconds, nil, &output) != 0) {
        *problem = [NSString stringWithFormat:@"cannot reach %@: %@", url, trimmed(output) ?: @"unknown error"];
        return nil;
    }
    NSData *jsonData = [output dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *release = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL] : nil;
    NSArray *assets = [release isKindOfClass:NSDictionary.class] && [release[@"assets"] isKindOfClass:NSArray.class] ? release[@"assets"] : nil;
    NSDictionary *asset;
    for (id candidate in assets)
        if ([candidate isKindOfClass:NSDictionary.class] && [candidate[@"name"] isEqual:kReleaseAsset]) asset = candidate;
    NSString *digest = asset[@"digest"], *downloadURL = asset[@"browser_download_url"], *tag = release[@"tag_name"];
    if (![digest isKindOfClass:NSString.class] || ![digest hasPrefix:@"sha256:"] || ![tag isKindOfClass:NSString.class]
        || ![downloadURL isKindOfClass:NSString.class] || !downloadURL.length) {
        *problem = [NSString stringWithFormat:@"no %@ in the latest DiaTweaks release", kReleaseAsset];
        return nil;
    }
    NSNumber *size = [asset[@"size"] isKindOfClass:NSNumber.class] ? asset[@"size"] : @0;
    NSString *notes = [release[@"html_url"] isKindOfClass:NSString.class] ? release[@"html_url"] : @"";
    return @{ @"tag" : tag, @"digest" : digest, @"size" : size, @"releaseNotes" : notes, @"url" : downloadURL };
}

static NSString *sourceCommit(void) {
    if (installedRelease()[@"tag"]) return nil;
#ifdef DIATWEAKS_COMMIT
    NSString *commit = env("DIAPATCH_COMMIT") ?: @DIATWEAKS_COMMIT;
#else
    NSString *commit = env("DIAPATCH_COMMIT");
#endif
    if (commit.length < 7 || commit.length > 40) return nil;
    for (NSUInteger i = 0; i < commit.length; i++) {
        unichar c = [commit characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return nil;
    }
    return commit;
}

static NSString *sourceNotOlder(NSDictionary *latest) {
    NSString *commit = sourceCommit();
    if (!commit || ![latest[@"tag"] isKindOfClass:NSString.class]) return nil;
    NSString *base = env("DIAPATCH_COMPARE") ?: kCompare, *output;
    NSString *tag = [latest[@"tag"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    // Without per_page the answer lists every commit and file between the two.
    NSString *url = [NSString stringWithFormat:@"%@/%@...%@%@", base, tag, commit, [base hasPrefix:@"https:"] ? @"?per_page=1" : @""];
    if (fetch(url, 10, nil, &output) != 0) return nil;
    NSData *jsonData = [output dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *compared = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL] : nil;
    NSString *status = [compared isKindOfClass:NSDictionary.class] ? compared[@"status"] : nil;
    return [@[ @"ahead", @"identical" ] containsObject:status] ? [commit substringToIndex:7] : nil;
}

static BOOL tweaksInstalled(NSDictionary *latest) {
    if (![installedRelease()[@"digest"] isEqual:latest[@"digest"]]) return NO;
    for (NSString *path in tweaksTargets().allValues)
        if (!exists(path)) return NO;
    return YES;
}

static BOOL tweaksDiffer(NSDictionary *latest) {
    return latest && !tweaksInstalled(latest) && ![stagedRelease()[@"digest"] isEqual:latest[@"digest"]];
}

static BOOL tweaksAvailable(NSDictionary *latest) { return tweaksDiffer(latest) && !sourceNotOlder(latest); }

// Dia quarantines what it writes, so Gatekeeper would refuse the unnotarized diapatch it installs.
static BOOL unquarantine(NSString *path) { return check(@[ @"/usr/bin/xattr", @"-dr", @"com.apple.quarantine", path ]); }

static BOOL stageTweaks(void) {
    NSString *problem, *output;
    NSDictionary *latest = latestTweaks(30, &problem);
    if (!latest) return fail(@"%@", problem);
    if ([stagedRelease()[@"digest"] isEqual:latest[@"digest"]]) return say(@"DiaTweaks %@ is ready to install", latest[@"tag"]);
    if (!tweaksDiffer(latest)) return say(@"DiaTweaks %@ is up to date", latest[@"tag"]);
    NSString *source = sourceNotOlder(latest);
    if (source) return say(@"DiaTweaks %@ is older than the source build %@ installed, so it isn't offered", latest[@"tag"], source);

    NSString *work = [gCache stringByAppendingPathComponent:@"release"], *zip = [work stringByAppendingPathComponent:kReleaseAsset];
    NSString *building = [gStagedTweaks stringByAppendingString:@".building"];
    if (!removeTree(work) || !makeDir(work)) return NO;
    note(@"downloading DiaTweaks %@ from %@", latest[@"tag"], latest[@"url"]);
    if (fetch(latest[@"url"], 600, zip, &output) != 0) {
        removeTree(work);
        return fail(@"cannot download DiaTweaks %@: %@", latest[@"tag"], trimmed(output) ?: @"unknown error");
    }
    BOOL ok = ([sha256(zip) isEqual:latest[@"digest"]] || fail(@"the DiaTweaks %@ download doesn't match its digest", latest[@"tag"]))
        && removeTree(building) && makeDir(building) && check(@[ @"/usr/bin/ditto", @"-x", @"-k", zip, building ]) && unquarantine(building);
    for (NSString *name in tweaksTargets())
        ok = ok && (exists([building stringByAppendingPathComponent:name]) || fail(@"DiaTweaks %@ has no %@, so it can't replace this install", latest[@"tag"], name));
    ok = ok && [@{ @"digest" : latest[@"digest"], @"tag" : latest[@"tag"] } writeToFile:[building stringByAppendingPathComponent:@"release.plist"] atomically:YES]
        && moveBundle(building, gStagedTweaks);
    removeTree(work);
    removeTree(building);
    return ok && say(@"DiaTweaks %@ is ready to install", latest[@"tag"]);
}

static NSString *agentPlist(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.diapatches.passwords.plist"];
}

static NSString *agentService(void) { return [NSString stringWithFormat:@"gui/%d/com.diapatches.passwords", getuid()]; }

// bootout returns before a busy job has exited, hence the wait.
static void removeRelay(void) {
    for (NSString *name in @[ @"passwords-helper", @"passwords.sock", @"onepassword.sock" ]) removeTree(inHome(name));
    if (env("DIAPATCH_HOME")) return;
    run(@[ @"/bin/launchctl", @"bootout", agentService() ], NULL);
    for (int i = 0; i < 100 && run(@[ @"/bin/launchctl", @"print", agentService() ], NULL) == 0; i++) usleep(100000);
    removeTree(agentPlist());
    removeTree(DPCopyFolder);
}

static NSNumber *inodeOf(NSString *path) {
    struct stat info;
    return lstat(path.fileSystemRepresentation, &info) == 0 ? @(info.st_ino) : nil;
}

static BOOL applyTweaks(void) {
    NSString *problem;
    NSDictionary *latest = stagedRelease() ? latestTweaks(15, &problem) : nil;
    if (latest && tweaksInstalled(latest)) removeTree(gStagedTweaks);
    else if (tweaksAvailable(latest)) stageTweaks();
    NSString *tag = stagedRelease()[@"tag"];
    if (!tag) return removeTree(gStagedTweaks);
    NSDictionary<NSString *, NSString *> *targets = tweaksTargets();
    removeRelay();
    BOOL ok = makeDir(inHome(@"bin")) && unquarantine(gStagedTweaks);
    // Records each staged item's inode so a resumed apply never swaps an old swapped-out item back.
    NSString *started = [gStagedTweaks stringByAppendingPathComponent:@".applying"];
    BOOL resumed = exists(started);
    NSDictionary *manifest = resumed ? [NSDictionary dictionaryWithContentsOfFile:started] : nil;
    NSMutableDictionary<NSString *, NSNumber *> *inodes = [NSMutableDictionary dictionary];
    for (NSString *name in targets) {
        NSNumber *inode = inodeOf([gStagedTweaks stringByAppendingPathComponent:name]);
        if (inode) inodes[name] = inode;
        ok = ok && (resumed || inode || fail(@"DiaTweaks %@ has no %@, so it can't replace this install", tag, name));
    }
    ok = ok && (resumed || [inodes writeToFile:started atomically:YES] || fail(@"cannot write %@", started));
    for (NSString *name in targets) {
        NSString *from = [gStagedTweaks stringByAppendingPathComponent:name];
        NSNumber *actual = inodeOf(from);
        if (!actual) continue;
        NSNumber *expected = [manifest isKindOfClass:NSDictionary.class] ? manifest[name] : nil;
        if (expected && ![actual isEqual:expected]) ok = ok && discard(from);
        else ok = ok && moveBundle(from, targets[name]);
    }
    ok = ok && moveBundle([gStagedTweaks stringByAppendingPathComponent:@"release.plist"], inHome(@"release.plist"));
    return ok && removeTree(gStagedTweaks) && say(@"installed DiaTweaks %@", tag);
}

static NSString *signatureOf(NSString *app) {
    NSString *output;
    if (run(@[ @"/usr/bin/codesign", @"-dr", @"-", app ], &output) != 0) return nil;
    NSRange range = [output rangeOfString:@"designated => "];
    return range.location == NSNotFound ? nil : trimmed([output substringFromIndex:NSMaxRange(range)]);
}

// Only a changed signature needs the reset: a stale grant stays on and macOS never prompts again.
static void forgetScreenRecordingIfResigned(NSString *before) {
    NSString *bundleID = infoOf(gApp)[@"CFBundleIdentifier"];
    if (env("DIAPATCH_APP") || !bundleID || [before isEqual:signatureOf(gApp)]) return;
    if (run(@[ @"/usr/bin/tccutil", @"reset", @"ScreenCapture", bundleID ], NULL) == 0)
        say(@"Dia's signature changed, so macOS asks again before Dia can share your screen: allow Dia under System Settings > "
            @"Privacy & Security > Screen & System Audio Recording, then reopen Dia");
}

static BOOL apply(void) {
    if (!exists(gStaged)) return YES;
    if (!stagedReady()) return unstage() && fail(@"deleted %@: a stopped run left it there; run `diapatch build` to stage Dia again", gStaged);
    if (appRunning()) return fail(@"Dia is running; quit it, then run `diapatch apply`");
    if (claimsOfficial(gApp) && ![buildOf(gApp) isEqual:buildOf(gPristine)])
        return unstage() && say(@"kept the official Dia %@ at %@; run `diapatch install` to patch it", versionOf(gApp), gApp);
    NSString *signature = signatureOf(gApp);
    if (!(moveBundle(gStaged, gApp) && removeTree(gReady))) return NO;
    forgetScreenRecordingIfResigned(signature);
    return say(@"installed patched Dia %@ at %@", versionOf(gApp), gApp);
}

static BOOL applyChosen(BOOL dia, BOOL tweaks) {
    if (!dia && !tweaks) dia = YES, tweaks = installedRelease()[@"tag"] != nil;
    return (!tweaks || applyTweaks()) && (!dia || apply());
}

static BOOL install(BOOL relaunch) {
    NSString *identity = env("DIAPATCH_IDENTITY");
    if (!exists(gApp)) return fail(@"Dia is not installed at %@; get it from https://www.diabrowser.com", gApp);
    if (identity && ![identity writeToFile:inHome(@"identity") atomically:YES encoding:NSUTF8StringEncoding error:NULL])
        return fail(@"cannot save the signing identity");
    if (claimsOfficial(gApp) && ![buildOf(gApp) isEqual:buildOf(gPristine)]) {
        NSString *copy = [gPristine stringByAppendingString:@".new"];
        BOOL adopted = removeTree(copy) && makeDir(gPristine.stringByDeletingLastPathComponent) && clone(gApp, copy)
            && verifyOfficial(copy) && moveBundle(copy, gPristine);
        if (!adopted) return removeTree(copy), NO;
    }
    removeRelay();
    DPForgetApp(gPristine);
    if (!build(gPristine)) return NO;
    if (appRunning() && relaunch) {
        run(@[ @"/usr/bin/osascript", @"-e", @"tell application id \"company.thebrowser.dia\" to quit" ], NULL);
        waitForQuit(0);
    }
    if (!appRunning()) return apply();
    if (isPatched(gApp)) return say(@"patched Dia %@ is staged and replaces Dia when it quits", versionOf(gStaged));
    return say(@"patched Dia %@ is staged: quit Dia, then run \"%@\" apply (or install --relaunch to do both)", versionOf(gStaged),
               inHome(@"bin/diapatch"));
}

static NSString *unpatchableFile(void) { return inHome(@"unpatchable.plist"); }

static NSString *ownDigest(void) { return sha256(NSBundle.mainBundle.executablePath); }

static void rememberUnpatchable(Release *release, NSString *action) {
    NSString *line = [gFailure componentsSeparatedByString:@"\n"].firstObject;
    note(@"Dia %@ can't be installed by this DiaTweaks (couldn't %@ it), so it isn't downloaded automatically again", release.version, action);
    [@{ @"build" : release.build, @"diapatch" : ownDigest() ?: @"", @"reason" : [NSString stringWithFormat:@"Couldn’t %@ this version: %@", action, line ?: @"unknown error"] }
        writeToFile:unpatchableFile() atomically:YES];
}

static NSString *unpatchableReason(Release *release) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:unpatchableFile()];
    NSString *reason = saved[@"reason"];
    return release && [saved[@"build"] isEqual:release.build] && [saved[@"diapatch"] isEqual:ownDigest()] && [reason isKindOfClass:NSString.class] ? reason : nil;
}

static BOOL update(void) {
    NSString *channel, *problem, *output;
    Release *release = latest(60, &channel, &problem);
    if (!release) return fail(@"%@", problem);
    if (!newer(release.build, buildOf(gPristine))) {
        if (stagedReady()) return say(@"Dia %@ is staged; relaunch Dia or run `diapatch apply` to install it", versionOf(gStaged));
        return say(@"Dia %@ is up to date", release.version);
    }
    NSString *work = [gCache stringByAppendingPathComponent:@"download"];
    NSString *zip = [work stringByAppendingPathComponent:@"Dia.zip"], *app = [work stringByAppendingPathComponent:@"Dia.app"];
    if (!removeTree(work) || !makeDir(work)) return NO;
    note(@"downloading Dia %@ (%@) from %@", release.version, channel ?: @"stable", release.url);
    if (fetch(release.url, 3600, zip, &output) != 0) {
        removeTree(work);
        return fail(@"cannot download Dia %@: %@", release.version, trimmed(output) ?: @"unknown error");
    }
    gFailure = nil;
    BOOL unpacked = check(@[ @"/usr/bin/ditto", @"-x", @"-k", zip, work ]) && check(@[ @"/usr/bin/xattr", @"-cr", work ]);
    BOOL official = unpacked && ([buildOf(app) isEqual:release.build] || fail(@"the download holds build %@, not %@", buildOf(app), release.build))
        && verifyOfficial(app);
    BOOL built = official && build(app);
    if (unpacked && !built) rememberUnpatchable(release, official ? @"patch" : @"verify");
    BOOL ok = built && makeDir(gPristine.stringByDeletingLastPathComponent) && moveBundle(app, gPristine) && (DPForgetApp(gPristine), YES);
    removeTree(work);
    if (ok) removeTree(unpatchableFile());
    return ok && say(@"Dia %@ is staged; relaunch Dia or run `diapatch apply` to install it", release.version);
}

static void removePasswordsHost(void) {
    NSArray<NSString *> *folders = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome/NativeMessagingHosts"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data/NativeMessagingHosts"],
    ];
    for (NSString *file in @[ @"com.apple.passwordmanager.json", @"io.github.fanckush.betterpasswords.bridge.json", @"com.openpasswords.icloud.json", @"com.diapatches.passkeys.json" ]) {
        for (NSString *folder in folders) {
            NSString *path = [folder stringByAppendingPathComponent:file];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data) continue;
            NSDictionary *host = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (![host isKindOfClass:NSDictionary.class] || ![host[@"path"] isEqual:inHome(@"bin/diapatch")]) continue;
            removeTree(path);
            [NSFileManager.defaultManager moveItemAtPath:inHome(file) toPath:path error:NULL];
        }
        NSString *kept = inHome(file);
        if (exists(kept)) {
            for (NSString *folder in folders) {
                if (!exists(folder)) continue;
                NSString *path = [folder stringByAppendingPathComponent:file];
                if (!exists(path) && [NSFileManager.defaultManager moveItemAtPath:kept toPath:path error:NULL]) break;
            }
        }
    }
}

static BOOL purge(void) {
    NSArray<NSString *> *linkDirs = env("DIATWEAKS_LINK_DIR") ? @[ env("DIATWEAKS_LINK_DIR") ]
        : @[ @"/opt/homebrew/bin", @"/usr/local/bin", [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"] ];
    for (NSString *dir in linkDirs) {
        NSString *link = [dir stringByAppendingPathComponent:@"diatweaks"];
        NSString *target = [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:link error:NULL];
        if (![target hasPrefix:[gHome stringByAppendingString:@"/"]]) continue;
        if (!removeTree(link)) return NO;
        say(@"deleted %@", link);
    }
    for (NSString *name in @[ @"bin", @DYLIB, @"patches.json", @"release.plist", @"pristine", @"staged", @"identity", @"diapatch.log", @"safe-mode.plist", @"paused",
                              @".diatweaks.lock", @".incoming", @"icons", @"app-icons", @"passwords-helper", @"passwords.sock", @"onepassword.sock", @"passwords-launch",
                              @"passkey-helper", @"passkey-helper.lock", @"passkeys-extension", @"unpatchable.plist",
                              @"methods.txt", @"views.txt", @"layout-loops.txt" ])
        if (!discard(inHome(name))) return NO;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:gHome error:NULL])
        if (([name hasPrefix:@".update-"] || [name hasPrefix:@"little-dia-"]) && !removeTree(inHome(name))) return NO;
    removeSetAside();
    for (NSString *name in @[ @"download", @"release", @"previews" ])
        if (!removeTree([gCache stringByAppendingPathComponent:name])) return NO;
    rmdir(gCache.fileSystemRepresentation);
    if (rmdir(gHome.fileSystemRepresentation) == 0) return say(@"deleted %@", gHome);
    return say(@"kept %@: it holds files DiaPatches did not create", gHome);
}

static BOOL uninstall(BOOL purgeFiles) {
    if (appRunning()) return fail(@"Dia is running; quit it, then run `diapatch uninstall`");
    BOOL needRestore = !claimsOfficial(gApp);
    if (needRestore && !exists(gPristine)) return fail(@"no official Dia at %@; reinstall Dia from https://www.diabrowser.com", gPristine);
    removeRelay();
    removePasswordsHost();
    if (!env("DIAPATCH_HOME") && !removeTree(DPCopyFolder)) return NO;
    NSString *signature = signatureOf(gApp);
    if (needRestore) {
        NSString *copy = [gPristine stringByAppendingString:@".restore"];
        if (!removeTree(copy) || !clone(gPristine, copy) || !moveBundle(copy, gApp)) return removeTree(copy), NO;
    }
    forgetScreenRecordingIfResigned(signature);
    say(@"%@ is the official Dia %@", gApp, versionOf(gApp));
    return unstage() && (!purgeFiles || purge());
}

static BOOL printJSON(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:NULL];
    printf("%.*s\n", (int)data.length, (const char *)data.bytes);
    return YES;
}

static BOOL status(BOOL json) {
    NSString *channel, *problem;
    Release *release = latest(15, &channel, &problem);
    NSDictionary *status = @{
        @"official" : versionOf(gPristine) ?: NSNull.null,
        @"installed" : versionOf(gApp) ?: NSNull.null,
        @"patched" : @(isPatched(gApp)),
        @"staged" : (stagedReady() ? versionOf(gStaged) : nil) ?: NSNull.null,
        @"feed" : release.version ?: NSNull.null,
        @"channel" : channel ?: @"stable",
        @"release" : installedRelease()[@"tag"] ?: NSNull.null,
    };
    if (json) return printJSON(status);
    for (NSString *key in @[ @"official", @"installed", @"patched", @"staged", @"feed", @"channel", @"release" ]) {
        id value = status[key];
        if (value == NSNull.null) value = [key isEqualToString:@"feed"] ? problem : @"none";
        else if ([key isEqualToString:@"patched"]) value = [value boolValue] ? @"yes" : @"no";
        printf("%-10s%s\n", key.UTF8String, [value UTF8String]);
    }
    return YES;
}

static BOOL checkUpdates(void) {
    NSString *channel, *problem, *tweaksProblem;
    Release *dia = latest(15, &channel, &problem);
    NSDictionary *tweaks = latestTweaks(15, &tweaksProblem);
    BOOL ready = stagedReady();
    BOOL diaStaged = ready && [buildOf(gStaged) isEqual:dia.build];
    NSDictionary *result = @{
        @"dia" : @{
            @"installed" : versionOf(gPristine) ?: NSNull.null,
            @"latest" : dia.version ?: NSNull.null,
            @"size" : @(dia.size),
            @"releaseNotes" : kDiaReleaseNotes,
            @"staged" : (ready ? versionOf(gStaged) : nil) ?: NSNull.null,
            @"available" : @((BOOL)(dia && newer(dia.build, buildOf(gPristine)) && !diaStaged)),
            @"unpatchable" : unpatchableReason(dia) ?: NSNull.null,
            @"error" : dia ? NSNull.null : problem,
        },
        @"tweaks" : @{
            @"installed" : installedRelease()[@"tag"] ?: NSNull.null,
            @"latest" : tweaks[@"tag"] ?: NSNull.null,
            @"size" : tweaks[@"size"] ?: @0,
            @"releaseNotes" : tweaks[@"releaseNotes"] ?: NSNull.null,
            @"staged" : stagedRelease()[@"tag"] ?: NSNull.null,
            @"available" : @((BOOL)tweaksAvailable(tweaks)),
            @"error" : tweaks ? NSNull.null : tweaksProblem,
        },
    };
    return printJSON(result);
}

static const char kUsage[] =
    "usage: diapatch <command>\n"
    "  install [--relaunch]\n"
    "                   keep the official Dia as the pristine copy, patch it and put it in place;\n"
    "                   --relaunch quits a running Dia first and reopens it afterwards\n"
    "  build            rebuild the staged patched Dia from the pristine copy\n"
    "  update           download, verify and stage a newer Dia from your channel (stable or Early Birds)\n"
    "  self-update      download, verify and stage the latest DiaTweaks release if it isn't the one installed\n"
    "  apply [--wait PID] [--relaunch] [--dia] [--tweaks]\n"
    "                   install what's staged once PID and Dia have quit, then reopen Dia; --dia or --tweaks limits it,\n"
    "                   and only --tweaks installs a staged DiaTweaks release over a source build\n"
    "  check --json     what's installed, available and staged for Dia and DiaTweaks\n"
    "  set-icon         use the icon chosen in the App Icon tweak\n"
    "  uninstall [--wait PID] [--relaunch] [--purge]\n"
    "                   put the official Dia back; --purge also deletes DiaPatches' files and the diatweaks command\n"
    "  status [--json]  official, installed, staged and offered versions, and the update channel\n"
    "environment: DIAPATCH_IDENTITY (codesigning identity, remembered by install), DIAPATCH_HOME,\n"
    "  DIAPATCH_APP, DIAPATCH_CACHE, DIAPATCH_FEED, DIAPATCH_RELEASES, DIAPATCH_COMMIT (the source commit installed), DIAPATCH_COMPARE, DIATWEAKS_LINK_DIR, DIAPATCH_NO_RELAUNCH (ignore --relaunch)\n"
    "  DIAPATCH_APP (also keeps apply and uninstall from clearing Dia's Screen Recording permission)\n";

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (DPIsPasswordsHandoff(argc, argv)) return DPRunPasswordsHandoff();
        signal(SIGPIPE, SIG_IGN);
        gHome = (env("DIAPATCH_HOME") ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DiaPatches"]).stringByStandardizingPath;
        gApp = (env("DIAPATCH_APP") ?: @"/Applications/Dia.app").stringByStandardizingPath;
        gCache = (env("DIAPATCH_CACHE") ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/DiaPatches"]).stringByStandardizingPath;
        gPristine = inHome(@"pristine/Dia.app");
        gStaged = inHome(@"staged/Dia.app");
        gReady = inHome(@"staged/ready");
        gStagedTweaks = inHome(@"staged/DiaTweaks");
        if (argc > 1 && !strncmp(argv[1], "chrome-extension://", 19)) {
            if (!DPIsPasswordsOrigin(argv[1])) return DPRunPasskeyHost(gHome);
            return DPRunPasswordsHost(gHome, gApp, argc, argv);
        }

        NSString *command = argc > 1 ? @(argv[1]) : @"";
        NSArray<NSString *> *allowed = @{
            @"install" : @[ @"--relaunch" ], @"build" : @[], @"set-icon" : @[], @"update" : @[], @"self-update" : @[], @"status" : @[ @"--json" ],
            @"apply" : @[ @"--wait", @"--relaunch", @"--dia", @"--tweaks" ], @"check" : @[ @"--json" ], @"uninstall" : @[ @"--wait", @"--relaunch", @"--purge" ],
        }[command];
        NSMutableSet<NSString *> *flags = [NSMutableSet set];
        pid_t pid = 0;
        for (int i = 2; allowed && i < argc; i++) {
            [flags addObject:@(argv[i])];
            if (![allowed containsObject:@(argv[i])] || (!strcmp(argv[i], "--wait") && (++i == argc || (pid = atoi(argv[i])) <= 0)))
                allowed = nil;
        }
        if (!allowed) {
            BOOL help = argc == 2 && [@[ @"help", @"-h", @"--help" ] containsObject:command];
            fputs(kUsage, help ? stdout : stderr);
            return help ? 0 : 2;
        }
        if (env("DIAPATCH_NO_RELAUNCH")) [flags removeObject:@"--relaunch"];
        if ([command isEqualToString:@"status"]) return status([flags containsObject:@"--json"]) ? 0 : 1;
        if ([command isEqualToString:@"check"]) return checkUpdates() ? 0 : 1;

        if (pid) setsid();  // Dia is about to quit: leave its process group
        gCommand = argv[1];
        if (!makeDir(gHome)) return 1;
        gLog = fopen(inHome(@"diapatch.log").fileSystemRepresentation, "ae");
        if (!gLog) return fail(@"cannot open %@: %s", inHome(@"diapatch.log"), strerror(errno)), 1;
        setvbuf(gLog, NULL, _IOLBF, 0);
        if (pid) waitForQuit(pid);
        if (flock(fileno(gLog), LOCK_EX | LOCK_NB) != 0) {
            if (errno == EWOULDBLOCK) say(@"waiting for another diapatch run to finish");
            while (flock(fileno(gLog), LOCK_EX) != 0 && errno == EINTR) {}
        }
        removeSetAside(), emptyTrash();
        BOOL ok = [command isEqualToString:@"install"] ? install([flags containsObject:@"--relaunch"])
            : [command isEqualToString:@"set-icon"]    ? switchIcon()
            : [command isEqualToString:@"build"]       ? build(gPristine) && say(@"staged patched Dia %@", versionOf(gStaged))
            : [command isEqualToString:@"update"]      ? update()
            : [command isEqualToString:@"self-update"] ? stageTweaks()
            : [command isEqualToString:@"apply"]       ? applyChosen([flags containsObject:@"--dia"], [flags containsObject:@"--tweaks"])
                                                       : uninstall([flags containsObject:@"--purge"]);
        // open sometimes fails with -600 right after Dia quits itself.
        if ([flags containsObject:@"--relaunch"] && exists(gApp)) {
            NSString *relaunchOut = nil;
            int relaunchStatus = -1;
            for (int i = 0; i < 20; i++) {
                if ((relaunchStatus = run(@[ @"/usr/bin/open", gApp ], &relaunchOut)) == 0) break;
                usleep(500000);
            }
            if (relaunchStatus != 0) fail(@"open failed (%d): %@", relaunchStatus, trimmed(relaunchOut) ?: @"unknown error");
        }
        return ok ? 0 : 1;
    }
}

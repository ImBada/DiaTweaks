#import <Security/Security.h>
#import <libproc.h>
#import <mach-o/loader.h>
#import <poll.h>
#import <spawn.h>
#import <sys/clonefile.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <sys/xattr.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/wait.h>
#import "LaunchServices.h"
#import "PasswordsParts.h"

extern char **environ;
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim);  // private: macOS asks about the copy, not Dia

NSString *const DPCopyFolder = @"/Applications/.DiaTweaks";
const char *const DPHandoffVariable = "DIAPATCH_PASSWORDS_HANDOFF";
static const NSTimeInterval kStartupTimeout = 20;

static void logLine(NSString *home, NSString *line) {
    FILE *log = fopen([home stringByAppendingPathComponent:@"diapatch.log"].fileSystemRepresentation, "a");
    if (!log) return;
    char stamp[20];
    time_t now = time(NULL);
    strftime(stamp, sizeof stamp, "%F %T", localtime(&now));
    fprintf(log, "%s passwords[%d] %s\n", stamp, getpid(), line.UTF8String);
    fclose(log);
}

static NSArray<NSString *> *strings(const char *const *list, int count) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (int i = 0; count < 0 ? list[i] != NULL : i < count; i++) {
        NSString *string = [NSString stringWithUTF8String:list[i]];
        if (string) [result addObject:string];
    }
    return result;
}

// A socket path holds 103 bytes; a long home falls back to the user's short, private temporary folder.
static BOOL fitsSocket(NSString *path) { return strlen(path.fileSystemRepresentation) < sizeof((struct sockaddr_un *)NULL)->sun_path; }

static NSString *socketPath(NSString *folder, NSString **problem) {
    NSString *path = [folder stringByAppendingString:@".sock"];
    if (fitsSocket(path)) return path;
    char temporary[PATH_MAX];
    struct stat info;
    BOOL mine = confstr(_CS_DARWIN_USER_TEMP_DIR, temporary, sizeof temporary) && stat(temporary, &info) == 0 && info.st_uid == getuid() && !(info.st_mode & 077);
    NSString *shorter = mine ? [[@(temporary) stringByAppendingPathComponent:[NSString stringWithFormat:@"diapatch-%d", getpid()]] stringByAppendingString:@".sock"] : nil;
    if (shorter && fitsSocket(shorter)) return shorter;
    *problem = [NSString stringWithFormat:@"%@ is too long for a socket, and there is no short folder of yours to use instead", path];
    return nil;
}

static int listenAt(NSString *path) {
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof address.sun_path) >= sizeof address.sun_path) return -1;
    unlink(address.sun_path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd >= 0 && bind(fd, (struct sockaddr *)&address, sizeof address) == 0 && listen(fd, 8) == 0) return fd;
    if (fd >= 0) close(fd);
    return -1;
}

static pid_t launchOriginal(NSString *app, NSString *folder, NSString *socket) {
    NSString *dia = [app stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    NSString *profile = [@"--user-data-dir=" stringByAppendingString:[folder stringByAppendingPathComponent:@"ud"]];
    NSString *subprocess = [@"--browser-subprocess-path=" stringByAppendingString:NSBundle.mainBundle.executablePath];
    const char *argv[] = { dia.fileSystemRepresentation, profile.UTF8String, subprocess.UTF8String, "--headless=new", "--no-first-run",
                           "--no-default-browser-check", "--use-mock-keychain", "--mute-audio", NULL };
    NSString *fixedHome = [@"CFFIXED_USER_HOME=" stringByAppendingString:folder];
    NSString *handoff = [NSString stringWithFormat:@"%s=%@", DPHandoffVariable, socket];
    NSString *handoffPrefix = [NSString stringWithFormat:@"%s=", DPHandoffVariable];
    size_t envCount = 0;
    while (environ[envCount]) envCount++;
    const char **envp = calloc(envCount + 3, sizeof *envp);
    if (!envp) return 0;
    size_t out = 0;
    envp[out++] = fixedHome.UTF8String;
    envp[out++] = handoff.UTF8String;
    const char *handoffPrefixStr = handoffPrefix.UTF8String;
    size_t handoffPrefixLen = strlen(handoffPrefixStr);
    for (size_t i = 0; i < envCount; i++) {
        if (!strncmp(environ[i], "CFFIXED_USER_HOME=", 18) || !strncmp(environ[i], handoffPrefixStr, handoffPrefixLen)) continue;
        envp[out++] = environ[i];
    }

    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    for (int fd = 0; fd < 3; fd++) posix_spawn_file_actions_addopen(&files, fd, "/dev/null", fd ? O_WRONLY : O_RDONLY, 0);
    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    posix_spawnattr_setflags(&attrs, POSIX_SPAWN_CLOEXEC_DEFAULT);
    responsibility_spawnattrs_setdisclaim(&attrs, 1);
    pid_t pid = 0;
    int status = posix_spawn(&pid, argv[0], &files, &attrs, (char *const *)argv, (char *const *)envp);
    posix_spawn_file_actions_destroy(&files);
    posix_spawnattr_destroy(&attrs);
    free(envp);
    return status == 0 ? pid : 0;
}

static int acceptSubprocess(int listener, pid_t *dia, pid_t *peer) {
    for (NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kStartupTimeout]; deadline.timeIntervalSinceNow > 0;) {
        struct pollfd ready = { .fd = listener, .events = POLLIN };
        if (poll(&ready, 1, 100) <= 0) {
            if (waitpid(*dia, NULL, WNOHANG) == *dia) return *dia = 0, -1;
            continue;
        }
        int client = accept(listener, NULL, NULL);
        audit_token_t token;
        socklen_t tokenLength = sizeof token, pidLength = sizeof *peer;
        if (client >= 0 && getsockopt(client, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &tokenLength) == 0
            && getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, peer, &pidLength) == 0 && DPParentOf(*peer) == *dia && DPRunsThisDiapatch(token))
            return client;
        if (client >= 0) close(client);
    }
    return -1;
}

static BOOL handOver(int client, NSString *helper, int argc, const char *argv[]) {
    NSDictionary *launch = @{ @"helper" : helper, @"arguments" : strings(argv + 1, argc - 1), @"environment" : strings((const char *const *)environ, -1) };
    NSData *payload = [NSJSONSerialization dataWithJSONObject:launch options:0 error:nil];
    if (!payload.length) return NO;
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &(struct timeval){ .tv_sec = 5 }, sizeof(struct timeval));
    uint32_t length = (uint32_t)payload.length;
    int fds[3] = { STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO };
    char control[CMSG_SPACE(sizeof fds)] = { 0 };
    struct iovec iov = { &length, sizeof length };
    struct msghdr message = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control };
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    *header = (struct cmsghdr){ .cmsg_len = CMSG_LEN(sizeof fds), .cmsg_level = SOL_SOCKET, .cmsg_type = SCM_RIGHTS };
    memcpy(CMSG_DATA(header), fds, sizeof fds);
    ssize_t head;
    do {
        head = sendmsg(client, &message, 0);
    } while (head < 0 && errno == EINTR);
    if (head != sizeof length) return NO;
    for (NSUInteger sent = 0; sent < payload.length;) {
        ssize_t n = write(client, (const char *)payload.bytes + sent, payload.length - sent);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        sent += (NSUInteger)n;
    }
    return YES;
}

static BOOL becameHelper(int client, pid_t peer, NSString *helperPath) {
    char byte, path[PROC_PIDPATHINFO_MAXSIZE], helper[PATH_MAX];
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &(struct timeval){ .tv_sec = 5 }, sizeof(struct timeval));
    for (ssize_t n;;) {
        n = read(client, &byte, 1);
        if (n > 0 || (n < 0 && errno == EINTR)) continue;
        break;
    }
    if (!realpath(helperPath.fileSystemRepresentation, helper)) return NO;
    for (int tries = 0; tries < 50; tries++, usleep(10000))
        if (proc_pidpath(peer, path, sizeof path) > 0 && !strcmp(path, helper)) return YES;
    return NO;
}

// 1Password's helper checks its browser a few ms after starting, so the browser must outlive it.
static const useconds_t kBrowserCheck = 300000;

static BOOL sameStat(const struct stat *a, const struct stat *b) {
    return a->st_size == b->st_size
        && a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec
        && a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec;
}

static NSData *machOUUID(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return nil;
    struct mach_header_64 header;
    if (read(fd, &header, sizeof header) != sizeof header || header.magic != MH_MAGIC_64 || header.sizeofcmds > 1024 * 1024) {
        close(fd);
        return nil;
    }
    NSMutableData *cmds = [NSMutableData dataWithLength:header.sizeofcmds];
    ssize_t got = cmds ? read(fd, cmds.mutableBytes, header.sizeofcmds) : -1;
    close(fd);
    if (got != (ssize_t)header.sizeofcmds) return nil;
    const uint8_t *bytes = cmds.bytes;
    for (uint64_t offset = 0, i = 0; i < header.ncmds; i++) {
        if (offset + sizeof(struct load_command) > header.sizeofcmds) break;
        const struct load_command *lc = (const void *)(bytes + offset);
        if (lc->cmdsize < sizeof(struct load_command) || offset + lc->cmdsize > header.sizeofcmds) break;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command))
            return [NSData dataWithBytes:((const struct uuid_command *)lc)->uuid length:sizeof(((struct uuid_command *)lc)->uuid)];
        offset += lc->cmdsize;
    }
    return nil;
}

static NSData *codeHashOnDisk(NSString *app) {
    SecStaticCodeRef code = NULL;
    NSData *cdhash = nil;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:app], kSecCSDefaultFlags, &code) == errSecSuccess
        && SecStaticCodeCheckValidity(code, kSecCSDoNotValidateResources, NULL) == errSecSuccess) {
        CFDictionaryRef info = NULL;
        if (SecCodeCopySigningInformation(code, kSecCSDefaultFlags, &info) == errSecSuccess)
            cdhash = ((__bridge NSDictionary *)info)[(__bridge NSString *)kSecCodeInfoUnique];
        if (info) CFRelease(info);
    }
    if (code) CFRelease(code);
    return cdhash;
}

static BOOL copyMatches(NSString *pristine, NSString *clone, struct stat *original) {
    NSString *executable = @"Contents/MacOS/Dia";
    NSString *origExe = [pristine stringByAppendingPathComponent:executable];
    NSString *cloneExe = [clone stringByAppendingPathComponent:executable];
    struct stat copy;
    if (stat(origExe.fileSystemRepresentation, original) != 0 || stat(cloneExe.fileSystemRepresentation, &copy) != 0 || !sameStat(original, &copy))
        return NO;

    NSDictionary *origInfo = [NSDictionary dictionaryWithContentsOfFile:[pristine stringByAppendingPathComponent:@"Contents/Info.plist"]];
    if (origInfo) {
        NSDictionary *cloneInfo = [NSDictionary dictionaryWithContentsOfFile:[clone stringByAppendingPathComponent:@"Contents/Info.plist"]];
        if (!cloneInfo) return NO;
        for (NSString *key in @[ @"CFBundleShortVersionString", @"CFBundleVersion" ]) {
            id expected = origInfo[key];
            if (expected && ![expected isEqual:cloneInfo[key]]) return NO;
        }
    }

    NSData *origUUID = machOUUID(origExe);
    if (origUUID) {
        NSData *cloneUUID = machOUUID(cloneExe);
        if (!cloneUUID || ![origUUID isEqualToData:cloneUUID]) return NO;
    }

    struct stat origRes, cloneRes;
    NSString *codeRes = @"Contents/_CodeSignature/CodeResources";
    if (stat([pristine stringByAppendingPathComponent:codeRes].fileSystemRepresentation, &origRes) == 0) {
        if (stat([clone stringByAppendingPathComponent:codeRes].fileSystemRepresentation, &cloneRes) != 0 || !sameStat(&origRes, &cloneRes))
            return NO;
    }

    NSData *origHash = codeHashOnDisk(pristine);
    if (origHash) {
        NSData *cloneHash = codeHashOnDisk(clone);
        if (!cloneHash || ![origHash isEqualToData:cloneHash]) return NO;
    }
    return YES;
}

static void stripQuarantine(NSString *path) {
    // Only strip it when present: macOS warns when a process changes an app it didn't make.
    if (getxattr(path.fileSystemRepresentation, "com.apple.quarantine", NULL, 0, 0, 0) >= 0)
        removexattr(path.fileSystemRepresentation, "com.apple.quarantine", 0);
}

static BOOL cloneBundle(NSString *from, NSString *to) {
    if (clonefile(from.fileSystemRepresentation, to.fileSystemRepresentation, 0) == 0) return YES;
    if (errno != EXDEV && errno != ENOTSUP) return NO;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    task.arguments = @[ from, to ];
    task.standardInput = task.standardOutput = task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:NULL]) return NO;
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

// Its sandbox reads only apps under /Applications, hence the clone.
static NSString *applicationsCopyIn(NSString *copyFolder, NSString *pristine) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *clone = [copyFolder stringByAppendingPathComponent:@"Dia.app"];
    struct stat original;
    if (stat([pristine stringByAppendingPathComponent:@"Contents/MacOS/Dia"].fileSystemRepresentation, &original) != 0) return nil;
    if (![files createDirectoryAtPath:copyFolder withIntermediateDirectories:YES attributes:nil error:nil]) return nil;

    int lock = open([copyFolder stringByAppendingPathComponent:@".lock"].fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (lock < 0) return nil;
    while (flock(lock, LOCK_EX) != 0) {
        if (errno != EINTR) return close(lock), nil;
    }

    // Sweep orphaned temp staging bundles from previously killed copies while holding LOCK_EX.
    for (NSString *entry in [files contentsOfDirectoryAtPath:copyFolder error:nil])
        if ([entry hasPrefix:@"Dia.app."]) [files removeItemAtPath:[copyFolder stringByAppendingPathComponent:entry] error:nil];

    NSString *result = clone;
    if (!copyMatches(pristine, clone, &original)) {
        NSString *fresh = [clone stringByAppendingFormat:@".%d", getpid()];
        [files removeItemAtPath:fresh error:nil];
        BOOL cloned = cloneBundle(pristine, fresh);
        if (cloned) stripQuarantine(fresh);
        const char *src = fresh.fileSystemRepresentation, *dst = clone.fileSystemRepresentation;
        BOOL placed = NO;
        if (cloned) {
            struct stat dstInfo;
            if (lstat(dst, &dstInfo) == 0) {
                if (S_ISDIR(dstInfo.st_mode)) {
                    placed = renamex_np(src, dst, RENAME_SWAP) == 0
                        || (errno == ENOTSUP && [files removeItemAtPath:clone error:nil] && rename(src, dst) == 0);
                } else {
                    placed = unlink(dst) == 0 && rename(src, dst) == 0;
                }
            } else {
                placed = rename(src, dst) == 0;
            }
        }
        [files removeItemAtPath:fresh error:nil];
        if (!placed) result = nil;
    }
    if (result) stripQuarantine(result);
    close(lock);
    return result;
}

static NSString *applicationsCopy(NSString *pristine) { return applicationsCopyIn(DPCopyFolder, pristine); }

pid_t DPStartHelperThroughOriginal(NSString *home, NSString *helperPath, BOOL checksBrowser, int argc, const char *argv[]) {
    NSString *launches = [home stringByAppendingPathComponent:@"passwords-launch"];
    NSString *folder = [launches stringByAppendingPathComponent:@(getpid()).stringValue], *problem = nil;
    NSString *socket = socketPath(folder, &problem);
    NSString *pristine = [home stringByAppendingPathComponent:@"pristine/Dia.app"];
    NSString *app = checksBrowser ? applicationsCopy(pristine) : pristine;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @0700 } error:nil];
    chmod(launches.fileSystemRepresentation, 0700);
    NSDate *start = NSDate.date;
    int listener = socket ? listenAt(socket) : -1;
    if (listener < 0) logLine(home, problem ?: [NSString stringWithFormat:@"couldn't listen at %@", socket]);
    pid_t dia = listener >= 0 && app ? launchOriginal(app, folder, socket) : 0, peer = 0, helper = 0;
    int client = dia ? acceptSubprocess(listener, &dia, &peer) : -1;
    if (listener >= 0) close(listener), unlink(socket.fileSystemRepresentation);
    if (client >= 0 && handOver(client, helperPath, argc, argv) && becameHelper(client, peer, helperPath)) helper = peer;
    if (client >= 0) close(client);
    if (!helper && peer > 0) kill(peer, SIGKILL);
    if (helper && checksBrowser) usleep(kBrowserCheck);
    if (dia) {
        kill(dia, SIGKILL);
        while (waitpid(dia, NULL, 0) < 0 && errno == EINTR) {}
    }
    if (dia) DPForgetApp(app);
    [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
    logLine(home, [NSString stringWithFormat:helper ? @"the original Dia started %@ in %.2f s" : @"the original Dia didn't start %@ (%.2f s)",
                                             helperPath.lastPathComponent, -start.timeIntervalSinceNow]);
    return helper;
}

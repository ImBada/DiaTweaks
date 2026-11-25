#import "StdPatch/StdPatch.h"
#include <libproc.h>

extern DPPatch DPICloudPasswords;

static NSDictionary *DPHostAt(NSString *path) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] ? host : nil;
}

static NSString *DPAppleHelperIn(NSArray<NSString *> *manifests) {
    for (NSString *manifest in manifests) {
        NSString *path = DPHostAt(manifest)[@"path"];
        if ([path isKindOfClass:NSString.class] && [NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

#ifndef DP_APPLE_HOST_MANIFESTS
static NSArray<NSString *> *DPAppleHostManifests(void) {
    return @[
        @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json",
        @"/System/Library/Templates/Data/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json",
        @"/System/Cryptexes/App/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json",
    ];
}
#endif

static NSString *DPAppleHelperPath(void) { return DPAppleHelperIn(DPAppleHostManifests()); }

static NSError *gWriteError;
static NSString *gWritePath;

static void DPRemoveHost(NSString *name, NSString *relay) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *file = [name stringByAppendingString:@".json"];
    NSString *kept = DPAppSupport([NSString stringWithFormat:@"DiaPatches/%@", file]);
    for (NSString *dir in DPHostFolders()) {
        NSString *path = [dir stringByAppendingPathComponent:file];
        if (![DPHostAt(path)[@"path"] isEqual:relay]) continue;
        [files removeItemAtPath:path error:nil];
        if ([files fileExistsAtPath:kept]) [files moveItemAtPath:kept toPath:path error:nil];
    }
    if ([files fileExistsAtPath:kept]) {
        NSString *active = [DPHostFolder(NO, nil) stringByAppendingPathComponent:file];
        if (![files fileExistsAtPath:active]) [files moveItemAtPath:kept toPath:active error:nil];
    }
}

static NSError *DPRegisterHost(NSString *name, NSString *description, NSArray<NSString *> *origins, BOOL on, NSString *hostFolder, NSString **failedPath) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *file = [name stringByAppendingString:@".json"], *relay = DPAppSupport(@"DiaPatches/bin/diapatch");
    if (!on) {
        DPRemoveHost(name, relay);
        return nil;
    }
    NSString *path = [hostFolder stringByAppendingPathComponent:file];
    NSString *kept = DPAppSupport([NSString stringWithFormat:@"DiaPatches/%@", file]);
    NSDictionary *host = DPHostAt(path);
    NSError *error;
    NSString *current = [host[@"path"] isKindOfClass:NSString.class] ? host[@"path"] : nil;
    if ([files fileExistsAtPath:path] && ![current isEqual:relay]) {
        NSString *apple = DPAppleHelperPath();
        BOOL replaceable = (apple && [current isEqual:apple]) || [current.lastPathComponent isEqual:@"OpenPasswordsHelper"];
        if (!replaceable) return nil;
        [files removeItemAtPath:kept error:nil];
        if (![files moveItemAtPath:path toPath:kept error:&error]) {
            if (failedPath) *failedPath = path;
            return error;
        }
    }
    NSDictionary *manifest = @{ @"name" : name, @"description" : description, @"path" : relay, @"type" : @"stdio", @"allowed_origins" : origins };
    BOOL written = [[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!written) {
        if (failedPath) *failedPath = path;
        return error;
    }
    for (NSString *dir in DPHostFolders()) {
        if ([dir isEqualToString:hostFolder]) continue;
        NSString *stale = [dir stringByAppendingPathComponent:file];
        if ([DPHostAt(stale)[@"path"] isEqual:relay]) [files removeItemAtPath:stale error:nil];
    }
    return nil;
}

static void DPRegisterHosts(BOOL on) {
    gWriteError = nil;
    gWritePath = nil;
    NSError *folderError = nil;
    NSString *hostFolder = on ? DPHostFolder(YES, &folderError) : nil;
    if (on && !hostFolder) {
        gWriteError = folderError;
        gWritePath = [DPHostFolders().lastObject stringByAppendingPathComponent:@"com.apple.passwordmanager.json"];
        return;
    }
    NSArray<NSArray *> *hosts = @[
        @[ @"com.apple.passwordmanager", @"DiaTweaks relay to iCloud Passwords",
           @[ @"chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/", @"chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" ] ],
        @[ @"io.github.fanckush.betterpasswords.bridge", @"DiaTweaks relay for Better Passwords to iCloud Passwords",
           @[ @"chrome-extension://ocongmkplhijgajnipnhhggfcjfdilgj/" ] ],
        @[ @"com.openpasswords.icloud", @"DiaTweaks relay for Open Passwords to iCloud Passwords",
           @[ @"chrome-extension://iaojbcjndjmmblmoemilknlnjijokkfg/", @"chrome-extension://abpahgnajbkclfhpodhjhlmgfjhpibaa/" ] ],
    ];
    for (NSArray *host in hosts) {
        NSString *failedPath = nil;
        NSError *error = DPRegisterHost(host[0], host[1], host[2], on, hostFolder, &failedPath);
        if (error && !gWriteError) gWriteError = error, gWritePath = failedPath;
    }
}

static NSString *DPICloudPasswordsProblem(DPPatch *patch) {
    if (!DPAppleHelperPath())
        return @"This Mac doesn’t have Apple’s iCloud Passwords helper, which comes with macOS 14 and later.";
    NSString *manifest = [DPHostFolder(NO, nil) stringByAppendingPathComponent:@"com.apple.passwordmanager.json"];
    if (gWriteError) return DPWriteProblem(gWritePath ?: manifest, gWriteError);
    return DPRelayProblem() ?: DPHostProblem(manifest, @"com.apple.passwordmanager");
}

// Only Dia itself, never a helper that sits beside it.
static BOOL DPIsStagedDia(const char *path, const char *pristine) {
    static const char root[] = "/Applications/.DiaTweaks/", executable[] = "/Contents/MacOS/Dia";
    size_t length = strlen(path), prefix = sizeof root - 1, tail = sizeof executable - 1;
    return !strcmp(path, pristine) || (!strncmp(path, root, prefix) && length > prefix + tail && !strcmp(path + length - tail, executable));
}

static BOOL DPAllGone(pid_t *pids, int count, int polls) {
    for (int poll = 0; poll < polls; poll++) {
        BOOL gone = YES;
        for (int i = 0; i < count; i++) {
            if (pids[i] && kill(pids[i], 0) == 0) gone = NO;
            else pids[i] = 0;
        }
        if (gone) return YES;
        usleep(10000);
    }
    return NO;
}

// A lingering pristine Dia from a prior hand-off blocks Dia's launch check; stop it off the main thread so launch never stalls.
static void DPStopOriginalDia(void) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    char real[PATH_MAX];
    const char *given = DPAppSupport(@"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia").fileSystemRepresentation, *pristine = realpath(given, real) ?: given;
    int listed = proc_listallpids(NULL, 0);
    int capacity = (listed > 0 ? listed : 0) + 64;
    pid_t *pids = calloc((size_t)capacity, sizeof *pids);
    if (!pids) return;
    int count = proc_listallpids(pids, capacity * (int)sizeof *pids), found = 0;
    if (count > capacity) count = capacity;
    for (int i = 0; i < count; i++)
        if (pids[i] != getpid() && proc_pidpath(pids[i], path, sizeof path) > 0 && DPIsStagedDia(path, pristine)) pids[found++] = pids[i];
    for (int i = 0; i < found; i++) kill(pids[i], SIGTERM);
    if (found && !DPAllGone(pids, found, 25)) {
        for (int i = 0; i < found; i++)
            if (pids[i]) kill(pids[i], SIGKILL);
        DPAllGone(pids, found, 25);
    }
    free(pids);
}

static void DPInstallICloudPasswords(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ DPStopOriginalDia(); });
    DPRegisterHosts(DPICloudPasswords.on);
}

static void DPApplyICloudPasswords(DPPatch *patch) { DPRegisterHosts(patch->on); }

DP_PATCH(DPICloudPasswords) {
    .key = @"icloudPasswords",
    .order = 101,
    .title = @"Allow iCloud Passwords",
    .detail = @"AutoFill passwords from Apple Passwords with the iCloud Passwords, Better Passwords or Open Passwords extension. A patched Dia can’t start Apple’s helper, so each time one connects, the original Dia that DiaTweaks keeps opens briefly, without windows, to start it.",
    .symbol = @"apple.passwords key.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .group = @"passwordManagers",
    .install = DPInstallICloudPasswords,
    .apply = DPApplyICloudPasswords,
    .ready = DPICloudPasswordsProblem,
};

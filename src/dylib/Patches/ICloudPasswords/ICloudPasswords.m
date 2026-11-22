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
        if (![files fileExistsAtPath:path] || ![DPHostAt(path)[@"path"] isEqual:relay]) continue;
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
    if ([files fileExistsAtPath:path] && ![host[@"path"] isEqual:relay]) {
        NSString *apple = DPAppleHelperPath();
        BOOL replaceable = (apple && [host[@"path"] isEqual:apple]) || [[host[@"path"] lastPathComponent] isEqual:@"OpenPasswordsHelper"];
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
        if ([files fileExistsAtPath:stale] && [DPHostAt(stale)[@"path"] isEqual:relay]) [files removeItemAtPath:stale error:nil];
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
    NSString *p1 = nil, *p2 = nil, *p3 = nil;
    NSError *apple = DPRegisterHost(@"com.apple.passwordmanager", @"DiaTweaks relay to iCloud Passwords",
                                    @[ @"chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/", @"chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" ], on, hostFolder, &p1);
    NSError *betterPasswords = DPRegisterHost(@"io.github.fanckush.betterpasswords.bridge", @"DiaTweaks relay for Better Passwords to iCloud Passwords",
                                              @[ @"chrome-extension://ocongmkplhijgajnipnhhggfcjfdilgj/" ], on, hostFolder, &p2);
    NSError *openPasswords = DPRegisterHost(@"com.openpasswords.icloud", @"DiaTweaks relay for Open Passwords to iCloud Passwords",
                                            @[ @"chrome-extension://iaojbcjndjmmblmoemilknlnjijokkfg/", @"chrome-extension://abpahgnajbkclfhpodhjhlmgfjhpibaa/" ], on, hostFolder, &p3);
    if (apple) gWriteError = apple, gWritePath = p1;
    else if (betterPasswords) gWriteError = betterPasswords, gWritePath = p2;
    else if (openPasswords) gWriteError = openPasswords, gWritePath = p3;
}

static NSString *DPICloudPasswordsProblem(DPPatch *patch) {
    if (!DPAppleHelperPath())
        return @"This Mac doesn’t have Apple’s iCloud Passwords helper, which comes with macOS 14 and later.";
    NSString *manifest = [DPHostFolder(NO, nil) stringByAppendingPathComponent:@"com.apple.passwordmanager.json"];
    if (gWriteError) return DPWriteProblem(gWritePath ?: manifest, gWriteError);
    return DPRelayProblem() ?: DPHostProblem(manifest, @"com.apple.passwordmanager");
}

// A lingering pristine Dia from a prior hand-off blocks Dia's launch check.
static void DPStopOriginalDia(void) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    NSString *pristine = DPAppSupport(@"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia").stringByResolvingSymlinksInPath;
    int listed = proc_listallpids(NULL, 0);
    int capacity = (listed > 0 ? listed : 0) + 64;
    pid_t *pids = calloc((size_t)capacity, sizeof *pids);
    if (!pids) return;
    int count = proc_listallpids(pids, capacity * (int)sizeof *pids);
    if (count > capacity) count = capacity;
    for (int i = 0; i < count; i++) {
        if (proc_pidpath(pids[i], path, sizeof path) <= 0 || (strcmp(path, pristine.fileSystemRepresentation) && ![@(path) hasPrefix:@"/Applications/.DiaTweaks/"])) continue;
        kill(pids[i], SIGKILL);
        for (int tries = 0; tries < 50 && kill(pids[i], 0) == 0; tries++) usleep(20000);
    }
    free(pids);
}

static void DPInstallICloudPasswords(void) {
    DPStopOriginalDia();
    DPRegisterHosts(DPICloudPasswords.on);
}

static void DPApplyICloudPasswords(DPPatch *patch) { DPRegisterHosts(patch->on); }

DP_PATCH(DPICloudPasswords) {
    .key = @"icloudPasswords",
    .order = 101,
    .title = @"Allow iCloud Passwords",
    .detail = @"AutoFill passwords from Apple Passwords with the iCloud Passwords, Better Passwords or Open Passwords extension. A patched Dia can’t start Apple’s helper, so each time one connects, the original Dia that DiaTweaks keeps opens briefly, without windows, to start it. Experimental.",
    .symbol = @"apple.passwords key.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .install = DPInstallICloudPasswords,
    .apply = DPApplyICloudPasswords,
    .ready = DPICloudPasswordsProblem,
};

#import "StdPatch/StdPatch.h"
#include <sys/stat.h>

extern DPPatch DPProtonPass;

static NSString *const kHost = @"me.proton.pass.nm";
static NSString *const kHostFile = @"me.proton.pass.nm.json";
static NSString *const kDescription = @"DiaTweaks link to the Proton Pass app";

static NSDictionary *DPHostAt(NSString *path) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] ? host : nil;
}

static BOOL DPIsExecutableRegularFile(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.length) return NO;
    struct stat st;
    const char *fs = path.fileSystemRepresentation;
    return stat(fs, &st) == 0 && S_ISREG(st.st_mode) && access(fs, X_OK) == 0;
}

static BOOL DPOwnsHostAt(NSString *path) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0 || S_ISDIR(st.st_mode)) return NO;
    NSDictionary *host = DPHostAt(path);
    return [host[@"name"] isEqual:kHost] && [host[@"description"] isEqual:kDescription];
}

static NSString *DPExecutableHostInApp(NSString *app) {
    if (!app.length) return nil;
    NSString *host = [app stringByAppendingPathComponent:@"Contents/Resources/assets/proton_pass_nm_host"];
    return DPIsExecutableRegularFile(host) ? host : nil;
}

#ifndef DP_PROTON_PASS_HOST_PATH
static NSString *DPHostPath(void) {
    NSString *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"me.proton.pass.electron"].path;
    NSString *host = app && ![app containsString:@"/.Trash/"] ? DPExecutableHostInApp(app) : nil;
    if (host) return host;
    for (NSString *candidate in @[ @"/Applications/Proton Pass.app", [@"~/Applications/Proton Pass.app" stringByExpandingTildeInPath] ])
        if ((host = DPExecutableHostInApp(candidate))) return host;
    return nil;
}
#endif

static NSError *gWriteError;
static NSString *gWritePath;

static void DPRemoveOwnHost(NSString *keepDir) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *dir in DPHostFolders()) {
        if (keepDir && [dir isEqualToString:keepDir]) continue;
        NSString *path = [dir stringByAppendingPathComponent:kHostFile];
        if (DPOwnsHostAt(path)) [files removeItemAtPath:path error:nil];
    }
}

static void DPRegisterHost(BOOL on) {
    gWriteError = nil;
    gWritePath = nil;
    NSString *host = on ? DPHostPath() : nil;
    if (!host) return DPRemoveOwnHost(nil);
    NSError *error = nil;
    NSString *hostFolder = DPHostFolder(YES, &error);
    if (!hostFolder) {
        gWriteError = error;
        gWritePath = [DPHostFolders().lastObject stringByAppendingPathComponent:kHostFile];
        return;
    }
    NSString *path = [hostFolder stringByAppendingPathComponent:kHostFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:path] && !DPOwnsHostAt(path)) {
        DPRemoveOwnHost(hostFolder);
        return;
    }
    NSDictionary *manifest = @{
        @"name" : kHost,
        @"description" : kDescription,
        @"path" : host,
        @"type" : @"stdio",
        @"allowed_origins" : @[
            @"chrome-extension://ghmbeldphafepmbegfdlkpapadhbakde/",
            @"chrome-extension://hlaiofkbmjenhgeinjlmkafaipackfjh/",
            @"chrome-extension://gcllgfdnfnllodcaambdaknbipemelie/",
        ],
    };
    if (![[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path options:NSDataWritingAtomic error:&error]) {
        gWriteError = error;
        gWritePath = path;
        return;
    }
    DPRemoveOwnHost(hostFolder);
}

static NSString *DPProtonPassProblem(DPPatch *patch) {
    NSString *path = [DPHostFolder(NO, nil) stringByAppendingPathComponent:kHostFile];
    if (!DPHostPath()) return DPTesting ? nil : @"The Proton Pass desktop app isn’t installed. Install it, then try again.";
    if (gWriteError) return DPWriteProblem(gWritePath ?: path, gWriteError);
    NSDictionary *host = DPHostAt(path);
    if (![host[@"name"] isEqual:kHost]) return [NSString stringWithFormat:@"%@ isn’t a valid host file.", path];
    if (!DPIsExecutableRegularFile(host[@"path"]))
        return [NSString stringWithFormat:@"Proton Pass’s %@ points to %@, which isn’t there. Quit and reopen Proton Pass, then try again.", path, host[@"path"]];
    return nil;
}

static void DPInstallProtonPass(void) { DPRegisterHost(DPProtonPass.on); }

static void DPApplyProtonPass(DPPatch *patch) { DPRegisterHost(patch->on); }

DP_PATCH(DPProtonPass) {
    .key = @"protonPass",
    .order = 210,
    .title = @"Allow Proton Pass",
    .detail = @"Unlock the Proton Pass extension with the Proton Pass app, such as with Touch ID. Proton Pass only sets this up for browsers it knows, so this adds the file Dia reads when it’s missing, and takes away only that file. Experimental.",
    .symbol = @"key.shield.fill key.horizontal.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .group = @"passwordManagers",
    .install = DPInstallProtonPass,
    .apply = DPApplyProtonPass,
    .ready = DPProtonPassProblem,
};

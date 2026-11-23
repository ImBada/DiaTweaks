#import "StdPatch/StdPatch.h"

extern DPPatch DPBitwarden;

static NSString *const kHost = @"com.8bit.bitwarden";
static NSString *const kHostFile = @"com.8bit.bitwarden.json";
static NSString *const kExtension = @"chrome-extension://nngceckbapebfimnlniiiahkandclblb/";
static NSString *const kDescription = @"DiaTweaks link to the Bitwarden app";

static NSDictionary *DPHostAt(NSString *path) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] ? host : nil;
}

#ifndef DP_BITWARDEN_PROXY_PATH
static NSString *DPProxyPath(void) {
    NSString *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.bitwarden.desktop"].path;
    NSString *proxy = [app stringByAppendingPathComponent:@"Contents/MacOS/desktop_proxy"];
    return app && [NSFileManager.defaultManager isExecutableFileAtPath:proxy] ? proxy : nil;
}
#endif

static NSError *gWriteError;
static NSString *gWritePath;

static void DPRemoveOwnHostFiles(NSString *keptFolder) {
    for (NSString *dir in DPHostFolders()) {
        if ([dir isEqual:keptFolder]) continue;
        NSString *path = [dir stringByAppendingPathComponent:kHostFile];
        if ([DPHostAt(path)[@"description"] isEqual:kDescription]) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}

static void DPRegisterHost(BOOL on) {
    gWriteError = nil;
    gWritePath = nil;
    if (!on) return DPRemoveOwnHostFiles(nil);
    NSString *proxy = DPProxyPath();
    if (!proxy) return;
    NSError *error = nil;
    NSString *hostFolder = DPHostFolder(YES, &error);
    if (!hostFolder) {
        gWriteError = error;
        gWritePath = [DPHostFolders().lastObject stringByAppendingPathComponent:kHostFile];
        return;
    }
    NSString *path = [hostFolder stringByAppendingPathComponent:kHostFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:path] && ![DPHostAt(path)[@"description"] isEqual:kDescription]) return;
    NSDictionary *manifest = @{ @"name" : kHost, @"description" : kDescription, @"path" : proxy, @"type" : @"stdio", @"allowed_origins" : @[ kExtension ] };
    if (![[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path options:NSDataWritingAtomic error:&error]) {
        gWriteError = error;
        gWritePath = path;
        return;
    }
    DPRemoveOwnHostFiles(hostFolder);
}

static NSString *DPBitwardenProblem(DPPatch *patch) {
    NSString *path = [DPHostFolder(NO, nil) stringByAppendingPathComponent:kHostFile];
    if (!DPProxyPath()) return DPTesting ? nil : @"The Bitwarden desktop app isn’t installed. Install it, then try again.";
    if (gWriteError) return DPWriteProblem(gWritePath ?: path, gWriteError);
    NSDictionary *host = DPHostAt(path);
    if (![host[@"name"] isEqual:kHost]) return [NSString stringWithFormat:@"%@ isn’t a valid host file.", path];
    if (![host[@"path"] isKindOfClass:NSString.class] || ![NSFileManager.defaultManager isExecutableFileAtPath:host[@"path"]])
        return [NSString stringWithFormat:@"Bitwarden’s %@ points to %@, which isn’t there. Quit and reopen Bitwarden, then try again.", path, host[@"path"]];
    return nil;
}

static void DPInstallBitwarden(void) { DPRegisterHost(DPBitwarden.on); }

static void DPApplyBitwarden(DPPatch *patch) { DPRegisterHost(patch->on); }

DP_PATCH(DPBitwarden) {
    .key = @"bitwarden",
    .order = 103,
    .title = @"Allow Bitwarden",
    .detail = @"Unlock the Bitwarden extension with the Bitwarden app, such as with Touch ID. Bitwarden only sets this up for browsers it knows, so this adds the file Dia reads when it’s missing, and takes away only that file. Experimental.",
    .symbol = @"shield.lefthalf.filled",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .group = @"passwordManagers",
    .install = DPInstallBitwarden,
    .apply = DPApplyBitwarden,
    .ready = DPBitwardenProblem,
};

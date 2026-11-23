#import "StdPatch/StdPatch.h"
#include <limits.h>
#include <sys/stat.h>

// ArcCore overrides DIR_USER_NATIVE_MESSAGING to Chrome's folder only when it exists or can be created and resolves;
// otherwise Chromium's PathProvider falls back to Dia/User Data/NativeMessagingHosts.
static BOOL DPDirectoryResolvable(NSString *dir) {
    struct stat info;
    char resolved[PATH_MAX];
    return stat(dir.fileSystemRepresentation, &info) == 0 && S_ISDIR(info.st_mode)
        && realpath(dir.fileSystemRepresentation, resolved) != NULL;
}

NSArray<NSString *> *DPHostFolders(void) {
    return @[ DPAppSupport(@"Google/Chrome/NativeMessagingHosts"), DPAppSupport(@"Dia/User Data/NativeMessagingHosts") ];
}

NSString *DPHostFolder(BOOL create, NSError **error) {
    NSArray<NSString *> *folders = DPHostFolders();
    NSString *chrome = folders[0], *dia = folders[1];
    if (DPDirectoryResolvable(chrome)) return chrome;
    if (!create) return dia;
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:chrome withIntermediateDirectories:YES attributes:nil error:nil];
    if (DPDirectoryResolvable(chrome)) return chrome;
    return [files createDirectoryAtPath:dia withIntermediateDirectories:YES attributes:nil error:error] ? dia : nil;
}

NSString *DPSystemHostFolder(void) {
    NSString *chrome = @"/Library/Google/Chrome/NativeMessagingHosts";
    return DPDirectoryResolvable(chrome) ? chrome : @"/Library/Application Support/Chromium/NativeMessagingHosts";
}

NSString *DPRelayProblem(void) {
    for (NSString *path in @[ @"DiaPatches/bin/diapatch", @"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia" ])
        if (![NSFileManager.defaultManager isExecutableFileAtPath:DPAppSupport(path)])
            return [NSString stringWithFormat:@"%@ is missing. Install DiaTweaks again to put it back.", DPAppSupport(path)];
    return nil;
}

static NSString *DPFolderToRepair(NSString *folder) {
    NSString *support = DPAppSupport(@""), *repair = nil;
    for (NSString *dir = folder; [dir hasPrefix:support]; dir = dir.stringByDeletingLastPathComponent) {
        if (access(dir.fileSystemRepresentation, W_OK | X_OK) == 0) return repair && [NSFileManager.defaultManager fileExistsAtPath:repair] ? repair : nil;
        repair = dir;
    }
    return nil;
}

NSString *DPWriteProblem(NSString *path, NSError *error) {
    path = error.userInfo[NSFilePathErrorKey] ?: path;
    NSString *problem = [NSString stringWithFormat:@"Couldn’t write %@: %@", path, error.localizedDescription];
    NSString *folder = error.code == NSFileWriteNoPermissionError ? DPFolderToRepair(path.stringByDeletingLastPathComponent) : nil;
    if (!folder) return problem;
    if ([folder hasPrefix:NSHomeDirectory()]) folder = [@"$HOME" stringByAppendingString:[folder substringFromIndex:NSHomeDirectory().length]];
    return [problem stringByAppendingFormat:@" To fix it, run sudo chown -R \"$(whoami)\" \"%@\" && chmod -R u+rwX \"%@\" in Terminal, then turn this on again.", folder, folder];
}

NSString *DPHostProblem(NSString *manifest, NSString *name) {
    NSData *data = [NSData dataWithContentsOfFile:manifest];
    if (!data) return [NSString stringWithFormat:@"%@ couldn’t be written.", manifest];
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![host isKindOfClass:NSDictionary.class] || ![host[@"name"] isEqual:name]) return [NSString stringWithFormat:@"%@ isn’t a valid host file.", manifest];
    if (![host[@"path"] isEqual:DPAppSupport(@"DiaPatches/bin/diapatch")])
        return [NSString stringWithFormat:@"Another app has replaced %@, so its extension goes to %@ instead.", manifest, host[@"path"]];
    return nil;
}

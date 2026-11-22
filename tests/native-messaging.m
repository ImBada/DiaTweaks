#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#include <sys/stat.h>

static NSString *gAppSupportRoot;
NSString *DPAppSupport(NSString *path) { return [gAppSupportRoot stringByAppendingPathComponent:path]; }

BOOL DPTesting;
static NSMutableArray<NSString *> *gLoadedExtensions, *gDroppedExtensions;
void DPLoadExtension(NSString *folder) { [gLoadedExtensions addObject:folder]; }
void DPDropExtension(NSString *folder) { [gDroppedExtensions addObject:folder]; }
BOOL DPSavedOn(DPPatch *patch) { return NO; }
void DPHandOffAndQuit(NSArray<NSString *> *args) {}

extern DPPatch DPPasskeys;
extern DPPatch DPOnePassword;

static NSArray<NSString *> *gAppleManifests;
#define DP_APPLE_HOST_MANIFESTS
static NSArray<NSString *> *DPAppleHostManifests(void) { return gAppleManifests; }
#import "Patches/ICloudPasswords/ICloudPasswords.m"

static NSString *gBitwardenProxy;
#define DP_BITWARDEN_PROXY_PATH
static NSString *DPProxyPath(void) { return gBitwardenProxy; }
#define DPHostAt DPBitwardenHostAt
#define gWriteError gBitwardenWriteError
#define gWritePath gBitwardenWritePath
#define DPRegisterHost DPBitwardenRegisterHost
#import "Patches/Bitwarden/Bitwarden.m"
#undef DPHostAt
#undef gWriteError
#undef gWritePath
#undef DPRegisterHost

static NSString *gProtonPassHost;
#define DP_PROTON_PASS_HOST_PATH
static NSString *DPHostPath(void) { return gProtonPassHost; }
#define kHost kProtonPassHost
#define kHostFile kProtonPassHostFile
#define kDescription kProtonPassDescription
#define DPHostAt DPProtonPassHostAt
#define gWriteError gProtonPassWriteError
#define gWritePath gProtonPassWritePath
#define DPRemoveOwnHost DPProtonPassRemoveOwnHost
#define DPRegisterHost DPProtonPassRegisterHost
#import "Patches/ProtonPass/ProtonPass.m"
#undef kHost
#undef kHostFile
#undef kDescription
#undef DPHostAt
#undef gWriteError
#undef gWritePath
#undef DPRemoveOwnHost
#undef DPRegisterHost

pid_t DPStartHelperThroughOriginal(NSString *home, NSString *helper, BOOL checksBrowser, int argc, const char *argv[]) { return 0; }
BOOL DPRunsPatchedDia(pid_t pid, NSString *app) { return NO; }
#import "../diapatch/PasswordsHost.m"

static NSString *makeTempDir(void) {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:@"diatweaks-nm-XXXXXX"];
    char *tmpl = strdup(base.fileSystemRepresentation);
    char *created = mkdtemp(tmpl);
    NSCAssert(created != NULL, @"mkdtemp failed");
    NSString *dir = [NSFileManager.defaultManager stringWithFileSystemRepresentation:created length:strlen(created)];
    free(tmpl);
    return dir;
}

static void unlockAndRemove(NSString *root) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:root];
    NSDirectoryEnumerator<NSString *> *it = [fm enumeratorAtPath:root];
    for (NSString *rel in it) [paths addObject:[root stringByAppendingPathComponent:rel]];
    for (NSString *path in paths) {
        chflags(path.fileSystemRepresentation, 0);
        chmod(path.fileSystemRepresentation, 0755);
    }
    [fm removeItemAtPath:root error:nil];
}

static void writeExecutable(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [@"#!/bin/sh\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(path.fileSystemRepresentation, 0755);
}

static void writeJSON(NSString *path, NSDictionary *object) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    NSCAssert([data writeToFile:path atomically:YES], @"writeJSON failed for %@", path);
}

static NSDictionary *readJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

static void installFakeRelay(void) {
    writeExecutable(DPAppSupport(@"DiaPatches/bin/diapatch"));
    writeExecutable(DPAppSupport(@"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia"));
}

static void testHostFolderFallback(void) {
    // 1. Chrome absent and creatable (macOS 14-26 without Chrome): creates and uses Chrome folder.
    gAppSupportRoot = makeTempDir();
    NSError *err = nil;
    NSString *chrome = DPAppSupport(@"Google/Chrome/NativeMessagingHosts");
    NSString *dia = DPAppSupport(@"Dia/User Data/NativeMessagingHosts");
    NSString *got = DPHostFolder(YES, &err);
    NSCAssert([got isEqualToString:chrome] && !err, @"creatable chrome dir should be used, got %@ err %@", got, err);
    NSCAssert([[DPHostFolder(NO, nil) stringByStandardizingPath] isEqualToString:chrome.stringByStandardizingPath], @"read-only lookup sees chrome");
    unlockAndRemove(gAppSupportRoot);

    // 2. Chrome absent and creating Google/Chrome returns EPERM (macOS 27.3 App-Data TCC via uchg).
    gAppSupportRoot = makeTempDir();
    chrome = DPAppSupport(@"Google/Chrome/NativeMessagingHosts");
    dia = DPAppSupport(@"Dia/User Data/NativeMessagingHosts");
    NSString *google = DPAppSupport(@"Google");
    [NSFileManager.defaultManager createDirectoryAtPath:google withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"chflags uchg failed");
    err = nil;
    got = DPHostFolder(YES, &err);
    NSCAssert([got isEqualToString:dia] && !err, @"EPERM on Google/Chrome must fall back to Dia/User Data, got %@ err %@", got, err);
    NSCAssert([DPHostFolder(NO, nil) isEqualToString:dia], @"read-only lookup must match fallback Dia/User Data");
    unlockAndRemove(gAppSupportRoot);

    // 3. Google/Chrome exists and is read-only (0555), NativeMessagingHosts missing -> falls back to Dia/User Data.
    gAppSupportRoot = makeTempDir();
    chrome = DPAppSupport(@"Google/Chrome/NativeMessagingHosts");
    dia = DPAppSupport(@"Dia/User Data/NativeMessagingHosts");
    NSString *chromeParent = DPAppSupport(@"Google/Chrome");
    [NSFileManager.defaultManager createDirectoryAtPath:chromeParent withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(chromeParent.fileSystemRepresentation, 0555);
    err = nil;
    got = DPHostFolder(YES, &err);
    NSCAssert([got isEqualToString:dia] && !err, @"missing NativeMessagingHosts under read-only Chrome must fall back, got %@", got);
    unlockAndRemove(gAppSupportRoot);

    // 4. Google/Chrome exists and is untraversable (0000) -> stat fails, falls back to Dia/User Data.
    gAppSupportRoot = makeTempDir();
    dia = DPAppSupport(@"Dia/User Data/NativeMessagingHosts");
    chromeParent = DPAppSupport(@"Google/Chrome");
    [NSFileManager.defaultManager createDirectoryAtPath:chromeParent withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(chromeParent.fileSystemRepresentation, 0000);
    err = nil;
    got = DPHostFolder(YES, &err);
    NSCAssert([got isEqualToString:dia] && !err, @"untraversable Chrome dir must fall back, got %@", got);
    unlockAndRemove(gAppSupportRoot);

    // 5. #384: Google/Chrome/NativeMessagingHosts ALREADY exists and is read-only (0555) -> stays on chrome so write surfaces repair command.
    gAppSupportRoot = makeTempDir();
    chrome = DPAppSupport(@"Google/Chrome/NativeMessagingHosts");
    [NSFileManager.defaultManager createDirectoryAtPath:chrome withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(chrome.fileSystemRepresentation, 0555);
    err = nil;
    got = DPHostFolder(YES, &err);
    NSCAssert([got isEqualToString:chrome], @"existing read-only Chrome host dir must not silently fall back, got %@", got);
    NSString *probe = [chrome stringByAppendingPathComponent:@"probe.json"];
    NSError *writeErr = nil;
    NSCAssert(![[@"x" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:probe options:NSDataWritingAtomic error:&writeErr], @"write should fail");
    NSString *msg = DPWriteProblem(probe, writeErr);
    NSCAssert([msg containsString:@"sudo chown -R \"$(whoami)\""], @"#384 repair command expected, got: %@", msg);
    unlockAndRemove(gAppSupportRoot);

    // 6. Corrupted file at Google/Chrome/NativeMessagingHosts -> falls back to Dia/User Data.
    gAppSupportRoot = makeTempDir();
    chrome = DPAppSupport(@"Google/Chrome/NativeMessagingHosts");
    dia = DPAppSupport(@"Dia/User Data/NativeMessagingHosts");
    [NSFileManager.defaultManager createDirectoryAtPath:chrome.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [@"not a dir" writeToFile:chrome atomically:YES encoding:NSUTF8StringEncoding error:nil];
    err = nil;
    got = DPHostFolder(YES, &err);
    NSCAssert([got isEqualToString:dia] && !err, @"regular file at Chrome host dir must fall back, got %@", got);
    unlockAndRemove(gAppSupportRoot);

    // 7. Both Chrome and Dia unwritable -> returns nil with error.
    gAppSupportRoot = makeTempDir();
    google = DPAppSupport(@"Google");
    NSString *diaParent = DPAppSupport(@"Dia");
    [NSFileManager.defaultManager createDirectoryAtPath:google withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:diaParent withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google");
    NSCAssert(chflags(diaParent.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg dia");
    err = nil;
    got = DPHostFolder(YES, &err);
    NSCAssert(got == nil && err != nil, @"both unwritable must fail with error");
    unlockAndRemove(gAppSupportRoot);
}

static void testPasskeysChromelessAndTransition(void) {
    gAppSupportRoot = makeTempDir();
    installFakeRelay();
    gLoadedExtensions = [NSMutableArray array];
    gDroppedExtensions = [NSMutableArray array];

    NSString *google = DPAppSupport(@"Google");
    NSString *diaHost = DPAppSupport(@"Dia/User Data/NativeMessagingHosts/com.diapatches.passkeys.json");
    NSString *chromeHost = DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.diapatches.passkeys.json");
    [NSFileManager.defaultManager createDirectoryAtPath:google withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google");

    // Off-tweak invariant: install while off creates nothing.
    DPPasskeys.on = NO;
    DPPasskeys.install();
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaHost], @"off passkeys must not write manifest");
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:DPAppSupport(@"Dia/User Data")], @"off passkeys must not create Dia dir");

    // Enable passkeys while Google/Chrome fails with EPERM.
    DPPasskeys.on = YES;
    DPPasskeys.apply(&DPPasskeys);
    NSString *problem = DPPasskeys.ready(&DPPasskeys);
    NSCAssert(problem == nil, @"passkeys should succeed without Chrome, got: %@", problem);
    NSDictionary *manifest = readJSON(diaHost);
    NSCAssert([manifest[@"name"] isEqual:@"com.diapatches.passkeys"], @"manifest written to Dia/User Data");
    NSCAssert([manifest[@"path"] isEqual:DPAppSupport(@"DiaPatches/bin/diapatch")], @"manifest points to diapatch");

    // Later Chrome gets installed: re-applying migrates manifest to Chrome and removes stale Dia copy.
    NSCAssert(chflags(google.fileSystemRepresentation, 0) == 0, @"nouchg google");
    DPPasskeys.apply(&DPPasskeys);
    NSCAssert(DPPasskeys.ready(&DPPasskeys) == nil, @"passkeys valid after Chrome installed");
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:chromeHost], @"manifest now in Chrome folder");
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaHost], @"stale Dia manifest removed");

    // Turning off removes Chrome manifest and extension folder.
    DPPasskeys.on = NO;
    DPPasskeys.install();
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:chromeHost], @"off passkeys removes Chrome manifest");
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:DPAppSupport(@"DiaPatches/passkeys-extension")], @"off passkeys removes extension");

    // Turning off after Chrome-less enable also cleans up Dia manifest.
    [NSFileManager.defaultManager removeItemAtPath:DPAppSupport(@"Google/Chrome") error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google again");
    DPPasskeys.on = YES;
    DPPasskeys.apply(&DPPasskeys);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:diaHost], @"Dia manifest written");
    DPPasskeys.on = NO;
    DPPasskeys.install();
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaHost], @"off passkeys removes Dia manifest");

    // #384: existing read-only Chrome NativeMessagingHosts still reports sudo chown repair.
    NSCAssert(chflags(google.fileSystemRepresentation, 0) == 0, @"nouchg google");
    NSString *chromeDir = chromeHost.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:chromeDir withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(chromeDir.fileSystemRepresentation, 0555);
    DPPasskeys.on = YES;
    DPPasskeys.apply(&DPPasskeys);
    problem = DPPasskeys.ready(&DPPasskeys);
    NSCAssert(problem && [problem containsString:@"sudo chown -R \"$(whoami)\""], @"#384 passkeys repair expected, got: %@", problem);

    unlockAndRemove(gAppSupportRoot);
}

static void testICloudPasswordsTemplatesAndChromeless(void) {
    gAppSupportRoot = makeTempDir();
    installFakeRelay();

    NSString *sysRoot = makeTempDir();
    NSString *missingLib = [sysRoot stringByAppendingPathComponent:@"Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json"];
    NSString *templates = [sysRoot stringByAppendingPathComponent:@"System/Library/Templates/Data/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json"];
    NSString *cryptex = [sysRoot stringByAppendingPathComponent:@"System/Cryptexes/App/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json"];
    NSString *appleHelper = [sysRoot stringByAppendingPathComponent:@"helper/PasswordManagerBrowserExtensionHelper"];
    writeExecutable(appleHelper);
    writeJSON(templates, @{ @"name" : @"com.apple.passwordmanager", @"path" : appleHelper });
    gAppleManifests = @[ missingLib, templates, cryptex ];

    // EPERM on Google/Chrome + /Library/Google/Chrome manifest missing (Templates present).
    NSString *google = DPAppSupport(@"Google");
    [NSFileManager.defaultManager createDirectoryAtPath:google withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google");

    // Off-tweak invariant: turning off when never on creates nothing.
    DPICloudPasswords.on = NO;
    DPICloudPasswords.apply(&DPICloudPasswords);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:DPAppSupport(@"Dia/User Data")], @"off iCloud Passwords must not create Dia dir");

    // Pre-existing OpenPasswordsHelper manifest in Dia/User Data should be backed up and restored.
    NSString *diaDir = DPAppSupport(@"Dia/User Data/NativeMessagingHosts");
    NSString *openPath = [diaDir stringByAppendingPathComponent:@"com.openpasswords.icloud.json"];
    writeJSON(openPath, @{ @"name" : @"com.openpasswords.icloud", @"path" : @"/Applications/OpenPasswords.app/Contents/MacOS/OpenPasswordsHelper" });

    DPICloudPasswords.on = YES;
    DPICloudPasswords.apply(&DPICloudPasswords);
    NSString *problem = DPICloudPasswords.ready(&DPICloudPasswords);
    NSCAssert(problem == nil, @"iCloud Passwords should succeed via Templates + Dia fallback, got: %@", problem);

    NSString *diaApple = [diaDir stringByAppendingPathComponent:@"com.apple.passwordmanager.json"];
    NSCAssert([readJSON(diaApple)[@"path"] isEqual:DPAppSupport(@"DiaPatches/bin/diapatch")], @"Apple relay written to Dia/User Data");
    NSCAssert([readJSON(openPath)[@"path"] isEqual:DPAppSupport(@"DiaPatches/bin/diapatch")], @"OpenPasswords relay written to Dia/User Data");
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:DPAppSupport(@"DiaPatches/com.openpasswords.icloud.json")], @"original OpenPasswords manifest kept");

    // Turning off removes relays and restores original OpenPasswords manifest.
    DPICloudPasswords.on = NO;
    DPICloudPasswords.apply(&DPICloudPasswords);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaApple], @"Apple relay removed when off");
    NSCAssert([[readJSON(openPath)[@"path"] lastPathComponent] isEqual:@"OpenPasswordsHelper"], @"original OpenPasswords manifest restored");

    // Transition from Chrome-less -> Chrome installed migrates relay and removes stale Dia copy.
    DPICloudPasswords.on = YES;
    DPICloudPasswords.apply(&DPICloudPasswords);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:diaApple], @"Dia relay exists before Chrome install");
    NSCAssert(chflags(google.fileSystemRepresentation, 0) == 0, @"nouchg google");
    DPICloudPasswords.apply(&DPICloudPasswords);
    NSString *chromeApple = DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json");
    NSCAssert(DPICloudPasswords.ready(&DPICloudPasswords) == nil, @"iCloud Passwords valid after Chrome installed");
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:chromeApple], @"Apple relay migrated to Chrome folder");
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaApple], @"stale Dia Apple relay removed");
    DPICloudPasswords.on = NO;
    DPICloudPasswords.apply(&DPICloudPasswords);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:chromeApple], @"Chrome Apple relay removed when off");

    // #384: existing read-only Chrome NativeMessagingHosts still reports sudo chown repair.
    NSString *chromeDir = chromeApple.stringByDeletingLastPathComponent;
    chmod(chromeDir.fileSystemRepresentation, 0555);
    DPICloudPasswords.on = YES;
    DPICloudPasswords.apply(&DPICloudPasswords);
    problem = DPICloudPasswords.ready(&DPICloudPasswords);
    NSCAssert(problem && [problem containsString:@"sudo chown -R \"$(whoami)\""], @"#384 iCloud Passwords repair expected, got: %@", problem);
    chmod(chromeDir.fileSystemRepresentation, 0755);
    [NSFileManager.defaultManager removeItemAtPath:DPAppSupport(@"Google/Chrome") error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google again");

    // Broken /Library manifest (non-executable path) falls through to Cryptex manifest.
    writeJSON(missingLib, @{ @"name" : @"com.apple.passwordmanager", @"path" : @"/nonexistent/helper" });
    [NSFileManager.defaultManager removeItemAtPath:templates error:nil];
    writeJSON(cryptex, @{ @"name" : @"com.apple.passwordmanager", @"path" : appleHelper });
    NSCAssert([DPAppleHelperPath() isEqualToString:appleHelper], @"must skip broken primary and use Cryptex fallback");

    // Missing everywhere reports missing Apple helper.
    [NSFileManager.defaultManager removeItemAtPath:cryptex error:nil];
    DPICloudPasswords.on = YES;
    DPICloudPasswords.apply(&DPICloudPasswords);
    problem = DPICloudPasswords.ready(&DPICloudPasswords);
    NSCAssert([problem containsString:@"doesn’t have Apple’s iCloud Passwords helper"], @"missing helper message expected, got: %@", problem);

    // diapatch PasswordsHost.m appleHelperIn & onePasswordHostIn parity.
    writeJSON(templates, @{ @"name" : @"com.apple.passwordmanager", @"path" : appleHelper });
    NSCAssert([appleHelperIn(@[ missingLib, templates, cryptex ]) isEqualToString:appleHelper], @"diapatch appleHelperIn falls back to Templates");
    NSCAssert(appleHelperIn(@[ missingLib ]) == nil, @"diapatch appleHelperIn rejects non-executable path");

    NSString *opManifest = [diaDir stringByAppendingPathComponent:@"com.1password.1password.json"];
    writeJSON(opManifest, @{ @"name" : @"com.1password.1password", @"path" : @"/Applications/1Password.app/Contents/MacOS/1Password-BrowserSupport",
                             @"allowed_origins" : @[ @"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/" ] });
    NSDictionary *op = onePasswordHostIn(@[ DPAppSupport(@"Google/Chrome/NativeMessagingHosts"), diaDir ]);
    NSCAssert([op[@"path"] hasSuffix:@"/1Password-BrowserSupport"], @"diapatch onePasswordHostIn falls back to Dia/User Data");

    // Live system smoke check: on macOS 14+, DPAppleHelper() finds Apple's real executable.
    NSString *liveHelper = DPAppleHelper();
    if (liveHelper) NSCAssert([NSFileManager.defaultManager isExecutableFileAtPath:liveHelper], @"live Apple helper must be executable");

    unlockAndRemove(sysRoot);
    unlockAndRemove(gAppSupportRoot);
}

static void testBitwardenAndOnePasswordChromeless(void) {
    gAppSupportRoot = makeTempDir();
    installFakeRelay();

    NSString *google = DPAppSupport(@"Google");
    [NSFileManager.defaultManager createDirectoryAtPath:google withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google");

    NSString *proxy = [gAppSupportRoot stringByAppendingPathComponent:@"Bitwarden/desktop_proxy"];
    writeExecutable(proxy);
    gBitwardenProxy = proxy;

    NSString *diaBw = DPAppSupport(@"Dia/User Data/NativeMessagingHosts/com.8bit.bitwarden.json");
    DPBitwarden.on = YES;
    DPBitwarden.apply(&DPBitwarden);
    NSCAssert(DPBitwarden.ready(&DPBitwarden) == nil, @"Bitwarden should succeed without Chrome, got: %@", DPBitwarden.ready(&DPBitwarden));
    NSCAssert([readJSON(diaBw)[@"path"] isEqual:proxy], @"Bitwarden manifest written to Dia/User Data");

    DPBitwarden.on = NO;
    DPBitwarden.apply(&DPBitwarden);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaBw], @"Bitwarden removes our Dia manifest when off");

    // Third-party Bitwarden manifest is untouched when toggling on and off.
    writeJSON(diaBw, @{ @"name" : @"com.8bit.bitwarden", @"description" : @"Bitwarden desktop", @"path" : proxy });
    DPBitwarden.on = YES;
    DPBitwarden.apply(&DPBitwarden);
    NSCAssert([readJSON(diaBw)[@"description"] isEqual:@"Bitwarden desktop"], @"Bitwarden leaves existing third-party manifest alone");
    DPBitwarden.on = NO;
    DPBitwarden.apply(&DPBitwarden);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:diaBw], @"Bitwarden does not delete third-party manifest when off");

    // #384: existing read-only Chrome NativeMessagingHosts still reports sudo chown repair.
    NSCAssert(chflags(google.fileSystemRepresentation, 0) == 0, @"nouchg google");
    NSString *chromeDir = DPAppSupport(@"Google/Chrome/NativeMessagingHosts");
    [NSFileManager.defaultManager createDirectoryAtPath:chromeDir withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(chromeDir.fileSystemRepresentation, 0555);
    DPBitwarden.on = YES;
    DPBitwarden.apply(&DPBitwarden);
    NSString *bwProblem = DPBitwarden.ready(&DPBitwarden);
    NSCAssert(bwProblem && [bwProblem containsString:@"sudo chown -R \"$(whoami)\""], @"#384 Bitwarden repair expected, got: %@", bwProblem);
    chmod(chromeDir.fileSystemRepresentation, 0755);
    [NSFileManager.defaultManager removeItemAtPath:DPAppSupport(@"Google/Chrome") error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google");

    // OnePassword ready check sees manifest in Dia/User Data when Chrome folder is absent/EPERM.
    DPTesting = NO;
    NSString *diaOp = DPAppSupport(@"Dia/User Data/NativeMessagingHosts/com.1password.1password.json");
    writeJSON(diaOp, @{ @"name" : @"com.1password.1password", @"path" : @"/Applications/1Password.app/Contents/MacOS/1Password-BrowserSupport" });
    NSCAssert(DPOnePassword.ready(&DPOnePassword) == nil, @"OnePassword should see manifest in Dia/User Data, got: %@", DPOnePassword.ready(&DPOnePassword));

    unlockAndRemove(gAppSupportRoot);
}

static void testProtonPass(void) {
    gAppSupportRoot = makeTempDir();
    DPTesting = NO;

    NSString *fakeApp = [gAppSupportRoot stringByAppendingPathComponent:@"Proton Pass.app"];
    NSString *hostBin = [fakeApp stringByAppendingPathComponent:@"Contents/Resources/assets/proton_pass_nm_host"];
    NSCAssert(DPExecutableHostInApp(nil) == nil && DPExecutableHostInApp(@"") == nil, @"empty app path yields nil");
    NSCAssert(DPExecutableHostInApp(fakeApp) == nil, @"missing host binary yields nil");
    [NSFileManager.defaultManager createDirectoryAtPath:hostBin.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [@"#!/bin/sh\n" writeToFile:hostBin atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(hostBin.fileSystemRepresentation, 0644);
    NSCAssert(DPExecutableHostInApp(fakeApp) == nil, @"non-executable host binary yields nil");
    chmod(hostBin.fileSystemRepresentation, 0755);
    NSCAssert([DPExecutableHostInApp(fakeApp) isEqualToString:hostBin], @"executable host binary discovered inside app");

    // Off-tweak invariant: install while off creates nothing.
    gProtonPassHost = hostBin;
    DPProtonPass.on = NO;
    DPProtonPass.install();
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:DPAppSupport(@"Google")], @"off Proton Pass must not create Google dir");
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:DPAppSupport(@"Dia")], @"off Proton Pass must not create Dia dir");

    // Missing app: ready() reports missing desktop app unless DPTesting is YES.
    gProtonPassHost = nil;
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSString *missingMsg = DPProtonPass.ready(&DPProtonPass);
    NSCAssert(missingMsg && [missingMsg containsString:@"The Proton Pass desktop app isn’t installed"], @"missing app message expected, got: %@", missingMsg);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:DPAppSupport(@"Google/Chrome/NativeMessagingHosts/me.proton.pass.nm.json")], @"missing app must not write manifest");
    DPTesting = YES;
    NSCAssert(DPProtonPass.ready(&DPProtonPass) == nil, @"DPTesting passes when Proton Pass app is absent");
    DPTesting = NO;

    // Standard install with full 3-origin JSON schema.
    gProtonPassHost = hostBin;
    NSArray<NSString *> *expectedOrigins = @[
        @"chrome-extension://ghmbeldphafepmbegfdlkpapadhbakde/",
        @"chrome-extension://hlaiofkbmjenhgeinjlmkafaipackfjh/",
        @"chrome-extension://gcllgfdnfnllodcaambdaknbipemelie/",
    ];
    NSString *chromePp = DPAppSupport(@"Google/Chrome/NativeMessagingHosts/me.proton.pass.nm.json");
    NSString *diaPp = DPAppSupport(@"Dia/User Data/NativeMessagingHosts/me.proton.pass.nm.json");
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert(DPProtonPass.ready(&DPProtonPass) == nil, @"Proton Pass ready on creatable Chrome dir, got: %@", DPProtonPass.ready(&DPProtonPass));
    NSDictionary *manifest = readJSON(chromePp);
    NSCAssert([manifest[@"name"] isEqual:@"me.proton.pass.nm"], @"manifest name");
    NSCAssert([manifest[@"description"] isEqual:@"DiaTweaks link to the Proton Pass app"], @"manifest description");
    NSCAssert([manifest[@"path"] isEqual:hostBin], @"manifest path");
    NSCAssert([manifest[@"type"] isEqual:@"stdio"], @"manifest type");
    NSCAssert([manifest[@"allowed_origins"] isEqual:expectedOrigins], @"manifest allowed_origins: %@", manifest[@"allowed_origins"]);

    // Off/pause removes our Chrome manifest.
    DPProtonPass.on = NO;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:chromePp], @"off Proton Pass removes Chrome manifest");

    // Chrome-less EPERM fallback writes to Dia/User Data/NativeMessagingHosts.
    [NSFileManager.defaultManager removeItemAtPath:DPAppSupport(@"Google/Chrome") error:nil];
    NSString *google = DPAppSupport(@"Google");
    [NSFileManager.defaultManager createDirectoryAtPath:google withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google");

    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert(DPProtonPass.ready(&DPProtonPass) == nil, @"Proton Pass succeeds without Chrome, got: %@", DPProtonPass.ready(&DPProtonPass));
    NSDictionary *diaManifest = readJSON(diaPp);
    NSCAssert([diaManifest[@"path"] isEqual:hostBin] && [diaManifest[@"allowed_origins"] isEqual:expectedOrigins], @"Dia fallback manifest matches schema");

    // Chrome later becomes available: re-apply migrates to Chrome and cleans stale Dia copy.
    NSCAssert(chflags(google.fileSystemRepresentation, 0) == 0, @"nouchg google");
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert(DPProtonPass.ready(&DPProtonPass) == nil, @"Proton Pass ready after Chrome appears");
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:chromePp], @"manifest migrated to Chrome folder");
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaPp], @"stale Dia manifest removed");

    // Off/pause cleans up Chrome-less Dia copy too.
    DPProtonPass.on = NO;
    DPProtonPass.apply(&DPProtonPass);
    [NSFileManager.defaultManager removeItemAtPath:DPAppSupport(@"Google/Chrome") error:nil];
    NSCAssert(chflags(google.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"uchg google again");
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:diaPp], @"Dia fallback manifest written");
    DPProtonPass.on = NO;
    DPProtonPass.install();
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaPp], @"off/install removes Dia fallback manifest");

    // Preserving user/app-owned manifest across on/off, plus broken/invalid manifest diagnostics.
    writeJSON(diaPp, @{
        @"name" : @"me.proton.pass.nm",
        @"description" : @"Proton Pass host for native messaging with the desktop app",
        @"path" : hostBin,
        @"type" : @"stdio",
        @"allowed_origins" : expectedOrigins,
    });
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert(DPProtonPass.ready(&DPProtonPass) == nil, @"valid third-party manifest passes ready");
    NSCAssert([readJSON(diaPp)[@"description"] isEqual:@"Proton Pass host for native messaging with the desktop app"], @"third-party manifest preserved on enable");
    DPProtonPass.on = NO;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:diaPp], @"third-party manifest preserved on disable");

    writeJSON(diaPp, @{ @"name" : @"me.proton.pass.nm", @"description" : @"Proton Pass host", @"path" : @"/nonexistent/proton_pass_nm_host" });
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSString *brokenMsg = DPProtonPass.ready(&DPProtonPass);
    NSCAssert(brokenMsg && [brokenMsg containsString:@"Quit and reopen Proton Pass"], @"broken third-party host message expected, got: %@", brokenMsg);

    writeJSON(diaPp, @{ @"name" : @"wrong.host", @"description" : @"Proton Pass host", @"path" : hostBin });
    DPProtonPass.apply(&DPProtonPass);
    NSString *invalidMsg = DPProtonPass.ready(&DPProtonPass);
    NSCAssert(invalidMsg && [invalidMsg containsString:@"isn’t a valid host file"], @"invalid host message expected, got: %@", invalidMsg);
    [NSFileManager.defaultManager removeItemAtPath:diaPp error:nil];

    // Stale DiaTweaks Dia copy is removed even when Chrome gains a third-party manifest.
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:diaPp], @"ours written in Dia");
    NSCAssert(chflags(google.fileSystemRepresentation, 0) == 0, @"nouchg google");
    writeJSON(chromePp, @{ @"name" : @"me.proton.pass.nm", @"description" : @"Proton Pass host for native messaging with the desktop app", @"path" : hostBin });
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert([readJSON(chromePp)[@"description"] hasPrefix:@"Proton Pass host"], @"Chrome third-party manifest untouched");
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:diaPp], @"stale DiaTweaks copy cleaned when Chrome has third-party manifest");
    [NSFileManager.defaultManager removeItemAtPath:chromePp error:nil];

    // #384: existing read-only Chrome NativeMessagingHosts reports sudo chown repair.
    NSString *chromeDir = chromePp.stringByDeletingLastPathComponent;
    chmod(chromeDir.fileSystemRepresentation, 0555);
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSString *permMsg = DPProtonPass.ready(&DPProtonPass);
    NSCAssert(permMsg && [permMsg containsString:@"sudo chown -R \"$(whoami)\""], @"#384 Proton Pass repair expected, got: %@", permMsg);
    chmod(chromeDir.fileSystemRepresentation, 0755);

    // Symlinked app & host succeed; directory or broken symlink at host binary is rejected.
    NSString *symlinkApp = [gAppSupportRoot stringByAppendingPathComponent:@"ProtonPassLink.app"];
    NSCAssert([NSFileManager.defaultManager createSymbolicLinkAtPath:symlinkApp withDestinationPath:fakeApp error:nil], @"create app symlink");
    NSCAssert([DPExecutableHostInApp(symlinkApp) hasSuffix:@"/ProtonPassLink.app/Contents/Resources/assets/proton_pass_nm_host"],
              @"symlinked Proton Pass app discovers executable host");

    NSString *dirApp = [gAppSupportRoot stringByAppendingPathComponent:@"DirHost.app"];
    NSString *dirHost = [dirApp stringByAppendingPathComponent:@"Contents/Resources/assets/proton_pass_nm_host"];
    [NSFileManager.defaultManager createDirectoryAtPath:dirHost withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(DPExecutableHostInApp(dirApp) == nil, @"directory named proton_pass_nm_host must be rejected");
    writeJSON(chromePp, @{ @"name" : @"me.proton.pass.nm", @"description" : @"Proton Pass host", @"path" : dirHost });
    DPProtonPass.apply(&DPProtonPass);
    NSString *dirReadyMsg = DPProtonPass.ready(&DPProtonPass);
    NSCAssert(dirReadyMsg && [dirReadyMsg containsString:@"Quit and reopen Proton Pass"],
              @"ready() must reject directory path in manifest, got: %@", dirReadyMsg);
    [NSFileManager.defaultManager removeItemAtPath:chromePp error:nil];

    NSString *brokenApp = [gAppSupportRoot stringByAppendingPathComponent:@"BrokenHost.app"];
    NSString *brokenHost = [brokenApp stringByAppendingPathComponent:@"Contents/Resources/assets/proton_pass_nm_host"];
    [NSFileManager.defaultManager createDirectoryAtPath:brokenHost.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:brokenHost withDestinationPath:@"/nonexistent/proton_pass_nm_host" error:nil];
    NSCAssert(DPExecutableHostInApp(brokenApp) == nil, @"broken symlink at host binary must be rejected");

    // Ownership requires BOTH name and description; matching description with another name is preserved.
    writeJSON(chromePp, @{ @"name" : @"other.host", @"description" : @"DiaTweaks link to the Proton Pass app", @"path" : hostBin });
    DPProtonPass.on = NO;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:chromePp], @"manifest with wrong name must not be deleted even if description matches");
    [NSFileManager.defaultManager removeItemAtPath:chromePp error:nil];

    // Uninstalling Proton Pass while tweak stays ON removes stale DiaTweaks-owned manifest.
    gProtonPassHost = hostBin;
    DPProtonPass.on = YES;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert([NSFileManager.defaultManager fileExistsAtPath:chromePp], @"DiaTweaks manifest installed before uninstall");
    gProtonPassHost = nil;
    DPProtonPass.apply(&DPProtonPass);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:chromePp], @"uninstalling Proton Pass cleans up stale DiaTweaks manifest");

    unlockAndRemove(gAppSupportRoot);
}

int main(void) {
    @autoreleasepool {
        testHostFolderFallback();
        testPasskeysChromelessAndTransition();
        testICloudPasswordsTemplatesAndChromeless();
        testBitwardenAndOnePasswordChromeless();
        testProtonPass();
        puts("all native messaging checks passed");
    }
    return 0;
}

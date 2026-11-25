#import "diapatch/AppIcon.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <sys/stat.h>
#import "watchdog.h"

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    fprintf(stderr, "FAIL %s\n", what.UTF8String);
}

static BOOL isSymlink(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode);
}

static int runCmd(NSArray<NSString *> *argv, NSDictionary<NSString *, NSString *> *env, NSString **output) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    if (env) {
        NSMutableDictionary *merged = [NSProcessInfo.processInfo.environment mutableCopy];
        [merged addEntriesFromDictionary:env];
        task.environment = merged;
    }
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = task.standardError = pipe;
    if (![task launchAndReturnError:NULL]) return -1;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (output) *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return task.terminationStatus;
}

static OSStatus checkValidity(NSString *app, SecCSFlags flags) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)app.fileSystemRepresentation, strlen(app.fileSystemRepresentation), true);
    SecStaticCodeRef sc = NULL;
    OSStatus st = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &sc);
    CFRelease(url);
    if (st != errSecSuccess) return st;
    CFErrorRef err = NULL;
    st = SecStaticCodeCheckValidityWithErrors(sc, flags, NULL, &err);
    if (err) CFRelease(err);
    CFRelease(sc);
    return st;
}

static void setDomainValue(NSString *domain, CFStringRef key, CFPropertyListRef value) {
    CFPreferencesSetAppValue(key, value, (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}

static NSString *gIconRoot, *gIconDomain;
static void DPCleanIconScratch(void) {
    if (gIconDomain) [NSUserDefaults.standardUserDefaults removePersistentDomainForName:gIconDomain];
    if (gIconRoot) [NSFileManager.defaultManager removeItemAtPath:gIconRoot error:NULL];
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"app-icon-signing-%@", NSUUID.UUID.UUIDString]];
        NSString *domain = [root stringByAppendingPathComponent:@"com.diapatches"];
        gIconRoot = root;
        gIconDomain = domain;
        DPOnTestCleanup(DPCleanIconScratch);
        DPArmTestWatchdog(60);
        NSString *home = [root stringByAppendingPathComponent:@"home"];
        NSString *cache = [root stringByAppendingPathComponent:@"cache"];
        NSString *installed = [root stringByAppendingPathComponent:@"Dia.app"];
        NSString *pristine = [home stringByAppendingPathComponent:@"pristine/Dia.app"];
        NSString *staged = [home stringByAppendingPathComponent:@"staged/Dia.app"];
        NSString *cwd = fm.currentDirectoryPath;
        NSString *diapatch = [cwd stringByAppendingPathComponent:@"build/diapatch"];
        NSString *neutralCar = [cwd stringByAppendingPathComponent:@"assets/app-icons/AppIconNeutral.car"];
        NSString *blueCar = [cwd stringByAppendingPathComponent:@"assets/app-icons/AppIconBlue.car"];
        NSString *redCar = [cwd stringByAppendingPathComponent:@"assets/app-icons/AppIconRed.car"];

        expect([fm isExecutableFileAtPath:diapatch], @"build/diapatch exists");
        expect([fm fileExistsAtPath:neutralCar], @"AppIconNeutral.car fixture exists");
        expect([fm createDirectoryAtPath:[pristine stringByAppendingPathComponent:@"Contents/MacOS"] withIntermediateDirectories:YES attributes:nil error:NULL], @"create pristine MacOS");
        expect([fm createDirectoryAtPath:[pristine stringByAppendingPathComponent:@"Contents/Resources"] withIntermediateDirectories:YES attributes:nil error:NULL], @"create pristine Resources");
        expect([fm createDirectoryAtPath:[home stringByAppendingPathComponent:@"app-icons"] withIntermediateDirectories:YES attributes:nil error:NULL], @"create app-icons dir");

        // Build a minimal thin arm64 Mach-O executable with headerpad so addLoadCommand succeeds.
        NSString *src = [root stringByAppendingPathComponent:@"stub.c"];
        NSString *bin = [pristine stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
        expect([@"int main(void){return 0;}\n" writeToFile:src atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write stub.c");
        expect(runCmd(@[ @"/usr/bin/clang", @"-arch", @"arm64", @"-Wl,-headerpad,0x400", src, @"-o", bin ], nil, NULL) == 0, @"compile arm64 stub");
        expect([fm copyItemAtPath:neutralCar toPath:[pristine stringByAppendingPathComponent:@"Contents/Resources/Assets.car"] error:NULL], @"copy fixture Assets.car");
        expect([fm copyItemAtPath:blueCar toPath:[home stringByAppendingPathComponent:@"app-icons/AppIconBlue.car"] error:NULL], @"copy AppIconBlue.car");
        expect([fm copyItemAtPath:redCar toPath:[home stringByAppendingPathComponent:@"app-icons/AppIconRed.car"] error:NULL], @"copy AppIconRed.car");
        expect([@"stub" writeToFile:[home stringByAppendingPathComponent:@"DiaPatches.dylib"] atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"create placeholder dylib");

        NSDictionary *info = @{
            @"CFBundleExecutable" : @"Dia",
            @"CFBundleIdentifier" : @"company.thebrowser.dia",
            @"CFBundleVersion" : @"91177",
            @"CFBundleShortVersionString" : @"1.58.0",
            @"CFBundlePackageType" : @"APPL",
            @"CFBundleIconName" : @"AppIconNeutral",
        };
        expect([info writeToFile:[pristine stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES], @"write pristine Info.plist");

        NSDictionary *env = @{
            @"DIAPATCH_HOME" : home,
            @"DIAPATCH_CACHE" : cache,
            @"DIAPATCH_APP" : installed,
            @"DIAPATCH_IDENTITY" : @"-",
            @"DIATWEAKS_DOMAIN" : domain,
            @"DIAPATCH_NO_RELAUNCH" : @"1",
        };
        setenv("DIATWEAKS_DOMAIN", domain.UTF8String, 1);

        NSString *out = nil;
        expect(runCmd(@[ diapatch, @"build" ], env, &out) == 0, @"diapatch build succeeds with appIcon off");
        expect(runCmd(@[ diapatch, @"apply" ], env, &out) == 0, @"diapatch apply succeeds with appIcon off");
        NSString *installedCar = [installed stringByAppendingPathComponent:@"Contents/Resources/Assets.car"];
        NSDictionary *installedInfo = [NSDictionary dictionaryWithContentsOfFile:[installed stringByAppendingPathComponent:@"Contents/Info.plist"]];
        expect(!isSymlink(installedCar) && [fm fileExistsAtPath:installedCar], @"Assets.car is regular file when appIcon off");
        expect([installedInfo[@"CFBundleIconName"] isEqual:@"AppIconNeutral"], @"CFBundleIconName untouched when appIcon off");
        expect(installedInfo[@"DiaTweaksOwnIcon"] == nil, @"DiaTweaksOwnIcon absent when appIcon off");
        expect(runCmd(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", installed ], nil, &out) == 0, @"codesign --deep --strict passes when appIcon off");
        expect(checkValidity(installed, kSecCSDefaultFlags) == errSecSuccess, @"SecStaticCode(Default) passes when appIcon off");
        expect(checkValidity(installed, kSecCSStrictValidate | kSecCSRestrictSymlinks) == errSecSuccess, @"SecStaticCode(Strict|RestrictSymlinks) passes when appIcon off");
        expect(runCmd(@[ diapatch, @"set-icon" ], env, &out) != 0, @"set-icon refuses unlinked bundle without corrupting it");
        expect(runCmd(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", installed ], nil, &out) == 0, @"codesign --deep --strict still passes after rejected set-icon");

        setDomainValue(domain, CFSTR("appIcon"), kCFBooleanTrue);
        setDomainValue(domain, CFSTR("appIconChoice"), CFSTR("AppIconBlue"));
        expect(runCmd(@[ diapatch, @"build" ], env, &out) == 0, @"diapatch build succeeds with appIcon on");
        expect(runCmd(@[ diapatch, @"apply" ], env, &out) == 0, @"diapatch apply succeeds with appIcon on");
        installedInfo = [NSDictionary dictionaryWithContentsOfFile:[installed stringByAppendingPathComponent:@"Contents/Info.plist"]];
        expect(isSymlink(installedCar), @"Assets.car is symlink when appIcon on");
        expect([installedInfo[@"CFBundleIconName"] isEqual:@"DiaChosenIcon"], @"CFBundleIconName is DiaChosenIcon when appIcon on");
        expect([installedInfo[@"DiaTweaksOwnIcon"] isEqual:@"AppIconNeutral"], @"DiaTweaksOwnIcon records original icon name");
        expect(checkValidity(installed, kSecCSDefaultFlags) == errSecSuccess, @"SecStaticCode(Default) passes when appIcon on");
        setDomainValue(domain, CFSTR("appIconChoice"), CFSTR("AppIconRed"));
        expect(runCmd(@[ diapatch, @"set-icon" ], env, &out) == 0, @"live set-icon succeeds on linked bundle");
        expect(checkValidity(installed, kSecCSDefaultFlags) == errSecSuccess, @"SecStaticCode(Default) still passes after live set-icon");

        NSString *pausedFile = [home stringByAppendingPathComponent:@"paused"];
        expect([NSData.data writeToFile:pausedFile atomically:YES], @"create paused marker");
        expect(runCmd(@[ diapatch, @"build" ], env, &out) == 0, @"diapatch build succeeds while paused");
        expect(!isSymlink([staged stringByAppendingPathComponent:@"Contents/Resources/Assets.car"]), @"staged Assets.car is regular file while paused");
        expect(runCmd(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", staged ], nil, &out) == 0, @"codesign --deep --strict passes while paused");
        [fm removeItemAtPath:pausedFile error:NULL];

        NSString *safeFile = [home stringByAppendingPathComponent:@"safe-mode.plist"];
        expect([@{ @"level" : @1 } writeToFile:safeFile atomically:YES], @"write safe-mode.plist level=1");
        expect(runCmd(@[ diapatch, @"build" ], env, &out) == 0, @"diapatch build succeeds in safe mode");
        expect(!isSymlink([staged stringByAppendingPathComponent:@"Contents/Resources/Assets.car"]), @"staged Assets.car is regular file in safe mode");
        expect(runCmd(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", staged ], nil, &out) == 0, @"codesign --deep --strict passes in safe mode");
        [fm removeItemAtPath:safeFile error:NULL];

        setDomainValue(domain, CFSTR("appIcon"), kCFBooleanFalse);
        expect(runCmd(@[ diapatch, @"build" ], env, &out) == 0, @"diapatch build succeeds after disabling appIcon");
        expect(runCmd(@[ diapatch, @"apply" ], env, &out) == 0, @"diapatch apply succeeds after disabling appIcon");
        installedInfo = [NSDictionary dictionaryWithContentsOfFile:[installed stringByAppendingPathComponent:@"Contents/Info.plist"]];
        expect(!isSymlink(installedCar) && [fm fileExistsAtPath:installedCar], @"Assets.car restored to regular file after disabling appIcon");
        expect([installedInfo[@"CFBundleIconName"] isEqual:@"AppIconNeutral"], @"CFBundleIconName restored after disabling appIcon");
        expect(installedInfo[@"DiaTweaksOwnIcon"] == nil, @"DiaTweaksOwnIcon cleared after disabling appIcon");
        expect(runCmd(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", installed ], nil, &out) == 0, @"codesign --deep --strict passes after disabling appIcon");
        expect(checkValidity(installed, kSecCSStrictValidate | kSecCSRestrictSymlinks) == errSecSuccess, @"SecStaticCode(Strict|RestrictSymlinks) passes after disabling appIcon");

        NSString *direct = [root stringByAppendingPathComponent:@"Direct.app"];
        expect([fm copyItemAtPath:pristine toPath:direct error:NULL], @"copy Direct.app");
        setDomainValue(domain, CFSTR("appIcon"), kCFBooleanTrue);
        NSString *res1 = DPPrepareIcons(direct, installed, home);
        expect([res1 isEqual:@"linked Dia's catalog for icon switching"], @"DPPrepareIcons links Direct.app when on");
        NSString *res2 = DPPrepareIcons(direct, installed, home);
        expect([res2 isEqual:@"linked Dia's catalog for icon switching"], @"DPPrepareIcons is idempotent on already-symlinked bundle");
        expect(!isSymlink([home stringByAppendingPathComponent:@"icons/builds/91177/base.car"]), @"base.car stays regular file after repeated DPPrepareIcons");
        setDomainValue(domain, CFSTR("appIcon"), kCFBooleanFalse);
        NSString *res3 = DPPrepareIcons(direct, installed, home);
        expect([res3 isEqual:@"restored Dia's catalog"], @"DPPrepareIcons restores previously symlinked bundle when off");
        expect(!isSymlink([direct stringByAppendingPathComponent:@"Contents/Resources/Assets.car"]), @"Direct.app Assets.car is regular file after restore");
        NSDictionary *directInfo = [NSDictionary dictionaryWithContentsOfFile:[direct stringByAppendingPathComponent:@"Contents/Info.plist"]];
        expect([directInfo[@"CFBundleIconName"] isEqual:@"AppIconNeutral"] && directInfo[@"DiaTweaksOwnIcon"] == nil, @"Direct.app Info.plist restored");
        expect(runCmd(@[ @"/usr/bin/codesign", @"--force", @"--timestamp=none", @"--sign", @"-", direct ], nil, &out) == 0, @"codesign Direct.app after restore");
        expect(runCmd(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", direct ], nil, &out) == 0, @"Direct.app passes codesign --deep --strict after restore");
        expect(checkValidity(direct, kSecCSStrictValidate | kSecCSRestrictSymlinks) == errSecSuccess, @"Direct.app passes SecStaticCode(Strict|RestrictSymlinks) after restore");

        setDomainValue(domain, CFSTR("appIcon"), NULL);
        setDomainValue(domain, CFSTR("appIconChoice"), NULL);
    }
    if (!failures) printf("all app-icon-signing checks passed\n");
    return failures ? 1 : 0;
}

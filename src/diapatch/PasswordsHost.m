#import <sys/event.h>
#import "Passwords.h"
#import "PasswordsParts.h"

// Apple's iCloud Passwords extensions plus Better Passwords and Open Passwords, which use Apple's helper too.
static const char *const kAppleOrigins[] = { "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/",
                                             "chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/",
                                             "chrome-extension://ocongmkplhijgajnipnhhggfcjfdilgj/",
                                             "chrome-extension://iaojbcjndjmmblmoemilknlnjijokkfg/",
                                             "chrome-extension://abpahgnajbkclfhpodhjhlmgfjhpibaa/" };

static NSDictionary *hostAt(NSString *manifest) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] && [host[@"path"] isKindOfClass:NSString.class] ? host : nil;
}

static NSString *appleHelperIn(NSArray<NSString *> *manifests) {
    for (NSString *manifest in manifests) {
        NSString *path = hostAt(manifest)[@"path"];
        if (path && [NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

static NSDictionary *onePasswordHostIn(NSArray<NSString *> *folders) {
    for (NSString *folder in folders) {
        NSDictionary *host = hostAt([folder stringByAppendingPathComponent:@"com.1password.1password.json"]);
        if (host) return host;
    }
    return nil;
}

static NSDictionary *onePasswordHost(void) {
    NSString *home = NSHomeDirectory();
    return onePasswordHostIn(@[
        [home stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome/NativeMessagingHosts"],
        [home stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data/NativeMessagingHosts"],
        @"/Library/Google/Chrome/NativeMessagingHosts",
        @"/Library/Application Support/Chromium/NativeMessagingHosts",
    ]);
}

NSString *DPAppleHelper(void) {
    return appleHelperIn(@[
        @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json",
        @"/System/Library/Templates/Data/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json",
        @"/System/Cryptexes/App/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json",
    ]);
}

NSString *DPOnePasswordHelper(void) {
    NSString *path = onePasswordHost()[@"path"];
    return [path.lastPathComponent isEqual:@"1Password-BrowserSupport"] ? path : nil;
}

BOOL DPIsOnePasswordOrigin(const char *origin) {
    id origins = onePasswordHost()[@"allowed_origins"];
    return [origins isKindOfClass:NSArray.class] && [origins containsObject:@(origin)];
}

BOOL DPIsPasswordsOrigin(const char *origin) {
    for (size_t i = 0; i < sizeof kAppleOrigins / sizeof *kAppleOrigins; i++)
        if (!strcmp(origin, kAppleOrigins[i])) return YES;
    return DPIsOnePasswordOrigin(origin);
}

static void waitForExit(pid_t pid) {
    int queue = kqueue();
    if (queue < 0) return;
    struct kevent change, event;
    EV_SET(&change, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (kevent(queue, &change, 1, NULL, 0, NULL) == 0)
        while (kevent(queue, NULL, 0, &event, 1, NULL) < 0 && errno == EINTR) {}
    close(queue);
}

// Chromium hears the helper exit when the pipes close, so this must hold no end of them.
static int runThroughOriginal(NSString *home, NSString *helper, BOOL checksBrowser, int argc, const char *argv[]) {
    pid_t started = DPStartHelperThroughOriginal(home, helper, checksBrowser, argc, argv);
    if (!started) return 1;
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    waitForExit(started);
    return 0;
}

// exec, not spawn: the launch constraint checks that the browser is the helper's parent.
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]) {
    BOOL onePassword = DPIsOnePasswordOrigin(argv[1]);
    NSString *helper = onePassword ? DPOnePasswordHelper() : DPAppleHelper();
    if (!helper) return 1;
    if (DPRunsPatchedDia(getppid(), app)) return runThroughOriginal(home, helper, onePassword, argc, argv);
    if (onePassword) return 1;
    argv[0] = helper.fileSystemRepresentation;
    execv(argv[0], (char *const *)argv);
    return 1;
}

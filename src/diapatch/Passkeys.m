#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <pthread.h>
#import <sys/file.h>
#import <sys/wait.h>
#import "LaunchServices.h"
#import "Passkeys.h"
#import "Disclaim.h"

static const int kSheetWidth = 480, kSheetHeight = 300;
static const uint32_t kMaxMessageLength = 1024 * 1024;
static const NSUInteger kMaxHelperMessageLength = 16 * 1024 * 1024;

static FILE *gFromHelper, *gToHelper;
static pthread_mutex_t gHelperLock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic pid_t gHelper;
static _Atomic int gCancelled;

static NSDictionary *asDictionary(id value) { return [value isKindOfClass:NSDictionary.class] ? value : nil; }
static NSArray *asArray(id value) { return [value isKindOfClass:NSArray.class] ? value : nil; }
static NSString *asString(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }

static NSDictionary *readFromHelper(void) {
    if (!gFromHelper) return nil;
    NSMutableData *data = [NSMutableData data];
    char chunk[16 * 1024];
    size_t used = 0;
    for (;;) {
        int c = getc_unlocked(gFromHelper);
        if (c == EOF) {
            if (!ferror(gFromHelper) || errno != EINTR) return nil;
            clearerr(gFromHelper);
            continue;
        }
        if (c) chunk[used++] = (char)c;
        if (c && used < sizeof chunk) continue;
        if (data.length + used > kMaxHelperMessageLength) return nil;
        [data appendBytes:chunk length:used];
        used = 0;
        if (!c) break;
    }
    return asDictionary([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
}

static int writeCDP(NSString *method, NSDictionary *params, NSString *session) {
    if (!gToHelper || !method) return 0;
    static int lastId;
    int id = ++lastId;
    NSMutableDictionary *message = [@{ @"id" : @(id), @"method" : method, @"params" : params ?: @{} } mutableCopy];
    message[@"sessionId"] = session;
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!data) return 0;
    fwrite(data.bytes, 1, data.length, gToHelper);
    fputc(0, gToHelper);
    fflush(gToHelper);
    return id;
}

static NSDictionary *sendWithEvents(NSString *method, NSDictionary *params, NSString *session, void (^onEvent)(NSDictionary *event)) {
    if (!gToHelper || !gFromHelper || !method) return nil;
    int id = writeCDP(method, params, session);
    if (!id) return nil;
    for (NSDictionary *reply; (reply = readFromHelper());) {
        if ([reply[@"id"] intValue] == id) return reply;
        if (onEvent && reply[@"method"] && (!session || !reply[@"sessionId"] || [reply[@"sessionId"] isEqual:session])) onEvent(reply);
    }
    return nil;
}

static NSDictionary *send(NSString *method, NSDictionary *params, NSString *session) {
    return sendWithEvents(method, params, session, nil);
}

static id evaluateWithEvents(NSString *session, NSString *expression, void (^onEvent)(NSDictionary *event)) {
    if (!expression) return nil;
    NSDictionary *params = @{ @"expression" : expression, @"awaitPromise" : @YES, @"returnByValue" : @YES, @"userGesture" : @YES };
    NSDictionary *reply = sendWithEvents(@"Runtime.evaluate", params, session, onEvent);
    return asDictionary(asDictionary(reply[@"result"])[@"result"])[@"value"];
}

static id evaluate(NSString *session, NSString *expression) {
    return evaluateWithEvents(session, expression, nil);
}

static NSDictionary *readMessageFrom(FILE *stream) {
    uint32_t length = 0;
    if (!stream || fread(&length, sizeof length, 1, stream) != 1 || !length || length > kMaxMessageLength) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (!data || fread(data.mutableBytes, 1, length, stream) != length) return nil;
    return asDictionary([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
}

static BOOL validRequest(NSDictionary *request) {
    if (![request isKindOfClass:NSDictionary.class]) return NO;
    id kind = request[@"kind"], options = request[@"options"];
    return ([kind isEqual:@"create"] || [kind isEqual:@"get"])
        && [asString(request[@"origin"]) length] > 0
        && [options isKindOfClass:NSDictionary.class]
        && [NSJSONSerialization isValidJSONObject:options];
}

static void writeMessage(NSDictionary *message) {
    if (!message) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!data) return;
    uint32_t length = (uint32_t)data.length;
    fwrite(&length, 4, 1, stdout);
    fwrite(data.bytes, 1, length, stdout);
    fflush(stdout);
}

static NSDictionary *failure(NSString *message) { return @{ @"error" : @{ @"name" : @"NotAllowedError", @"message" : message } }; }

static int bail(NSString *message, int status) {
    writeMessage(failure(message));
    return status;
}

// The extension holds our stdin open until it has the answer, so EOF means the page gave up.
static void *watchForCancel(void *_) {
    char byte;
    for (ssize_t n;;) {
        n = read(STDIN_FILENO, &byte, 1);
        if (n > 0 || (n < 0 && errno == EINTR)) continue;
        break;
    }
    gCancelled = 1;
    pthread_mutex_lock(&gHelperLock);
    pid_t helper = gHelper;
    if (helper > 0) kill(helper, SIGTERM);
    pthread_mutex_unlock(&gHelperLock);
    if (helper <= 0) return NULL;
    for (int i = 0; i < 30 && gHelper == helper; i++) usleep(100000);
    pthread_mutex_lock(&gHelperLock);
    if (gHelper == helper) kill(helper, SIGKILL);
    pthread_mutex_unlock(&gHelperLock);
    return NULL;
}

static NSArray<NSString *> *const kAccountStore = @[ @"global_key_value_store.db", @"global_key_value_store.db-wal", @"global_key_value_store.db-shm" ];

static NSArray *modificationDates(NSString *folder) {
    NSMutableArray *dates = [NSMutableArray array];
    for (NSString *name in kAccountStore)
        [dates addObject:[NSFileManager.defaultManager attributesOfItemAtPath:[folder stringByAppendingPathComponent:name] error:nil].fileModificationDate ?: NSNull.null];
    return dates;
}

// Dia may be writing its account store: copy until the files hold still.
static void signInAsDia(NSString *userData) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *dia = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data"];
    [files createDirectoryAtPath:userData withIntermediateDirectories:YES attributes:nil error:nil];
    for (int tries = 0; tries < 5; tries++) {
        NSArray *before = modificationDates(dia);
        for (NSString *name in kAccountStore) {
            [files removeItemAtPath:[userData stringByAppendingPathComponent:name] error:nil];
            [files copyItemAtPath:[dia stringByAppendingPathComponent:name] toPath:[userData stringByAppendingPathComponent:name] error:nil];
        }
        if ([modificationDates(dia) isEqual:before]) return;
    }
}

// Through cfprefsd as `defaults write` did; macOS may map this path to Dia's own domain, so only write when unset.
static void skipIntro(NSString *data) {
    NSString *folder = [data stringByAppendingPathComponent:@"Library/Preferences"];
    CFStringRef preferences = (__bridge CFStringRef)[folder stringByAppendingPathComponent:@"company.thebrowser.dia"];
    Boolean valid = false;
    if (CFPreferencesGetAppBooleanValue(CFSTR("hasPresentedOnboardingIntro"), preferences, &valid) && valid) return;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    CFPreferencesSetAppValue(CFSTR("hasPresentedOnboardingIntro"), kCFBooleanTrue, preferences);
    CFPreferencesAppSynchronize(preferences);
}

static void forgetWindows(NSString *userData) {
    for (NSString *saved in @[ @"Sessions", @"Sessions_Encrypted", @"tabs.db", @"tabs.db-wal", @"tabs.db-shm" ])
        [NSFileManager.defaultManager removeItemAtPath:[userData stringByAppendingPathComponent:[@"Default" stringByAppendingPathComponent:saved]] error:nil];
}

// Fetch.fulfillRequest creates a response without SSLInfo, so Chromium rejects WebAuthn on it unless this pref is set.
static void setAllowSyntheticOriginInProfile(NSString *profileDir, BOOL createIfMissing) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *path = [profileDir stringByAppendingPathComponent:@"Preferences"];
    NSMutableDictionary *prefs;
    if ([files fileExistsAtPath:path]) {
        NSData *raw = [NSData dataWithContentsOfFile:path];
        id parsed = raw ? [NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:nil] : nil;
        if (![parsed isKindOfClass:NSMutableDictionary.class]) return;
        prefs = parsed;
    } else if (createIfMissing) {
        [files createDirectoryAtPath:profileDir withIntermediateDirectories:YES attributes:nil error:nil];
        prefs = [NSMutableDictionary dictionary];
    } else {
        return;
    }
    NSMutableDictionary *webauthn = [prefs[@"webauthn"] isKindOfClass:NSDictionary.class]
        ? [prefs[@"webauthn"] mutableCopy]
        : [NSMutableDictionary dictionary];
    if ([webauthn[@"allow_with_broken_certs"] isEqual:@YES]) return;
    webauthn[@"allow_with_broken_certs"] = @YES;
    prefs[@"webauthn"] = webauthn;
    NSData *data = [NSJSONSerialization dataWithJSONObject:prefs options:0 error:nil];
    if (data) [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static void allowSyntheticOrigin(NSString *userData) {
    setAllowSyntheticOriginInProfile([userData stringByAppendingPathComponent:@"Default"], YES);
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:userData error:nil])
        if ([name hasPrefix:@"Profile "]) setAllowSyntheticOriginInProfile([userData stringByAppendingPathComponent:name], NO);
}

static NSDictionary *sheetBounds(void) {
    CGRect screen = CGDisplayBounds(CGMainDisplayID());
    return @{
        @"left" : @((int)(CGRectGetMidX(screen) - kSheetWidth / 2)), @"top" : @((int)(CGRectGetMidY(screen) - kSheetHeight / 2 - 100)),
        @"width" : @(kSheetWidth), @"height" : @(kSheetHeight),
    };
}

static pid_t launchHelper(NSString *home, int toHelper[2], int fromHelper[2]) {
    NSString *data = [home stringByAppendingPathComponent:@"passkey-helper"];
    NSString *userData = [data stringByAppendingPathComponent:@"ud/User Data"];
    signInAsDia(userData);
    skipIntro(data);
    forgetWindows(userData);
    allowSyntheticOrigin(userData);

    NSString *app = [home stringByAppendingPathComponent:@"pristine/Dia.app/Contents/MacOS/Dia"];
    NSString *profile = [@"--user-data-dir=" stringByAppendingString:[data stringByAppendingPathComponent:@"ud"]];
    NSDictionary *bounds = sheetBounds();
    NSString *size = [NSString stringWithFormat:@"--window-size=%@,%@", bounds[@"width"], bounds[@"height"]];
    NSString *position = [NSString stringWithFormat:@"--window-position=%@,%@", bounds[@"left"], bounds[@"top"]];
    // Disable sync so the helper's empty profile doesn't wipe the user's synced tabs, favorites, and extensions.
    const char *argv[] = { app.fileSystemRepresentation, profile.UTF8String, size.UTF8String, position.UTF8String, "--remote-debugging-pipe", "--mute-audio",
                           "-transientFeatureFlagOverrides", "sync-enabled=false", NULL };

    // adddup2 onto 3 and 4 would clobber a pipe end already sitting there.
    int childIn = toHelper[0] <= 4 ? fcntl(toHelper[0], F_DUPFD_CLOEXEC, 5) : toHelper[0];
    int childOut = fromHelper[1] <= 4 ? fcntl(fromHelper[1], F_DUPFD_CLOEXEC, 5) : fromHelper[1];
    pid_t pid = 0;
    if (childIn >= 0 && childOut >= 0) {
        posix_spawn_file_actions_t files;
        posix_spawn_file_actions_init(&files);
        posix_spawn_file_actions_adddup2(&files, childIn, 3);
        posix_spawn_file_actions_adddup2(&files, childOut, 4);
        for (int fd = 0; fd < 3; fd++) posix_spawn_file_actions_addopen(&files, fd, "/dev/null", fd ? O_WRONLY : O_RDONLY, 0);
        pid = DPSpawnDisclaimed(argv, @[ [@"CFFIXED_USER_HOME=" stringByAppendingString:data] ], &files);
        posix_spawn_file_actions_destroy(&files);
    }
    if (childIn >= 0 && childIn != toHelper[0]) close(childIn);
    if (childOut >= 0 && childOut != fromHelper[1]) close(childOut);
    return pid;
}

static BOOL hasWindowOnScreen(pid_t pid) {
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *window in windows)
        if ([window[(id)kCGWindowOwnerPID] intValue] == pid && [window[(id)kCGWindowLayer] intValue] == 0) return YES;
    return NO;
}

typedef NS_ENUM(int, DPStartup) { DPStartupReady, DPStartupSignedOut, DPStartupFailed };

static DPStartup waitForStartupTab(pid_t pid, int seconds, NSString **targetId, NSNumber **windowId) {
    for (int tries = 0, tablessWindow = 0; tries < seconds * 4; tries++, usleep(250000)) {
        NSDictionary *targets = send(@"Target.getTargets", nil, nil);
        if (!targets) return DPStartupFailed;
        for (NSDictionary *target in asArray(asDictionary(targets[@"result"])[@"targetInfos"])) {
            if (![target isKindOfClass:NSDictionary.class] || ![target[@"type"] isEqual:@"page"]) continue;
            NSString *tid = asString(target[@"targetId"]);
            if (!tid) continue;
            NSDictionary *window = asDictionary(send(@"Browser.getWindowForTarget", @{ @"targetId" : tid }, nil)[@"result"]);
            if (![asDictionary(window[@"bounds"])[@"width"] intValue] || !window[@"windowId"]) continue;
            *targetId = tid;
            *windowId = window[@"windowId"];
            return DPStartupReady;
        }
        tablessWindow = hasWindowOnScreen(pid) ? tablessWindow + 1 : 0;
        if (tablessWindow == 8) return DPStartupSignedOut;
    }
    return DPStartupFailed;
}

static NSString *pageHTML(NSString *title, NSString *detail, NSString *site) {
    NSString *html = [NSString stringWithFormat:
        @"<!doctype html><meta name=color-scheme content='light dark'><title>Passkey</title>"
         "<style>html,body{height:100%%;margin:0}body{display:grid;place-items:center;text-align:center;font:13px -apple-system,sans-serif;"
         "background:Canvas;color:CanvasText}b{display:block;font-size:15px;margin-bottom:6px}p{margin:0;opacity:.6}</style>"
         "<div><b>%@</b><p>%@</p></div>", title, detail];
    return site ? [html stringByReplacingOccurrencesOfString:@"{site}" withString:site] : html;
}

static NSString *pageScript(NSString *title, NSString *detail) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[ pageHTML(title, detail, nil) ] options:0 error:nil];
    return [NSString stringWithFormat:@"(() => { const h = %@[0].replace('{site}', location.host);"
                                       " try { document.open(); document.write(h); document.close(); }"
                                       " catch { document.documentElement.replaceWith(document.importNode(new DOMParser().parseFromString(h, 'text/html').documentElement, true)); } })()",
                                      [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
}

static NSString *originOfURL(NSString *url) {
    if (![url isKindOfClass:NSString.class]) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    NSString *scheme = parts.scheme.lowercaseString, *host = parts.host.lowercaseString;
    if (!scheme.length || !host.length) return nil;
    NSNumber *port = parts.port;
    if (port && (([scheme isEqualToString:@"https"] && port.intValue == 443) || ([scheme isEqualToString:@"http"] && port.intValue == 80)))
        port = nil;
    if ([host containsString:@":"] && ![host hasPrefix:@"["]) host = [NSString stringWithFormat:@"[%@]", host];
    return port ? [NSString stringWithFormat:@"%@://%@:%@", scheme, host, port]
                : [NSString stringWithFormat:@"%@://%@", scheme, host];
}

static NSArray<NSString *> *candidatePaths(NSString *pagePath) {
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObjects:@"/robots.txt", @"/.well-known/webauthn", @"/", nil];
    if ([pagePath isKindOfClass:NSString.class] && [pagePath hasPrefix:@"/"]
        && ![pagePath containsString:@"?"] && ![pagePath containsString:@"#"] && ![paths containsObject:pagePath])
        [paths addObject:pagePath];
    return paths;
}

static BOOL isTLSError(NSString *errorText) {
    return [errorText isKindOfClass:NSString.class]
        && ([errorText containsString:@"ERR_CERT_"] || [errorText containsString:@"ERR_SSL_"]);
}

static NSString *navigationError(NSDictionary *navigation) { return asString(asDictionary(navigation[@"result"])[@"errorText"]); }

static BOOL atOrigin(NSString *session, NSString *origin, void (^onEvent)(NSDictionary *event)) {
    for (int tries = 0; tries < 50; tries++, usleep(100000)) {
        NSArray *state = evaluateWithEvents(session, @"[location.origin, document.readyState]", onEvent);
        if (!state) {
            if (!gFromHelper || feof(gFromHelper)) return NO;
            continue;
        }
        if (![state isKindOfClass:NSArray.class] || state.count < 2) return NO;
        if (![originOfURL(state.firstObject) isEqualToString:origin]) return NO;
        if ([state.lastObject isEqual:@"complete"]) return YES;
    }
    return NO;
}

static BOOL openOrigin(NSString *session, NSString *origin, NSString *pagePath) {
    NSString *expectedOrigin = originOfURL(origin);
    if (!expectedOrigin || (![expectedOrigin hasPrefix:@"https://"] && ![expectedOrigin hasPrefix:@"http://"])) return NO;

    send(@"Page.setBypassCSP", @{ @"enabled" : @YES }, session);
    send(@"Emulation.setScriptExecutionDisabled", @{ @"value" : @YES }, session);
    send(@"Fetch.enable", @{ @"patterns" : @[ @{ @"urlPattern" : @"*", @"requestStage" : @"Request" } ] }, session);

    __block BOOL sawCrossOriginRedirect = NO;
    __block BOOL sawServerResponse = NO;
    __block BOOL synthetic = NO;
    NSMutableSet<NSString *> *originRequestIds = [NSMutableSet set];
    NSRange schemeEnd = [expectedOrigin rangeOfString:@"://"];
    NSString *site = schemeEnd.location != NSNotFound ? [expectedOrigin substringFromIndex:NSMaxRange(schemeEnd)] : expectedOrigin;
    NSString *syntheticBody = [[pageHTML(@"Use your passkey for {site}",
                                         @"DiaTweaks opened this window to reach Apple Passwords. It closes by itself.",
                                         site) dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];

    void (^onEvent)(NSDictionary *) = ^(NSDictionary *event) {
        if (![event[@"method"] isEqualToString:@"Fetch.requestPaused"]) return;
        NSDictionary *params = asDictionary(event[@"params"]);
        NSString *requestId = asString(params[@"requestId"]);
        NSString *url = asString(asDictionary(params[@"request"])[@"url"]);
        NSString *type = asString(params[@"resourceType"]);
        if (!requestId) return;
        if ([type isEqualToString:@"Document"] && [originOfURL(url) isEqualToString:expectedOrigin]) {
            if (synthetic) {
                writeCDP(@"Fetch.fulfillRequest", @{
                    @"requestId" : requestId,
                    @"responseCode" : @200,
                    @"responseHeaders" : @[ @{ @"name" : @"Content-Type", @"value" : @"text/html; charset=utf-8" } ],
                    @"body" : syntheticBody,
                }, session);
            } else {
                [originRequestIds addObject:requestId];
                writeCDP(@"Fetch.continueRequest", @{ @"requestId" : requestId }, session);
            }
            return;
        }
        NSString *fromId = asString(params[@"redirectedRequestId"]);
        if ([type isEqualToString:@"Document"] && fromId && [originRequestIds containsObject:fromId])
            sawCrossOriginRedirect = YES;
        writeCDP(@"Fetch.failRequest", @{ @"requestId" : requestId, @"errorReason" : @"Aborted" }, session);
    };

    BOOL landed = NO;
    BOOL sawTLSError = NO;
    for (NSString *path in candidatePaths(pagePath)) {
        NSDictionary *nav = sendWithEvents(@"Page.navigate", @{ @"url" : [expectedOrigin stringByAppendingString:path] }, session, onEvent);
        if (!nav) break;
        NSString *errorText = navigationError(nav);
        if (isTLSError(errorText)) {
            sawTLSError = YES;
            break;
        }
        if (!errorText.length || [errorText isEqualToString:@"net::ERR_HTTP_RESPONSE_CODE_FAILURE"])
            sawServerResponse = YES;
        if (!errorText.length && atOrigin(session, expectedOrigin, onEvent)) {
            landed = YES;
            break;
        }
    }

    if (!landed && !sawTLSError && (sawCrossOriginRedirect || sawServerResponse)) {
        synthetic = YES;
        NSDictionary *nav = sendWithEvents(@"Page.navigate", @{ @"url" : [expectedOrigin stringByAppendingString:@"/"] }, session, onEvent);
        if (nav && !navigationError(nav).length) landed = atOrigin(session, expectedOrigin, onEvent);
    }

    if (landed && !synthetic)
        evaluateWithEvents(session, pageScript(@"Use your passkey for {site}",
                                               @"DiaTweaks opened this window to reach Apple Passwords. It closes by itself."), onEvent);

    send(@"Fetch.disable", nil, session);
    send(@"Emulation.setScriptExecutionDisabled", @{ @"value" : @NO }, session);
    return landed;
}

// Only the frontmost app can bring another forward, and that's Dia.
static void tellDia(NSString *what, pid_t helper) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:[@"com.diapatches.passkeys." stringByAppendingString:what]
                                                                 object:@(helper).stringValue
                                                               userInfo:nil
                                                     deliverImmediately:YES];
}

static NSDictionary *runInHelper(pid_t pid, NSString *kind, NSString *origin, NSString *path, id options) {
    if (![kind isKindOfClass:NSString.class] || ![origin isKindOfClass:NSString.class] || ![options isKindOfClass:NSDictionary.class])
        return failure(@"Invalid passkey request.");
    NSString *targetId;
    NSNumber *windowId;
    DPStartup startup = waitForStartupTab(pid, 60, &targetId, &windowId);
    if (startup == DPStartupSignedOut) {
        tellDia(@"signIn", pid);
        startup = waitForStartupTab(pid, 600, &targetId, &windowId);
    }
    if (startup != DPStartupReady || !targetId || !windowId) return failure(@"The passkey copy of Dia didn't open.");

    send(@"Browser.setWindowBounds", @{ @"windowId" : windowId, @"bounds" : sheetBounds() }, nil);
    NSDictionary *attached = send(@"Target.attachToTarget", @{ @"targetId" : targetId, @"flatten" : @YES }, nil);
    NSString *session = asString(asDictionary(attached[@"result"])[@"sessionId"]);
    if (!session) return failure(@"Couldn't connect to the passkey copy of Dia.");
    if (!openOrigin(session, origin, path)) return failure(@"Couldn't open the site in the passkey copy of Dia.");
    tellDia(@"show", pid);
    // WebAuthn refuses an unfocused page, and focus comes once Dia has brought the copy forward.
    for (int tries = 0; tries < 30; tries++, usleep(100000))
        if ([evaluate(session, @"document.hasFocus()") boolValue]) break;

    NSData *json = [NSJSONSerialization dataWithJSONObject:@{ @"kind" : kind, @"options" : options } options:0 error:nil];
    if (!json) return failure(@"Invalid passkey request.");
    NSString *script = [NSString stringWithFormat:@"(async ({ kind, options }) => {"
                                                    "  const signal = AbortSignal.timeout(Math.min(options.timeout || 300000, 600000));"
                                                    "  try {"
                                                    "    const credential = kind === 'create'"
                                                    "      ? await navigator.credentials.create({ publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options), signal })"
                                                    "      : await navigator.credentials.get({ publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(options), signal });"
                                                    "    return { credential: credential.toJSON() };"
                                                    "  } catch (e) { return { error: { name: e.name === 'TimeoutError' ? 'NotAllowedError' : e.name, message: e.message } }; }"
                                                    "})(%@)",
                                                   [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    id result = evaluate(session, script);
    if (![result isKindOfClass:NSDictionary.class]) return failure(@"The passkey copy of Dia quit before answering.");
    if (result[@"credential"]) evaluate(session, pageScript(@"Done", @"This window closes in a moment. Thanks for waiting."));
    return result;
}

static void closePair(int fds[2]) {
    for (int i = 0; i < 2; i++) {
        if (fds[i] >= 0) close(fds[i]);
        fds[i] = -1;
    }
}

static void closeHelperStreams(void) {
    if (gFromHelper) fclose(gFromHelper);
    if (gToHelper) fclose(gToHelper);
    gFromHelper = gToHelper = NULL;
}

static void killHelper(pid_t pid) {
    pthread_mutex_lock(&gHelperLock);
    gHelper = 0;
    kill(pid, SIGKILL);
    pthread_mutex_unlock(&gHelperLock);
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
}

static int openPasskeyLock(NSString *home) {
    if (!home.length) return -1;
    if (![NSFileManager.defaultManager createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:nil]) return -1;
    return open([home stringByAppendingPathComponent:@"passkey-helper.lock"].fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
}

static BOOL lockPasskeyHelper(int lock) {
    while (flock(lock, LOCK_EX | LOCK_NB) != 0) {
        if (errno == EINTR) continue;
        if (errno != EWOULDBLOCK || gCancelled) return NO;
        usleep(50000);
    }
    return !gCancelled;
}

int DPRunPasskeyHost(NSString *home) {
    NSDictionary *request = readMessageFrom(stdin);
    if (!validRequest(request)) return 1;
    pthread_t watcher;
    if (pthread_create(&watcher, NULL, watchForCancel, NULL) == 0) pthread_detach(watcher);

    int lock = openPasskeyLock(home);
    if (lock < 0) return bail(@"Couldn't open the passkey lock file.", 1);
    if (!lockPasskeyHelper(lock)) {
        close(lock);
        if (gCancelled) return bail(@"The passkey request was cancelled.", 0);
        return bail(@"Couldn't lock the passkey helper.", 1);
    }

    int toHelper[2] = { -1, -1 }, fromHelper[2] = { -1, -1 };
    pid_t pid = 0;
    if (pipe(toHelper) != 0 || pipe(fromHelper) != 0 || !(pid = launchHelper(home, toHelper, fromHelper))) {
        closePair(toHelper);
        closePair(fromHelper);
        close(lock);
        return bail(@"Couldn't start the passkey copy of Dia.", 1);
    }
    pthread_mutex_lock(&gHelperLock);
    gHelper = pid;
    if (gCancelled) kill(pid, SIGTERM);
    pthread_mutex_unlock(&gHelperLock);
    close(toHelper[0]);
    toHelper[0] = -1;
    close(fromHelper[1]);
    fromHelper[1] = -1;

    gFromHelper = fdopen(fromHelper[0], "r");
    if (gFromHelper) fromHelper[0] = -1;
    gToHelper = fdopen(toHelper[1], "w");
    if (gToHelper) toHelper[1] = -1;
    if (!gFromHelper || !gToHelper) {
        closeHelperStreams();
        closePair(toHelper);
        closePair(fromHelper);
        killHelper(pid);
        close(lock);
        return bail(@"Couldn't connect to the passkey copy of Dia.", 1);
    }

    NSDictionary *result = runInHelper(pid, request[@"kind"], request[@"origin"], request[@"path"], request[@"options"]);
    // Dia kills this process once it has the answer, so the copy has to quit before then.
    send(@"Browser.close", nil, nil);
    BOOL exited = NO;
    for (int i = 0; i < 50 && !exited; i++) {
        pthread_mutex_lock(&gHelperLock);
        pid_t w = waitpid(pid, NULL, WNOHANG);
        exited = w == pid || (w < 0 && errno == ECHILD);
        if (exited) gHelper = 0;
        pthread_mutex_unlock(&gHelperLock);
        if (!exited) usleep(100000);
    }
    if (!exited) killHelper(pid);
    closeHelperStreams();
    close(lock);
    DPForgetApp([home stringByAppendingPathComponent:@"pristine/Dia.app"]);
    writeMessage(result);
    return 0;
}

#import <Foundation/Foundation.h>
#import <pthread.h>
#import <unistd.h>

void DPForgetApp(NSString *path) { (void)path; }

#import "diapatch/Passkeys.m"

typedef NS_ENUM(int, FakeSiteMode) {
    FakeSiteNormal,
    FakeSiteDuo,
    FakeSitePagePathOnly,
    FakeSiteAllCrossOriginRedirect,
    FakeSitePrefixSpoofRedirect,
    FakeSiteBrokenTLS,
    FakeSiteUnreachable,
};

@interface FakeCDPState : NSObject
@property (nonatomic) FakeSiteMode mode;
@property (nonatomic) int serverReadFD;
@property (nonatomic) int serverWriteFD;
@property (nonatomic, strong) NSMutableArray<NSString *> *navigatedURLs;
@property (nonatomic, strong) NSMutableArray<NSString *> *abortedURLs;
@property (nonatomic, strong) NSMutableArray<NSString *> *fulfilledURLs;
@property (nonatomic, copy) NSString *fulfilledBody;
@property (nonatomic, copy) NSString *currentOrigin;
@property (nonatomic) BOOL bypassCSP;
@property (nonatomic) BOOL scriptsDisabledDuringNav;
@property (nonatomic) BOOL scriptsDisabledAtEnd;
@property (nonatomic) BOOL fetchEnabledAtEnd;
@property (nonatomic) BOOL wrotePromptPage;
@end

@implementation FakeCDPState
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _navigatedURLs = [NSMutableArray array];
    _abortedURLs = [NSMutableArray array];
    _fulfilledURLs = [NSMutableArray array];
    _currentOrigin = @"https://www.diabrowser.com";
    return self;
}
@end

static void serverSend(FILE *out, NSDictionary *msg) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
    fwrite(data.bytes, 1, data.length, out);
    fputc(0, out);
    fflush(out);
}

static NSDictionary *serverRead(FILE *in) {
    NSMutableData *data = [NSMutableData data];
    for (int c; (c = fgetc(in)) != 0;) {
        if (c == EOF) return nil;
        [data appendBytes:&(char){ c } length:1];
    }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

// Simulates Chromium's Fetch + Page.navigate + Runtime.evaluate CDP interaction.
static void *fakeCDPThread(void *ctx) {
    @autoreleasepool {
        FakeCDPState *s = (__bridge FakeCDPState *)ctx;
        FILE *in = fdopen(s.serverReadFD, "r");
        FILE *out = fdopen(s.serverWriteFD, "w");
        BOOL fetchEnabled = NO;
        BOOL scriptsDisabled = NO;
        __block int nextReqId = 0;

        for (NSDictionary *msg; (msg = serverRead(in));) {
            NSNumber *msgId = msg[@"id"];
            NSString *method = msg[@"method"];
            NSDictionary *params = msg[@"params"];
            NSString *session = msg[@"sessionId"];

            if ([method isEqualToString:@"Page.setBypassCSP"]) {
                s.bypassCSP = [params[@"enabled"] boolValue];
                serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{} });
            } else if ([method isEqualToString:@"Emulation.setScriptExecutionDisabled"]) {
                scriptsDisabled = [params[@"value"] boolValue];
                s.scriptsDisabledAtEnd = scriptsDisabled;
                serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{} });
            } else if ([method isEqualToString:@"Fetch.enable"]) {
                fetchEnabled = YES;
                s.fetchEnabledAtEnd = YES;
                serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{} });
            } else if ([method isEqualToString:@"Fetch.disable"]) {
                fetchEnabled = NO;
                s.fetchEnabledAtEnd = NO;
                serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{} });
            } else if ([method isEqualToString:@"Page.navigate"]) {
                NSString *url = params[@"url"];
                [s.navigatedURLs addObject:url];
                if (scriptsDisabled) s.scriptsDisabledDuringNav = YES;

                NSDictionary * (^pauseRequest)(NSString *, NSString *, NSString *) = ^NSDictionary *(NSString *reqUrl, NSString *rtype, NSString *redirFrom) {
                    NSString *reqId = [NSString stringWithFormat:@"req-%d", ++nextReqId];
                    NSMutableDictionary *evParams = [@{
                        @"requestId" : reqId,
                        @"request" : @{ @"url" : reqUrl },
                        @"resourceType" : rtype,
                    } mutableCopy];
                    if (redirFrom) evParams[@"redirectedRequestId"] = redirFrom;
                    serverSend(out, @{ @"method" : @"Fetch.requestPaused", @"sessionId" : session, @"params" : evParams });
                    NSDictionary *action = serverRead(in);
                    serverSend(out, @{ @"id" : action[@"id"], @"sessionId" : session, @"result" : @{} });
                    return @{ @"reqId" : reqId, @"action" : action };
                };

                if (!fetchEnabled) {
                    s.currentOrigin = originOfURL(url);
                    serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1" } });
                    continue;
                }

                NSDictionary *first = pauseRequest(url, @"Document", nil);
                NSString *firstMethod = first[@"action"][@"method"];
                if ([firstMethod isEqualToString:@"Fetch.fulfillRequest"]) {
                    [s.fulfilledURLs addObject:url];
                    NSString *b64 = first[@"action"][@"params"][@"body"];
                    if (b64) {
                        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
                        s.fulfilledBody = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
                    }
                    s.currentOrigin = originOfURL(url);
                    serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1" } });
                    continue;
                }
                if ([firstMethod isEqualToString:@"Fetch.failRequest"]) {
                    [s.abortedURLs addObject:url];
                    serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1", @"errorText" : @"net::ERR_ABORTED" } });
                    continue;
                }

                if (s.mode == FakeSiteBrokenTLS) {
                    serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1", @"errorText" : @"net::ERR_CERT_AUTHORITY_INVALID" } });
                    continue;
                }
                if (s.mode == FakeSiteUnreachable) {
                    serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1", @"errorText" : @"net::ERR_NAME_NOT_RESOLVED" } });
                    continue;
                }

                NSString *redirectTarget = nil;
                if (s.mode == FakeSiteDuo && ([url hasSuffix:@"/robots.txt"] || [url hasSuffix:@"/"])) {
                    redirectTarget = @"https://duo.com/";
                } else if (s.mode == FakeSitePagePathOnly && ![url hasSuffix:@"/frame/v4/auth/prompt"]) {
                    redirectTarget = @"https://duo.com/";
                } else if (s.mode == FakeSiteAllCrossOriginRedirect) {
                    redirectTarget = @"https://sso.other.example/login";
                } else if (s.mode == FakeSitePrefixSpoofRedirect) {
                    redirectTarget = @"https://duo.com.evil.example/";
                }

                if (redirectTarget) {
                    NSDictionary *hop = pauseRequest(redirectTarget, @"Document", first[@"reqId"]);
                    if ([hop[@"action"][@"method"] isEqualToString:@"Fetch.failRequest"]) {
                        [s.abortedURLs addObject:redirectTarget];
                        serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1", @"errorText" : @"net::ERR_ABORTED" } });
                    } else {
                        s.currentOrigin = originOfURL(redirectTarget);
                        serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1" } });
                    }
                    continue;
                }

                // Same-origin response committed (also fire a subresource request to ensure scripts are blocked).
                NSDictionary *sub = pauseRequest([originOfURL(url) stringByAppendingString:@"/app.js"], @"Script", nil);
                if ([sub[@"action"][@"method"] isEqualToString:@"Fetch.failRequest"])
                    [s.abortedURLs addObject:[originOfURL(url) stringByAppendingString:@"/app.js"]];

                s.currentOrigin = originOfURL(url);
                serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"frameId" : @"F1" } });
            } else if ([method isEqualToString:@"Runtime.evaluate"]) {
                NSString *expr = params[@"expression"];
                id value = NSNull.null;
                if ([expr isEqualToString:@"[location.origin, document.readyState]"]) {
                    value = @[ s.currentOrigin ?: @"null", @"complete" ];
                } else if ([expr containsString:@"Use your passkey for"]) {
                    s.wrotePromptPage = YES;
                    value = @YES;
                }
                serverSend(out, @{ @"id" : msgId, @"sessionId" : session, @"result" : @{ @"result" : @{ @"value" : value } } });
            }
        }
        fclose(in);
        fclose(out);
    }
    return NULL;
}

static FakeCDPState *runOpenOriginScenario(FakeSiteMode mode, NSString *origin, NSString *pagePath, BOOL *outLanded) {
    int c2s[2], s2c[2];
    NSCAssert(pipe(c2s) == 0 && pipe(s2c) == 0, @"pipes");

    FakeCDPState *state = [FakeCDPState new];
    state.mode = mode;
    state.serverReadFD = c2s[0];
    state.serverWriteFD = s2c[1];

    gToHelper = fdopen(c2s[1], "w");
    gFromHelper = fdopen(s2c[0], "r");

    pthread_t th;
    NSCAssert(pthread_create(&th, NULL, fakeCDPThread, (__bridge void *)state) == 0, @"thread");

    *outLanded = openOrigin(@"S1", origin, pagePath);

    fclose(gToHelper);
    gToHelper = NULL;
    pthread_join(th, NULL);
    fclose(gFromHelper);
    gFromHelper = NULL;
    return state;
}

static void testOriginAndPathHelpers(void) {
    NSCAssert([originOfURL(@"https://api-4b6bfd4c.duosecurity.com/robots.txt") isEqualToString:@"https://api-4b6bfd4c.duosecurity.com"], @"basic origin");
    NSCAssert([originOfURL(@"https://API-4B6BFD4C.DuoSecurity.COM:443/login") isEqualToString:@"https://api-4b6bfd4c.duosecurity.com"], @"lowercase + default https port");
    NSCAssert([originOfURL(@"http://localhost:80/foo") isEqualToString:@"http://localhost"], @"default http port");
    NSCAssert([originOfURL(@"https://example.com:8443/path") isEqualToString:@"https://example.com:8443"], @"non-default port preserved");
    NSCAssert([originOfURL(@"https://[::1]:8443/path") isEqualToString:@"https://[::1]:8443"], @"IPv6 origin");
    NSCAssert(![originOfURL(@"https://duo.com.evil.com/") isEqualToString:originOfURL(@"https://duo.com")], @"prefix spoof rejected");
    NSCAssert(originOfURL(@"about:blank") == nil, @"about:blank has no origin");
    NSCAssert(originOfURL(@"null") == nil, @"opaque null origin rejected");

    NSArray *base = @[ @"/robots.txt", @"/.well-known/webauthn", @"/" ];
    NSCAssert([candidatePaths(nil) isEqual:base], @"nil pagePath");
    NSCAssert([candidatePaths(@"/") isEqual:base], @"root deduplicated");
    NSCAssert([candidatePaths(@"/frame/v4/auth/prompt") isEqual:[base arrayByAddingObject:@"/frame/v4/auth/prompt"]], @"custom pagePath appended");
    NSCAssert([candidatePaths(@"/frame/v4/auth/prompt?sid=secret") isEqual:base], @"query string path rejected");
    NSCAssert([candidatePaths(@"relative") isEqual:base], @"relative path rejected");
}

static void testAllowSyntheticOriginPrefs(void) {
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"passkeys-test-%@", NSUUID.UUID.UUIDString]];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];

    allowSyntheticOrigin(tmp);
    NSDictionary *def = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[tmp stringByAppendingPathComponent:@"Default/Preferences"]] options:0 error:nil];
    NSCAssert([def[@"webauthn"][@"allow_with_broken_certs"] isEqual:@YES], @"Default pref written");

    NSString *p2 = [tmp stringByAppendingPathComponent:@"Profile 2"];
    NSString *p3 = [tmp stringByAppendingPathComponent:@"Profile 3"];
    [fm createDirectoryAtPath:p2 withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:p3 withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *existing = [NSJSONSerialization dataWithJSONObject:@{ @"profile" : @{ @"name" : @"School" }, @"webauthn" : @{ @"touchid" : @"secret" } } options:0 error:nil];
    [existing writeToFile:[p2 stringByAppendingPathComponent:@"Preferences"] atomically:YES];
    [@"not-json" writeToFile:[p3 stringByAppendingPathComponent:@"Preferences"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    allowSyntheticOrigin(tmp);
    NSDictionary *p2Prefs = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[p2 stringByAppendingPathComponent:@"Preferences"]] options:0 error:nil];
    NSCAssert([p2Prefs[@"profile"][@"name"] isEqual:@"School"], @"Profile 2 existing keys preserved");
    NSCAssert([p2Prefs[@"webauthn"][@"touchid"] isEqual:@"secret"], @"Profile 2 existing webauthn keys preserved");
    NSCAssert([p2Prefs[@"webauthn"][@"allow_with_broken_certs"] isEqual:@YES], @"Profile 2 allow_with_broken_certs set");
    NSString *p3Raw = [NSString stringWithContentsOfFile:[p3 stringByAppendingPathComponent:@"Preferences"] encoding:NSUTF8StringEncoding error:nil];
    NSCAssert([p3Raw isEqualToString:@"not-json"], @"Corrupt Preferences file left intact");

    [fm removeItemAtPath:tmp error:nil];
}

int main(void) {
    @autoreleasepool {
        testOriginAndPathHelpers();
        testAllowSyntheticOriginPrefs();

        BOOL landed = NO;

        FakeCDPState *s1 = runOpenOriginScenario(FakeSiteNormal, @"https://github.com", @"/login", &landed);
        NSCAssert(landed, @"normal site lands");
        NSCAssert([s1.navigatedURLs isEqual:@[ @"https://github.com/robots.txt" ]], @"stops after robots.txt: %@", s1.navigatedURLs);
        NSCAssert(s1.fulfilledURLs.count == 0, @"no synthetic fallback needed");
        NSCAssert(s1.wrotePromptPage && s1.bypassCSP && s1.scriptsDisabledDuringNav && !s1.scriptsDisabledAtEnd && !s1.fetchEnabledAtEnd, @"clean CDP teardown");

        FakeCDPState *s2 = runOpenOriginScenario(FakeSiteDuo, @"https://api-4b6bfd4c.duosecurity.com", @"/frame/v4/auth/prompt", &landed);
        NSArray *duoExpectedNav = @[ @"https://api-4b6bfd4c.duosecurity.com/robots.txt", @"https://api-4b6bfd4c.duosecurity.com/.well-known/webauthn" ];
        NSCAssert(landed, @"Duo lands at real origin");
        NSCAssert([s2.currentOrigin isEqualToString:@"https://api-4b6bfd4c.duosecurity.com"], @"never stays on duo.com");
        NSCAssert([s2.navigatedURLs isEqual:duoExpectedNav], @"Duo navigation order: %@", s2.navigatedURLs);
        NSCAssert([s2.abortedURLs containsObject:@"https://duo.com/"], @"cross-origin redirect to duo.com aborted before fetch");
        NSCAssert([s2.abortedURLs containsObject:@"https://api-4b6bfd4c.duosecurity.com/app.js"], @"subresource scripts aborted");
        NSCAssert(s2.fulfilledURLs.count == 0, @"Duo uses real TLS, no synthetic needed");
        NSCAssert(s2.wrotePromptPage && !s2.scriptsDisabledAtEnd && !s2.fetchEnabledAtEnd, @"Duo clean teardown");

        FakeCDPState *s3 = runOpenOriginScenario(FakeSitePagePathOnly, @"https://api-4b6bfd4c.duosecurity.com", @"/frame/v4/auth/prompt", &landed);
        NSCAssert(landed, @"pagePath fallback lands");
        NSCAssert([s3.navigatedURLs.lastObject isEqualToString:@"https://api-4b6bfd4c.duosecurity.com/frame/v4/auth/prompt"], @"reached pagePath");
        NSCAssert(s3.fulfilledURLs.count == 0, @"real TLS pagePath succeeded");

        FakeCDPState *s4 = runOpenOriginScenario(FakeSiteAllCrossOriginRedirect, @"https://portal.corp.example", @"/settings", &landed);
        NSCAssert(landed, @"all-redirect portal lands via synthetic origin");
        NSCAssert([s4.currentOrigin isEqualToString:@"https://portal.corp.example"], @"landed on portal origin");
        NSCAssert([s4.fulfilledURLs isEqual:@[ @"https://portal.corp.example/" ]], @"synthesized at portal origin");
        NSCAssert([s4.fulfilledBody containsString:@"Use your passkey for portal.corp.example"], @"prompt body shows real host");
        NSCAssert(!s4.wrotePromptPage && !s4.scriptsDisabledAtEnd && !s4.fetchEnabledAtEnd, @"synthetic skips redundant document.write and tears down cleanly");

        FakeCDPState *s5 = runOpenOriginScenario(FakeSitePrefixSpoofRedirect, @"https://duo.com", nil, &landed);
        NSCAssert(landed, @"prefix spoof does not fool origin check");
        NSCAssert([s5.abortedURLs containsObject:@"https://duo.com.evil.example/"], @"prefix-spoofed host aborted");
        NSCAssert([s5.currentOrigin isEqualToString:@"https://duo.com"], @"stays at duo.com");

        FakeCDPState *s6 = runOpenOriginScenario(FakeSiteBrokenTLS, @"https://badssl.example", @"/login", &landed);
        NSCAssert(!landed, @"broken TLS fails");
        NSCAssert(s6.navigatedURLs.count == 1, @"stops on first TLS error");
        NSCAssert(s6.fulfilledURLs.count == 0, @"never synthesizes past broken TLS");
        NSCAssert(!s6.scriptsDisabledAtEnd && !s6.fetchEnabledAtEnd, @"broken TLS tears down cleanly");

        FakeCDPState *s7 = runOpenOriginScenario(FakeSiteUnreachable, @"https://offline.example", @"/login", &landed);
        NSCAssert(!landed, @"unreachable fails");
        NSCAssert(s7.fulfilledURLs.count == 0, @"never synthesizes unreachable host");

        FakeCDPState *s8 = runOpenOriginScenario(FakeSiteNormal, @"chrome://settings", nil, &landed);
        NSCAssert(!landed && s8.navigatedURLs.count == 0, @"non-http(s) origin rejected");

        puts("PASS: passkeys origin navigation, Duo redirects, and synthetic fallback");
    }
    return 0;
}

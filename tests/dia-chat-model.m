#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "StdPatch/StdPatch.h"
#import "Patches/AgentTransport/AgentRelay.h"
#import "Patches/AgentTransport/AgentSocket.h"
#import "Patches/AgentTransport/AgentWriter.h"
#include <mach-o/dyld.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <signal.h>
#include <spawn.h>
#include <stdatomic.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>

extern char **environ;

// What the tweak needs from the rest of DiaTweaks, stood in so the real transport, request rewrite and patch logic run unchanged.
extern DPPatch DPDiaChatModel, DPDiaChatModelFallback, DPTurnOffAI;
void DPApplyDiaChatModel(DPPatch *patch);
NSData *DPChatAgentRequest(NSData *line, NSString *model);
NSString *DPSelectedDiaChatModel(NSString *choice, NSArray<NSString *> *models, BOOL fallback);
BOOL DPValidChatModel(NSString *model);
BOOL DPChatModelNeedsRelaunch(DPPatch *patch);
BOOL DPChatModelTakeRelaunchOffer(DPPatch *patch);

NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
static NSString *gChoice;
static NSArray<NSString *> *gModels;
NSString *DPChoice(DPPatch *patch) { return gChoice ?: patch->defaultChoice; }
void DPOnLaunch(void (^block)(void)) {}
NSArray<NSString *> *DPInstalledChatModels(void) { return gModels; }
void DPInstallDiaModelOverview(void) {}
void DPRefreshDiaModelPicker(void) {}
NSString *DPVerifyDiaModelOverview(DPPatch *patch) { return nil; }
DP_PATCH(DPTurnOffAI) { .key = @"turnOffAI" };
BOOL DPTesting = YES;
static BOOL gSaved = YES;
BOOL DPSavedOn(DPPatch *patch) { return gSaved; }
void DPHandOffAndQuit(NSArray<NSString *> *args) { fputs("FAIL: the test must never relaunch\n", stderr); exit(1); }

#define CHECK(condition, ...) do { if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n  ", __LINE__, #condition); fprintf(stderr, "" __VA_ARGS__); fputc('\n', stderr); exit(1); } } while (0)

static NSData *Bytes(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *JSON(id object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }
static id Parse(NSData *data) { return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; }

static NSDictionary *Payload(NSString *model, NSString *agent, id env) {
    NSMutableDictionary *settings = [@{ @"model": model } mutableCopy];
    if (env) settings[@"env"] = env;
    return @{ @"agent": agent, @"prompt": @"Hello — ünïcode ☃ \"quoted\" \\ /", @"context_id": @"c1",
        @"spec_override": @{ @"settings": settings, @"keep": @[ @1, @2.5, @YES, NSNull.null ] } };
}

static NSData *Frame(NSString *model, NSString *agent, BOOL nested, id env) {
    NSDictionary *payload = Payload(model, agent, env);
    if (nested) return JSON(@{ @"type": @"RUN", @"msg": @"m1", @"payload": payload });
    NSMutableDictionary *flat = [payload mutableCopy];
    flat[@"type"] = @"RUN";
    flat[@"msg"] = @"m1";
    return JSON(flat);
}

static NSString *ModelIn(NSData *frame) {
    NSDictionary *message = Parse(frame);
    NSDictionary *run = message[@"payload"] ?: message;
    return run[@"spec_override"][@"settings"][@"model"];
}

static NSData *InvalidUTF8(void) {
    static const char frame[] = "{\"type\":\"RUN\",\"payload\":{\"agent\":\"default\",\"prompt\":\"\xff\xfe\",\"spec_override\":{\"settings\":{\"model\":\"m\"}}}}";
    return [NSData dataWithBytes:frame length:sizeof frame - 1];
}

static void TestRequestRewrite(void) {
    for (NSNumber *nested in @[ @YES, @NO ]) {
        NSData *original = Frame(@"claude-haiku-5-5", @"default", nested.boolValue, @{ @"KEEP": @"yes" });
        NSData *out = DPChatAgentRequest(original, @"claude-opus-5-5");
        NSDictionary *message = Parse(out), *run = message[@"payload"] ?: message;
        CHECK([ModelIn(out) isEqual:@"claude-opus-5-5"], "model must change (nested=%d)", nested.boolValue);
        CHECK([run[@"spec_override"][@"settings"][@"env"][@"KEEP"] isEqual:@"yes"], "env kept");
        CHECK([run[@"spec_override"][@"settings"][@"env"][@"DIA_EXPLICIT_MODEL_SELECTION"] isEqual:@"true"], "explicit flag set");
        CHECK([run[@"prompt"] isEqual:@"Hello — ünïcode ☃ \"quoted\" \\ /"], "prompt must survive unchanged");
        CHECK([run[@"spec_override"][@"keep"] isEqual:(@[ @1, @2.5, @YES, NSNull.null ])], "other fields must survive");
        CHECK(!memchr(out.bytes, '\n', out.length), "frame must stay one line");
        CHECK([Parse(DPChatAgentRequest(out, @"claude-opus-5-5")) isEqual:Parse(out)], "rewriting twice changes nothing more");
        NSData *noEnv = DPChatAgentRequest(Frame(@"a", @"default", nested.boolValue, nil), @"b");
        CHECK([ModelIn(noEnv) isEqual:@"b"], "missing env is created");
    }
    NSData *keep = Frame(@"a", @"default", YES, nil);
    CHECK(DPChatAgentRequest(keep, nil) == keep, "no model leaves the frame object alone");
    NSData *other = Frame(@"a", @"clia-brief", YES, nil);
    CHECK(DPChatAgentRequest(other, @"b") == other, "other agents are untouched");
    NSMutableDictionary *notRun = [Parse(keep) mutableCopy];
    notRun[@"type"] = @"CANCEL";
    NSData *cancel = JSON(notRun);
    CHECK(DPChatAgentRequest(cancel, @"b") == cancel, "non-RUN frames are untouched");
    NSData *badEnv = Frame(@"a", @"default", YES, @"not a dict");
    CHECK(DPChatAgentRequest(badEnv, @"b") == badEnv, "unexpected env shape is untouched");
    NSData *badModel = JSON(@{ @"type": @"RUN", @"payload": @{ @"agent": @"default", @"prompt": @"p", @"spec_override": @{ @"settings": @{ @"model": @7 } } } });
    CHECK(DPChatAgentRequest(badModel, @"b") == badModel, "non-string model is untouched");
    NSData *noSpec = JSON(@{ @"type": @"RUN", @"payload": @{ @"agent": @"default", @"prompt": @"p", @"model": @"x" } });
    CHECK(DPChatAgentRequest(noSpec, @"b") == noSpec, "a run without spec_override is untouched");

    NSArray<NSData *> *hostile = @[
        [NSData data], Bytes(@"\n"), Bytes(@"{"), Bytes(@"null"), Bytes(@"[]"), Bytes(@"\"RUN\" spec_override model"),
        Bytes(@"{\"type\":\"RUN\",\"spec_override\":\"model\"}"),
        Bytes(@"{\"type\":\"RUN\",\"payload\":{\"agent\":\"default\",\"prompt\":\"\\ud800\",\"spec_override\":{\"settings\":{\"model\":\"m\"}}}}"),
        Bytes(@"{\"type\":\"RUN\",\"payload\":{\"agent\":\"default\",\"prompt\":\"p\",\"n\":1e999,\"spec_override\":{\"settings\":{\"model\":\"m\"}}}}"),
        InvalidUTF8(),
    ];
    for (NSData *bad in hostile) {
        NSData *out = DPChatAgentRequest(bad, @"b");
        CHECK([out isEqual:bad] || Parse(out), "hostile input must pass through or stay valid JSON");
    }
    NSMutableString *deep = [NSMutableString stringWithString:@"{\"type\":\"RUN\",\"spec_override\":\"model\",\"x\":"];
    for (int i = 0; i < 5000; i++) [deep appendString:@"["];
    NSData *deepData = Bytes(deep);
    CHECK(DPChatAgentRequest(deepData, @"b") == deepData, "deep nesting is untouched, not a crash");

    for (NSString *bad in @[ @"", @"has space", @"new\nline", @"tab\t", @"nul\0x", [@"" stringByPaddingToLength:300 withString:@"a" startingAtIndex:0] ])
        CHECK(!DPValidChatModel(bad), "invalid identifier accepted: %s", bad.UTF8String);
    for (NSString *good in @[ @"claude-sonnet-5-5", @"gpt-6.1-sol", @"another-model-v99[huge]", @"muse-spark-1.3-contributor" ])
        CHECK(DPValidChatModel(good), "valid identifier rejected: %s", good.UTF8String);
    CHECK(DPChatAgentRequest(keep, @"bad model") == keep, "an invalid saved choice is never sent");
    CHECK(!DPSelectedDiaChatModel(@"bad\nmodel", @[], NO), "an invalid saved choice stays native");
}

static void TestSelection(void) {
    NSArray *models = @[ @"claude-haiku-5-5", @"claude-opus-5-5" ];
    CHECK([DPSelectedDiaChatModel(@"claude-opus-5-5", models, YES) isEqual:@"claude-opus-5-5"], "listed model is kept");
    CHECK(!DPSelectedDiaChatModel(@"removed", models, YES), "unlisted model falls back");
    CHECK([DPSelectedDiaChatModel(@"removed", models, NO) isEqual:@"removed"], "fallback off keeps the saved model");
    CHECK(!DPSelectedDiaChatModel(@"removed", @[], YES), "empty catalog falls back");
    CHECK(!DPSelectedDiaChatModel(@"dia-default", models, NO) && !DPSelectedDiaChatModel(@"", models, NO) && !DPSelectedDiaChatModel(nil, models, NO), "default stays native");
}

// A connected pair: what the app writes comes out of `app`, what the agent writes comes out of `agent`.
typedef struct { int app, agent, relayClient, relayBackend; } Relay;

static Relay StartRelay(dispatch_semaphore_t *done) {
    int client[2], backend[2];
    CHECK(!socketpair(AF_UNIX, SOCK_STREAM, 0, client) && !socketpair(AF_UNIX, SOCK_STREAM, 0, backend), "socketpair");
    Relay relay = { client[0], backend[0], client[1], backend[1] };
    struct timeval timeout = { .tv_sec = 5 };
    setsockopt(relay.app, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    setsockopt(relay.agent, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    *done = dispatch_semaphore_create(0);
    dispatch_semaphore_t finished = *done;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DPRelayAgentConnection(relay.relayClient, relay.relayBackend);
        close(relay.relayClient);
        close(relay.relayBackend);
        dispatch_semaphore_signal(finished);
    });
    return relay;
}

static void StopRelay(Relay relay, dispatch_semaphore_t done) {
    close(relay.app);
    close(relay.agent);
    CHECK(!dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), "relay must end when both ends close");
}

static NSData *ReadExactly(int fd, size_t length) {
    NSMutableData *data = [NSMutableData new];
    char buffer[4096];
    while (data.length < length) {
        ssize_t got = read(fd, buffer, MIN(sizeof buffer, length - data.length));
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) break;
        [data appendBytes:buffer length:got];
    }
    return data;
}

static void WriteAll(int fd, NSData *data) {
    const char *bytes = data.bytes;
    size_t left = data.length;
    while (left) {
        ssize_t wrote = write(fd, bytes, left);
        if (wrote < 0 && errno == EINTR) continue;
        CHECK(wrote > 0, "write failed: %d", errno);
        bytes += wrote;
        left -= wrote;
    }
}

static NSData *Upper(NSData *line, DPAgentReply reply) {
    return Bytes([[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding].uppercaseString);
}

static void TestOffIsUntouched(void) {
    SEL launch = @selector(launchAndReturnError:);
    Class task = [NSTask new].class;
    IMP before = class_getMethodImplementation(task, launch);
    CHECK(!DPAgentFiltersActive() && !DPAgentTransportInstalled(), "nothing may be registered before the tweak is on");
    gModels = @[ @"claude-haiku-5-5" ];
    gChoice = @"claude-haiku-5-5";
    DPDiaChatModel.on = NO;
    DPApplyDiaChatModel(&DPDiaChatModel);
    DPSetAgentFilters(@"diaChatModel", nil, nil);
    CHECK(!DPAgentFiltersActive() && !DPAgentTransportInstalled(), "off must not register a filter or hook NSTask");
    CHECK(class_getMethodImplementation(task, launch) == before, "off must leave NSTask alone");
    CHECK(DPAgentFilters(YES).count == 0 && DPAgentFilterCount(NO) == 0, "off has no filters in either direction");

    DPTurnOffAI.on = YES;
    DPDiaChatModel.on = YES;
    DPApplyDiaChatModel(&DPDiaChatModel);
    CHECK(!DPAgentFiltersActive() && class_getMethodImplementation(task, launch) == before, "Turn Off AI must keep the tweak away from the socket");
    DPTurnOffAI.on = NO;
    DPDiaChatModel.on = NO;
}

static void TestPatchLifecycle(void) {
    NSData *request = Frame(@"claude-sonnet-5-5", @"default", YES, nil);
    gModels = @[ @"claude-haiku-5-5", @"claude-opus-5-5" ];
    gChoice = @"claude-opus-5-5";
    DPDiaChatModel.on = YES;
    DPDiaChatModelFallback.on = YES;
    DPApplyDiaChatModel(&DPDiaChatModel);
    CHECK(DPAgentFiltersActive() && DPAgentFilterCount(YES) == 1 && DPAgentFilterCount(NO) == 0, "on registers one request filter");
    CHECK(DPAgentTransportInstalled(), "on hooks the agent launch");
    DPAgentFilter filter = DPAgentFilters(YES).firstObject;
    CHECK([ModelIn(filter(request, ^(NSDictionary *m) {})) isEqual:@"claude-opus-5-5"], "the picked model is sent");

    gChoice = @"retired-model";
    DPApplyDiaChatModel(&DPDiaChatModel);
    filter = DPAgentFilters(YES).firstObject;
    CHECK(filter(request, ^(NSDictionary *m) {}) == request, "fallback on: a retired model leaves Dia's request alone");
    DPDiaChatModelFallback.on = NO;
    DPApplyDiaChatModel(&DPDiaChatModel);
    filter = DPAgentFilters(YES).firstObject;
    CHECK([ModelIn(filter(request, ^(NSDictionary *m) {})) isEqual:@"retired-model"], "fallback off: the saved model is still sent");
    DPDiaChatModelFallback.on = YES;

    gChoice = @"dia-default";
    DPApplyDiaChatModel(&DPDiaChatModel);
    filter = DPAgentFilters(YES).firstObject;
    CHECK([ModelIn(filter(request, ^(NSDictionary *m) {})) isEqual:@"claude-sonnet-5-5"], "Dia Default sends exactly what Dia sent");

    gChoice = @"claude-opus-5-5";
    DPApplyDiaChatModel(&DPDiaChatModel);
    filter = DPAgentFilters(YES).firstObject;
    DPTurnOffAI.on = YES;
    CHECK([ModelIn(filter(request, ^(NSDictionary *m) {})) isEqual:@"claude-sonnet-5-5"], "Turn Off AI switched on later stops the rewrite");
    DPTurnOffAI.on = NO;

    DPDiaChatModel.on = NO;
    DPApplyDiaChatModel(&DPDiaChatModel);
    CHECK(!DPAgentFiltersActive(), "off or paused removes the filter live");
    CHECK(!DPDiaChatModel.verify(&DPDiaChatModel), "verify passes when off and nothing is registered");
    DPSetAgentFilters(@"stray", ^NSData *(NSData *line, DPAgentReply reply) { return line; }, nil);
    CHECK(DPDiaChatModel.verify(&DPDiaChatModel), "verify notices a filter left behind while off");
    DPSetAgentFilters(@"stray", nil, nil);
    DPDiaChatModel.on = YES;
    DPApplyDiaChatModel(&DPDiaChatModel);
    CHECK(!DPDiaChatModel.verify(&DPDiaChatModel), "verify passes when on and the filter and launch hook are in");
    DPDiaChatModel.on = NO;
    DPApplyDiaChatModel(&DPDiaChatModel);
}

static void TestRelayPassThrough(void) {
    CHECK(!DPAgentFiltersActive(), "relay tests start unfiltered");
    dispatch_semaphore_t done;
    Relay relay = StartRelay(&done);
    NSData *partial = Bytes(@"{\"type\":\"HEL");
    WriteAll(relay.app, partial);
    CHECK([ReadExactly(relay.agent, partial.length) isEqual:partial], "with no filter a partial frame arrives at once, unbuffered");
    NSData *rest = Bytes(@"LO\"}\nnext");
    WriteAll(relay.app, rest);
    CHECK([ReadExactly(relay.agent, rest.length) isEqual:rest], "the rest follows byte for byte");
    NSMutableData *blob = [NSMutableData dataWithLength:200000];
    arc4random_buf(blob.mutableBytes, blob.length);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ WriteAll(relay.agent, blob); });
    CHECK([ReadExactly(relay.app, blob.length) isEqual:blob], "binary data from the agent arrives intact, including bytes that aren't text");
    StopRelay(relay, done);
}

static void TestRelayFilters(void) {
    DPSetAgentFilters(@"t", ^NSData *(NSData *line, DPAgentReply reply) { return Upper(line, reply); }, nil);
    dispatch_semaphore_t done;
    Relay relay = StartRelay(&done);
    NSData *input = Bytes(@"abc\ndéf ☃\n\nlast\n");
    for (NSUInteger i = 0; i < input.length; i++) WriteAll(relay.app, [input subdataWithRange:NSMakeRange(i, 1)]);
    NSData *expected = Bytes(@"ABC\nDÉF ☃\n\nLAST\n");
    CHECK([ReadExactly(relay.agent, expected.length) isEqual:expected], "byte-at-a-time input is framed and filtered");
    WriteAll(relay.app, Bytes(@"one\ntwo\nthr"));
    WriteAll(relay.app, Bytes(@"ee\nfour\n"));
    expected = Bytes(@"ONE\nTWO\nTHREE\nFOUR\n");
    CHECK([ReadExactly(relay.agent, expected.length) isEqual:expected], "several frames and a split frame in two writes");
    WriteAll(relay.agent, Bytes(@"response, never filtered\nhalf"));
    expected = Bytes(@"response, never filtered\nhalf");
    CHECK([ReadExactly(relay.app, expected.length) isEqual:expected], "the response direction is untouched and unbuffered");
    WriteAll(relay.app, Bytes(@"tail without newline"));
    shutdown(relay.app, SHUT_WR);
    expected = Bytes(@"tail without newline");
    CHECK([ReadExactly(relay.agent, expected.length) isEqual:expected], "an unfinished frame at the end of the stream is delivered");
    StopRelay(relay, done);

    // A filter that consumes a frame, answers it, throws, or is added between frames.
    DPSetAgentFilters(@"t", ^NSData *(NSData *line, DPAgentReply reply) {
        NSString *text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
        if ([text isEqual:@"consume"]) { reply(@{ @"type": @"ACK", @"ok": @YES }); return nil; }
        if ([text isEqual:@"throw"]) @throw [NSException exceptionWithName:@"Test" reason:@"boom" userInfo:nil];
        if ([text isEqual:@"nan"]) { reply(@{ @"bad": @(NAN) }); return line; }
        return line;
    }, nil);
    relay = StartRelay(&done);
    WriteAll(relay.app, Bytes(@"consume\nthrow\nnan\nplain\n"));
    expected = Bytes(@"throw\nnan\nplain\n");
    CHECK([ReadExactly(relay.agent, expected.length) isEqual:expected], "consumed frames vanish, a throwing filter passes the frame, an invalid reply is dropped");
    NSMutableData *ack = [NSMutableData new];
    for (char byte = 0; byte != '\n'; ) {
        CHECK(read(relay.app, &byte, 1) == 1, "reply missing");
        [ack appendBytes:&byte length:1];
    }
    CHECK([Parse(ack)[@"type"] isEqual:@"ACK"], "the reply reaches the app, not the agent");
    StopRelay(relay, done);
    DPSetAgentFilters(@"t", nil, nil);

    // The decision is made at a frame's first byte.
    relay = StartRelay(&done);
    WriteAll(relay.app, Bytes(@"raw-start "));
    CHECK([ReadExactly(relay.agent, 10) isEqual:Bytes(@"raw-start ")], "unfiltered frame start is forwarded at once");
    DPSetAgentFilters(@"t", ^NSData *(NSData *line, DPAgentReply reply) { return Upper(line, reply); }, nil);
    WriteAll(relay.app, Bytes(@"middle\nfiltered\n"));
    expected = Bytes(@"middle\nFILTERED\n");
    CHECK([ReadExactly(relay.agent, expected.length) isEqual:expected], "a filter added mid-frame waits for the next frame");
    DPSetAgentFilters(@"t", nil, nil);
    WriteAll(relay.app, Bytes(@"back to raw\n"));
    CHECK([ReadExactly(relay.agent, 12) isEqual:Bytes(@"back to raw\n")], "removed filter returns to raw forwarding");
    StopRelay(relay, done);

    // A frame beyond the limit isn't buffered or dropped: it goes through as it came.
    NSUInteger limit = DPAgentFrameLimit;
    DPAgentFrameLimit = 64;
    DPSetAgentFilters(@"t", ^NSData *(NSData *line, DPAgentReply reply) { return Upper(line, reply); }, nil);
    relay = StartRelay(&done);
    NSMutableData *big = [NSMutableData dataWithData:Bytes([@"" stringByPaddingToLength:1000 withString:@"x" startingAtIndex:0])];
    [big appendData:Bytes(@"\nsmall\n")];
    WriteAll(relay.app, big);
    expected = [NSMutableData dataWithData:Bytes([@"" stringByPaddingToLength:1000 withString:@"x" startingAtIndex:0])];
    [(NSMutableData *)expected appendData:Bytes(@"\nSMALL\n")];
    CHECK([ReadExactly(relay.agent, expected.length) isEqual:expected], "oversized frame passes unmodified and the next frame is filtered again");
    StopRelay(relay, done);
    DPAgentFrameLimit = limit;
    DPSetAgentFilters(@"t", nil, nil);
}

static int OpenDescriptors(void) {
    int count = 0;
    for (int fd = 0; fd < 1024; fd++) count += fcntl(fd, F_GETFD) != -1;
    return count;
}

static void TestConcurrencyAndLeaks(void) {
    int before = OpenDescriptors();
    DPSetAgentFilters(@"t", ^NSData *(NSData *line, DPAgentReply reply) { return Upper(line, reply); }, nil);
    enum { connections = 6, frames = 300 };
    dispatch_group_t group = dispatch_group_create();
    __block _Atomic int failures = 0;
    for (int c = 0; c < connections; c++) {
        dispatch_semaphore_t done;
        Relay relay = StartRelay(&done);
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSMutableData *all = [NSMutableData new], *expected = [NSMutableData new];
            for (int i = 0; i < frames; i++) {
                NSString *line = [NSString stringWithFormat:@"c%d-frame-%d-%@", c, i, [@"" stringByPaddingToLength:(NSUInteger)(i % 97) withString:@"z" startingAtIndex:0]];
                [all appendData:Bytes([line stringByAppendingString:@"\n"])];
                [expected appendData:Bytes([line.uppercaseString stringByAppendingString:@"\n"])];
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                for (NSUInteger at = 0; at < all.length; at += 37) WriteAll(relay.app, [all subdataWithRange:NSMakeRange(at, MIN((NSUInteger)37, all.length - at))]);
            });
            NSData *got = ReadExactly(relay.agent, expected.length);
            if (![got isEqual:expected]) atomic_fetch_add(&failures, 1);
            StopRelay(relay, done);
        });
    }
    // Filters come and go while those connections run.
    DPAgentFilter identity = ^NSData *(NSData *line, DPAgentReply reply) { return line; };
    for (int flip = 0; flip < 400; flip++) {
        DPSetAgentFilters(@"u", flip % 2 ? identity : nil, nil);
        usleep(200);
    }
    DPSetAgentFilters(@"u", nil, nil);
    CHECK(!dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)), "concurrent connections must finish");
    CHECK(!atomic_load(&failures), "concurrent connections lost or reordered frames");
    DPSetAgentFilters(@"t", nil, nil);
    usleep(50000);
    CHECK(OpenDescriptors() == before, "descriptors leaked: %d before, %d after", before, OpenDescriptors());

    int pair[2];
    CHECK(!socketpair(AF_UNIX, SOCK_STREAM, 0, pair), "pair");
    DPAgentWriter *writer = [[DPAgentWriter alloc] initWithFD:pair[0]];
    CHECK([writer write:"x" length:0] && [writer write:"x" length:1], "writer writes");
    [writer invalidate];
    CHECK(![writer write:"x" length:1], "an invalidated writer never touches its descriptor again");
    close(pair[0]);
    close(pair[1]);
}

// The chat agent stand-in is this same executable, copied to where Dia keeps its agent and run with --agent: it echoes every line.
static void RunFakeAgent(const char *socket) {
    int listener = DPAgentSocket();
    struct sockaddr_un address = DPAgentAddress(socket);
    if (listener < 0 || bind(listener, (struct sockaddr *)&address, address.sun_len) || listen(listener, 16)) _exit(2);
    alarm(60);
    for (;;) {
        int client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buffer[512];
            ssize_t got;
            while ((got = read(client, buffer, sizeof buffer)) > 0 && write(client, buffer, got) == got) {}
            close(client);
        });
    }
}

static NSString *MakeTemporaryFolder(void) {
    char folder[] = "/tmp/diatweaks-test.XXXXXX";
    CHECK(mkdtemp(folder), "mkdtemp");
    return @(folder);
}

static pid_t Spawn(const char *path, const char *argument, const char *second) {
    char *argv[] = { (char *)path, (char *)argument, (char *)second, NULL };
    pid_t pid = 0;
    CHECK(!posix_spawn(&pid, path, NULL, NULL, argv, environ), "spawn %s", path);
    return pid;
}

static pid_t SpawnFakeAgent(NSString *home, NSString *socket) {
    NSString *dist = [home stringByAppendingPathComponent:@"agent-server-resources/dist"];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:dist withIntermediateDirectories:YES attributes:nil error:nil], "dist folder");
    char own[4096];
    uint32_t size = sizeof own;
    CHECK(!_NSGetExecutablePath(own, &size), "executable path");
    NSString *copy = [dist stringByAppendingPathComponent:@"agent-server"];
    CHECK([NSFileManager.defaultManager copyItemAtPath:@(own) toPath:copy error:nil], "copy agent");
    chmod(copy.fileSystemRepresentation, 0755);
    return Spawn(copy.fileSystemRepresentation, "--agent", socket.fileSystemRepresentation);
}

static BOOL WaitUntil(BOOL (^condition)(void), int seconds) {
    for (int i = 0; i < seconds * 100; i++) {
        if (condition()) return YES;
        usleep(10000);
    }
    return condition();
}

static void StopProcess(pid_t pid) {
    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
}

static int ListenOn(NSString *path) {
    int listener = DPAgentSocket();
    struct sockaddr_un address = DPAgentAddress(path.fileSystemRepresentation);
    CHECK(listener >= 0 && !bind(listener, (struct sockaddr *)&address, address.sun_len) && !chmod(path.fileSystemRepresentation, 0600) && !listen(listener, 16), "listener");
    return listener;
}

static int ConnectTo(NSString *path) {
    int fd = DPAgentSocket();
    struct sockaddr_un address = DPAgentAddress(path.fileSystemRepresentation);
    struct timeval timeout = { .tv_sec = 5 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    CHECK(!connect(fd, (struct sockaddr *)&address, address.sun_len), "connect %s", path.fileSystemRepresentation);
    return fd;
}

static void TestRelaunchOffer(void) {
    gModels = @[ @"claude-haiku-5-5" ];
    gChoice = @"claude-haiku-5-5";
    DPDiaChatModel.on = YES;
    DPTurnOffAI.on = NO;
    gSaved = YES;
    DPApplyDiaChatModel(&DPDiaChatModel);
    CHECK(DPAgentTransportInstalled() && !DPAgentServerRunning() && !DPAgentRelayRunning(), "no chat agent yet");
    CHECK(!DPChatModelNeedsRelaunch(&DPDiaChatModel), "no agent means nothing to relaunch for");
    CHECK(!DPChatModelTakeRelaunchOffer(&DPDiaChatModel), "no offer before the agent exists");

    pid_t other = Spawn("/bin/sleep", "30", NULL);
    CHECK(!DPAgentServerRunning(), "another child process isn't the chat agent");
    StopProcess(other);

    NSString *home = MakeTemporaryFolder(), *directory = MakeTemporaryFolder();
    pid_t agent = SpawnFakeAgent(home, [directory stringByAppendingPathComponent:@"agent.sock"]);
    CHECK(WaitUntil(^BOOL { return DPAgentServerRunning(); }, 5), "the chat agent under this process is found");
    CHECK(!DPAgentRelayRunning(), "nothing relays it");
    CHECK(DPChatModelNeedsRelaunch(&DPDiaChatModel), "an agent started without the transport needs a relaunch");

    DPDiaChatModel.on = NO;
    CHECK(!DPChatModelNeedsRelaunch(&DPDiaChatModel), "turning the tweak off never asks");
    CHECK(!DPChatModelTakeRelaunchOffer(&DPDiaChatModel), "off resets without offering");
    DPDiaChatModel.on = YES;
    DPTurnOffAI.on = YES;
    CHECK(!DPChatModelNeedsRelaunch(&DPDiaChatModel), "Turn Off AI never asks");
    DPTurnOffAI.on = NO;
    gSaved = NO;
    CHECK(!DPChatModelNeedsRelaunch(&DPDiaChatModel), "a paused tweak never asks");
    gSaved = YES;

    CHECK(DPChatModelTakeRelaunchOffer(&DPDiaChatModel), "the first call offers");
    CHECK(!DPChatModelTakeRelaunchOffer(&DPDiaChatModel), "changing the model while it waits doesn't ask again");
    DPDiaChatModel.on = NO;
    DPChatModelTakeRelaunchOffer(&DPDiaChatModel);
    DPDiaChatModel.on = YES;
    CHECK(DPChatModelTakeRelaunchOffer(&DPDiaChatModel), "turning it off and on again asks once more");

    NSString *public = [NSString stringWithFormat:@"/tmp/dia-agent.server.test.%d.sock", getpid()];
    int listener = ListenOn(public);
    DPRelayChatAgent(listener, public, directory, agent, nil);
    CHECK(DPAgentRelayRunning() && DPAgentServerRunning(), "a relayed agent is both running and relayed");
    CHECK(!DPChatModelNeedsRelaunch(&DPDiaChatModel), "a relayed agent needs nothing: models switch live");
    DPDiaChatModel.on = NO;
    DPApplyDiaChatModel(&DPDiaChatModel);
    CHECK(DPAgentRelayRunning(), "turning off leaves the relay passing frames through");

    StopProcess(agent);
    CHECK(WaitUntil(^BOOL { return !DPAgentRelayRunning(); }, 5), "the relay ends with its agent");
    CHECK(!DPAgentServerRunning() && !DPChatModelNeedsRelaunch(&DPDiaChatModel), "nothing is left to ask about");
    struct stat info;
    CHECK(stat(public.fileSystemRepresentation, &info) && stat(directory.fileSystemRepresentation, &info), "socket and private folder are removed");
    [NSFileManager.defaultManager removeItemAtPath:home error:nil];
    DPDiaChatModel.on = NO;
}

static void TestConcurrentConnections(void) {
    int descriptors = OpenDescriptors();
    DPSetAgentFilters(@"t", ^NSData *(NSData *line, DPAgentReply reply) { return Upper(line, reply); }, nil);
    NSString *home = MakeTemporaryFolder(), *directory = MakeTemporaryFolder();
    NSString *public = [NSString stringWithFormat:@"/tmp/dia-agent.server.test.%d.sock", getpid()];
    int listener = ListenOn(public);
    pid_t agent = SpawnFakeAgent(home, [directory stringByAppendingPathComponent:@"agent.sock"]);
    __block _Atomic int connected = 0;
    DPRelayChatAgent(listener, public, directory, agent, ^(NSString *folder) { atomic_fetch_add(&connected, 1); });

    int first = ConnectTo(public);
    WriteAll(first, Bytes(@"one\n"));
    CHECK([ReadExactly(first, 4) isEqual:Bytes(@"ONE\n")], "the first connection works");
    int second = ConnectTo(public), third = ConnectTo(public);
    WriteAll(second, Bytes(@"two\n"));
    CHECK([ReadExactly(second, 4) isEqual:Bytes(@"TWO\n")], "a second connection is served while the first is still open");
    WriteAll(third, Bytes(@"three\n"));
    CHECK([ReadExactly(third, 6) isEqual:Bytes(@"THREE\n")], "and a third");
    WriteAll(first, Bytes(@"again\n"));
    CHECK([ReadExactly(first, 6) isEqual:Bytes(@"AGAIN\n")], "the first connection carried on meanwhile");
    CHECK(atomic_load(&connected) == 3, "the connection callback ran once per connection");
    close(second);
    int fourth = ConnectTo(public);
    WriteAll(fourth, Bytes(@"four\n"));
    CHECK([ReadExactly(fourth, 5) isEqual:Bytes(@"FOUR\n")], "a connection made after another closed is served");
    WriteAll(third, Bytes(@"more\n"));
    CHECK([ReadExactly(third, 5) isEqual:Bytes(@"MORE\n")], "the others are unaffected");

    // The agent going away ends every open connection and then removes the private folder.
    StopProcess(agent);
    char byte;
    CHECK(read(first, &byte, 1) <= 0 && read(third, &byte, 1) <= 0 && read(fourth, &byte, 1) <= 0, "open connections end with the agent");
    close(first);
    close(third);
    close(fourth);
    CHECK(WaitUntil(^BOOL { return !DPAgentRelayRunning(); }, 10), "the relay finishes after the last connection");
    struct stat info;
    CHECK(stat(public.fileSystemRepresentation, &info) && stat(directory.fileSystemRepresentation, &info), "socket and private folder are removed");
    [NSFileManager.defaultManager removeItemAtPath:home error:nil];
    DPSetAgentFilters(@"t", nil, nil);
    CHECK(WaitUntil(^BOOL { return OpenDescriptors() == descriptors; }, 3), "descriptors leaked: %d before, %d after", descriptors, OpenDescriptors());
}

static void TestTurnOffAILive(void) {
    gModels = @[ @"claude-haiku-5-5" ];
    gChoice = @"claude-haiku-5-5";
    DPDiaChatModel.on = YES;
    DPTurnOffAI.on = YES;
    DPDiaChatModel.install();
    CHECK(!DPAgentFiltersActive(), "Turn Off AI on: nothing registered");
    DPTurnOffAI.on = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    CHECK(DPAgentFiltersActive(), "Turn Off AI switched off live brings the tweak back without a relaunch");
    DPTurnOffAI.on = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    CHECK(!DPAgentFiltersActive(), "and switched on live takes it away again");
    DPTurnOffAI.on = NO;
    DPDiaChatModel.on = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    CHECK(!DPAgentFiltersActive(), "an off tweak stays off when Turn Off AI changes");
}

// Reads the Swift type metadata straight from a Dia executable on disk, with the same layout checks the tweak makes at runtime.
static NSString *StaticCatalogProblem(NSString *path, NSUInteger *caseCount) {
    NSData *file = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (file.length < 4096) return @"unreadable";
    const uint8_t *base = file.bytes;
    size_t offset = 0;
    if (OSSwapBigToHostInt32(*(const uint32_t *)base) == FAT_MAGIC) {
        const struct fat_header *fat = (const void *)base;
        const struct fat_arch *arch = (const void *)(fat + 1);
        for (uint32_t i = 0; i < OSSwapBigToHostInt32(fat->nfat_arch); i++)
            if (OSSwapBigToHostInt32(arch[i].cputype) == CPU_TYPE_ARM64) offset = OSSwapBigToHostInt32(arch[i].offset);
        if (!offset) return @"no arm64 slice";
    }
    const struct mach_header_64 *header = (const void *)(base + offset);
    if (header->magic != MH_MAGIC_64 || header->filetype != MH_EXECUTE) return @"not a 64-bit executable";
    static struct { uint64_t vm, size, off; } segments[16];
    int segmentCount = 0;
    uint64_t typesVM = 0, typesSize = 0;
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const char *)command + command->cmdsize)) {
        if (command->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *segment = (const void *)command;
        if (segmentCount < 16) segments[segmentCount++] = (typeof(segments[0])){ segment->vmaddr, segment->vmsize, segment->fileoff };
        const struct section_64 *section = (const void *)(segment + 1);
        for (uint32_t s = 0; s < segment->nsects; s++)
            if (!strcmp(section[s].sectname, "__swift5_types")) { typesVM = section[s].addr; typesSize = section[s].size; }
    }
    if (!typesVM) return @"no __swift5_types";
    const uint8_t *(^pointer)(uint64_t) = ^const uint8_t *(uint64_t vm) {
        for (int i = 0; i < segmentCount; i++)
            if (vm >= segments[i].vm && vm < segments[i].vm + segments[i].size) {
                size_t at = offset + segments[i].off + (vm - segments[i].vm);
                return at + 64 < file.length ? base + at : NULL;
            }
        return NULL;
    };
    uint64_t (^resolve)(uint64_t) = ^uint64_t(uint64_t field) {
        const int32_t *value = (const void *)pointer(field);
        return value && *value ? field + *value : 0;
    };
    for (uint64_t index = 0; index < typesSize / 4; index++) {
        uint64_t type = resolve(typesVM + index * 4);
        const uint32_t *descriptor = (const void *)(type ? pointer(type) : NULL);
        if (!descriptor || (type & 3)) continue;
        if ((descriptor[0] & 0x1f) != 18 || (descriptor[0] & 0xff80)) continue;
        uint64_t nameVM = resolve(type + 8);
        const char *name = (const char *)(nameVM ? pointer(nameVM) : NULL);
        if (!name || strncmp(name, "ChatResponseModel", 18)) continue;
        if (!resolve(type + 12)) return @"no metadata accessor";
        uint64_t fieldsVM = resolve(type + 16);
        const uint8_t *fields = fieldsVM ? pointer(fieldsVM) : NULL;
        if (!fields) return @"no field descriptor";
        uint16_t kind = *(const uint16_t *)(fields + 8);
        uint32_t count = *(const uint32_t *)(fields + 12);
        if (kind != 2) return @"not an enum";
        if (!count || count > 256) return @"unexpected case count";
        *caseCount = count;
        return nil;
    }
    return @"ChatResponseModel not found";
}

static void TestRealDiaBundles(void) {
    NSMutableArray<NSString *> *bundles = [NSMutableArray arrayWithObject:@"/Applications/Dia.app"];
    [bundles addObject:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DiaPatches/staged/Dia.app"]];
    NSUInteger checked = 0;
    for (NSString *bundle in bundles) {
        NSString *executable = [bundle stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
        if (![NSFileManager.defaultManager fileExistsAtPath:executable]) continue;
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Contents/Info.plist"]];
        NSUInteger count = 0;
        NSString *problem = StaticCatalogProblem(executable, &count);
        // Real bundles may be a version the tweak doesn't know: that must show as an empty catalog, never a crash, so report instead of failing.
        printf("  Dia %s (%s): %s\n", [info[@"CFBundleShortVersionString"] UTF8String] ?: "?", bundle.UTF8String,
               problem ? problem.UTF8String : [NSString stringWithFormat:@"ChatResponseModel layout accepted, %lu cases", (unsigned long)count].UTF8String);
        CHECK(!problem || [problem isEqual:@"ChatResponseModel not found"], "unexpected catalog layout in %s: %s", bundle.UTF8String, problem.UTF8String);
        checked++;
    }
    if (!checked) puts("  no installed Dia to read: the Swift fixture catalog in tests/chat-models covers discovery");
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc == 3 && !strcmp(argv[1], "--agent")) RunFakeAgent(argv[2]);
    TestOffIsUntouched();
    TestRequestRewrite();
    TestSelection();
    TestPatchLifecycle();
    TestRelayPassThrough();
    TestRelayFilters();
    TestConcurrencyAndLeaks();
    TestConcurrentConnections();
    TestRelaunchOffer();
    TestTurnOffAILive();
    TestRealDiaBundles();
    puts("PASS: chat model request rewrite, fallback policy, off/paused/Turn Off AI isolation, framing, concurrent connections, relaunch offer and descriptor hygiene");
}}

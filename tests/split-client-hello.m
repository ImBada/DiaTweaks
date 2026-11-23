#import <Foundation/Foundation.h>
#import "Patches/SplitClientHello/Split.h"
#import "Patches/SplitClientHello/Write.h"
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>

static BOOL DPReceive(int fd, uint8_t *buffer, size_t length) {
    for (ssize_t got; length; buffer += got, length -= (size_t)got)
        if ((got = recv(fd, buffer, length, 0)) <= 0) return NO;
    return YES;
}

static int DPLoopbackListener(struct sockaddr_in *address) {
    int server = socket(AF_INET, SOCK_STREAM, 0);
    *address = (struct sockaddr_in){ .sin_len = sizeof *address, .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
    socklen_t size = sizeof *address;
    NSCAssert(bind(server, (struct sockaddr *)address, size) == 0 && listen(server, 1) == 0
                  && getsockname(server, (struct sockaddr *)address, &size) == 0, @"listens on loopback");
    return server;
}

static NSData *DPCaptureHello(NSString *host) {
    struct sockaddr_in address;
    int server = DPLoopbackListener(&address);
    int port = ntohs(address.sin_port);
    NSTask *curl = [NSTask new];
    curl.executableURL = [NSURL fileURLWithPath:@"/usr/bin/curl"];
    curl.arguments = @[ @"-s", @"-m", @"5", @"--resolve", [NSString stringWithFormat:@"%@:%d:127.0.0.1", host, port],
                        [NSString stringWithFormat:@"https://%@:%d/", host, port] ];
    curl.standardOutput = curl.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSCAssert([curl launchAndReturnError:nil], @"runs curl");
    struct pollfd ready = { server, POLLIN, 0 };
    NSCAssert(poll(&ready, 1, 5000) == 1, @"curl connects");
    int client = accept(server, NULL, NULL);
    uint8_t header[5];
    NSCAssert(DPReceive(client, header, 5) && header[0] == 0x16, @"curl starts with a handshake record");
    NSMutableData *hello = [NSMutableData dataWithBytes:header length:5];
    hello.length = 5 + (header[3] << 8 | header[4]);
    NSCAssert(DPReceive(client, hello.mutableBytes + 5, hello.length - 5), @"reads the whole record");
    close(client);
    close(server);
    [curl waitUntilExit];
    return hello;
}

static size_t DPCheckSplit(NSData *data, size_t record, NSString *name, uint32_t random) {
    const uint8_t *in = data.bytes;
    // Exact size so ASan catches any overwrite.
    uint8_t *out = malloc(data.length + 5);
    NSCAssert(DPSplitHello(in, data.length, out, random) == data.length + 5, @"splits a ClientHello");
    size_t recordLength = in[record + 3] << 8 | in[record + 4], first = out[record + 3] << 8 | out[record + 4];
    size_t cut = record + 5 + first, second = out[cut + 3] << 8 | out[cut + 4];
    const uint8_t *found = memmem(in, data.length, name.UTF8String, strlen(name.UTF8String));
    size_t nameAt = (size_t)(found - in);
    NSCAssert(found && cut > nameAt && cut < nameAt + strlen(name.UTF8String), @"cuts inside the server name");
    NSCAssert(first + second == recordLength && memcmp(out + cut, in + record, 3) == 0, @"the two records hold the one");
    NSCAssert(memcmp(out, in, record + 3) == 0 && memcmp(out + record + 5, in + record + 5, first) == 0
                  && memcmp(out + cut + 5, in + cut, data.length - cut) == 0, @"every other byte is unchanged");
    free(out);
    return cut;
}

typedef struct { ssize_t count; int error; uintptr_t secondary; } DPStep;
static DPStep gSteps[8];
static int gStepCount, gCalls;
static NSMutableData *gWire;

static DPSendResult DPScriptedSend(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address,
                                   socklen_t addressLength) {
    DPStep step = gCalls < gStepCount ? gSteps[gCalls] : (DPStep){ -1, 0, 0 };
    gCalls++;
    if (step.error) return errno = step.error, (DPSendResult){ -1, 0 };
    size_t sent = step.count < 0 || (size_t)step.count > length ? length : (size_t)step.count;
    [gWire appendBytes:buffer length:sent];
    return (DPSendResult){ (ssize_t)sent, step.secondary };
}

static DPSendResult DPSendScripted(int fd, NSData *data, bool checkSecondary, int count, const DPStep *steps, bool *handled) {
    if (count) memcpy(gSteps, steps, count * sizeof *steps);
    gStepCount = count, gCalls = 0, gWire = [NSMutableData data];
    DPSendResult result = { 0, 0 };
    *handled = DPSendSplit(fd, data.bytes, data.length, MSG_NOSIGNAL, 7, DPScriptedSend, checkSecondary, &result);
    return result;
}

static void DPCheckSend(NSData *hello) {
    int pair[2], datagrams[2];
    NSCAssert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0 && socketpair(AF_UNIX, SOCK_DGRAM, 0, datagrams) == 0, @"socket pairs");
    NSMutableData *expected = [NSMutableData dataWithLength:hello.length + 5];
    DPSplitHello(hello.bytes, hello.length, expected.mutableBytes, 7);
    bool handled;
    struct { const char *what; int count; DPStep steps[4]; } goes[] = {
        { "sends a split ClientHello in one go", 0, { { 0, 0, 0 } } },
        { "sends the rest after a partial send", 1, { { 100, 0, 0 } } },
        { "waits out EAGAIN and EINTR once some is sent", 3, { { 100, 0, 0 }, { 0, EAGAIN, 0 }, { 0, EINTR, 0 } } },
        { "ignores the second register where Chromium doesn't read it", 1, { { -1, 0, 1 } } },
    };
    for (size_t i = 0; i < sizeof goes / sizeof *goes; i++) {
        DPSendResult result = DPSendScripted(pair[0], hello, i < 3, goes[i].count, goes[i].steps, &handled);
        NSCAssert(handled && result.sent == (ssize_t)hello.length && result.secondary == 0 && [gWire isEqual:expected], @"%s", goes[i].what);
    }
    DPSendResult result = DPSendScripted(pair[0], hello, true, 1, (DPStep[]){ { 0, EAGAIN, 0 } }, &handled);
    NSCAssert(handled && result.sent == -1 && errno == EAGAIN && gWire.length == 0, @"EAGAIN before anything is sent goes back to Chromium");
    result = DPSendScripted(pair[0], hello, true, 2, (DPStep[]){ { 50, 0, 0 }, { 0, EPIPE, 0 } }, &handled);
    NSCAssert(handled && result.sent == -1 && errno == EPIPE, @"a failure partway keeps its errno");
    result = DPSendScripted(pair[0], hello, true, 1, (DPStep[]){ { -1, 0, 1 } }, &handled);
    NSCAssert(handled && result.sent == -1 && errno == ECONNRESET, @"the kernel bug Chromium checks for fails the send");
    result = DPSendScripted(pair[0], hello, true, 2, (DPStep[]){ { 50, 0, 0 }, { 0, 0, 0 } }, &handled);
    NSCAssert(handled && result.sent == -1 && errno == ECONNRESET && gCalls == 2, @"zero-byte send after partial progress fails instead of spinning");
    result = DPSendScripted(pair[0], hello, true, 1, (DPStep[]){ { 0, 0, 0 } }, &handled);
    NSCAssert(handled && result.sent == 0 && gCalls == 1, @"zero-byte initial send returns 0 instead of spinning");
    NSCAssert(!DPSendSplit(pair[0], NULL, hello.length, MSG_NOSIGNAL, 7, DPScriptedSend, true, &result), @"NULL buffer falls through");

    const char *request = "GET / HTTP/1.1\r\nHost: split-client-hello.example\r\nAccept: */*\r\n\r\n";
    DPSendScripted(pair[0], [NSData dataWithBytes:request length:strlen(request)], true, 0, NULL, &handled);
    NSCAssert(!handled && gCalls == 0, @"leaves other data to the real sendto");
    DPSendScripted(datagrams[0], hello, true, 0, NULL, &handled);
    NSCAssert(!handled && gCalls == 0, @"leaves datagram sockets alone");

    struct sockaddr_in address;
    int server = DPLoopbackListener(&address), client = socket(AF_INET, SOCK_STREAM, 0);
    NSCAssert(connect(client, (struct sockaddr *)&address, sizeof address) == 0, @"connects over loopback");
    int peer = accept(server, NULL, NULL);
    DPSendScripted(client, hello, true, 0, NULL, &handled);
    NSCAssert(handled, @"splits on a fresh TCP socket");
    fcntl(client, F_SETFL, O_NONBLOCK);
    char filler[4096] = { 0 };
    // The peer keeps draining what is in flight after the first EAGAIN, so top up until a pause adds nothing.
    for (ssize_t added = 1; added;) {
        usleep(20000);
        added = 0;
        for (size_t chunk = sizeof filler; chunk; chunk = chunk > 1)
            for (ssize_t sent; (sent = send(client, filler, chunk, 0)) > 0;) added += sent;
    }
    DPSendScripted(client, hello, true, 0, NULL, &handled);
    NSCAssert(!handled && gCalls == 0, @"leaves it whole when the send buffer is full");
    close(peer), close(client), close(server);
    close(pair[0]), close(pair[1]), close(datagrams[0]), close(datagrams[1]);
}

int main(void) {
    @autoreleasepool {
        NSString *name = @"split-client-hello.example";
        NSData *hello = DPCaptureHello(name);
        NSMutableIndexSet *cuts = [NSMutableIndexSet indexSet];
        for (uint32_t random = 0; random < 4 * name.length; random++) [cuts addIndex:DPCheckSplit(hello, 0, name, random)];
        NSCAssert(cuts.count == name.length - 1, @"every cut inside the name comes up");
        DPCheckSplit(hello, 0, name, UINT32_MAX);

        NSMutableData *retry = [NSMutableData dataWithBytes:"\x14\x03\x03\x00\x01\x01" length:6];
        [retry appendData:hello];
        DPCheckSplit(retry, 6, name, 7);
        NSMutableData *trailing = [hello mutableCopy];
        [trailing appendBytes:"\x17\x03\x03\x00\x02hi" length:7];
        DPCheckSplit(trailing, 0, name, 7);

        uint8_t out[8192];
        for (size_t length = 0; length < hello.length; length++)
            NSCAssert(!DPSplitHello(hello.bytes, length, out, 7), @"leaves a cut-off ClientHello alone");
        NSData *nameless = DPCaptureHello(@"127.0.0.1");
        NSCAssert(!DPSplitHello(nameless.bytes, nameless.length, out, 7), @"leaves one without a name alone");
        const char *request = "GET / HTTP/1.1\r\nHost: split-client-hello.example\r\n\r\n";
        NSCAssert(!DPSplitHello((const uint8_t *)request, strlen(request), out, 7), @"leaves other data alone");
        NSMutableData *serverHello = [hello mutableCopy];
        ((uint8_t *)serverHello.mutableBytes)[5] = 0x02;
        NSCAssert(!DPSplitHello(serverHello.bytes, serverHello.length, out, 7), @"leaves other handshake messages alone");

        NSMutableData *badSni = [hello mutableCopy];
        const uint8_t *found = memmem(badSni.bytes, badSni.length, name.UTF8String, strlen(name.UTF8String));
        NSCAssert(found != NULL, @"finds SNI name in captured hello");
        size_t listLenAt = (size_t)(found - (const uint8_t *)badSni.bytes) - 5;
        ((uint8_t *)badSni.mutableBytes)[listLenAt] = 0x00;
        ((uint8_t *)badSni.mutableBytes)[listLenAt + 1] = 0x04;
        NSCAssert(!DPSplitHello(badSni.bytes, badSni.length, out, 7), @"rejects truncated SNI server_name_list length");
        ((uint8_t *)badSni.mutableBytes)[listLenAt] = 0x7F;
        ((uint8_t *)badSni.mutableBytes)[listLenAt + 1] = 0xFF;
        NSCAssert(!DPSplitHello(badSni.bytes, badSni.length, out, 7), @"rejects oversized SNI server_name_list length");

        for (int i = 0; i < 20000; i++) {
            NSMutableData *garbled = [hello mutableCopy];
            for (int flips = 1 + arc4random_uniform(4); flips; flips--)
                ((uint8_t *)garbled.mutableBytes)[arc4random_uniform((uint32_t)garbled.length)] = (uint8_t)arc4random();
            uint8_t *exact = malloc(garbled.length + 5);
            DPSplitHello(garbled.bytes, garbled.length, exact, arc4random());
            free(exact);
        }
        DPCheckSend(hello);
        puts("all Split TLS ClientHello checks passed");
    }
}

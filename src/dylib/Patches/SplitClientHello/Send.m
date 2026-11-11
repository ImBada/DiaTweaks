#import "SplitClientHello.h"
#import "Split.h"
#include <errno.h>
#include <poll.h>
#include <stdatomic.h>
#include <sys/socket.h>

// Chromium's network service sends through sendto, which this replaces for all of Dia.

_Atomic bool DPSplitting;
static bool gCheckSecondary;

// On macOS 13.3 up to 26.1, Chromium also reads sendto's second return register to catch a kernel bug
// (crbug.com/40064248): anything but 0 there after a send that worked fails the connection. So the replacement hands
// back the real one's pair untouched, and a split send returns 0 there itself.
typedef struct { ssize_t sent; uintptr_t secondary; } DPSendResult;
extern DPSendResult DPRealSendto(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address,
                                 socklen_t addressLength) __asm__("_sendto");

// The socket is fresh, so this almost always goes out at once.
static DPSendResult DPSendAll(int fd, const uint8_t *data, size_t length, int flags) {
    for (size_t sent = 0; sent < length;) {
        DPSendResult result = DPRealSendto(fd, data + sent, length - sent, flags, NULL, 0);
        if (result.sent >= 0 && result.secondary && gCheckSecondary) return errno = ECONNRESET, (DPSendResult){ -1, 0 };
        if (result.sent >= 0) {
            sent += (size_t)result.sent;
        } else if (errno == EAGAIN && sent) {
            // Part of it is out, so the rest has to follow before Chromium writes anything else.
            struct pollfd ready = { fd, POLLOUT, 0 };
            if (poll(&ready, 1, 5000) == 0) return errno = ETIMEDOUT, (DPSendResult){ -1, 0 };
        } else if (errno != EINTR) {
            return result;  // With nothing sent, Chromium sends it all again later, and it's split afresh.
        }
    }
    return (DPSendResult){ (ssize_t)length, 0 };
}

static DPSendResult DPSendto(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address,
                             socklen_t addressLength) {
    const uint8_t *data = buffer;
    // Every send in Dia comes through here, so this is checked first.
    if (!DPSplitting || address || length < 64 || (data[0] != 0x16 && data[0] != 0x14))
        return DPRealSendto(fd, buffer, length, flags, address, addressLength);
    uint8_t onStack[4096], *out = length + 5 <= sizeof onStack ? onStack : malloc(length + 5);
    size_t split = out ? DPSplitHello(data, length, out, arc4random()) : 0;
    int type = 0;
    socklen_t size = sizeof type;
    bool cut = split && getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &size) == 0 && type == SOCK_STREAM;
    DPSendResult result = cut ? DPSendAll(fd, out, split, flags) : DPRealSendto(fd, buffer, length, flags, address, addressLength);
    int error = errno;
    if (out != onStack) free(out);
    errno = error;
    if (!cut || result.sent < 0) return result;
    static atomic_flag logged;
    if (!atomic_flag_test_and_set(&logged)) NSLog(@"DiaPatches: Split TLS ClientHello is splitting ClientHellos");
    return (DPSendResult){ (ssize_t)length, 0 };
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *replacee; } DPInterposeSendto = {
    (const void *)DPSendto, (const void *)sendto
};

void DPInstallSplitSend(void) {
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    long version = v.majorVersion * 10000 + v.minorVersion * 100 + v.patchVersion;
    gCheckSecondary = version >= 130300 && version < 260100;
}

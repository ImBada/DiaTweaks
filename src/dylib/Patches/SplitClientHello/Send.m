#import "SplitClientHello.h"
#import "Write.h"

_Atomic bool DPSplitting;
static _Atomic bool gCheckSecondary;

extern DPSendResult DPRealSendto(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address,
                                 socklen_t addressLength) __asm__("_sendto");

__attribute__((noinline)) static DPSendResult DPSendHello(int fd, const void *buffer, size_t length, int flags) {
    DPSendResult result;
    if (!DPSendSplit(fd, buffer, length, flags, arc4random(), DPRealSendto, atomic_load_explicit(&gCheckSecondary, memory_order_relaxed), &result))
        return DPRealSendto(fd, buffer, length, flags, NULL, 0);
    static atomic_flag logged = ATOMIC_FLAG_INIT;
    if (result.sent >= 0 && !atomic_flag_test_and_set(&logged)) NSLog(@"DiaPatches: Split TLS ClientHello is splitting ClientHellos");
    return result;
}

static DPSendResult DPSendto(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address,
                             socklen_t addressLength) {
    const uint8_t *data = buffer;
    if (atomic_load_explicit(&DPSplitting, memory_order_acquire) && !address && data && length >= 64 && (data[0] == 0x16 || data[0] == 0x14))
        return DPSendHello(fd, buffer, length, flags);
    return DPRealSendto(fd, buffer, length, flags, address, addressLength);
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *replacee; } DPInterposeSendto = {
    (const void *)DPSendto, (const void *)sendto
};

void DPInstallSplitSend(void) {
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    long version = v.majorVersion * 10000 + v.minorVersion * 100 + v.patchVersion;
    atomic_store_explicit(&gCheckSecondary, version >= 130300 && version < 260100, memory_order_relaxed);
}

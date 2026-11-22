#import "AgentWriter.h"
#include <unistd.h>

static BOOL DPWriteAgent(int fd, const void *data, size_t size) {
    const char *bytes = data;
    while (size) {
        ssize_t wrote = write(fd, bytes, size);
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) return NO;
        size -= wrote;
        bytes += wrote;
    }
    return YES;
}

@implementation DPAgentWriter {
    NSLock *_lock;
    int _fd;
}
- (instancetype)initWithFD:(int)fd {
    if ((self = [super init])) {
        _fd = fd;
        _lock = [NSLock new];
    }
    return self;
}
- (BOOL)write:(const void *)bytes length:(size_t)length {
    [_lock lock];
    BOOL success = _fd >= 0 && (!length || DPWriteAgent(_fd, bytes, length));
    [_lock unlock];
    return success;
}
- (void)invalidate {
    [_lock lock];
    _fd = -1;
    [_lock unlock];
}
@end

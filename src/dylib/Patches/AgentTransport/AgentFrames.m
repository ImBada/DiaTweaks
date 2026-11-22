#import "AgentSocket.h"
#import "AgentWriter.h"
#include <sys/socket.h>

// A frame this long isn't buffered for a filter: it goes through as Dia sent it.
NSUInteger DPAgentFrameLimit = 64 * 1024 * 1024;

static NSData *DPFilterFrame(NSArray *filters, NSData *frame, DPAgentReply reply) {
    NSData *output = [frame copy];
    for (DPAgentFilter filter in filters) {
        NSData *next;
        @try { next = filter(output, reply); } @catch (NSException *exception) { return frame; }
        if (!(output = next)) return nil;
    }
    return output;
}

// Frames are decided at their first byte, so a filter that comes or goes mid-stream never sees half a frame.
// With none registered for this direction a frame is forwarded as it arrives, with no buffering.
static void DPForwardAgent(int source, DPAgentWriter *destination, DPAgentWriter *sender, BOOL requests) {
    NSMutableData *line = [NSMutableData new];
    DPAgentReply reply = ^(NSDictionary *message) {
        if (![NSJSONSerialization isValidJSONObject:message]) return;
        NSMutableData *frame = [[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] mutableCopy];
        if (!frame) return;
        [frame appendBytes:"\n" length:1];
        [sender write:frame.bytes length:frame.length];
    };
    NSArray *filters = nil;
    BOOL inFrame = NO, passing = NO;
    char bytes[32768];
    for (;;) @autoreleasepool {
        ssize_t got = read(source, bytes, sizeof bytes);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) break;
        for (const char *part = bytes, *end = bytes + got; part < end;) {
            const char *newline = memchr(part, '\n', end - part);
            const char *stop = newline ? newline + 1 : end;
            if (!inFrame) {
                inFrame = YES;
                filters = DPAgentFilterCount(requests) ? DPAgentFilters(requests) : @[];
                passing = !filters.count;
            }
            if (!passing && line.length + (NSUInteger)(stop - part) > DPAgentFrameLimit) {
                if (line.length && ![destination write:line.bytes length:line.length]) return;
                line = [NSMutableData new];
                passing = YES;
            }
            if (passing) {
                if (![destination write:part length:stop - part]) return;
            } else {
                [line appendBytes:part length:newline ? newline - part : stop - part];
                if (newline) {
                    NSData *output = DPFilterFrame(filters, line, reply);
                    if (output) {
                        NSMutableData *frame = [output mutableCopy];
                        [frame appendBytes:"\n" length:1];
                        if (![destination write:frame.bytes length:frame.length]) return;
                    }
                }
            }
            if (newline) {
                inFrame = NO;
                if (line.length) line = [NSMutableData new];
            }
            part = stop;
        }
    }
    // An unfinished frame at the end of the stream is delivered rather than lost.
    if (inFrame && !passing && line.length) [destination write:line.bytes length:line.length];
}

void DPRelayAgentConnection(int client, int backend) {
    DPAgentWriter *toClient = [[DPAgentWriter alloc] initWithFD:client];
    DPAgentWriter *toAgent = [[DPAgentWriter alloc] initWithFD:backend];
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DPForwardAgent(backend, toClient, toAgent, NO);
        shutdown(client, SHUT_RDWR);
        shutdown(backend, SHUT_RDWR);
    });
    DPForwardAgent(client, toAgent, toClient, YES);
    shutdown(client, SHUT_RDWR);
    shutdown(backend, SHUT_RDWR);
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [toClient invalidate];
    [toAgent invalidate];
}

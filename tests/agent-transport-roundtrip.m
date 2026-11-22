#import "agent-transport.h"
#import "Patches/AgentTransport/AgentRelay.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

NSTask *DPTestAgentTaskNamed(NSString *path, NSString *name) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"AGENT_SERVER_SOCKET_PATH"] = [NSString stringWithFormat:@"/tmp/dia-agent.server.%@.sock", name];
    environment[@"KEEP"] = @"preserved";
    task.environment = environment;
#ifdef CONFIGURED_AGENT
    task.arguments = @[ @"--agents-dir", @"original" ];
#endif
    return task;
}

NSTask *DPTestAgentTask(NSString *path) {
    return DPTestAgentTaskNamed(path, [NSString stringWithFormat:@"%d.test", getpid()]);
}

void DPTestAgentRoundtrip(NSString *path, BOOL enabled) {
    DPTestAgentRoundtripNamed(path, [NSString stringWithFormat:@"%d.test", getpid()], enabled);
}

void DPTestAgentRoundtripNamed(NSString *path, NSString *name, BOOL enabled) {
    atomic_store(&DPTestConnected, false);
    NSTask *task = DPTestAgentTaskNamed(path, name);
    NSString *socketPath = task.environment[@"AGENT_SERVER_SOCKET_PATH"];
    NSDictionary *before = task.environment;
    NSError *error = nil;
    NSCAssert([task launchAndReturnError:&error], @"launch failed: %@", error);
    NSCAssert(DPAgentServerRunning(), @"the launched agent isn't found among Dia's children");
    NSCAssert(DPAgentRelayRunning() == enabled, @"an agent is reported as relayed only when it is");
    NSString *after = task.environment[@"AGENT_SERVER_SOCKET_PATH"];
    NSCAssert(enabled ? ![socketPath isEqual:after] : [socketPath isEqual:after], @"wrong process routing");
    int fd = -1;
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    strlcpy(address.sun_path, socketPath.fileSystemRepresentation, sizeof address.sun_path);
    for (int attempt = 0; attempt < 200; attempt++) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (!connect(fd, (struct sockaddr *)&address, SUN_LEN(&address))) break;
        close(fd);
        fd = -1;
        usleep(25000);
    }
    NSCAssert(fd >= 0, @"connection failed");
    struct timeval timeout = { .tv_sec = 5 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    NSCAssert(write(fd, "ori", 3) == 3, @"first fragment failed");
    usleep(10000);
    NSCAssert(write(fd, "ginal\n", 6) == 6, @"second fragment failed");
    char buffer[40] = {0};
    size_t length = 0;
    while (length < sizeof buffer && (!length || buffer[length - 1] != '\n')) {
        ssize_t readCount = read(fd, buffer + length, sizeof buffer - length);
        if (readCount < 0 && errno == EINTR) continue;
        NSCAssert(readCount > 0, @"response timed out or closed");
        length += readCount;
    }
    NSString *actual = [[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding];
    NSCAssert([actual isEqual:enabled ? @"selected\n" : @"original\n"], @"roundtrip failed: %@", actual);
    NSCAssert(atomic_load(&DPTestConnected) == enabled, @"connection callback must match routed connections");
    close(fd);
    [task waitUntilExit];
    NSCAssert(task.terminationStatus == 0, @"agent failed: %d", task.terminationStatus);
    NSCAssert([before[@"KEEP"] isEqual:task.environment[@"KEEP"]], @"environment lost");
    for (int attempt = 0; attempt < 100 && [NSFileManager.defaultManager fileExistsAtPath:socketPath]; attempt++) usleep(25000);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:socketPath], @"socket not cleaned");
    for (int attempt = 0; attempt < 200 && (DPAgentRelayRunning() || DPAgentServerRunning()); attempt++) usleep(25000);
    NSCAssert(!DPAgentRelayRunning() && !DPAgentServerRunning(), @"the relay must end with its agent");
}

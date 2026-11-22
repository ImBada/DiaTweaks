#import "StdPatch/StdPatch.h"
#import "AgentRelay.h"
#import "AgentSocket.h"
#include <sys/socket.h>
#include <sys/stat.h>

static NSString *DPSocketPath(NSDictionary *environment) {
    NSString *path = environment[@"AGENT_SERVER_SOCKET_PATH"];
    NSString *prefix = @"/tmp/dia-agent.server.";
    if (![path isKindOfClass:NSString.class] || ![path hasPrefix:prefix] || ![path hasSuffix:@".sock"] ||
        strlen(path.fileSystemRepresentation) >= sizeof(((struct sockaddr_un *)0)->sun_path)) return nil;
    // Dia names the socket after the profile, and a profile name can hold spaces and other punctuation
    // ("Profile 2"), so only a path separator would let the name leave /tmp.
    NSString *name = [path substringFromIndex:prefix.length];
    return [name rangeOfString:@"/"].location == NSNotFound ? path : nil;
}

static BOOL DPAgentTask_launchAndReturnError(NSTask *self, SEL _cmd, NSError **error) {
    NSString *agent = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"agent-server-resources/dist/agent-server"];
    if (!DPAgentFiltersActive() || ![self.executableURL.path.stringByStandardizingPath isEqual:agent.stringByStandardizingPath])
        return DPCallOriginal(DPAgentTask_launchAndReturnError, self, error);
    NSDictionary *original = self.environment;
    NSDictionary *environment = original ?: NSProcessInfo.processInfo.environment;
    NSString *socket = DPSocketPath(environment);
    if (!socket) return DPCallOriginal(DPAgentTask_launchAndReturnError, self, error);
    char directory[] = "/tmp/diatweaks-agent.XXXXXX";
    if (!mkdtemp(directory)) return DPCallOriginal(DPAgentTask_launchAndReturnError, self, error);

    int listener = DPAgentSocket();
    struct sockaddr_un address = DPAgentAddress(socket.fileSystemRepresentation);
    BOOL bound = listener >= 0 && !bind(listener, (struct sockaddr *)&address, SUN_LEN(&address));
    if (!bound || chmod(socket.fileSystemRepresentation, 0600) || listen(listener, 16)) {
        if (bound) unlink(socket.fileSystemRepresentation);
        if (listener >= 0) close(listener);
        rmdir(directory);
        return DPCallOriginal(DPAgentTask_launchAndReturnError, self, error);
    }
    NSMutableDictionary *modified = [environment mutableCopy];
    NSDictionary *extra = DPAgentEnvironmentChanges(@(directory), environment);
    [modified addEntriesFromDictionary:extra ?: @{}];
    NSArray *arguments = self.arguments ?: @[];
    if (extra[@"AGENTS_DIR"]) {
        NSMutableArray *changed = [arguments mutableCopy];
        for (NSUInteger i = 0; i + 1 < changed.count; i++)
            if ([changed[i] isEqual:@"--agents-dir"]) changed[i + 1] = extra[@"AGENTS_DIR"];
        self.arguments = changed;
    }
    DPAgentConnected connected = DPAgentConnectedHandler();
    modified[@"AGENT_SERVER_SOCKET_PATH"] = [@(directory) stringByAppendingPathComponent:@"agent.sock"];
    BOOL launched = NO;
    @try {
        self.environment = modified;
        launched = DPCallOriginal(DPAgentTask_launchAndReturnError, self, error);
        if (launched) DPRelayChatAgent(listener, socket, @(directory), self.processIdentifier, connected);
        return launched;
    } @finally {
        if (!launched) {
            self.environment = original;
            self.arguments = arguments;
            unlink(socket.fileSystemRepresentation);
            close(listener);
            [NSFileManager.defaultManager removeItemAtPath:@(directory) error:nil];
        }
    }
}

static Class DPTaskClass;

void DPInstallAgentTransport(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DPTaskClass = [NSTask new].class;
        DPHookClass(DPTaskClass, @selector(launchAndReturnError:), (IMP)DPAgentTask_launchAndReturnError);
    });
}

BOOL DPAgentTransportInstalled(void) {
    return DPIsHooked(DPTaskClass, @selector(launchAndReturnError:), (IMP)DPAgentTask_launchAndReturnError);
}

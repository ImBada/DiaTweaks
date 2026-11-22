#import "agent-transport.h"
#import "Patches/AgentTransport/AgentRelay.h"
#include <sys/stat.h>

atomic_bool DPTestConnected;

int main(void) { @autoreleasepool {
    NSString *agent = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"agent-server-resources/dist/agent-server"];
#ifdef CONFIGURED_AGENT
    DPSetAgentEnvironment(^NSDictionary *(NSString *directory, NSDictionary *original) {
        return @{ @"AGENTS_DIR": @"/synthetic/agents" };
    });
#endif
    DPSetAgentConnected(^(NSString *directory) { atomic_store(&DPTestConnected, true); });
    DPSetAgentFilters(@"test", ^NSData *(NSData *line, DPAgentReply reply) {
        return [@"selected" dataUsingEncoding:NSUTF8StringEncoding];
    }, nil);
    DPTestAgentRoundtrip(agent, YES);
    // Dia names the socket after the profile, and a profile name can hold spaces ("Profile 2").
    DPTestAgentRoundtripNamed(agent, [NSString stringWithFormat:@"%d.Profile 2", getpid()], YES);
    DPSetAgentFilters(@"test", nil, nil);
#ifndef CONFIGURED_AGENT
    DPTestAgentRoundtrip(agent, NO);
#endif
    DPSetAgentFilters(@"test", ^NSData *(NSData *line, DPAgentReply reply) { return line; }, nil);
    NSTask *unrelated = DPTestAgentTask(@"/usr/bin/true");
    NSDictionary *original = unrelated.environment;
    NSCAssert([unrelated launchAndReturnError:nil], @"unrelated launch failed");
    [unrelated waitUntilExit];
    NSCAssert([original isEqual:unrelated.environment], @"unrelated launch changed");

    chmod(agent.fileSystemRepresentation, 0600);
    NSTask *failure = DPTestAgentTask(agent);
    original = failure.environment;
    NSArray *arguments = failure.arguments ?: @[];
    NSError *error = nil;
    NSCAssert(![failure launchAndReturnError:&error] && error, @"expected launch failure");
    NSCAssert([failure.environment isEqual:original], @"failed launch didn't restore environment");
    NSCAssert([failure.arguments isEqual:arguments], @"failed launch didn't restore arguments");
    chmod(agent.fileSystemRepresentation, 0700);
    NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:original[@"AGENT_SERVER_SOCKET_PATH"]], @"failed launch leaked socket");
    puts("PASS: agent routing, fragmented frames, connection hooks, inactive pass-through, unrelated tasks and failed-launch cleanup");
}}

#import "AgentRelay.h"
#import "AgentSocket.h"
#include <stdatomic.h>

static NSMutableDictionary<NSString *, NSArray *> *DPRules;
static _Atomic NSUInteger DPRequestFilters, DPResponseFilters;

static NSObject *AgentFiltersLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

// The launch hook goes in only once a filter exists, so a tweak that was never on leaves NSTask alone.
void DPSetAgentFilters(NSString *key, DPAgentFilter requests, DPAgentFilter responses) {
    if (!key || (!requests && !responses && !DPAgentFiltersActive())) return;
    if (requests || responses) DPInstallAgentTransport();
    @synchronized (AgentFiltersLock()) {
        DPRules = DPRules ?: [NSMutableDictionary new];
        if (requests || responses) DPRules[key] = @[ [requests copy] ?: NSNull.null, [responses copy] ?: NSNull.null ];
        else [DPRules removeObjectForKey:key];
        NSUInteger requestCount = 0, responseCount = 0;
        for (NSArray *rule in DPRules.allValues) {
            requestCount += rule[0] != NSNull.null;
            responseCount += rule[1] != NSNull.null;
        }
        atomic_store(&DPRequestFilters, requestCount);
        atomic_store(&DPResponseFilters, responseCount);
    }
}

NSUInteger DPAgentFilterCount(BOOL requests) {
    return atomic_load(requests ? &DPRequestFilters : &DPResponseFilters);
}

BOOL DPAgentFiltersActive(void) {
    return DPAgentFilterCount(YES) + DPAgentFilterCount(NO) != 0;
}

NSArray *DPAgentFilters(BOOL requests) {
    if (!DPAgentFilterCount(requests)) return @[];
    @synchronized (AgentFiltersLock()) {
        NSMutableArray *filters = [NSMutableArray new];
        for (NSString *key in [DPRules.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            id filter = DPRules[key][requests ? 0 : 1];
            if (filter != NSNull.null) [filters addObject:filter];
        }
        return filters;
    }
}

static DPAgentEnvironment DPEnvironment;
static DPAgentConnected DPConnected;

void DPSetAgentEnvironment(DPAgentEnvironment configure) {
    @synchronized (AgentFiltersLock()) { DPEnvironment = [configure copy]; }
}

void DPSetAgentConnected(DPAgentConnected connected) {
    @synchronized (AgentFiltersLock()) { DPConnected = [connected copy]; }
}

NSDictionary<NSString *, NSString *> *DPAgentEnvironmentChanges(NSString *directory, NSDictionary<NSString *, NSString *> *original) {
    DPAgentEnvironment configure;
    @synchronized (AgentFiltersLock()) { configure = DPEnvironment; }
    return configure ? configure(directory, original) : nil;
}

DPAgentConnected DPAgentConnectedHandler(void) {
    @synchronized (AgentFiltersLock()) { return DPConnected; }
}

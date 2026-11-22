#import "AgentRelay.h"
#include <sys/un.h>

int DPAgentSocket(void);
struct sockaddr_un DPAgentAddress(const char *path);
void DPRelayChatAgent(int listener, NSString *socket, NSString *directory, pid_t child, DPAgentConnected connected);

BOOL DPAgentFiltersActive(void);
NSUInteger DPAgentFilterCount(BOOL requests);
NSArray *DPAgentFilters(BOOL requests);

extern NSUInteger DPAgentFrameLimit;
void DPRelayAgentConnection(int client, int backend);
NSDictionary<NSString *, NSString *> *DPAgentEnvironmentChanges(NSString *directory, NSDictionary<NSString *, NSString *> *original);
DPAgentConnected DPAgentConnectedHandler(void);

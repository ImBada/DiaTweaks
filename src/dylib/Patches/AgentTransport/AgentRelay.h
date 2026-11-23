#import <Foundation/Foundation.h>

// A filter returns nil to consume a frame; `reply` sends a frame back to the peer and may be called after returning.
typedef void (^DPAgentReply)(NSDictionary *message);
typedef NSData * (^DPAgentFilter)(NSData *line, DPAgentReply reply);

void DPSetAgentFilters(NSString *key, DPAgentFilter requests, DPAgentFilter responses);

void DPInstallAgentTransport(void);
BOOL DPAgentTransportInstalled(void);

// An agent that started before the transport was installed is running without a relay.
BOOL DPAgentRelayRunning(void);
BOOL DPAgentServerRunning(void);

typedef NSDictionary<NSString *, NSString *> * (^DPAgentEnvironment)(NSString *directory, NSDictionary<NSString *, NSString *> *original);
typedef void (^DPAgentConnected)(NSString *directory);
void DPSetAgentEnvironment(DPAgentEnvironment configure);
void DPSetAgentConnected(DPAgentConnected connected);

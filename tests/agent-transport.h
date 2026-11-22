#import <Foundation/Foundation.h>
#include <stdatomic.h>

extern atomic_bool DPTestConnected;
NSTask *DPTestAgentTask(NSString *path);
NSTask *DPTestAgentTaskNamed(NSString *path, NSString *name);
void DPTestAgentRoundtrip(NSString *path, BOOL enabled);
void DPTestAgentRoundtripNamed(NSString *path, NSString *name, BOOL enabled);

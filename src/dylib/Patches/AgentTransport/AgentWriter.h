#import <Foundation/Foundation.h>

@interface DPAgentWriter : NSObject
- (instancetype)initWithFD:(int)fd;
- (BOOL)write:(const void *)bytes length:(size_t)length;
- (void)invalidate;
@end

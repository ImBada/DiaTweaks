#import <Foundation/Foundation.h>

// Spins the main run loop until the condition holds, so a slow runner can't end the wait before an animation or timer lands.
static inline void DPPumpUntil(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

// The main queue is FIFO, so once the sentinel runs, every block queued before it has run too, however long a slow runner stalls.
static inline void DPDrainMainQueue(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    DPPumpUntil(^BOOL { return drained; });
    [NSRunLoop.mainRunLoop runUntilDate:until];
}

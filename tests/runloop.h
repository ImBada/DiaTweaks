#import <Foundation/Foundation.h>

// Spins the main run loop until the condition holds, so a slow runner can't end the wait before an animation or timer lands.
// NO means the 30 seconds ran out first, so a caller can fail once instead of cascading.
static inline BOOL DPPumpUntil(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done();
}

// The main queue is FIFO, so once a sentinel runs, every block queued before it has run too, however long a slow runner stalls.
// The timed sentinel outlasts any dispatch_after or NSTimer of at most `seconds` set before the call, and its clock starts after the first drain so a stall can't spend it.
static inline void DPDrainMainQueue(NSTimeInterval seconds) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    DPPumpUntil(^BOOL { return drained; });
    if (seconds <= 0) return;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    __block BOOL timerDrained = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ timerDrained = YES; });
    });
    DPPumpUntil(^BOOL { return timerDrained && until.timeIntervalSinceNow <= 0; });
}

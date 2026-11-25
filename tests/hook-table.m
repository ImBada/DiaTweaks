#import "StdPatch/Hook.m"
#import <pthread.h>
#import <stdatomic.h>

@interface DPTarget : NSObject
- (int)work;
@end
@implementation DPTarget
- (int)work { return 1; }
@end

@interface DPBaseChain : NSObject
- (int)value;
- (int)recurse:(int)n;
@end
@implementation DPBaseChain
- (int)value { return 10; }
- (int)recurse:(int)n { return n <= 0 ? 0 : 1 + [self recurse:n - 1]; }
@end

@interface DPMidChain : DPBaseChain
@end
@implementation DPMidChain
- (int)value { return [super value] + 100; }
@end

@interface DPLeafChain : DPMidChain
@end
@implementation DPLeafChain
- (int)value { return [super value] + 1000; }
@end

@interface DPInheritedBase : NSObject
- (int)ping;
@end
@implementation DPInheritedBase
- (int)ping { return 5; }
@end

@interface DPInheritedSub : DPInheritedBase
@end
@implementation DPInheritedSub
@end

@interface DPOverrideSub : DPInheritedBase
@end
@implementation DPOverrideSub
- (int)ping { return 50; }
@end

@interface DPMultiTarget : NSObject
- (int)stack;
@end
@implementation DPMultiTarget
- (int)stack { return 1; }
@end

@interface DPDupBase : NSObject
- (int)step;
@end
@implementation DPDupBase
- (int)step { return 1; }
@end

@interface DPLateBase : NSObject
- (int)tick;
@end
@implementation DPLateBase
- (int)tick { return 1; }
@end

@interface DPLateSub : DPLateBase
@end
@implementation DPLateSub
@end

@interface DPDupSub : DPDupBase
@end
@implementation DPDupSub
@end

@interface DPDupGrand : DPDupSub
@end
@implementation DPDupGrand
@end

static int DPTarget_work(id self, SEL _cmd) { return DPCallOriginal(DPTarget_work, self) + 1; }
static int DPSub_work(id self, SEL _cmd) { return DPCallOriginal(DPSub_work, self) + 1; }
static int DPShared_value(id self, SEL _cmd) { return DPCallOriginal(DPShared_value, self) + 1; }
static int DPRecurse_hook(id self, SEL _cmd, int n) { return DPCallOriginal(DPRecurse_hook, self, n); }
static int DPPing_sub(id self, SEL _cmd) { return DPCallOriginal(DPPing_sub, self) * 2; }
static int DPPing_base(id self, SEL _cmd) { return DPCallOriginal(DPPing_base, self) + 3; }
static int DPMulti_h1(id self, SEL _cmd) { return DPCallOriginal(DPMulti_h1, self) * 10 + 1; }
static int DPMulti_h2(id self, SEL _cmd) { return DPCallOriginal(DPMulti_h2, self) * 10 + 2; }
static int DPMulti_h3(id self, SEL _cmd) { return DPCallOriginal(DPMulti_h3, self) * 10 + 3; }
static int DPMulti_h4(id self, SEL _cmd) { return DPCallOriginal(DPMulti_h4, self) * 10 + 4; }
static int DPDup_repA(id self, SEL _cmd) { return DPCallOriginal(DPDup_repA, self) + 10; }
static int DPDup_repB(id self, SEL _cmd) { return DPCallOriginal(DPDup_repB, self) * 3; }
static int DPDup_repC(id self, SEL _cmd) { return DPCallOriginal(DPDup_repC, self) + 100; }

static int DPLate_tick(id self, SEL _cmd) { return DPCallOriginal(DPLate_tick, self) + 5; }
static int DPLate_other(id self, SEL _cmd) { return DPCallOriginal(DPLate_other, self) + 9; }
static int DPFan_tick(id self, SEL _cmd) { return DPCallOriginal(DPFan_tick, self) + 7; }

static atomic_bool stop;
static atomic_long calls, wrong;
static DPTarget *target;

static void *reader(void *unused) {
    while (!atomic_load(&stop)) {
        if ([target work] != 2) atomic_fetch_add(&wrong, 1);
        atomic_fetch_add(&calls, 1);
    }
    return NULL;
}

static Class subclass(int index) {
    Class cls = objc_allocateClassPair(NSObject.class, [NSString stringWithFormat:@"DPHookTableSub%d", index].UTF8String, 0);
    class_addMethod(cls, @selector(work), imp_implementationWithBlock(^int(id self) { return 1; }), "i@:");
    objc_registerClassPair(cls);
    return cls;
}

static atomic_int nextWriterClass;
static void *writer(void *unused) {
    for (int i = 0; i < 40; i++) {
        int idNum = atomic_fetch_add(&nextWriterClass, 1);
        Class cls = subclass(10000 + idNum);
        DPHookClass(cls, @selector(work), (IMP)DPSub_work);
        id inst = [cls new];
        if ([inst work] != 2) atomic_fetch_add(&wrong, 1);
    }
    return NULL;
}

int main(void) {
    int failures = 0;
    @autoreleasepool {
        // Reverse-order subclass-then-superclass hooking with the same replacement must not recurse infinitely on [super].
        DPHookClass(DPLeafChain.class, @selector(value), (IMP)DPShared_value);
        DPHookClass(DPMidChain.class, @selector(value), (IMP)DPShared_value);
        DPHookClass(DPBaseChain.class, @selector(value), (IMP)DPShared_value);
        DPLeafChain *leaf = [DPLeafChain new];
        if ([leaf value] != 1113) { failures++; printf("FAIL reverse-order [super] chain returned %d, expected 1113\n", [leaf value]); }
        if ([[DPMidChain new] value] != 112) { failures++; printf("FAIL mid [super] chain returned wrong value\n"); }
        if ([[DPBaseChain new] value] != 11) { failures++; printf("FAIL base returned wrong value\n"); }

        DPHookClass(DPBaseChain.class, @selector(recurse:), (IMP)DPRecurse_hook);
        if ([[DPBaseChain new] recurse:5] != 5) { failures++; printf("FAIL recursive [self] hook failed\n"); }

        // Subclass (not overriding ping) hooked before superclass must still chain through superclass hook, and DPDiaIMP must unwind both.
        IMP realBasePing = class_getMethodImplementation(DPInheritedBase.class, @selector(ping));
        IMP realOverridePing = class_getMethodImplementation(DPOverrideSub.class, @selector(ping));
        DPHookClass(DPInheritedSub.class, @selector(ping), (IMP)DPPing_sub);
        DPHookClass(DPInheritedBase.class, @selector(ping), (IMP)DPPing_base);
        if ([[DPInheritedSub new] ping] != 16) { failures++; printf("FAIL subclass-before-superclass re-chain got %d, expected 16\n", [[DPInheritedSub new] ping]); }
        if (DPDiaIMP(DPInheritedSub.class, @selector(ping)) != realBasePing) { failures++; printf("FAIL DPDiaIMP(DPInheritedSub) did not unwind to base original IMP\n"); }
        if (DPDiaIMP(DPOverrideSub.class, @selector(ping)) != realOverridePing) { failures++; printf("FAIL DPDiaIMP(DPOverrideSub) did not return subclass's own IMP\n"); }

        IMP realStack = class_getMethodImplementation(DPMultiTarget.class, @selector(stack));
        DPHookClass(DPMultiTarget.class, @selector(stack), (IMP)DPMulti_h1);
        DPHookClass(DPMultiTarget.class, @selector(stack), (IMP)DPMulti_h2);
        DPHookClass(DPMultiTarget.class, @selector(stack), (IMP)DPMulti_h3);
        DPHookClass(DPMultiTarget.class, @selector(stack), (IMP)DPMulti_h4);
        int stacked = [[DPMultiTarget new] stack];
        if (stacked != 11234) { failures++; printf("FAIL 4-hook stack got %d, expected 11234\n", stacked); }
        if (DPDiaIMP(DPMultiTarget.class, @selector(stack)) != realStack) { failures++; printf("FAIL DPDiaIMP did not unwind 4 hooks\n"); }

        // Regression: subclass with repB -> repA -> base must not re-chain repA to repB when base is later hooked with repB.
        DPHookClass(DPDupSub.class, @selector(step), (IMP)DPDup_repA);
        DPHookClass(DPDupSub.class, @selector(step), (IMP)DPDup_repB);
        DPHookClass(DPDupGrand.class, @selector(step), (IMP)DPDup_repC);
        DPHookClass(DPDupBase.class, @selector(step), (IMP)DPDup_repB);
        int dupSubVal = [[DPDupSub new] step];
        int dupBaseVal = [[DPDupBase new] step];
        int dupGrandVal = [[DPDupGrand new] step];
        if (dupSubVal != 33) { failures++; printf("FAIL duplicate-replacement re-chain on DPDupSub got %d, expected 33\n", dupSubVal); }
        if (dupBaseVal != 3) { failures++; printf("FAIL duplicate-replacement base got %d, expected 3\n", dupBaseVal); }
        if (dupGrandVal != 133) { failures++; printf("FAIL duplicate-replacement grandchild got %d, expected 133\n", dupGrandVal); }

        // A miss is remembered per thread, so hooking afterwards has to drop it.
        if (DPFindOriginal(DPLateSub.class, @selector(tick), (IMP)DPLate_tick, NULL)) { failures++; printf("FAIL an unhooked class found an original\n"); }
        DPHookClass(DPLateBase.class, @selector(tick), (IMP)DPLate_tick);
        Class matched = Nil;
        IMP lateOriginal = DPFindOriginal(DPLateSub.class, @selector(tick), (IMP)DPLate_tick, &matched);
        if (!lateOriginal || matched != DPLateBase.class) { failures++; printf("FAIL a hook added after a miss was not found from its subclass\n"); }
        if ([[DPLateSub new] tick] != 6) { failures++; printf("FAIL inherited hook returned %d, expected 6\n", [[DPLateSub new] tick]); }

        size_t before = atomic_load(&DPHookCount);
        DPHookClass(DPLateBase.class, @selector(tick), (IMP)DPLate_tick);
        DPHookClass(DPLateSub.class, @selector(tick), (IMP)DPLate_tick);
        if (atomic_load(&DPHookCount) != before) { failures++; printf("FAIL hooking again added a record\n"); }

        Class fan[200];
        for (int i = 0; i < 200; i++) {
            fan[i] = subclass(20000 + i);
            DPHookClass(fan[i], @selector(work), (IMP)DPFan_tick);
        }
        for (int i = 0; i < 200; i++) {
            Class found = Nil;
            if (!DPFindOriginal(fan[i], @selector(work), (IMP)DPFan_tick, &found) || found != fan[i]) { failures++; printf("FAIL fan-out hook %d was not found at its own class\n", i); break; }
        }
        if (DPFindOriginal(DPTarget.class, @selector(work), (IMP)DPFan_tick, NULL)) { failures++; printf("FAIL a class outside the fan-out found one of its originals\n"); }

        __block BOOL sawMiss = NO, sawHit = NO;
        dispatch_semaphore_t missed = dispatch_semaphore_create(0), joined = dispatch_semaphore_create(0);
        dispatch_queue_t other = dispatch_queue_create("hook-table.memo", DISPATCH_QUEUE_SERIAL);
        dispatch_async(other, ^{
            sawMiss = !DPFindOriginal(DPLateSub.class, @selector(tick), (IMP)DPLate_other, NULL);
            dispatch_semaphore_signal(missed);
            dispatch_semaphore_wait(joined, DISPATCH_TIME_FOREVER);
            sawHit = DPFindOriginal(DPLateSub.class, @selector(tick), (IMP)DPLate_other, NULL) != NULL;
        });
        dispatch_semaphore_wait(missed, DISPATCH_TIME_FOREVER);
        DPHookClass(DPLateBase.class, @selector(tick), (IMP)DPLate_other);
        dispatch_semaphore_signal(joined);
        dispatch_sync(other, ^{});
        if (!sawMiss || !sawHit) { failures++; printf("FAIL another thread kept a stale miss (miss %d, hit %d)\n", sawMiss, sawHit); }
        if ([[DPLateSub new] tick] != 15) { failures++; printf("FAIL two hooks on an inherited method returned %d, expected 15\n", [[DPLateSub new] tick]); }

        target = [DPTarget new];
        DPHookClass(DPTarget.class, @selector(work), (IMP)DPTarget_work);
        pthread_t readers[4], writers[3];
        for (int i = 0; i < 4; i++) pthread_create(&readers[i], NULL, reader, NULL);
        for (int i = 0; i < 3; i++) pthread_create(&writers[i], NULL, writer, NULL);
        for (int i = 0; i < 3; i++) pthread_join(writers[i], NULL);
        while (!atomic_load(&calls)) usleep(100);

        id first = nil, last = nil;
        int hooked = 0;
        for (; hooked < 4000; hooked++) {
            last = [subclass(hooked) new];
            DPHookClass(object_getClass(last), @selector(work), (IMP)DPSub_work);
            if ([last work] != 2) break;
            first = first ?: last;
            if (DPOriginalIMP(last, @selector(work), (IMP)DPSub_work) == (IMP)DPSub_work) { failures++; printf("FAIL the original of a new hook is its replacement\n"); }
        }
        atomic_store(&stop, YES);
        for (int i = 0; i < 4; i++) pthread_join(readers[i], NULL);

        if (atomic_load(&wrong)) { failures++; printf("FAIL %ld of %ld calls on other threads missed their hook\n", atomic_load(&wrong), atomic_load(&calls)); }
        if (hooked < 500 || hooked >= 4000) { failures++; printf("FAIL the table took %d hooks, expected it to fill up in between\n", hooked); }
        if ([last work] != 1) { failures++; printf("FAIL a hook past the end of the table took effect\n"); }
        if ([target work] != 2 || [first work] != 2) { failures++; printf("FAIL the full table broke earlier hooks\n"); }
        printf("%d hooks, %ld calls from 4 threads while they were added\n", hooked + 1, atomic_load(&calls));
    }
    if (!failures) printf("all hook table checks passed\n");
    return failures ? 1 : 0;
}

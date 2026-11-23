#import "StdPatch/StdPatch.h"
#import <os/lock.h>
#import <stdatomic.h>

typedef struct { Class cls; SEL sel; IMP replacement; _Atomic(IMP) original; } DPHookRecord;
// Writers serialize on DPHookLock while any thread reads lock-free; the table never moves and a record counts only once whole.
static DPHookRecord DPHooks[1024];
static _Atomic size_t DPHookCount;
static os_unfair_lock DPHookLock = OS_UNFAIR_LOCK_INIT;
static _Thread_local DPHookFrame *DPActiveFrame;

static BOOL DPInherits(Class cls, Class ancestor) {
    for (Class c = cls; c; c = class_getSuperclass(c))
        if (c == ancestor) return YES;
    return NO;
}

void DPHookClass(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return;
    os_unfair_lock_lock(&DPHookLock);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return os_unfair_lock_unlock(&DPHookLock);
    IMP original = method_getImplementation(method);
    if (original == replacement) return os_unfair_lock_unlock(&DPHookLock);
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_relaxed);
    // Already hooked here or in a superclass: a second copy would double-run or recurse.
    for (size_t i = 0; i < count; i++)
        if (DPHooks[i].sel == sel && DPHooks[i].replacement == replacement && DPInherits(cls, DPHooks[i].cls)) return os_unfair_lock_unlock(&DPHookLock);
    if (count == sizeof DPHooks / sizeof *DPHooks) {
        os_unfair_lock_unlock(&DPHookLock);
        return NSLog(@"DiaPatches: hook table is full; not hooking -[%s %@]", class_getName(cls), NSStringFromSelector(sel));
    }
    // The record goes in first: once the replacement is live, any thread that reaches it must find it.
    DPHooks[count].cls = cls;
    DPHooks[count].sel = sel;
    DPHooks[count].replacement = replacement;
    atomic_store_explicit(&DPHooks[count].original, original, memory_order_relaxed);
    atomic_store_explicit(&DPHookCount, count + 1, memory_order_release);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(method, replacement);
    // Re-chain any subclass that copied cls's inherited IMP earlier so it still calls through this hook,
    // unless that subclass (or an intermediate below cls) already hooks the same replacement.
    for (size_t i = 0; i < count; i++) {
        Class sub = DPHooks[i].cls;
        if (DPHooks[i].sel != sel || DPHooks[i].replacement == replacement || sub == cls || !DPInherits(sub, cls)) continue;
        if (atomic_load_explicit(&DPHooks[i].original, memory_order_relaxed) != original) continue;
        BOOL hasReplacement = NO;
        for (size_t j = 0; j < count && !hasReplacement; j++)
            hasReplacement = DPHooks[j].sel == sel && DPHooks[j].replacement == replacement && DPInherits(sub, DPHooks[j].cls);
        if (!hasReplacement) atomic_store_explicit(&DPHooks[i].original, replacement, memory_order_release);
    }
    os_unfair_lock_unlock(&DPHookLock);
}

void DPHook(const char *className, SEL sel, IMP replacement) {
    Class cls = className ? objc_getClass(className) : Nil;
    if (!class_getInstanceMethod(cls, sel)) NSLog(@"DiaPatches: can't hook -[%s %@]; Dia may have renamed it", className ?: "(null)", NSStringFromSelector(sel));
    else DPHookClass(cls, sel, replacement);
}

static IMP DPFindOriginal(Class start, SEL sel, IMP replacement, Class *matched) {
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    IMP best = NULL;
    Class bestClass = Nil;
    size_t bestDepth = SIZE_MAX;
    for (size_t i = 0; i < count; i++) {
        if (DPHooks[i].replacement != replacement || DPHooks[i].sel != sel) continue;
        Class hooked = DPHooks[i].cls;
        if (hooked == start) {
            if (matched) *matched = hooked;
            return atomic_load_explicit(&DPHooks[i].original, memory_order_acquire);
        }
        size_t depth = 1;
        for (Class c = class_getSuperclass(start); c && depth < bestDepth; c = class_getSuperclass(c), depth++)
            if (c == hooked) {
                best = atomic_load_explicit(&DPHooks[i].original, memory_order_acquire);
                bestClass = hooked;
                bestDepth = depth;
                break;
            }
    }
    if (matched) *matched = bestClass;
    return best;
}

IMP DPOriginalIMP(id object, SEL sel, IMP replacement) {
    IMP imp = DPFindOriginal(object_getClass(object), sel, replacement, NULL);
    if (imp) return imp;
    abort();
}

IMP DPPushOriginalIMP(id object, SEL sel, IMP replacement, DPHookFrame *frame) {
    const void *target = (__bridge const void *)object;
    Class start = object_getClass(object), matched = Nil;
    IMP imp = NULL;
    // When a subclass hooked before its superclass calls [super sel], step above the active class instead of recursing.
    for (DPHookFrame *active = DPActiveFrame; active; active = active->previous) {
        if (active->object == target && active->sel == sel && active->replacement == replacement) {
            Class super = class_getSuperclass(active->cls);
            if (super) imp = DPFindOriginal(super, sel, replacement, &matched);
            break;
        }
    }
    if (!imp) imp = DPFindOriginal(start, sel, replacement, &matched);
    if (!imp) abort();
    *frame = (DPHookFrame){target, sel, replacement, matched, DPActiveFrame};
    DPActiveFrame = frame;
    return imp;
}

void DPPopOriginalIMP(DPHookFrame *frame) {
    DPActiveFrame = frame->previous;
}

BOOL DPIsHooked(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return NO;
    IMP current = class_getMethodImplementation(cls, sel);
    if (current == replacement) return YES;
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    for (size_t hops = 0; hops < count && current; hops++) {
        IMP next = DPFindOriginal(cls, sel, current, NULL);
        if (!next) break;
        if (next == replacement) return YES;
        current = next;
    }
    return NO;
}

IMP DPDiaIMP(Class cls, SEL sel) {
    if (!cls || !sel) return NULL;
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    IMP imp = NULL;
    for (Class c = cls; c && !imp; c = class_getSuperclass(c)) {
        for (size_t i = 0; i < count; i++)
            if (DPHooks[i].cls == c && DPHooks[i].sel == sel) {
                imp = atomic_load_explicit(&DPHooks[i].original, memory_order_acquire);
                break;
            }
        if (imp) break;
        Method own = class_getInstanceMethod(c, sel);
        Class super = class_getSuperclass(c);
        if (own && (!super || own != class_getInstanceMethod(super, sel)))
            return method_getImplementation(own);
    }
    if (!imp) return class_getMethodImplementation(cls, sel);
    for (size_t hops = 0; hops < count; hops++) {
        IMP next = NULL;
        for (size_t i = 0; i < count && !next; i++)
            if (DPHooks[i].sel == sel && DPHooks[i].replacement == imp && DPInherits(cls, DPHooks[i].cls))
                next = atomic_load_explicit(&DPHooks[i].original, memory_order_acquire);
        if (!next) break;
        imp = next;
    }
    return imp;
}
